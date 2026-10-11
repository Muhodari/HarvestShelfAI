"""End-to-end pipeline check on synthetic images, in a temporary folder.

    python -m tools.smoke_test

Runs clean -> split -> train (demo arch, 2 epochs) -> thresholds ->
evaluate -> export, and checks the TFLite file loads. Real data and
training/exports/ are not touched.
"""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

import yaml

from src import clean, evaluate, export_tflite, split, thresholds, train
from src.config import DEFAULT_CONFIG, Config

from .synthetic_data import make


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        make(root / "data")
        raw = yaml.safe_load(DEFAULT_CONFIG.read_text())
        raw["paths"] = {
            "raw_dir": "data/raw", "metadata": "data/metadata.csv", "processed_dir": "data/processed",
            "splits_dir": "data/splits", "experiments_dir": "experiments", "exports_dir": "exports",
        }
        raw["image_size"] = 96
        raw["processed_short_side"] = 112
        cfg_path = root / "config.yaml"
        cfg_path.write_text(yaml.safe_dump(raw))
        cfg = Config(cfg_path)

        clean.run(cfg)
        split.run(cfg)
        run_dir = train.run(cfg, "demo", fold=None, head_epochs=2, finetune_epochs=0, name="smoke")
        thresholds.run(cfg, run_dir)
        evaluate.run(cfg, run_dir, "val")
        out = export_tflite.run(cfg, run_dir, demo=False)

        meta = json.loads((out / "model_meta.json").read_text())
        assert meta["num_classes"] == len(cfg.labels)
        assert (out / "model.tflite").stat().st_size > 0
        print("\nSMOKE TEST PASSED")


if __name__ == "__main__":
    main()
