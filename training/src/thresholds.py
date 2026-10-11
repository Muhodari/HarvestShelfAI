"""Step 4: choose t_conf and t_spoil on the validation set.

    python -m src.thresholds --run experiments/<run>

Searches a grid for the pair that maximises action macro-F1 while keeping
spoilage recall >= target and the Uncertain rate <= max. Writes
thresholds.json and a risk-coverage plot into the run folder. Never tune
on the test set.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from .config import Config
from .metrics import summarize


def search(y_true, probs, labels, target_recall: float, max_uncertain: float, step: float = 0.05) -> dict:
    grid = np.round(np.arange(0.20, 0.951, step), 3)
    rows = []
    for t_conf in grid:
        for t_spoil in grid:
            m = summarize(y_true, probs, labels, float(t_conf), float(t_spoil))
            rows.append({
                "t_conf": float(t_conf), "t_spoil": float(t_spoil),
                "f1": m.get("action_macro_f1") or 0.0,
                "recall": m.get("spoilage_recall"),
                "uncertain": m.get("uncertain_rate") or 0.0,
            })

    ok = [r for r in rows if r["recall"] is not None and r["recall"] >= target_recall and r["uncertain"] <= max_uncertain]
    if ok:
        best = max(ok, key=lambda r: (r["f1"], -r["uncertain"]))
        best["constraints_met"] = True
    else:
        # Fall back to the safest choice: highest spoilage recall, then F1.
        best = max(rows, key=lambda r: ((r["recall"] or 0.0), r["f1"]))
        best["constraints_met"] = False
    best["grid"] = rows
    return best


def plot_risk_coverage(y_true, probs, labels, t_spoil: float, path: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    cov, risk = [], []
    for t in np.linspace(0.0, 0.99, 50):
        m = summarize(y_true, probs, labels, float(t), t_spoil)
        if m.get("uncertain_rate") is None:
            return
        answered = 1 - m["uncertain_rate"]
        cov.append(answered)
        risk.append(1 - (m["answered_macro_f1"] or 0.0) if answered > 0 else np.nan)
    plt.figure(figsize=(5, 4))
    plt.plot(cov, risk, marker=".")
    plt.xlabel("coverage (share of usable photos answered)")
    plt.ylabel("risk (1 - macro-F1 on answered)")
    plt.title(f"Risk-coverage, t_spoil={t_spoil}")
    plt.grid(alpha=0.3)
    plt.tight_layout()
    plt.savefig(path, dpi=120)
    plt.close()


def run(cfg: Config, run_dir: Path) -> dict:
    probs = np.load(run_dir / "val_probs.npy")
    y = np.load(run_dir / "val_true.npy")
    th = cfg["thresholds"]
    best = search(y, probs, cfg.labels, th["target_spoilage_recall"], th["max_uncertain_rate"])
    grid = best.pop("grid")
    final = summarize(y, probs, cfg.labels, best["t_conf"], best["t_spoil"])
    out = {"t_conf": best["t_conf"], "t_spoil": best["t_spoil"], "constraints_met": best["constraints_met"],
           "val_metrics": final}
    (run_dir / "thresholds.json").write_text(json.dumps(out, indent=2))
    (run_dir / "threshold_grid.json").write_text(json.dumps(grid))
    plot_risk_coverage(y, probs, cfg.labels, best["t_spoil"], run_dir / "risk_coverage.png")

    print(f"t_conf={best['t_conf']}  t_spoil={best['t_spoil']}  constraints met: {best['constraints_met']}")
    print(f"val action macro-F1={final.get('action_macro_f1')}  spoilage recall={final.get('spoilage_recall')}  "
          f"uncertain rate={final.get('uncertain_rate')}")
    if not best["constraints_met"]:
        print("WARNING: no threshold pair meets both constraints; the model needs more or better data.")
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run", required=True, type=Path)
    ap.add_argument("--config", default=None)
    a = ap.parse_args()
    run(Config(a.config) if a.config else Config(), a.run.resolve())


if __name__ == "__main__":
    main()
