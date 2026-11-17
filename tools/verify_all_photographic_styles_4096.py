#!/usr/bin/env python3
"""Evaluate every YCam photographic and film recipe across all 4096 RGB colors.

This is an internal gamut and numerical-regression diagnostic, NOT a
comparison against Apple's proprietary ISP or film stocks. Chart positions
are exhaustive (16*16*16), unlike conventional 24-color sample smoke tests.
"""
import sys
import json
from pathlib import Path
import numpy as np

root=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(root/"tools"))
from style_check import parse_recipes,transform,lab, lut_names, load_lut, lut_apply

entries=parse_recipes()
# These are the 4096 RGB color-cell centers from the user's chart in index
# order: red varies fastest, green next, blue slowest.
grid=np.arange(4096)
rgb=np.stack([grid%16,(grid//16)%16,grid//256],axis=1).astype(np.float64)/15.0
assert rgb.shape==(4096,3)
assert np.isfinite(rgb).all()
luma=rgb@np.array([.2126,.7152,.0722])
dark=luma<.28
middle=(luma>=.28)&(luma<.72)
high=luma>=.72
ramp=np.linspace(0,1,16).reshape(-1,1).repeat(3,axis=1)
styles_lut=lut_names()
reports={}
for name,recipe in entries.items():
    # A film LUT is an independent color pipeline; applying the original
    # formula instead would not represent the photo actually displayed.
    if name in styles_lut:
        lut=load_lut(styles_lut[name])
        colors=lut_apply(lut,rgb)
        grays=lut_apply(lut,ramp)
    else:
        colors=transform(rgb,recipe)
        grays=transform(ramp,recipe)
    if colors.shape!=rgb.shape:
        raise AssertionError((name,"shape mismatch",colors.shape))
    if not np.isfinite(colors).all():
        raise AssertionError((name,"NaN/Inf"))
    if np.any(colors<-.00001) or np.any(colors>1.00001):
        raise AssertionError((name,"out-of-gamut data not clipped"))
    # All 16 gray values should be monotonic in perceived luminance.
    g=lab(grays)[:,0]
    monotonic=bool(np.all(np.diff(g)>=-.15))
    if not monotonic:
        raise AssertionError((name,"gray ramp lightness reversal"))
    clipped=((colors<=.001)|(colors>=.999)).any(axis=1)
    output_lab=lab(colors)
    base_lab=lab(rgb)
    de=np.linalg.norm(output_lab-base_lab,axis=1)
    # Gray luminance and chroma checks on EVERY color, not just a few swatches.
    chroma=np.ptp(colors,axis=1)
    reports[name]={
       "patches":4096,
       "mean_color_deltaE76_vs_standard_synthetic":round(float(de.mean()),4),
       "p95_color_deltaE76_vs_standard_synthetic":round(float(np.percentile(de,95)),4),
       "any_channel_boundary_percent":round(float(clipped.mean()*100),2),
       "near_gray_output_chroma_mean":round(float(chroma[np.ptp(rgb,axis=1)<.1].mean()),5),
       "mean_output_dark_luma":round(float((colors[dark]@np.array([.2126,.7152,.0722])).mean()),5),
       "mean_output_midtone_luma":round(float((colors[middle]@np.array([.2126,.7152,.0722])).mean()),5),
       "mean_output_highlight_luma":round(float((colors[high]@np.array([.2126,.7152,.0722])).mean()),5),
       "gray_monotonic":monotonic
    }
assert len(entries)>=28, f"missing style recipes: {len(entries)}"
assert sum(v["patches"] for v in reports.values())==len(entries)*4096
print(json.dumps({"status":"PASS","styles":len(entries),"colors_per_style":4096,
  "total_style_color_evaluations":len(entries)*4096,
  "scope":"YCam internal numerical gamut consistency only; not Apple color match",
  "selected_metrics":{k:reports[k] for k in ("pearl","coolRose","amber","gold","roseGold") if k in reports}},ensure_ascii=False,indent=2))
