# Tankarr Reader Mac runner

The `Tankarr Reader iOS` workflow uses the personal Apple Silicon Mac with these
labels: `self-hosted`, `macOS`, `ARM64`, `tankarr-reader`. The runner is
registered only in the private repository `Renzodef/tankarr-reader`.

## Requirements and registration

- Xcode installed in `/Applications/Xcode.app`, first launch completed and
  iOS SDK available. The normal flow does not need a simulator runtime.
  A runtime with iPhone and iPad is needed only for the optional UI tests.
- Homebrew Python 3 in `/opt/homebrew/bin/python3` and network access to GitHub
  and the Apple services. The workflow explicitly uses this interpreter to
  prepare the dependencies in a temporary virtual environment.
- Mac user with an open session, Mac awake and connection available
  for the whole duration of tests and distribution. The runner service must
  run in this user's session, which the simulators need.

Registration is managed in GitHub → repository → **Settings → Actions →
Runners → New self-hosted runner**, choosing macOS and ARM64 and adding
the `tankarr-reader` label. The expected directory on the Mac is
`~/Developer/actions-runner-tankarr-reader`. Use the instructions and the temporary
token shown by GitHub to register the runner and configure its
service; token and local configuration files stay out of the repository.
Check on the Runners page that all labels are present and the
status is **Idle** before starting a workflow.

## Execution and queue

The workflow starts only from relevant pushes to `main` and from `workflow_dispatch`;
it does not run pull request code. All jobs require the four
labels listed above. Concurrency is set on the whole workflow with
`cancel-in-progress: false`: only one test and distribution flow at a time,
without interrupting the one in progress. GitHub may replace a run still
pending with a more recent one from the same concurrency group.

The checks include the Python release safeguards, `swift test`, the
App Store assets and the iOS build for a generic device without signing.
Since 2 November 2026 Renzo verifies the interface on the real iPhone with TestFlight;
this manual verification is not claimed as run by CI. After the checks, pushes to `main`
distribute automatically to the internal TestFlight group. The default manual
action `verify` runs these checks and skips distribution; `testflight`
uploads a new build after the tests. `submit` requires an explicit version and build
that have already been tried and keeps the checks that prevent changing a version
already in review. Start `verify` from `main` to test the runner without
uploading another build to Apple. Select `simulator_ui` only to add
the iPhone/iPad UI tests with an already installed runtime; CI does not download runtimes.

If the Mac is off, offline or asleep, the job stays queued until the runner
is available again, within the limits of the GitHub queue. No backup hosted
runner is configured and no GitHub-hosted Mac minutes are consumed.

## Verification from the repository root

With an active virtual environment created from `/opt/homebrew/bin/python3` and the
Python dependencies listed in the workflow installed:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./run-tests.sh
python3 Tools/ci_build.py verify-device
```

`verify-device` regenerates the project and runs core, assets and iOS build
without simulators. Reading, background downloads, bookmarks and push
must then be tried on the TestFlight build on the iPhone before the public submission.

`verify` remains the optional command for core, assets and UI tests on the two
simulator families. UI results are in `build/results/`; the verification does not
require Apple credentials. Simulators already booted stay on; those
booted by CI are shut down at the end. CI does not delete simulators.
UI tests launch the app with `--demo` and change only the demo's progress and
bookmarks, without requests to the personal server.

## Signing and cleanup

The Apple Secrets are the same ones described in
[BUILD_AND_UPLOAD.md](../AppStore/BUILD_AND_UPLOAD.md) and are provided only
to the distribution step, after dependency installation and tests.
Signing uses a temporary keychain, P12, `.p8` key and profile with restrictive
permissions. Cleanup deletes the material created by CI even in case of
error and restores the keychain configuration.

An already present and identical provisioning profile is reused without
changing or removing it. A different profile at the same path makes
distribution fail: CI does not overwrite the Mac's personal profiles.
