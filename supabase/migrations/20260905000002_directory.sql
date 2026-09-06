-- ============================================================================
-- 0002 DIRECTORY
-- The things being rented (spaces), the people renting them (clients), and
-- the agreements between them (contracts).
--
-- This layer is what the spreadsheet never had. Previously "Office 1 = 12,500"
-- was retyped as a fresh transaction every single month, in every month file.
-- Here it is stated once as a contract, and the monthly charge is generated
-- from it. Rent changes, move-outs and renewals become data instead of
-- silent edits.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Spaces — the rentable inventory
-- ---------------------------------------------------------------------------
create table public.spaces (
  id          uuid       primary key default gen_random_uuid(),
  branch_id   uuid       not null references public.branches (id) on delete restrict,
  code        text       not null,          -- 'Office 1', 'NC-01', 'M-01', 'WG-01'
  name_en     text,
  name_ar     text,
  type        space_type not null,
  capacity    int        check (capacity is null or capacity > 0),

  -- Asking price. The contract carries the agreed price, which may differ;
  -- this is the default offered to new tenants.
  list_price  numeric(14,2) check (list_price is null or list_price >= 0),
  -- Meeting rooms and hot desks bill by the hour instead.
  hourly_rate numeric(14,2) check (hourly_rate is null or hourly_rate >= 0),

  is_active   boolean    not null default true,
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  -- 'Office 1' in 6 October and 'Office 1' in Nasr City are different rooms.
  unique (branch_id, code)
);

comment on table public.spaces is
  'Rentable inventory. Replaces the free-text `space` string on transactions '
  'with a real foreign key, so occupancy and per-room revenue become queryable.';

create index spaces_branch_idx on public.spaces (branch_id) where is_active;
create index spaces_type_idx   on public.spaces (branch_id, type) where is_active;

-- ---------------------------------------------------------------------------
-- Clients — tenants and customers
-- ---------------------------------------------------------------------------
create table public.clients (
  id            uuid       primary key default gen_random_uuid(),
  code          text       not null unique, -- 'CL-000123', assigned on insert
  branch_id     uuid       not null references public.branches (id) on delete restrict,

  name_en       text       not null,
  name_ar       text,
  company_name  text,

  -- Egyptian statutory identifiers, required to issue a compliant tax invoice.
  tax_id        text,      -- الرقم الضريبي
  commercial_reg text,     -- السجل التجاري
  national_id   text,      -- for individual (non-company) tenants

  phone         text,
  email         text,
  address       text,

  is_active     boolean    not null default true,
  onboarded_on  date       not null default current_date,
  notes         text,

  created_by    uuid       references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint clients_email_ck check (
    email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  )
);

comment on column public.clients.tax_id is
  'Egyptian tax registration number. Required on invoices for VAT-registered '
  'clients; leave null for individuals.';

create index clients_branch_idx on public.clients (branch_id) where is_active;
create index clients_name_idx   on public.clients using gin (
  to_tsvector('simple', coalesce(name_en, '') || ' ' || coalesce(company_name, ''))
);

-- ---------------------------------------------------------------------------
-- Contracts — the recurring revenue engine
-- ---------------------------------------------------------------------------
create table public.contracts (
  id               uuid            primary key default gen_random_uuid(),
  contract_number  text            not null unique,
  client_id        uuid            not null references public.clients (id) on delete restrict,
  space_id         uuid            references public.spaces (id) on delete restrict,
  branch_id        uuid            not null references public.branches (id) on delete restrict,

  start_date       date            not null,
  end_date         date,           -- null = open-ended / rolling
  monthly_amount   numeric(14,2)   not null check (monthly_amount >= 0),
  deposit_amount   numeric(14,2)   not null default 0 check (deposit_amount >= 0),
  -- Day of month the charge is raised. Your sheets bill on the 1st.
  billing_day      int             not null default 1 check (billing_day between 1 and 28),

  status           contract_status not null default 'draft',
  auto_renew       boolean         not null default false,
  -- Set when status becomes 'terminated', for early move-outs.
  terminated_on    date,
  termination_reason text,

  notes            text,
  created_by       uuid            references public.profiles (id) on delete set null,
  created_at       timestamptz     not null default now(),
  updated_at       timestamptz     not null default now(),

  constraint contracts_dates_ck check (end_date is null or end_date >= start_date),
  constraint contracts_terminated_ck check (
    (status = 'terminated' and terminated_on is not null)
    or
    (status <> 'terminated' and terminated_on is null)
  )
);

