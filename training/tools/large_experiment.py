"""Production model on a large multi-source public dataset.

    python -m tools.large_experiment [--models efficientnet_lite0 ...] [--install-in-app]
    python -m tools.large_experiment --reuse --models efficientnet_lite0   # keep data, retrain

Downloads go to sandbox/extra/ (see `make data-large`). Every source that is
present is used; missing ones are skipped with a warning.

Sources and label mapping
-------------------------
HarvestShelf targets *green cooking bananas*, so bananas follow one ripeness
scale everywhere: green -> fresh, yellow -> sell_soon, spotted / overripe ->
discount_today, black / rotten -> spoilage_risk.

  AgriFreshNET (CC BY 4.0)         tomato Fresh/Semi/Rotten -> fresh/sell_soon/spoilage_risk
                                   banana Fresh(yellow)/Semi(spotted)/Rotten -> sell_soon/discount_today/spoilage_risk
                                   other crops -> unusable
  Banana Ripeness (Roboflow)       unripe/ripe/overripe/rotten -> fresh/sell_soon/discount_today/spoilage_risk
  Fresh and Stale (Kaggle)         tomato fresh/stale -> fresh/spoilage_risk, banana fresh/stale -> sell_soon/spoilage_risk,
                                   other crops -> unusable
  Healthy vs Rotten (Kaggle)       tomato healthy/rotten -> fresh/spoilage_risk, banana rotten -> spoilage_risk,
                                   other crops -> unusable
  Garbage classification (Kaggle)  bottles, cans, paper, ... -> unusable (non-produce)
  Imagenette (fast.ai)             everyday scenes and objects -> unusable (non-produce)

"Fresh" bananas from Fresh and Stale are all yellow (-> sell_soon); those
from Healthy vs Rotten are not used unless they are checked to be one colour.

Pipeline: sources (tools/large/sources.py) -> caps -> near-duplicate grouping
(tools/large/dedupe.py) -> clean -> grouped split -> mixed scenes per split
(tools/large/scenes.py) -> train -> thresholds -> test -> export.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

from src import clean, evaluate, export_tflite, split, thresholds, train
from src.config import DEFAULT_CONFIG, TRAINING_DIR, Config
from src.metrics import summarize
from tools.large.dedupe import merge_near_duplicates
from tools.large.scenes import SceneGenerator
from tools.large.sources import OBJECT, PRODUCE, TARGET, default_sources

ROOT = TRAINING_DIR / "sandbox" / "large"
NOTICE = ("Trained on public datasets (AgriFreshNET, Banana Ripeness, Fresh and Stale, Healthy vs Rotten, "
          "Garbage, Imagenette), not yet on Rwandan market photos.")

CAP_PER_CLASS_SOURCE = 2500   # per (source, class), keeps one source from dominating
CAP_UNUSABLE_PRODUCE = 3000   # other fruit and vegetables, all sources together
CAP_UNUSABLE_OBJECTS = 2500   # non-produce, all sources together
SCENES = {"train": 4000, "val": 700, "test": 700}


# ---------------------------------------------------------------- metadata

def build_metadata(work: Path, seed: int) -> pd.DataFrame:
    rows = []
    for source in default_sources():
        photos = source.photos()
        if not photos:
            print(f"WARNING: {source.name} not found at {source.root}, skipped")
        rows += [ph.to_dict() for ph in photos]
    df = pd.DataFrame(rows)
    rng = np.random.RandomState(seed)

    # Caps: sample whole groups so capped sources still split cleanly.
    def cap(part: pd.DataFrame, n: int) -> pd.DataFrame:
        if len(part) <= n:
            return part
        order = part.group.drop_duplicates().sample(frac=1, random_state=rng)
        keep, total = [], 0
        sizes = part.group.value_counts()
        for g in order:
            if total >= n:
                break
            keep.append(g)
            total += sizes[g]
        return part[part.group.isin(keep)]

    target = df[df.kind == TARGET]
    target = pd.concat([cap(p, CAP_PER_CLASS_SOURCE) for _, p in target.groupby(["source", "crop", "label"])])
    produce = cap(df[df.kind == PRODUCE].sample(frac=1, random_state=rng), CAP_UNUSABLE_PRODUCE)
    objects = cap(df[df.kind == OBJECT].sample(frac=1, random_state=rng), CAP_UNUSABLE_OBJECTS)
    df = pd.concat([target, produce, objects], ignore_index=True)
    df = merge_near_duplicates(df)

    meta = pd.DataFrame({
        "image_id": [f"{s}_{i:06d}" for i, s in enumerate(df.source)],
        "file": df.src, "market": df.source, "district": "public", "date": "", "crop": df.crop,
        "phone_model": "unknown", "label_a": df.label, "label_b": None, "final_label": df.label,
        "batch_id": df.group, "notes": df.kind,
    })
    work.mkdir(parents=True, exist_ok=True)
    meta.to_csv(work / "metadata.csv", index=False)
    print(f"metadata: {len(meta)} images from {meta.market.nunique()} sources, {meta.batch_id.nunique()} groups")
    print(pd.crosstab([meta.crop, meta.final_label], meta.market).to_string())
    return meta


# ---------------------------------------------------------------- mixed scenes

def add_scenes(cfg: Config, seed: int) -> None:
    processed, splits = cfg.path_of("processed_dir"), cfg.path_of("splits_dir")
    for name, n in SCENES.items():
        part = pd.read_csv(splits / f"{name}.csv")
        part = part[part.market != "scene"]
        scenes = SceneGenerator(part, name, processed, seed).generate(n, processed / "scenes")
        if name != "test":  # spread train/val scenes over the CV folds too
            scenes["fold"] = np.arange(len(scenes)) % cfg["split"]["n_folds"]
        pd.concat([part, scenes], ignore_index=True).to_csv(splits / f"{name}.csv", index=False)
        print(f"{name}: +{len(scenes)} mixed scenes -> {scenes.class_id.value_counts().to_dict()}")


# ---------------------------------------------------------------- evaluation extras

def breakdown(cfg: Config, run_dir: Path) -> dict:
    """Test metrics per source and for single photos vs mixed scenes."""
    df = pd.read_csv(cfg.path_of("splits_dir") / "test.csv")
    probs, y = np.load(run_dir / "test_probs.npy"), np.load(run_dir / "test_true.npy")
    t = json.loads((run_dir / "thresholds.json").read_text())
    out = {}
    for name, mask in [("single_photos", df.market != "scene"), ("mixed_scenes", df.market == "scene"),
                       *[(f"source:{s}", df.market == s) for s in sorted(df.market.unique()) if s != "scene"]]:
        mask = mask.to_numpy()
        if mask.sum() == 0:
            continue
        m = summarize(y[mask], probs[mask], cfg.labels, t["t_conf"], t["t_spoil"])
        out[name] = {k: m.get(k) for k in ["n", "action_macro_f1", "spoilage_recall", "uncertain_rate",
                                           "unusable_rejected_rate", "class_accuracy"]}
    (run_dir / "test_breakdown.json").write_text(json.dumps(out, indent=2))
    print(json.dumps(out, indent=2))
    return out


# ---------------------------------------------------------------- main

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--models", nargs="+", default=["efficientnet_lite0"])
    ap.add_argument("--head-epochs", type=int, default=None)
    ap.add_argument("--finetune-epochs", type=int, default=None)
    ap.add_argument("--reuse", action="store_true", help="keep the built dataset and splits; only train")
    ap.add_argument("--rescene", action="store_true", help="with --reuse: regenerate the mixed scenes first")
    ap.add_argument("--install-in-app", action="store_true", help="copy the best phone-ready model into the app")
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()

    work = ROOT / "work"
    reuse = a.reuse and (work / "splits" / "test.csv").exists()
    if not reuse:
        if work.exists():
            shutil.rmtree(work)
        build_metadata(work, a.seed)
        raw = yaml.safe_load(DEFAULT_CONFIG.read_text())
        raw["paths"] = {"raw_dir": "/", "metadata": "metadata.csv", "processed_dir": "processed",
                        "splits_dir": "splits", "experiments_dir": "experiments", "exports_dir": "exports"}
        raw["train"].update(head_epochs=6, finetune_epochs=14, early_stopping_patience=4)
        (work / "config.yaml").write_text(yaml.safe_dump(raw, sort_keys=False))
    cfg = Config(work / "config.yaml")

    if not reuse:
        clean.run(cfg, force_kappa=True)  # single labels from the dataset authors
        split.run(cfg)
    if not reuse or a.rescene:
        shutil.rmtree(cfg.path_of("processed_dir") / "scenes", ignore_errors=True)
        add_scenes(cfg, a.seed)

    results = {}
    for arch in a.models:
        run_dir = cfg.path_of("experiments_dir") / f"large_{arch}"
        if run_dir.exists():
            shutil.rmtree(run_dir)
        run_dir = train.run(cfg, arch, fold=None, head_epochs=a.head_epochs,
                            finetune_epochs=a.finetune_epochs, name=f"large_{arch}")
        thresholds.run(cfg, run_dir)
        m = evaluate.run(cfg, run_dir, "test")
        breakdown(cfg, run_dir)
        export_tflite.run(cfg, run_dir, demo=False, notice=NOTICE)
        shutil.copytree(cfg.path_of("exports_dir"), run_dir / "tflite", dirs_exist_ok=True)
        e = json.loads((run_dir / "export.json").read_text())
        results[arch] = {"run": str(run_dir), **{k: m.get(k) for k in [
            "action_macro_f1", "spoilage_recall", "uncertain_rate", "unusable_rejected_rate", "class_macro_f1"]},
            **{k: e[k] for k in ["size_mb", "quantization", "top1_agreement"]}}

    (work / "summary.json").write_text(json.dumps(results, indent=2))
    print("\n=== LARGE DATASET TEST RESULTS ===")
    print(json.dumps(results, indent=2))

    if a.install_in_app:
        max_mb = cfg["export"]["max_model_mb"]
        phone = [k for k, r in results.items() if r["size_mb"] <= max_mb and r["top1_agreement"] >= 0.95]
        if not phone:
            raise SystemExit("no phone-ready model (size or TFLite agreement); nothing installed")
        ok = [k for k in phone if (results[k]["spoilage_recall"] or 0) >= 0.85] or phone
        best = max(ok, key=lambda k: (round(results[k]["action_macro_f1"] or 0, 2), -results[k]["size_mb"]))
        dst = TRAINING_DIR / "exports"
        dst.mkdir(exist_ok=True)
        for f in ["model.tflite", "labels.json", "model_meta.json", "export_report.json"]:
            shutil.copy(Path(results[best]["run"]) / "tflite" / f, dst / f)
        subprocess.run([str(TRAINING_DIR.parent / "scripts" / "copy_model_to_app.sh")], check=True)
        print(f"installed {best} in the app")


if __name__ == "__main__":
    main()
