#!/bin/sh
# Static source policy; PASS is not evidence that any guest code executed.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
fail() { echo "NATIVE_SOURCE_POLICY_FAILED: $*" >&2; exit 1; }

# Every implementation language file is Oreslang; POSIX sh is only a host CI harness.
bad="$(git ls-files | grep -E '(^|/)(package(-lock)?\.json|[^/]+\.(mjs|cjs|js|jsx|ts|tsx|py|pyi|ipynb))$' || true)"
[ -z "$bad" ] || fail "non-native implementation files: $bad"
# Ban additional implementation languages in the demo itself. Only Oreslang
# runs workflow logic; .sh is permitted exclusively as a CI harness.
tracked="$(git ls-files)"
while IFS= read -r path || [ -n "$path" ]; do
  case "$path" in
    *.ores|*.md|*.json|*.sql|*.yml|*.yaml|*.toml|*.gitignore|.github/CODEOWNERS|ci/*.sh|ci/*.txt) ;;
    *) fail "unreviewed language or binary artifact: $path" ;;
  esac
done <<EOF
$tracked
EOF
[ ! -d src ] || fail "the old host runtime src directory remains"
# A tracked source symlink can point outside the checked-out Git tree even
# when git status is clean; never allow the native guest to dereference it.
if git ls-files -s | grep '^120000 ' >/dev/null; then
  fail "symlink path not allowed in native-only source tree"
fi
for f in examples/oreslang/workflow-generation-fence.ores examples/oreslang/checkpoint-candidate-m1.ores ci/verify-native-semantic-negatives.sh ci/test-native-semantic-negatives.sh \
         ci/verify-build-info.sh ci/test-build-info.sh ci/native-cases.txt ci/verify-native.sh workflows/order-workflow.ores \
         workflows/order-rejected.ores workflows/agent-memory-workflow.ores \
         workflows/agent-memory-quarantine.ores workflows/release-review-workflow.ores \
         workflows/release-waiting.ores workflows/bounded-retry.ores \
         workflows/cancel-before-work.ores workflows/coordinator-state.ores \
         workflows/order-saga-success.ores workflows/order-saga-compensated.ores \
         workflows/order-saga-ambiguous.ores \
         workflows/order-saga-void-unknown.ores workflows/effect-receipt-ledger.ores; do
  git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 ||
    fail "required native source is not tracked: $f"
done
[ "$(git ls-files 'workflows/*.ores' | wc -l | tr -d ' ')" -eq 14 ] ||
  fail "unreviewed extra/missing native workflow source"
if git grep -nE 'node:|require\(|eval\(|child_process|npm (run|test)|\.mjs' -- 'workflows/*.ores'; then
  fail "host JavaScript runtime invoked by native guest"
fi
if git grep -nE '(^|[[:space:]])(python|pip|uv|pytest)([[:space:]]|$)' -- 'ci/*.sh'; then
  fail "Python tooling forbidden"
fi
# Validate exact guest manifest and all 13 canonical paths; source-only.
sh ci/check-native-manifest.sh || fail 'native manifest verification'
# Mutation probes must reject invalid native guest manifests.
sh ci/test-native-manifest.sh || fail 'native manifest negative probes'
# Every actor is examined for illegal ordinary instance fields or direct state.
git ls-files 'workflows/*.ores' 'examples/oreslang/*.ores' |
  while IFS= read -r source; do
    sh ci/audit-actor-state.sh "$source" || fail "actor-state policy: $source"
  done
sh ci/test-actor-state-policy.sh || fail 'actor-state negative probes'
# Source-only inventory: no new undeclared actor state bypass exemptions.
sh ci/check-actor-state-inventory.sh || fail 'stateless actor exception inventory'
echo 'NATIVE_SOURCE_POLICY_PASS (source only, no guest test verdict)'
