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
         workflows/cancel-before-work.ores workflows/coordinator-state.ores; do
  git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 ||
    fail "required native source is not tracked: $f"
done
[ "$(git ls-files 'workflows/*.ores' | wc -l | tr -d ' ')" -eq 9 ] ||
  fail "unreviewed extra/missing native workflow source"
if git grep -nE 'node:|require\(|eval\(|child_process|npm (run|test)|\.mjs' -- 'workflows/*.ores'; then
  fail "host JavaScript runtime invoked by native guest"
fi
if git grep -nE '(^|[[:space:]])(python|pip|uv|pytest)([[:space:]]|$)' -- 'ci/*.sh'; then
  fail "Python tooling forbidden"
fi
echo 'NATIVE_SOURCE_POLICY_PASS (source only, no guest test verdict)'
