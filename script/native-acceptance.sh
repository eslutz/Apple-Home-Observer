#!/bin/bash
# Run only on the designated test Mac's logged-in graphical session.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${OBSERVER_NATIVE_TEST_HOST:?Set OBSERVER_NATIVE_TEST_HOST=1 on the designated test Mac}"
[[ "$OBSERVER_NATIVE_TEST_HOST" == 1 ]] || exit 2
xcodegen generate
xcodebuild build -project AppleHomeObserver.xcodeproj -scheme AcceptanceFixture \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/native
xcodebuild build-for-testing -project AppleHomeObserver.xcodeproj -scheme NativeAcceptance \
  -destination 'platform=macOS' -derivedDataPath build/native
python3 script/prepare-native-tests.py build/native/Build/Products
xcodebuild test-without-building -xctestrun build/native/Build/Products/NativeAcceptance.portable.xctestrun \
  -destination 'platform=macOS' \
  -resultBundlePath "build/native-$(date -u +%Y%m%dT%H%M%SZ).xcresult" -collect-test-diagnostics never
