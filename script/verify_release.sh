#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 ARCHIVE_PATH EXPECTED_TEAM_ID [SHA256_PATH]" >&2
}

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  usage
  exit 2
fi

ARCHIVE_PATH="$1"
EXPECTED_TEAM_ID="$2"
CHECKSUM_PATH=""
if [[ "$#" -eq 3 ]]; then
  CHECKSUM_PATH="$3"
fi

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "Release archive does not exist: $ARCHIVE_PATH" >&2
  exit 1
fi
if [[ ! "$EXPECTED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "EXPECTED_TEAM_ID must be a 10-character Apple Team ID." >&2
  exit 2
fi

if [[ -n "$CHECKSUM_PATH" ]]; then
  if [[ ! -f "$CHECKSUM_PATH" ]]; then
    echo "Checksum file does not exist: $CHECKSUM_PATH" >&2
    exit 1
  fi

  EXPECTED_CHECKSUM="$(/usr/bin/awk '{print $1; exit}' "$CHECKSUM_PATH")"
  ACTUAL_CHECKSUM="$(/usr/bin/shasum -a 256 "$ARCHIVE_PATH" | /usr/bin/awk '{print $1}')"
  if [[ -z "$EXPECTED_CHECKSUM" || "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]]; then
    echo "SHA-256 mismatch for $ARCHIVE_PATH." >&2
    exit 1
  fi
fi

TMP_ROOT="$(printenv TMPDIR || true)"
if [[ -z "$TMP_ROOT" ]]; then
  TMP_ROOT="/tmp"
fi
VERIFY_DIR="$(/usr/bin/mktemp -d "$TMP_ROOT/governor-verify.XXXXXX")"

cleanup() {
  /bin/rm -rf "$VERIFY_DIR"
}
trap cleanup EXIT

/usr/bin/ditto -x -k "$ARCHIVE_PATH" "$VERIFY_DIR"
APP_BUNDLE="$VERIFY_DIR/Governor.app"
HELPER_EXECUTABLE_NAME="GovernorPowerHelper"
HELPER_SIGNING_IDENTIFIER="com.ella.Governor.PowerHelper"
HELPER_PLIST_NAME="com.ella.Governor.PowerHelper.plist"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Archive must contain Governor.app at its top level." >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNING_DETAILS="$(/usr/bin/codesign -dvv "$APP_BUNDLE" 2>&1)"
ACTUAL_TEAM_ID="$(printf '%s\n' "$SIGNING_DETAILS" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"

if [[ "$ACTUAL_TEAM_ID" != "$EXPECTED_TEAM_ID" ]]; then
  echo "Signature Team ID mismatch: expected $EXPECTED_TEAM_ID, found $ACTUAL_TEAM_ID." >&2
  exit 1
fi
if ! printf '%s\n' "$SIGNING_DETAILS" | /usr/bin/grep -Fq "Authority=Developer ID Application:"; then
  echo "Release archive is not signed by a Developer ID Application identity." >&2
  exit 1
fi
if printf '%s\n' "$SIGNING_DETAILS" | /usr/bin/grep -Fq "Signature=adhoc"; then
  echo "Release archive contains an ad hoc signature." >&2
  exit 1
fi

HELPER_BINARY="$APP_BUNDLE/Contents/Resources/$HELPER_EXECUTABLE_NAME"
HELPER_PLIST="$APP_BUNDLE/Contents/Library/LaunchDaemons/$HELPER_PLIST_NAME"
if [[ ! -x "$HELPER_BINARY" || ! -f "$HELPER_PLIST" ]]; then
  echo "Release archive is missing the SMAppService helper layout." >&2
  exit 1
fi

/usr/bin/codesign --verify --strict --verbose=2 "$HELPER_BINARY"
HELPER_SIGNING_DETAILS="$(/usr/bin/codesign -dvv "$HELPER_BINARY" 2>&1)"
HELPER_TEAM_ID="$(printf '%s\n' "$HELPER_SIGNING_DETAILS" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
if [[ "$HELPER_TEAM_ID" != "$EXPECTED_TEAM_ID" ]]; then
  echo "Helper Team ID mismatch: expected $EXPECTED_TEAM_ID, found $HELPER_TEAM_ID." >&2
  exit 1
fi
if ! printf '%s\n' "$HELPER_SIGNING_DETAILS" | /usr/bin/grep -Fq "Identifier=$HELPER_SIGNING_IDENTIFIER"; then
  echo "Helper signing identifier is incorrect." >&2
  exit 1
fi
if ! printf '%s\n' "$HELPER_SIGNING_DETAILS" | /usr/bin/grep -Fq "Authority=Developer ID Application:"; then
  echo "Helper is not signed by a Developer ID Application identity." >&2
  exit 1
fi
if printf '%s\n' "$HELPER_SIGNING_DETAILS" | /usr/bin/grep -Fq "Signature=adhoc"; then
  echo "Helper contains an ad hoc signature." >&2
  exit 1
fi
if [[ "$(/usr/bin/plutil -extract BundleProgram raw "$HELPER_PLIST")" \
  != "Contents/Resources/$HELPER_EXECUTABLE_NAME" ]]; then
  echo "Helper daemon does not use the fixed bundled executable." >&2
  exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c \
  'Print :MachServices:com.ella.Governor.PowerHelper' "$HELPER_PLIST")" != "true" ]]; then
  echo "Helper daemon does not advertise the expected Mach service." >&2
  exit 1
fi
if /usr/bin/plutil -extract Program raw "$HELPER_PLIST" >/dev/null 2>&1 \
  || /usr/bin/plutil -extract ProgramArguments raw "$HELPER_PLIST" >/dev/null 2>&1; then
  echo "Helper daemon contains an unsafe launch command declaration." >&2
  exit 1
fi
CLIENT_REQUIREMENT="$(/usr/bin/plutil -extract \
  EnvironmentVariables.GOVERNOR_CLIENT_CODE_REQUIREMENT raw "$HELPER_PLIST")"
if ! printf '%s\n' "$CLIENT_REQUIREMENT" | /usr/bin/grep -Fq 'identifier "com.ella.MacPower"'; then
  echo "Helper daemon is missing the Governor client identity requirement." >&2
  exit 1
fi
if ! printf '%s\n' "$CLIENT_REQUIREMENT" | /usr/bin/grep -Fq \
  "certificate leaf[subject.OU] = \"$EXPECTED_TEAM_ID\""; then
  echo "Helper daemon client identity requirement does not bind the expected Team ID." >&2
  exit 1
fi
HELPER_REQUIREMENT="$(/usr/bin/plutil -extract GovernorHelperCodeRequirement raw \
  "$APP_BUNDLE/Contents/Info.plist")"
if ! printf '%s\n' "$HELPER_REQUIREMENT" | /usr/bin/grep -Fq \
  "identifier \"$HELPER_SIGNING_IDENTIFIER\""; then
  echo "App bundle is missing the helper identity requirement." >&2
  exit 1
fi
if ! printf '%s\n' "$HELPER_REQUIREMENT" | /usr/bin/grep -Fq \
  "certificate leaf[subject.OU] = \"$EXPECTED_TEAM_ID\""; then
  echo "App bundle helper identity requirement does not bind the expected Team ID." >&2
  exit 1
fi

/usr/bin/xcrun stapler validate "$APP_BUNDLE"
/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_BUNDLE"

echo "Verified notarized Governor release: $ARCHIVE_PATH"
