#!/bin/sh
# Real two-session DB test; not a crash or guest compiler proof.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf 'M1_RACE_NOT_VERIFIED: %s\n' "$*" >&2; exit 1; }
[ "${M1_TEST_DISPOSABLE_DATABASE_ACK:-}" = YES ] ||
 die 'explicit disposable database approval required'
case "${M1_TEST_PGSERVICE:-}" in
 ''|*[!A-Za-z0-9_-]*) die 'invalid test PGSERVICE';;
esac
command -v psql >/dev/null 2>&1 || die 'psql unavailable'
if command -v timeout >/dev/null 2>&1; then
 limiter="$(command -v timeout)"
elif command -v gtimeout >/dev/null 2>&1; then
 limiter="$(command -v gtimeout)"
else
 die 'bounded timeout unavailable'
fi
export PGSERVICE="$M1_TEST_PGSERVICE"
tmp="$(mktemp -d)" || die 'cannot make private temp directory'
chmod 700 "$tmp"
race_run="r_$(basename "$tmp" | tr -cd 'A-Za-z0-9_')"
[ "${#race_run}" -le 64 ] && [ "${#race_run}" -gt 4 ] ||
 die 'invalid ephemeral run key'
contender_app="m1_race_contender_$race_run"
seeded=no
owner_pid=
contender_pid=
cleanup() {
  rc=$?
  trap - EXIT HUP INT TERM
  if [ -n "$owner_pid" ]; then
    kill "$owner_pid" 2>/dev/null || true
    wait "$owner_pid" 2>/dev/null || true
  fi
  if [ -n "$contender_pid" ]; then
    kill "$contender_pid" 2>/dev/null || true
    wait "$contender_pid" 2>/dev/null || true
  fi
  if [ "$seeded" = yes ]; then
    if ! "$limiter" --kill-after=3s 10s psql -X -w -qAt \
      -v ON_ERROR_STOP=1 -v race_run="$race_run" \
      -f sql/workflow_m1_disposable_guard.sql \
      -f sql/workflow_m1_race_cleanup.sql >"$tmp/cleanup.out" 2>"$tmp/cleanup.err"; then
      cat "$tmp/cleanup.err" >&2
      rc=1
    fi
  fi
  rm -rf "$tmp"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
"$limiter" --kill-after=3s 12s psql -X -w -qAt \
 -v ON_ERROR_STOP=1 -v race_run="$race_run" \
 -f sql/workflow_m1_disposable_guard.sql \
 -f sql/workflow_m1_race_setup.sql >"$tmp/setup.out" 2>"$tmp/setup.err" ||
 { cat "$tmp/setup.err" >&2; die 'setup rejected'; }
seeded=yes
"$limiter" --kill-after=3s 25s psql -X -w -qAt \
 -v ON_ERROR_STOP=1 -v race_run="$race_run" \
 -f sql/workflow_m1_disposable_guard.sql \
 -f sql/workflow_m1_race_owner.sql >"$tmp/owner.out" 2>"$tmp/owner.err" &
owner_pid=$!
held=no
i=0
while [ "$i" -lt 80 ]; do
  if grep -Fq 'M1_RACE_OWNER_LOCK_HELD' "$tmp/owner.out"; then held=yes; break; fi
  if ! kill -0 "$owner_pid" 2>/dev/null; then break; fi
  sleep 0.05
  i=$((i+1))
done
[ "$held" = yes ] || { cat "$tmp/owner.err" >&2; die 'owner never held row lock'; }
env PGAPPNAME="$contender_app" "$limiter" --kill-after=3s 25s \
 psql -X -w -qAt -v ON_ERROR_STOP=1 -v race_run="$race_run" \
 -f sql/workflow_m1_disposable_guard.sql \
 -f sql/workflow_m1_race_contender.sql >"$tmp/contender.out" 2>"$tmp/contender.err" &
contender_pid=$!
observed=no
i=0
while [ "$i" -lt 80 ]; do
  if ! kill -0 "$contender_pid" 2>/dev/null; then break; fi
  seen="$("$limiter" --kill-after=2s 4s psql -X -w -qAt \
    -v ON_ERROR_STOP=1 -v contender_app="$contender_app" \
    -f sql/workflow_m1_disposable_guard.sql \
    -f sql/workflow_m1_race_observe.sql)" ||
      die 'cannot observe contender row-lock wait'
  if [ "$seen" = M1_RACE_LOCK_WAIT_OBSERVED ]; then observed=yes; break; fi
  sleep 0.05
  i=$((i+1))
done
[ "$observed" = yes ] || { cat "$tmp/contender.err" >&2; die 'concurrent lock wait not observed'; }
if ! wait "$owner_pid"; then cat "$tmp/owner.err" >&2; die 'owner failed'; fi
owner_pid=
if ! wait "$contender_pid"; then cat "$tmp/contender.err" >&2; die 'contender failed'; fi
contender_pid=
grep -Fxq 'M1_RACE_OWNER_COMMITTED' "$tmp/owner.out" ||
 die 'no acknowledged owner COMMIT'
grep -Fxq 'M1_RACE_CONTENDER_FENCED' "$tmp/contender.out" ||
 die 'stale contender not rejected'
printf 'M1_RACE_SQL_PASS (two-session lock + generation fence; NOT crash/native proof)\n'
