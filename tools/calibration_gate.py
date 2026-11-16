#!/usr/bin/env python3
"""YCam 2,000-photo gate and exact 28-style/10-filter label checks.

A Wikimedia photograph is not by itself a target preset reference. Pair labels
must be verified before any automatic color fitting can use them.
The gate writes a report but never changes Swift/LUT or publishes an IPA.
"""
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIN_PHOTOS = 2000
MIN_TRAIN_PAIRS = 15
MIN_HOLDOUT_PAIRS = 5


def expected_effects():
    source = (ROOT / "Styles.swift").read_text(encoding="utf8")
    def enum_cases(name):
        part = source.split("enum "+name+":", 1)[1].split("var id: String", 1)[0]
        keys = []
        for line in re.findall(r"^\s*case ([A-Za-z0-9_, ]+)$", part, re.M):
            keys.extend(k.strip() for k in line.split(",") if k.strip())
        if len(keys) != len(set(keys)):
            raise ValueError("Duplicate "+name+" case")
        return keys
    styles = enum_cases("CameraStyle")
    filters = enum_cases("AppleFilter")
    if len(styles) != 28 or len(filters) != 10:
        raise ValueError(f"Expected 28/10 effects, got {len(styles)}/{len(filters)}")
    # Stable, disjoint source-code keys. Never infer a target style from a file name.
    return {"style:"+k: {"family":"style","swift_case":k} for k in styles} | {
        "filter:"+k: {"family":"filter","swift_case":k} for k in filters
    }


def verify_pair(pair, effects):
    if not isinstance(pair, dict):
        raise ValueError("Pair must be a JSON object")
    effect = pair.get("effect_key")
    if effect not in effects:
        raise ValueError("Unknown or mismatched preset identity: "+str(effect))
    if not pair.get("same_scene_verified") or not pair.get("target_preset_verified"):
        raise ValueError(f"{effect}: pair lacks independent scene/preset verification")
    for field in ("original_sha256","target_sha256"):
        if not re.fullmatch(r"[0-9a-fA-F]{64}",str(pair.get(field,""))):
            raise ValueError(f"{effect}: missing validated {field}")
    if pair["original_sha256"] == pair["target_sha256"]:
        raise ValueError(f"{effect}: original and target cannot be identical")
    if not pair.get("license_permission_verified") or not pair.get("camera_model"):
        raise ValueError(f"{effect}: provenance / usage rights missing")
    for field in ("original_url","target_url"):
        if not str(pair.get(field,"")).startswith("https://"):
            raise ValueError(f"{effect}: missing HTTPS photo source for {field}")
    for field in ("lighting_description","color_profile","tone_color_strength"):
        if not pair.get(field):
            raise ValueError(f"{effect}: missing image and control matching metadata: {field}")

    # The source photograph's actual on-device tone, color and strength must
    # be documented, not guessed from a color swatch or random test category.
    controls = pair["tone_color_strength"]
    if not isinstance(controls, dict):
        raise ValueError(f"{effect}: tone_color_strength must be an exact control record")
    for name, lower, upper in (("tone", -100, 100), ("color", -100, 100),
                                ("intensity", 0, 100)):
        v = controls.get(name)
        if isinstance(v, bool) or not isinstance(v, (int, float)) or not lower <= v <= upper:
            raise ValueError(f"{effect}: missing / out-of-range {name}")
    x = (controls["color"] + 100) / 200
    y = (100 - controls["tone"]) / 200
    location = pair.get("normalized_point")
    if not isinstance(location, dict) or not all(
        isinstance(location.get(axis), (int, float)) and
        not isinstance(location.get(axis), bool) for axis in ("x", "y")
    ) or abs(location["x"] - x) > 0.005 or abs(location["y"] - y) > 0.005:
        raise ValueError(f"{effect}: grid position does not match photographed tone/color values")
    if not re.fullmatch(r"[0-9a-fA-F]{64}",str(pair.get("controls_evidence_sha256",""))):
        raise ValueError(f"{effect}: missing verifiable screenshot of actual control position")
    if not pair.get("reference_effect_source_verified"):
        raise ValueError(f"{effect}: no independent verification of real on-camera effect")
    return effect


