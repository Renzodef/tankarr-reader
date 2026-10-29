"""Release boundary, simulator selection and signing cleanup regression checks."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

import pytest

SOURCE = Path(__file__).resolve().parents[1] / "Tools/ci_build.py"
SPEC = importlib.util.spec_from_file_location("tankarr_ios_ci", SOURCE)
ci = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = ci
SPEC.loader.exec_module(ci)


def environment(**changes):
    return {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REF": "refs/heads/main",
            "RELEASE_ACTION": "testflight", **changes}


def device(name, available=True):
    return {"name": name, "isAvailable": available, "udid": name, "state": "Shutdown"}


def test_newest_runtime_with_both_device_families():
    payload = {"devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-26-6": [device("iPhone 17")],
        "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [device("iPad Pro"), device("iPhone 17"), device("iPhone 16", False)],
        "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [device("iPhone 16"), device("iPad Air")],
        "com.apple.CoreSimulator.SimRuntime.tvOS-27-0": [device("iPhone fake"), device("iPad fake")],
    }}
    assert [item["name"] for item in ci.select_simulators(payload)] == ["iPhone 17", "iPad Pro"]


def test_requires_both_available_families():
    with pytest.raises(ValueError, match="No available"):
        ci.select_simulators({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5":
                                         [device("iPhone 17"), device("iPad Pro", False)]}})


@pytest.mark.parametrize("changes", [
    {"GITHUB_EVENT_NAME": "pull_request"},
    {"GITHUB_EVENT_NAME": "pull_request_target"},
    {"GITHUB_REF": "refs/heads/feature"},
    {"GITHUB_EVENT_NAME": "push", "RELEASE_ACTION": "submit", "INPUT_VERSION": "1.0.0", "INPUT_BUILD": "2"},
    {"RELEASE_ACTION": "submit", "INPUT_VERSION": "1.0.0"},
    {"RELEASE_ACTION": "submit", "INPUT_BUILD": "2"},
    {"RELEASE_ACTION": "shell"},
    {"INPUT_VERSION": "1.0.0; touch /tmp/injected"},
    {"INPUT_VERSION": "$(id)"},
    {"INPUT_BUILD": "2\nmalicious"},
    {"INPUT_BUILD": "0"},
    {"GITHUB_EVENT_NAME": "push", "INPUT_VERSION": "2.0.0"},
])
def test_dispatch_rejects_unsafe_or_implicit_requests(changes):
    with pytest.raises(ValueError):
        ci.release_request(environment(**changes))


def test_submit_requires_explicit_version_and_build():
    assert ci.release_request(environment(RELEASE_ACTION="submit", INPUT_VERSION="1.2.3", INPUT_BUILD="42")) == ("submit", "1.2.3", "42")
    assert ci.release_request(environment(GITHUB_EVENT_NAME="push")) == ("testflight", "", "")


def test_subprocess_arguments_are_a_list_and_raw_secrets_are_removed(monkeypatch):
    for name in ci.SECRET_NAMES:
        monkeypatch.setenv(name, "private-material")
    received = {}

    def fake_run(args, **kwargs):
        received.update(args=args, **kwargs)
        return subprocess.CompletedProcess(args, 0, stdout="done")

    monkeypatch.setattr(ci.subprocess, "run", fake_run)
    assert ci.run("tool", "1.2.3;$(dangerous)", capture=True) == "done"
    assert received["args"] == ["tool", "1.2.3;$(dangerous)"]
    assert not received.get("shell", False)
    assert all(name not in received["env"] for name in ci.SECRET_NAMES)


def test_credentials_cleanup_runs_after_signing_failure(tmp_path, monkeypatch):
    monkeypatch.setenv("RUNNER_TEMP", str(tmp_path))
    monkeypatch.setenv("ASC_KEY_ID", "ABCDEFGHIJ")
    monkeypatch.setenv("ASC_ISSUER_ID", "issuer")
    monkeypatch.setenv("ASC_APP_ID", "123")
    monkeypatch.setenv("TANKARR_ASC_PRIVATE_KEY", "test private key")
    monkeypatch.setenv("TANKARR_DISTRIBUTION_P12_PASSWORD", "persistent-password")
    with pytest.raises(RuntimeError, match="archive failed"):
        with ci.credentials() as folder:
            assert (folder / "AuthKey_ABCDEFGHIJ.p8").read_text() == "test private key"
            assert (folder / "AuthKey_ABCDEFGHIJ.p8").stat().st_mode & 0o777 == 0o600
            raise RuntimeError("archive failed")
    assert not ci.signing_dir().exists()
    assert "ASC_PRIVATE_KEY_PATH" not in ci.os.environ
    assert all(name not in ci.os.environ for name in ci.SECRET_NAMES)


def test_cleanup_removes_keys_and_profiles_even_if_security_fails(tmp_path, monkeypatch):
    monkeypatch.setenv("RUNNER_TEMP", str(tmp_path))
    folder = ci.signing_dir()
    folder.mkdir()
    profile = tmp_path / "installed.mobileprovision"
    profile.write_text("profile")
    (folder / "signing.keychain-db").write_text("private key")
    (folder / "AuthKey_TEST.p8").write_text("private key")
    (folder / "state.json").write_text(json.dumps({"keychains": ["login.keychain-db"], "profiles": [str(profile)]}))

    def failed_security(*args, **kwargs):
        raise subprocess.CalledProcessError(1, args)

    monkeypatch.setattr(ci, "run", failed_security)
    with pytest.raises(RuntimeError, match="cleanup failed"):
        ci.cleanup()
    assert not folder.exists()
    assert not profile.exists()


def test_submit_reuses_existing_build_without_archiving(tmp_path, monkeypatch):
    for name, value in environment(RELEASE_ACTION="submit", INPUT_VERSION="1.2.3", INPUT_BUILD="42").items():
        monkeypatch.setenv(name, value)
    monkeypatch.setenv("RUNNER_TEMP", str(tmp_path))
    monkeypatch.setenv("ASC_KEY_ID", "ABCDEFGHIJ")
    monkeypatch.setenv("ASC_ISSUER_ID", "issuer")
    monkeypatch.setenv("ASC_APP_ID", "123")
    monkeypatch.setenv("TANKARR_ASC_PRIVATE_KEY", "private key")
    calls = []
    monkeypatch.setattr(ci, "run", lambda *args, **kwargs: calls.append(args))
    ci.distribute()
    assert calls == [(sys.executable, "Tools/asc_release.py", "submit", "--version", "1.2.3", "--build", "42")]
    assert not ci.signing_dir().exists()


def test_temporary_p12_uses_macos_compatible_envelope_and_preserves_identity():
    from datetime import datetime, timedelta, timezone
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.serialization import pkcs12
    from cryptography.x509.oid import NameOID

    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Test distribution identity")])
    now = datetime.now(timezone.utc)
    certificate = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                   .public_key(key.public_key()).serial_number(x509.random_serial_number())
                   .not_valid_before(now - timedelta(minutes=1))
                   .not_valid_after(now + timedelta(days=1)).sign(key, hashes.SHA256()))
    payload = ci.macos_import_p12(key, certificate, [], "one-use-test-password")
    # Check the actual DER algorithm identifiers: macOS rejects the PBESv2 defaults.
    assert bytes.fromhex("060a2a864886f70d010c0103") in payload  # PKCS12 SHA1 + 3-key 3DES
    assert bytes.fromhex("06052b0e03021a") in payload  # SHA1 MAC
    assert bytes.fromhex("06092a864886f70d01050d") not in payload  # PBESv2
    recovered_key, recovered_certificate, _ = pkcs12.load_key_and_certificates(payload, b"one-use-test-password")
    assert recovered_certificate == certificate
    assert recovered_key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
    ) == key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    with pytest.raises(ValueError):
        pkcs12.load_key_and_certificates(payload, b"different-password")


@pytest.mark.parametrize("profile_id", [
    "eb3be43a-0d6b-4d61-8115-ff8e39d6c1bf",
    "Eb3bE43a-0D6b-4d61-8115-Ff8e39D6c1bF",
])
def test_signing_profile_uuid_retains_exact_case(profile_id):
    from datetime import datetime, timedelta, timezone
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import NameOID

    team = "ABCDEFGHIJ"
    key = ec.generate_private_key(ec.SECP256R1())
    subject = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, "Apple Distribution: Test team"),
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, team),
    ])
    now = datetime.now(timezone.utc)
    certificate = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
                   .public_key(key.public_key()).serial_number(x509.random_serial_number())
                   .not_valid_before(now - timedelta(minutes=1))
                   .not_valid_after(now + timedelta(days=1)).sign(key, hashes.SHA256()))
    profile = {
        "UUID": profile_id,
        "TeamIdentifier": [team],
        "ExpirationDate": now + timedelta(days=1),
        "Entitlements": {"application-identifier": f"{team}.{ci.BUNDLE_ID}", "get-task-allow": False},
        "DeveloperCertificates": [certificate.public_bytes(serialization.Encoding.DER)],
    }
    assert ci.validate_signing(profile, certificate, team) == profile_id
