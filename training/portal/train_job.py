"""One training run started from the portal (runs in its own process).

    python -m portal.train_job --name <run> --model efficientnet_lite0 [--public]

Combines the field photos (data/metadata.csv) with, optionally, the public
AgriFreshNET photos, then runs the normal pipeline: clean -> split ->
train -> thresholds -> evaluate on test -> export. Progress goes to
sandbox/portal/jobs/<run>/job.json; the console output is the log.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import traceback
from datetime import datetime
from pathlib import Path

import pandas as pd
import yaml

from src.config import DEFAULT_CONFIG, Config

PORTAL_DIR = Path(__file__).resolve().parent.parent / "sandbox" / "portal"
JOBS_DIR = PORTAL_DIR / "jobs"
WORK_DIR = PORTAL_DIR / "work"
PUBLIC_SOURCE = PORTAL_DIR.parent / "public" / "extracted" / "Processed Data"
STAGES = ["prepare", "clean", "split", "train", "thresholds", "evaluate", "export"]
METRIC_KEYS = ["action_macro_f1", "spoilage_recall", "uncertain_rate", "answered_macro_f1",
               "unusable_rejected_rate", "action_accuracy"]
PUBLIC_NOTICE = ("Trained on field photos plus public Bangladesh photos (AgriFreshNET). "
                 "Check results on Rwandan market photos before relying on it.")


def now() -> str:
    return datetime.now().isoformat(timespec="seconds")


class Job:
    def __init__(self, name: str):
        self.dir = JOBS_DIR / name
        self.file = self.dir / "job.json"

    def read(self) -> dict:
        return json.loads(self.file.read_text())

    def update(self, **changes) -> None:
        info = self.read() if self.file.exists() else {}
        info.update(changes)
        tmp = self.file.with_suffix(".tmp")
        tmp.write_text(json.dumps(info, indent=2))
        tmp.replace(self.file)


def prepare(include_public: bool) -> tuple[Config, dict]:
    """Builds WORK_DIR/config.yaml + metadata.csv over field (+ public) photos."""
    from tools.public_experiment import build_metadata

    if WORK_DIR.exists():
        shutil.rmtree(WORK_DIR)
    raw = WORK_DIR / "raw"
    raw.mkdir(parents=True)

    base = Config()
    parts, sources = [], {}
    field_csv = base.path_of("metadata")
    if field_csv.exists() and field_csv.stat().st_size:
        field = pd.read_csv(field_csv, dtype=str, keep_default_na=False).replace("", None)
        if len(field):
            os.symlink(base.path_of("raw_dir"), raw / "field")
            field["file"] = "field/" + field.file
            parts.append(field)
    sources["field"] = sum(len(p) for p in parts)

    if include_public:
        if not PUBLIC_SOURCE.exists():
            raise SystemExit(f"public photos not found at {PUBLIC_SOURCE}; run `make data-public` first")
        os.symlink(PUBLIC_SOURCE, raw / "public")
        public = build_metadata(PUBLIC_SOURCE, WORK_DIR / "public_metadata.csv")
        public["file"] = "public/" + public.file
        parts.append(public)
        sources["public"] = len(public)

    if not parts:
        raise SystemExit("no photos to train on: upload field photos or tick 'include public photos'")
    pd.concat(parts, ignore_index=True).to_csv(WORK_DIR / "metadata.csv", index=False)

    cfg_raw = yaml.safe_load(DEFAULT_CONFIG.read_text())
    cfg_raw["paths"] = {
        "raw_dir": "raw", "metadata": "metadata.csv", "processed_dir": "processed",
        "splits_dir": "splits", "experiments_dir": str(PORTAL_DIR / "experiments"),
        "exports_dir": "exports",
    }
    (WORK_DIR / "config.yaml").write_text(yaml.safe_dump(cfg_raw))
    return Config(WORK_DIR / "config.yaml"), sources


def run(job: Job, name: str, arch: str, include_public: bool, head_epochs: int | None,
        finetune_epochs: int | None, force_kappa: bool) -> None:
    from src import clean, evaluate, export_tflite, split, thresholds, train

    job.update(stage="prepare")
    cfg, sources = prepare(include_public)
    job.update(sources=sources)

    job.update(stage="clean")
    report = clean.run(cfg, force_kappa=force_kappa)
    job.update(images=report["rows_out"])

    job.update(stage="split")
    split.run(cfg)

    job.update(stage="train")
    run_dir = train.run(cfg, arch, fold=None, head_epochs=head_epochs,
                        finetune_epochs=finetune_epochs, name=name)
    job.update(run_dir=str(run_dir))

    job.update(stage="thresholds")
    t = thresholds.run(cfg, run_dir)

    job.update(stage="evaluate")
    m = evaluate.run(cfg, run_dir, "test")

    job.update(stage="export")
    notice = PUBLIC_NOTICE if include_public else None
    export_tflite.run(cfg, run_dir, demo=False, notice=notice)
    shutil.copytree(cfg.path_of("exports_dir"), run_dir / "tflite", dirs_exist_ok=True)
    e = json.loads((run_dir / "export.json").read_text())

    job.update(
        metrics={k: m.get(k) for k in METRIC_KEYS},
        thresholds={k: t.get(k) for k in ("t_conf", "t_spoil")},
        export={k: e.get(k) for k in ("size_mb", "quantization", "top1_agreement")},
    )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--public", action="store_true")
    ap.add_argument("--head-epochs", type=int, default=None)
    ap.add_argument("--finetune-epochs", type=int, default=None)
    ap.add_argument("--strict-kappa", action="store_true",
                    help="stop if labeler agreement is below target (default: warn only)")
    a = ap.parse_args()

    job = Job(a.name)
    job.update(status="running", pid=os.getpid())
    try:
        run(job, a.name, a.model, a.public, a.head_epochs, a.finetune_epochs, not a.strict_kappa)
        job.update(status="done", finished=now())
    except BaseException as exc:  # SystemExit from the pipeline carries a readable message
        traceback.print_exc()
        msg = str(exc) or type(exc).__name__
        job.update(status="failed", finished=now(), error=msg)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
