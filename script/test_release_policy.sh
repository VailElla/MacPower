#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/script/package_release.sh"
TEST_PACKAGE_SCRIPT="$ROOT_DIR/script/package_test_release.sh"
BUILD_SCRIPT="$ROOT_DIR/script/build_and_run.sh"

assert_contains() {
  local file_path="$1"
  local expected_text="$2"

  if ! /usr/bin/grep -Fq -- "$expected_text" "$file_path"; then
    echo "Expected $file_path to contain: $expected_text" >&2
    exit 1
  fi
}

assert_fails_before_build() {
  local label="$1"
  shift

  set +e
  local output
  output="$("$@" 2>&1)"
  local exit_code=$?
  set -e

  if [[ "$exit_code" -eq 0 ]]; then
    echo "$label unexpectedly succeeded without distribution credentials." >&2
    exit 1
  fi
  if ! printf '%s\n' "$output" | /usr/bin/grep -Fq "MACPOWER_SIGNING_IDENTITY"; then
    echo "$label did not fail at MACPOWER_SIGNING_IDENTITY preflight." >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

assert_fails_before_build \
  "package_release.sh" \
  /usr/bin/env -u MACPOWER_SIGNING_IDENTITY -u MACPOWER_EXPECTED_TEAM_ID -u MACPOWER_NOTARY_PROFILE \
  "$PACKAGE_SCRIPT"

assert_fails_before_build \
  "build_and_run.sh --bundle-only --distribution" \
  /usr/bin/env -u MACPOWER_SIGNING_IDENTITY -u MACPOWER_EXPECTED_TEAM_ID \
  "$BUILD_SCRIPT" --bundle-only --distribution

assert_contains "$PACKAGE_SCRIPT" "--distribution"
assert_contains "$PACKAGE_SCRIPT" "notarytool submit"
assert_contains "$PACKAGE_SCRIPT" "stapler staple"
assert_contains "$PACKAGE_SCRIPT" "verify_release.sh"
assert_contains "$BUILD_SCRIPT" "--options runtime"
assert_contains "$BUILD_SCRIPT" "Authority=Developer ID Application:"
assert_contains "$ROOT_DIR/script/verify_release.sh" "Authority=Developer ID Application:"
assert_contains "$TEST_PACKAGE_SCRIPT" "UNNOTARIZED"
assert_contains "$TEST_PACKAGE_SCRIPT" "Signature=adhoc"
assert_contains "$TEST_PACKAGE_SCRIPT" "spctl --assess"
assert_contains "$TEST_PACKAGE_SCRIPT" "hdiutil create"
assert_contains "$TEST_PACKAGE_SCRIPT" "hdiutil verify"
assert_contains "$TEST_PACKAGE_SCRIPT" "DMG_MOUNT_DIR/Applications"

echo "Release policy regression checks passed."
