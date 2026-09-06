-- ============================================================================
-- 0004 OPERATIONS
-- Meeting room / desk bookings, employees, commission rules, and payroll.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Employees
--
-- Distinct from `profiles`: a profile is a login, an employee is a person on
-- the payroll. Cleaning staff have no login; the owner has a login but may
-- not draw a salary here. profile_id links the two when both exist.
-- ---------------------------------------------------------------------------
create table public.employees (
  id             uuid        primary key default gen_random_uuid(),
  employee_code  text        not null unique,
  profile_id     uuid        unique references public.profiles (id) on delete set null,
  branch_id      uuid        not null references public.branches (id) on delete restrict,

  full_name_en   text        not null,
  full_name_ar   text,
  national_id    text        unique,
  job_title_en   text,
  job_title_ar   text,

  hire_date      date        not null,
  termination_date date,
  base_salary    numeric(14,2) not null default 0 check (base_salary >= 0),

  phone          text,
  email          text,
  bank_account   text,
  -- Egyptian social insurance number (الرقم التأميني)
  insurance_no   text,

  is_active      boolean     not null default true,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint employees_termination_ck check (
    termination_date is null or termination_date >= hire_date
  )
);

create index employees_branch_idx on public.employees (branch_id) where is_active;

create sequence if not exists public.employee_code_seq start 1;

create or replace function public.assign_employee_code()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.employee_code is null or new.employee_code = '' then
    new.employee_code := 'EMP-' || lpad(
      nextval('public.employee_code_seq')::text, 4, '0'
    );
  end if;
  return new;
end
$$;

create trigger employees_assign_code
  before insert on public.employees
  for each row execute function public.assign_employee_code();

-- Now that employees exists, complete the link deferred from migration 0003.
alter table public.income_transactions
  add constraint income_sales_person_fk
  foreign key (sales_person_id) references public.employees (id) on delete set null;

-- ---------------------------------------------------------------------------
-- Bookings — meeting rooms and hot desks by the hour
-- ---------------------------------------------------------------------------
create table public.bookings (
  id             uuid           primary key default gen_random_uuid(),
  branch_id      uuid           not null references public.branches (id) on delete restrict,
  space_id       uuid           not null references public.spaces (id) on delete restrict,
  -- Null client_id = walk-in; capture a name and phone instead.
  client_id      uuid           references public.clients (id) on delete set null,
  contact_name   text,
  contact_phone  text,

  starts_at      timestamptz    not null,
  ends_at        timestamptz    not null,
  -- Generated from the times so billable hours can never disagree with the
  -- slot actually reserved.
  hours          numeric(6,2)   generated always as (
                   round(extract(epoch from (ends_at - starts_at)) / 3600.0, 2)
                 ) stored,

  hourly_rate    numeric(14,2)  not null check (hourly_rate >= 0),
  total_amount   numeric(14,2)  not null default 0 check (total_amount >= 0),

  status         booking_status not null default 'tentative',
  invoice_id     uuid           references public.invoices (id) on delete set null,
  income_txn_id  uuid           references public.income_transactions (id) on delete set null,

  notes          text,
  booked_by      uuid           references public.profiles (id) on delete set null,
  created_at     timestamptz    not null default now(),
  updated_at     timestamptz    not null default now(),

  constraint bookings_time_ck check (ends_at > starts_at),
  constraint bookings_contact_ck check (
    client_id is not null or contact_name is not null
  )
);

comment on table public.bookings is
  'Hourly room and desk reservations. Replaces the manual Meeting / hours '
  'rows previously typed straight into the income sheet.';

-- The database itself refuses to double-book a room. This is an exclusion
-- constraint: for any two rows sharing a space_id, their time ranges may not
-- overlap. Cancelled and no-show bookings are excluded so the slot frees up.
alter table public.bookings
  add constraint bookings_no_overlap
  exclude using gist (
    space_id with =,
    tstzrange(starts_at, ends_at) with &&
  )
  where (status in ('tentative', 'confirmed', 'completed'));

