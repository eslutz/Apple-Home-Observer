# Configuration

| Value | Location | Behavior |
| --- | --- | --- |
| Bundle ID, developer team, signing style/profile | Ignored `Config/Local.xcconfig` | Overrides portable `Config/Defaults.xcconfig`; preserve bundle ID across upgrades. |
| Monitoring export folder | `OBSERVER_MONITORING_FOLDER` in local xcconfig | Relative path under the account home; defaults to `.local/state/apple-home-observer`. Requires explicit folder access. Changing the path requires granting access again. |
| Dashboard URL | Monitoring screen | Stored locally in UserDefaults; optional HTTPS URL without embedded credentials. |
| Remote deployment host and bundle ID | Ignored `Config/deployment.env` or environment | Required by install/rollback scripts. Copy the example; the host is not embedded in source. |
| Encrypted export source | `OBSERVER_ARCHIVE_ROOT` environment | Configure a fixed path at deployment; do not allow remote callers to choose paths. |

Never place recovery keys, API tokens, SSH private keys, provisioning profiles or household exports in these examples. Local config, runtime files, archives and generated Xcode projects are ignored. Build settings are not a secret-storage mechanism: do not embed credentials in the app bundle.
