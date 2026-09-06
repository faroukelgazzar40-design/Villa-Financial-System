# Villa ERP — Architecture

## Why this rewrite exists

The previous version was a dashboard, not a system of record:

| Problem | Consequence |
|---|---|
| No database — data compiled into `.ts` files plus browser `localStorage` | Every browser held a different copy; nothing synced |
| No authentication | The public GitHub Pages URL exposed every transaction to anyone |
| Office rent retyped every month across 16 files | 12,500 appeared ~16 times; a rent change meant editing history |
| `paymentStatus` set by hand | 'Paid' could say one thing while the money said another |
| Free-text `salesPerson` | `mariam`, `Mariam`, `mariam ahmed` were three different people in reports |
| `Branch` a hardcoded TypeScript union | Opening El Ma7or and West Gate required a code change and redeploy |
| No history | Edits and deletions left no trace |

Each of those is addressed below.

---

## Stack

- **Postgres (via Supabase)** — the system of record. Chosen over Firestore because financial reporting is inherently relational: monthly P&L, per-branch rollups, receivables ageing and occupancy are joins and aggregates, which SQL does natively and a document store does badly.
- **Supabase Auth** — login, sessions, password reset.
- **Row-Level Security** — permissions enforced *inside* the database.
- **React + Vite** — the existing frontend, retained.

### Why RLS rather than checks in the app

Access rules live in Postgres, not in React. A policy applies no matter how the row is reached — the web app, a direct REST call, or a leaked API key. Hiding a button is not security. The result is that `select * from expense_transactions` returns different rows depending on who is asking, and there is no code path that forgets to filter.

Every table is `enable row level security` **and** `force row level security`; the latter applies policies to the table owner too, closing the usual escape hatch. With RLS on and no matching policy, the default is deny.

---

## Permission model

| Role | Branch scope | Income | Expenses | Payroll | Users | Audit log |
|---|---|---|---|---|---|---|
| **owner** | All | Full | Full | Full + approve | Manage | Read |
| **accountant** | All | Full | Full | Prepare | — | — |
| **branch_manager** | One branch | Full | Full | — | — | — |
| **sales** | One branch | Own entries only | **None** | — | — | — |
| **viewer** | One branch | Read | Read | — | — | — |

Deliberate choices:

- **Sales cannot see expenses at all.** Not greyed out — the rows are never returned.
- **Branch managers cannot see individual salaries**, including their own staff's. Payroll is owner + accountant only.
- **Accountant prepares payroll, owner approves it.** Separation of duties on the largest cash outflow.
- **A new signup is inert.** `handle_new_user()` creates a `viewer` profile; the owner must assign a real role before it can do anything.
- **Users cannot change their own role.** The `profiles_update_self` policy re-reads role and branch from the stored row, so sending `role='owner'` in an update is rejected.

`profiles_branch_scope_ck` enforces the model structurally: `owner`/`accountant` must have `branch_id IS NULL`; every other role must name a branch. Without it a branch manager with a null branch would slip past the branch predicates and read everything.

---

## Schema

### Directory
- **`branches`** — locations are rows, not a type. Opening a 5th branch is an `INSERT`.
- **`spaces`** — rentable inventory (`office`, `meeting_room`, `desk`, `virtual`). Replaces the free-text `space` string with a foreign key, which is what makes occupancy and per-room revenue answerable.
- **`clients`** — tenants, with Egyptian `tax_id` and `commercial_reg` for compliant invoices.
- **`contracts`** — **the fix for the copy-paste.** Rent is stated once. `generate_monthly_invoices()` produces one invoice per active contract per month and is idempotent, so re-running it never double-bills. An exclusion constraint prevents letting the same office to two tenants over overlapping dates.

