#!/usr/bin/env python3
"""Reject private artifacts and obvious credentials in the committed public tree.

This is a guardrail, not a complete secret detector or privacy review.
"""
import re
import subprocess
import sys
from pathlib import Path

names = subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0")
patterns = [rb"-----BEGIN (?:[A-Z ]+)?PRIVATE KEY-----", rb"gh[pousr]_[A-Za-z0-9]{30,}",
            rb"AKIA[A-Z0-9]{16}", rb"AHO-RECOVERY-v1\n[A-Za-z0-9+/]{43}=",
            rb"/Users/[A-Za-z0-9._-]+/", rb"(?:[a-zA-Z0-9-]+\.)+home\.arpa"]
failures = []
for name in names:
    if not name: continue
    path = Path(name)
    if any(part in (".runtime", ".secrets", "build", "dist", "xcuserdata") for part in path.parts) or path.name in ("Local.xcconfig", "deployment.env") or path.suffix in (".aho", ".recovery-key", ".key", ".p12", ".provisionprofile", ".mobileprovision"):
        failures.append(name); continue
    data = subprocess.check_output(["git", "show", ":" + name])
    if any(re.search(pattern, data) for pattern in patterns): failures.append(name)
if failures:
    print("Publication blocked; review these paths (contents withheld):")
    print("\n".join(failures)); sys.exit(1)
print("Public tracked-file privacy guard: PASS")
