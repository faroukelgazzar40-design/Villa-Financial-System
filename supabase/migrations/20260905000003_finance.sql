-- ============================================================================
-- 0003 FINANCE
-- Invoices, invoice lines, payments, and the two transaction ledgers.
--
-- Money rule for this whole schema: every monetary column is numeric(14,2),
-- never float/double. Floating point cannot represent 0.10 exactly, and
-- summing thousands of float rows silently drifts. numeric is exact.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Invoices
-- ---------------------------------------------------------------------------
create table public.invoices (
  id             uuid           primary key default gen_random_uuid(),
  invoice_number text           not null unique,
  branch_id      uuid           not null references public.branches (id) on delete restrict,
  client_id      uuid           not null references public.clients (id) on delete restrict,
  contract_id    uuid           references public.contracts (id) on delete set null,

  issue_date     date           not null default current_date,
  due_date       date           not null,
  -- The service period this invoice covers, e.g. 2026-05-01 .. 2026-05-31.
  period_start   date,
  period_end     date,

  -- Totals are maintained by trigger from invoice_lines; never written by the
  -- client. See recalc_invoice_totals() below.
  subtotal       numeric(14,2)  not null default 0 check (subtotal >= 0),
  vat_rate       numeric(5,4)   not null default 0.14 check (vat_rate >= 0 and vat_rate <= 1),
  vat_amount     numeric(14,2)  not null default 0 check (vat_amount >= 0),
  discount       numeric(14,2)  not null default 0 check (discount >= 0),
  total          numeric(14,2)  not null default 0 check (total >= 0),
  amount_paid    numeric(14,2)  not null default 0 check (amount_paid >= 0),

  status         invoice_status not null default 'draft',
  currency       char(3)        not null default 'EGP',
  notes          text,

  -- Financial records are never hard-deleted. Voiding preserves the number
  -- and the trail; DELETE is blocked by RLS for everyone except the owner.
  voided_at      timestamptz,
  voided_by      uuid           references public.profiles (id) on delete set null,
  void_reason    text,

  created_by     uuid           references public.profiles (id) on delete set null,
  created_at     timestamptz    not null default now(),
  updated_at     timestamptz    not null default now(),

  constraint invoices_due_ck    check (due_date >= issue_date),
  constraint invoices_period_ck check (
    (period_start is null and period_end is null)
    or (period_end >= period_start)
  ),
  constraint invoices_void_ck check (
    (status = 'void' and voided_at is not null and void_reason is not null)
    or (status <> 'void' and voided_at is null)
  )
);

comment on column public.invoices.vat_rate is
  'Stored per-invoice rather than read from config, so historical invoices '
  'keep the rate that applied when issued. Egypt standard VAT is 14%.';

create index invoices_client_idx  on public.invoices (client_id, issue_date desc);
create index invoices_branch_idx  on public.invoices (branch_id, issue_date desc);
create index invoices_status_idx  on public.invoices (status, due_date)
  where status in ('issued', 'partially_paid', 'overdue');

-- ---------------------------------------------------------------------------
-- Invoice lines
-- ---------------------------------------------------------------------------
create table public.invoice_lines (
  id             uuid          primary key default gen_random_uuid(),
  invoice_id     uuid          not null references public.invoices (id) on delete cascade,
  space_id       uuid          references public.spaces (id) on delete set null,

  description_en text          not null,
  description_ar text,
  category       income_category not null default 'other',

  quantity       numeric(10,2) not null default 1 check (quantity > 0),
  unit_price     numeric(14,2) not null check (unit_price >= 0),
  -- Generated, so a line total can never disagree with its own inputs.
  line_total     numeric(14,2) generated always as (quantity * unit_price) stored,

  period_start   date,
  period_end     date,
  sort_order     int           not null default 0,
  created_at     timestamptz   not null default now()
);

create index invoice_lines_invoice_idx on public.invoice_lines (invoice_id, sort_order);

-- ---------------------------------------------------------------------------
-- Payments
--
-- A payment may settle an invoice, or stand alone (walk-in cash for a meeting
-- room). Invoice status is DERIVED from payments — the old spreadsheet's
-- manually-set 'Done'/'Pending'/'Partial' could drift from reality; here it
-- cannot.
-- ---------------------------------------------------------------------------
create table public.payments (
  id             uuid           primary key default gen_random_uuid(),
  receipt_number text           not null unique,
  branch_id      uuid           not null references public.branches (id) on delete restrict,
  invoice_id     uuid           references public.invoices (id) on delete restrict,
  client_id      uuid           references public.clients (id) on delete restrict,

  amount         numeric(14,2)  not null check (amount > 0),
  payment_date   date           not null default current_date,
  method         payment_method not null,
  reference      text,          -- bank ref, Instapay txn id, cheque number

  received_by    uuid           references public.profiles (id) on delete set null,
  notes          text,

  reversed_at    timestamptz,
  reversed_by    uuid           references public.profiles (id) on delete set null,
  reversal_reason text,

  created_at     timestamptz    not null default now(),
  updated_at     timestamptz    not null default now(),

  constraint payments_reversal_ck check (
    (reversed_at is null and reversal_reason is null)
    or (reversed_at is not null and reversal_reason is not null)
  )
);

