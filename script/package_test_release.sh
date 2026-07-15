#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_BUNDLE="$ROOT_DIR/dist/Governor.app"
RELEASE_DIR="$ROOT_DIR/release"
HELPER_EXECUTABLE_NAME="GovernorPowerHelper"
HELPER_PLIST_NAME="com.ella.Governor.PowerHelper.plist"

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

ARCHIVE_NAME="Governor-$GOVERNOR_RELEASE_TAG-UNNOTARIZED-macOS.zip"
ARCHIVE_PATH="$RELEASE_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"
TMP_ROOT="$(printenv TMPDIR || true)"
if [[ -z "$TMP_ROOT" ]]; then
  TMP_ROOT="/tmp"
fi
VERIFY_DIR="$(/usr/bin/mktemp -d "$TMP_ROOT/governor-test-release.XXXXXX")"
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

GOVERNOR_BUILD_CONFIGURATION=release \
  "$ROOT_DIR/script/build_and_run.sh" --bundle-only

ACTUAL_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$ACTUAL_VERSION" != "$GOVERNOR_VERSION" ]]; then
  echo "Bundle version mismatch: expected $GOVERNOR_VERSION, found $ACTUAL_VERSION" >&2
  exit 1
fi

BINARY_ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_BUNDLE/Contents/MacOS/Governor")"
ARCHITECTURE_LABEL="$(printf '%s' "$BINARY_ARCHITECTURES" | /usr/bin/tr ' ' '-')"
DMG_NAME="Governor-$GOVERNOR_RELEASE_TAG-UNNOTARIZED-macOS-$ARCHITECTURE_LABEL.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
DMG_CHECKSUM_PATH="$DMG_PATH.sha256"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/codesign --verify --strict --verbose=2 \
  "$APP_BUNDLE/Contents/Resources/$HELPER_EXECUTABLE_NAME"
HELPER_PLIST="$APP_BUNDLE/Contents/Library/LaunchDaemons/$HELPER_PLIST_NAME"
if [[ ! -f "$HELPER_PLIST" ]]; then
  echo "SMAppService daemon plist is missing from the app bundle." >&2
  exit 1
fi
if [[ "$(/usr/bin/plutil -extract BundleProgram raw "$HELPER_PLIST")" \
  != "Contents/Resources/$HELPER_EXECUTABLE_NAME" ]]; then
  echo "SMAppService daemon must use the fixed bundled helper executable." >&2
  exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c \
  'Print :MachServices:com.ella.Governor.PowerHelper' "$HELPER_PLIST")" != "true" ]]; then
  echo "SMAppService daemon must advertise only Governor's fixed Mach service." >&2
  exit 1
fi
if /usr/bin/plutil -extract Program raw "$HELPER_PLIST" >/dev/null 2>&1; then
  echo "SMAppService daemon must use BundleProgram instead of Program." >&2
  exit 1
fi
if /usr/bin/plutil -extract ProgramArguments raw "$HELPER_PLIST" >/dev/null 2>&1; then
  echo "SMAppService daemon must not contain ProgramArguments." >&2
  exit 1
fi
CLIENT_REQUIREMENT="$(/usr/bin/plutil -extract \
  EnvironmentVariables.GOVERNOR_CLIENT_CODE_REQUIREMENT raw "$HELPER_PLIST")"
if [[ "$CLIENT_REQUIREMENT" != *'identifier "com.ella.MacPower"'* ]]; then
  echo "SMAppService daemon is missing its app-client code requirement." >&2
  exit 1
fi
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
EXTRACTED_APP="$VERIFY_DIR/Governor.app"
if [[ ! -d "$EXTRACTED_APP" ]]; then
  echo "Archive must contain Governor.app at its top level." >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$EXTRACTED_APP"
/usr/bin/codesign --verify --strict --verbose=2 \
  "$EXTRACTED_APP/Contents/Resources/$HELPER_EXECUTABLE_NAME"
EXTRACTED_SIGNING_DETAILS="$(/usr/bin/codesign -dvv "$EXTRACTED_APP" 2>&1)"
if ! printf '%s\n' "$EXTRACTED_SIGNING_DETAILS" | /usr/bin/grep -Fq "Signature=adhoc"; then
  echo "Extracted test app is not ad hoc signed as expected." >&2
  exit 1
fi

mkdir -p "$DMG_STAGING_DIR" "$DMG_MOUNT_DIR"
/usr/bin/ditto "$APP_BUNDLE" "$DMG_STAGING_DIR/Governor.app"
/bin/ln -s /Applications "$DMG_STAGING_DIR/Applications"

cat >"$DMG_STAGING_DIR/READ ME - UNNOTARIZED.txt" <<'NOTICE'
Governor free test build (UNNOTARIZED)

This test asset is ad hoc signed and has not been notarized by Apple.
It is not a Developer ID-trusted release. Drag Governor.app onto the
Applications shortcut to install it.

Apple requires an SMAppService LaunchDaemon to be in a notarized app. This
UNNOTARIZED asset cannot register Governor's root power helper and must not be
treated as a no-repeat-password release.

Upgrading from MacPower? Quit it and move MacPower.app to Trash before
installing Governor.app. Do not keep both apps installed or running.

On first launch, macOS will block the app. Only if you trust the source and
have verified the published SHA-256 checksum, open System Settings > Privacy
& Security and choose Open Anyway.
NOTICE

/usr/bin/hdiutil create \
  -volname "Governor $GOVERNOR_VERSION UNNOTARIZED" \
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

if [[ ! -d "$DMG_MOUNT_DIR/Governor.app" ]]; then
  echo "DMG must contain Governor.app at its top level." >&2
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

/usr/bin/codesign --verify --deep --strict --verbose=2 "$DMG_MOUNT_DIR/Governor.app"
/usr/bin/codesign --verify --strict --verbose=2 \
  "$DMG_MOUNT_DIR/Governor.app/Contents/Resources/$HELPER_EXECUTABLE_NAME"
DMG_SIGNING_DETAILS="$(/usr/bin/codesign -dvv "$DMG_MOUNT_DIR/Governor.app" 2>&1)"
if ! printf '%s\n' "$DMG_SIGNING_DETAILS" | /usr/bin/grep -Fq "Signature=adhoc"; then
  echo "App inside the DMG is not ad hoc signed as expected." >&2
  exit 1
fi

/usr/bin/hdiutil detach "$DMG_MOUNT_DIR" -quiet
DMG_MOUNTED=0

echo "Created UNNOTARIZED test archive: $ARCHIVE_PATH"
echo "SHA-256 checksum: $CHECKSUM_PATH"
echo "Created drag-to-install DMG: $DMG_PATH"
echo "DMG SHA-256 checksum: $DMG_CHECKSUM_PATH"
echo "Architectures: $BINARY_ARCHITECTURES"
echo "WARNING: These test artifacts are ad hoc signed, are not notarized by Apple, and will trigger Gatekeeper."
echo "Gatekeeper preflight result: $GATEKEEPER_OUTPUT"
