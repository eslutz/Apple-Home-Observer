import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("audit_selector", Path(__file__).resolve().parents[1] / "script/create-audit-simulator.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class AuditSimulatorSelectionTests(unittest.TestCase):
    def runtime(self, number, allowed, available=True):
        return {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-" + number,
                "version": number, "name": "iOS " + number, "isAvailable": available,
                "supportedDeviceTypes": [{"identifier": item} for item in allowed]}
    def devices(self):
        return [{"identifier": "obsolete", "name": "iPad Pro", "minRuntimeVersion": 0},
                {"identifier": "m4", "name": "iPad Pro 11-inch (M4)", "minRuntimeVersion": 17 << 16},
                {"identifier": "m5", "name": "iPad Pro 11-inch (M5)", "minRuntimeVersion": 26 << 16}]
    def test_runtime_compatibility_overrides_device_list_order(self):
        runtime, device = module.choose([self.runtime("26.5", ["m4", "m5"])], self.devices())
        self.assertEqual(device["identifier"], "m5")
    def test_unsupported_newer_device_is_not_selected(self):
        _, device = module.choose([self.runtime("26.5", ["m4"])], self.devices())
        self.assertEqual(device["identifier"], "m4")
    def test_newest_available_version_not_reversed_list_order(self):
        runtime, _ = module.choose([self.runtime("27.0", ["m5"]), self.runtime("26.5", ["m4"]),
                                   self.runtime("28.0", ["m5"], False)], self.devices())
        self.assertEqual(runtime["version"], "27.0")
    def test_legacy_metadata_uses_numeric_version_bounds(self):
        runtime = self.runtime("17.5", [])
        del runtime["supportedDeviceTypes"]
        _, device = module.choose([runtime], self.devices())
        self.assertEqual(device["identifier"], "m4")
