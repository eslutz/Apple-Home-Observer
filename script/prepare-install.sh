#!/bin/bash
# Preparation only. Deploy after successful signing and Home permission onboarding.
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/Build/Products/Debug-maccatalyst/AppleHomeObserver.app"
[[ -d "$app" ]] || { echo 'Build the signed Catalyst app first' >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/codesign -d --entitlements :- "$app" 2>/dev/null > /private/tmp/apple-home-observer-entitlements.plist
/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.homekit' /private/tmp/apple-home-observer-entitlements.plist | /usr/bin/grep -qx true
[[ -f "$app/Contents/embedded.provisionprofile" ]] || { echo 'HomeKit provisioning profile missing' >&2; exit 1; }
mkdir -p dist
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" dist/AppleHomeObserver.zip
/usr/bin/shasum -a 256 dist/AppleHomeObserver.zip
