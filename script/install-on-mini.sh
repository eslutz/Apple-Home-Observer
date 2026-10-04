#!/bin/bash
# Installs the verified Catalyst app into the existing Mac mini user session.
# The embedded development profile must include the target Mac's UDID.
set -euo pipefail
cd "$(dirname "$0")/.."
source "$(dirname "$0")/deployment-config.sh"
app="$PWD/build/Build/Products/Debug-maccatalyst/AppleHomeObserver.app"
archive="$PWD/dist/AppleHomeObserver.zip"
actual_bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist")
[[ "$actual_bundle" == "$OBSERVER_BUNDLE_ID" ]] || { echo "Configured bundle ID does not match signed app" >&2; exit 2; }
[[ -d "$app" && -f "$archive" ]] || { echo 'Build and prepare the signed package first.' >&2; exit 2; }
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/codesign -d --entitlements :- "$app" 2>/dev/null > /private/tmp/apple-home-observer-entitlements.plist
/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.homekit' /private/tmp/apple-home-observer-entitlements.plist | /usr/bin/grep -qx true
profile="$app/Contents/embedded.provisionprofile"
[[ -f "$profile" ]] || { echo 'The signed app has no embedded development profile.' >&2; exit 2; }
remote_udid="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" "/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/sed -n 's/^.*Provisioning UDID: //p'")"
[[ -n "$remote_udid" ]] || { echo 'Could not read the Mac mini provisioning identifier.' >&2; exit 2; }
profile_plist="$(/usr/bin/mktemp /private/tmp/apple-home-profile.XXXXXX)"
trap '/bin/rm -f "$profile_plist"' EXIT
/usr/bin/openssl cms -verify -noverify -inform DER -in "$profile" -out "$profile_plist" 2>/dev/null
/usr/bin/python3 - "$profile_plist" "$remote_udid" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as stream:
    profile = plistlib.load(stream)
if sys.argv[2] not in profile.get("ProvisionedDevices", []):
    raise SystemExit("The profile does not include the Mac mini; register it and rebuild before installation.")
PY
if ssh -o BatchMode=yes "$target" '/usr/bin/pgrep -x AppleHomeObserver >/dev/null 2>&1'; then
    echo 'Quit AppleHomeObserver on the Mac mini before updating it.' >&2
    exit 2
fi
checksum="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
token="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
remote_archive="/private/tmp/apple-home-observer-${token}.zip"
/bin/chmod 600 "$archive"
/usr/bin/scp -p -q "$archive" "$target:$remote_archive"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" /bin/bash -s -- "$token" "$checksum" "$remote_archive" "$OBSERVER_BUNDLE_ID" <<'REMOTE'
set -euo pipefail
token="$1"; checksum="$2"; archive="$3"; bundle_id="$4"
case "$token" in (*[!0-9a-f-]*|'') exit 2;; esac
[[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || exit 2
[[ "$archive" == "/private/tmp/apple-home-observer-${token}.zip" ]] || exit 2
/usr/bin/printf '%s  %s\n' "$checksum" "$archive" | /usr/bin/shasum -a 256 -c - >/dev/null
uid="$(/usr/bin/id -u)"
/bin/launchctl print "gui/$uid" >/dev/null
apps="$HOME/Applications"
agent_dir="$HOME/Library/LaunchAgents"
agent="$agent_dir/${bundle_id}.plist"
app="$apps/AppleHomeObserver.app"
rollback_root="$HOME/Library/Application Support/AppleHomeObserver-Deployment/rollback"
stage="$apps/.AppleHomeObserver-${token}.incoming"
rollback="$rollback_root/$(/bin/date -u +%Y%m%dT%H%M%SZ)-${token}"
/usr/bin/install -d -m 700 "$apps" "$agent_dir" "$rollback_root" "$stage" "$rollback"
/usr/bin/ditto -x -k --sequesterRsrc --rsrc "$archive" "$stage"
candidate="$stage/AppleHomeObserver.app"
[[ -d "$candidate" ]]
/usr/bin/codesign --verify --deep --strict "$candidate"
/usr/bin/codesign -d --entitlements :- "$candidate" 2>/dev/null > "$stage/entitlements.plist"
/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.homekit' "$stage/entitlements.plist" | /usr/bin/grep -qx true
[[ -f "$candidate/Contents/embedded.provisionprofile" ]]
had_app=0; had_agent=0
if [[ -e "$app" ]]; then /usr/bin/ditto "$app" "$rollback/AppleHomeObserver.app"; had_app=1; fi
if [[ -e "$agent" ]]; then /bin/cp -p "$agent" "$rollback/${bundle_id}.plist"; had_agent=1; fi
/usr/bin/printf '%s\n' "$had_app" > "$rollback/previous_app"
/usr/bin/printf '%s\n' "$had_agent" > "$rollback/previous_agent"
restore_previous() {
    /bin/launchctl bootout "gui/$uid/${bundle_id}" >/dev/null 2>&1 || true
    /bin/rm -rf "$app"
    if (( had_app )); then /usr/bin/ditto "$rollback/AppleHomeObserver.app" "$app"; fi
    if (( had_agent )); then /bin/cp -p "$rollback/${bundle_id}.plist" "$agent"; else /bin/rm -f "$agent"; fi
    if (( had_agent )); then /bin/launchctl bootstrap "gui/$uid" "$agent" >/dev/null 2>&1 || true; fi
}
/bin/launchctl bootout "gui/$uid/${bundle_id}" >/dev/null 2>&1 || true
if [[ -e "$app" ]]; then /bin/rm -rf "$app"; fi
if ! /bin/mv "$candidate" "$app"; then restore_previous; exit 1; fi
/bin/rm -f "$agent_dir/.AppleHomeObserver-${token}.plist"
APP_PATH="$app" BUNDLE_ID="$bundle_id" /usr/bin/python3 - "$agent_dir/.AppleHomeObserver-${token}.plist" <<'PY'
import os, plistlib, sys
plist = {"Label":os.environ["BUNDLE_ID"], "ProgramArguments":["/usr/bin/open","-g",os.environ["APP_PATH"]], "RunAtLoad":True}
with open(sys.argv[1], "wb") as stream:
    plistlib.dump(plist, stream, fmt=plistlib.FMT_XML, sort_keys=True)
PY
/bin/chmod 600 "$agent_dir/.AppleHomeObserver-${token}.plist"
if ! /bin/mv "$agent_dir/.AppleHomeObserver-${token}.plist" "$agent"; then restore_previous; exit 1; fi
if ! /bin/launchctl bootstrap "gui/$uid" "$agent"; then restore_previous; exit 1; fi
/bin/rm -rf "$stage"
/bin/rm -f "$archive"
/usr/bin/open "$app"
/usr/bin/printf 'Installed signed Apple Home Observer. Rollback snapshot: %s\n' "$rollback"
REMOTE
