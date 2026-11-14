#!/usr/bin/env python3
"""Small App Store Connect release client; public submission is an explicit command.

Requires requests and cryptography. Credentials are read only from ASC_KEY_ID,
ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH and ASC_APP_ID. beta also needs
ASC_BETA_GROUP_ID. This client never creates public versions or edits metadata,
availability, pricing, release policy, or existing reviews.
"""

import argparse
import base64
import json
import math
import os
from pathlib import Path
import re
import sys
import time
from urllib.parse import urlsplit

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature


API_ORIGIN = "https://api.appstoreconnect.apple.com"
EDITABLE_VERSION_STATES = frozenset({
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
    "METADATA_REJECTED", "INVALID_BINARY",
})
ACTIVE_VERSION_STATES = frozenset({
    "WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW", "ACCEPTED",
    "WAITING_FOR_EXPORT_COMPLIANCE", "PENDING_APPLE_RELEASE", "PENDING_CONTRACT",
    "PENDING_DEVELOPER_RELEASE", "PROCESSING_FOR_APP_STORE",
    "PROCESSING_FOR_DISTRIBUTION", "PREORDER_READY_FOR_SALE",
})


class ReleaseError(Exception):
    """An actionable error whose message contains no credentials or response body."""


def validate_version(value):
    if not isinstance(value, str) or not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", value):
        raise ReleaseError("Version must contain three non-negative integers, for example 1.2.0.")
    return value


def validate_build(value):
    if not isinstance(value, str) or not re.fullmatch(r"[1-9][0-9]*", value):
        raise ReleaseError("Build number must be a positive integer without leading zeroes.")
    return value


def resource_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9-]+", value):
        raise ReleaseError("App Store Connect returned or was configured with an invalid resource ID.")
    return value


def relationship(resource, name):
    return resource.get("relationships", {}).get(name, {}).get("data")


def jwt_provider(key_id, issuer_id, private_key_path):
    try:
        key = serialization.load_pem_private_key(Path(private_key_path).read_bytes(), password=None)
    except (OSError, ValueError, TypeError):
        raise ReleaseError("Cannot load ASC_PRIVATE_KEY_PATH as an unencrypted ES256 private key.") from None
    if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
        raise ReleaseError("ASC_PRIVATE_KEY_PATH must contain an ES256 private key.")
    cached = {"expires": 0, "token": ""}

    def encode(data):
        return base64.urlsafe_b64encode(data).rstrip(b"=")

    def token():
        now = int(time.time())
        if cached["expires"] - now > 60:
            return cached["token"]
        header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
        claims = {"iss": issuer_id, "iat": now - 10, "exp": now + 600, "aud": "appstoreconnect-v1"}
        signing_input = b".".join(encode(json.dumps(x, separators=(",", ":")).encode()) for x in (header, claims))
        r, s = decode_dss_signature(key.sign(signing_input, ec.ECDSA(hashes.SHA256())))
        signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
        cached.update(expires=claims["exp"], token=(signing_input + b"." + encode(signature)).decode())
        return cached["token"]

    return token


class AppleClient:
    def __init__(self, token_provider, session=None):
        self.token_provider = token_provider
        self.session = session or requests.Session()

    def request(self, method, path, *, params=None, body=None):
        url = API_ORIGIN + path if path.startswith("/") and not path.startswith("//") else path
        parts = urlsplit(url)
        if (parts.scheme != "https" or parts.netloc != "api.appstoreconnect.apple.com"
                or not parts.path.startswith("/v1/") or parts.fragment or "\\" in url):
            raise ReleaseError("Refused an API URL outside the Apple App Store Connect host.")
        try:
            response = self.session.request(
                method, url, params=params, json=body,
                headers={"Authorization": "Bearer " + self.token_provider(), "Accept": "application/json"},
                timeout=(10, 30), allow_redirects=False,
            )
        except requests.RequestException:
            raise ReleaseError("App Store Connect network request failed; check connectivity and retry.") from None
        if not 200 <= response.status_code < 300:
            # Apple error details can echo submitted data; never log response bodies or headers.
            code = ""
            if response.status_code == 403:
                try:
                    errors = response.json().get("errors", [])
                    value = errors[0].get("code", "")
                    if re.fullmatch(r"[A-Z][A-Z0-9_.]{0,95}", value):
                        code = f" ({value})"
                except (ValueError, AttributeError, IndexError, TypeError, KeyError):
                    pass
            raise ReleaseError(f"App Store Connect returned HTTP {response.status_code}{code}; inspect the request in App Store Connect.")
        if response.status_code == 204:
            return {}
        try:
            payload = response.json()
        except ValueError:
            raise ReleaseError("App Store Connect returned an invalid JSON response.") from None
        if not isinstance(payload, dict):
            raise ReleaseError("App Store Connect returned an unexpected response.")
        return payload

    def collection(self, path, *, params=None):
        result = {"data": [], "included": []}
        visited = set()
        while path:
            if path in visited or len(visited) >= 1000:
                raise ReleaseError("App Store Connect pagination is cyclic or exceeds the safety limit.")
            visited.add(path)
            page = self.request("GET", path, params=params)
            if not isinstance(page.get("data"), list) or not isinstance(page.get("included", []), list):
                raise ReleaseError("App Store Connect returned an invalid collection.")
            result["data"].extend(page["data"])
            result["included"].extend(page.get("included", []))
            path = page.get("links", {}).get("next")
            if path is not None and not isinstance(path, str):
                raise ReleaseError("App Store Connect returned an invalid pagination link.")
            params = None
        return result