comment on table public.contracts is
  'A tenancy agreement. Monthly office revenue is GENERATED from active '
  'contracts by generate_monthly_invoices(), never typed by hand.';

create index contracts_client_idx  on public.contracts (client_id);
create index contracts_branch_idx  on public.contracts (branch_id, status);
create index contracts_active_idx  on public.contracts (status, end_date)
  where status = 'active';

-- A physical office cannot be let to two tenants over the same dates.
-- Meeting rooms and virtual offices are excluded: those are deliberately
-- shared/oversubscribed and are handled by the bookings table instead.
create or replace function public.contract_blocks_space(p_space uuid)
returns boolean
language sql stable set search_path = public, pg_temp
as $$
  select coalesce(
    (select type in ('office', 'desk') from public.spaces where id = p_space),
    false
  )
$$;

alter table public.contracts
  add constraint contracts_no_double_let
  exclude using gist (
    space_id with =,
    daterange(start_date, coalesce(end_date, 'infinity'::date), '[]') with &&
  )
  where (status in ('active', 'draft') and space_id is not null);

-- ---------------------------------------------------------------------------
-- Auto-numbering
-- ---------------------------------------------------------------------------
create or replace function public.assign_client_code()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.code is null or new.code = '' then
    new.code := 'CL-' || lpad(
      nextval('public.client_code_seq')::text, 6, '0'
    );
  end if;
  return new;
end
$$;

create sequence if not exists public.client_code_seq start 1;

create trigger clients_assign_code
  before insert on public.clients
  for each row execute function public.assign_client_code();

create or replace function public.assign_contract_number()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  n bigint;
  y int := extract(year from new.start_date)::int;
begin
  if new.contract_number is null or new.contract_number = '' then
    n := public.next_document_number(new.branch_id, 'contract', y);
    new.contract_number := public.format_document_number(
      new.branch_id, 'contract', y, n
    );
  end if;
  return new;
end
$$;

create trigger contracts_assign_number
  before insert on public.contracts
  for each row execute function public.assign_contract_number();

-- Keep a contract's branch consistent with the space it occupies. Without
-- this a Nasr City office could be attached to a 6 October contract and the
-- branch-scoped security would report against the wrong location.
create or replace function public.sync_contract_branch()
returns trigger
language plpgsql set search_path = public, pg_temp
as $$
begin
  if new.space_id is not null then
    select branch_id into new.branch_id
    from public.spaces where id = new.space_id;
  end if;
  return new;
end
$$;

create trigger contracts_sync_branch
  before insert or update of space_id on public.contracts
  for each row execute function public.sync_contract_branch();

-- ---------------------------------------------------------------------------
-- Expire contracts whose end date has passed. Called nightly by a scheduled
-- job (pg_cron) or on demand.
-- ---------------------------------------------------------------------------
create or replace function public.expire_contracts()
returns int
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  affected int;
begin
  update public.contracts
     set status = 'expired',
         updated_at = now()
   where status = 'active'
     and end_date is not null
     and end_date < current_date
     and not auto_renew;

  get diagnostics affected = row_count;
  return affected;
end
$$;

create trigger spaces_touch
  before update on public.spaces
  for each row execute function public.touch_updated_at();

create trigger clients_touch
  before update on public.clients
  for each row execute function public.touch_updated_at();

create trigger contracts_touch
  before update on public.contracts
  for each row execute function public.touch_updated_at();
