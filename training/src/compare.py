"""Builds the model comparison table (proposal Section 3.4.5) from all runs.

    python -m src.compare

Reads experiments/*/metrics*.json (validation / CV results) and writes
experiments/comparison.csv and comparison.md: mean and standard deviation
per architecture, plus model size where an export exists.
"""

from __future__ import annotations

import argparse
import json

import pandas as pd

from .config import Config

COLS = ["action_macro_f1", "spoilage_recall", "uncertain_rate", "class_macro_f1"]


def collect(cfg: Config) -> pd.DataFrame:
    rows = []
    for p in sorted(cfg.path_of("experiments_dir").glob("*/metrics*.json")):
        m = json.loads(p.read_text())
        if m.get("split") != "val" or m.get("arch") == "demo":
            continue
        export = p.parent / "export.json"
        rows.append({
            "run": p.parent.name, "arch": m["arch"], "fold": m.get("fold"),
            **{c: m.get(c) for c in COLS},
            "params": m.get("params"),
            "tflite_mb": json.loads(export.read_text())["size_mb"] if export.exists() else None,
        })
    return pd.DataFrame(rows)


def table(df: pd.DataFrame) -> pd.DataFrame:
    g = df.groupby("arch")
    out = pd.DataFrame({"runs": g.size()})
    for c in COLS:
        out[f"{c}_mean"] = g[c].mean().round(3)
        out[f"{c}_std"] = g[c].std().round(3)
    out["params_m"] = (g["params"].max() / 1e6).round(2)
    out["tflite_mb"] = g["tflite_mb"].max()
    return out.sort_values(["spoilage_recall_mean", "action_macro_f1_mean"], ascending=False)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=None)
    a = ap.parse_args()
    cfg = Config(a.config) if a.config else Config()
    df = collect(cfg)
    if df.empty:
        raise SystemExit("no validation metrics found in experiments/")
    t = table(df)
    out = cfg.path_of("experiments_dir")
    df.to_csv(out / "comparison_runs.csv", index=False)
    t.to_csv(out / "comparison.csv")
    (out / "comparison.md").write_text(t.to_markdown())
    print(t.to_string())
    print("\nPick the best action macro-F1 and spoilage recall that still runs in < 1 s on the test phone; "
          "if two are close, pick the smaller model.")


if __name__ == "__main__":
    main()
