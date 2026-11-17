#!/usr/bin/env python3
"""Regression checks for real 5000 x 2 photo-proxy candidate evaluations.
No claim of official Apple fidelity or ΔE2000.
"""
import json
from pathlib import Path
p=Path(__file__).resolve().parent.parent
data=json.loads((p/"calibration/iphone16pro_5000_candidate_fit_2026-11-17.json").read_text(encoding="utf-8"))
source=(p/"Styles.swift").read_text(encoding="utf-8")
assert data["trial_count_total"]==10000
assert data["per_style_trials"]==5000
assert "not Apple-native-vs-YCam" in data["measurement"]
assert data["models"]["coolRose"]["applied"]
assert not data["models"]["amber"]["applied"]
for key,info in data["models"].items():
    assert info["evaluations"]==5000 and info["training_patches"]==384
    assert info["heldout_patches"]==256 and info["heldout_loss_selected"]<info["heldout_loss_before"]
    line=next((s for s in source.splitlines() if s.strip().startswith(f"case .{key}: return LookRecipe(")),None)
    assert line is not None, key
    expected=info["new_recipe"] if info["applied"] else info["starting_recipe"]
    for parameter,value in expected.items():
        assert f"{parameter}: {value}" in line,(key,parameter,value)
# Preserve hard-won distinction between Amber and Gold (original amber remains).
assert "case .gold: return LookRecipe(exposure: 0.012, contrast: 0.075, saturation: 0.97" in source
assert "case .pearl: return LookRecipe(" in source
print("PASS: 10,000 actual iPhone16Pro photo-proxy trials; CoolRose improvement and Amber/Gold safety guard")
