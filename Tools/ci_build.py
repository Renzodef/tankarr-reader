#!/usr/bin/env python3
"""Credential-free CI tests and short-lived signing on the dedicated Mac runner."""
from __future__ import annotations

import argparse
import base64
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "app.tankarr.reader"
SCHEME = "Tankarr Reader"
SECRET_NAMES = (
    "TANKARR_ASC_PRIVATE_KEY", "TANKARR_DISTRIBUTION_P12_BASE64",
    "TANKARR_DISTRIBUTION_P12_PASSWORD", "TANKARR_PROFILE_BASE64",
)


def run(*args, capture=False, env=None, timeout=1800):
    # Child build tools never inherit the raw repository secrets.
    child_env = {k: v for k, v in os.environ.items() if k not in SECRET_NAMES}
    if env:
        child_env.update(env)
    result = subprocess.run([str(arg) for arg in args], cwd=ROOT, env=child_env,
                            check=True, text=True, capture_output=capture, timeout=timeout)
    return result.stdout if capture else ""


def select_simulators(payload):
    """Select an available iPhone and iPad from the newest common iOS runtime."""
    runtimes = []
    for runtime, devices in payload["devices"].items():
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-([0-9-]+)", runtime)
        if match:
            runtimes.append((tuple(map(int, match[1].split("-"))), devices))
    for _, devices in sorted(runtimes, key=lambda item: item[0], reverse=True):
        selected = []
        for family in ("iPhone", "iPad"):
            candidates = [device for device in devices if device.get("isAvailable") is True
                          and device.get("name", "").startswith(family)]
            if candidates:
                selected.append(sorted(candidates, key=lambda device: (device.get("state") != "Shutdown", device["name"]))[0])
        if len(selected) == 2:
            return selected
    raise ValueError("No available iPhone and iPad in a common iOS simulator runtime")


@contextmanager
def simulator_session(device):
    """Reuse local simulators without shutting down one that was already running."""
    started = False
    try:
        if device["state"] != "Booted":
            run("xcrun", "simctl", "boot", device["udid"], timeout=120)
            started = True
        # An installed runtime can still need first-boot data migration.
        run("xcrun", "simctl", "bootstatus", device["udid"], "-b", timeout=600)
        yield
    finally:
        if started:
            run("xcrun", "simctl", "shutdown", device["udid"], timeout=120)


def verify_core():
    run("xcodebuild", "-version")
    run(sys.executable, "generate_project.py")
    run("swift", "test", "--jobs", "2", "--scratch-path", "build/package-tests")
    run(sys.executable, "Tools/check_store_assets.py")


def verify_device():
    """Test core and compile the iOS app without installing simulator runtimes.

    This checks compilation, not on-device behavior. The owner tests the
    TestFlight build on an iPhone before requesting public App Review.
    """
    verify_core()
    run("xcodebuild", "-project", "TankarrReader.xcodeproj", "-scheme", SCHEME,
        "-configuration", "Debug", "-destination", "generic/platform=iOS",
        "-derivedDataPath", "build/DeviceDerivedData", "CODE_SIGNING_ALLOWED=NO", "build")
    print("Core tests, store assets and iOS compilation passed. "
          "Simulator UI tests were not run; test this build on an iPhone before public submission.", flush=True)


