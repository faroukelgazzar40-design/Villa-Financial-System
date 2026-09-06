-- ============================================================================
-- 0006 REPORTING VIEWS
--
-- Every view here is declared WITH (security_invoker = true). That matters:
-- it makes the view run with the *querying user's* permissions, so the RLS
-- policies from migration 0005 still apply through the view. Without it a
-- view would run as its owner and become a hole straight through branch
-- security — a sales login could read the whole company's P&L.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Monthly profit & loss, per branch.
-- ---------------------------------------------------------------------------
create view public.v_monthly_pnl
with (security_invoker = true) as
with income as (
  select branch_id,
         date_trunc('month', txn_date)::date as month,
         sum(amount)                          as income_total
  from public.income_transactions
  where deleted_at is null
  group by 1, 2
),
invoiced as (
  select branch_id,
         date_trunc('month', issue_date)::date as month,
         sum(total)                            as invoiced_total,
         sum(amount_paid)                      as collected_total
  from public.invoices
  where status <> 'void'
  group by 1, 2
),
expenses as (
  select branch_id,
         date_trunc('month', txn_date)::date as month,
         sum(amount)                          as expense_total
  from public.expense_transactions
  where deleted_at is null
  group by 1, 2
)
select
  b.id                                as branch_id,
  b.code                              as branch_code,
  b.name_en                           as branch_name_en,
  b.name_ar                           as branch_name_ar,
  m.month,
  coalesce(i.income_total, 0)         as direct_income,
  coalesce(iv.invoiced_total, 0)      as invoiced,
  coalesce(iv.collected_total, 0)     as collected,
  coalesce(e.expense_total, 0)        as expenses,
  coalesce(i.income_total, 0) + coalesce(iv.collected_total, 0)
    - coalesce(e.expense_total, 0)    as net_profit
from public.branches b
cross join (
  select distinct month from (
    select month from income
    union select month from invoiced
    union select month from expenses
  ) x
) m
left join income   i  on i.branch_id  = b.id and i.month  = m.month
left join invoiced iv on iv.branch_id = b.id and iv.month = m.month
left join expenses e  on e.branch_id  = b.id and e.month  = m.month;

comment on view public.v_monthly_pnl is
  'Income, expenses and net profit by branch by month. Sales users see no '
  'expense rows, so their `expenses` column reads 0 — by design.';

-- ---------------------------------------------------------------------------
-- Receivables ageing — who owes money and how late they are.
-- Replaces the spreadsheet's manually-typed 'Pending' flag.
-- ---------------------------------------------------------------------------
create view public.v_receivables
with (security_invoker = true) as
select
  i.id                       as invoice_id,
  i.invoice_number,
  i.branch_id,
  b.name_en                  as branch_name,
  i.client_id,
  c.name_en                  as client_name,
  c.company_name,
  c.phone,
  i.issue_date,
  i.due_date,
  i.total,
  i.amount_paid,
  i.total - i.amount_paid    as balance_due,
  i.status,
  (current_date - i.due_date) as days_overdue,
  case
    when i.total - i.amount_paid <= 0     then 'settled'
    when current_date <= i.due_date       then 'current'
    when current_date - i.due_date <= 30  then '1-30 days'
    when current_date - i.due_date <= 60  then '31-60 days'
    when current_date - i.due_date <= 90  then '61-90 days'
    else '90+ days'
  end as ageing_bucket
from public.invoices i
join public.clients  c on c.id = i.client_id
join public.branches b on b.id = i.branch_id
where i.status not in ('void', 'draft')
  and i.total > i.amount_paid;

-- ---------------------------------------------------------------------------
-- Occupancy — how much of each branch is actually let.
-- Impossible to answer from the old spreadsheet; trivial now that contracts
-- and spaces are real tables.
-- ---------------------------------------------------------------------------
create view public.v_occupancy
with (security_invoker = true) as
select
  s.branch_id,
  b.name_en                                    as branch_name,
  s.type                                       as space_type,
  count(*)                                     as total_spaces,
  count(ct.id)                                 as occupied_spaces,
  count(*) - count(ct.id)                      as vacant_spaces,
  round(100.0 * count(ct.id) / nullif(count(*), 0), 1) as occupancy_pct,
  coalesce(sum(ct.monthly_amount), 0)          as contracted_monthly_revenue,
  coalesce(sum(s.list_price), 0)               as potential_monthly_revenue
from public.spaces s
join public.branches b on b.id = s.branch_id
left join public.contracts ct
       on ct.space_id = s.id
      and ct.status = 'active'
      and ct.start_date <= current_date
      and (ct.end_date is null or ct.end_date >= current_date)
where s.is_active
group by s.branch_id, b.name_en, s.type;

-- ---------------------------------------------------------------------------
-- Contracts expiring soon — the renewal worklist.
-- ---------------------------------------------------------------------------
create view public.v_expiring_contracts
with (security_invoker = true) as
select
  ct.id                      as contract_id,
  ct.contract_number,
  ct.branch_id,
  b.name_en                  as branch_name,
  c.name_en                  as client_name,
  c.company_name,
  c.phone,
  s.code                     as space_code,
  ct.start_date,
  ct.end_date,
  ct.monthly_amount,
  ct.auto_renew,
  (ct.end_date - current_date) as days_remaining
from public.contracts ct
join public.clients  c on c.id = ct.client_id
join public.branches b on b.id = ct.branch_id
left join public.spaces s on s.id = ct.space_id
where ct.status = 'active'
  and ct.end_date is not null
  and ct.end_date between current_date and current_date + interval '90 days';

-- ---------------------------------------------------------------------------
-- Sales performance — revenue and commission by person.
-- ---------------------------------------------------------------------------
create view public.v_sales_performance
with (security_invoker = true) as
select
  e.id                                as employee_id,
  e.full_name_en                      as sales_person,
  e.branch_id,
  b.name_en                           as branch_name,
  date_trunc('month', it.txn_date)::date as month,
  count(*)                            as transaction_count,
  sum(it.amount)                      as revenue_generated
from public.income_transactions it
join public.employees e on e.id = it.sales_person_id
join public.branches  b on b.id = it.branch_id
where it.deleted_at is null
group by e.id, e.full_name_en, e.branch_id, b.name_en,
         date_trunc('month', it.txn_date);

-- ---------------------------------------------------------------------------
-- Cash position by payment method — where the money physically landed.
-- ---------------------------------------------------------------------------
create view public.v_cash_by_method
with (security_invoker = true) as
select
  branch_id,
  date_trunc('month', payment_date)::date as month,
  method,
  count(*)     as payment_count,
  sum(amount)  as total_received
from public.payments
where reversed_at is null
group by 1, 2, 3;
