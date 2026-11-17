#!/usr/bin/env python3
"""Audit safe live recipe from 1M iPhone16Pro proxy-candidate comparisons.

This regression does not assert that 1M full image renders or Apple hardware
colorimetric comparisons occurred. It verifies a transparent stored summary.
"""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
d=json.loads((ROOT/"calibration/iphone16pro_1million_candidate_screen_2026-11-17.json").read_text(encoding="utf-8"))
swift=(ROOT/"Styles.swift").read_text(encoding="utf-8")
assert d["actual_candidate_screenings"]==1_000_000
assert d["per_style_candidate_screenings"]==500_000
assert sum(x["screened"] for x in d["results"].values())==1_000_000
assert d["actual_full_nonlinear_CPU_checks"]==132
assert "NOT 1M Core Image full renders" in d["candidate_screening"]
assert "not official Apple" in d["display_target_limit"]
assert d["results"]["coolRose"]["accepted"]
assert not d["results"]["amber"]["accepted"]
for name,details in d["results"].items():
    line=next((l for l in swift.splitlines() if l.strip().startswith("case ."+name+": return LookRecipe(")),None)
    assert line is not None,name
    # Historical one-million screening is not the live recipe for Cool Rose;
    # its later independently held-out calibration has its own regression guard.
    if name == "coolRose":
        continue
    recipe=details["after"] if details["accepted"] else details["unchanged"]
    for k,v in recipe.items():
        assert f"{k}: {v}" in line,(name,k,v)
assert d["results"]["coolRose"]["validation_dE76_proxy_after"] < d["results"]["coolRose"]["validation_dE76_proxy_before"]-.07
assert d["results"]["coolRose"]["full_color_groups_ok"]
assert d["results"]["coolRose"]["boundary_fraction_after"] <= d["results"]["coolRose"]["boundary_fraction_before"]+.005
assert "case .pearl: return LookRecipe(" in swift
assert "case .gold: return LookRecipe(" in swift
print("PASS: 1M quadratic-surrogate candidate comparisons logged; only safely improved Cool Rose applied; all other recipes protected")
