#!/usr/bin/env python3
"""Verify screenshot-based photographic style palette ART without uploading source photos."""
import json
import re
from pathlib import Path
root = Path(__file__).resolve().parent.parent
data = json.loads((root / "calibration/iphone_palette_screenshot_rgb5x5_2026-11-16.json").read_text())
code = (root / "DotPalette.swift").read_text()
panel = (root / "ControlPanels.swift").read_text()
assert data["reviewed_screenshots"] == 59
assert data["reference_palette_screenshots"] == 53
assert sum(group["screenshots"] for group in data["groups"].values()) == 53
assert len(data["groups"]) == 7
for style in ["gold", "coolRose", "cool", "roseGold", "vibrant", "neutral"]:
    assert "case ." + style + ":" in code
    src = code.split("case ." + style + ":\n            return [", 1)[1].split("            ]", 1)[0]
    actual = [list(map(int, triple)) for triple in re.findall(r"[.]init\((\d+), (\d+), (\d+)\)", src)]
    expected = [list(rgb) for row in data["groups"][style]["rgb5x5"] for rgb in row]
    assert actual == expected, (style, len(actual), len(expected))
    assert len(set(map(tuple, actual))) >= 23, style
assert data["groups"]["unlabeledAmber"]["applied_to_ycam"] is None
assert "case .unlabeledAmber" not in code
art = code.split("private struct ScreenshotPaletteArtwork: View", 1)[1].split("/// UIKit owns palette touches", 1)[0]
assert "case .warm:" not in art
assert "if ScreenshotPaletteArtwork.supports(style)" in code
assert "let strips = 72" in code
assert art.count(".init(color: mixed[") == 5
assert "let columns = 11" in code and "let rows = 11" in code
assert 'CASpringAnimation(keyPath: "position")' in code
assert "DotPalette(point: $camera.styleSettings.point," in panel
assert ".frame(width: 110 * m.s, height: 110 * m.s)" in panel
assert "TickSlider(value: $camera.styleSettings.intensity)" in panel
print("PASS: 59 screenshots reviewed; 6 × 25 RGB style palette samples; 1 unnamed group retained safely, original YCam UI & filters untouched")
