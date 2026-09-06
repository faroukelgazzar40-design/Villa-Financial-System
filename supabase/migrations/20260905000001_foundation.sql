-- ============================================================================
-- 0001 FOUNDATION
-- Extensions, enums, branches, user profiles, and the security helper
-- functions that every Row-Level Security policy in this system depends on.
-- ============================================================================

create extension if not exists "pgcrypto";   -- gen_random_uuid()
create extension if not exists "btree_gist"; -- overlap constraints for bookings

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

-- Five access levels. See docs/ARCHITECTURE.md for the full permission matrix.
create type user_role as enum (
  'owner',           -- full access, all branches, approves payroll, reads audit log
  'accountant',      -- all branches, full finance read/write, no user management
  'branch_manager',  -- one branch, full read/write inside it
  'sales',           -- one branch, creates income/bookings/clients, no cost visibility
  'viewer'           -- one branch, read-only
);

create type space_type as enum (
  'office',        -- private office let on a contract
  'meeting_room',  -- booked by the hour
  'desk',          -- hot desk / coworking seat
  'virtual'        -- virtual office (address + mail handling only)
);

create type payment_method as enum (
  'cash',
  'bank_transfer',
  'instapay',
  'vodafone_cash',
  'cheque'
);

create type contract_status as enum (
  'draft',
  'active',
  'expired',
  'terminated'
);

create type invoice_status as enum (
  'draft',
  'issued',
  'partially_paid',
  'paid',
  'overdue',
  'void'
);

create type booking_status as enum (
  'tentative',
  'confirmed',
  'completed',
  'cancelled',
  'no_show'
);

create type payroll_status as enum (
  'draft',
  'approved',
  'paid'
);

-- Income categories, carried over from the spreadsheet vocabulary.
create type income_category as enum (
  'office_space',
  'virtual_office',
  'meeting_room',
  'market_bar',
  'coworking',
  'hr',
  'commission',
  'registration_fee',
  'vat',
  'other'
);

create type expense_category as enum (
  'rent',
  'salaries',
  'ads',
  'market',
  'maintenance',
  'electricity',
  'internet',
  'transportation',
  'assets',
  'mobile',
  'cleaning',
  'registration_fee',
  'commission',
  'bank_fees',
  'stationery',
  'other'
);

-- ---------------------------------------------------------------------------
-- Branches
--
-- Branches were previously a hardcoded TypeScript union type, which meant
-- opening a 5th location required a code change and a redeploy. They are now
-- rows: opening a branch is an INSERT.
-- ---------------------------------------------------------------------------
create table public.branches (
  id          uuid primary key default gen_random_uuid(),
  code        text        not null unique,  -- '6OCT', 'NC', 'MAHOR', 'WG'
  name_en     text        not null,
  name_ar     text        not null,
  address_en  text,
  address_ar  text,
  phone       text,
  is_active   boolean     not null default true,
  opened_on   date,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.branches is
  'Physical locations. Every financial record is scoped to exactly one branch; '
  'this column is the axis all row-level security is built on.';

-- ---------------------------------------------------------------------------
-- Profiles
--
-- Supabase keeps credentials in auth.users, which we never touch directly.
-- This table holds the application-level identity: role and branch scope.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text        not null,
  email       text        not null,
  phone       text,
  role        user_role   not null default 'viewer',
  -- NULL branch_id means "all branches" and is only meaningful for
  -- owner/accountant. Enforced by profiles_branch_scope_ck below.
  branch_id   uuid        references public.branches (id) on delete restrict,
  locale      text        not null default 'en' check (locale in ('en', 'ar')),
  is_active   boolean     not null default true,
  last_seen_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  -- Owners and accountants are org-wide; everyone else MUST be pinned to a
  -- branch. Without this, a branch_manager with a null branch_id would slip
  -- past the RLS predicates and read every branch.
  constraint profiles_branch_scope_ck check (
    (role in ('owner', 'accountant') and branch_id is null)
    or
    (role in ('branch_manager', 'sales', 'viewer') and branch_id is not null)
  )
);

comment on column public.profiles.branch_id is
  'NULL = organisation-wide access (owner/accountant only). Any other role '
  'must name a branch; see profiles_branch_scope_ck.';

create index profiles_branch_idx on public.profiles (branch_id) where is_active;
create index profiles_role_idx   on public.profiles (role)      where is_active;

