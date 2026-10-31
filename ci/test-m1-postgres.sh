#!/bin/sh
# Opt-in SQL-only check; no compiler, actor, or crash proof.
set -eu
cd "$(dirname "$0")/.."
[ "${M1_TEST_DISPOSABLE_DATABASE_ACK:-}" = YES ] || {
  echo 'M1_SQL_NOT_EXECUTED: disposable database approval required' >&2; exit 1;
}
case "${M1_TEST_PGSERVICE:-}" in
 '' | *[!A-Za-z0-9_-]*)
  echo 'M1_SQL_NOT_EXECUTED: missing/invalid PGSERVICE' >&2; exit 1 ;;
esac
command -v psql >/dev/null 2>&1 || {
 echo 'M1_SQL_NOT_EXECUTED: psql unavailable' >&2; exit 1;
}
export PGSERVICE="$M1_TEST_PGSERVICE"
psql -X -v ON_ERROR_STOP=1 -f sql/workflow_m1_atomic_checkpoint.sql
psql -X -v ON_ERROR_STOP=1 -f sql/workflow_m1_atomic_tests.sql
echo 'M1_SQL_TEST_COMPLETE (not native/durable crash proof)'
