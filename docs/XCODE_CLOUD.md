# Xcode Cloud TestFlight deployment

TestFlight builds for this app are produced and distributed through Xcode Cloud. Do not upload local archives or packages directly to App Store Connect.

## Repository setup

The committed `AppleHomeObserver.xcodeproj` lets Xcode Cloud discover the shared `AppleHomeObserver` scheme. `project.yml` remains the project source of truth. The executable `ci_scripts/ci_post_clone.sh` installs XcodeGen in the temporary Xcode Cloud environment when needed, then regenerates the project and its generated Info.plist files before Xcode builds.

## First-time onboarding in Xcode

Before opening the Cloud assistant, copy `Config/Local.xcconfig.example` to the ignored `Config/Local.xcconfig` and supply your registered bundle identifier and developer team. Run `xcodegen generate` to create the generated Info.plist files.

Xcode Cloud provides `CI_BUNDLE_ID` and `CI_TEAM_ID` only inside Cloud builds. A clean local checkout without `Local.xcconfig` resolves both values to empty strings. Selecting a team in the onboarding assistant does not fix the missing bundle identifier.

Apple also requires an explicit app-target bundle identifier for initial onboarding when an `.xcconfig` supplies it. In the app target's Signing & Capabilities pane, set the registered bundle identifier explicitly for both Debug and Release, enable automatic signing, and select your team. Keep this deployment-specific project override local; do not commit it. After onboarding, the committed variable-based configuration remains the portable source configuration and Cloud builds resolve identity from their predefined environment.

Verify local Release build settings before opening Integrate > Create Workflow: `PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM` must both be nonempty and match the registered app. Xcode should find the existing App Store Connect app. If it shows separate iOS and macOS products or fails at Select Product with an unexpected error, check the resolved identifier first.

The ignored `xcshareddata/xcodecloud` manifest is deployment-specific linkage created by Xcode. Workflow definitions live in Xcode Cloud and are not this manifest.

References: [Apple's first-workflow guide](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow), [project requirements](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud), and [predefined environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference).

## Workflow settings

Create an Xcode Cloud workflow for the Apple Home Observer app record with these settings:

- Repository: `https://github.com/eslutz/Apple-Home-Observer`
- Scheme: `AppleHomeObserver`
- Configuration: Release
- Build action: Archive, macOS, Any Mac (Mac Catalyst), with TestFlight (Internal Testing Only) distribution preparation
- Start condition: Manual, unless the owner later chooses a branch trigger
- Post-action: TestFlight Internal Testing, using the Mac Catalyst archive and an existing internal group. This uploads the build to TestFlight. Group membership is managed separately; do not invite users implicitly.
- Distribution: TestFlight internal testing; do not submit the app for App Review
- Clean: Off for internal testing, so later builds can reuse caches
- Environment values: Xcode Cloud supplies `CI_BUNDLE_ID` and `CI_TEAM_ID`; `Config/Defaults.xcconfig` maps them to the app's bundle identifier and signing team. Keep signing credentials in Xcode Cloud-managed signing, never in source control.

The internal TestFlight group and its membership are managed in App Store Connect. Add a build to the group only after Xcode Cloud reports a successful archive and App Store Connect finishes processing it. Use only the owner-approved internal group; an empty group can receive the build without sending tester invitations. Confirm membership before distributing to additional people.

## Validation

Before enabling distribution, run the workflow once and verify the Xcode Cloud build succeeds, App Store Connect shows the processed build, and the internal group lists that exact build. Future TestFlight deployments must start from Xcode Cloud.

## Versioning

Use semantic versioning (`MAJOR.MINOR.PATCH`) for `MARKETING_VERSION` in `project.yml`, starting at `1.0.0`. Keep `CURRENT_PROJECT_VERSION` separate: Xcode Cloud assigns its incrementing build number during archives. TestFlight therefore displays versions such as `1.0.0 (3)`. Uploaded builds retain their original version; changing source cannot rename an existing TestFlight build.