create index bookings_space_time_idx on public.bookings (space_id, starts_at);
create index bookings_branch_time_idx on public.bookings (branch_id, starts_at desc);
create index bookings_client_idx on public.bookings (client_id, starts_at desc);

-- Price the booking from its own hours and rate.
create or replace function public.price_booking()
returns trigger
language plpgsql set search_path = public, pg_temp
as $$
begin
  new.total_amount := round(
    round(extract(epoch from (new.ends_at - new.starts_at)) / 3600.0, 2)
    * new.hourly_rate, 2
  );

  -- Keep branch aligned with the room being booked.
  select branch_id into new.branch_id
  from public.spaces where id = new.space_id;

  return new;
end
$$;

create trigger bookings_price
  before insert or update of starts_at, ends_at, hourly_rate, space_id
  on public.bookings
  for each row execute function public.price_booking();

-- ---------------------------------------------------------------------------
-- Commission rules
--
-- Your sales team earns on what they close. Rules are effective-dated so
-- changing a rate does not retroactively rewrite past payroll.
-- ---------------------------------------------------------------------------
create table public.commission_rules (
  id             uuid            primary key default gen_random_uuid(),
  -- Null employee_id = a default rule applying to everyone.
  employee_id    uuid            references public.employees (id) on delete cascade,
  category       income_category,  -- null = all categories
  percentage     numeric(5,2)    not null check (percentage >= 0 and percentage <= 100),
  effective_from date            not null default current_date,
  effective_to   date,
  is_active      boolean         not null default true,
  notes          text,
  created_at     timestamptz     not null default now(),

  constraint commission_dates_ck check (
    effective_to is null or effective_to >= effective_from
  )
);

create index commission_employee_idx
  on public.commission_rules (employee_id, effective_from desc) where is_active;

-- What commission did this person earn in this period?
create or replace function public.calculate_commission(
  p_employee     uuid,
  p_period_start date,
  p_period_end   date
)
returns numeric
language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce(sum(
    it.amount * (
      select cr.percentage / 100.0
      from public.commission_rules cr
      where cr.is_active
        and (cr.employee_id = p_employee or cr.employee_id is null)
        and (cr.category = it.category or cr.category is null)
        and cr.effective_from <= it.txn_date
        and (cr.effective_to is null or cr.effective_to >= it.txn_date)
      -- Most specific rule wins: employee+category, then employee, then default.
      order by (cr.employee_id is not null) desc,
               (cr.category is not null) desc,
               cr.effective_from desc
      limit 1
    )
  ), 0)
  from public.income_transactions it
  where it.sales_person_id = p_employee
    and it.deleted_at is null
    and it.txn_date between p_period_start and p_period_end
$$;

-- ---------------------------------------------------------------------------
-- Payroll
-- ---------------------------------------------------------------------------
create table public.payroll_runs (
  id             uuid           primary key default gen_random_uuid(),
  branch_id      uuid           references public.branches (id) on delete restrict,
  -- Always the 1st of the month being paid.
  period_month   date           not null,
  status         payroll_status not null default 'draft',

  total_gross      numeric(14,2) not null default 0 check (total_gross >= 0),
  total_deductions numeric(14,2) not null default 0 check (total_deductions >= 0),
  total_net        numeric(14,2) not null default 0 check (total_net >= 0),

  approved_by    uuid           references public.profiles (id) on delete set null,
  approved_at    timestamptz,
  paid_at        timestamptz,
  notes          text,
  created_by     uuid           references public.profiles (id) on delete set null,
  created_at     timestamptz    not null default now(),
  updated_at     timestamptz    not null default now(),

  unique (branch_id, period_month),
  constraint payroll_approved_ck check (
    (status = 'draft')
    or (status in ('approved', 'paid') and approved_by is not null and approved_at is not null)
  )
);

