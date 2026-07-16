#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/script/package_release.sh"
TEST_PACKAGE_SCRIPT="$ROOT_DIR/script/package_test_release.sh"
BUILD_SCRIPT="$ROOT_DIR/script/build_and_run.sh"
VERSION_FILE="$ROOT_DIR/VERSION"
HELPER_POLICY_SCRIPT="$ROOT_DIR/script/test_helper_policy.sh"
TEST_RUNNER="$ROOT_DIR/script/run_tests.sh"

assert_contains() {
  local file_path="$1"
  local expected_text="$2"

  if ! /usr/bin/grep -Fq -- "$expected_text" "$file_path"; then
    echo "Expected $file_path to contain: $expected_text" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file_path="$1"
  local unexpected_text="$2"

  if /usr/bin/grep -Fq -- "$unexpected_text" "$file_path"; then
    echo "Did not expect $file_path to contain: $unexpected_text" >&2
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
  if ! printf '%s\n' "$output" | /usr/bin/grep -Fq "GOVERNOR_SIGNING_IDENTITY"; then
    echo "$label did not fail at GOVERNOR_SIGNING_IDENTITY preflight." >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

assert_fails_before_build \
  "package_release.sh" \
  /usr/bin/env -u GOVERNOR_SIGNING_IDENTITY -u GOVERNOR_EXPECTED_TEAM_ID -u GOVERNOR_NOTARY_PROFILE \
  "$PACKAGE_SCRIPT"

assert_fails_before_build \
  "build_and_run.sh --bundle-only --distribution" \
  /usr/bin/env -u GOVERNOR_SIGNING_IDENTITY -u GOVERNOR_EXPECTED_TEAM_ID \
  "$BUILD_SCRIPT" --bundle-only --distribution

assert_contains "$PACKAGE_SCRIPT" "--distribution"
assert_contains "$PACKAGE_SCRIPT" "notarytool submit"
assert_contains "$PACKAGE_SCRIPT" "stapler staple"
assert_contains "$PACKAGE_SCRIPT" "verify_release.sh"
assert_contains "$PACKAGE_SCRIPT" "GovernorPersistentHelperRegistrationSupported"
assert_contains "$PACKAGE_SCRIPT" "GovernorSessionAuthorizationSupported"
assert_contains "$BUILD_SCRIPT" "--options runtime"
assert_contains "$BUILD_SCRIPT" "Authority=Developer ID Application:"
assert_contains "$BUILD_SCRIPT" 'APP_NAME="Governor"'
assert_contains "$BUILD_SCRIPT" 'LEGACY_APP_NAME="MacPower"'
assert_contains "$BUILD_SCRIPT" 'BUNDLE_ID="com.ella.MacPower"'
assert_contains "$BUILD_SCRIPT" 'HELPER_EXECUTABLE_NAME="GovernorPowerHelper"'
assert_contains "$BUILD_SCRIPT" 'HELPER_SIGNING_IDENTIFIER="com.ella.Governor.PowerHelper"'
assert_contains "$BUILD_SCRIPT" 'APP_LAUNCH_DAEMONS="$APP_CONTENTS/Library/LaunchDaemons"'
assert_contains "$BUILD_SCRIPT" 'GovernorHelperCodeRequirement'
assert_contains "$BUILD_SCRIPT" 'GovernorPersistentHelperRegistrationSupported'
assert_contains "$BUILD_SCRIPT" 'GovernorSessionAuthorizationSupported'
assert_contains "$BUILD_SCRIPT" "GOVERNOR_BUILD_CONFIGURATION"
assert_contains "$VERSION_FILE" "GOVERNOR_VERSION=0.2.2"
assert_contains "$VERSION_FILE" "GOVERNOR_BUILD_NUMBER=6"
assert_contains "$VERSION_FILE" "GOVERNOR_RELEASE_TAG=v0.2.2"
assert_contains "$ROOT_DIR/script/verify_release.sh" "Authority=Developer ID Application:"
assert_contains "$ROOT_DIR/script/verify_release.sh" "Governor.app"
assert_contains "$ROOT_DIR/script/verify_release.sh" "GovernorPowerHelper"
assert_contains "$ROOT_DIR/script/verify_release.sh" "BundleProgram"
assert_contains "$ROOT_DIR/script/verify_release.sh" "GovernorPersistentHelperRegistrationSupported"
assert_contains "$ROOT_DIR/script/verify_release.sh" "GovernorSessionAuthorizationSupported"
assert_contains "$TEST_PACKAGE_SCRIPT" "UNNOTARIZED"
assert_contains "$TEST_PACKAGE_SCRIPT" "Signature=adhoc"
assert_contains "$TEST_PACKAGE_SCRIPT" "spctl --assess"
assert_contains "$TEST_PACKAGE_SCRIPT" "hdiutil create"
assert_contains "$TEST_PACKAGE_SCRIPT" "hdiutil verify"
assert_contains "$TEST_PACKAGE_SCRIPT" "DMG_MOUNT_DIR/Applications"
assert_contains "$TEST_PACKAGE_SCRIPT" "Governor.app"
assert_contains "$TEST_PACKAGE_SCRIPT" "SMAppService daemon plist"
assert_contains "$TEST_PACKAGE_SCRIPT" "GovernorPowerHelper"
assert_contains "$TEST_PACKAGE_SCRIPT" "GovernorPersistentHelperRegistrationSupported"
assert_contains "$TEST_PACKAGE_SCRIPT" "GovernorSessionAuthorizationSupported"
assert_contains "$TEST_PACKAGE_SCRIPT" "Do not keep both apps installed or running."
assert_contains "$HELPER_POLICY_SCRIPT" "AuthorizationExecuteWithPrivileges"
assert_contains "$HELPER_POLICY_SCRIPT" "Privileged helper policy checks passed."
assert_contains "$TEST_RUNNER" "test_helper_policy.sh"
assert_not_contains "$BUILD_SCRIPT" "MACPOWER_"
assert_not_contains "$PACKAGE_SCRIPT" "MACPOWER_"
assert_not_contains "$TEST_PACKAGE_SCRIPT" "MACPOWER_"
assert_not_contains "$VERSION_FILE" "MACPOWER_"
assert_not_contains "$BUILD_SCRIPT" "GOVENOR_"
assert_not_contains "$PACKAGE_SCRIPT" "GOVENOR_"
assert_not_contains "$TEST_PACKAGE_SCRIPT" "GOVENOR_"

echo "Release policy regression checks passed."
