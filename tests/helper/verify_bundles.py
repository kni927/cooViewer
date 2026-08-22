#!/usr/bin/env python3
import plistlib
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


if len(sys.argv) != 2:
    fail("usage: verify_bundles.py /path/to/cooViewer.app")

app = Path(sys.argv[1])
helpers = list((app / "Contents" / "Helpers").glob("*.app"))
if len(helpers) != 1:
    fail(f"expected exactly one embedded helper, found {len(helpers)}")

with (app / "Contents" / "Info.plist").open("rb") as stream:
    main_info = plistlib.load(stream)
with (helpers[0] / "Contents" / "Info.plist").open("rb") as stream:
    helper_info = plistlib.load(stream)

expected = {
    "CFBundleIdentifier": "jp.coo.cooViewer.NewWindowHelper",
    "CFBundleDisplayName": "cooViewer (New Window)",
    "LSUIElement": True,
}
for key, value in expected.items():
    if helper_info.get(key) != value:
        fail(f"helper {key} is {helper_info.get(key)!r}, expected {value!r}")

if main_info.get("CFBundleIdentifier") != "jp.coo.cooViewer":
    fail("unexpected main bundle identifier")
if main_info.get("CFBundleDocumentTypes") != helper_info.get("CFBundleDocumentTypes"):
    fail("main/helper document claims diverge")
if "CFBundleURLTypes" in helper_info:
    fail("helper must not register the private URL scheme")
if main_info.get("CooViewerNewWindowScheme") != "cooviewer-new-window":
    fail("main private URL scheme setting is missing")

print(f"PASS: one helper at {helpers[0]}")
print(f"PASS: {len(main_info['CFBundleDocumentTypes'])} document declarations match")
