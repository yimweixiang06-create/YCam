#!/usr/bin/env python3
"""Keep user screenshot references, but reject prior over-bright scene fits."""
import json,re
from pathlib import Path
root=Path(__file__).resolve().parent.parent
src=(root/"FilterEngine.swift").read_text()
styles=(root/"Styles.swift").read_text()
ref=json.loads((root/"calibration/iphone_photo_style_scene_response_2026-11-16.json").read_text())
assert ref["schema"]=="ycam-photographic-style-scene-response-v1"
assert sum(ref["styles"][k]["count"] for k in ("gold","coolRose","cool","roseGold","vibrant","neutral","warm"))==53
assert ref["styles"]["pearl"]["count"]==20
assert not ref["styles"]["warm"]["confirmed"] and not ref["styles"]["cool"]["confirmed"]
assert ref["styles"]["gold"]["confirmed"] and ref["styles"]["pearl"]["confirmed"]
assert "let response = FilterEngine.photoStyleResponse(for: snap.settings.style)" in src
assert "let gammaResponse = response.gamma" in src
assert "let exposureResponse = response.exposure" in src
assert '"inputPower": 1 - gammaResponse * tone' in src
assert "kCIInputEVKey: exposureResponse * tone" in src
assert "response.right : response.left" in src
assert "let zoneSaturation = 1.0 + (rawTone >= 0 ? 0.03 : 0.02) * rawTone" in src
assert "settings.filter == .original && settings.intensity > 0.001" in src
assert "var r = s.filter == .original" in src
assert "let lut: LutTable? = s.filter == .original" in src
assert "case .pearl: return LookRecipe(exposure: -0.015" in styles
assert "if snap.settings.filter != .original && snap.recipe.softness > 0.001" in src
assert "if snap.settings.filter != .original && snap.recipe.bloom > 0.001" in src
assert "case .pearl: return PhotoStyleResponse(gamma: 0.072" in src
assert "default: return PhotoStyleResponse(" not in src
assert "softness:" not in styles.split("var recipe: LookRecipe {",1)[1].split("// MARK: - 人像光效",1)[0]
# The old RGB proxy compared differently exposed/white-balanced iPhone
# screenshots, not paired output from YCam; never certify its parameters.
old=ref["styles"]["pearl"]["gamma"]
assert old>=0.40 and old>0.072
print("PASS: 53 user screenshots + 20 Pearl frames preserved as references; 0.48 overbright curve retired")
print("NOTE: style-specific color fidelity still needs paired Apple and YCam shots")
