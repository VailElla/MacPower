#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

"$ROOT_DIR/script/test_release_policy.sh"
"$ROOT_DIR/script/test_helper_policy.sh"

cd "$ROOT_DIR"

if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" && -d "$CLT_FRAMEWORKS/Testing.framework" ]]; then
  # Some Command Line Tools installations ship Swift Testing outside the
  # compiler's default framework search path and with a broken Foundation
  # cross-import overlay. Keep the workaround local to the test command.
  exec swift test \
    -Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -F -Xlinker "$CLT_FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS"
fi

exec swift test
