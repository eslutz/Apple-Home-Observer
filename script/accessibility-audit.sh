#!/bin/bash
# Runs isolated synthetic-data audits in a simulator without opening Simulator.app.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${OBSERVER_AUDIT_DEVICE:?Set OBSERVER_AUDIT_DEVICE to an isolated iPad simulator UDID}"
task_test_options=(-only-testing:AccessibilityUITests/AccessibilityTests -skip-testing:AccessibilityUITests/AccessibilityTests/testOverviewContrast)
if [[ -n "${OBSERVER_AUDIT_TEST:-}" ]]; then
  task_test_options=(-only-testing:"AccessibilityUITests/AccessibilityTests/$OBSERVER_AUDIT_TEST")
fi
xcodegen generate
xcodebuild test -project AppleHomeObserver.xcodeproj -scheme AccessibilityAudit \
  -destination "platform=iOS Simulator,id=$OBSERVER_AUDIT_DEVICE" \
  -derivedDataPath build/audit -resultBundlePath "build/accessibility-$(date -u +%Y%m%dT%H%M%SZ).xcresult" \
  -collect-test-diagnostics never \
  "${task_test_options[@]}" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Automatic PROVISIONING_PROFILE_SPECIFIER=
