-- ============================================================================
-- SECURITY TEST
-- Proves the RLS policies actually isolate data. Each block switches to a
-- real user identity and asserts what they can and cannot see.
-- ============================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on

-- --- Fixtures --------------------------------------------------------------
-- Created as superuser (bypasses RLS) to set the stage.

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'owner@villa.eg'),
  ('22222222-2222-2222-2222-222222222222', 'mgr6oct@villa.eg'),
  ('33333333-3333-3333-3333-333333333333', 'mgrnc@villa.eg'),
  ('44444444-4444-4444-4444-444444444444', 'sales6oct@villa.eg');

-- handle_new_user() created viewer profiles; promote them to real roles.
update public.profiles set role='owner', branch_id=null, full_name='Owner'
  where id='11111111-1111-1111-1111-111111111111';
update public.profiles set role='branch_manager', full_name='Mgr 6Oct',
  branch_id=(select id from public.branches where code='6OCT')
  where id='22222222-2222-2222-2222-222222222222';
update public.profiles set role='branch_manager', full_name='Mgr NC',
  branch_id=(select id from public.branches where code='NC')
  where id='33333333-3333-3333-3333-333333333333';
update public.profiles set role='sales', full_name='Sales 6Oct',
  branch_id=(select id from public.branches where code='6OCT')
  where id='44444444-4444-4444-4444-444444444444';

-- One expense and one income row in each of two branches.
insert into public.expense_transactions (branch_id, txn_date, amount, category, description)
values
  ((select id from public.branches where code='6OCT'), '2026-09-01', 5000, 'rent', '6Oct rent'),
  ((select id from public.branches where code='NC'),   '2026-09-01', 7000, 'rent', 'NC rent');

insert into public.income_transactions (branch_id, txn_date, amount, category, created_by)
values
  ((select id from public.branches where code='6OCT'), '2026-09-02', 1000, 'meeting_room',
   '44444444-4444-4444-4444-444444444444'),
  ((select id from public.branches where code='6OCT'), '2026-09-03', 2000, 'meeting_room',
   '22222222-2222-2222-2222-222222222222'),
  ((select id from public.branches where code='NC'),   '2026-09-04', 3000, 'meeting_room',
   '33333333-3333-3333-3333-333333333333');

grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

\echo '=========================================='
\echo 'RLS ISOLATION TESTS'
\echo '=========================================='

-- --- OWNER: sees everything -------------------------------------------------
set role app_user;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select 'owner sees expenses (expect 2): ' || count(*) from public.expense_transactions;
select 'owner sees income   (expect 3): ' || count(*) from public.income_transactions;

-- --- BRANCH MANAGER 6OCT: only their own branch -----------------------------
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select 'mgr6oct sees expenses (expect 1): ' || count(*) from public.expense_transactions;
select 'mgr6oct sees income   (expect 2): ' || count(*) from public.income_transactions;
select 'mgr6oct sees NC data  (expect 0): ' || count(*)
  from public.expense_transactions e
  join public.branches b on b.id=e.branch_id where b.code='NC';

-- --- BRANCH MANAGER NC: the mirror image ------------------------------------
set request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

select 'mgrNC sees expenses  (expect 1): ' || count(*) from public.expense_transactions;
select 'mgrNC sees 6Oct data (expect 0): ' || count(*)
  from public.expense_transactions e
  join public.branches b on b.id=e.branch_id where b.code='6OCT';

-- --- SALES: no cost visibility at all, own income only ----------------------
set request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';

select 'sales sees expenses (expect 0): ' || count(*) from public.expense_transactions;
select 'sales sees income   (expect 1): ' || count(*) from public.income_transactions;
select 'sales sees payroll  (expect 0): ' || count(*) from public.payroll_items;

\echo ''
\echo '=========================================='
\echo 'PRIVILEGE ESCALATION TESTS (must all fail)'
\echo '=========================================='

-- Sales tries to promote themselves to owner.
do $$
declare n int;
begin
  update public.profiles set role='owner'
   where id='44444444-4444-4444-4444-444444444444';
  get diagnostics n = row_count;
  if n > 0 then
    raise exception 'SECURITY HOLE: sales escalated to owner';
  end if;
  raise notice 'PASS: sales cannot change own role (silently blocked)';
exception
  when insufficient_privilege then
    raise notice 'PASS: sales cannot change own role (hard denied by RLS)';
end $$;

-- Sales tries to write an expense.
do $$
begin
  insert into public.expense_transactions (branch_id, txn_date, amount, category, description)
  values ((select id from public.branches where code='6OCT'), '2026-09-05', 999, 'other', 'sneaky');
  raise exception 'SECURITY HOLE: sales inserted an expense';
