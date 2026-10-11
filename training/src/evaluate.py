"""Step 5: evaluate a run on the untouched test set (do this once, at the end).

    python -m src.evaluate --run experiments/<run> --split test --confirm-test

Uses the run's thresholds.json. Writes <split>_metrics.json, a confusion
matrix image, a per-image prediction CSV and the raw probabilities
(<split>_probs.npy, <split>_true.npy) into the run folder.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from .config import Config
from .decision import decide
from .metrics import ALL_ACTIONS, ACTIONS, format_summary, summarize


def load_thresholds(cfg: Config, run_dir: Path) -> tuple[float, float, bool]:
    p = run_dir / "thresholds.json"
    if p.exists():
        t = json.loads(p.read_text())
        return t["t_conf"], t["t_spoil"], True
    th = cfg["thresholds"]
    return th["default_t_conf"], th["default_t_spoil"], False


def plot_confusion(m: dict, path: Path, title: str) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    cm = np.array(m["confusion_actions"]["matrix"])
    fig, ax = plt.subplots(figsize=(6.5, 4.5))
    ax.imshow(cm, cmap="Greens")
    ax.set_xticks(range(len(ALL_ACTIONS)), ALL_ACTIONS, rotation=30, ha="right")
    ax.set_yticks(range(len(ACTIONS)), ACTIONS)
    ax.set_xlabel("shown by app")
    ax.set_ylabel("expert label")
    for i in range(cm.shape[0]):
        for j in range(cm.shape[1]):
            ax.text(j, i, cm[i, j], ha="center", va="center", color="black")
    ax.set_title(title)
    fig.tight_layout()
    fig.savefig(path, dpi=130)
    plt.close(fig)


def run(cfg: Config, run_dir: Path, split: str) -> dict:
    import pandas as pd

    from .dataset import load_split, make_dataset
    from .models import load_run_model

    df = load_split(cfg, split)
    model = load_run_model(run_dir)
    probs = model.predict(make_dataset(df, cfg, training=False), verbose=0)
    index = {c: i for i, c in enumerate(cfg.class_ids)}
    y = df.class_id.map(index).to_numpy()

    # Raw probabilities, for curves and calibration plots in the notebook.
    np.save(run_dir / f"{split}_probs.npy", probs)
    np.save(run_dir / f"{split}_true.npy", y)

    t_conf, t_spoil, tuned = load_thresholds(cfg, run_dir)
    if not tuned:
        print("WARNING: no thresholds.json; using defaults. Run src.thresholds first.")
    m = summarize(y, probs, cfg.labels, t_conf, t_spoil)
    m["split"] = split
    (run_dir / f"{split}_metrics.json").write_text(json.dumps(m, indent=2))
    plot_confusion(m, run_dir / f"{split}_confusion.png", f"{run_dir.name} ({split})")

    decisions = [decide(p, cfg.labels, t_conf, t_spoil) for p in probs]
    pd.DataFrame({
        "image_id": df.image_id, "true_class": df.class_id, "pred_class": [cfg.class_ids[i] for i in probs.argmax(1)],
        "shown_action": [d.category for d in decisions], "confidence": [round(d.confidence, 4) for d in decisions],
        "reason": [d.reason for d in decisions], "market": df.market, "date": df.date,
    }).to_csv(run_dir / f"{split}_predictions.csv", index=False)

    print(format_summary(m))
    print(f"targets met: {m['meets_targets']}")
    return m


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run", required=True, type=Path)
    ap.add_argument("--split", default="val", choices=["val", "test"])
    ap.add_argument("--confirm-test", action="store_true", help="required for --split test")
    ap.add_argument("--config", default=None)
    a = ap.parse_args()
    if a.split == "test" and not a.confirm_test:
        raise SystemExit("The test set is for the final evaluation only. Add --confirm-test if that is now.")
    run(Config(a.config) if a.config else Config(), a.run.resolve(), a.split)


if __name__ == "__main__":
    main()
