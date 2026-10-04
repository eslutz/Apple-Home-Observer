#!/usr/bin/env python3
"""Normalize Xcode's mixed macOS-runner/Catalyst-app generated test path."""
from pathlib import Path
import plistlib
import sys
import subprocess
root = Path(sys.argv[1])
files = [p for p in root.glob("NativeAcceptance_*.xctestrun")]
if len(files) != 1: raise SystemExit("Expected exactly one native test manifest")
manifest = plistlib.loads(files[0].read_bytes())
target = manifest["NativeAcceptanceTests"]
app = root / "Debug-maccatalyst/AcceptanceApp.app"
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
if info["CFBundleIdentifier"] != "org.example.AppleHomeObserver.Acceptance": raise SystemExit("Unexpected acceptance app identity")
entitlements = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(app)], check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout
if entitlements and plistlib.loads(entitlements).get("com.apple.developer.homekit"):
    raise SystemExit("Acceptance app must not have HomeKit entitlement")
target["UITargetAppPath"] = "__TESTROOT__/Debug-maccatalyst/AcceptanceApp.app"
# The test bundle/runner are macOS binaries even though the app is Catalyst.
# Remove a Catalyst platform override from the genuine macOS runner.
# Invalid AX coordinates persisted after correcting the binary platforms;
# this normalization alone does not prove native interaction acceptance.
target.get("TestingEnvironmentVariables", {}).pop("DYLD_FORCE_PLATFORM", None)
(root / "NativeAcceptance.portable.xctestrun").write_bytes(plistlib.dumps(manifest))

# Xcode copies an Apple-signed runner. Ad-hoc test bundles cannot pass its
# library validation until the isolated runner is signed consistently.
runner = root / "Debug/NativeAcceptanceTests-Runner.app"
# Fail closed if a future destination again compiles either test binary as Catalyst.
for bundle in [runner, runner / "Contents/PlugIns/NativeAcceptanceTests.xctest"]:
    bundle_info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    executable = bundle / "Contents/MacOS" / bundle_info["CFBundleExecutable"]
    build_info = subprocess.check_output(["xcrun", "vtool", "-show-build", str(executable)], text=True)
    if "platform MACOS" not in build_info or "platform MACCATALYST" in build_info:
        raise SystemExit("Native test runner and bundle must be macOS binaries")
runner_entitlements = subprocess.run(
    ["codesign", "-d", "--entitlements", ":-", str(runner)], check=True,
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout
values = plistlib.loads(runner_entitlements) if runner_entitlements else {}
values["com.apple.security.cs.disable-library-validation"] = True
entitlement_file = root / "NativeAcceptance.runner.entitlements"
entitlement_file.write_bytes(plistlib.dumps(values))
subprocess.run(["codesign", "--force", "--sign", "-", "--entitlements",
                str(entitlement_file), str(runner)], check=True)
subprocess.run(["codesign", "--verify", "--strict", str(runner)], check=True)