### Finance
- **`invoices` / `invoice_lines`** — totals are recomputed by trigger from the lines; the client never writes them. `vat_rate` is stored per invoice so historical documents keep the rate that applied when issued (Egypt: 14%).
- **`payments`** — invoice status is *derived* from payments. `paid` / `partially_paid` / `overdue` are conclusions, not fields anyone sets.
- **`income_transactions`** — non-contract revenue: walk-in rooms, market/bar, hourly desks.
- **`expense_transactions`** — costs, with optional receipt attachment.

### Operations
- **`bookings`** — hourly reservations. A GiST exclusion constraint makes double-booking **impossible at the database level**, not merely validated in the UI.
- **`employees`** — distinct from `profiles`: a profile is a login, an employee is a person on the payroll. Cleaning staff have no login; not every login draws a salary.
- **`commission_rules`** — effective-dated, so changing a rate does not retroactively rewrite past payroll. Most specific rule wins (employee+category → employee → default).
- **`payroll_runs` / `payroll_items`** — approved runs are frozen by trigger. Corrections are made by reversal, never by editing history.

### Integrity rules applied throughout
- **Money is `numeric(14,2)`, never float.** Floats cannot represent 0.10 exactly and drift when summed over thousands of rows.
- **Financial records are never hard-deleted.** Invoices are voided (keeping the number), payments reversed, transactions soft-deleted.
- **Derived values are `generated always as ... stored`** — `line_total`, booking `hours`, `gross_pay`, `net_pay` cannot disagree with their inputs.
- **Document numbers** are atomic and per branch per year: `INV-6OCT-2026-000042`. Two users invoicing simultaneously cannot collide.

---

## Audit trail

Every insert, update and delete on the 15 business tables writes to `audit_log` with the before state, after state, the list of changed fields, and who did it.

The log is **append-only for everyone**. There is no `UPDATE` or `DELETE` policy on it — not even for the owner — so history cannot be rewritten through the API. Rows arrive only via a `SECURITY DEFINER` trigger.

---

## A note on the helper functions

The RLS helpers (`current_role()`, `has_branch_access()`, …) are all:

- `SECURITY DEFINER` — they read `profiles`, and the caller's own RLS on `profiles` would otherwise recurse infinitely.
- `STABLE` — Postgres calls them once per statement rather than once per row.
- `SET search_path = public, pg_temp` — pins schema resolution so a user cannot shadow `profiles` with their own table and escalate.

Reporting views are declared `WITH (security_invoker = true)`, so they run as the *querying* user and RLS still applies through them. Without that flag a view runs as its owner and becomes a hole straight through branch security.

---

## Verification

The schema is not asserted to be secure — it is tested:

```bash
./supabase/tests/run_tests.sh
```

Spins up a throwaway Postgres, applies all six migrations, and asserts:

**Isolation** — owner sees all branches; each branch manager sees only their own and zero rows of the other's; sales sees zero expenses, zero payroll, and only their own income entries.

**Escalation attempts, all blocked** — sales promoting themselves to owner; sales writing an expense; a manager writing into another branch; the owner deleting audit rows.

**Business rules** — double-booking refused; adjacent booking accepted; invoice totals computed (10,000 + 14% = 11,400); partial payment → `partially_paid`; full payment → `paid`; invoice numbering formatted per branch.

All currently pass.

---

## Migrations

| File | Contents |
|---|---|
| `0001_foundation` | Extensions, enums, branches, profiles, security helpers, document numbering |
| `0002_directory` | Spaces, clients, contracts |
| `0003_finance` | Invoices, lines, payments, income, expenses, monthly billing |
| `0004_operations` | Bookings, employees, commission, payroll |
| `0005_audit_rls` | Audit log + every RLS policy |
| `0006_reporting` | P&L, receivables ageing, occupancy, expiring contracts, sales performance |

Applied in filename order.

---

## Status

Done: schema, security model, audit, reporting views, test suite.

Next: Supabase project provisioning; wiring auth into the React app; migrating the 16 months of existing data; module screens; bilingual EN/AR with RTL.
