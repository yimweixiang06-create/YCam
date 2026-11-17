#!/usr/bin/env python3
"""Check 113 recovered iPhone16Pro image-by-image CPU proxy result coverage.

The per-image evidence is from offline CPU screening, NOT from true Apple/YCam
matched camera images. This guard checks record integrity and source set.
"""
import json,base64,zlib,pathlib
root=pathlib.Path(__file__).resolve().parent.parent
report=json.loads((root/"calibration/iphone16pro_113_10m_coverage_2026-11-18.json").read_text(encoding="utf-8"))
source=zlib.decompress(base64.b85decode((root/"calibration/iphone16pro_recovered_113_photo_samples.b85").read_text(encoding="utf-8").strip()))
assert len(source)==113*34
known={source[k:k+6].hex() for k in range(0,len(source),34)}
lines=report["results"]
ids=[line[0] for line in lines]
assert len(known)==113==len(lines)==len(set(ids))
assert set(ids)==known
assert all(row[1]==1 for row in lines), "every image must record 10M comparisons"
assert all(row[2] in (0,1) for row in lines)
assert sum(row[2] for row in lines)==report["proxy_holdout_improved_images"]==99
assert len(lines)-sum(row[2] for row in lines)==report["proxy_holdout_not_improved_images"]==14
assert report["actual_candidate_scores"]==report["completed_images"]*report["candidates_per_image"]==1_130_000_000
assert not report["modified_color_recipes"]
assert not report["raw_photo_bytes_published"]
assert "NOT real Apple-native/YCam" in report["comparison_method"]
print("PASS: 113/113 unique original iPhone16Pro image SHA fingerprints, 10M logged CPU proxy scores per image, 1.13B total; no unsupported Apple fidelity claim.")
