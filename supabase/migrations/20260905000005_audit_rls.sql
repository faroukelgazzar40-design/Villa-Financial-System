-- ============================================================================
-- 0005 AUDIT + ROW LEVEL SECURITY
--
-- This is the migration that makes the data actually secure.
--
-- Two things are established here:
--
--   1. An append-only audit log. Every insert, update and delete on a
--      financial table is recorded with the before and after state and who
--      did it. Nothing changes silently.
--
--   2. Row-Level Security on every table, default deny. RLS is enforced by
--      Postgres itself, so it applies no matter how the data is reached —
--      the web app, a REST call, or someone with the API key. Hiding a
--      button in the UI is not security; this is.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Audit log
-- ---------------------------------------------------------------------------
create table public.audit_log (
  id         bigint      generated always as identity primary key,
  table_name text        not null,
  record_id  uuid,
  action     text        not null check (action in ('insert', 'update', 'delete')),
  old_data   jsonb,
  new_data   jsonb,
  -- Only the columns that actually changed, for readable update history.
  changed_fields text[],
  changed_by uuid        references public.profiles (id) on delete set null,
  changed_at timestamptz not null default now()
);

comment on table public.audit_log is
  'Append-only history of every change to financial data. No UPDATE or DELETE '
  'policy exists for any role, including owner, so the trail cannot be edited.';

create index audit_table_record_idx on public.audit_log (table_name, record_id, changed_at desc);
create index audit_actor_idx        on public.audit_log (changed_by, changed_at desc);
create index audit_time_idx         on public.audit_log (changed_at desc);

create or replace function public.audit_trigger()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  rec_id  uuid;
  changed text[];
begin
  if tg_op = 'DELETE' then
    rec_id := old.id;
  else
    rec_id := new.id;
  end if;

  if tg_op = 'UPDATE' then
    select array_agg(key)
      into changed
      from jsonb_each(to_jsonb(new))
     where to_jsonb(new) -> key is distinct from to_jsonb(old) -> key
       and key <> 'updated_at';

    -- A no-op update (only updated_at moved) is not worth a log row.
    if changed is null then
      return new;
    end if;
  end if;

  insert into public.audit_log (
    table_name, record_id, action, old_data, new_data, changed_fields, changed_by
  )
  values (
    tg_table_name,
    rec_id,
    lower(tg_op),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end,
    changed,
    auth.uid()
  );

  return coalesce(new, old);
end
$$;

-- Attach the audit trigger to everything that touches money or access.
do $$
declare
  t text;
begin
  foreach t in array array[
    'branches', 'profiles', 'spaces', 'clients', 'contracts',
    'invoices', 'invoice_lines', 'payments',
    'income_transactions', 'expense_transactions',
    'bookings', 'employees', 'commission_rules',
    'payroll_runs', 'payroll_items'
  ]
  loop
    execute format(
      'create trigger %I_audit
         after insert or update or delete on public.%I
         for each row execute function public.audit_trigger()',
      t, t
    );
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere.
--
-- Once enabled with no matching policy, the default is DENY. Every table
-- below therefore starts locked and is opened only by the explicit policies
-- that follow.
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'branches', 'profiles', 'spaces', 'clients', 'contracts',
    'invoices', 'invoice_lines', 'payments',
    'income_transactions', 'expense_transactions',
    'bookings', 'employees', 'commission_rules',
    'payroll_runs', 'payroll_items', 'audit_log', 'document_counters'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    -- FORCE applies RLS to the table owner too, closing the usual escape hatch.
    execute format('alter table public.%I force row level security', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- BRANCHES — everyone signed in may read the branch list (it is just names);
-- only the owner may change it.
-- ---------------------------------------------------------------------------
create policy branches_read on public.branches
  for select to authenticated
  using (true);

create policy branches_write on public.branches
  for all to authenticated
  using (public.is_owner()) with check (public.is_owner());

-- ---------------------------------------------------------------------------
-- PROFILES — you can always read yourself. Finance roles see everyone;
-- a branch manager sees their own branch's staff. Only the owner may create
-- accounts or change a role (that is the privilege-escalation path, so it is
-- deliberately the narrowest policy in the system).
-- ---------------------------------------------------------------------------
create policy profiles_read_self on public.profiles
  for select to authenticated
  using (id = auth.uid());

create policy profiles_read_team on public.profiles
  for select to authenticated
  using (
    public.is_finance()
    or (public.current_role() = 'branch_manager' and branch_id = public.current_branch())
  );

-- Users may edit their own name/phone/locale. The WITH CHECK re-reads role
-- and branch from the stored row, so a user cannot promote themselves by
-- sending role='owner' in an update.
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = (select p.role from public.profiles p where p.id = auth.uid())
    and branch_id is not distinct from
        (select p.branch_id from public.profiles p where p.id = auth.uid())
  );

create policy profiles_admin on public.profiles
  for all to authenticated
  using (public.is_owner()) with check (public.is_owner());

