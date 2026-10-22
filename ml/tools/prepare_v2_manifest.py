#!/usr/bin/env python3
"""Generate a SUNO V2 manifest ONLY from human-reviewed WAVs.

Input CSV requires relative_path,review_status,reviewer,source_group,license.
No training or app/model update happens in this script.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import wave

REQUIRED = {"relative_path", "review_status", "reviewer", "source_group", "license"}


class DatasetPolicyError(ValueError):
    pass


def group_split(group):
    ratio = int(hashlib.sha256(group.encode("utf-8")).hexdigest()[:8], 16) / 0xffffffff
    return "train" if ratio < .8 else "validation" if ratio < .9 else "test"


def validate_wav(path, spec):
    try:
        with wave.open(str(path), "rb") as wav:
            valid = (wav.getframerate() == spec["sample_rate_hz"]
                     and wav.getnchannels() == spec["channels"]
                     and wav.getsampwidth() * 8 == spec["bit_depth"]
                     and wav.getnframes() > 0 and wav.getcomptype() == "NONE")
    except (OSError, EOFError, wave.Error) as exc:
        raise DatasetPolicyError(f"Invalid WAV {path}: {exc}") from exc
    if not valid:
        raise DatasetPolicyError(f"Wrong WAV format: {path}")


def build_manifest(dataset_root, review_csv, policy_file):
    root = Path(dataset_root).resolve(strict=True)
    policy = json.loads(Path(policy_file).read_text(encoding="utf-8"))
    enabled = set(policy["enabled_alert_folders"])
    excluded = set(policy["excluded_alert_folders"])
    high_risk_neg = set(policy["high_risk_negative_folders"])
    out, seen = [], set()
    with Path(review_csv).open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames or not REQUIRED.issubset(reader.fieldnames):
            raise DatasetPolicyError("Review CSV needs: " + ", ".join(sorted(REQUIRED)))
        for line, row in enumerate(reader, 2):
            if (row.get("review_status") or "").lower().strip() != "approved":
                continue
            rel = (row.get("relative_path") or "").replace("\\", "/")
            path = (root / rel).resolve()
            if not path.is_relative_to(root):
                raise DatasetPolicyError(f"Row {line}: path escapes dataset root")
            parts = Path(rel).parts
            if len(parts) != 2 or path.suffix.lower() != ".wav":
                raise DatasetPolicyError(f"Row {line}: expected folder/filename.wav")
            if any(word.lower() in rel.lower() for word in policy["excluded_path_fragments"]):
                raise DatasetPolicyError(f"Row {line}: quarantine/review archive excluded")
            folder = parts[0]
            if folder in excluded:
                raise DatasetPolicyError(f"Row {line}: disabled V2 class: {folder}")
            negative = folder.startswith("n") and len(folder) > 3 and folder[1:3].isdigit()
            if not negative and folder not in enabled:
                raise DatasetPolicyError(f"Row {line}: unknown class {folder}")
            if folder in high_risk_neg and (row.get("false_negative_review") or "").lower().strip() != "pass":
                raise DatasetPolicyError(f"Row {line}: explicit false_negative_review=pass required")
            reviewer, group, license_name = ((row.get(k) or "").strip() for k in ("reviewer", "source_group", "license"))
            if not all((reviewer, group, license_name)):
                raise DatasetPolicyError(f"Row {line}: reviewer, source_group and license required")
            if (row.get("original_split") or "").lower().strip() in {"eval", "evaluation", "original_evaluation"}:
                raise DatasetPolicyError(f"Row {line}: original evaluation audio must not train")
            if rel in seen:
                raise DatasetPolicyError(f"Row {line}: duplicated path {rel}")
            if not path.is_file():
                raise DatasetPolicyError(f"Row {line}: WAV missing: {rel}")
            validate_wav(path, policy["required_audio_format"])
            seen.add(rel)
            label = "ambient_safe" if negative else "scream_loud" if folder == "a01_scream_loud" else "glass_break"
            out.append({"relative_path": rel, "class_label": label,
                        "source_group": group, "split": group_split(group),
                        "license": license_name, "reviewer": reviewer,
                        "review_status": "approved"})
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-root", type=Path, required=True)
    parser.add_argument("--reviews", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--policy", type=Path, default=Path(__file__).resolve().parents[1] / "config/v2_dataset_policy.json")
    args = parser.parse_args()
    rows = build_manifest(args.dataset_root, args.reviews, args.policy)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=["relative_path", "class_label", "source_group", "split", "license", "reviewer", "review_status"])
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} human-approved V2 rows to {args.out}")
    if not rows:
        print("No reviewed data: do not train.")


if __name__ == "__main__":
    main()
