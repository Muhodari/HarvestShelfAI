import numpy as np
import pandas as pd
from PIL import Image

from src.config import Config
from src.metrics import summarize
from src.thresholds import search
from tools.large.dedupe import UnionFind, merge_near_duplicates
from tools.large.scenes import scene_label
from tools.large.sources import parse_produce_folder


def test_scene_label_is_the_worst_supported_item():
    assert scene_label([("banana", "fresh"), ("banana", "spoilage_risk"), ("other", "unusable")]) == \
        ("banana", "spoilage_risk")
    assert scene_label([("tomato", "sell_soon"), ("banana", "fresh")]) == ("tomato", "sell_soon")
    assert scene_label([("other", "unusable")] * 4) == ("other", "unusable")  # only bottles etc.


def test_produce_folder_names():
    assert parse_produce_folder("Tomato__Healthy") == ("tomato", "good")
    assert parse_produce_folder("Banana__Rotten") == ("banana", "bad")
    assert parse_produce_folder("stale_tomato") == ("tomato", "bad")
    assert parse_produce_folder("fresh_bitter_gourd") == ("bitter", "good")
    assert parse_produce_folder("Train")[1] is None  # not a class folder


def test_union_find_merges_and_respects_the_size_cap():
    sets = UnionFind({"a": 2, "b": 3, "c": 10})
    assert sets.union("a", "b", max_size=5)
    assert sets.find("a") == sets.find("b")
    assert not sets.union("a", "c", max_size=5)  # 5 + 10 would exceed the cap
    assert sets.find("c") == "c"


def test_near_duplicates_share_a_group_but_different_photos_do_not(tmp_path):
    rng = np.random.default_rng(0)
    a = (rng.random((64, 64, 3)) * 255).astype(np.uint8)
    b = (rng.random((64, 64, 3)) * 255).astype(np.uint8)
    Image.fromarray(a).save(tmp_path / "a.png")
    Image.fromarray(a).resize((128, 128)).save(tmp_path / "a_big.jpg", quality=80)  # resized copy
    Image.fromarray(b).save(tmp_path / "b.png")
    df = pd.DataFrame({"src": [str(tmp_path / f) for f in ["a.png", "a_big.jpg", "b.png"]],
                       "group": ["s1:x", "s2:y", "s1:z"]})
    out = merge_near_duplicates(df)
    assert out.group[0] == out.group[1]
    assert out.group[0] != out.group[2]


def test_threshold_search_refuses_to_answer_for_non_crops():
    labels = Config().labels
    unusable = len(labels) - 1
    # Usable photos are confident; non-crop photos look like weak tomato spoilage.
    probs, y = [], []
    def photo(top: int, p_top: float, base: float, extra: dict[int, float] | None = None) -> np.ndarray:
        p = np.full(len(labels), base)
        p[top] = p_top
        for i, v in (extra or {}).items():
            p[i] = v
        return p / p.sum()

    for _ in range(50):
        probs += [photo(0, 0.92, 0.01), photo(3, 0.92, 0.01),             # tomato fresh, tomato spoilage
                  photo(3, 0.40, 0.05, {unusable: 0.30})]                 # non-crop: weak tomato spoilage
        y += [0, 3, unusable]
    y, probs = np.array(y), np.array(probs)
    assert summarize(y, probs, labels, 0.4, 0.2)["unusable_rejected_rate"] == 0  # a loose t_spoil answers them
    best = search(y, probs, labels, 0.85, 0.15, min_rejection=0.95, min_t_conf=0.4)
    assert best["constraints_met"]
    m = summarize(y, probs, labels, best["t_conf"], best["t_spoil"])
    assert m["unusable_rejected_rate"] == 1.0 and m["spoilage_recall"] == 1.0
