#!/usr/bin/env python3
"""Generate public update metadata for a signed GitHub release only."""
import json
import os
from pathlib import Path
import re
import xml.etree.ElementTree as ET

version = os.environ["RELEASE_VERSION"]
build = int(os.environ["GITHUB_RUN_NUMBER"])
repository = os.environ["GITHUB_REPOSITORY"]
if not re.fullmatch(r"\d+\.\d+\.\d+", version) or build <= 0:
    raise SystemExit("Invalid release version or build number")

# Use the built manifest, so set_bundle_id.sh and later ID changes cannot
# accidentally advertise an update for a different application.
manifest = ET.parse(
    "build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml"
).getroot()
android = "{http://schemas.android.com/apk/res/android}"
if manifest.attrib[android + "versionCode"] != str(build):
    raise SystemExit("Built APK version code differs from update metadata")
if manifest.attrib[android + "versionName"] != version:
    raise SystemExit("Built APK version name differs from update metadata")

Path("dist/update.json").write_text(
    json.dumps(
        {
            "schema": 1,
            "version": version,
            "buildNumber": build,
            "applicationId": manifest.attrib["package"],
            "downloadUrl": f"https://github.com/{repository}/releases/download/v{version}/reading-library.apk",
        },
        indent=2,
    ) + "\n",
    encoding="utf-8",
)
