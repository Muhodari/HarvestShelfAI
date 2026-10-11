"""Step 1: validate metadata, check labeler agreement, filter and resize photos.

    python -m src.clean [--config config.yaml] [--force-kappa]

Reads data/metadata.csv and data/raw/, writes data/processed/clean.csv,
resized copies, and data/processed/clean_report.json.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import pandas as pd
from PIL import Image
from sklearn.metrics import cohen_kappa_score

from .config import UNUSABLE, Config, class_id
from .quality import assess, load_rgb

REQUIRED = ["image_id", "file", "market", "date", "crop", "phone_model", "label_a", "label_b", "final_label", "batch_id"]


def validate(df: pd.DataFrame, cfg: Config) -> None:
    missing = [c for c in REQUIRED if c not in df.columns]
    if missing:
        raise ValueError(f"metadata.csv is missing columns: {missing}")
    if df.image_id.duplicated().any():
        raise ValueError(f"duplicate image_id: {df.image_id[df.image_id.duplicated()].tolist()[:5]}")
    allowed_labels = set(cfg["categories"]) | {UNUSABLE}
    for col in ["label_a", "label_b", "final_label"]:
        bad = set(df[col].dropna()) - allowed_labels
        if bad:
            raise ValueError(f"{col} has unknown labels {sorted(bad)}; allowed: {sorted(allowed_labels)}")
    bad_crops = set(df.crop.dropna()) - set(cfg["crops"]) - {"other"}
    if bad_crops:
        raise ValueError(f"unknown crops {sorted(bad_crops)}; use one of {cfg['crops']} or 'other'")
    if df.batch_id.isna().any():
        raise ValueError("every row needs a batch_id (used to split without leakage)")


def labeler_kappa(df: pd.DataFrame) -> tuple[float | None, int]:
    """Cohen's kappa on rows labelled by both labelers."""
    both = df.dropna(subset=["label_a", "label_b"])
    if len(both) < 2:
        return None, len(both)
    return float(cohen_kappa_score(both.label_a, both.label_b)), len(both)


def resolve_label(row: pd.Series) -> str | None:
    """final_label wins; else agreeing labels; else single label; else drop."""
    if pd.notna(row.final_label):
        return row.final_label
    a, b = row.label_a, row.label_b
    if pd.notna(a) and pd.notna(b):
        return a if a == b else None
    return a if pd.notna(a) else (b if pd.notna(b) else None)


def resize_short_side(im: Image.Image, short: int) -> Image.Image:
    s = short / min(im.size)
    if s >= 1:
        return im
    return im.resize((round(im.width * s), round(im.height * s)), Image.BOX)


def run(cfg: Config, force_kappa: bool = False) -> dict:
    df = pd.read_csv(cfg.path_of("metadata"))
    validate(df, cfg)
    report: dict = {"rows_in": len(df)}

    kappa, n_double = labeler_kappa(df)
    report.update(kappa=kappa, double_labelled=n_double)
    min_kappa = cfg["labeling"]["min_kappa"]
    print(f"Cohen's kappa = {kappa} on {n_double} double-labelled images (need >= {min_kappa})")
    if kappa is None or kappa < min_kappa:
        msg = "Labeler agreement is below target: discuss disagreements and update docs/labeling_guide.md."
        if not force_kappa:
            raise SystemExit(msg + " (use --force-kappa to continue anyway)")
        print("WARNING: " + msg)

    df["label"] = df.apply(resolve_label, axis=1)
    disagreements = df[df.label.isna()]
    report["dropped_unresolved_disagreement"] = disagreements.image_id.tolist()
    df = df[df.label.notna()].copy()

    # Unsupported produce is always "unusable" whatever the label says.
    df.loc[df.crop == "other", "label"] = UNUSABLE

    raw_dir, out_dir = cfg.path_of("raw_dir"), cfg.path_of("processed_dir")
    (out_dir / "images").mkdir(parents=True, exist_ok=True)
    q = cfg["quality"]
    short = cfg["processed_short_side"]

    rows, seen_hashes = [], {}
    report["missing_files"], report["exact_duplicates"], report["moved_to_unusable"] = [], [], []
    for row in df.itertuples(index=False):
        src = raw_dir / row.file
        if not src.exists():
            report["missing_files"].append(row.file)
            continue
        digest = hashlib.md5(src.read_bytes()).hexdigest()
        if digest in seen_hashes:
            report["exact_duplicates"].append([row.image_id, seen_hashes[digest]])
            continue
        seen_hashes[digest] = row.image_id

        im = load_rgb(src)
        qual = assess(im)
        failure = qual.failure(q["min_brightness"], q["max_brightness"], q["min_sharpness"])
        label = row.label
        if failure and label != UNUSABLE:
            report["moved_to_unusable"].append([row.image_id, failure])
            label = UNUSABLE

        out = out_dir / "images" / f"{row.image_id}.jpg"
        resize_short_side(im, short).save(out, quality=92)
        rows.append({
            **row._asdict(),
            "label": label,
            "class_id": class_id(row.crop, label),
            "path": str(out.relative_to(out_dir)),
            "brightness": round(qual.brightness, 2),
            "sharpness": round(qual.sharpness, 2),
        })

    clean = pd.DataFrame(rows)
    clean.to_csv(out_dir / "clean.csv", index=False)
    report["rows_out"] = len(clean)
    report["class_counts"] = clean.class_id.value_counts().to_dict() if len(clean) else {}
    (out_dir / "clean_report.json").write_text(json.dumps(report, indent=2))

    print(f"Kept {len(clean)} of {report['rows_in']} images -> {out_dir / 'clean.csv'}")
    print(f"  moved to unusable by quality check: {len(report['moved_to_unusable'])}")
    print(f"  dropped (labelers disagree, no final_label): {len(report['dropped_unresolved_disagreement'])}")
    print(f"  exact duplicates removed: {len(report['exact_duplicates'])}")
    if report["missing_files"]:
        print(f"  MISSING FILES: {len(report['missing_files'])} (see clean_report.json)", file=sys.stderr)
    for cid in cfg.class_ids:
        print(f"  {cid:24s} {report['class_counts'].get(cid, 0)}")
    return report


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=None)
    ap.add_argument("--force-kappa", action="store_true")
    a = ap.parse_args()
    run(Config(a.config) if a.config else Config(), a.force_kappa)


if __name__ == "__main__":
    main()
