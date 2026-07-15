#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_BUNDLE="$ROOT_DIR/dist/Governor.app"
RELEASE_DIR="$ROOT_DIR/release"
SIGNING_IDENTITY="$(printenv GOVERNOR_SIGNING_IDENTITY || true)"
EXPECTED_TEAM_ID="$(printenv GOVERNOR_EXPECTED_TEAM_ID || true)"
NOTARY_PROFILE="$(printenv GOVERNOR_NOTARY_PROFILE || true)"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Refusing to package a distributable archive without GOVERNOR_SIGNING_IDENTITY." >&2
  exit 1
fi
if [[ -z "$EXPECTED_TEAM_ID" ]]; then
  echo "Refusing to package a distributable archive without GOVERNOR_EXPECTED_TEAM_ID." >&2
  exit 1
fi
if [[ ! "$EXPECTED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "GOVERNOR_EXPECTED_TEAM_ID must be a 10-character Apple Team ID." >&2
  exit 1
fi
if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Refusing to package a distributable archive without GOVERNOR_NOTARY_PROFILE." >&2
  exit 1
fi
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Missing version file: $VERSION_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$VERSION_FILE"

if [[ -z "$GOVERNOR_VERSION" || -z "$GOVERNOR_RELEASE_TAG" ]]; then
  echo "VERSION must define GOVERNOR_VERSION and GOVERNOR_RELEASE_TAG." >&2
  exit 1
fi

ARCHIVE_NAME="Governor-$GOVERNOR_RELEASE_TAG-macOS.zip"
ARCHIVE_PATH="$RELEASE_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"
STAGING_DIR="$(/usr/bin/mktemp -d "$ROOT_DIR/.release-staging.XXXXXX")"
NOTARY_ARCHIVE="$STAGING_DIR/$ARCHIVE_NAME"

cleanup() {
  /bin/rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

GOVERNOR_BUILD_CONFIGURATION=release \
  GOVERNOR_SIGNING_IDENTITY="$SIGNING_IDENTITY" \
  GOVERNOR_EXPECTED_TEAM_ID="$EXPECTED_TEAM_ID" \
  "$ROOT_DIR/script/build_and_run.sh" --bundle-only --distribution

ACTUAL_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$ACTUAL_VERSION" != "$GOVERNOR_VERSION" ]]; then
  echo "Bundle version mismatch: expected $GOVERNOR_VERSION, found $ACTUAL_VERSION" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$NOTARY_ARCHIVE"
/usr/bin/xcrun notarytool submit "$NOTARY_ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$APP_BUNDLE"
/usr/bin/xcrun stapler validate "$APP_BUNDLE"
/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_BUNDLE"

mkdir -p "$RELEASE_DIR"
/bin/rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE_PATH"
(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$ARCHIVE_NAME" >"$ARCHIVE_NAME.sha256"
)

"$ROOT_DIR/script/verify_release.sh" "$ARCHIVE_PATH" "$EXPECTED_TEAM_ID" "$CHECKSUM_PATH"

echo "Notarized release archive: $ARCHIVE_PATH"
echo "SHA-256 convenience checksum: $CHECKSUM_PATH"
