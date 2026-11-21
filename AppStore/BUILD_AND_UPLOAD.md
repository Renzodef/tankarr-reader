# Build, TestFlight and App Store

The [Tankarr Reader iOS](../.github/workflows/tankarr-ios.yml) workflow
builds the code at the root of the `Renzodef/tankarr-reader` repository on the personal
ARM64 Mac, with Xcode in `/Applications/Xcode.app`. The runner dedicated to the
repository uses the labels `self-hosted`, `macOS`, `ARM64`, `tankarr-reader`.
The repository contains sources and metadata; the Apple credentials are in the
GitHub repository Secrets. Requirements, Mac availability and registration
are described in [Tools/CI_RUNNER.md](../Tools/CI_RUNNER.md).

## Automatic flow

1. A relevant push to `main` runs the Python release tests, `swift test`,
   the App Store materials check and the unsigned iOS build.
   It does not require simulator runtimes. These steps receive no Apple credentials.
   The workflow has no trigger on pull requests.
2. After the tests pass, it creates a signed archive, exports the IPA and
   uploads it to App Store Connect.
3. The workflow waits for Apple processing and adds the build to the configured
   **internal** TestFlight group. Testers receive the updates from
   TestFlight; on the device they can turn on automatic updates.

The automatic version comes from `AppStore/metadata.json`, field `version`.
The build number is computed by querying App Store Connect. Concurrency
is global to the workflow: only one test and distribution flow at a time, with
`cancel-in-progress: false`. GitHub may replace a run that is still
pending with a more recent push. If the Mac is offline or asleep, the jobs stay
queued without using hosted macOS runners or consuming their minutes.
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are passed to `xcodebuild`.

A push does not select builds for App Review, does not change the public metadata and
does not withdraw a version already in review.

## Manual run

In GitHub → Actions → **Tankarr Reader iOS** → **Run workflow**, always select
the `main` branch:

| Action | Version | Build | Result |
| --- | --- | --- | --- |
| `verify` (default) | Not used | Not used | Runs core, assets and iOS build without distributing; `simulator_ui` enables the iPhone/iPad UI path |
| `testflight` | Optional; otherwise from the metadata file | Optional; otherwise next Apple number | Builds, signs, uploads and distributes to the internal group |
| `submit` | Required, in the `X.Y.Z` format | Required, already present and tried in TestFlight | Selects that build and submits the public version to App Review |

`submit` reuses the existing build: it does not rebuild and does not upload a new
IPA. Before starting it, prepare the public version in App Store Connect,
complete screenshots, localizations, review notes, privacy, rating,
content rights and any obligations required by the account.
The workflow check rejects versions already in review and ineligible
builds. It does not create public versions and does not fill in declarations on behalf of the
account holder. Approval and availability on the App Store depend on Apple
and on the version's release settings.

For the next version number update `AppStore/metadata.json` and
`generate_project.py`, then regenerate the project. Apple allows creating
a new public version when the current one is ready for distribution.
A TestFlight build can then be used for the public release: the CI
export does not apply the «TestFlight Internal Only» restriction.

## Public version updates

TestFlight and the App Store are two distributions of the same bundle, but their
versions do not advance together. A push prepares a beta; it does not update the app
installed from the App Store. Every public update goes through App Review,
even after the first approval.

1. Group the tried changes into a stable version, for example
   `1.0.1` after `1.0.0`. Update the version in the metadata and in the generator,
   regenerate the project and leave tests and TestFlight upload to CI.
   A `1.0.0` build cannot be selected as the build of `1.0.1`:
   the marketing version must match too, not only the build number.
2. Try that build, including background downloads, offline bookmarks
   and, if configured, push on a real iPhone. The simulator is not enough for APNs.
3. Prepare the matching version in App Store Connect: IT/EN descriptions,
   what's new, consistent screenshots, privacy and notes for the reviewer. The
   `marketing_url` field in the metadata points to the public Tankarr project; do not
   link the Reader's private repository to users.
4. Explicitly start `submit` with the tried version and build. Prefer
   manual release if you want to control the moment of publication;
   the automatic option publishes after approval. Do not submit every push.
5. Users receive the update from the App Store, automatically if they
   allowed it or with Aggiorna (Update). No second app or
   new installation is needed. TestFlight remains the channel to try new features first.

### Changing only the App Store page

