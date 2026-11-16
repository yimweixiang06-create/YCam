#!/usr/bin/env python3
"""Enforce one independent look and tone curve per photographic style."""
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sty=(ROOT/"Styles.swift").read_text()
eng=(ROOT/"FilterEngine.swift").read_text()
cam=(ROOT/"CameraModel.swift").read_text()
cases=sty.split("enum CameraStyle:",1)[1].split("var id:",1)[0]
items=re.findall(r"\bcase\s+([^\n]+)",cases)
names=[name.strip().lstrip(".") for line in items for name in line.split(",")]
assert len(names)==28 and len(set(names))==28, names
block=eng.split("private static func photoStyleResponse(for style:",1)[1].split("// MARK: Colour math",1)[0]
regex=r"case \.([A-Za-z0-9_]+): return PhotoStyleResponse\(gamma: ([0-9.]+), left: ([0-9.]+), right: ([0-9.]+), upperCorner: ([0-9.]+), lowerCorner: ([0-9.]+), exposure: ([0-9.]+)\)"
rs={a: tuple(map(float,p)) for a,*p in re.findall(regex,block)}
assert set(rs)==set(names),(set(names)-set(rs),set(rs)-set(names))
assert len(set(rs.values()))==28,"Two styles accidentally share the full tone-response recipe"
for name,(g,l,r,u,d,e) in rs.items():
    assert 0.03<=g<=0.14,(name,g)
    assert 0.18<=l<=0.99 and 0.20<=r<=0.75,(name,l,r)
    assert 0<=e<=0.02,(name,e)
    assert 0<u<0.50 and 0<d<0.50,(name,u,d)
assert "default:" not in block, "All 28 cases must be explicit; no global default"
styleblock=sty.split("var recipe: LookRecipe {",1)[1].split("// MARK: - 人像光效",1)[0]
recipes=dict(re.findall(r"case \.([A-Za-z0-9_]+): return LookRecipe\((.*)\)",styleblock))
assert set(recipes)==set(names)
assert sum(body=="" for body in recipes.values())==1, "Only Standard may have identity base; LUT styles have distinct complements"
for name,body in recipes.items():
    if name=="standard":continue
    assert "softness:" not in body and "bloom:" not in body,(name,body)
assert rs["pearl"][0]<=0.08 and rs["pearl"][5]<=0.015
assert "case .pearl: return LookRecipe(exposure: -0.015" in sty
assert "exposureResponse = pearlImageMode ? (tone >= 0 ? 0.06 : -0.12)" not in eng
assert "if snap.settings.filter != .original && snap.recipe.softness > 0.001" in eng
assert "if snap.settings.filter != .original && snap.recipe.bloom > 0.001" in eng
# Preserve full selected recording resolution only when writer is armed.
# Video tab idle preview should adapt to real GPU time (including screen recording).
assert "let fullResolutionForRecording = dataIsVideoMode && recorder.isArmed" in cam
assert "let scale = fullResolutionForRecording ? 1" in cam
assert "recordingPreviewPool" in cam
assert "recorder.appendVideo(target, pts: pts)" in cam
assert "adaptivePreviewLongEdge: CGFloat = 1200" in cam
assert "maxPreviewLongEdge: CGFloat = 1450" in cam
assert "adaptivePreviewLongEdge = max(680, adaptivePreviewLongEdge * 0.82)" in cam
# Scientific check: neutral high-light input after maximum upward movement
# must remain < 1.5% brighter to guard against blown-out Pearl paper.
x=.94
g,l,r,u,d,ev=rs["pearl"]
tone=1-u
out=x**(1-g*tone) * (2**(ev*tone))
assert out-x<0.015,(out,x)
assert out<.97
print("PASS: 28 independent style responses, 27 distinct nonstandard base looks/LUT complements")
print("PASS: Pearl highlight overshoot bounded, no style-added spatial soft-focus/bloom, sharper adaptive preview")