create table public.payroll_items (
  id               uuid          primary key default gen_random_uuid(),
  payroll_run_id   uuid          not null references public.payroll_runs (id) on delete cascade,
  employee_id      uuid          not null references public.employees (id) on delete restrict,

  base_salary      numeric(14,2) not null default 0 check (base_salary >= 0),
  commission       numeric(14,2) not null default 0 check (commission >= 0),
  bonus            numeric(14,2) not null default 0 check (bonus >= 0),
  overtime         numeric(14,2) not null default 0 check (overtime >= 0),

  deductions       numeric(14,2) not null default 0 check (deductions >= 0),
  social_insurance numeric(14,2) not null default 0 check (social_insurance >= 0),
  income_tax       numeric(14,2) not null default 0 check (income_tax >= 0),

  gross_pay        numeric(14,2) generated always as (
                     base_salary + commission + bonus + overtime
                   ) stored,
  net_pay          numeric(14,2) generated always as (
                     base_salary + commission + bonus + overtime
                     - deductions - social_insurance - income_tax
                   ) stored,

  notes            text,
  created_at       timestamptz   not null default now(),

  unique (payroll_run_id, employee_id)
);

create index payroll_items_run_idx      on public.payroll_items (payroll_run_id);
create index payroll_items_employee_idx on public.payroll_items (employee_id);

-- Roll item totals up to the run.
create or replace function public.recalc_payroll_run()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  run uuid := coalesce(new.payroll_run_id, old.payroll_run_id);
begin
  update public.payroll_runs r
     set total_gross = coalesce(t.g, 0),
         total_deductions = coalesce(t.d, 0),
         total_net = coalesce(t.n, 0),
         updated_at = now()
    from (
      select sum(gross_pay) g,
             sum(deductions + social_insurance + income_tax) d,
             sum(net_pay) n
      from public.payroll_items where payroll_run_id = run
    ) t
   where r.id = run;

  return coalesce(new, old);
end
$$;

create trigger payroll_items_recalc
  after insert or update or delete on public.payroll_items
  for each row execute function public.recalc_payroll_run();

-- An approved or paid payroll run is frozen. Corrections are made by
-- reversing and re-running, never by quietly editing history.
create or replace function public.guard_payroll_immutability()
returns trigger
language plpgsql set search_path = public, pg_temp
as $$
declare
  st payroll_status;
begin
  select status into st from public.payroll_runs
  where id = coalesce(new.payroll_run_id, old.payroll_run_id);

  if st in ('approved', 'paid') then
    raise exception 'Payroll run is % and can no longer be modified', st;
  end if;

  return coalesce(new, old);
end
$$;

create trigger payroll_items_immutable
  before insert or update or delete on public.payroll_items
  for each row execute function public.guard_payroll_immutability();

-- Build a draft payroll run, pulling commission automatically.
create or replace function public.generate_payroll_draft(
  p_period_month date,
  p_branch       uuid default null
)
returns uuid
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  run_id     uuid;
  period_end date := (p_period_month + interval '1 month - 1 day')::date;
  e          record;
begin
  if not public.is_finance() then
    raise exception 'Only owner or accountant may run payroll';
  end if;

  insert into public.payroll_runs (branch_id, period_month, created_by)
  values (p_branch, p_period_month, auth.uid())
  on conflict (branch_id, period_month) do update
    set updated_at = now()
  returning id into run_id;

  for e in
    select * from public.employees
    where is_active
      and (p_branch is null or branch_id = p_branch)
      and hire_date <= period_end
      and (termination_date is null or termination_date >= p_period_month)
  loop
    insert into public.payroll_items (
      payroll_run_id, employee_id, base_salary, commission
    )
    values (
      run_id, e.id, e.base_salary,
      public.calculate_commission(e.id, p_period_month, period_end)
    )
    on conflict (payroll_run_id, employee_id) do update
      set base_salary = excluded.base_salary,
          commission  = excluded.commission;
  end loop;

  return run_id;
end
$$;

create trigger employees_touch
  before update on public.employees
  for each row execute function public.touch_updated_at();

create trigger bookings_touch
  before update on public.bookings
  for each row execute function public.touch_updated_at();

create trigger payroll_runs_touch
  before update on public.payroll_runs
  for each row execute function public.touch_updated_at();
