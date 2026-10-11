"""User and device evaluation (proposal Objective 3).

    python evaluation/analysis.py sus        evaluation/usability/sus_results.csv
    python evaluation/analysis.py agreement  evaluation/agreement_study/seller_sorts.csv \
                                             evaluation/agreement_study/expert_labels.csv
    python evaluation/analysis.py latency    evaluation/device_logs/*.csv

Needs only pandas and scipy (both in training/requirements.txt).
"""

from __future__ import annotations

import argparse
import sys

import numpy as np
import pandas as pd
from scipy import stats

SUS_TARGET = 68
AGREEMENT_TARGET_PTS = 15
LATENCY_TARGET_MS = 1000


def sus_score(row: pd.Series) -> float:
    """Standard SUS: odd items score-1, even items 5-score, sum x 2.5."""
    total = 0
    for i in range(1, 11):
        v = row[f"q{i}"]
        if not 1 <= v <= 5:
            raise ValueError(f"participant {row.participant_id}: q{i}={v} outside 1-5")
        total += (v - 1) if i % 2 == 1 else (5 - v)
    return total * 2.5


def cmd_sus(path: str) -> None:
    df = pd.read_csv(path)
    df["sus"] = df.apply(sus_score, axis=1)
    s = df.sus
    lo, hi = stats.t.interval(0.95, len(s) - 1, loc=s.mean(), scale=stats.sem(s)) if len(s) > 1 else (np.nan, np.nan)
    print(f"participants: {len(s)}")
    print(f"SUS mean {s.mean():.1f} (95% CI {lo:.1f}-{hi:.1f}), median {s.median():.1f}, range {s.min():.1f}-{s.max():.1f}")
    print(f"target mean >= {SUS_TARGET}: {'MET' if s.mean() >= SUS_TARGET else 'NOT MET'}")
    if "task_success" in df:
        print(f"task success rate: {df.task_success.mean():.0%}")
    if "time_on_task_s" in df:
        print(f"time on task: median {df.time_on_task_s.median():.0f} s")
    df.to_csv(path.replace(".csv", "_scored.csv"), index=False)


def cmd_agreement(sorts_path: str, expert_path: str) -> None:
    """Each seller sorts batch items with and without the app; compare with expert labels."""
    sorts = pd.read_csv(sorts_path)
    expert = pd.read_csv(expert_path)
    m = sorts.merge(expert, on="item_id", how="left", validate="many_to_one")
    if m.expert_label.isna().any():
        missing = m[m.expert_label.isna()].item_id.unique()[:5]
        raise SystemExit(f"items without expert label: {list(missing)}")
    m["agree"] = m.seller_label == m.expert_label
    per = m.pivot_table(index="participant_id", columns="condition", values="agree", aggfunc="mean")
    if not {"with_app", "without_app"} <= set(per.columns):
        raise SystemExit("condition column must contain 'with_app' and 'without_app'")
    per = per.dropna()
    diff = (per.with_app - per.without_app) * 100
    print(f"participants with both conditions: {len(per)}")
    print(f"agreement without app: {per.without_app.mean():.1%}   with app: {per.with_app.mean():.1%}")
    print(f"mean improvement: {diff.mean():+.1f} percentage points (median {diff.median():+.1f})")
    if len(per) >= 6:
        w = stats.wilcoxon(per.with_app, per.without_app, alternative="greater", zero_method="zsplit")
        print(f"Wilcoxon signed-rank (with > without): W={w.statistic:.1f}, p={w.pvalue:.4f}")
    else:
        print("too few participants for a Wilcoxon test")
    if "order" in m:
        by_order = m[m.condition == "with_app"].groupby("order").agree.mean()
        print(f"with-app agreement by order (check for learning effects): {by_order.round(3).to_dict()}")
    print(f"target >= +{AGREEMENT_TARGET_PTS} pts: {'MET' if diff.mean() >= AGREEMENT_TARGET_PTS else 'NOT MET'}")


def cmd_latency(paths: list[str]) -> None:
    df = pd.concat([pd.read_csv(p).assign(source=p) for p in paths], ignore_index=True)
    ms = pd.to_numeric(df.inference_ms, errors="coerce").dropna()
    if ms.empty:
        raise SystemExit("no inference_ms values (all scans rejected before inference?)")
    p95 = np.percentile(ms, 95)
    print(f"scans: {len(df)}, with inference: {len(ms)}")
    print(f"inference ms: median {ms.median():.0f}, p95 {p95:.0f}, max {ms.max():.0f}")
    print(f"target p95 < {LATENCY_TARGET_MS} ms: {'MET' if p95 < LATENCY_TARGET_MS else 'NOT MET'}")
    print("\nshown actions:\n" + df.category.value_counts().to_string())
    print("\nreasons:\n" + df.reason.value_counts().to_string())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("sus").add_argument("csv")
    a = sub.add_parser("agreement")
    a.add_argument("sorts_csv")
    a.add_argument("expert_csv")
    sub.add_parser("latency").add_argument("csv", nargs="+")
    args = ap.parse_args()
    if args.cmd == "sus":
        cmd_sus(args.csv)
    elif args.cmd == "agreement":
        cmd_agreement(args.sorts_csv, args.expert_csv)
    else:
        cmd_latency(args.csv)


if __name__ == "__main__":
    sys.exit(main())
