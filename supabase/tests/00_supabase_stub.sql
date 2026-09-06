-- Local stand-in for the parts of Supabase the migrations depend on.
-- Lets the real migration files run unmodified against plain Postgres.

create schema if not exists auth;

create table if not exists auth.users (
  id                    uuid primary key default gen_random_uuid(),
  email                 text unique,
  raw_user_meta_data    jsonb default '{}'::jsonb,
  created_at            timestamptz default now()
);

-- Supabase resolves the current user from the request JWT. Locally we read a
-- session GUC that the tests set explicitly.
create or replace function auth.uid()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

do $$ begin
  create role authenticated;
exception when duplicate_object then null; end $$;

do $$ begin
  create role anon;
exception when duplicate_object then null; end $$;

do $$ begin
  create role app_user login;
exception when duplicate_object then null; end $$;

grant authenticated to app_user;
grant usage on schema public to authenticated, anon;
