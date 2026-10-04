#!/bin/bash
# Restore the most recent locally saved app/login-agent predecessor on macmini.
set -euo pipefail
source "$(dirname "$0")/deployment-config.sh"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" /bin/bash -s -- "$OBSERVER_BUNDLE_ID" <<'REMOTE'
set -euo pipefail
bundle_id="$1"
uid="$(/usr/bin/id -u)"
if /usr/bin/pgrep -x AppleHomeObserver >/dev/null 2>&1; then /usr/bin/printf 'Quit AppleHomeObserver on the Mac mini before rollback.\n' >&2; exit 2; fi
root="$HOME/Library/Application Support/AppleHomeObserver-Deployment/rollback"
app="$HOME/Applications/AppleHomeObserver.app"
agent="$HOME/Library/LaunchAgents/${bundle_id}.plist"
latest="$(/usr/bin/find "$root" -mindepth 1 -maxdepth 1 -type d -print | /usr/bin/sort | /usr/bin/tail -1)"
[[ -n "$latest" ]] || { /usr/bin/printf 'No install predecessor is recorded.\n' >&2; exit 2; }
/bin/launchctl bootout "gui/$uid/${bundle_id}" >/dev/null 2>&1 || true
if [[ "$(/bin/cat "$latest/previous_app" 2>/dev/null || /usr/bin/printf 0)" == 1 ]]; then
    /bin/rm -rf "$app"
    /usr/bin/ditto "$latest/AppleHomeObserver.app" "$app"
else
    /bin/rm -rf "$app"
fi
if [[ "$(/bin/cat "$latest/previous_agent" 2>/dev/null || /usr/bin/printf 0)" == 1 ]]; then
    /bin/cp -p "$latest/${bundle_id}.plist" "$agent"
    /bin/launchctl bootstrap "gui/$uid" "$agent"
else
    /bin/rm -f "$agent"
fi
/usr/bin/printf 'Restored app files from %s\n' "$latest"
REMOTE
