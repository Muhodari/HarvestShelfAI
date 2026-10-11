"""Interim model on the public AgriFreshNET dataset (CC BY 4.0).

    python -m tools.public_experiment --source "sandbox/public/extracted/Processed Data"
        [--models efficientnet_lite0 mobilenet_v3_small ...] [--install-in-app]

Risdin, F., Salauddin, H., Tufa, T. A., & Hossain, M. J. (2026).
AgriFreshNET Freshness and Shelf-Life Image Dataset (Version 1).
Mendeley Data. https://doi.org/10.17632/42m5tb7yv9.1

Label mapping (the dataset has 3 stages, HarvestShelf has 4):
  Fresh -> fresh, Semi-fresh -> sell_soon, Rotten -> spoilage_risk.
  discount_today has NO examples. Other crops (orange, cucumber, ...)
  become `unusable`, which teaches the model to reject unsupported produce.

Caveats: single items on a white cloth, Bangladesh, mostly yellow
dessert-type bananas. This is not a substitute for Rwandan market
photos; it gives the app a model that reacts to real produce while field
data is collected, and a starting point for fine-tuning later.

The "Processed Data" folder mixes original photos with augmented copies
(`aug_<n>_<original name>`). Copies are dropped: they would duplicate test
images and, if split apart from their originals, leak into evaluation.
This pipeline does its own augmentation during training.

Originals are grouped into capture sessions so near-identical shots never
cross train/val/test: IMG_YYYYMMDD_HH... -> class + date + hour,
IMG-YYYYMMDD-WA... (WhatsApp) -> class + date, anything else -> one group
per class.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path

import pandas as pd
import yaml

from src import clean, evaluate, export_tflite, split, thresholds, train
from src.config import DEFAULT_CONFIG, TRAINING_DIR, Config

ROOT = TRAINING_DIR / "sandbox" / "public"
TARGET = {"tomato": "tomato", "banana": "banana"}
STAGE = {"fresh": "fresh", "semi": "sell_soon", "rotten": "spoilage_risk"}
UNUSABLE_PER_CROP = 40  # per stage of each non-target crop -> about 700 unusable
NOTICE = ("INTERIM MODEL: trained on public Bangladesh photos (AgriFreshNET), not Rwandan markets. "
          "No Discount Today examples. For testing only.")


def parse_folder(name: str) -> tuple[str, str]:
    """'Semi fresh Tomato(10-24)' -> ('semi', 'tomato')."""
    n = re.sub(r"\(.*\)", "", name).replace("_", " ").strip().lower()
    stage = "semi" if n.startswith("semi") else n.split()[0]
    crop = n.split()[-1]
    if stage not in STAGE:
        raise ValueError(f"cannot parse stage from {name!r}")
    return stage, crop


def is_augmented(filename: str) -> bool:
    return filename.lower().startswith("aug_")


def session_of(cls: str, filename: str) -> str:
    if m := re.match(r"IMG_(\d{8})_(\d{2})", filename):
        return f"{cls}_{m.group(1)}_{m.group(2)}"
    if m := re.match(r"IMG-(\d{8})-WA", filename):
        return f"{cls}_{m.group(1)}_wa"
    return f"{cls}_misc"


def build_metadata(source: Path, out_csv: Path, seed: int = 0) -> pd.DataFrame:
    rows = []
    for folder in sorted(p for p in source.iterdir() if p.is_dir()):
        stage, crop = parse_folder(folder.name)
        files = sorted(f for f in folder.iterdir()
                       if f.suffix.lower() in {".jpg", ".jpeg", ".png"} and not is_augmented(f.name))
        if crop in TARGET:
            label, crop_out = STAGE[stage], TARGET[crop]
        else:
            label, crop_out = "unusable", "other"
            files = pd.Series(files).sample(min(UNUSABLE_PER_CROP, len(files)), random_state=seed).tolist()
        cls = f"{crop}_{stage}"
        for f in files:
            rows.append({
                "image_id": f"{cls}_{f.stem}", "file": f"{folder.name}/{f.name}", "market": "agrifreshnet",
                "district": "bangladesh", "date": "", "crop": crop_out, "phone_model": "unknown",
                "label_a": label, "label_b": None, "final_label": label,
                "batch_id": session_of(cls, f.name), "notes": f"AgriFreshNET {folder.name}",
            })
    df = pd.DataFrame(rows)
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out_csv, index=False)
    print(f"metadata: {len(df)} images, {df.batch_id.nunique()} capture sessions")
    print(df.groupby(["crop", "label_a"]).size().to_string())
    return df


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", type=Path, required=True)
    ap.add_argument("--models", nargs="+", default=["efficientnet_lite0"])
    ap.add_argument("--head-epochs", type=int, default=None)
    ap.add_argument("--finetune-epochs", type=int, default=None)
    ap.add_argument("--install-in-app", action="store_true",
                    help="copy the best model's export into app/assets/model")
    ap.add_argument("--reuse", action="store_true",
                    help="keep the existing cleaned data, splits and runs; only train the given models")
    ap.add_argument("--classical", action="store_true", help="also train and test the SVM and Random Forest")
    ap.add_argument("--no-install", nargs="*", default=[],
                    help="model-name prefixes never installed in the app (e.g. mobilenet)")
    a = ap.parse_args()

    source = a.source.resolve()
    work = ROOT / "work"
    reuse = a.reuse and (work / "splits" / "test.csv").exists()
    if not reuse:
        if work.exists():
            shutil.rmtree(work)
        build_metadata(source, work / "metadata.csv")
        raw = yaml.safe_load(DEFAULT_CONFIG.read_text())
        raw["paths"] = {
            "raw_dir": str(source), "metadata": "metadata.csv", "processed_dir": "processed",
            "splits_dir": "splits", "experiments_dir": "experiments", "exports_dir": "exports",
        }
        (work / "config.yaml").write_text(yaml.safe_dump(raw))
    cfg = Config(work / "config.yaml")

    if not reuse:
        clean.run(cfg, force_kappa=True)  # single labels from the dataset authors
        split.run(cfg)

    results = {}
    for arch in a.models:
        old = cfg.path_of("experiments_dir") / f"agrifreshnet_{arch}"
        if old.exists():
            shutil.rmtree(old)
        run_dir = train.run(cfg, arch, fold=None, head_epochs=a.head_epochs,
                            finetune_epochs=a.finetune_epochs, name=f"agrifreshnet_{arch}")
        thresholds.run(cfg, run_dir)
        m = evaluate.run(cfg, run_dir, "test")
        export_tflite.run(cfg, run_dir, demo=False, notice=NOTICE)
        shutil.copytree(cfg.path_of("exports_dir"), run_dir / "tflite", dirs_exist_ok=True)
        results[arch] = {"run": str(run_dir), **{k: m.get(k) for k in
                         ["action_macro_f1", "spoilage_recall", "uncertain_rate", "answered_macro_f1",
                          "unusable_rejected_rate", "class_macro_f1"]},
                         **{k: json.loads((run_dir / "export.json").read_text())[k]
                            for k in ["size_mb", "quantization", "top1_agreement"]}}

    # Merge with runs already in the folder, so the summary covers every model.
    for run_dir in sorted(cfg.path_of("experiments_dir").glob("agrifreshnet_*")):
        arch = run_dir.name.removeprefix("agrifreshnet_")
        if arch in results or not (run_dir / "test_metrics.json").exists() or not (run_dir / "export.json").exists():
            continue
        m, e = json.loads((run_dir / "test_metrics.json").read_text()), json.loads((run_dir / "export.json").read_text())
        results[arch] = {"run": str(run_dir), **{k: m.get(k) for k in
                         ["action_macro_f1", "spoilage_recall", "uncertain_rate", "answered_macro_f1",
                          "unusable_rejected_rate", "class_macro_f1"]},
                         **{k: e[k] for k in ["size_mb", "quantization", "top1_agreement"]}}

    if a.classical:
        from src import classical as classical_mod
        for name, m in classical_mod.run(cfg, test=True).items():
            results[name] = {"run": "classical", "size_mb": None, "quantization": None, "top1_agreement": None,
                             **{k: m.get(k) for k in ["action_macro_f1", "spoilage_recall", "uncertain_rate",
                                                      "answered_macro_f1", "unusable_rejected_rate", "class_macro_f1"]}}

    (work / "summary.json").write_text(json.dumps(results, indent=2))
    print("\n=== AGRIFRESHNET TEST RESULTS (held-out capture sessions) ===")
    print(json.dumps(results, indent=2))

    if a.install_in_app:
        # Proposal 3.4.5: among models meeting the spoilage-recall target, best
        # macro-F1; smaller model on a near-tie (within 0.01).
        # Only phone-ready models: exported, under the size limit, TFLite agreeing with Keras.
        target, max_mb = 0.85, cfg["export"]["max_model_mb"]
        phone = [k for k in results if results[k]["size_mb"] is not None and results[k]["size_mb"] <= max_mb
                 and (results[k]["top1_agreement"] or 0) >= 0.95
                 and not any(k.startswith(p) for p in a.no_install)]
        ok = [k for k in phone if (results[k]["spoilage_recall"] or 0) >= target] or phone
        top = max(results[k]["action_macro_f1"] or 0 for k in ok)
        near = [k for k in ok if (results[k]["action_macro_f1"] or 0) >= top - 0.01]
        best = min(near, key=lambda k: results[k]["size_mb"])
        best_dir = Path(results[best]["run"]) / "tflite"
        dst = TRAINING_DIR / "exports"
        dst.mkdir(exist_ok=True)
        for f in ["model.tflite", "labels.json", "model_meta.json", "export_report.json"]:
            shutil.copy(best_dir / f, dst / f)
        subprocess.run([str(TRAINING_DIR.parent / "scripts" / "copy_model_to_app.sh")], check=True)
        print(f"installed {best} in the app")


if __name__ == "__main__":
    main()
