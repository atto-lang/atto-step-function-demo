#!/bin/sh
# Static negative tests of the source-only policy; never a native guest verdict.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
fail() { echo "POLICY_TEST_FAILED: $*" >&2; exit 1; }
sh ci/audit-source.sh >/dev/null || fail "clean committed source did not pass"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
# Build an isolated tiny Git repo with the exact policy script, without
# borrowing a cross-organization source Git tree or its credentials.
git -C "$tmp" init -q
mkdir -p "$tmp/ci" "$tmp/workflows"
cp ci/*.sh "$tmp/ci/"


cp ci/native-cases.txt "$tmp/ci/"
for f in workflows/*.ores; do cp "$f" "$tmp/workflows/"; done
git -C "$tmp" add ci workflows
# The manifest gate explicitly requires a clean committed source tree.
# The synthetic selftest is source-free and commits only local fixture text.
git -C "$tmp" -c user.name='Native Source Policy Test' -c user.email='source-policy@example.invalid' commit -qm 'isolated source-only policy fixture'
# The policy reads only the index, so no commit/identity config is required.
(cd "$tmp" && sh ci/audit-source.sh) >/dev/null || fail "clean fixture rejected"
printf 'console.log("not allowed")\n' >"$tmp/runtime.js"
git -C "$tmp" add runtime.js
if (cd "$tmp" && sh ci/audit-source.sh) >/dev/null 2>&1; then
  fail "JavaScript implementation admitted"
fi
git -C "$tmp" rm --cached -q -- runtime.js
rm -f "$tmp/runtime.js"
printf 'print("not allowed")\n' > "$tmp/tool.py"
git -C "$tmp" add tool.py
if (cd "$tmp" && sh ci/audit-source.sh) >/dev/null 2>&1; then
  fail "Python implementation admitted"
fi
git -C "$tmp" rm --cached -q -- tool.py
rm -f "$tmp/tool.py"
ln -s /etc/passwd "$tmp/workflows/symlink.ores"
git -C "$tmp" add workflows/symlink.ores
# A policy pass is not enough; the native runner separately validates file
# modes and real Git-blob identity. Reject all symlinks at source policy too.
if (cd "$tmp" && sh ci/audit-source.sh) >/dev/null 2>&1; then
  fail "symlinked guest admitted"
fi
echo 'NATIVE_SOURCE_NEGATIVE_TESTS_PASS (static source only)'
