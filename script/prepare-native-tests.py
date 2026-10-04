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
(root / "NativeAcceptance.portable.xctestrun").write_bytes(plistlib.dumps(manifest))

# Xcode copies an Apple-signed runner. Ad-hoc test bundles cannot pass its
# library validation until the isolated runner is signed consistently.
runner = root / "Debug-maccatalyst/NativeAcceptanceTests-Runner.app"
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
