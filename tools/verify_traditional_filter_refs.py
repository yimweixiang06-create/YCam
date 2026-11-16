#!/usr/bin/env python3
"""Compare ordinary Apple-style filter recipes against supplied iPhone camera
screenshots. Medians were measured on the same five broad scene regions.
Screenshots are NOT raw, registered Apple pipeline reference pairs; camera
auto-exposure and AWB can change between screenshots. Use tolerant criteria.
Photographic Styles (CameraStyle) must remain untouched.
"""
import re
from pathlib import Path
import numpy as np
import style_check as sc

root=Path(__file__).resolve().parent.parent
styles=(root/"Styles.swift").read_text(encoding="utf-8")
engine=(root/"FilterEngine.swift").read_text(encoding="utf-8")
model=(root/"CameraModel.swift").read_text(encoding="utf-8")
p=styles.split("enum AppleFilter:",1)[1].split("// MARK: - 界面上的全部风格状态",1)[0]
look={}
for name,recipe in re.findall(r"case [.]([A-Za-z0-9_]+): return LookRecipe[(](.*)[)]$",p,re.M):
    v=dict(sc.IDENT)
    for part in sc.split_top(recipe):
        key,value=(x.strip() for x in part.split(":",1))
        v[key]=float(value)
    look[name]=v
assert len(look)==10
# Region order: paper, paper_shadow, counter, lower_stone, plastic_lid.
# Observations rounded from user screenshots IMG_3120 (ORIGINAL),
# IMG_3122 VIVID WARM, IMG_3123 VIVID COOL, IMG_3124 DRAMATIC,
# IMG_3125 DRAMATIC WARM, IMG_3127 MONO, IMG_3128 SILVERTONE, IMG_3129 NOIR.
refs={
    "original": [[194,194,190],[196,194,192],[135,125,107],[152,141,125],[147,146,135]],
    "vividWarm": [[220,210,195],[220,207,195],[183,146,116],[198,166,140],[181,162,143]],
    "vividCool": [[209,218,224],[207,216,224],[145,149,144],[167,170,166],[155,178,179]],
    "dramatic": [[205,203,202],[204,199,199],[134,131,113],[158,151,136],[144,152,143]],
    "dramaticWarm": [[205,195,171],[206,193,170],[122,109,93],[147,133,115],[133,138,121]],
    "mono": [[210,210,210],[206,206,206],[129,129,129],[152,152,152],[148,148,148]],
    "silvertone": [[228,225,218],[227,223,217],[150,147,138],[179,176,165],[182,179,168]],
    "noir": [[224,224,224],[220,220,220],[124,124,124],[154,154,154],[157,157,157]],
}
src=np.asarray(refs["original"],dtype=np.float64)/255
errors={}
outputs={}
for name,target in refs.items():
    out=sc.transform(src,look[name])
    actual=np.asarray(target,dtype=np.float64)/255
    mae=float(np.abs(out-actual).mean())
    errors[name]=mae
    outputs[name]=out
    # Wide bound recognizes small framing and hardware-auto-WB differences.
    assert mae < 0.070,(name,mae)
assert outputs["vividWarm"][0,0] > outputs["vividWarm"][0,2] + 0.07
assert outputs["vividCool"][0,2] > outputs["vividCool"][0,0] + 0.04
assert outputs["dramaticWarm"][0,0] > outputs["dramaticWarm"][0,2] + 0.07
assert np.max(np.ptp(outputs["mono"],axis=1)) < .00001
assert np.max(np.ptp(outputs["noir"],axis=1)) < .00001
lum=lambda a:a@np.array([.2126,.7152,.0722])
assert lum(outputs["silvertone"][0]) > lum(outputs["mono"][0]) + .015
assert lum(outputs["noir"][0]) > lum(outputs["mono"][0]) + .015
assert np.allclose(outputs["original"],src,atol=.00005)
# Crucial isolation: a traditional filter must not double with 28
# photographic style recipes, 9 FUJI LUTs or 2D palette axes.
assert 'var r = s.filter == .original' in engine
assert '? s.style.recipe.scaled(by: k)' in engine
assert ': s.filter.recipe' in engine
assert 'let lut: LutTable? = s.filter == .original' in engine
assert 'settings.filter == .original && settings.intensity > 0.001' in engine
# Hardware automatic white balance explicitly re-applied on initialization
# and after camera change. Original color path gets no software yellow tint.
assert model.count("applyWhiteBalance(whiteBalanceKelvin, device)") >= 2
assert 'device.whiteBalanceMode = .continuousAutoWhiteBalance' in model
print("PASS: 7 screenshot-referenced traditional looks + original, original filter isolation, automatic white balance path")
print("Screenshot chart RGB mean absolute errors (0..255):",
      {name:round(err*255,1) for name,err in errors.items()})
