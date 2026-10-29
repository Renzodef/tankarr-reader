"""Release safety checks use a fake HTTP transport; no Apple account is contacted."""

import base64
import copy
import importlib.util
import json
from pathlib import Path
from urllib.parse import urlsplit

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
import pytest
import requests


SPEC = importlib.util.spec_from_file_location(
    "asc_release", Path(__file__).resolve().parents[1] / "Tools/asc_release.py"
)
asc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(asc)


def link(kind, identifier):
    return {"data": {"type": kind, "id": identifier}}


def build(number="3", *, state="VALID", encryption=False):
    return {
        "type": "builds", "id": "build-" + number.replace(".", "-"),
        "attributes": {"version": number, "processingState": state, "expired": False,
                       "usesNonExemptEncryption": encryption, "buildAudienceType": "APP_STORE_ELIGIBLE"},
        "relationships": {"app": link("apps", "app-test"),
                          "preReleaseVersion": link("preReleaseVersions", "prerelease-test")},
    }


def version(state="PREPARE_FOR_SUBMISSION", *, number="1.0.1", identifier="version-test"):
    return {"type": "appStoreVersions", "id": identifier,
            "attributes": {"versionString": number, "platform": "IOS", "appVersionState": state},
            "relationships": {"build": {"data": None}}}


def submission(state="READY_FOR_REVIEW"):
    return {"type": "reviewSubmissions", "id": "submission-test",
            "attributes": {"state": state, "platform": "IOS"}}


def item(version_id="version-test", state="READY_FOR_REVIEW"):
    return {"type": "reviewSubmissionItems", "id": "item-test", "attributes": {"state": state},
            "relationships": {"appStoreVersion": link("appStoreVersions", version_id)}}


class Response:
    def __init__(self, data, status=200):
        self.payload = data
        self.status_code = status

    def json(self):
        return copy.deepcopy(self.payload)


class FakeSession:
    def __init__(self):
        self.calls = []
        self.builds = [build()]
        self.marketing_version = "1.0.1"
        self.versions = [version()]
        self.submissions = []
        self.items = []
        self.group = {"type": "betaGroups", "id": "group-test",
                      "attributes": {"isInternalGroup": True, "hasAccessToAllBuilds": False},
                      "relationships": {"app": link("apps", "app-test")}}
        self.members = []
        self.override = None

    @property
    def writes(self):
        return [call for call in self.calls if call[0] != "GET"]

    def request(self, method, url, **kwargs):
        assert kwargs["allow_redirects"] is False
        assert kwargs["timeout"] == (10, 30)
        assert kwargs["headers"]["Authorization"] == "Bearer fake-token"
        self.calls.append((method, urlsplit(url).path, kwargs.get("params"), kwargs.get("json")))
        if self.override:
            response = self.override(method, url, kwargs)
            if response is not None:
                return response
        path = urlsplit(url).path
        if method == "GET":
            if path == "/v1/builds":
                payload = self.build_payload(copy.deepcopy(self.builds))
                # Apple emits relationship links without data unless app is included.
                if "app" not in kwargs["params"].get("include", "").split(","):
                    for row in payload["data"]:
                        row["relationships"]["app"] = {"links": {"related": "unused"}}
                return Response(payload)
            if path == "/v1/apps/app-test/appStoreVersions":
                return Response({"data": self.versions})
            if path == "/v1/betaGroups/group-test":
                group = copy.deepcopy(self.group)
                if "app" not in kwargs["params"].get("include", "").split(","):
                    group["relationships"]["app"] = {"links": {"related": "unused"}}
                return Response({"data": group})
            if path == "/v1/betaGroups/group-test/relationships/builds":
                return Response({"data": self.members})
            if path == "/v1/reviewSubmissions":
                return Response({"data": self.submissions})
            if path == "/v1/reviewSubmissions/submission-test/items":
                return Response({"data": self.items})
        if method == "POST" and path == "/v1/betaGroups/group-test/relationships/builds":
            self.members.extend(kwargs["json"]["data"])
            return Response({}, 204)
        if method == "POST" and path == "/v1/reviewSubmissions":
            self.submissions.append(submission())
            return Response({"data": self.submissions[-1]}, 201)
        if method == "POST" and path == "/v1/reviewSubmissionItems":
            self.items.append(item())
            return Response({"data": self.items[-1]}, 201)
        if method == "PATCH" and path in {
            "/v1/appStoreVersions/version-test/relationships/build", "/v1/builds/build-3",
            "/v1/reviewSubmissions/submission-test",
        }:
            return Response({}, 204)
        pytest.fail(f"Unexpected fake API request: {method} {path}")

    def build_payload(self, rows):
        return {"data": rows, "included": [{
            "type": "preReleaseVersions", "id": "prerelease-test",
            "attributes": {"version": self.marketing_version, "platform": "IOS"},
        }]}


