#!/usr/bin/env python3
"""Cheap, offline validation of metadata and bundled privacy resources."""
import json
import plistlib
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    metadata = json.loads((ROOT / "AppStore/metadata.json").read_text())
    assert 1 <= len(metadata["name"]) <= 30, "App name exceeds Apple's limit"
    for locale, fields in metadata["localizations"].items():
        for name, limit in (("subtitle", 30), ("promotional_text", 170), ("description", 4000), ("keywords", 100)):
            assert 0 < len(fields[name]) <= limit, f"{locale} {name} exceeds {limit} characters"
        assert len(fields["keywords"].encode()) <= 100, f"{locale} keywords exceed 100 bytes"
    icon = (ROOT / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png").read_bytes()
    assert icon[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", icon[16:24]) == (1024, 1024)
    assert icon[25] == 2, "App icon must be opaque RGB"
    with (ROOT / "App/PrivacyInfo.xcprivacy").open("rb") as source:
        privacy = plistlib.load(source)
    assert privacy["NSPrivacyTracking"] is False
    assert privacy["NSPrivacyCollectedDataTypes"] == []
    assert any(item["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryUserDefaults"
               and "CA92.1" in item["NSPrivacyAccessedAPITypeReasons"] for item in privacy["NSPrivacyAccessedAPITypes"])
    project = (ROOT / "TankarrReader.xcodeproj/project.pbxproj").read_text()
    assert 'App/PrivacyInfo.xcprivacy' in project, "Privacy manifest must be included in the app target"
    assert any(item["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryDiskSpace"
               and "E174.1" in item["NSPrivacyAccessedAPITypeReasons"] for item in privacy["NSPrivacyAccessedAPITypes"])
    print("Store metadata, opaque 1024px icon and bundled privacy manifest: OK")


if __name__ == "__main__":
    main()
