#!/usr/bin/env python3
"""Guard verified iPhone16Pro 1,000-trial blended color recipes.

The reported proxy is not actual Apple/YCam paired-image accuracy.
"""
import json
from pathlib import Path
root = Path(__file__).resolve().parent.parent
src = (root / "Styles.swift").read_text(encoding="utf-8")
data = json.loads((root / "calibration/iphone16pro_1000_candidate_fit_2026-11-17.json").read_text(encoding="utf-8"))
assert data["actual_trials_per_style"] == 1000
assert data["actual_trial_total"] == 2000
assert "NOT a verified Apple camera similarity" in data["loss"]
for style, info in data["results"].items():
    assert info["trial_count"] == 1000
    assert info["holdout_dE76_proxy_deployed"] < info["holdout_dE76_proxy_before"]
    line = next((row for row in src.splitlines() if row.strip().startswith("case ." + style + ": return LookRecipe(")), None)
    assert line is not None, style
    for key, value in info["new"].items():
        assert f"{key}: {value}" in line, (style, key, value)
assert "case .pearl: return LookRecipe(" in src
print("PASS: 1,000 trials per identified iPhone16Pro style and CV-tested blended recipe values")