@pytest.fixture
def api():
    session = FakeSession()
    client = asc.AppleClient(lambda: "fake-token", session=session)
    return session, asc.ReleaseManager(client, "app-test", "group-test")


@pytest.mark.parametrize("value", ["", "1", "1.2", "1.2.3.4", "v1.2.3", "1.0.1-beta", "01.0.0", "-1.0.0", "1.0.0\n", "１.0.0", "1.0.0/.."])
def test_invalid_marketing_versions_fail_before_requests(api, value):
    session, manager = api
    with pytest.raises(asc.ReleaseError, match="Version"):
        manager.next_build(value)
    assert not session.calls


def test_next_build_checks_every_page_and_all_processing_states(api):
    session, manager = api

    def pages(method, url, kwargs):
        if urlsplit(url).path != "/v1/builds":
            return None
        if not urlsplit(url).query:
            assert kwargs["params"]["filter[preReleaseVersion.version]"] == "1.0.1"
            assert kwargs["params"]["filter[app]"] == "app-test"
            assert "filter[processingState]" not in kwargs["params"]
            payload = session.build_payload([build("2"), build("9")])
            payload["links"] = {"next": asc.API_ORIGIN + "/v1/builds?cursor=next"}
            return Response(payload)
        assert kwargs["params"] is None
        return Response(session.build_payload([build("10", state="FAILED"), build("3")]))

    session.override = pages
    assert manager.next_build("1.0.1") == 11
    assert not session.writes


def test_next_build_starts_at_one_and_refuses_ambiguous_existing_numbers(api):
    session, manager = api
    session.builds = []
    assert manager.next_build("1.0.1") == 1
    session.builds = [build("1.2")]
    with pytest.raises(asc.ReleaseError, match="positive integer"):
        manager.next_build("1.0.1")


def test_beta_adds_once_and_never_touches_public_version(api):
    session, manager = api
    assert manager.beta("1.0.1", "3")["already_available"] is False
    assert manager.beta("1.0.1", "3")["already_available"] is True
    assert [(method, path) for method, path, _, _ in session.writes] == [
        ("POST", "/v1/betaGroups/group-test/relationships/builds")
    ]
    assert all("appStoreVersions" not in call[1] and "reviewSubmission" not in call[1] for call in session.calls)


def test_beta_group_with_all_builds_is_already_available(api):
    session, manager = api
    session.group["attributes"]["hasAccessToAllBuilds"] = True
    assert manager.beta("1.0.1", "3")["already_available"] is True
    assert not session.writes


@pytest.mark.parametrize("change", ["external", "wrong-app"])
def test_beta_rejects_external_or_other_app_group_before_writes(api, change):
    session, manager = api
    if change == "external":
        session.group["attributes"]["isInternalGroup"] = False
    else:
        session.group["relationships"]["app"] = link("apps", "other-app")
    with pytest.raises(asc.ReleaseError):
        manager.beta("1.0.1", "3")
    assert not session.writes


