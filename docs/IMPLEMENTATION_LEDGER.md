# Implementation status

Implemented: authenticated encrypted archives, stable-inventory gating, recovery-key codec, offline verifier, guarded restore previews/journals, monitoring exports, external ciphertext packaging and a layered Icon Composer asset.

## Verification on October 4, 2026

Core tests: 38 passed. Ciphertext packaging, deployment rollback and simulator compatibility tests: 12 passed. Rollback selects the predecessor recorded for the last successful installation, validates its signature and login-agent presence before changing files, and rejects invalid or incomplete records. Legacy records use install time rather than random UUID order.

The isolated iPad regression passed all 24 empty/populated screens across Light/Dark and all 12 maximum-accessibility-text screens. Recovery confirmation independently passed in both appearances at standard and maximum text sizes. Standard-size runs cover Dynamic Type mutation; forced maximum-text fixtures check rendered contrast, element detection, hit regions, descriptions, clipping and traits. A focused follow-up for the final storage-disclosure change passed in both appearances at both text sizes, including scrolling and expanded/collapsed state announcements.

Native Catalyst acceptance passed all six populated screens in Light and Dark, guarded recovery fixtures, Command-R and Shift-Command-B, search, actual window sizes of 1200×850, 980×720 and 680×520, and macOS Fill/Left window layouts. The fixture has no HomeKit entitlement or live Home operations. The final coverage layout/disclosure also passed a separate native Light/Dark regression. Builds and signed-package validation passed. Production installation is verified separately from these synthetic tests.

Fixes include semantic Home/blind pickers, scalable in-page recovery confirmation with Escape cancellation, higher-contrast slider endpoints and identifier captions, an explicitly labeled storage disclosure, reset scroll position when changing pages, and compact navigation that dismisses its overlay after selecting a page. Maximum-text scrolling exposed an app event-loop stall in the coverage page’s lazy layout; a regular outer stack removes the reproduced loop and the focused scroll regression passes. Native scene sizing uses public UIWindowScene geometry and size-restriction APIs. Acceptance-only commands request test sizes and expose the scene’s actual observed geometry; production contains neither test commands nor geometry metadata.

## Accessibility evidence limits

The accessibility handlers do not broadly ignore audit categories. Reproduced sidebar contrast warnings require a known control identity or its matching text child, containment in its captured row/sidebar/window, and independently measured pre-audit pixels meeting 4.5:1. Native dark sidebar labels measured approximately 11.25–11.40:1. The native toolbar-title handler additionally requires the exact direct-window title field, its AX value and toolbar geometry; a reported Backups title measured 8.45:1. Unidentified, hidden, clipped or insufficient-contrast controls still fail. Pixel crops and household screenshots remain private.

A minimal text/button Catalyst control independently reproduced the disabled, unlabeled system wrapper above the named UIKit window. Only that exact disabled group structure is excluded from description findings; app controls remain audited. The Home and blind pickers and storage disclosure were fixed in app source rather than excluded.

Actual VoiceOver navigation and speech remain an acceptance gate. Direct remote interaction awaits owner approval after automatic approval review rejected clicks whose remote targets it could not independently verify. Automated semantic/contrast audits do not establish that result. The signed candidate was installed with a preserved predecessor, verified signature and matching executable hash. Fresh live health confirmed authorization and a ready inventory. The final successor passed the same signature and executable-hash checks. Fresh private and exported health report authorization and a ready inventory.

## Monitoring export follow-up

Live validation exposed stale export files despite fresh private health. Value-free diagnostics identified a dedicated-folder mismatch. The custom monitoring-folder build setting was absent from the generated app Info.plist, causing an unintended runtime fallback. Both app targets now explicitly embed the configured key, and packaging rejects missing, unresolved or unsafe relative values. The signed deployment restored fresh exported health with logging healthy, using the existing folder bookmark without another grant. Valid stale bookmarks can be renewed only after successful scoped access and validation of the same dedicated folder, ownership, type and private permissions. Resolution, scope and validation failures produce value-free unified-log diagnostics; bookmarks and paths are not logged.

## Hosted baseline and remaining gates

[Run 37231487527](https://github.com/eslutz/Apple-Home-Observer/actions/runs/37231487527) passed core and accessibility jobs for commit `a13c07fa6de2f4823c46627bf17c082e661662f6`. This is evidence for the published baseline; the local results above cover the subsequent candidate. New hosted verification remains separate.

Other remaining gates: independent scheduled/reboot backup acceptance, live Home restore acceptance and TestFlight preparation. No live Home changes were used for UI tests. Household identifiers, credentials, recovery keys, deployment records and desktop evidence stay outside public source.
