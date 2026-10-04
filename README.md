# Apple Home Observer

A Mac Catalyst app for encrypted Apple Home configuration snapshots, recovery previews, metadata drift detection and blind-command diagnostics. Built with SwiftUI and public HomeKit APIs.

## Build

Requires macOS, Xcode with Mac Catalyst support, and XcodeGen. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, set your bundle ID and Apple developer team, and enable HomeKit for that identifier. Local configuration is ignored by Git. Run `./script/build_and_run.sh --build-only`. Sign and provision for the Mac that will run the app; an unsigned build cannot validate HomeKit access.

The generic `org.example` identifier is a build placeholder. Keep your production identifier stable: changing it changes the sandbox and Keychain namespace. Existing installations must use their original identifier to retain access to archives and keys.

## Use

Grant Home Data permission, select a Home and wait for two matching complete inventories. Export the recovery key to independent secure storage. In Monitoring, optionally configure an HTTPS dashboard URL and grant access to the dedicated export folder. Keys and encrypted snapshots are never part of monitoring exports.

See [operations](docs/OPERATIONS.md), [configuration](docs/CONFIGURATION.md), [design](docs/DESIGN.md) and [release gates](docs/IMPLEMENTATION_PLAN.md).

## Verify

```
swift build --disable-sandbox --product aho-verify
swift test --disable-sandbox
python3 -m unittest discover -s Tests -p 'test_*.py'
```

The verifier rejects malformed keys and unauthenticated archives. For synthetic accessibility testing, set `OBSERVER_AUDIT_DEVICE` to an isolated iPad simulator UUID and run `./script/accessibility-audit.sh`.

## Limits

Public HomeKit APIs cannot clone pairing credentials, every Apple-only automation, hub configuration, resident permissions, camera recording, favorites or all Home UI settings. Reported positions do not prove physical movement. Live restoration and native accessibility acceptance require separate validation. This repository is prepared for open-source development; it is not a claim of completed production or App Store release acceptance.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Licensed under MIT.
