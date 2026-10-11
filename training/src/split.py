"""Step 2: split by batch so near-identical photos never leak across splits.

    python -m src.split [--config config.yaml]

Writes data/splits/{train,val,test}.csv. train.csv and val.csv also carry a
`fold` column (0..n_folds-1) for grouped cross-validation over train+val.
"""

from __future__ import annotations

import argparse

import numpy as np
import pandas as pd
from sklearn.model_selection import StratifiedGroupKFold

from .config import Config


def _take_fold(df: pd.DataFrame, frac: float, group_col: str, seed: int) -> tuple[pd.Index, pd.Index]:
    """Splits off roughly `frac` of rows as whole groups, stratified by class."""
    n_splits = max(2, round(1 / frac))
    groups = df[group_col]
    if groups.nunique() < n_splits:
        raise ValueError(
            f"Need at least {n_splits} distinct {group_col} values to split off {frac:.0%}; "
            f"found {groups.nunique()}. Collect more batches or lower the fraction."
        )
    sgkf = StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=seed)
    rest, held = next(sgkf.split(df, df.class_id, groups))
    return df.index[rest], df.index[held]


def grouped_split(df: pd.DataFrame, test_frac: float, val_frac: float, n_folds: int, group_col: str, seed: int) -> pd.DataFrame:
    df = df.copy()
    rest_idx, test_idx = _take_fold(df, test_frac, group_col, seed)
    rest = df.loc[rest_idx]
    train_idx, val_idx = _take_fold(rest, val_frac / (1 - test_frac), group_col, seed + 1)

    df["split"] = ""
    df.loc[test_idx, "split"] = "test"
    df.loc[train_idx, "split"] = "train"
    df.loc[val_idx, "split"] = "val"

    df["fold"] = -1
    trainval = df[df.split != "test"]
    k = min(n_folds, trainval[group_col].nunique())
    sgkf = StratifiedGroupKFold(n_splits=k, shuffle=True, random_state=seed)
    for fold, (_, idx) in enumerate(sgkf.split(trainval, trainval.class_id, trainval[group_col])):
        df.loc[trainval.index[idx], "fold"] = fold
    return df


def check_no_leakage(df: pd.DataFrame, group_col: str) -> None:
    per_group = df.groupby(group_col).split.nunique()
    leaked = per_group[per_group > 1]
    if len(leaked):
        raise AssertionError(f"groups in more than one split: {leaked.index.tolist()[:5]}")


def run(cfg: Config) -> pd.DataFrame:
    s = cfg["split"]
    df = pd.read_csv(cfg.path_of("processed_dir") / "clean.csv")
    out = grouped_split(df, s["test_frac"], s["val_frac"], s["n_folds"], s["group_col"], s["seed"])
    check_no_leakage(out, s["group_col"])

    d = cfg.path_of("splits_dir")
    d.mkdir(parents=True, exist_ok=True)
    for name in ["train", "val", "test"]:
        part = out[out.split == name]
        part.to_csv(d / f"{name}.csv", index=False)

    table = pd.crosstab(out.class_id, out.split).reindex(cfg.class_ids, fill_value=0)
    table = table.reindex(columns=["train", "val", "test"], fill_value=0)
    print(table.to_string())
    print(f"\nrows: {dict(out.split.value_counts())}  groups: {out[s['group_col']].nunique()}")
    empty = table.index[(table["test"] == 0)].tolist()
    if empty:
        print(f"WARNING: no test images for {empty}; collect more batches for these classes.")
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=None)
    a = ap.parse_args()
    run(Config(a.config) if a.config else Config())


if __name__ == "__main__":
    np.set_printoptions(suppress=True)
    main()
