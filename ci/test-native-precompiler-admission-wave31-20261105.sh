#!/usr/bin/env bash
# Validate fail-closed precompiler admission in a disposable Git checkout.
# No fake compiler acceptance, no native guest certification.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/ci" "$tmp/workflows"
cp "$root/ci/verify-native.sh" "$tmp/ci/verify-native.sh"
cp "$root/ci/check-native-manifest.sh" "$tmp/ci/check-native-manifest.sh"
cp "$root/ci/native-cases.txt" "$tmp/ci/native-cases.txt"
while IFS='|' read -r file expected || [[ -n "$file" ]]; do
  [[ "$file" == workflows/* ]] || continue
  printf 'pub routine main(): void { return; }\n' > "$tmp/$file"
done < "$root/ci/native-cases.txt"
git init -q "$tmp"
git -C "$tmp" config user.name "Native admission fixture"
git -C "$tmp" config user.email "fixture@example.invalid"
git -C "$tmp" add .
git -C "$tmp" commit -qm "pinned host-native fixture"
head_sha="$(git -C "$tmp" rev-parse HEAD)"
run_deny() {
  local label="$1" expected_message="$2" expected_sha="$3"
  if EXPECTED_SOURCE_SHA="$expected_sha" ORESLANG_BIN='' \
    sh "$tmp/ci/verify-native.sh" >"$tmp/verify.out" 2>&1; then
    printf 'NATIVE_ADMISSION_MUTATION_MISSED: %s\n' "$label" >&2
    exit 1
  fi
  grep -Fq "$expected_message" "$tmp/verify.out"
}
# A spoofed HEAD is rejected ahead of compiler process startup.
run_deny spoofed_head SOURCE_SHA_MISMATCH "$(printf '0%.0s' {1..40})"
# Even a clean, exact-HEAD checkout without a real pinned compiler is not executed.
run_deny absent_compiler 'NOT_EXECUTED: specify absolute ATTOLANG_BIN' "$head_sha"
# A manifest symlink cannot inherit the trusted committed manifest.
mv "$tmp/ci/native-cases.txt" "$tmp/ci/cases-original"
ln -s cases-original "$tmp/ci/native-cases.txt"
run_deny symlinked_manifest UNTRUSTED_CASES "$head_sha"
rm "$tmp/ci/native-cases.txt"
mv "$tmp/ci/cases-original" "$tmp/ci/native-cases.txt"
# Untracked guest source cannot inherit exact-head execution evidence.
printf 'unreviewed\n' > "$tmp/workflows/new.atto"
run_deny untracked_workflow DIRTY_GUEST_SOURCES "$head_sha"
rm "$tmp/workflows/new.atto"
run_deny restored_clean_checkout 'NOT_EXECUTED: specify absolute ATTOLANG_BIN' "$head_sha"
printf 'HOST_ONLY_NATIVE_PRECOMPILER_DENIAL_PASS cases=5; NOT_GUEST_EXECUTION\n'
