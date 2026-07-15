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

/usr/bin/xcrun stapler validate "$APP_BUNDLE"
/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_BUNDLE"

echo "Verified notarized Governor release: $ARCHIVE_PATH"
