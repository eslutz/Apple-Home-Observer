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
