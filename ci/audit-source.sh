#!/bin/sh
# Static source policy; PASS is not evidence that any guest code executed.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
fail() { echo "NATIVE_SOURCE_POLICY_FAILED: $*" >&2; exit 1; }

# Every implementation language file is AttoLang; POSIX sh is only a host CI harness.
bad="$(git ls-files | grep -E '(^|/)(package(-lock)?\.json|[^/]+\.(mjs|cjs|js|jsx|ts|tsx|py|pyi|ipynb))$' || true)"
[ -z "$bad" ] || fail "non-native implementation files: $bad"
[ ! -d src ] || fail "the old host runtime src directory remains"
for f in ci/native-cases.txt ci/verify-native.sh ci/check-native-manifest.sh ci/test-atto-manifest.sh ci/verify-build-info.sh ci/test-build-info.sh workflows/order-workflow.atto \
         workflows/order-rejected.atto workflows/agent-memory-workflow.atto \
         workflows/agent-memory-quarantine.atto workflows/release-review-workflow.atto \
         workflows/release-waiting.atto workflows/bounded-retry.atto \
         workflows/cancel-before-work.atto workflows/coordinator-state.atto; do
  git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 ||
    fail "required native source is not tracked: $f"
done
sh ci/check-native-manifest.sh || fail "AttoLang manifest/source bijection failed"
if git grep -nE 'node:|require\(|eval\(|child_process|npm (run|test)|\.mjs' -- 'workflows/*.atto'; then
  fail "host JavaScript runtime invoked by native guest"
fi
if git grep -nE '==|!=' -- '*.atto'; then
  fail "legacy equality operators found; use eq/neq"
fi
if git grep -nE '(^|[[:space:]])(python|pip|uv|pytest)([[:space:]]|$)' -- 'ci/*.sh'; then
  fail "Python tooling forbidden"
fi
echo 'NATIVE_SOURCE_POLICY_PASS (source only, no guest test verdict)'
