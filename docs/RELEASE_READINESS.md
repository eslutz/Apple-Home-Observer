# Release readiness — October 5, 2026

Scope: Mac Catalyst 1.0 (1), TestFlight preparation. Baseline source 15e7684, initially clean; Xcode 27.0 (27A266a). App Store Connect macOS record, bundle ID and SKU verified against local configuration. No upload or distribution performed.

## Initial findings

- R1 — Blocker, verified configuration defect: no PrivacyInfo.xcprivacy despite app-local UserDefaults and file metadata APIs. Add UserDefaults CA92.1 and FileTimestamp C617.1/3B52.1; verify the manifest is in the archive.
- R2 — Blocker, verified configuration gap: explicit version/build and distribution export validation missing. Set 1.0 (1), archive Release and validate its identity, signature, profile, privacy manifest and absence of acceptance fixtures. Local certificates currently include development identities only; final distribution signing requires an eligible distribution identity or Xcode-managed signing.
- R3 — Blocker for distribution, portal evidence: no build uploaded; description, support URL, screenshots, category, age ratings and review information incomplete. Prepare metadata for owner review. Check TestFlight information and privacy separately. Do not declare portal answers complete from source checks.

## Existing UI and recovery evidence

October 4–5 local synthetic audits cover six sections, empty/populated, Light/Dark, standard/maximum text. Native checks cover six sections, keyboard/search, 1200×850, 980×720 and 680×520 windows, and guarded restore confirmation. These are historical runtime results, not a newly distributed build test. The hosted audit engine timed out; hosted accessibility was removed at the owner's request. Actual VoiceOver testing was waived; do not claim VoiceOver support based on these checks.

Fresh core recovery suite: 38 passed. Packaging/deployment/compatibility suite: 12 passed. Core tests cover different Home rejection, stale previews, explicit replacement mappings, incomplete inventory, authenticated archives, tampering, pending journal reload, cleanup order, unjournaled/aliased ID rejection and predecessor verification. No live Home restore was applied. Fixture behavior and cryptographic recovery do not prove a real HomeKit rollback.

## Apple guidance reviewed

