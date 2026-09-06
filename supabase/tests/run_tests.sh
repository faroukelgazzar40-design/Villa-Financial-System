#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Runs the full migration chain plus the security test suite against a
# throwaway local Postgres. No Supabase account or network needed.
#
#   ./supabase/tests/run_tests.sh
#
# Requires: postgresql-16 (or later) client + server binaries.
# ---------------------------------------------------------------------------
set -uo pipefail

PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
WORK="${WORK:-/tmp/vfs-pgtest}"
PORT="${PORT:-55432}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Postgres will not run as root; use an unprivileged account when necessary.
RUNAS=""
if [ "$(id -u)" -eq 0 ]; then
  id pgtest >/dev/null 2>&1 || useradd -m pgtest
  RUNAS="pgtest"
fi

run() {
  if [ -n "$RUNAS" ]; then su "$RUNAS" -c "$1"; else bash -c "$1"; fi
}

echo "==> Preparing $WORK"
rm -rf "$WORK"; mkdir -p "$WORK/sock"
cp "$REPO"/supabase/migrations/*.sql "$WORK/"
cp "$REPO"/supabase/tests/*.sql      "$WORK/"
[ -n "$RUNAS" ] && chown -R "$RUNAS":"$RUNAS" "$WORK"

echo "==> Starting Postgres on port $PORT"
run "$PGBIN/initdb -D $WORK/pgdata -U postgres --auth=trust" >/dev/null 2>&1
run "$PGBIN/pg_ctl -D $WORK/pgdata \
     -o '-p $PORT -k $WORK/sock -c listen_addresses=\"\"' \
     -l $WORK/pg.log start" >/dev/null 2>&1
sleep 3

trap 'run "$PGBIN/pg_ctl -D $WORK/pgdata stop -m immediate" >/dev/null 2>&1' EXIT

PSQL="psql -h $WORK/sock -p $PORT -U postgres"
run "$PSQL -tAc 'create database villa;'" >/dev/null 2>&1

echo "==> Applying migrations"
FAILED=0
for f in "$WORK"/00_supabase_stub.sql "$WORK"/2026*.sql; do
  name="$(basename "$f")"
  out="$(run "$PSQL -d villa -v ON_ERROR_STOP=1 -q -f $f" 2>&1 | grep -v "NOTICE:" || true)"
  if [ -n "$out" ]; then
    echo "    FAIL  $name"; echo "$out" | head -5; FAILED=1
  else
    echo "    ok    $name"
  fi
done

if [ "$FAILED" -ne 0 ]; then
  echo "==> Migrations failed; stopping."
  exit 1
fi

echo "==> Running security + business rule tests"
run "$PSQL -d villa -f $WORK/90_security_test.sql" 2>&1 \
  | grep -v "^SET$\|^INSERT\|^UPDATE\|^GRANT\|^DO$\|^RESET$\|^$\|Output format" \
  | sed 's/^psql:.*NOTICE:  /    /'

echo "==> Done."
