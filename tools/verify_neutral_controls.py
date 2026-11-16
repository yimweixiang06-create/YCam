#!/usr/bin/env python3
"""Check every YCam style defaults to tone 0 / color 0 / palette 100 without built-in blur."""
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
styles = (root / "Styles.swift").read_text()
engine = (root / "FilterEngine.swift").read_text()
panels = (root / "ControlPanels.swift").read_text()
body = styles.split("var referenceControls:", 1)[1].split("var isFilm:", 1)[0]
assert "(0, 0, 1.0)" in body
assert "case .pearl: return (45, 90" not in body
assert "case .coolRose: return (35, -20" not in body
assert "var point = CGPoint(x: 0.5, y: 0.5)" in styles
assert "var intensity: Double = 1.0" in styles
assert "next.restoreStyleControls()" in panels
assert "mutating func restoreStyleControls()" in styles
# Match the live FilterEngine Snapshot path, not obsolete pre-refactor symbols.
assert "Double((snap.settings.point.x - 0.5) * 2)" in engine
assert "Double((0.5 - snap.settings.point.y) * 2)" in engine
assert "snap.settings.intensity" in engine
# The v1.11 tonal path uses anchored, five-point curves instead of
# gamma/exposure, and left/right apply hue-neutral saturation only.
assert 'out.applyingFilter("CIToneCurve"' in engine
assert '"inputPoint0": CIVector(x: 0.0, y: 0.0)' in engine
assert '"inputPoint4": CIVector(x: 1.0, y: 1.0)' in engine
assert 'kCIInputSaturationKey: 1 + color * (color >= 0 ? 0.36 : 0.24)' in engine
assert 'out.applyingFilter("CIVibrance"' not in engine
assert "defaults.color" not in engine and "defaults.tone" not in engine
recipes = styles.split("var recipe: LookRecipe {", 1)[1].split("// MARK: - 人像光效", 1)[0]
entries = re.findall(r"^[ ]*case [.](?P<name>[A-Za-z0-9_]+): return LookRecipe[(](?P<recipe>.*)[)]", recipes, re.M)
assert len(entries) == 28, f"Expected 28 styles, got {len(entries)}"
for name, recipe in entries:
    assert "softness:" not in recipe, f"{name} has unexpected soft focus"
    assert "bloom:" not in recipe, f"{name} has unexpected blurred bloom"
print(f"PASS: {len(entries)} styles use tone 0 / color 0 / palette 100, without default spatial blur.")
