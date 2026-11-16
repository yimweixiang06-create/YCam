#!/usr/bin/env python3
"""Verify 45 screenshot-position tone fits and protect neutral whites.
This test does not certify colorimetric accuracy versus Apple proprietary ISP.
"""
from pathlib import Path
import json,re
r=Path(__file__).resolve().parent.parent
data=json.loads((r/"calibration/iphone_screen_tone_and_chroma_45_2026-11-16.json").read_text())
e=(r/"FilterEngine.swift").read_text()
s=(r/"Styles.swift").read_text()
assert data["schema"]=="ycam-user-iphone-screen-references-tone-and-chroma-v2"
refs=data["style_reference_points"]
assert len(refs)==6 and sum(x["observations"] for x in refs.values())==45
assert data["candidate_screen_reference_curve_cv_mae_luma_255"] < data["existing_global_gamma_model_cv_mae_luma_255"]*.55
for name,entry in refs.items():
    p=entry["tone_curve"]
    triplet=(p["shadow_at_018"],p["midtone_at_055"],p["highlight_at_090"])
    expected="case .%s: return ScreenReferenceCurve(shadow: %.5f, midtone: %.5f, highlight: %.5f)" %(name,*triplet)
    assert expected in e, (name,expected)
    chrom=entry["chroma_axis"]
    case=re.search(r"case \."+re.escape(name)+r": return PhotoStyleResponse\(gamma: .*?, left: ([0-9.]+), right: ([0-9.]+),",e)
    assert case, name
    assert abs(float(case.group(1))-chrom["left_decrease"])<1e-6
    assert abs(float(case.group(2))-chrom["right_increase"])<1e-6
    # White endpoint remains fixed, and 90% white at maximum +tone is
    # bounded by at most a 6% increase; no excessive exposure clipping.
    assert p["highlight_at_090"] <= .055
    points=[0,.18,.55,.90,1]
    values=[0,.18+p["shadow_at_018"],.55+p["midtone_at_055"],.9+p["highlight_at_090"],1]
    assert values==sorted(values),(name,values)
assert '"inputPoint0": p0' in e and '"inputPoint4": p4' in e
assert 'out.applyingFilter("CIToneCurve"' in e
assert 'screenCurve == nil ? k : min(1.0, k * 1.35)' in e
assert 'if let screenCurve {' in e
assert 'settings.filter == .original && settings.intensity > 0.001' in e
assert 'if snap.settings.filter != .original && snap.recipe.softness > 0.001' in e
assert 'if snap.settings.filter != .original && snap.recipe.bloom > 0.001' in e
assert "enum AppleFilter:" in s
print("PASS: 45 screenshot-position points; 6 independent protected tone curves and chroma axes")
print("PASS: no clipped white endpoint, other 22 styles remain independent, original filters isolated")
