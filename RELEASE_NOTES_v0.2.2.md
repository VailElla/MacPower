# Governor v0.2.2 build 6 — UNNOTARIZED manual-install pre-release

> These are **UNNOTARIZED manual-install assets**. They are ad hoc signed and
> require an explicit, per-Mac Gatekeeper exception after checksum verification.
> They are not Developer ID-trusted or Apple-notarized releases.

> **Build 6:** This update improves settings accessibility. It retains the
> session-only administrator authorization bridge: the first time automation is
> enabled after Governor is opened, macOS requests administrator authorization.
> That authorization ends when Governor quits, and Governor will not appear in
> Login Items.

## What's new

- The Automation Settings window is resizable, scrollable, and initially sized
  within the display's visible height so larger system fonts do not hide lower
  settings.
- The language-default caption was removed from Settings.
- Explanatory settings text now appears through native `i` hover tooltips;
  authorization and hardware-availability warnings remain directly visible.

## Install the UNNOTARIZED app

1. Download the DMG and its matching `.sha256` file, then verify it before
   opening anything:

   ```bash
   shasum -a 256 -c Governor-v0.2.2-UNNOTARIZED-macOS-arm64.dmg.sha256
   ```

2. Open the DMG and drag `Governor.app` to `Applications`.
3. Try to open the app once. Then open **System Settings → Privacy & Security**,
   scroll to **Security**, choose **Open Anyway**, and confirm the next dialog.
   This creates an exception for this app on this Mac; it is not a Developer ID
   signature or notarization.
4. In Governor, enable Automation and approve the administrator prompt. The
   password is not stored; closing Governor ends that authorization session.

Do not disable Gatekeeper globally or strip a downloaded app's quarantine
attribute with Terminal commands. Only use the per-app exception after verifying
the release URL and SHA-256 checksum.

## Authorization modes

- **UNNOTARIZED build 6:** cannot register the persistent `SMAppService`
  helper. It uses a deprecated, session-scoped authorization bridge that can
  execute only Governor's fixed `/usr/bin/pmset` allow-list. This is a manual
  compatibility path, not a trusted long-term distribution mechanism.
- **Developer ID-signed and notarized build:** registers the code-signed XPC
  Helper through `SMAppService`. The user approves it once in System Settings >
  General > Login Items; later app relaunches and lock/unlock do not request an
  administrator password again.

## Test scope

- Passed unit, state-machine, allow-list, build, package, ZIP extraction, DMG
  mount, signature, and SHA-256 verification.
- No test requested real administrator authorization or put the Mac to sleep,
  restarted, shut down, logged out, or disconnected networking.
- Lock/unlock, app-relaunch, reboot persistence, and daemon approval behavior
  were code/simulation/static-validated only; no physical power-lifecycle claim
  is made.