`AppStore/metadata.json` describes the current code: committing it does not publish
the description to Apple. Keep a copy of the metadata read from Apple
before updating it and verify the fields by reading them back after the change.

The promotional text (170 characters) can be changed even on the published
version. The full description and Marketing URL of `1.0.0` are locked
in `READY_FOR_SALE`: Apple returns HTTP 409 `STATE_ERROR`. Prepare those
fields on the next version, without claiming they are already visible on the Store.
On 2 November 2026 the IT/EN promotional text was updated with an
explanation of the server and `https://github.com/Renzodef/tankarr`. The public
support page contains the clickable link and the requirements.

Apple references: [version properties](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information),
[new version](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version/).

## Enabling followed-series notifications

Open a series and choose **Follow series**, then **Enable notifications** and
allow the iOS request. If consent was denied, use **Open
notification settings**: iOS does not show the popup again on every attempt.

A build with this feature and a gateway with APNs credentials
configured are required. If the server declares `push_notifications_available=false`,
the app shows that push is not configured and does not ask for a useless
consent. The App Store Connect API key used to upload builds is not
an APNs key: the operator must create a key with the Apple Push
Notification service enabled and keep it only in the gateway's private
configuration. iOS consent is per device and is not imported with the
configuration file. Follow stays saved even without push.

The initial public release `1.0.0 (2)` predates this feature; its
code is present in the later betas. Testing its delivery requires
a registered iPhone, consent, configured APNs and a real new chapter
imported after Follow; neither Follow alone nor an outbox test proves delivery.

## GitHub configuration

Repository Secrets:

| Name | Content |
| --- | --- |
| `TANKARR_ASC_PRIVATE_KEY` | Full PEM text of the App Store Connect `.p8` API key |
| `TANKARR_DISTRIBUTION_P12_BASE64` | Apple Distribution certificate with private key, P12 in base64 without line breaks |
| `TANKARR_DISTRIBUTION_P12_PASSWORD` | P12 password |
| `TANKARR_PROFILE_BASE64` | App Store profile for `app.tankarr.reader`, in base64 without line breaks |

Repository Variables:

| Name | Content |
| --- | --- |
| `TANKARR_ASC_KEY_ID` | API key ID |
| `TANKARR_ASC_ISSUER_ID` | Issuer ID of the team API key |
| `TANKARR_ASC_APP_ID` | Numeric ID of Tankarr Reader in App Store Connect |
| `TANKARR_ASC_BETA_GROUP_ID` | ID of the already configured internal TestFlight group |
| `TANKARR_TEAM_ID` | Apple Developer Program Team ID |

The internal group and its testers must exist in App Store Connect.
The API key must be able to upload builds and manage the app; the App Manager role
is sufficient. Certificate and profile must be renewed before expiry and
replaced in the Secrets. The workflow checks team, bundle ID, validity and
the match between certificate and profile before signing.

Python dependencies are installed before the secrets are introduced.
Distribution uses a temporary keychain and files with restrictive permissions;
cleanup removes keychains, P12, `.p8` and profiles created by CI even after an
error and restores the keychain configuration. An already present and
identical profile is reused without changing or removing it; a different profile
at the same path blocks distribution. Only the distribution
step on `main` receives the Secrets. The credentials are not in the test
arguments, in the artifacts or in the repository.

## Verification on the Mac

Since 2 November 2026 Renzo prefers to try the beta on the real iPhone to
save space on the Mac. The default verification builds for iOS without
installing runtimes. From the repository root, with Xcode initialized and
the Python environment described in the
[runner guide](../Tools/CI_RUNNER.md) active:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 Tools/ci_build.py verify-device
```

The command regenerates the project, runs core and asset tests and builds the app
for a generic iOS device without signing. It does not test the interface on a
device: before the public submission Renzo verifies the TestFlight build
on the iPhone, especially reading, background downloads, bookmarks and push.

The full path `python3 Tools/ci_build.py verify` remains available
when an iOS runtime with iPhone and iPad is installed, also by selecting
`simulator_ui` in the manual workflow. UI results stay in `build/results/`.
No Apple account is needed; simulators already running stay booted and
those booted by CI are shut down at the end, without erasing their data.
CI does not automatically download or reinstall removed runtimes.

References: [signing on GitHub Actions](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications),
[Apple build upload](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).