- [Distribution and Catalyst archives](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases/)
- [Required reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [Encryption export guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)

The app uses Apple CryptoKit AES-GCM and Security Keychain, with no third-party crypto implementation. The proposed export declaration is exempt OS-provided encryption. Owner review of the declaration remains separate from archive validation.

## Fresh archive results

Initial Release archive built successfully; deep strict signature validation passed. Embedded version is 1.0 (1); display name includes spaces; app has HomeKit, sandbox, network-client and user-selected-folder entitlements. PrivacyInfo.xcprivacy is included in Contents/Resources; dSYM is present. The embedded profile is development-only (registered devices, get-task-allow=true), so it must be re-signed/exported for App Store Connect before distribution. This is not a TestFlight-valid export yet.

R1 resolved in source and initial archive. R2 version/build resolved; distribution signing remains pending. The final Release archive includes the Utilities application category and no longer reports the missing-category warning. Intentional legacy HomeKit timezone reads and skipped App Intents metadata extraction remain documented; neither is suppressed.

Registered App Store Connect name was changed and saved as Apple Home Observer at the owner's request. Bundle ID and SKU match the established registered values. TestFlight reports no submitted builds. Public metadata, privacy policy and beta test/review copy are prepared in TESTFLIGHT_PREPARATION.md and PRIVACY.md for owner review; portal submission remains separate.

## Follow-up on October 5

The mini has matching Apple Development and Apple Distribution identities. A signing probe exposed a missing WWDR G3 intermediate; installed the Apple-provided intermediate after verifying it against the existing system trust chain. Both identities now pass `security find-identity -v -p codesigning`. Remote signing still returns `errSecInternalComponent`; private-key access must be verified in the logged-in session before export. No trust overrides or replacement certificates were created.

The live Home selector menu correctly checks the selected Home while the closed picker displays its placeholder. Replaced the closed picker with an explicit selected-name Menu label while retaining the selection Picker inside it. Release and signed Debug builds pass. Deployed through the rollback-protected installer and verified that the closed menu now displays the selected Home after relaunch. The installed icon resource matches the freshly compiled icon by SHA-256 and renders the intended house/cards design; the Dock still displays a generic placeholder, so runtime icon acceptance remains open. Re-registered the installed bundle with Launch Services without resetting its database.

## Distribution export follow-up

Transferred the verified Release archive to the mini and attempted an export with method `app-store-connect`, destination `export`, automatic signing, and no version/build-number management or upload. Selected the mini's installed Xcode per command with DEVELOPER_DIR; the system developer directory remains unchanged. Xcode downloaded an App Store Catalyst profile: HomeKit=true, get-task-allow=false, no registered devices, expiration October 5, 2027. Export reached codesign but failed with errSecInternalComponent. This is not an exported distributable artifact; login-keychain/private-key access remains the blocking prerequisite.

Rechecked Release archive signature, version/build, display name, encryption declaration and embedded privacy manifest. All pass. Source-based privacy review supports the prepared Data Not Collected answer under Apple's definitions; no portal answer has been published. Added local-only synthetic release screenshot capture; compilation and runtime image acceptance are separate gates. Desktop control currently cannot continue because it reports a locked Mac.

## Successful distribution export and validation

The owner completed the login-keychain authorization prompt. The signing probe passed in the mini's desktop session; the same session exported the archive successfully using `app-store-connect` with destination `export`. No upload occurred. Expanded the exported installer without installing it: installer certificate chain validation passed, and the packaged app passes deep strict signature verification. Its bundle identity, team, version 1.0 (1), HomeKit and sandbox entitlements match the release configuration; `get-task-allow=false`. The privacy manifest is present. A copy of the installer was transferred to the laptop for review.

The isolated release screenshot run reached XCTest but timed out enabling UI automation before executing tests. No screenshot acceptance is claimed; the mini's native authorization prompt must be completed before a fresh capture run. VoiceOver remains waived. Runtime Dock icon acceptance and release screenshot review are still open.

## Latest acceptance status

The final archive includes the recovery-preview label polish and exported successfully to a signed App Store Connect installer. Fresh deep strict verification of the packaged app passes; version is 1.0 (1). Nothing has been uploaded. Earlier signing failures above are historical and resolved.

The synthetic screenshot test now passes: one test, zero failures, six Light/Dark Overview, Backups and Recovery captures at 2560×1600. Earlier automation authorization failures above are resolved. Captures use the isolated acceptance target and sample inventory; real Home data is excluded. Final visual review remains separate from test success.

The final signed Debug build was installed on the mini through the rollback-protected installer on October 5 at 12:23 UTC. The installed production Dock icon was subsequently verified after the icon registration/cache follow-up below.

Final package audit passed for identity/version, HomeKit and sandbox entitlements, get-task-allow=false, an App Store profile without registered devices, an embedded nontracking privacy manifest and absence of an acceptance bundle. Installer SHA-256: `62f45aeb9c9033547226f5f450dad8a056a000e12ac2d1c4f4af132f4da8ee3e`. Final screenshot review found no clipping or private household/desktop content in the six synthetic captures.

Owner review materials are saved under ignored `dist/release-review/`: signed installer, six screenshots, privacy policy and metadata drafts. The production Dock icon check subsequently passed; the preparation requirements for steps 1–3 are complete. App Store Connect upload, portal metadata publication and tester distribution are deliberately outside this preparation stage.

## Production icon acceptance completed

Finder rendered the approved layered house/cards icon, while the production Dock entry initially retained a generic icon. The isolated acceptance app rendered correctly. Both bundles contain the Icon Composer layers and matching icon metadata. Restarting icon services, unregistering 27 duplicate production app registrations and rebuilding the Dock cache alone did not immediately change the running production icon. The previous Dock icon cache was preserved for rollback; no global Launch Services database was erased.

An unchanged signed production app copied to a fresh temporary path displayed the correct Dock icon. After unregistering that probe, refreshing the installed bundle modification timestamp and re-registering the installed path, the installed app also displayed the correct Dock icon. Its process path was confirmed as the normal user Applications installation and deep strict signature verification passed. The selected Home label remained correct and inventory returned to 133 accessories. Evidence supports stale path registration/cache rather than an icon source defect; the exact responsible cache is not isolated. No icon artwork or signing configuration was changed during this diagnosis.

Steps 1–3 preparation audit: final distribution export and package verification pass; installed Home selection and production icon checks pass; privacy manifest, policy, metadata/beta copy and six reviewed synthetic screenshots are prepared. VoiceOver remains waived. Upload, App Store Connect processing and publication/distribution still require owner review and are not claimed complete.
