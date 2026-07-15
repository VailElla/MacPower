# Governor v0.2.0 — Pre-release

## SMAppService power helper

- Replaces the deprecated in-process privileged executor with a bundled `SMAppService` LaunchDaemon.
- The root Helper exposes one code-signed XPC method only. It accepts three enumerated values and constructs a fixed `/usr/bin/pmset` allow-list itself; it accepts no shell, executable path, environment, arbitrary command, or arbitrary arguments.
- In a Developer ID-signed and Apple-notarized build installed in `/Applications`, the user approves the daemon once in System Settings > General > Login Items. Later lock/unlock, app relaunch, and automation enable actions do not request an administrator password again.

## Asset status

`Governor-v0.2.0-UNNOTARIZED-*` assets are free packaging-test assets. They are ad hoc signed, not notarized, and not Developer ID-trusted. Apple requires a notarized app for an `SMAppService` LaunchDaemon, so these assets cannot register the privileged Helper and must not be represented as a functioning no-repeat-password release. SHA-256 files detect download corruption or change; they do not prove publisher identity.

## Test scope

- Passed unit, state-machine, allow-list, build, package, ZIP extraction, DMG mount, signature, and SHA-256 verification.
- No test put the Mac to sleep, restarted, shut down, logged out, or disconnected networking.
- Lock/unlock, app-relaunch, reboot persistence, and daemon approval behavior were simulated/static-validated only; no claim of a physical power-lifecycle test is made.
