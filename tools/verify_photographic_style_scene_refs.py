#!/usr/bin/env python3
"""Validate source-derived YCam photographic style processing (NOT an Apple ISP certification)."""
import json, re
from pathlib import Path
import numpy as np
root=Path(__file__).resolve().parent.parent
data=json.loads((root/"calibration/iphone_photo_style_scene_response_2026-11-16.json").read_text())
engine=(root/"FilterEngine.swift").read_text()
styles=(root/"Styles.swift").read_text()
assert data["schema"]=="ycam-photographic-style-scene-response-v1"
assert sum(data["styles"][k]["count"] for k in ["gold","coolRose","cool","roseGold","vibrant","neutral","warm"]) == 53
assert data["styles"]["pearl"]["count"] == 20
Y=np.array([0.2126,0.7152,0.0722])
regex=r"case [.]([A-Za-z0-9_]+): return PhotoStyleResponse[(]gamma: ([0-9.]+), left: ([0-9.]+), right: ([0-9.]+)[)]"
values={m.group(1):tuple(map(float,m.groups()[1:])) for m in re.finditer(regex,engine)}
assert set(data["styles"]).issubset(values), (set(data["styles"])-set(values))
assert "default: return PhotoStyleResponse(gamma: 0.10, left: 0.24, right: 0.36)" in engine
assert 'snap.settings.filter == .original && snap.settings.intensity > 0.01' in engine
assert 'settings.filter == .original && settings.intensity > 0.001' in engine
assert "let response = FilterEngine.photoStyleResponse(for: snap.settings.style)" in engine
assert '"inputPower": 1 - gammaResponse * tone' in engine
assert "response.right : response.left" in engine
assert "let zoneSaturation = 1.0 + (rawTone >= 0 ? 0.03 : 0.02) * rawTone" in engine
# Only the YCam photographed styles change, AppleFilter remains exclusive.
filters=styles.split("enum AppleFilter:",1)[1].split("// MARK: - 界面上的全部风格状态",1)[0]
assert filters.count("case .")>=20
assert "var r = s.filter == .original" in engine
assert "let lut: LutTable? = s.filter == .original" in engine
assert "case .warm: return LookRecipe(exposure: 0.04, contrast: 0.03, saturation: 1.04, temperature: 0.24, tint: 0.02)" in styles
assert "case .vibrant: return LookRecipe(exposure: -0.04" in styles
assert "case .pearl: return LookRecipe(exposure: 0.09" in styles
assert "softness:" not in styles.split("var recipe: LookRecipe {",1)[1].split("// MARK: - 人像光效",1)[0]
def simulate(center,x,t,gamma,left,right):
    upper=.08 if gamma>.20 else .28
    lower=.12 if gamma>.20 else .50
    effective_t=t*(1-(upper if t>0 else lower))
    out=np.clip(center,0.00001,1)**(1-gamma*effective_t)
    out=np.clip(out*2**(.02*effective_t),0,1)
    sat=1+x*(right if x>0 else left)
    lum=out@Y
    return np.clip(lum[:,None]+(out-lum[:,None])*sat,0,1)
total_before=total_after=0
for name,ref in data["styles"].items():
    param=tuple(ref[k] for k in ["gamma","left","right"])
    assert np.allclose(param,values[name]),(name,param,values[name])
    assert 0.20<=ref["gamma"]<=0.60 and 0.50<=ref["left"]<=0.95 and 0.45<=ref["right"]<=0.65
    if name=="pearl":continue # video has no full 4-corner scene pairs
    assert len(ref["corners"])==4
    target=np.array(ref["corners"],dtype=float)/255
    center=np.mean(target,axis=0)
    points=[(-1,1),(1,1),(-1,-1),(1,-1)]
    old=np.mean([np.abs(simulate(center,x,t,.10,.24,.36)-target[i]) for i,(x,t) in enumerate(points)])*255
    new=np.mean([np.abs(simulate(center,x,t,*param)-target[i]) for i,(x,t) in enumerate(points)])*255
    assert new<old,(name,round(old,2),round(new,2))
    total_before+=old;total_after+=new
assert not data["styles"]["warm"]["confirmed"] and not data["styles"]["cool"]["confirmed"]
assert data["styles"]["gold"]["confirmed"] and data["styles"]["pearl"]["confirmed"]
print(f"PASS: 53 screenshot samples and 20 Pearl frames; mean scene-relative RGB proxy error {total_before/7:.1f} -> {total_after/7:.1f} (not true paired-photo DeltaE)")
print("PASS: traditional filters isolated, unknown styles use old response, warm attribution provisional, no default blur")
