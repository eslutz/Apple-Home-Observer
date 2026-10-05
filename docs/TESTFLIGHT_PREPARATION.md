# TestFlight metadata draft

Platform: macOS, Mac Catalyst. Version 1.0, build 1. Preserve the registered bundle ID and SKU from ignored local developer configuration.

## Public copy for owner review

Subtitle: Encrypted Home recovery history

Description:

Apple Home Observer keeps an encrypted recovery history of supported Apple Home configuration and helps investigate unexpected accessory changes.

Capture stable inventories, track changes to accessory names and room assignments, and inspect reported blind positions alongside command observations. Export encrypted backups and keep a separate recovery key for independent archive verification. Optional folder exports connect to monitoring services you configure.

Recovery starts with a preview and explicit accessory mappings. Applying supported changes requires confirmation. Apple-only settings, pairing identities and unsupported automations may require manual recovery; this app is not a complete Apple Home or iCloud backup. Reported device state does not prove physical movement.

Requires Apple Home access in a logged-in macOS session. No separate app account or developer-hosted service is required.

Keywords: homekit,home,backup,recovery,automation,lights,blinds,monitoring

Category: Utilities

Support URL: https://github.com/eslutz/Apple-Home-Observer/issues

Marketing URL: https://github.com/eslutz/Apple-Home-Observer

Privacy policy URL, after publication: https://github.com/eslutz/Apple-Home-Observer/blob/main/PRIVACY.md

Copyright: 2026 Eric Slutz

## Beta test information

What to test: Home permission and stable inventory loading; encrypted backup creation; recovery-key export to separate secure storage; read-only restore preview and explicit mappings; monitoring folder permission and export freshness. Confirm app relaunch retains Home selection. Do not apply restore changes to an important Home merely to test. Use a disposable Home for any destructive recovery testing.

Review notes: No separate app sign-in is required. Grant Home access and choose an available Home. A Home without supported accessories may show an empty inventory. Accessory diagnostics require paired devices; physical movement must be checked independently. Exported archives and recovery keys contain sensitive household data and must not be submitted with feedback.

Prepared App Privacy answer: Data Not Collected. Source inspection found no developer endpoint, networking client, analytics/tracking SDK or third-party dependency. HomeKit reads, local encrypted archives and user-selected folder exports do not give the developer or an integrated third-party partner access to household data. The developer does not collect those files. Apple defines collection as off-device transmission that gives the developer or its partners access beyond servicing a request; on-device processing does not require disclosure. User-configured synchronization or monitoring outside the app is disclosed in PRIVACY.md. Reassess this answer if a hosted service or SDK is added. Publishing remains subject to owner review.

Export proposal: Uses OS-provided CryptoKit/Security encryption only; no proprietary or third-party algorithm implementation. Info.plist declares ITSAppUsesNonExemptEncryption=false. Confirm at distribution review.

Screenshots: capture synthetic, clearly representative macOS Overview, Backups and Recovery screens in an accepted Mac resolution. Never upload real Home names, accessory identifiers or desktop content. Contact details, age-rating questionnaire and tester group need owner review in App Store Connect. Do not advertise unverified VoiceOver support.

## Distribution boundary

Archive and local validation are preparation only. Before upload, verify an App Store-compatible signing profile and distribution identity. Before assigning testers or submitting for review, obtain owner review of the concrete archive and metadata. No TestFlight build is available until Apple processes an uploaded build.

## Review answers and release capture

- App account sign-in: not required. App Review's sign-in checkbox should be off; no app username or password should be supplied. Apple Home access is an OS permission and requires the review device's own Home configuration.
- Content rights: the app does not contain, display or access third-party media content. Household configuration is user-authorized HomeKit data.
- Age-rating draft: no advertising, messaging/social networking, public user-generated content, gambling, contests, violence, sexual content, profanity, drugs or medical advice. No embedded unrestricted web browser; a configured dashboard opens in the system browser. Do not market specifically to children. Confirm the actual portal questionnaire and calculated rating before saving.
- Beta review contact: use the owner's private contact details in App Store Connect only; do not add email/phone or account credentials to public source.
- Availability, pricing, trader status and tester assignment: retain existing settings until owner review.
- Release screenshot capture: run only `NativeAcceptanceTests/testReleaseScreenshots` with the isolated AcceptanceApp. Its bundle has no HomeKit entitlement and the fixture avoids live archives, Keychain and monitoring exports. It captures three pages in Light and Dark at a requested 1280×800 native window size and rejects any PNG dimensions outside Apple's Mac list. Export the test attachments, inspect each image for clipping and private content, and select the three Light images for the first review package; Dark images are alternatives. Do not upload test logs or desktop screenshots.

Apple references checked October 5, 2026:

- [App Privacy definitions and on-device processing](https://developer.apple.com/app-store/app-privacy-details/)
- [Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) — 1280×800, 1440×900, 2560×1600 or 2880×1800 pixels.

The public privacy policy URL is a planned destination until PRIVACY.md is published; verify the URL returns the final policy before copying it to App Store Connect.
