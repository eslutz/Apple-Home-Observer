#!/usr/bin/env python3
"""Choose a new isolated iPad from the runtime's actual compatibility metadata."""
import argparse
import json
import os
import re
import subprocess


def version(value):
    parts = [int(part) for part in value.split('.')]
    return tuple((parts + [0, 0, 0])[:3])


def choose(runtimes, device_types):
    available = sorted((runtime for runtime in runtimes if runtime.get('isAvailable') and
                        runtime['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')),
                       key=lambda runtime: version(runtime['version']), reverse=True)
    for runtime in available:
        allowed = runtime.get('supportedDeviceTypes')
        identifiers = {item['identifier'] for item in allowed} if allowed is not None else None
        major, minor, patch = version(runtime['version'])
        encoded = (major << 16) | (minor << 8) | patch
        candidates = [device for device in device_types if device['name'].startswith('iPad Pro') and
                      ((device['identifier'] in identifiers) if identifiers is not None else
                       device.get('minRuntimeVersion', 0) <= encoded <= device.get('maxRuntimeVersion', 0xffffffff))]
        if candidates:
            def rank(device):
                chip = re.search(r'\(M(\d+)\)', device['name'])
                return (device.get('minRuntimeVersion', 0), int(chip.group(1)) if chip else 0,
                        '11-inch' in device['name'], device['identifier'])
            return runtime, max(candidates, key=rank)
    raise RuntimeError('No available iOS runtime has a compatible iPad Pro')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j']))['runtimes']
    types = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devicetypes', '-j']))['devicetypes']
    runtime, device = choose(runtimes, types)
    print('Audit destination:', runtime['name'], '/', device['name'])
    if args.dry_run:
        return
    identifier = subprocess.check_output(['xcrun', 'simctl', 'create', 'Observer Audit',
                                         device['identifier'], runtime['identifier']], text=True).strip()
    if 'GITHUB_ENV' in os.environ:
        with open(os.environ['GITHUB_ENV'], 'a') as output:
            output.write('OBSERVER_AUDIT_DEVICE=' + identifier + '\n')
    else:
        print('OBSERVER_AUDIT_DEVICE=' + identifier)


if __name__ == '__main__':
    main()
