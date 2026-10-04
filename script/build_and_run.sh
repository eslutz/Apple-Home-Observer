#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-}"
case "$mode" in ''|--build-only|--debug|--logs|--telemetry|--verify) ;; *) echo 'Unsupported option' >&2; exit 2;; esac
if [[ "$mode" != --build-only ]]; then pkill -x AppleHomeObserver || true; fi
xcodegen generate
xcodebuild -project AppleHomeObserver.xcodeproj -scheme AppleHomeObserver -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build -allowProvisioningUpdates build > build.log 2>&1 || { tail -80 build.log; exit 1; }
app="$PWD/build/Build/Products/Debug-maccatalyst/AppleHomeObserver.app"
[[ "$mode" == --build-only ]] && exit 0
/usr/bin/open -n "$app"
case "$mode" in
 --verify) sleep 2; pgrep -x AppleHomeObserver ;;
 --debug) sleep 2; lldb -n AppleHomeObserver ;;
 --logs|--telemetry) /usr/bin/log stream --info --predicate 'process == "AppleHomeObserver"' ;;
esac