create index payments_invoice_idx on public.payments (invoice_id)
  where reversed_at is null;
create index payments_branch_idx  on public.payments (branch_id, payment_date desc);
create index payments_client_idx  on public.payments (client_id, payment_date desc);

-- ---------------------------------------------------------------------------
-- Income transactions
--
-- Revenue that is not tied to a contract invoice: walk-in meeting room hire,
-- market/bar sales, hourly desks, registration fees.
-- ---------------------------------------------------------------------------
create table public.income_transactions (
  id             uuid            primary key default gen_random_uuid(),
  branch_id      uuid            not null references public.branches (id) on delete restrict,
  space_id       uuid            references public.spaces (id) on delete set null,
  client_id      uuid            references public.clients (id) on delete set null,
  invoice_id     uuid            references public.invoices (id) on delete set null,

  txn_date       date            not null,
  amount         numeric(14,2)   not null check (amount >= 0),
  category       income_category not null,
  description    text,

  method         payment_method  not null default 'cash',
  -- Who made the sale, for commission. Becomes a foreign key to employees in
  -- migration 0004 (that table is created there); typed here so the column
  -- order stays readable. Once linked, 'mariam' / 'Mariam' / 'mariam ahmed'
  -- can no longer be three different people in the reports.
  sales_person_id uuid,

  created_by     uuid            references public.profiles (id) on delete set null,
  created_at     timestamptz     not null default now(),
  updated_at     timestamptz     not null default now(),
  deleted_at     timestamptz
);

create index income_branch_date_idx on public.income_transactions (branch_id, txn_date desc)
  where deleted_at is null;
create index income_category_idx    on public.income_transactions (category, txn_date desc)
  where deleted_at is null;
create index income_sales_idx       on public.income_transactions (sales_person_id, txn_date desc)
  where deleted_at is null;
create index income_creator_idx     on public.income_transactions (created_by)
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- Expense transactions
-- ---------------------------------------------------------------------------
create table public.expense_transactions (
  id             uuid             primary key default gen_random_uuid(),
  branch_id      uuid             not null references public.branches (id) on delete restrict,

  txn_date       date             not null,
  amount         numeric(14,2)    not null check (amount >= 0),
  category       expense_category not null,
  description    text             not null,
  vendor         text,

  method         payment_method   not null default 'cash',
  is_recurring   boolean          not null default false,
  -- Scanned receipt / invoice image in Supabase Storage.
  attachment_url text,

  approved_by    uuid             references public.profiles (id) on delete set null,
  approved_at    timestamptz,

  created_by     uuid             references public.profiles (id) on delete set null,
  created_at     timestamptz      not null default now(),
  updated_at     timestamptz      not null default now(),
  deleted_at     timestamptz
);

create index expense_branch_date_idx on public.expense_transactions (branch_id, txn_date desc)
  where deleted_at is null;
create index expense_category_idx    on public.expense_transactions (category, txn_date desc)
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- Derived totals and status
-- ---------------------------------------------------------------------------

-- Recompute an invoice's money columns from its lines. Fires whenever a line
-- changes, so subtotal/VAT/total are never stale or client-supplied.
create or replace function public.recalc_invoice_totals()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  inv uuid := coalesce(new.invoice_id, old.invoice_id);
  s   numeric(14,2);
begin
  select coalesce(sum(line_total), 0) into s
  from public.invoice_lines where invoice_id = inv;

  update public.invoices
     set subtotal   = s,
         vat_amount = round((s - discount) * vat_rate, 2),
         total      = round((s - discount) * (1 + vat_rate), 2),
         updated_at = now()
   where id = inv;

  return coalesce(new, old);
end
$$;

create trigger invoice_lines_recalc
  after insert or update or delete on public.invoice_lines
  for each row execute function public.recalc_invoice_totals();

-- Recompute amount_paid and status from non-reversed payments.
-- 'paid' / 'partially_paid' / 'overdue' are conclusions drawn from the
-- payment record, never a field somebody sets by hand.
create or replace function public.recalc_invoice_payment_state()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  inv  uuid := coalesce(new.invoice_id, old.invoice_id);
  paid numeric(14,2);
  rec  public.invoices%rowtype;
