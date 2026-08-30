#!/bin/bash
# Rebuilds the debug binary and relaunches Lunchpad, replacing any running debug instance.
# Usage: ./Scripts/dev-run.sh          rebuild, relaunch detached
#        ./Scripts/dev-run.sh -f       rebuild, run in the foreground with live logs
set -euo pipefail

PACKAGE_PATH="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$PACKAGE_PATH/.build/debug/Lunchpad"

# Replace a previous debug instance so two Lunchpads cannot fight over the global hot key.
if pkill -f "build/debug/Lunchpad" 2>/dev/null; then
    sleep 1
fi

swift build --package-path "$PACKAGE_PATH"

# An installed copy (e.g. /Applications/Lunchpad.app) still holding the hot key would swallow
# activation and make the fresh build look broken.
if pgrep -x Lunchpad >/dev/null 2>&1; then
    echo "⚠️ Another Lunchpad instance is still running; it may hold the global hot key."
fi

if [[ "${1:-}" == "-f" ]]; then
    exec "$BINARY"
fi

nohup "$BINARY" >/dev/null 2>&1 &
echo "Lunchpad debug build running (pid $!)."
