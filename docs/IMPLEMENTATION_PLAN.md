# Release acceptance gates

- Build and sign the optimized Mac Catalyst target with local developer configuration.
- Pass core, archive authentication, malformed-key, inventory and interrupted-recovery tests.
- Verify Home permission, complete inventory, encrypted baseline and independent recovery-key custody on the intended installation.
- Prove isolated external-backup download/authentication and independently observe scheduled runs and reboot recovery.
- Resolve accessibility audit findings, then verify native Light/Dark, window sizing, keyboard and assistive-technology navigation.
- Validate restore previews, mappings, journal recovery and rollback separately from applying any live Home changes.
- Review App Store metadata, entitlement/provisioning scope and privacy disclosures before distribution.

Do not interpret source tests, a signed build or a manual recovery roundtrip as full production acceptance.