begin
  if inv is null then
    return coalesce(new, old);
  end if;

  select coalesce(sum(amount), 0) into paid
  from public.payments
  where invoice_id = inv and reversed_at is null;

  select * into rec from public.invoices where id = inv;

  -- A voided invoice stays voided regardless of payment activity.
  if rec.status = 'void' then
    return coalesce(new, old);
  end if;

  update public.invoices
     set amount_paid = paid,
         status = case
           when paid >= rec.total and rec.total > 0 then 'paid'::invoice_status
           when paid > 0                            then 'partially_paid'::invoice_status
           when rec.due_date < current_date         then 'overdue'::invoice_status
           when rec.status = 'draft'                then 'draft'::invoice_status
           else 'issued'::invoice_status
         end,
         updated_at = now()
   where id = inv;

  return coalesce(new, old);
end
$$;

create trigger payments_recalc_invoice
  after insert or update or delete on public.payments
  for each row execute function public.recalc_invoice_payment_state();

-- ---------------------------------------------------------------------------
-- Numbering triggers
-- ---------------------------------------------------------------------------
create or replace function public.assign_invoice_number()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  n bigint;
  y int := extract(year from new.issue_date)::int;
begin
  if new.invoice_number is null or new.invoice_number = '' then
    n := public.next_document_number(new.branch_id, 'invoice', y);
    new.invoice_number := public.format_document_number(
      new.branch_id, 'invoice', y, n
    );
  end if;
  return new;
end
$$;

create trigger invoices_assign_number
  before insert on public.invoices
  for each row execute function public.assign_invoice_number();

create or replace function public.assign_receipt_number()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  n bigint;
  y int := extract(year from new.payment_date)::int;
begin
  if new.receipt_number is null or new.receipt_number = '' then
    n := public.next_document_number(new.branch_id, 'receipt', y);
    new.receipt_number := public.format_document_number(
      new.branch_id, 'receipt', y, n
    );
  end if;
  return new;
end
$$;

create trigger payments_assign_number
  before insert on public.payments
  for each row execute function public.assign_receipt_number();

-- ---------------------------------------------------------------------------
-- Monthly invoice generation
--
-- This is the function that retires the copy-paste. Run it once at the start
-- of a month and every active contract produces exactly one invoice for that
-- period. The NOT EXISTS guard makes it idempotent: running it twice does not
-- double-bill.
-- ---------------------------------------------------------------------------
create or replace function public.generate_monthly_invoices(
  p_period_start date,
  p_branch       uuid default null
)
returns table (invoice_id uuid, contract_number text, amount numeric)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  period_end date := (p_period_start + interval '1 month - 1 day')::date;
  c          record;
  new_inv    uuid;
begin
  if not public.is_finance() then
    raise exception 'Only owner or accountant may generate invoices';
  end if;

  for c in
    select ct.*, s.code as space_code, s.name_en as space_name
    from public.contracts ct
    left join public.spaces s on s.id = ct.space_id
    where ct.status = 'active'
      and ct.start_date <= period_end
      and (ct.end_date is null or ct.end_date >= p_period_start)
      and (p_branch is null or ct.branch_id = p_branch)
      and not exists (
        select 1 from public.invoices i
        where i.contract_id = ct.id
          and i.period_start = p_period_start
          and i.status <> 'void'
      )
  loop
    insert into public.invoices (
      branch_id, client_id, contract_id,
      issue_date, due_date, period_start, period_end, status
    )
    values (
      c.branch_id, c.client_id, c.id,
      p_period_start,
      p_period_start + interval '14 days',
      p_period_start, period_end,
      'issued'
    )
    returning id into new_inv;

    insert into public.invoice_lines (
      invoice_id, space_id, description_en, description_ar,
      category, quantity, unit_price, period_start, period_end
    )
    values (
      new_inv, c.space_id,
      'Rent — ' || coalesce(c.space_code, 'space') || ' — '
        || to_char(p_period_start, 'Mon YYYY'),
      'إيجار — ' || coalesce(c.space_code, '') || ' — '
        || to_char(p_period_start, 'MM/YYYY'),
      'office_space', 1, c.monthly_amount,
      p_period_start, period_end
    );

    invoice_id      := new_inv;
    contract_number := c.contract_number;
    amount          := c.monthly_amount;
    return next;
  end loop;
end
$$;

comment on function public.generate_monthly_invoices is
  'Idempotent monthly billing run. Creates one invoice per active contract '
  'for the given period; safe to re-run (skips contracts already invoiced).';

-- Flag invoices that have sailed past their due date unpaid.
create or replace function public.mark_overdue_invoices()
returns int
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  affected int;
begin
  update public.invoices
     set status = 'overdue', updated_at = now()
   where status in ('issued', 'partially_paid')
     and due_date < current_date
     and amount_paid < total;

  get diagnostics affected = row_count;
  return affected;
end
$$;

create trigger invoices_touch
  before update on public.invoices
  for each row execute function public.touch_updated_at();

create trigger payments_touch
  before update on public.payments
  for each row execute function public.touch_updated_at();

create trigger income_touch
  before update on public.income_transactions
  for each row execute function public.touch_updated_at();

create trigger expense_touch
  before update on public.expense_transactions
  for each row execute function public.touch_updated_at();
