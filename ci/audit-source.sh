#!/bin/sh
# Static source policy; PASS is not evidence that any guest code executed.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
fail() { echo "NATIVE_SOURCE_POLICY_FAILED: $*" >&2; exit 1; }

# Every implementation language file is Oreslang; POSIX sh is only a host CI harness.
bad="$(git ls-files | grep -E '(^|/)(package(-lock)?\.json|[^/]+\.(mjs|cjs|js|jsx|ts|tsx|py|pyi|ipynb))$' || true)"
[ -z "$bad" ] || fail "non-native implementation files: $bad"
[ ! -d src ] || fail "the old host runtime src directory remains"
for f in ci/native-cases.txt ci/verify-native.sh workflows/order-workflow.ores \
         workflows/order-rejected.ores workflows/agent-memory-workflow.ores \
         workflows/agent-memory-quarantine.ores workflows/release-review-workflow.ores \
         workflows/release-waiting.ores workflows/bounded-retry.ores \
         workflows/cancel-before-work.ores workflows/coordinator-state.ores \
         workflows/order-saga-success.ores workflows/order-saga-compensated.ores \
         workflows/order-saga-ambiguous.ores; do
  git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 ||
    fail "required native source is not tracked: $f"
done
[ "$(git ls-files 'workflows/*.ores' | wc -l | tr -d ' ')" -eq 12 ] ||
  fail "unreviewed extra/missing native workflow source"
if git grep -nE 'node:|require\(|eval\(|child_process|npm (run|test)|\.mjs' -- 'workflows/*.ores'; then
  fail "host JavaScript runtime invoked by native guest"
fi
if git grep -nE '(^|[[:space:]])(python|pip|uv|pytest)([[:space:]]|$)' -- 'ci/*.sh'; then
  fail "Python tooling forbidden"
fi

# Only one actor-owned state root; no direct phase mutations.
grep -Fqx 'define isolated actor WorkflowCoordinator as' workflows/coordinator-state.ores ||
  fail "coordinator is not an isolated actor"
grep -Eq '^[[:space:]]*state[[:space:]]*\{' workflows/coordinator-state.ores ||
  fail "coordinator state schema missing"
grep -Fq 'self.handle_state(critical |s| -> {' workflows/coordinator-state.ores ||
  fail "coordinator exclusive state loan missing"
if grep -Eq 'self[.]phase|^[[:space:]]*let[[:space:]]+String[[:space:]]+phase[[:space:]]*=' workflows/coordinator-state.ores; then
  fail "direct coordinator actor field access"
fi
if grep -Eq 'return[[:space:]]+self[.]handle_state|val[[:space:]]+response[[:space:]]*=[[:space:]]*self[.]handle_state' workflows/coordinator-state.ores; then
  fail "void actor state-loan callback used as a result-returning API"
fi

# The exclusive loan must close before any send, stop or output. The current
# fixture has one lexical state loan. This is source-only verification and
# not a substitute for checked compiler effects/borrow admission.
awk '
  /^[[:space:]]*self[.]handle_state[(]critical[[:space:]]*[|]s[|]/ {
    loans++; in_loan = 1; next
  }
  in_loan && /^[[:space:]]*[}][)][;][[:space:]]*$/ {
    in_loan = 0; closed = 1; next
  }
  in_loan && (/self[.](send|end)[(]/ || /stdio[.]/ ||
              /(^|[[:space:]])await([[:space:]]|$)/) { bad = 1 }
  /self[.]send[(]response[)]/ { sent++; if (!closed || in_loan) bad = 1 }
  END { if (loans != 1 || in_loan || !closed || sent != 1 || bad) exit 1 }
' workflows/coordinator-state.ores ||
  fail "actor state loan must be closed before send/stop/IO"

echo 'NATIVE_SOURCE_POLICY_PASS (source only, no guest test verdict)'
