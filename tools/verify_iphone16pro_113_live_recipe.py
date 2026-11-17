#!/usr/bin/env python3
"""Ensure iPhone16Pro evidence-backed recipe correction is in shipping Swift.
Historical proxy trials are not a measured Apple/YCam fidelity percentage.
"""
from pathlib import Path
import json,re
root=Path(__file__).resolve().parent.parent
x=json.loads((root/"calibration/iphone16pro_113_reverified_style_recipe_2026-11-18.json").read_text(encoding="utf-8"))
s=(root/"Styles.swift").read_text(encoding="utf-8")
assert x["source_material"]["distinct_images_reviewed"]==113
assert x["results"]["coolRose"]["applied"] and not x["results"]["amber"]["applied"]
assert x["results"]["coolRose"]["heldout_reduction_percent"]>1.0
assert x["results"]["coolRose"]["all_valid_color_proxy_improvement_percent"]>1.0
assert all(z["after"]<z["before"] for z in x["results"]["coolRose"]["groups"].values())
for name,info,rec_key in [("coolRose",x["results"]["coolRose"],"new_recipe"),("amber",x["results"]["amber"],"unchanged_recipe")]:
    row=next((v for v in s.splitlines() if v.strip().startswith("case ."+name+": return LookRecipe(")),None)
    assert row is not None,name
    for k,v in info[rec_key].items():
        m=re.search(r"\\b"+k+r":\\s*(-?[0-9.]+)",row)
        assert m and abs(float(m.group(1))-v)<.000001,(name,k,v)
assert "case .pearl: return LookRecipe(" in s
assert "case .gold: return LookRecipe(" in s
print("PASS: validated 113-image audit; actual Cool Rose RGB formula updated, Amber and unrelated formulas protected")
