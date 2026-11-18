#!/usr/bin/env python3
"""Audited, per-unique-image RGB proxy screening for YCam.

Each completed pass actually evaluates 50,000,000 six-parameter candidate
vectors for ONE recovered 3x3 RGB sample from the 113-image inventory.
A second separate pass reaches 100M/image before the workflow ends.

IMPORTANT: The stored samples are NOT full photos/videos, are not verified
same-scene Apple/YCam pairs, and are not Core Image renders. Do not publish
camera recipes or IPA based on this proxy's scores.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import sys
import time

import numpy as np
from ycam_each_image_10m import GROUPS, LIMITS, fit_matrices, load

HERE = Path(__file__).resolve().parent.parent
PASS_SIZE = 50_000_000
TARGET_PASSES = 2
SCHEMA = 2


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    temp.replace(path)


def new_ledger(images):
    return {
        "schema": SCHEMA,
        "created_utc": utc_now(),
        "updated_utc": utc_now(),
        "source": "calibration/iphone16pro_recovered_113_photo_samples.b85",
        "reference_format": "nine 3x3 RGB samples per user-derived image, not full original photos",
        "unique_image_count": len(images),
        "minimum_complete_pass_per_image": PASS_SIZE,
        "target_complete_passes_per_image": TARGET_PASSES,
        "real_Apple_YCam_matched_image_pairs": 0,
        "verified_full_CoreImage_renders": 0,
        "videos_audited": 0,
        "styles_swift_edited": False,
        "ipa_published": False,
        "limitations": [
            "One candidate comparison = one six-parameter quadratic RGB proxy score.",
            "No pixels of original full-size images are rendered.",
            "Nine recovered RGB samples per ID are not sufficient for actual Apple camera fidelity.",
            "Group median is not a matched Apple native/YCam capture pair.",
            "Video files and reference Apple/YCam paired renders are not included in this dataset.",
            "This ledger must not be interpreted as 100% Apple reproduction.",
        ],
        "images": {
            image["id"]: {
                "category": image["group"],
                "completed_50m_passes": [],
                "attempts": [],
                "actual_candidate_comparisons": 0,
            }
            for image in images
        },
    }


def load_ledger(ledger_path, images):
    ids = {image["id"] for image in images}
    if ledger_path.exists():
        ledger = json.loads(ledger_path.read_text(encoding="utf8"))
        if ledger.get("schema") != SCHEMA or set(ledger.get("images", {})) != ids:
            raise RuntimeError("Ledger schema or 113-image identity mismatch; refusing to count.")
        for image in images:
            if ledger["images"][image["id"]]["category"] != image["group"]:
                raise RuntimeError("Image ID/category changed: " + image["id"])
        return ledger
    return new_ledger(images)


def choose_batch(images, ledger, max_images):
    # First give every unique image one full 50M pass; only then start pass #2.
    for target_passes in range(1, TARGET_PASSES + 1):
        pending = [image for image in images
                   if len(ledger["images"][image["id"]]["completed_50m_passes"]) < target_passes]
        if pending:
            return pending[:max_images]
    return []


def evaluate_50m(image, reference, run_key, pass_number, seconds):
    (H, g, c), (Hv, gv, cv) = fit_matrices(reference, image["rgb"])
    regularized = H + np.eye(6) * 0.02
    try:
        center = np.clip(-np.linalg.solve(regularized, g), -LIMITS, LIMITS)
    except np.linalg.LinAlgError:
        center = np.zeros(6)
    digest = hashlib.sha256(
        (image["id"] + ":" + str(pass_number) + ":" + run_key).encode("ascii")
    ).digest()
    rng = np.random.default_rng(int.from_bytes(digest[:8], "big"))
    best = np.zeros(6)
    best_score = c
    count = 0
    start = time.monotonic()
    while count < PASS_SIZE:
        if time.monotonic() - start >= seconds:
            break
        n = min(200_000, PASS_SIZE - count)
        points = rng.uniform(-1, 1, (n, 6)) * LIMITS
        around = int(n * 0.70)
        points[:around] = np.clip(
            center + rng.normal(0, 0.15, (around, 6)) * LIMITS, -LIMITS, LIMITS
        )
        # These n floating-point scores are really evaluated, not assumed.
        scores = np.einsum("ni,ij,nj->n", points, regularized, points, optimize=True)
        scores += 2.0 * (points @ g)
        scores += c
        i = int(np.argmin(scores))
        if float(scores[i]) < best_score:
            best_score = float(scores[i])
            best = points[i].copy()
        count += n
    heldout = float(best @ Hv @ best + 2.0 * (gv @ best) + cv)
    return {
        "image_id": image["id"],
        "category": image["group"],
        "pass_number": pass_number,
        "status": "COMPLETE" if count == PASS_SIZE else "PARTIAL",
        "actual_candidate_comparisons": count,
        "required_for_one_pass": PASS_SIZE,
        "training_rgb_proxy_sse_before": round(c, 8),
        "training_rgb_proxy_sse_after": round(best_score, 8),
        "heldout_rgb_proxy_sse_before": round(cv, 8),
        "heldout_rgb_proxy_sse_after": round(heldout, 8),
        "heldout_proxy_improved": heldout < cv,
        "suggested_delta_NOT_APPLIED": np.round(best, 8).tolist(),
        "full_image_rendered": False,
        "official_Apple_fidelity_verified": False,
        "elapsed_seconds": round(time.monotonic() - start, 3),
    }


def summary(ledger):
    entries = ledger["images"].values()
    stats = {
        "total_unique_image_ids": len(ledger["images"]),
        "actual_candidate_comparisons": sum(
            entry["actual_candidate_comparisons"] for entry in entries
        ),
        "unique_images_with_full_50m_pass": sum(
            len(entry["completed_50m_passes"]) >= 1
            for entry in ledger["images"].values()
        ),
        "unique_images_with_full_100m_passes": sum(
            len(entry["completed_50m_passes"]) >= TARGET_PASSES
            for entry in ledger["images"].values()
        ),
    }
    stats["categories"] = {}
    for group in GROUPS:
        items = [entry for entry in ledger["images"].values()
                 if entry["category"] == group]
        completed = [entry for entry in items if entry["completed_50m_passes"]]
        two_pass = [entry for entry in items
                    if len(entry["completed_50m_passes"]) >= TARGET_PASSES]
        heldout = [entry["completed_50m_passes"][-1]
                   for entry in completed]
        stats["categories"][group] = {
            "total_ids": len(items),
            "complete_50m_distinct": len(completed),
            "complete_100m_distinct": len(two_pass),
            "heldout_proxy_sse_before_average_among_completed": (
                round(sum(x["heldout_rgb_proxy_sse_before"] for x in heldout) / len(heldout), 8)
                if heldout else None
            ),
            "heldout_proxy_sse_after_average_among_completed": (
                round(sum(x["heldout_rgb_proxy_sse_after"] for x in heldout) / len(heldout), 8)
                if heldout else None
            ),
        }
    stats["target_met"] = stats["unique_images_with_full_100m_passes"] == 113
    return stats


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ledger-root", default="audit")
    parser.add_argument("--images-per-run", type=int, default=2)
    parser.add_argument("--seconds-per-image", type=int, default=420)
    parser.add_argument("--needs-more", action="store_true")
    args = parser.parse_args()
    if not (1 <= args.images_per_run <= 4):
        parser.error("--images-per-run must be between 1 and 4")

    images = load()
    base = Path(args.ledger_root) / "reports/iphone16pro_50m"
    ledger_file = base / "audit_50m_state.json"
    ledger = load_ledger(ledger_file, images)
    if args.needs_more:
        stats = summary(ledger)
        print(json.dumps(stats, ensure_ascii=False, sort_keys=True))
        raise SystemExit(1 if stats["target_met"] else 0)

    run_id = os.getenv("GITHUB_RUN_ID", "manual")
    attempt = os.getenv("GITHUB_RUN_ATTEMPT", "1")
    run_key = run_id + "-" + attempt
    per_run_file = base / "runs" / (run_key + ".json")
    if per_run_file.exists():
        raise SystemExit("Same run/attempt already recorded; rejecting duplicate accounting.")

    batch = choose_batch(images, ledger, args.images_per_run)
    medians = {
        group: np.median(np.array([img["rgb"] for img in images
                                    if img["group"] == group]), axis=0)
        for group in GROUPS
    }
    report = {
        "run_key": run_key,
        "workflow_sha": os.getenv("GITHUB_SHA"),
        "started_utc": utc_now(),
        "finished_utc": None,
        "selected_unique_image_ids": [img["id"] for img in batch],
        "per_image": [],
        "proxy_only_not_full_image_render": True,
    }

    for image in batch:
        record = ledger["images"][image["id"]]
        pass_number = len(record["completed_50m_passes"]) + 1
        row = evaluate_50m(
            image, medians[image["group"]], run_key, pass_number,
            args.seconds_per_image
        )
        row["run_key"] = run_key
        if any(x["run_key"] == run_key for x in record["attempts"]):
            raise RuntimeError("Duplicate run/image attempt detected.")
        record["attempts"].append({
            "run_key": run_key,
            "pass_number": pass_number,
            "status": row["status"],
            "actual_candidate_comparisons": row["actual_candidate_comparisons"],
        })
        record["actual_candidate_comparisons"] += row["actual_candidate_comparisons"]
        if row["status"] == "COMPLETE":
            record["completed_50m_passes"].append(row)
        report["per_image"].append(row)
        report["finished_utc"] = utc_now()
        ledger["updated_utc"] = utc_now()
        ledger["summary"] = summary(ledger)
        # Update checkpoint after each image so failures do not erase finished work.
        atomic_json(ledger_file, ledger)
        atomic_json(per_run_file, report)
        print(
            image["id"], image["group"], row["status"],
            format(row["actual_candidate_comparisons"], ","),
            "real candidate scores", "pass", pass_number, flush=True
        )

    report["summary_after_run"] = summary(ledger)
    report["finished_utc"] = utc_now()
    atomic_json(per_run_file, report)
    atomic_json(ledger_file, ledger)
    print(json.dumps(report["summary_after_run"], ensure_ascii=False), flush=True)
    github_summary = os.getenv("GITHUB_STEP_SUMMARY")
    if github_summary:
        s = report["summary_after_run"]
        with open(github_summary, "a", encoding="utf8") as f:
            f.write(
                "\n## Audited per-photo proxy comparisons (not real photo renders)\n\n"
                + "Actual scores: " + format(s["actual_candidate_comparisons"], ",")
                + "; unique >=50M: " + str(s["unique_images_with_full_50m_pass"])
                + "/113; unique >=100M: "
                + str(s["unique_images_with_full_100m_passes"]) + "/113\n\n"
                + "Do not change Styles.swift or publish an IPA from mathematical proxy scores.\n"
            )


if __name__ == "__main__":
    main()