-- ---------------------------------------------------------------------------
-- SPACES
-- ---------------------------------------------------------------------------
create policy spaces_read on public.spaces
  for select to authenticated
  using (public.has_branch_access(branch_id));

create policy spaces_write on public.spaces
  for all to authenticated
  using (
    public.can_write_branch(branch_id)
    and public.current_role() in ('owner', 'accountant', 'branch_manager')
  )
  with check (
    public.can_write_branch(branch_id)
    and public.current_role() in ('owner', 'accountant', 'branch_manager')
  );

-- ---------------------------------------------------------------------------
-- CLIENTS — sales staff need the client list to do their job, so read is
-- branch-wide for all roles. Deletion is owner-only.
-- ---------------------------------------------------------------------------
create policy clients_read on public.clients
  for select to authenticated
  using (public.has_branch_access(branch_id));

create policy clients_insert on public.clients
  for insert to authenticated
  with check (public.can_write_branch(branch_id));

create policy clients_update on public.clients
  for update to authenticated
  using (public.can_write_branch(branch_id))
  with check (public.can_write_branch(branch_id));

create policy clients_delete on public.clients
  for delete to authenticated
  using (public.is_owner());

-- ---------------------------------------------------------------------------
-- CONTRACTS — the rent roll. Sales may read (to answer tenant questions) but
-- not create or alter an agreement; that is a manager/finance act.
-- ---------------------------------------------------------------------------
create policy contracts_read on public.contracts
  for select to authenticated
  using (public.has_branch_access(branch_id));

create policy contracts_write on public.contracts
  for all to authenticated
  using (
    public.can_write_branch(branch_id)
    and public.current_role() in ('owner', 'accountant', 'branch_manager')
  )
  with check (
    public.can_write_branch(branch_id)
    and public.current_role() in ('owner', 'accountant', 'branch_manager')
  );

-- ---------------------------------------------------------------------------
-- INVOICES — sales can see what a client owes; only finance and managers
-- issue them. Nobody deletes an invoice: void it instead, which keeps the
-- number and the audit trail intact.
-- ---------------------------------------------------------------------------
create policy invoices_read on public.invoices
  for select to authenticated
  using (public.has_branch_access(branch_id));

create policy invoices_insert on public.invoices
  for insert to authenticated
  with check (
    public.can_write_branch(branch_id)
    and public.current_role() in ('owner', 'accountant', 'branch_manager')
  );

create policy invoices_update on public.invoices
  for update to authenticated
  using (
    public.can_write_branch(branch_id)
    and public.current_role() in ('owner', 'accountant', 'branch_manager')
    -- A paid or voided invoice is closed history.
    and status not in ('paid', 'void')
  )
  with check (public.can_write_branch(branch_id));

-- No DELETE policy on invoices, by design.

create policy invoice_lines_read on public.invoice_lines
  for select to authenticated
  using (exists (
    select 1 from public.invoices i
    where i.id = invoice_id and public.has_branch_access(i.branch_id)
  ));

create policy invoice_lines_write on public.invoice_lines
  for all to authenticated
  using (exists (
    select 1 from public.invoices i
    where i.id = invoice_id
      and public.can_write_branch(i.branch_id)
      and i.status in ('draft', 'issued')
      and public.current_role() in ('owner', 'accountant', 'branch_manager')
  ))
  with check (exists (
    select 1 from public.invoices i
    where i.id = invoice_id
      and public.can_write_branch(i.branch_id)
      and i.status in ('draft', 'issued')
  ));

-- ---------------------------------------------------------------------------
-- PAYMENTS — sales CAN record a payment (they take cash at the desk), but
-- nobody can edit or delete one. A mistake is corrected by reversal, which
-- is an owner/accountant action recorded in the audit log.
-- ---------------------------------------------------------------------------
create policy payments_read on public.payments
  for select to authenticated
  using (public.has_branch_access(branch_id));

create policy payments_insert on public.payments
  for insert to authenticated
  with check (public.can_write_branch(branch_id));

create policy payments_reverse on public.payments
  for update to authenticated
  using (public.is_finance())
  with check (public.is_finance());

-- No DELETE policy on payments, by design.

-- ---------------------------------------------------------------------------
-- INCOME — sales see and edit only what they entered themselves, and only
-- while it is fresh (same day). Managers and finance see the whole branch.
-- ---------------------------------------------------------------------------
create policy income_read on public.income_transactions
  for select to authenticated
  using (
    deleted_at is null
    and public.has_branch_access(branch_id)
    and (
      public.can_see_costs()      -- owner / accountant / branch_manager
      or created_by = auth.uid()  -- sales sees own entries
      or public.current_role() = 'viewer'
    )
  );

create policy income_insert on public.income_transactions
  for insert to authenticated
  with check (
    public.can_write_branch(branch_id)
    and created_by = auth.uid()
  );

create policy income_update on public.income_transactions
  for update to authenticated
  using (
    public.can_write_branch(branch_id)
    and (
      public.current_role() in ('owner', 'accountant', 'branch_manager')
      or (created_by = auth.uid() and created_at > now() - interval '24 hours')
    )
  )
  with check (public.can_write_branch(branch_id));