-- ---------------------------------------------------------------------------
-- Security helper functions
--
-- These are the primitives every RLS policy calls. Notes on why they look
-- like this:
--
--   SECURITY DEFINER  - they read public.profiles, but the calling user's own
--                       RLS on profiles would otherwise recurse infinitely.
--   STABLE            - result is fixed within a statement, so Postgres can
--                       call them once instead of per-row.
--   SET search_path   - pins schema resolution so a malicious user cannot
--                       shadow `profiles` with their own table and escalate.
-- ---------------------------------------------------------------------------

create or replace function public.current_role()
returns user_role
language sql stable security definer set search_path = public, pg_temp
as $$
  select role from public.profiles where id = auth.uid() and is_active
$$;

create or replace function public.current_branch()
returns uuid
language sql stable security definer set search_path = public, pg_temp
as $$
  select branch_id from public.profiles where id = auth.uid() and is_active
$$;

-- Owner only: user administration, payroll approval, voiding documents.
create or replace function public.is_owner()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce(public.current_role() = 'owner', false)
$$;

-- Owner or accountant: the two roles that see money across all branches.
create or replace function public.is_finance()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce(public.current_role() in ('owner', 'accountant'), false)
$$;

-- Can this user see rows belonging to `target_branch`?
-- Finance roles see everything; everyone else sees only their own branch.
create or replace function public.has_branch_access(target_branch uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.is_active
      and (
        p.role in ('owner', 'accountant')
        or p.branch_id = target_branch
      )
  )
$$;

-- Can this user create/modify rows in `target_branch`?
-- Excludes 'viewer', which is read-only by definition.
create or replace function public.can_write_branch(target_branch uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.is_active
      and p.role <> 'viewer'
      and (
        p.role in ('owner', 'accountant')
        or p.branch_id = target_branch
      )
  )
$$;

-- Sales staff must not see cost/expense/payroll data at all.
create or replace function public.can_see_costs()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce(
    public.current_role() in ('owner', 'accountant', 'branch_manager'),
    false
  )
$$;

-- ---------------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end
$$;

create trigger branches_touch
  before update on public.branches
  for each row execute function public.touch_updated_at();

create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Sequential document numbering (invoices, receipts, contracts)
--
-- Numbers restart each year and are independent per branch, producing
-- references like  INV-6OCT-2026-000042.
--
-- The INSERT .. ON CONFLICT DO UPDATE .. RETURNING is a single atomic
-- statement, so two users invoicing at the same moment cannot collide or
-- reuse a number.
-- ---------------------------------------------------------------------------
create table public.document_counters (
  branch_id   uuid   not null references public.branches (id) on delete cascade,
  doc_type    text   not null,  -- 'invoice' | 'receipt' | 'contract'
  year        int    not null,
  last_number bigint not null default 0,
  primary key (branch_id, doc_type, year)
);

create or replace function public.next_document_number(
  p_branch uuid,
  p_type   text,
  p_year   int
)
returns bigint
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  n bigint;
begin
  insert into public.document_counters (branch_id, doc_type, year, last_number)
  values (p_branch, p_type, p_year, 1)
  on conflict (branch_id, doc_type, year)
    do update set last_number = public.document_counters.last_number + 1
  returning last_number into n;

  return n;
end
$$;

-- Formats a full human-readable reference, e.g. 'INV-6OCT-2026-000042'.
create or replace function public.format_document_number(
  p_branch uuid,
  p_type   text,
  p_year   int,
  p_number bigint
)
returns text
language sql stable security definer set search_path = public, pg_temp
as $$
  select upper(left(p_type, 3)) || '-'
      || (select code from public.branches where id = p_branch) || '-'
      || p_year::text || '-'
      || lpad(p_number::text, 6, '0')
$$;

-- ---------------------------------------------------------------------------
-- Seed the four branches that exist today.
-- ---------------------------------------------------------------------------
insert into public.branches (code, name_en, name_ar, opened_on) values
  ('6OCT',  '6 October', 'السادس من أكتوبر', '2025-07-01'),
  ('NC',    'Nasr City', 'مدينة نصر',        '2025-07-01'),
  ('MAHOR', 'El Ma7or',  'المحور',           '2026-08-01'),
  ('WG',    'West Gate', 'وست جيت',          '2026-09-01')
on conflict (code) do nothing;