def verify():
    verify_core()
    devices = select_simulators(json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json", capture=True)))
    for family, device in zip(("iphone", "ipad"), devices):
        print(f"UI tests: {device['name']} ({device['udid']})", flush=True)
        result = ROOT / "build/results" / f"{family}.xcresult"
        result.parent.mkdir(parents=True, exist_ok=True)
        if result.exists():
            shutil.rmtree(result)
        with simulator_session(device):
            run("xcodebuild", "-project", "TankarrReader.xcodeproj", "-scheme", SCHEME,
                "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={device['udid']}",
                "-derivedDataPath", "build/DerivedData", "-resultBundlePath", result,
                # Ad-hoc simulator signing enables the real Keychain used by the
                # background download/relaunch tests; no Apple credentials needed.
                "-parallel-testing-enabled", "NO", "CODE_SIGN_IDENTITY=-", "test")


def release_request(env):
    """Reject PRs, non-main dispatches and incomplete public release requests."""
    event = env.get("GITHUB_EVENT_NAME")
    if event not in ("push", "workflow_dispatch") or env.get("GITHUB_REF") != "refs/heads/main":
        raise ValueError("Distribution requires a main push or manual main workflow")
    action = env.get("RELEASE_ACTION", "testflight")
    if action not in ("testflight", "submit") or (action == "submit" and event != "workflow_dispatch"):
        raise ValueError("Public submission requires the explicit submit workflow action")
    version, build = env.get("INPUT_VERSION", ""), env.get("INPUT_BUILD", "")
    if event == "push" and (version or build):
        raise ValueError("Push versions and build numbers come from the project and Apple")
    if action == "submit" and (not version or not build):
        raise ValueError("submit requires an explicit version and existing tested build")
    if version and not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Version must have the form X.Y.Z")
    if build and not re.fullmatch(r"[1-9][0-9]{0,8}", build):
        raise ValueError("Build must be a positive integer of at most nine digits")
    return action, version, build


def signing_dir():
    return Path(os.environ["RUNNER_TEMP"]) / "tankarr-ios-signing"


def private_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.write_bytes(data)
    path.chmod(0o600)


def security_commands(commands):
    # security's interactive interpreter receives passwords over stdin, never argv.
    result = subprocess.run(["security", "-i"], input="\n".join(commands) + "\n",
                            text=True, capture_output=True, timeout=120,
                            env={k: v for k, v in os.environ.items() if k not in SECRET_NAMES})
    # Interactive security can return success after a failed earlier command.
    if result.returncode or "SecKeychain" in result.stderr or "Error:" in result.stderr:
        raise RuntimeError("Temporary signing keychain setup failed (output suppressed)")


def cleanup():
    folder = signing_dir()
    if not folder.exists():
        return
    state_file = folder / "state.json"
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    failures = []
    if "keychains" in state:
        try:
            run("security", "list-keychains", "-d", "user", "-s", *state["keychains"], capture=True, timeout=30)
        except (subprocess.SubprocessError, OSError):
            failures.append("keychain search list")
    keychain = folder / "signing.keychain-db"
    if keychain.exists():
        try:
            run("security", "delete-keychain", keychain, capture=True, timeout=30)
        except (subprocess.SubprocessError, OSError):
            failures.append("temporary keychain")
    for profile in state.get("profiles", []):
        try:
            Path(profile).unlink(missing_ok=True)
        except OSError:
            failures.append("provisioning profile")
    # Removing this directory also removes private keys even if security fails.
    shutil.rmtree(folder)
    if failures:
        raise RuntimeError("Signing cleanup failed: " + ", ".join(failures))


@contextmanager
def credentials():
    cleanup()
    folder = signing_dir()
    folder.mkdir(mode=0o700)
    try:
        key_id = os.environ.get("ASC_KEY_ID", "")
        if not re.fullmatch(r"[A-Z0-9]{10}", key_id):
            raise ValueError("ASC_KEY_ID must be configured")
        for name in ("ASC_ISSUER_ID", "ASC_APP_ID"):
            if not os.environ.get(name):
                raise ValueError(f"{name} must be configured")
        private_key = os.environ.pop("TANKARR_ASC_PRIVATE_KEY", "")
        if not private_key:
            raise ValueError("TANKARR_ASC_PRIVATE_KEY is missing")
        key_path = folder / f"AuthKey_{key_id}.p8"
        private_write(key_path, private_key.encode())
        del private_key
        os.environ["ASC_PRIVATE_KEY_PATH"] = str(key_path)
        yield folder
    finally:
        os.environ.pop("ASC_PRIVATE_KEY_PATH", None)
        for name in SECRET_NAMES:
            os.environ.pop(name, None)
        cleanup()


def validate_signing(profile, certificate, team):
    from cryptography.hazmat.primitives.serialization import Encoding
    from cryptography.x509.oid import NameOID

    now = datetime.now(timezone.utc)
    expires = profile["ExpirationDate"].replace(tzinfo=timezone.utc)
    entitlements = profile.get("Entitlements", {})
    if expires <= now or not certificate.not_valid_before_utc <= now < certificate.not_valid_after_utc:
        raise ValueError("Distribution certificate or provisioning profile has expired or is not valid yet")
    if (profile.get("TeamIdentifier") != [team]
            or entitlements.get("application-identifier") != f"{team}.{BUNDLE_ID}"
            or entitlements.get("get-task-allow") is not False
            or entitlements.get("aps-environment") != "production"
            or profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices")):
        raise ValueError("Expected an App Store distribution profile for the configured team and bundle")
    if not entitlements.get("com.apple.developer.associated-domains"):
        # Web reader links open the app through applinks:tankarr.renzodef.com.
        raise ValueError("The provisioning profile lacks Associated Domains: enable it on the App ID and regenerate the profile")
    common_names = certificate.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
    teams = certificate.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)
    if (not common_names or not common_names[0].value.startswith(("Apple Distribution:", "iPhone Distribution:"))
            or [item.value for item in teams] != [team]
            or certificate.public_bytes(Encoding.DER) not in profile.get("DeveloperCertificates", [])):
        raise ValueError("Distribution certificate does not match the team and provisioning profile")
    profile_id = profile["UUID"]
    uuid.UUID(profile_id)
    # Xcode matches the profile specifier case-sensitively against its stored UUID.
    return profile_id


def macos_import_p12(key, certificate, chain, password):
    """Use Apple's compatible P12 envelope only for the short-lived import file."""
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.serialization import pkcs12

    encryption = (serialization.PrivateFormat.PKCS12.encryption_builder()
                  .kdf_rounds(50000)
                  .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
                  .hmac_hash(hashes.SHA1())
                  .build(password.encode()))
    return pkcs12.serialize_key_and_certificates(b"Tankarr CI", key, certificate, chain, encryption)


def new_profile_paths(profiles, data):
    """Leave identical existing profiles untouched; refuse to replace local files."""
    new_paths = []
    for path in profiles:
        if path.exists():
            if path.read_bytes() != data:
                raise ValueError("A different provisioning profile already exists at the installation path")
        else:
            new_paths.append(path)
    return new_paths


def provisioning_profile_path(home, profile_id, xcode_version):
    """Install only where the selected Xcode reads profiles; leave legacy folders alone."""
    version = re.search(r"(?m)^Xcode ([1-9][0-9]*)(?:\.[0-9]+)*\s*$", xcode_version)
    if not version:
        raise ValueError("Cannot determine the selected Xcode provisioning profile location")
    # Apple-Actions/download-provisioning-profiles documents the Xcode 16 migration.
    location = ("Library/Developer/Xcode/UserData/Provisioning Profiles" if int(version[1]) >= 16
                else "Library/MobileDevice/Provisioning Profiles")
    return home / location / f"{profile_id}.mobileprovision"


def prepare_signing(folder):
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.serialization import pkcs12

    team = os.environ.get("APPLE_TEAM_ID", "")
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("APPLE_TEAM_ID must be configured")
    p12 = base64.b64decode(os.environ.pop("TANKARR_DISTRIBUTION_P12_BASE64", ""), validate=True)
    password = os.environ.pop("TANKARR_DISTRIBUTION_P12_PASSWORD", "")
    key, cert, chain = pkcs12.load_key_and_certificates(p12, password.encode() if password else None)
    del p12, password
    if key is None or cert is None:
        raise ValueError("P12 must contain a distribution certificate and its private key")
    profile_path = folder / "distribution.mobileprovision"
    private_write(profile_path, base64.b64decode(os.environ.pop("TANKARR_PROFILE_BASE64", ""), validate=True))
    profile = plistlib.loads(run("security", "cms", "-D", "-i", profile_path, capture=True).encode())
    profile_id = validate_signing(profile, cert, team)
    keychain = folder / "signing.keychain-db"
    keychain_password, import_password = secrets.token_hex(32), secrets.token_hex(32)
    # Re-encrypt with a one-use password: the persistent P12 password stays in Python.
    import_path = folder / "distribution.p12"
    private_write(import_path, macos_import_p12(key, cert, chain, import_password))
    old_keychains = shlex.split(run("security", "list-keychains", "-d", "user", capture=True))
    profiles = [provisioning_profile_path(Path.home(), profile_id,
                                         run("xcodebuild", "-version", capture=True, timeout=30))]
    profile_data = profile_path.read_bytes()
    profiles_to_install = new_profile_paths(profiles, profile_data)
    private_write(folder / "state.json", json.dumps({"keychains": old_keychains,
                                                    "profiles": [str(path) for path in profiles_to_install]}).encode())
    quote = shlex.quote
    security_commands([
        f"create-keychain -p {keychain_password} {quote(str(keychain))}",
        f"set-keychain-settings -lut 7200 {quote(str(keychain))}",
        f"unlock-keychain -p {keychain_password} {quote(str(keychain))}",
        f"import {quote(str(import_path))} -k {quote(str(keychain))} -P {import_password} -T /usr/bin/codesign -T /usr/bin/security",
        f"set-key-partition-list -S apple-tool:,apple:,codesign: -s -k {keychain_password} {quote(str(keychain))}",
    ])
    import_path.unlink()
    run("security", "list-keychains", "-d", "user", "-s", keychain, *old_keychains, capture=True)
    fingerprint = cert.fingerprint(hashes.SHA1()).hex().upper()
    identities = run("security", "find-identity", "-v", "-p", "codesigning", keychain, capture=True)
    if fingerprint not in identities:
        raise ValueError("Imported distribution certificate is not a valid signing identity")
    for destination in profiles_to_install:
        private_write(destination, profile_data)
    return team, profile_id, fingerprint, keychain


def upload(ipa, version, build):
    help_text = run("xcrun", "altool", "--help", capture=True, timeout=60)
    if "--api-key" in help_text and "--p8-file-path" in help_text:
        run("xcrun", "altool", "--upload-package", ipa,
            "--api-key", os.environ["ASC_KEY_ID"], "--api-issuer", os.environ["ASC_ISSUER_ID"],
            "--p8-file-path", os.environ["ASC_PRIVATE_KEY_PATH"],
            # Passing the App Store Connect app id skips the list-apps lookup,
            # which can fail with HTTP 500 while uploads still work.
            *(["--apple-id", os.environ["ASC_APP_ID"], "--bundle-id", "app.tankarr.reader",
               "--bundle-version", str(build), "--bundle-short-version-string", str(version)]
              if os.environ.get("ASC_APP_ID") else []),
            "--wait")
    else:
        # Xcode's older uploader discovers AuthKey_<ID>.p8 in this private directory.
        run("xcrun", "altool", "--upload-app", "-f", ipa, "-t", "ios",
            "--apiKey", os.environ["ASC_KEY_ID"], "--apiIssuer", os.environ["ASC_ISSUER_ID"],
            env={"API_PRIVATE_KEYS_DIR": str(Path(os.environ["ASC_PRIVATE_KEY_PATH"]).parent)})


def export_archive(archive, export, options):
    # Xcode's /usr/bin/rsync launches its server by name. Homebrew rsync uses
    # different extended-attribute flags, so both halves must resolve Apple's tools.
    system_paths = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    other_paths = [path for path in os.environ.get("PATH", "").split(os.pathsep)
                   if path and path not in system_paths]
    run("xcodebuild", "-exportArchive", "-archivePath", archive, "-exportPath", export,
        "-exportOptionsPlist", options, env={"PATH": os.pathsep.join(system_paths + other_paths)})


def distribute():
    action, version, requested_build = release_request(os.environ)
    with credentials() as folder:
        helper = (sys.executable, "Tools/asc_release.py")
        if action == "submit":
            run(*helper, "submit", "--version", version, "--build", requested_build)
            return
        if not os.environ.get("ASC_BETA_GROUP_ID"):
            raise ValueError("ASC_BETA_GROUP_ID must identify an existing internal TestFlight group")
        run(sys.executable, "generate_project.py")
        if not version:
            version = json.loads((ROOT / "AppStore/metadata.json").read_text())["version"]
            if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
                raise ValueError("AppStore/metadata.json must declare version X.Y.Z")
        try:
            next_build = run(*helper, "next-build", "--version", version, capture=True).strip()
        except subprocess.CalledProcessError as error:
            # asc_release reports sanitized diagnostics with this prefix.
            diagnostic = (error.stderr or "").strip()
            if re.fullmatch(r"error: [^\r\n]{1,240}", diagnostic):
                raise RuntimeError(diagnostic) from None
            raise
        if not re.fullmatch(r"[1-9][0-9]{0,8}", next_build):
            raise ValueError("Invalid next build number from Apple")
        build = requested_build or next_build
        if int(build) < int(next_build):
            raise ValueError("Requested build number has already been used in App Store Connect")
        team, profile_id, fingerprint, keychain = prepare_signing(folder)
        archive, export = ROOT / "build/TankarrReader.xcarchive", ROOT / "build/export"
        for path in (archive, export):
            if path.exists():
                shutil.rmtree(path)
        print(f"Archiving Tankarr Reader {version} ({build}) for TestFlight", flush=True)
        run("xcodebuild", "-project", "TankarrReader.xcodeproj", "-scheme", SCHEME,
            "-configuration", "Release", "-destination", "generic/platform=iOS",
            "-archivePath", archive, f"DEVELOPMENT_TEAM={team}", "CODE_SIGN_STYLE=Manual",
            f"CODE_SIGN_IDENTITY={fingerprint}", f"PROVISIONING_PROFILE_SPECIFIER={profile_id}",
            f"OTHER_CODE_SIGN_FLAGS=--keychain {shlex.quote(str(keychain))}",
            f"CURRENT_PROJECT_VERSION={build}", f"MARKETING_VERSION={version}", "archive")
        options = folder / "ExportOptions.plist"
        private_write(options, plistlib.dumps({
            "method": "app-store-connect", "destination": "export", "signingStyle": "manual",
            "teamID": team, "signingCertificate": fingerprint,
            "provisioningProfiles": {BUNDLE_ID: profile_id}, "uploadSymbols": True,
            "manageAppVersionAndBuildNumber": False,
        }))
        export_archive(archive, export, options)
        ipas = list(export.glob("*.ipa"))
        if len(ipas) != 1:
            raise ValueError("Expected exactly one exported IPA")
        upload(ipas[0], version, build)
        run(*helper, "beta", "--version", version, "--build", build, timeout=2400)
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with Path(summary).open("a") as output:
                output.write(f"Tankarr Reader **{version} ({build})** caricata nel gruppo TestFlight interno.\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("verify", "verify-device", "distribute", "cleanup"))
    command = parser.parse_args().command
    os.umask(0o077)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    try:
        {"verify": verify, "verify-device": verify_device, "distribute": distribute, "cleanup": cleanup}[command]()
    except subprocess.CalledProcessError as exc:
        # Do not dump command arguments or captured authentication output.
        print(f"CI failed: {Path(exc.cmd[0]).name} exited {exc.returncode}", file=sys.stderr)
        return 1
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        print(f"CI failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
