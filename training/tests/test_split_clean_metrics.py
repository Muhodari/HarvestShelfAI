import numpy as np
import pandas as pd
import pytest

from src.clean import labeler_kappa, resolve_label
from src.config import Config
from src.metrics import summarize
from src.split import check_no_leakage, grouped_split


def frame(n_groups=40, per_group=6, classes=("a", "b", "c", "d")):
    rows = []
    for g in range(n_groups):
        for i in range(per_group):
            rows.append({"image_id": f"{g}_{i}", "batch_id": f"g{g}", "class_id": classes[g % len(classes)]})
    return pd.DataFrame(rows)


def test_split_has_no_group_leakage_and_covers_all_rows():
    out = grouped_split(frame(), 0.15, 0.15, 5, "batch_id", 42)
    check_no_leakage(out, "batch_id")
    assert set(out.split) == {"train", "val", "test"}
    assert (out.split != "").all()
    assert (out[out.split != "test"].fold >= 0).all()
    assert (out[out.split == "test"].fold == -1).all()
    # folds are also whole groups
    assert (out[out.split != "test"].groupby("batch_id").fold.nunique() == 1).all()


def test_split_proportions_roughly_right():
    out = grouped_split(frame(n_groups=80), 0.15, 0.15, 5, "batch_id", 0)
    share = out.split.value_counts(normalize=True)
    assert 0.08 < share["test"] < 0.25
    assert 0.08 < share["val"] < 0.25


def test_split_needs_enough_groups():
    with pytest.raises(ValueError, match="distinct batch_id"):
        grouped_split(frame(n_groups=3), 0.15, 0.15, 5, "batch_id", 0)


def test_leakage_detected():
    df = pd.DataFrame({"batch_id": ["x", "x"], "split": ["train", "test"]})
    with pytest.raises(AssertionError):
        check_no_leakage(df, "batch_id")


@pytest.mark.parametrize("a,b,final,want", [
    ("fresh", "fresh", None, "fresh"),
    ("fresh", "sell_soon", None, None),
    ("fresh", "sell_soon", "sell_soon", "sell_soon"),
    ("fresh", None, None, "fresh"),
    (None, None, None, None),
])
def test_resolve_label(a, b, final, want):
    row = pd.Series({"label_a": a, "label_b": b, "final_label": final})
    assert resolve_label(row) == want


def test_kappa_perfect_and_partial():
    df = pd.DataFrame({"label_a": ["fresh", "sell_soon", "fresh", "discount_today"] * 5,
                       "label_b": ["fresh", "sell_soon", "fresh", "discount_today"] * 5})
    k, n = labeler_kappa(df)
    assert n == 20 and k == pytest.approx(1.0)
    df.loc[0, "label_b"] = "sell_soon"
    assert labeler_kappa(df)[0] < 1.0


def test_metrics_counts_uncertain_as_miss():
    cfg = Config()
    labels = cfg.labels
    n = len(labels)
    spoil = cfg.class_ids.index("tomato_spoilage_risk")
    fresh = cfg.class_ids.index("tomato_fresh")

    def onehot(i, p=0.9):
        v = np.full(n, (1 - p) / (n - 1))
        v[i] = p
        return v

    y = [spoil, spoil, fresh, fresh]
    probs = np.stack([onehot(spoil), np.full(n, 1 / n), onehot(fresh), onehot(fresh)])
    m = summarize(y, probs, labels, 0.55, 0.35)
    assert m["spoilage_recall"] == pytest.approx(0.5)  # second spoilage image shown as Uncertain
    assert m["uncertain_rate"] == pytest.approx(0.25)
    assert m["per_action"]["fresh"]["recall"] == pytest.approx(1.0)
