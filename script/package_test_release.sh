#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_BUNDLE="$ROOT_DIR/dist/MacPower.app"
RELEASE_DIR="$ROOT_DIR/release"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Missing version file: $VERSION_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$VERSION_FILE"

if [[ -z "$MACPOWER_VERSION" || -z "$MACPOWER_RELEASE_TAG" ]]; then
  echo "VERSION must define MACPOWER_VERSION and MACPOWER_RELEASE_TAG." >&2
  exit 1
fi

ARCHIVE_NAME="MacPower-$MACPOWER_RELEASE_TAG-UNNOTARIZED-macOS.zip"
ARCHIVE_PATH="$RELEASE_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"
TMP_ROOT="$(printenv TMPDIR || true)"
if [[ -z "$TMP_ROOT" ]]; then
  TMP_ROOT="/tmp"
fi
VERIFY_DIR="$(/usr/bin/mktemp -d "$TMP_ROOT/macpower-test-release.XXXXXX")"
DMG_STAGING_DIR="$VERIFY_DIR/dmg-staging"
DMG_MOUNT_DIR="$VERIFY_DIR/dmg-mount"
DMG_MOUNTED=0

cleanup() {
  if [[ "$DMG_MOUNTED" -eq 1 ]]; then
    /usr/bin/hdiutil detach "$DMG_MOUNT_DIR" -quiet || true
  fi
  /bin/rm -rf "$VERIFY_DIR"
}
trap cleanup EXIT

MACPOWER_BUILD_CONFIGURATION=release \
  "$ROOT_DIR/script/build_and_run.sh" --bundle-only

ACTUAL_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$ACTUAL_VERSION" != "$MACPOWER_VERSION" ]]; then
  echo "Bundle version mismatch: expected $MACPOWER_VERSION, found $ACTUAL_VERSION" >&2
  exit 1
fi

BINARY_ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_BUNDLE/Contents/MacOS/MacPower")"
ARCHITECTURE_LABEL="$(printf '%s' "$BINARY_ARCHITECTURES" | /usr/bin/tr ' ' '-')"
DMG_NAME="MacPower-$MACPOWER_RELEASE_TAG-UNNOTARIZED-macOS-$ARCHITECTURE_LABEL.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
DMG_CHECKSUM_PATH="$DMG_PATH.sha256"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNING_DETAILS="$(/usr/bin/codesign -dvv "$APP_BUNDLE" 2>&1)"
if ! printf '%s\n' "$SIGNING_DETAILS" | /usr/bin/grep -Fq "Signature=adhoc"; then
  echo "Free test packages must remain explicitly ad hoc signed." >&2
  exit 1
fi

set +e
GATEKEEPER_OUTPUT="$(/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_BUNDLE" 2>&1)"
GATEKEEPER_STATUS=$?
set -e
if [[ "$GATEKEEPER_STATUS" -eq 0 ]]; then
  echo "Gatekeeper unexpectedly accepted the unnotarized test app." >&2
  exit 1
fi

mkdir -p "$RELEASE_DIR"
/bin/rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH" "$DMG_PATH" "$DMG_CHECKSUM_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE_PATH"
(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$ARCHIVE_NAME" >"$ARCHIVE_NAME.sha256"
  /usr/bin/shasum -a 256 -c "$ARCHIVE_NAME.sha256"
)

/usr/bin/ditto -x -k "$ARCHIVE_PATH" "$VERIFY_DIR"
EXTRACTED_APP="$VERIFY_DIR/MacPower.app"
if [[ ! -d "$EXTRACTED_APP" ]]; then
  echo "Archive must contain MacPower.app at its top level." >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$EXTRACTED_APP"
EXTRACTED_SIGNING_DETAILS="$(/usr/bin/codesign -dvv "$EXTRACTED_APP" 2>&1)"
if ! printf '%s\n' "$EXTRACTED_SIGNING_DETAILS" | /usr/bin/grep -Fq "Signature=adhoc"; then
  echo "Extracted test app is not ad hoc signed as expected." >&2
  exit 1
fi

mkdir -p "$DMG_STAGING_DIR" "$DMG_MOUNT_DIR"
/usr/bin/ditto "$APP_BUNDLE" "$DMG_STAGING_DIR/MacPower.app"
/bin/ln -s /Applications "$DMG_STAGING_DIR/Applications"

cat >"$DMG_STAGING_DIR/READ ME - UNNOTARIZED.txt" <<'NOTICE'
MacPower free test build

This app is ad hoc signed and has not been notarized by Apple.
Drag MacPower.app onto the Applications shortcut to install it.

On first launch, macOS will block the app. Only if you trust the source and
have verified the published SHA-256 checksum, open System Settings > Privacy
& Security and choose Open Anyway.
NOTICE

/usr/bin/hdiutil create \
  -volname "MacPower $MACPOWER_VERSION UNNOTARIZED" \
  -srcfolder "$DMG_STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$DMG_NAME" >"$DMG_NAME.sha256"
  /usr/bin/shasum -a 256 -c "$DMG_NAME.sha256"
)

/usr/bin/hdiutil verify "$DMG_PATH"
/usr/bin/hdiutil attach \
  -readonly \
  -nobrowse \
  -noautoopen \
  -mountpoint "$DMG_MOUNT_DIR" \
  "$DMG_PATH" >/dev/null
DMG_MOUNTED=1

if [[ ! -d "$DMG_MOUNT_DIR/MacPower.app" ]]; then
  echo "DMG must contain MacPower.app at its top level." >&2
  exit 1
fi
if [[ ! -L "$DMG_MOUNT_DIR/Applications" ]]; then
  echo "DMG must contain a drag-to-install Applications shortcut." >&2
  exit 1
fi
if [[ "$(/usr/bin/readlink "$DMG_MOUNT_DIR/Applications")" != "/Applications" ]]; then
  echo "DMG Applications shortcut must point to /Applications." >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$DMG_MOUNT_DIR/MacPower.app"
DMG_SIGNING_DETAILS="$(/usr/bin/codesign -dvv "$DMG_MOUNT_DIR/MacPower.app" 2>&1)"
if ! printf '%s\n' "$DMG_SIGNING_DETAILS" | /usr/bin/grep -Fq "Signature=adhoc"; then
  echo "App inside the DMG is not ad hoc signed as expected." >&2
  exit 1
fi

/usr/bin/hdiutil detach "$DMG_MOUNT_DIR" -quiet
DMG_MOUNTED=0

echo "Created free test archive: $ARCHIVE_PATH"
echo "SHA-256 checksum: $CHECKSUM_PATH"
echo "Created drag-to-install DMG: $DMG_PATH"
echo "DMG SHA-256 checksum: $DMG_CHECKSUM_PATH"
echo "Architectures: $BINARY_ARCHITECTURES"
echo "WARNING: These test artifacts are ad hoc signed, are not notarized by Apple, and will trigger Gatekeeper."
echo "Gatekeeper preflight result: $GATEKEEPER_OUTPUT"