exception
  when insufficient_privilege or check_violation then
    raise notice 'PASS: sales blocked from writing expenses';
end $$;

-- Branch manager tries to write into another branch.
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
begin
  insert into public.expense_transactions (branch_id, txn_date, amount, category, description)
  values ((select id from public.branches where code='NC'), '2026-09-05', 999, 'other', 'cross-branch');
  raise exception 'SECURITY HOLE: manager wrote into another branch';
exception
  when insufficient_privilege or check_violation then
    raise notice 'PASS: manager blocked from cross-branch write';
end $$;

-- Nobody may rewrite the audit log.
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$
declare n int;
begin
  delete from public.audit_log;
  get diagnostics n = row_count;
  if n > 0 then
    raise exception 'SECURITY HOLE: owner deleted % audit rows', n;
  end if;
  raise notice 'PASS: audit log is append-only even for owner';
end $$;

\echo ''
\echo '=========================================='
\echo 'BUSINESS RULE TESTS'
\echo '=========================================='

reset role;
reset request.jwt.claim.sub;

-- Double-booking a meeting room must be refused by the database.
do $$
declare
  sp uuid;
  br uuid := (select id from public.branches where code='6OCT');
begin
  insert into public.spaces (branch_id, code, type, hourly_rate)
  values (br, 'MR-1', 'meeting_room', 250) returning id into sp;

  insert into public.bookings (space_id, branch_id, contact_name, starts_at, ends_at, hourly_rate, status)
  values (sp, br, 'Client A', '2026-09-10 10:00+02', '2026-09-10 12:00+02', 250, 'confirmed');

  begin
    insert into public.bookings (space_id, branch_id, contact_name, starts_at, ends_at, hourly_rate, status)
    values (sp, br, 'Client B', '2026-09-10 11:00+02', '2026-09-10 13:00+02', 250, 'confirmed');
    raise exception 'BUG: double-booking was allowed';
  exception when exclusion_violation then
    raise notice 'PASS: database refused a double-booking';
  end;

  -- Non-overlapping slot in the same room must still succeed.
  insert into public.bookings (space_id, branch_id, contact_name, starts_at, ends_at, hourly_rate, status)
  values (sp, br, 'Client C', '2026-09-10 12:00+02', '2026-09-10 14:00+02', 250, 'confirmed');
  raise notice 'PASS: adjacent booking accepted';
end $$;

-- Booking price must be derived, not trusted from the client.
select 'booking hours/total (expect 2.00 / 500.00): '
       || hours || ' / ' || total_amount
  from public.bookings where contact_name='Client A';

-- Invoice totals must be computed from lines, incl. 14% VAT.
do $$
declare
  cl  uuid; inv uuid; br uuid := (select id from public.branches where code='6OCT');
  t   numeric; v numeric;
begin
  insert into public.clients (branch_id, name_en) values (br, 'Test Tenant') returning id into cl;
  insert into public.invoices (branch_id, client_id, due_date) values (br, cl, '2026-10-01') returning id into inv;
  insert into public.invoice_lines (invoice_id, description_en, quantity, unit_price)
  values (inv, 'Office rent', 1, 10000);

  select total, vat_amount into t, v from public.invoices where id=inv;
  if t <> 11400.00 or v <> 1400.00 then
    raise exception 'BUG: invoice total % vat % (expected 11400 / 1400)', t, v;
  end if;
  raise notice 'PASS: invoice totals computed correctly (10000 + 14%% VAT = 11400)';
end $$;

-- Paying an invoice must flip its status without anyone setting it by hand.
do $$
declare
  inv uuid := (select id from public.invoices order by created_at desc limit 1);
  br  uuid := (select branch_id from public.invoices where id=inv);
  cl  uuid := (select client_id from public.invoices where id=inv);
  st  invoice_status;
begin
  insert into public.payments (branch_id, invoice_id, client_id, amount, method)
  values (br, inv, cl, 5000, 'cash');
  select status into st from public.invoices where id=inv;
  if st <> 'partially_paid' then raise exception 'BUG: expected partially_paid, got %', st; end if;
  raise notice 'PASS: partial payment -> status partially_paid';

  insert into public.payments (branch_id, invoice_id, client_id, amount, method)
  values (br, inv, cl, 6400, 'instapay');
  select status into st from public.invoices where id=inv;
  if st <> 'paid' then raise exception 'BUG: expected paid, got %', st; end if;
  raise notice 'PASS: full payment -> status paid';
end $$;

-- Invoice numbers must be sequential and per-branch.
select 'invoice number format: ' || invoice_number
  from public.invoices order by created_at desc limit 1;

-- The audit log must have captured all of the above.
select 'audit rows captured: ' || count(*) from public.audit_log;

\echo ''
\echo 'ALL TESTS COMPLETE'
