"""Trains every candidate model on synthetic images to verify each
architecture learns and exports. Results mean nothing about real produce.

    python -m tools.synthetic_experiment [--per-class 60] [--models ...]

Everything is written under training/sandbox/synthetic/ (git-ignored);
data/ and exports/ are not touched.
"""

from __future__ import annotations

import argparse
import json
import shutil

import yaml

from src import classical, clean, compare, evaluate, export_tflite, split, thresholds, train
from src.config import DEFAULT_CONFIG, TRAINING_DIR, Config
from src.models import ARCHITECTURES

from .synthetic_data import make

ROOT = TRAINING_DIR / "sandbox" / "synthetic"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--per-class", type=int, default=60)
    ap.add_argument("--models", nargs="+", default=[a for a in ARCHITECTURES if a != "demo"])
    ap.add_argument("--head-epochs", type=int, default=6)
    ap.add_argument("--finetune-epochs", type=int, default=3)
    ap.add_argument("--reuse", action="store_true", help="keep the generated data and earlier runs")
    ap.add_argument("--skip-classical", action="store_true")
    a = ap.parse_args()

    reuse = a.reuse and (ROOT / "data" / "splits" / "test.csv").exists()
    if not reuse:
        if ROOT.exists():
            shutil.rmtree(ROOT)
        make(ROOT / "data", per_class=a.per_class, batches_per_class=10)
    raw = yaml.safe_load(DEFAULT_CONFIG.read_text())
    raw["paths"] = {
        "raw_dir": "data/raw", "metadata": "data/metadata.csv", "processed_dir": "data/processed",
        "splits_dir": "data/splits", "experiments_dir": "experiments", "exports_dir": "exports",
    }
    if not reuse:
        (ROOT / "config.yaml").write_text(yaml.safe_dump(raw))
    cfg = Config(ROOT / "config.yaml")

    if not reuse:
        clean.run(cfg)
        split.run(cfg)

    old_summary = ROOT / "summary.json"
    summary = json.loads(old_summary.read_text()) if reuse and old_summary.exists() else {}
    summary.pop("mobilenet_v2", None)
    for arch in a.models:
        if (cfg.path_of("experiments_dir") / arch).exists():
            shutil.rmtree(cfg.path_of("experiments_dir") / arch)
        run_dir = train.run(cfg, arch, fold=None, head_epochs=a.head_epochs,
                            finetune_epochs=a.finetune_epochs, name=arch)
        thresholds.run(cfg, run_dir)
        m = evaluate.run(cfg, run_dir, "test")
        export_tflite.run(cfg, run_dir, demo=False)
        shutil.copytree(cfg.path_of("exports_dir"), run_dir / "tflite", dirs_exist_ok=True)
        exp = json.loads((run_dir / "export.json").read_text())
        summary[arch] = {
            "test_action_macro_f1": m.get("action_macro_f1"),
            "test_spoilage_recall": m.get("spoilage_recall"),
            "test_uncertain_rate": m.get("uncertain_rate"),
            "tflite_mb": exp["size_mb"],
            "tflite_keras_top1_agreement": exp["top1_agreement"],
            "laptop_tflite_ms": round(exp["laptop_cpu_ms_median"], 1),
        }

    if not a.skip_classical:
        classical.run(cfg, test=True)
    for name in ([] if a.skip_classical else ["svm", "random_forest"]):
        p = sorted(cfg.path_of("experiments_dir").glob(f"*_{name}_test/test_metrics.json"))[-1]
        m = json.loads(p.read_text())
        summary[name] = {"test_action_macro_f1": m.get("action_macro_f1"),
                         "test_spoilage_recall": m.get("spoilage_recall"),
                         "test_uncertain_rate": m.get("uncertain_rate")}

    (ROOT / "summary.json").write_text(json.dumps(summary, indent=2))
    print("\n=== SYNTHETIC SUMMARY (test split; synthetic images, not produce) ===")
    for k, v in summary.items():
        print(f"{k:20s} " + "  ".join(f"{kk}={vv:.3f}" if isinstance(vv, float) else f"{kk}={vv}" for kk, vv in v.items()))


if __name__ == "__main__":
    main()
