# Xcode Cloud TestFlight deployment

TestFlight builds for this app are produced and distributed through Xcode Cloud. Do not upload local archives or packages directly to App Store Connect.

## Repository setup

The committed `AppleHomeObserver.xcodeproj` lets Xcode Cloud discover the shared `AppleHomeObserver` scheme. `project.yml` remains the project source of truth. The executable `ci_scripts/ci_post_clone.sh` installs XcodeGen in the temporary Xcode Cloud environment when needed, then regenerates the project and its generated Info.plist files before Xcode builds.

## Workflow settings

Create an Xcode Cloud workflow for the Apple Home Observer app record with these settings:

- Repository: `https://github.com/eslutz/Apple-Home-Observer`
- Scheme: `AppleHomeObserver`
- Configuration: Release
- Build action: Archive
- Start condition: Manual, unless the owner later chooses a branch trigger
- Distribution: TestFlight internal testing; do not submit the app for App Review
- Environment values: Xcode Cloud supplies `CI_BUNDLE_ID` and `CI_TEAM_ID`; `Config/Defaults.xcconfig` maps them to the app's bundle identifier and signing team. Keep signing credentials in Xcode Cloud-managed signing, never in source control.

The internal TestFlight group and its membership are managed in App Store Connect. Add a build to the group only after Xcode Cloud reports a successful archive and App Store Connect finishes processing it. Keep automatic distribution off until the owner confirms the intended tester list.

## Validation

Before enabling distribution, run the workflow once and verify the Xcode Cloud build succeeds, App Store Connect shows the processed build, and the internal group lists that exact build. Future TestFlight deployments must start from Xcode Cloud.
