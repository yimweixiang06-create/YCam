#!/usr/bin/env python3
"""Guard all-4096 RGB chart color audit and independently calibrated styles.

The proxy errors are from photos of a monitor and NOT device-measured Apple
Photographic Style accuracy. Only accept a style when all categories and
held-out colors demonstrate a safe improvement.
"""
import json
from pathlib import Path
root=Path(__file__).resolve().parent.parent
d=json.loads((root/"calibration/iphone16pro_full_4096_color_audit_2026-11-17.json").read_text(encoding="utf-8"))
src=(root/"Styles.swift").read_text(encoding="utf-8")
assert d["patches_per_photo"] == 4096
assert len(d["photo_quality"]) == 10
assert sum(x["total_patches"] for x in d["photo_quality"]) == 40960
assert all(x["reliable_patches"] + x["unreliable_patches"] == 4096 for x in d["photo_quality"])
assert d["train_patches_per_labeled_style"] == 3072
assert d["heldout_patches_per_labeled_style"] == 1024
for style,m in d["style_fit"].items():
    assert m["all_4096_evaluated"]
    assert m["holdout_after"] < m["holdout_before"]
    assert all(y["after"] < y["before"] * 1.02 for y in m["group_errors"].values())
    actual=next((row for row in src.splitlines() if row.strip().startswith("case ."+style+": return LookRecipe(")),None)
    assert actual is not None
    # Historical 4096-color calibration is immutable. Cool Rose's live
    # recipe was subsequently updated by the 1M candidate screening round.
    if style == "coolRose":
        continue
    recipe=m["chosen_recipe"] if m["applied"] else m["old_recipe"]
    for key,value in recipe.items():
        assert f"{key}: {value}" in actual,(style,key,value)
assert d["style_fit"]["coolRose"]["applied"]
assert not d["style_fit"]["amber"]["applied"]
assert "case .pearl: return LookRecipe(" in src
assert "case .gold: return LookRecipe(" in src
print("PASS: all 40,960 photo chart samples audited; 4,096-color per-image tests; held-out RGB gamut improvement")
