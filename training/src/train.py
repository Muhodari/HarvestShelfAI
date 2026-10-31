"""Step 3: train one model (two-stage transfer learning).

    python -m src.train --model efficientnet_lite0            # train.csv vs val.csv
    python -m src.train --model mobilenet_v3_small --fold 2   # grouped CV fold 2

Each run writes experiments/<run>/ with the SavedModel, training history,
validation probabilities (used by src.thresholds) and metrics.json.
"""

from __future__ import annotations

import argparse
import json
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import tensorflow as tf
from sklearn.utils.class_weight import compute_class_weight

from .config import Config
from .dataset import make_dataset, train_val_frames
from .metrics import format_summary, summarize
from .models import ARCHITECTURES, build, save_run_model


def class_weights(y: np.ndarray, cfg: Config) -> dict[int, float]:
    n = len(cfg.labels)
    present = np.unique(y)
    w = dict(zip(present.tolist(), compute_class_weight("balanced", classes=present, y=y).tolist(), strict=True))
    boost = cfg["train"]["spoilage_weight_boost"]
    for l in cfg.labels:
        if l.category == "spoilage_risk" and l.index in w:
            w[l.index] *= boost
    return {i: float(w.get(i, 1.0)) for i in range(n)}


def _fit(model, train_ds, val_ds, epochs, lr, weights, patience, log_path, label_smoothing=0.0, cosine=False):
    if cosine:
        # Decays from `lr` to 0 over the stage; early stopping may end it sooner.
        lr = tf.keras.optimizers.schedules.CosineDecay(lr, decay_steps=max(1, epochs * len(train_ds)))
    model.compile(
        # Legacy Adam: same algorithm; the new one crashes the Apple-GPU (Metal) plugin when fine-tuning.
        optimizer=tf.keras.optimizers.legacy.Adam(lr),
        loss=tf.keras.losses.CategoricalCrossentropy(label_smoothing=label_smoothing),
        metrics=["accuracy"],
    )
    return model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=epochs,
        class_weight=weights,
        callbacks=[
            tf.keras.callbacks.EarlyStopping(monitor="val_loss", patience=patience, restore_best_weights=True),
            tf.keras.callbacks.CSVLogger(str(log_path), append=True),
        ],
        verbose=2,
    )


def run(cfg: Config, arch: str, fold: int | None, head_epochs: int | None = None,
        finetune_epochs: int | None = None, name: str | None = None) -> Path:
    t = cfg["train"]
    head_epochs = t["head_epochs"] if head_epochs is None else head_epochs
    finetune_epochs = t["finetune_epochs"] if finetune_epochs is None else finetune_epochs
    tf.keras.utils.set_random_seed(cfg["split"]["seed"])

    train_df, val_df = train_val_frames(cfg, fold)
    index = {c: i for i, c in enumerate(cfg.class_ids)}
    y_train = train_df.class_id.map(index).to_numpy()
    y_val = val_df.class_id.map(index).to_numpy()

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    run_name = name or f"{stamp}_{arch}_{'final' if fold is None else f'fold{fold}'}"
    run_dir = cfg.path_of("experiments_dir") / run_name
    run_dir.mkdir(parents=True, exist_ok=False)

    model, base = build(arch, len(cfg.labels), cfg["image_size"], t["dropout"])
    train_ds = make_dataset(train_df, cfg, training=True, one_hot=True)
    val_ds = make_dataset(val_df, cfg, training=False, one_hot=True)
    weights = class_weights(y_train, cfg)
    smoothing = t.get("label_smoothing", 0.0)
    log = run_dir / "history.csv"

    start = time.time()
    print(f"[{run_name}] stage 1: train head ({head_epochs} epochs), {len(train_df)} train / {len(val_df)} val")
    _fit(model, train_ds, val_ds, head_epochs, t["head_lr"], weights, t["early_stopping_patience"], log, smoothing)
    if finetune_epochs > 0 and arch != "demo":
        print(f"[{run_name}] stage 2: fine-tune backbone ({finetune_epochs} epochs)")
        base.trainable = True
        _fit(model, train_ds, val_ds, finetune_epochs, t["finetune_lr"], weights, t["early_stopping_patience"], log,
             smoothing, cosine=True)
    train_seconds = time.time() - start

    val_probs = model.predict(make_dataset(val_df, cfg, training=False), verbose=0)
    np.save(run_dir / "val_probs.npy", val_probs)
    np.save(run_dir / "val_true.npy", y_val)
    val_df[["image_id", "class_id"]].to_csv(run_dir / "val_ids.csv", index=False)

    th = cfg["thresholds"]
    metrics = summarize(y_val, val_probs, cfg.labels, th["default_t_conf"], th["default_t_spoil"])
    metrics.update(
        arch=arch, fold=fold, split="val", n_train=len(train_df),
        params=int(model.count_params()), train_seconds=round(train_seconds, 1),
    )
    (run_dir / "metrics.json").write_text(json.dumps(metrics, indent=2))
    (run_dir / "run.json").write_text(json.dumps({
        "arch": arch, "fold": fold, "created": stamp, "class_ids": cfg.class_ids,
        "head_epochs": head_epochs, "finetune_epochs": finetune_epochs, "config": cfg.raw,
    }, indent=2))
    save_run_model(model, run_dir)

    print(f"\n[{run_name}] validation (default thresholds)\n{format_summary(metrics)}\n-> {run_dir}")
    return run_dir


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", required=True, choices=list(ARCHITECTURES))
    ap.add_argument("--fold", type=int, default=None)
    ap.add_argument("--head-epochs", type=int, default=None)
    ap.add_argument("--finetune-epochs", type=int, default=None)
    ap.add_argument("--name", default=None)
    ap.add_argument("--config", default=None)
    a = ap.parse_args()
    run(Config(a.config) if a.config else Config(), a.model, a.fold, a.head_epochs, a.finetune_epochs, a.name)


if __name__ == "__main__":
    main()
