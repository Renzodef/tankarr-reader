# Tankarr Reader — iOS client development

Public repository of the SwiftUI app for iPhone and iPad, iOS 17+.
Push directly to `main`, without force; no branches/PRs/issues unless requested.
Install the pre-push check: `git config core.hooksPath .githooks`.
`./run-tests.sh` checks the whole Python suite and the assets; `PYTHON` can
point to the virtual environment's interpreter. Do not skip the hooks.
The bundle ID stays `app.tankarr.reader`: TestFlight and the App Store use the same
existing Apple record. The server lives in `Renzodef/tankarr`; the home stack
configuration lives in `Renzodef/self-hosted`.

## Environment and structure

- Identify the machine with `hostname`, `uname -m` and, if present,
  `/proc/device-tree/model` before operational work.
- iOS builds and UI tests require macOS/Xcode. The Python release tests
  also work on Linux and do not contact Apple.
- `App/`: SwiftUI interface and resources; `Sources/`: shared core;
  `Tests/`: Swift tests; `UITests/`: UI tests; `tooling_tests/`: Python release tests.
- `generate_project.py` regenerates `TankarrReader.xcodeproj`; run it after
  adding or removing sources or resources managed by the generator.
- This repository contains no server production scripts. Do not
  modify or restart the home stack for client-only work.

## Verification

Use a Python environment with `pytest`, `requests` and `cryptography` installed.
The CI versions are pinned in `.github/workflows/tankarr-ios.yml`.

```sh
python3 -m pytest tooling_tests/test_tankarr_ios_ci.py tooling_tests/test_tankarr_ios_release.py -q
python3 Tools/check_store_assets.py
```

Renzo's decision of 2 November 2026: to save space and speed up
TestFlight, CI uses `python3 Tools/ci_build.py verify-device`: core tests,
assets and iOS compilation without simulator runtimes. Renzo tries the
TestFlight build on the iPhone before the public submission; do not claim those
manual tests were run by the agent. Compilation does not prove background
downloads, push or navigation on a device.

`python3 Tools/ci_build.py verify` remains available for the full path
with iPhone/iPad UI tests in the same iOS runtime, also through the
manual `simulator_ui` option of the workflow. Do not automatically install heavy
runtimes. Signing checks and pre-push hooks remain mandatory.

## Credentials and distribution

- Never commit private connections, passwords, `.p8` keys, certificates with
  private keys, provisioning profiles, keychains or local signing
  configurations. Demo data must stay original and free of personal information.
- The Apple Secrets belong to the GitHub repository and are injected only
  in the distribution step, after the tests and the dependency installation.
- Relevant pushes to `main` update the internal TestFlight group.
  Public submission happens only through `workflow_dispatch` with the `submit`
  action and an explicit version and build that have already been tried. Do not
  withdraw or replace a version already in review as a result of a push.
- Preserve the numbering by querying App Store Connect; do not reset it
  after the separation from the stack repository.
- The temporary import P12 uses the macOS-compatible format. The profile
  UUID must keep exactly the upper and lower case of the original.
- During the migration, disable the old uploader and resolve any
  pending jobs before the first push with an active workflow in this repository.

Details: [AppStore/BUILD_AND_UPLOAD.md](AppStore/BUILD_AND_UPLOAD.md).
