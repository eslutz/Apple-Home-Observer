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
latest="$(/usr/bin/python3 - "$root" <<'SELECT'
from pathlib import Path
import sys, uuid
root = Path(sys.argv[1])
def valid(record):
    try:
        if str(uuid.UUID(record.name)) != record.name or not record.is_dir() or record.is_symlink(): return False
        app_flag = (record / "previous_app").read_text().strip()
        agent_flag = (record / "previous_agent").read_text().strip()
        if app_flag not in ("0", "1") or agent_flag not in ("0", "1"): return False
        if app_flag == "1" and not (record / "AppleHomeObserver.app").is_dir(): return False
        return True
    except (ValueError, OSError): return False
pointer = root / "latest"
if pointer.exists() or pointer.is_symlink():
    if pointer.is_symlink(): raise SystemExit("Invalid predecessor pointer")
    record = root / pointer.read_text().strip()
    if record.parent != root or not valid(record): raise SystemExit("Invalid predecessor pointer")
else:
    records = [record for record in root.iterdir() if valid(record)] if root.exists() else []
    if not records: raise SystemExit("No install predecessor is recorded")
    record = max(records, key=lambda value: value.stat().st_mtime_ns)
print(record)
SELECT
)"
[[ -n "$latest" ]] || { /usr/bin/printf 'No install predecessor is recorded.\n' >&2; exit 2; }
if [[ "$(/bin/cat "$latest/previous_app")" == 1 ]]; then
    /usr/bin/codesign --verify --deep --strict "$latest/AppleHomeObserver.app"
fi
if [[ "$(/bin/cat "$latest/previous_agent")" == 1 && ! -f "$latest/${bundle_id}.plist" ]]; then
    /usr/bin/printf 'The predecessor login agent is missing; rollback refused.\n' >&2; exit 2
fi
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
