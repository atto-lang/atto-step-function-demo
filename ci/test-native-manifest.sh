#!/bin/sh
# Source-free negative tests of manifest admission; never runs Oreslang guests.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf '%s\n' "NATIVE_GATE_SELFTEST_FAILED: $*" >&2; exit 1; }
umask 077
scratch="$(mktemp -d)" || die "cannot create sandbox"
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
mkdir -p "$scratch/ci" "$scratch/workflows"
cp ci/check-native-manifest.sh ci/native-cases.txt ci/verify-native.sh "$scratch/ci/"
sed -n 's#^\(workflows/[^|]*\)|.*#\1#p' ci/native-cases.txt |
while IFS= read -r path; do
  # Validate BEFORE touching the sandbox filesystem, including when the
  # committed manifest itself is malicious or mistakenly edited.
  case "$path" in workflows/*.ores) ;; *) die "unsafe input fixture path" ;; esac
  leaf="${path#workflows/}"
  stem="${leaf%.ores}"
  case "$stem" in '' | -* | *[!a-z0-9-]* )
    die "unsafe input fixture name" ;;
  esac
  case "$leaf" in */*) die "unsafe nested input fixture" ;; esac
  [ "$path" = "workflows/$stem.ores" ] ||
    die "unsafe input fixture suffix"
  printf 'synthetic source-only fixture\n' > "$scratch/$path"
done
git -C "$scratch" init -q
git -C "$scratch" config user.name "Native CI Selftest"
git -C "$scratch" config user.email "native-gate@example.invalid"
git -C "$scratch" add .
git -C "$scratch" commit -qm "synthetic manifest selftest"
base="$(git -C "$scratch" rev-parse HEAD)"
(
  cd "$scratch"
  sh ci/check-native-manifest.sh >/dev/null
) || die "valid manifest rejected"

reset_case() {
  git -C "$scratch" reset --hard -q "$base"
}
commit_case() {
  git -C "$scratch" add -A
  git -C "$scratch" commit -qm "synthetic malformed admission"
}
reject_case() {
  label="$1"
  if (cd "$scratch" && sh ci/check-native-manifest.sh > /dev/null 2>&1); then
    die "invalid input was accepted: $label"
  fi
  printf 'NATIVE_GATE_NEGATIVE_PASS %s\n' "$label"
}

# The compiler gate must refuse source-only approval when no trusted compiler
# executable and SHA-256 have been provisioned.
if (cd "$scratch" && env -u ORESLANG_BIN -u ORESLANG_COMPILER_SHA256 \
    sh ci/verify-native.sh >/dev/null 2>&1); then
  die "native execution claimed without pinned compiler"
fi
printf 'NATIVE_GATE_NEGATIVE_PASS missing-compiler\n'

sed '/^workflows\/order-saga-ambiguous.ores|/d' "$scratch/ci/native-cases.txt" \
  > "$scratch/ci/modified"
mv "$scratch/ci/modified" "$scratch/ci/native-cases.txt"
commit_case; reject_case missing-case; reset_case

sed 's#workflows/order-saga-ambiguous.ores#workflows/order-saga-success.ores#' \
  "$scratch/ci/native-cases.txt" > "$scratch/ci/modified"
mv "$scratch/ci/modified" "$scratch/ci/native-cases.txt"
commit_case; reject_case duplicate-case; reset_case

# Distinct guest paths may not use the same exact stdout oracle: every case
# needs an independently discriminating expected behavior.
sed 's#saga:reconciliation-required$#saga:complete#' \
  "$scratch/ci/native-cases.txt" > "$scratch/ci/modified"
mv "$scratch/ci/modified" "$scratch/ci/native-cases.txt"
commit_case; reject_case duplicate-stdout-oracle; reset_case

# An oracle beginning with '-' must still be treated as data rather than
# as grep options. Two such output contracts must be rejected.
sed -e 's#saga:reconciliation-required$#-same-oracle#' \
    -e 's#saga:complete$#-same-oracle#' \
  "$scratch/ci/native-cases.txt" > "$scratch/ci/modified"
mv "$scratch/ci/modified" "$scratch/ci/native-cases.txt"
commit_case; reject_case option-prefixed-duplicate-oracle; reset_case

sed 's#workflows/order-saga-ambiguous.ores#workflows/../outside.ores#' \
  "$scratch/ci/native-cases.txt" > "$scratch/ci/modified"
mv "$scratch/ci/modified" "$scratch/ci/native-cases.txt"
commit_case; reject_case traversal; reset_case

sed 's#saga:complete$#saga:complete|unsafe#' \
  "$scratch/ci/native-cases.txt" > "$scratch/ci/modified"
mv "$scratch/ci/modified" "$scratch/ci/native-cases.txt"
commit_case; reject_case invalid-output; reset_case

rm "$scratch/workflows/order-saga-ambiguous.ores"
ln -s order-saga-success.ores "$scratch/workflows/order-saga-ambiguous.ores"
commit_case; reject_case symlink-guest; reset_case

printf 'unlisted\n' > "$scratch/workflows/unlisted.ores"
commit_case; reject_case unlisted-guest; reset_case

printf 'mutated\n' >> "$scratch/workflows/order-saga-success.ores"
reject_case dirty-guest; reset_case

# Git status can be fooled by Git index flags. The source gate must compare
# real working-file bytes to HEAD even if both paths are skip-worktree.
git -C "$scratch" update-index --skip-worktree -- ci/native-cases.txt
sed 's#saga:complete$#saga:tampered#' \
  "$scratch/ci/native-cases.txt" > "$scratch/ci/modified"
mv "$scratch/ci/modified" "$scratch/ci/native-cases.txt"
reject_case hidden-dirty-manifest
git -C "$scratch" update-index --no-skip-worktree -- ci/native-cases.txt
reset_case

git -C "$scratch" update-index --skip-worktree -- workflows/order-saga-success.ores
printf 'hidden mutation\n' >> "$scratch/workflows/order-saga-success.ores"
reject_case hidden-dirty-guest
git -C "$scratch" update-index --no-skip-worktree -- workflows/order-saga-success.ores
reset_case

printf 'NATIVE_GATE_SOURCE_ONLY_SELFTEST_PASS negative_cases=12\n'
