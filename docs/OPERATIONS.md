# Operations and recovery

## Installation

Use the signed Mac Catalyst build in a logged-in user session. Register the destination Mac in the provisioning profile. Do not run HomeKit in a root daemon. Choose the intended Home and wait for two matching complete inventories before accepting a baseline.

Optional remote installation uses `script/prepare-install.sh` and `script/install-on-mini.sh` with ignored local deployment settings. The legacy script names support any configured Mac. Quit only the observer before updating. The installer validates signatures, profile device membership and transfer hashes, saves the predecessor app and login agent, and provides `script/rollback-on-mini.sh`. Rollback restores app files, not a live Home graph.

## Archives and key custody

The app stores Home-scoped AES-GCM archives in its sandbox Application Support directory. The private archive key is held in Keychain with ThisDeviceOnly protection. Keep an exported recovery key in independent secure storage, separate from the archive destination. Neither keys nor plaintext Home metadata belong in Git, monitoring or a backup-server payload.

Authenticate an isolated downloaded archive using `aho-verify --archive PATH --key-file PRIVATE_PATH`. Files must be owner-only. Verification prints aggregate counts and does not apply a restore. Test a tampered copy and require rejection. Full pairing and Apple-only configuration recovery is outside public API coverage.

## External backup

Configure `OBSERVER_ARCHIVE_ROOT` in a trusted fixed-command exporter installation. Use a dedicated source-restricted SSH key without general shell access, sudo or caller-controlled paths. Export only indexed encrypted `.aho` files. Validate paths, ownership, modes, format, duplicate names and bounded sizes before publishing. Archive format checks are distinct from cryptographic authentication.

An external service may schedule collection/upload and monitor receipt freshness and server verification. Keep deployment-specific schedules, hostnames, credentials, restore receipts and rollback locations in private infrastructure configuration. Prove recovery by downloading into isolated staging, comparing manifest/artifact hashes, and decrypting on a separate machine with the separately held key. A successful manual roundtrip does not prove future schedules or reboot recovery.

## Monitoring and investigation

Grant the app access only to its dedicated export folder. It exports owner-only health and bounded event logs; events may contain Home names and accessory IDs. No Full Disk Access is required. Removing access stops future export but leaves existing files for deliberate cleanup. Dashboard URLs are optional and stored locally.

Preserve accessory identity and timestamps before unpairing or resetting. Compare commands and physical response across controllers. Neither a callback nor a reported position proves actual movement. Mark deliberate configuration work before applying it. Keep live restore previews and interrupted-recovery journals separate from backup authentication tests.

## Accessibility

Isolated simulator audits use synthetic data, without HomeKit, Keychain, archive stores or desktop appearance changes. They cover shared SwiftUI controls; native Catalyst windows/toolbars and spoken VoiceOver behavior require separate acceptance. Known audit findings must be fixed or documented before release.

## Repeatable native acceptance

Install full Xcode and XcodeGen on the designated test Mac, complete Xcode's license/additional-component setup, and use its logged-in graphical session. Set DEVELOPER_DIR explicitly if needed. Run `OBSERVER_NATIVE_TEST_HOST=1 ./script/native-acceptance.sh`. This builds a separate ad-hoc signed `AcceptanceApp` without HomeKit entitlement. The preparation script consistently ad-hoc signs the isolated test runner and disables library validation only for that runner so it can load the locally built test bundle. macOS may require an explicit UI automation grant; a timeout enabling automation is a host setup failure, not a completed UI test. Its compilation flag forces synthetic mode even when no launch environment is supplied. Refresh, backup and restore operations are simulated; production observation and archive/key stores are not started.

The suite checks native screen accessibility, menu shortcuts, an in-app appearance transition, resizing/search and guarded recovery states. The appearance transition is app-local; a real system appearance transition still needs separate acceptance on the designated Mac. Result bundles stay in ignored build storage. Do not publish household screenshots or attach a public self-hosted runner to a household Mac.

For spoken VoiceOver acceptance, record the designated Mac's original VoiceOver, appearance and keyboard-navigation settings first. Review headings, navigation order, repeated snapshot action identification, disabled actions and dialog focus recovery using synthetic data. Restore those settings afterward. Automated audits and screenshots alone do not close this gate.

## Audit evidence and bounded false positives

The simulator suite covers six sections in empty/populated Light/Dark states and maximum text in both appearances. It runs contrast separately before trait-changing audits, then runs every remaining audit category. Fixed maximum-text checks include contrast and clipping; Dynamic Type mutation is covered by the standard matrix.

iOS 26/27 reproduced contrast false positives in native sidebar text. The suite identifies candidates through stable section and Home-selector identities, verifies that the reported text lies within the matching visible control and sidebar, then measures its pre-audit pixels. It requires at least 4.5:1 for normal text; measured light-mode examples include the Home caption at 6.71:1, selected Overview at 5.08:1 and unselected sections around 20:1. Missing elements, geometry mismatches, clipped text and insufficient contrast fail. Captures and ratios remain in the result bundle. This follows Apple's approach to investigating and narrowly filtering false positives: https://developer.apple.com/videos/play/wwdc2023/10035/?time=847 . Actual VoiceOver acceptance remains separate.

Successful installation atomically records its exact predecessor in the private deployment directory's latest pointer. Rollback validates this pointer and the predecessor signature before changing files. Invalid/incomplete records fail closed. For records created before the pointer existed, the most recent complete directory by install time is selected; UUID lexical order is never used.

Hosted simulator setup uses `script/create-audit-simulator.py`: select the newest available iOS runtime with compatible iPad Pro hardware from `supportedDeviceTypes`, falling back to numeric version bounds on older tooling. Never select hardware by reversing the global device list. `--dry-run` reports the destination without creating a device. Hosted core and compatibility tests run independently of the UI matrix.

Synthetic simulator fixtures explicitly select their Light/Dark color scheme as well as setting the simulator appearance. The hosted iOS 26.5 system-only appearance request produced light screenshots during dark-labeled runs; these screenshots did not establish dark coverage. App-local fixture appearance is separate from real system appearance acceptance on the designated Mac. Coverage identifiers use a labeled 44-point copy control rather than a small selectable-text target.