class ReleaseManager:
    def __init__(self, client, app_id, beta_group_id=None, *, sleep=time.sleep, monotonic=time.monotonic):
        self.client = client
        self.app_id = resource_id(app_id)
        self.beta_group_id = resource_id(beta_group_id) if beta_group_id else None
        self.sleep = sleep
        self.monotonic = monotonic

    def builds(self, version, build_number=None):
        validate_version(version)
        params = {
            "filter[app]": self.app_id,
            "filter[preReleaseVersion.version]": version,
            "filter[preReleaseVersion.platform]": "IOS",
            "include": "preReleaseVersion,app",
            "fields[builds]": "version,processingState,expired,usesNonExemptEncryption,buildAudienceType,preReleaseVersion,app",
            "fields[preReleaseVersions]": "version,platform",
            "fields[apps]": "bundleId",
            "limit": 200,
        }
        if build_number is not None:
            params["filter[version]"] = validate_build(build_number)
        payload = self.client.collection("/v1/builds", params=params)
        included = {(row["type"], row["id"]): row for row in payload["included"]}
        for build in payload["data"]:
            resource_id(build.get("id"))
            prerelease = relationship(build, "preReleaseVersion")
            if not prerelease or prerelease.get("type") != "preReleaseVersions":
                raise ReleaseError("Build is missing its marketing version relationship.")
            source = included.get(("preReleaseVersions", prerelease.get("id")))
            if source is None:
                source = self.client.request("GET", "/v1/preReleaseVersions/" + resource_id(prerelease.get("id")))["data"]
            attributes = source.get("attributes", {})
            if attributes.get("version") != version or attributes.get("platform") != "IOS":
                raise ReleaseError("Build marketing version or platform does not match the requested iOS version.")
            app = relationship(build, "app")
            if not app or app.get("type") != "apps" or app.get("id") != self.app_id:
                raise ReleaseError("Build app relationship does not match ASC_APP_ID.")
            if build_number is not None and build.get("attributes", {}).get("version") != build_number:
                raise ReleaseError("Build number does not match the requested build.")
        return payload["data"]

    def next_build(self, version):
        numbers = [int(validate_build(row.get("attributes", {}).get("version"))) for row in self.builds(version)]
        return max(numbers, default=0) + 1

    def valid_build(self, version, build_number, *, timeout=0, poll_interval=30):
        validate_version(version)
        validate_build(build_number)
        if not math.isfinite(timeout) or not 0 <= timeout <= 7200:
            raise ReleaseError("Processing timeout must be between 0 and 7200 seconds.")
        if not math.isfinite(poll_interval) or not 1 <= poll_interval <= 300:
            raise ReleaseError("Polling interval must be between 1 and 300 seconds.")
        deadline = self.monotonic() + timeout
        while True:
            builds = self.builds(version, build_number)
            if len(builds) > 1:
                raise ReleaseError("Multiple builds match the requested version and number.")
            if builds:
                build = builds[0]
                attributes = build.get("attributes", {})
                state = attributes.get("processingState")
                if attributes.get("expired") is not False:
                    raise ReleaseError("Build has expired or its expiration status is unknown.")
                if state == "VALID":
                    return build
                if state != "PROCESSING":
                    raise ReleaseError("Build processing failed, is invalid, or has an unknown state.")
            remaining = deadline - self.monotonic()
            if remaining <= 0:
                raise ReleaseError("Requested build is not available and VALID within the processing timeout.")
            self.sleep(min(poll_interval, remaining))

    def beta(self, version, build_number, *, timeout=1800, poll_interval=30):
        validate_version(version)
        validate_build(build_number)
        if not self.beta_group_id:
            raise ReleaseError("ASC_BETA_GROUP_ID is required for internal TestFlight distribution.")
        group = self.client.request("GET", f"/v1/betaGroups/{self.beta_group_id}", params={
            "fields[betaGroups]": "isInternalGroup,hasAccessToAllBuilds,app",
            "include": "app", "fields[apps]": "bundleId",
        })["data"]
        app = relationship(group, "app")
        if group.get("attributes", {}).get("isInternalGroup") is not True:
            raise ReleaseError("ASC_BETA_GROUP_ID must identify an internal TestFlight group.")
        if not app or app.get("type") != "apps" or app.get("id") != self.app_id:
            raise ReleaseError("Internal TestFlight group does not belong to ASC_APP_ID.")
        build = self.valid_build(version, build_number, timeout=timeout, poll_interval=poll_interval)
        already_available = group.get("attributes", {}).get("hasAccessToAllBuilds") is True
        if not already_available:
            path = f"/v1/betaGroups/{self.beta_group_id}/relationships/builds"
            members = self.client.collection(path, params={"limit": 200})["data"]
            already_available = any(row.get("id") == build["id"] for row in members)
            if not already_available:
                self.client.request("POST", path, body={"data": [{"type": "builds", "id": build["id"]}]})
        return {"version": version, "build": build_number, "internal_beta": True, "already_available": already_available}

    def versions(self):
        return self.client.collection(f"/v1/apps/{self.app_id}/appStoreVersions", params={
            "filter[platform]": "IOS", "limit": 200,
            "fields[appStoreVersions]": "versionString,platform,appStoreState,appVersionState,build",
            "include": "build", "fields[builds]": "version",
        })["data"]

    @staticmethod
    def version_states(version):
        attributes = version.get("attributes", {})
        return {attributes[name] for name in ("appStoreState", "appVersionState") if attributes.get(name)}

    def editable_version(self, version):
        candidates = []
        for row in self.versions():
            attributes = row.get("attributes", {})
            if attributes.get("platform") != "IOS":
                raise ReleaseError("App Store Connect returned a non-iOS public version.")
            states = self.version_states(row)
            if states & ACTIVE_VERSION_STATES:
                raise ReleaseError("An iOS public version is already pending, ready for review/release, or in review; no changes made.")
            if attributes.get("versionString") == version:
                if not states or not states <= EDITABLE_VERSION_STATES:
                    raise ReleaseError("Requested public version is not editable; no changes made.")
                candidates.append(row)
        if len(candidates) != 1:
            raise ReleaseError("Create exactly one matching editable iOS version in App Store Connect before submitting.")
        resource_id(candidates[0].get("id"))
        return candidates[0]

    def draft_submission(self, version_id):
        submissions = self.client.collection("/v1/reviewSubmissions", params={
            "filter[app]": self.app_id, "filter[platform]": "IOS", "limit": 200,
            "fields[reviewSubmissions]": "platform,state",
        })["data"]
        drafts = []
        for submission in submissions:
            attributes = submission.get("attributes", {})
            if attributes.get("platform") != "IOS":
                raise ReleaseError("Review submission platform does not match iOS.")
            state = attributes.get("state")
            if state == "COMPLETE":
                continue
            if state != "READY_FOR_REVIEW":
                raise ReleaseError("An existing iOS review submission is active or unresolved; no changes made.")
            drafts.append(submission)
        if len(drafts) > 1:
            raise ReleaseError("Multiple draft review submissions need manual resolution; no changes made.")
        if not drafts:
            return None, False
        submission_id = resource_id(drafts[0].get("id"))
        items = self.client.collection(f"/v1/reviewSubmissions/{submission_id}/items", params={
            "include": "appStoreVersion", "limit": 200,
        })["data"]
        has_item = False
        for item in items:
            if item.get("attributes", {}).get("state") == "REMOVED":
                continue
            linked = relationship(item, "appStoreVersion")
            if (not linked or linked.get("type") != "appStoreVersions" or linked.get("id") != version_id
                    or item.get("attributes", {}).get("state") != "READY_FOR_REVIEW"):
                raise ReleaseError("Draft review submission contains another item or an uneditable item; no changes made.")
            has_item = True
        return submission_id, has_item

    def submit(self, version, build_number):
        validate_version(version)
        validate_build(build_number)
        public_version = self.editable_version(version)
        build = self.valid_build(version, build_number)
        attributes = build.get("attributes", {})
        if attributes.get("buildAudienceType") != "APP_STORE_ELIGIBLE":
            raise ReleaseError("Build must be eligible for App Store distribution.")
        encryption = attributes.get("usesNonExemptEncryption")
        if encryption is not None and encryption is not False:
            raise ReleaseError("Build declares non-exempt encryption; resolve export compliance manually.")
        version_id = public_version["id"]
        submission_id, has_item = self.draft_submission(version_id)
        # Recheck after all preflight reads, immediately before the first mutation.
        if self.editable_version(version)["id"] != version_id:
            raise ReleaseError("Public version changed during validation; no changes made.")
        if encryption is None:
            self.client.request("PATCH", f"/v1/builds/{build['id']}", body={"data": {
                "type": "builds", "id": build["id"], "attributes": {"usesNonExemptEncryption": False},
            }})
        linked = relationship(public_version, "build")
        if not linked or linked.get("id") != build["id"]:
            self.client.request("PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build", body={
                "data": {"type": "builds", "id": build["id"]},
            })
        if not submission_id:
            submission = self.client.request("POST", "/v1/reviewSubmissions", body={"data": {
                "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": self.app_id}}},
            }})["data"]
            submission_id = resource_id(submission.get("id"))
        if not has_item:
            self.client.request("POST", "/v1/reviewSubmissionItems", body={"data": {
                "type": "reviewSubmissionItems", "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                },
            }})
        self.client.request("PATCH", f"/v1/reviewSubmissions/{submission_id}", body={"data": {
            "type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True},
        }})
        return {"version": version, "build": build_number, "submitted": True}

    def status(self, version):
        validate_version(version)
        return {
            "version": version,
            "builds": [{"build": row["attributes"]["version"],
                        "processing": row["attributes"].get("processingState"),
                        "expired": row["attributes"].get("expired")}
                       for row in self.builds(version)],
            "public_versions": [{"version": row.get("attributes", {}).get("versionString"),
                                 "states": sorted(self.version_states(row))}
                                for row in self.versions()
                                if row.get("attributes", {}).get("versionString") == version],
        }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("next-build", "beta", "submit", "status"):
        command = commands.add_parser(name)
        command.add_argument("--version", required=True)
        if name in ("beta", "submit"):
            command.add_argument("--build", required=True)
        if name == "beta":
            command.add_argument("--timeout", type=float, default=1800)
            command.add_argument("--poll-interval", type=float, default=30)
    args = parser.parse_args(argv)
    try:
        validate_version(args.version)
        if hasattr(args, "build"):
            validate_build(args.build)
        required = ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_PATH", "ASC_APP_ID"]
        if args.command == "beta":
            required.append("ASC_BETA_GROUP_ID")
        missing = [name for name in required if not os.environ.get(name)]
        if missing:
            raise ReleaseError("Missing environment variables: " + ", ".join(missing))
        client = AppleClient(jwt_provider(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_PRIVATE_KEY_PATH"]))
        manager = ReleaseManager(client, os.environ["ASC_APP_ID"], os.environ.get("ASC_BETA_GROUP_ID"))
        if args.command == "next-build":
            print(manager.next_build(args.version))
        elif args.command == "status":
            print(json.dumps(manager.status(args.version), sort_keys=True))
        elif args.command == "beta":
            print(json.dumps(manager.beta(args.version, args.build, timeout=args.timeout, poll_interval=args.poll_interval), sort_keys=True))
        else:
            print(json.dumps(manager.submit(args.version, args.build), sort_keys=True))
        return 0
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except (KeyError, TypeError, ValueError, AttributeError):
        print("error: Unexpected App Store Connect response or invalid configuration.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