def evaluate(state, latest, manifest, effects):
    historical_ids = state.get("seen_ids",[])
    if not isinstance(historical_ids,list) or len(historical_ids) != len(set(historical_ids)):
        raise ValueError("Duplicate / invalid state source IDs")
    candidates = int(state.get("cumulative_candidates",0))
    photo_evidence = int(state.get("verified_photos",0))
    counts = state.get("effect_counts",{})
    if not isinstance(counts,dict) or any(int(v) < 0 for v in counts.values()):
        raise ValueError("Invalid effect test coverage")
    expected_internal = set(k.removeprefix("style:") if k.startswith("style:") else k for k in effects)
    if not set(counts).issubset(expected_internal):
        raise ValueError("Unknown source effect key in test coverage")
    if candidates < 0 or photo_evidence < 0 or photo_evidence > candidates:
        raise ValueError("Impossible cumulative totals")
    if candidates > len(set(historical_ids)) or sum(int(v) for v in counts.values()) != candidates:
        raise ValueError("Cumulative count is not backed by unique IDs/effect assignments")
    if latest.get("cumulative_photo_candidates") != candidates:
        raise ValueError("Report does not match cached count")
    if int(latest.get("cumulative_photographic_evidence",-1)) != photo_evidence:
        raise ValueError("Report does not match strict photographic evidence count")
    new_samples = latest.get("samples",[])
    if int(latest.get("actual_valid_unique",-1)) != len(new_samples):
        raise ValueError("Run photo count does not match per-photo evidence")
    for item in new_samples:
        tested = item.get("evaluated_effect_key")
        canonical = ("filter:"+tested.split(":",1)[1] if isinstance(tested,str) and tested.startswith("filter:") else "style:"+str(tested))
        if canonical not in effects:
            raise ValueError("Run tested an invalid effect: "+str(tested))
        if item.get("source_effect_label_verified") or item.get("ground_truth_reference_effect_key"):
            raise ValueError("Unpaired images must not claim a real preset identity")
        if not item.get("source") or not item.get("license") or not item.get("source_file_sha1"):
            raise ValueError("Sample missing source, rights or identity")
    if not isinstance(manifest, list):
        raise ValueError("Paired reference manifest must be an array")
    pair_ids, by_effect, holdout = set(), Counter(), Counter()
    for pair in manifest:
        effect = verify_pair(pair,effects)
        unique_id = (pair["original_sha256"],pair["target_sha256"])
        if unique_id in pair_ids:
            raise ValueError("Duplicate reference pair")
        pair_ids.add(unique_id)
        by_effect[effect] += 1
        # Deterministic 80:20 independent validation cohort.
        if int(pair["original_sha256"][-2:],16) % 5 == 0:
            holdout[effect] += 1
    train = {name:by_effect[name]-holdout[name] for name in effects}
    photo_gate = photo_evidence >= MIN_PHOTOS
    independently_validated = all(train[k] >= MIN_TRAIN_PAIRS and holdout[k] >= MIN_HOLDOUT_PAIRS for k in effects)
    # Even if sample size is sufficient, applying changes additionally requires
    # a separate fitter comparing current and proposed parameters against holdout.
    report = {
        "utc":datetime.now(timezone.utc).isoformat(),
        "photo_candidate_count":candidates,
        "photo_verified_count":photo_evidence,
        "minimum_photo_requirement":MIN_PHOTOS,
        "minimum_reached":photo_gate,
        "must_continue_collecting":not photo_gate,
        "effect_key_semantics":"style:SwiftCase or filter:SwiftCase; test assignment does NOT label a source photo",
        "effect_count":len(effects),
        "per_effect_test_coverage":{
            name:counts.get(name.removeprefix("style:"),0) if name.startswith("style:") else counts.get(name,0)
            for name in effects},
        "confirmed_original_target_pairs":len(manifest),
        "per_effect_paired_evidence":{
            k:{"train":train[k],"holdout":holdout[k]} for k in effects},
        "pair_gate_reached":independently_validated,
        "automatic_color_fit_permitted":bool(photo_gate and independently_validated),
        "automatic_color_change_performed":False,
        "second_comparison_performed":False,
        "ipa_built_or_released":False,
        "reason":("Collect until at least 2000 photograph-evidenced, unique, licensed samples."
                  if not photo_gate else
                  "Need verified, exact-effect original/target pairs and an independent holdout comparison."
                  if not independently_validated else
                  "All evidence gates passed; fit and holdout comparison must still prove improvement before editing Swift/LUT."),
    }
    return report


def main():
    expected = expected_effects()
    cache = ROOT / ".cache" / "ycam_photo_seen.json"
    latest_file = ROOT / "reports" / "continuous" / "latest.json"
    manifest_path = ROOT / "calibration" / "reference_pairs.json"
    state = json.loads(cache.read_text(encoding="utf8"))
    latest = json.loads(latest_file.read_text(encoding="utf8"))
    manifest = json.loads(manifest_path.read_text(encoding="utf8")) if manifest_path.exists() else []
    result = evaluate(state,latest,manifest,expected)
    out = ROOT / "reports" / "continuous" / "readiness.json"
    out.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf8")
    summary = (
        "\n## 2000 张正式校准准入检测\n"
        f"- 来源已去重的图片候选：{result['photo_candidate_count']}\n"
        f"- 有明确实拍分类证据的图片：{result['photo_verified_count']} / {MIN_PHOTOS}\n"
        f"- 确认同场景、滤镜身份正确的原图/效果图配对：{result['confirmed_original_target_pairs']}\n"
        f"- 摄影风格：28，滤镜：10；仅供测试的效果身份不能当成图片真实效果。\n"
        f"- 已更改滤镜参数：否；执行二次准确度对比：否；发布 IPA：否。\n"
        f"- 判定：{result['reason']}\n"
    )
    if Path("/dev/null").exists():
        import os
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf8") as s:
                s.write(summary)
    print(summary)
    return 0

if __name__=="__main__":
    raise SystemExit(main())