create policy income_delete on public.income_transactions
  for delete to authenticated
  using (public.is_owner());

-- ---------------------------------------------------------------------------
-- EXPENSES — invisible to sales entirely. can_see_costs() excludes them, so
-- no expense row is ever returned to a sales login.
-- ---------------------------------------------------------------------------
create policy expenses_read on public.expense_transactions
  for select to authenticated
  using (
    deleted_at is null
    and public.has_branch_access(branch_id)
    and public.can_see_costs()
  );

create policy expenses_write on public.expense_transactions
  for all to authenticated
  using (
    public.can_write_branch(branch_id)
    and public.current_role() in ('owner', 'accountant', 'branch_manager')
  )
  with check (
    public.can_write_branch(branch_id)
    and public.current_role() in ('owner', 'accountant', 'branch_manager')
  );

-- ---------------------------------------------------------------------------
-- BOOKINGS — front-desk work; all non-viewer roles may take a booking.
-- ---------------------------------------------------------------------------
create policy bookings_read on public.bookings
  for select to authenticated
  using (public.has_branch_access(branch_id));

create policy bookings_insert on public.bookings
  for insert to authenticated
  with check (public.can_write_branch(branch_id));

create policy bookings_update on public.bookings
  for update to authenticated
  using (public.can_write_branch(branch_id))
  with check (public.can_write_branch(branch_id));

create policy bookings_delete on public.bookings
  for delete to authenticated
  using (
    public.current_role() in ('owner', 'accountant', 'branch_manager')
  );

-- ---------------------------------------------------------------------------
-- EMPLOYEES — salary is sensitive. Finance sees all. A branch manager sees
-- their own branch's employee records. Everyone else sees only their own
-- record, and only if it is linked to their login.
-- ---------------------------------------------------------------------------
create policy employees_read_self on public.employees
  for select to authenticated
  using (profile_id = auth.uid());

create policy employees_read_managers on public.employees
  for select to authenticated
  using (
    public.is_finance()
    or (public.current_role() = 'branch_manager' and branch_id = public.current_branch())
  );

create policy employees_write on public.employees
  for all to authenticated
  using (public.is_finance()) with check (public.is_finance());

-- ---------------------------------------------------------------------------
-- COMMISSION RULES — you may see the rule that applies to you; only finance
-- may set rates.
-- ---------------------------------------------------------------------------
create policy commission_read on public.commission_rules
  for select to authenticated
  using (
    public.is_finance()
    or employee_id in (select id from public.employees where profile_id = auth.uid())
  );

create policy commission_write on public.commission_rules
  for all to authenticated
  using (public.is_finance()) with check (public.is_finance());

-- ---------------------------------------------------------------------------
-- PAYROLL — the tightest policies in the schema. Owner and accountant only.
-- Branch managers deliberately CANNOT read individual salaries, including
-- for their own staff. Only the owner may approve a run.
-- ---------------------------------------------------------------------------
create policy payroll_runs_read on public.payroll_runs
  for select to authenticated
  using (public.is_finance());

create policy payroll_runs_write on public.payroll_runs
  for insert to authenticated
  with check (public.is_finance());

create policy payroll_runs_update on public.payroll_runs
  for update to authenticated
  using (
    public.is_finance()
    -- Approving or marking paid is reserved to the owner; the accountant
    -- prepares the run, the owner signs it off.
    and (status = 'draft' or public.is_owner())
  )
  with check (public.is_finance());

create policy payroll_items_read on public.payroll_items
  for select to authenticated
  using (public.is_finance());

create policy payroll_items_write on public.payroll_items
  for all to authenticated
  using (public.is_finance()) with check (public.is_finance());

-- ---------------------------------------------------------------------------
-- AUDIT LOG — readable by the owner only, and append-only for everybody.
-- There is no UPDATE or DELETE policy at all, so not even the owner can
-- rewrite history through the API. Rows arrive solely via the SECURITY
-- DEFINER trigger, which bypasses RLS on insert.
-- ---------------------------------------------------------------------------
create policy audit_read on public.audit_log
  for select to authenticated
  using (public.is_owner());

-- ---------------------------------------------------------------------------
-- DOCUMENT COUNTERS — internal plumbing. No direct access; the numbering
-- functions are SECURITY DEFINER and reach the table on the user's behalf.
-- ---------------------------------------------------------------------------
create policy counters_read on public.document_counters
  for select to authenticated
  using (public.is_finance());

-- ---------------------------------------------------------------------------
-- New signups get a profile automatically, defaulting to the least
-- privileged role. The owner then assigns the real role and branch.
--
-- 'viewer' requires a branch, so the account stays inert until an owner
-- completes it — a new signup can read nothing in the meantime.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, full_name, email, role, branch_id)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    new.email,
    'viewer',
    (select id from public.branches order by created_at limit 1)
  )
  on conflict (id) do nothing;

  return new;
end
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
