#!/usr/bin/env python3
"""Verify YCam system-level per-app language assets; no custom picker."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parent.parent
info = plistlib.loads((root / "Info.plist").read_bytes())
assert info["CFBundleLocalizations"] == ["en", "zh-Hans"]
project = (root / "YCam.xcodeproj/project.pbxproj").read_text()
for keyword in ("PBXVariantGroup", "en.lproj/Localizable.strings",
                "zh-Hans.lproj/Localizable.strings",
                "en.lproj/InfoPlist.strings",
                "zh-Hans.lproj/InfoPlist.strings",
                "Localizable.strings in Resources",
                "InfoPlist.strings in Resources"):
    assert keyword in project, keyword

def load(language):
    text = (root / f"{language}.lproj/Localizable.strings").read_text()
    items = re.findall(r'^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";$', text, re.M)
    keys = dict(items)
    assert len(keys) > 100 and len(keys) == len(items), language
    return keys

en, zh = load("en"), load("zh-Hans")
assert en.keys() == zh.keys()
for label in ("视频", "照片", "人像", "滤镜", "摄影风格", "自定义", "返回", "重置"):
    assert en[label] != label and zh[label] == label

for language in ("en", "zh-Hans"):
    data = (root / f"{language}.lproj/InfoPlist.strings").read_text()
    for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription",
                "NSPhotoLibraryAddUsageDescription", "NSPhotoLibraryUsageDescription"):
        assert f'"{key}"' in data
assert "mode.title" in (root / "CameraHomeView.swift").read_text()
assert "rawValue.ycamLocalized" in (root / "CameraControls.swift").read_text()
assert 'NSLocalizedString(self' in (root / "FilmStyleCameraApp.swift").read_text()
print(f"PASS: iOS native per-app languages en, zh-Hans, {len(en)} translated labels")