def test_beta_polls_until_valid_and_times_out_without_writes(api):
    session, manager = api
    clock = [0]
    manager.monotonic = lambda: clock[0]
    manager.sleep = lambda seconds: clock.__setitem__(0, clock[0] + seconds)

    def pending(method, url, kwargs):
        if urlsplit(url).path == "/v1/builds":
            state = "VALID" if clock[0] >= 2 else "PROCESSING"
            return Response(session.build_payload([build(state=state)]))
        return None

    session.override = pending
    assert manager.beta("1.0.1", "3", timeout=3, poll_interval=1)["internal_beta"] is True
    assert clock[0] == 2
    session.calls.clear()
    clock[0] = 0
    with pytest.raises(asc.ReleaseError, match="timeout"):
        manager.beta("1.0.1", "3", timeout=1, poll_interval=1)
    assert clock[0] == 1
    assert not session.writes


@pytest.mark.parametrize("state", ["WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "READY_FOR_SALE", "READY_FOR_DISTRIBUTION"])
def test_public_pending_or_ready_version_refused_before_any_write(api, state):
    session, manager = api
    session.versions = [version(state)]
    with pytest.raises(asc.ReleaseError):
        manager.submit("1.0.1", "3")
    assert not session.writes
    assert len(session.calls) == 1


def test_other_pending_public_version_blocks_new_submission(api):
    session, manager = api
    session.versions.append(version("WAITING_FOR_REVIEW", number="1.0.0", identifier="pending-version"))
    with pytest.raises(asc.ReleaseError, match="already pending"):
        manager.submit("1.0.1", "3")
    assert not session.writes


@pytest.mark.parametrize("issue", ["marketing-version", "build-number", "failed", "invalid", "expired", "wrong-app", "internal-only", "encryption"])
def test_wrong_or_ineligible_build_never_changes_public_version(api, issue):
    session, manager = api
    attributes = session.builds[0]["attributes"]
    if issue == "marketing-version":
        session.marketing_version = "9.0.0"
    elif issue == "build-number":
        attributes["version"] = "99"
    elif issue in {"failed", "invalid"}:
        attributes["processingState"] = issue.upper()
    elif issue == "expired":
        attributes["expired"] = True
    elif issue == "wrong-app":
        session.builds[0]["relationships"]["app"] = link("apps", "other-app")
    elif issue == "internal-only":
        attributes["buildAudienceType"] = "INTERNAL_ONLY"
    else:
        attributes["usesNonExemptEncryption"] = True
    with pytest.raises(asc.ReleaseError):
        manager.submit("1.0.1", "3")
    assert not session.writes


@pytest.mark.parametrize("state", ["FAILED", "INVALID"])
def test_beta_failed_processing_does_not_attach_build(api, state):
    session, manager = api
    session.builds[0]["attributes"]["processingState"] = state
    with pytest.raises(asc.ReleaseError, match="processing failed"):
        manager.beta("1.0.1", "3")
    assert not session.writes


def test_submit_creates_only_review_records_and_preserves_released_version(api):
    session, manager = api
    session.versions.append(version("READY_FOR_DISTRIBUTION", number="1.0.0", identifier="released-version"))
    session.builds[0]["attributes"]["usesNonExemptEncryption"] = None
    assert manager.submit("1.0.1", "3") == {"version": "1.0.1", "build": "3", "submitted": True}
    assert [(method, path) for method, path, _, _ in session.writes] == [
        ("PATCH", "/v1/builds/build-3"),
        ("PATCH", "/v1/appStoreVersions/version-test/relationships/build"),
        ("POST", "/v1/reviewSubmissions"),
        ("POST", "/v1/reviewSubmissionItems"),
        ("PATCH", "/v1/reviewSubmissions/submission-test"),
    ]
    assert session.writes[0][3]["data"]["attributes"] == {"usesNonExemptEncryption": False}
    assert session.writes[-1][3]["data"]["attributes"] == {"submitted": True}


def test_submit_reuses_existing_draft_item_and_linked_build(api):
    session, manager = api
    session.submissions = [submission()]
    session.items = [item()]
    session.versions[0]["relationships"]["build"] = link("builds", "build-3")
    manager.submit("1.0.1", "3")
    assert [(method, path) for method, path, _, _ in session.writes] == [
        ("PATCH", "/v1/reviewSubmissions/submission-test")
    ]


@pytest.mark.parametrize("issue", ["other-version", "other-item", "active-review", "unresolved-review", "missing-version"])
def test_submit_preflights_drafts_and_requires_existing_public_version(api, issue):
    session, manager = api
    session.submissions = [submission()]
    if issue == "other-version":
        session.items = [item("other-version")]
    elif issue == "other-item":
        session.items = [{"type": "reviewSubmissionItems", "id": "other-item", "attributes": {"state": "READY_FOR_REVIEW"}}]
    elif issue == "active-review":
        session.submissions = [submission("IN_REVIEW")]
    elif issue == "unresolved-review":
        session.submissions = [submission("UNRESOLVED_ISSUES")]
    else:
        session.versions = []
    with pytest.raises(asc.ReleaseError):
        manager.submit("1.0.1", "3")
    assert not session.writes


def test_submit_rechecks_public_state_before_first_write(api):
    session, manager = api
    checks = [0]

    def race(method, url, kwargs):
        if urlsplit(url).path == "/v1/apps/app-test/appStoreVersions":
            checks[0] += 1
            if checks[0] == 2:
                return Response({"data": [version("WAITING_FOR_REVIEW")]})
        return None

    session.override = race
    with pytest.raises(asc.ReleaseError, match="already pending"):
        manager.submit("1.0.1", "3")
    assert not session.writes


@pytest.mark.parametrize("destination", ["https://evil.example/v1/builds", "https://api.appstoreconnect.apple.com.evil.example/v1/builds", "http://api.appstoreconnect.apple.com/v1/builds", "https://user@api.appstoreconnect.apple.com/v1/builds", "//evil.example/v1/builds"])
def test_pagination_cannot_send_token_off_apple_host(api, destination):
    session, manager = api

    def malicious_page(method, url, kwargs):
        return Response({"data": [], "links": {"next": destination}})

    session.override = malicious_page
    with pytest.raises(asc.ReleaseError, match="outside"):
        manager.next_build("1.0.1")
    assert len(session.calls) == 1


def test_http_errors_and_redirects_do_not_disclose_response_or_token(api):
    session, manager = api
    for status in (302, 401, 422, 500):
        session.override = lambda *args: Response({"errors": [{"detail": "private key or account secret"}]}, status)
        with pytest.raises(asc.ReleaseError) as error:
            manager.next_build("1.0.1")
        assert str(status) in str(error.value)
        assert "private" not in str(error.value)
        assert "fake-token" not in str(error.value)


def test_network_exception_text_is_redacted(api):
    session, manager = api

    def disconnected(*args):
        raise requests.ConnectionError("request contained fake-token and private data")

    session.override = disconnected
    with pytest.raises(asc.ReleaseError) as error:
        manager.next_build("1.0.1")
    assert "fake-token" not in str(error.value)
    assert "private" not in str(error.value)


def test_jwt_is_verifiable_es256_and_has_short_expiration(tmp_path):
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    path = tmp_path / "temporary-test-key.p8"
    path.write_bytes(pem)
    provider = asc.jwt_provider("test-key", "test-issuer", path)
    token = provider()
    header, claims, signature = token.split(".")

    def decode(value):
        return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))

    assert json.loads(decode(header)) == {"alg": "ES256", "kid": "test-key", "typ": "JWT"}
    payload = json.loads(decode(claims))
    assert payload["aud"] == "appstoreconnect-v1"
    assert payload["iss"] == "test-issuer"
    assert payload["exp"] - payload["iat"] == 610
    raw = decode(signature)
    assert len(raw) == 64
    der = encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
    key.public_key().verify(der, (header + "." + claims).encode(), ec.ECDSA(hashes.SHA256()))
    assert provider() == token


def test_cli_validates_before_credentials_and_never_echoes_invalid_input(capsys):
    assert asc.main(["next-build", "--version", "private-value"]) == 1
    output = capsys.readouterr()
    assert output.out == ""
    assert "private-value" not in output.err
