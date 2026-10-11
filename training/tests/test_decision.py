"""Same cases as app/test/decision_mapper_test.dart."""

import json
from pathlib import Path

import pytest

from src.config import Config, Label
from src.decision import decide

SHARED = json.loads((Path(__file__).resolve().parents[2] / "shared" / "decision_cases.json").read_text())
LABELS = [Label(**l) for l in SHARED["labels"]]


@pytest.mark.parametrize("case", SHARED["cases"], ids=[c["name"] for c in SHARED["cases"]])
def test_shared_case(case):
    d = decide(case["probs"], LABELS, SHARED["t_conf"], SHARED["t_spoil"])
    want = case["expected"]
    assert d.category == want["category"]
    assert d.crop == want["crop"]
    assert d.reason == want["reason"]
    assert d.confidence == pytest.approx(want["confidence"])


def test_config_labels_match_shared_file():
    """The app's labels.json is generated from config.yaml; keep it in sync with the shared cases."""
    assert [l.to_json() for l in Config().labels] == SHARED["labels"]


def test_wrong_length():
    with pytest.raises(ValueError):
        decide([1.0], LABELS, 0.5, 0.5)
