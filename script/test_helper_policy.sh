#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
HELPER_SOURCE="$ROOT_DIR/Sources/GovernorPowerHelper/main.swift"
CONTRACT_SOURCE="$ROOT_DIR/Sources/GovernorHelperSupport/PrivilegedPMSetCommand.swift"
DAEMON_PLIST="$ROOT_DIR/Resources/LaunchDaemons/com.ella.Governor.PowerHelper.plist"

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

assert_no_swift_match() {
  local pattern="$1"
  if rg -n --glob '*.swift' -- "$pattern" "$ROOT_DIR/Sources"; then
    echo "Forbidden privileged-execution pattern found: $pattern" >&2
    exit 1
  fi
}

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) is required for privileged-helper policy checks." >&2
  exit 1
fi

assert_contains "$CONTRACT_SOURCE" 'static let executablePath = "/usr/bin/pmset"'
assert_contains "$CONTRACT_SOURCE" 'return [source.commandFlag, "powermode", String(request.modeRawValue)]'
assert_contains "$CONTRACT_SOURCE" 'return [source.commandFlag, "lowpowermode", String(request.modeRawValue)]'
assert_contains "$HELPER_SOURCE" 'let arguments = try PrivilegedPMSetCommand.arguments(for: request)'
assert_contains "$HELPER_SOURCE" 'process.environment = [:]'
assert_contains "$HELPER_SOURCE" 'listener.setConnectionCodeSigningRequirement(clientRequirement)'
assert_not_contains "$HELPER_SOURCE" 'ProcessInfo.processInfo.arguments'
assert_not_contains "$HELPER_SOURCE" 'ProgramArguments'
assert_no_swift_match 'AuthorizationExecuteWithPrivileges'
assert_no_swift_match 'SMJobBless'
assert_no_swift_match 'AuthorizationCopyRights'
assert_no_swift_match 'kAuthorizationRightExecute'
assert_no_swift_match 'sudo'
assert_no_swift_match '"/bin/sh"'

/usr/bin/plutil -lint "$DAEMON_PLIST" >/dev/null
assert_contains "$DAEMON_PLIST" '<key>BundleProgram</key>'
assert_not_contains "$DAEMON_PLIST" '<key>Program</key>'
assert_not_contains "$DAEMON_PLIST" '<key>ProgramArguments</key>'
assert_contains "$DAEMON_PLIST" '<key>MachServices</key>'
assert_contains "$DAEMON_PLIST" '<key>GOVERNOR_CLIENT_CODE_REQUIREMENT</key>'

echo "Privileged helper policy checks passed."
