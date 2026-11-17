#!/usr/bin/env python3
"""Regression guard for iPhone16Pro user-photo provenance & QA gate.

Does NOT claim colorimetric equality to Apple or that trillions of model
evaluations are useful. Original private user photos remain outside repo.
"""
from pathlib import Path
import json
root=Path(__file__).resolve().parent.parent
data=json.loads((root/"calibration/iphone16pro_reference_quality_gate_2026-11-17.json").read_text(encoding="utf-8"))
photos=data["photos"]
assert data["total_photos"]==10==len(photos)
assert len({p["filename"] for p in photos})==10
assert all(p["reliable_patches"]+p["downweighted_patches"]==4096 for p in photos)
assert sum(p["reliable_patches"] for p in photos)==data["proxy_reliable_count"]==23739
assert sum(p["downweighted_patches"] for p in photos)==data["downweighted_count"]==17221
assert data["total_patch_positions"]==40960
assert sum("inferred" in p["style_association"] for p in photos)==2
assert all(p["photo_exif_srgb"] for p in photos)
assert not any(p["embedded_icc_profile"] or p["exposure_white_balance_capture_timestamp_present"] for p in photos)
assert data["validation_additional"]["resample_count"]==10000
assert data["validation_additional"]["new_proxy_dE76"]<data["validation_additional"]["old_proxy_dE76"]
assert data["production_decision"]["existing_profiles_unchanged"]
assert not data["production_decision"]["new_recipe_change"]
print("PASS: user-shot iPhone 16 Pro reference data quality gate (40960 samples, 23739 proxy-reliable); no unsupported official 1:1 claim")
