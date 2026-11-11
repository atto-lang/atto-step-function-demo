#!/bin/sh
# Adversarial source inventory tests in a disposable Git repo; no compiler mock.
set -eu
export LC_ALL=C
root="$(cd "$(dirname "$0")/.." && pwd -P)"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/ci" "$tmp/workflows"
cp "$root/ci/check-native-manifest.sh" "$tmp/ci/"
cp "$root/ci/native-cases.txt" "$tmp/ci/"
while IFS='|' read -r file oracle || [ -n "$file" ]; do
  case "$file" in ''|\#*) continue;; esac
  printf 'pub routine main(): void { return; }\n' > "$tmp/$file"
done < "$root/ci/native-cases.txt"
git init -q "$tmp"
git -C "$tmp" config user.name "Manifest fixture"
git -C "$tmp" config user.email "fixture@example.invalid"
git -C "$tmp" add .
git -C "$tmp" commit -qm "nine .atto manifest fixture"
sh "$tmp/ci/check-native-manifest.sh" > "$tmp/out" 2>&1 ||
  { cat "$tmp/out" >&2; exit 1; }
reset_case() {
  git -C "$tmp" reset --hard -q HEAD
  git -C "$tmp" clean -fdq
}
deny_case() {
  name="$1"
  if sh "$tmp/ci/check-native-manifest.sh" > "$tmp/out" 2>&1; then
    printf 'ATTO_MANIFEST_MUTATION_MISSED: %s\n' "$name" >&2
    exit 1
  fi
  grep -Fq 'ATTO_MANIFEST_FAIL:' "$tmp/out" || {
    printf 'ATTO_MANIFEST_WRONG_FAILURE: %s\n' "$name" >&2
    cat "$tmp/out" >&2
    exit 1
  }
  reset_case
}
awk -F '|' 'BEGIN{OFS="|"} /^#/ {print;next} {if (++n==2) $1=first; else if (n==1) first=$1;print}' \
  "$tmp/ci/native-cases.txt" > "$tmp/altered"
mv "$tmp/altered" "$tmp/ci/native-cases.txt"
deny_case duplicate_path
awk -F '|' 'BEGIN{OFS="|"} /^#/ {print;next} {if (++n==2) $2=first; else if (n==1) first=$2;print}' \
  "$tmp/ci/native-cases.txt" > "$tmp/altered"
mv "$tmp/altered" "$tmp/ci/native-cases.txt"
deny_case duplicate_oracle
sed 's#workflows/order-workflow.atto#workflows/../unsafe.atto#' \
  "$tmp/ci/native-cases.txt" > "$tmp/altered"
mv "$tmp/altered" "$tmp/ci/native-cases.txt"
deny_case path_traversal
rm "$tmp/workflows/order-workflow.atto"
deny_case missing_source
: > "$tmp/workflows/order-workflow.atto"
deny_case empty_source
printf 'new\n' > "$tmp/workflows/unreviewed.atto"
git -C "$tmp" add workflows/unreviewed.atto
deny_case unexpected_workflow
printf 'legacy\n' > "$tmp/workflows/legacy.ores"
git -C "$tmp" add workflows/legacy.ores
deny_case legacy_source
rm "$tmp/workflows/order-workflow.atto"
ln -s order-rejected.atto "$tmp/workflows/order-workflow.atto"
deny_case symlinked_source
mv "$tmp/ci/native-cases.txt" "$tmp/ci/trusted"
ln -s trusted "$tmp/ci/native-cases.txt"
deny_case symlinked_manifest
chmod +x "$tmp/workflows/order-workflow.atto"
git -C "$tmp" add workflows/order-workflow.atto
deny_case executable_source
printf 'ATTO_MANIFEST_NEGATIVE_TESTS_PASS cases=10 (HOST_ONLY; NOT_EXECUTED)\n'
