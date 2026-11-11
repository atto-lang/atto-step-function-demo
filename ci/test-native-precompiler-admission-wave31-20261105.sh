#!/usr/bin/env bash
# Validate fail-closed precompiler admission in a disposable Git checkout.
# No fake compiler acceptance, no native guest certification.
set -euo pipefail
# Avoid inheriting host or CI compiler settings in adversarial fixtures.
unset ATTOLANG_BIN ATTOLANG_COMPILER_SHA256 ORESLANG_BIN ORESLANG_COMPILER_SHA256 EXPECTED_SOURCE_SHA
root="$(cd "$(dirname "$0")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/ci" "$tmp/workflows"
cp "$root/ci/verify-native.sh" "$tmp/ci/verify-native.sh"
cp "$root/ci/verify-build-info.sh" "$tmp/ci/verify-build-info.sh"
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
# Reject disagreement between old and new compiler identity variables before executing any binary.
if EXPECTED_SOURCE_SHA="$head_sha" ATTOLANG_BIN=/bin/false ORESLANG_BIN=/bin/true \
  sh "$tmp/ci/verify-native.sh" >"$tmp/verify.out" 2>&1; then
  echo 'NATIVE_ADMISSION_MUTATION_MISSED: conflicting_compiler_paths' >&2; exit 1
fi
grep -Fq COMPILER_PATH_VARIABLE_CONFLICT "$tmp/verify.out"
if EXPECTED_SOURCE_SHA="$head_sha" ATTOLANG_COMPILER_SHA256="$(printf '1%.0s' {1..64})" \
  ORESLANG_COMPILER_SHA256="$(printf '2%.0s' {1..64})" ORESLANG_BIN='' \
  sh "$tmp/ci/verify-native.sh" >"$tmp/verify.out" 2>&1; then
  echo 'NATIVE_ADMISSION_MUTATION_MISSED: conflicting_compiler_digests' >&2; exit 1
fi
grep -Fq COMPILER_DIGEST_VARIABLE_CONFLICT "$tmp/verify.out"

# These deliberately fake binaries are used ONLY to prove rejection by the
# native verifier; they never count as real guest/compiler execution.
mkdir -p "$tmp/bins"
cat > "$tmp/bins/fake-compiler" <<'FAKE'
#!/bin/sh
if [ "$1" = "--build-info" ]; then
  if [ "$FAKE_GUEST_FLAG" = false ]; then
    printf '%s\n' '{"build_mode":"native","guest_execution":false}'
  else
    printf '%s\n' '{"build_mode":"native","guest_execution":true}'
  fi
  exit 0
fi
# Malicious no-op: accepts invalid source instead of parsing it.
exit 0
FAKE
chmod 700 "$tmp/bins/fake-compiler"
digest="$(sha256sum "$tmp/bins/fake-compiler" | cut -d ' ' -f 1)"
if EXPECTED_SOURCE_SHA="$head_sha" FAKE_GUEST_FLAG=false \
  ATTOLANG_BIN="$tmp/bins/fake-compiler" ATTOLANG_COMPILER_SHA256="$digest" \
  sh "$tmp/ci/verify-native.sh" >"$tmp/verify.out" 2>&1; then
  echo 'NATIVE_ADMISSION_MUTATION_MISSED: reported_false_guest' >&2; exit 1
fi
grep -Fq 'BAD_COMPILER: untrusted reported guest_execution/build_mode' "$tmp/verify.out"
if EXPECTED_SOURCE_SHA="$head_sha" \
  ATTOLANG_BIN="$tmp/bins/fake-compiler" ATTOLANG_COMPILER_SHA256="$digest" \
  sh "$tmp/ci/verify-native.sh" >"$tmp/verify.out" 2>&1; then
  echo 'NATIVE_ADMISSION_MUTATION_MISSED: no_op_compiler' >&2; exit 1
fi
grep -Fq 'BAD_COMPILER: accepted deliberately invalid AttoLang syntax' "$tmp/verify.out"
printf 'HOST_ONLY_NATIVE_PRECOMPILER_DENIAL_PASS cases=9; NOT_GUEST_EXECUTION\n'
