"""Python mirror of app/lib/services/decision_mapper.dart.

Both are tested against shared/decision_cases.json, so evaluation here
measures exactly what the phone will show.

Rule order:
  1. top class is unusable              -> uncertain (unsupported)
  2. spoilage prob of top crop >= t_spoil -> spoilage_risk
  3. top prob < t_conf                  -> uncertain (low_confidence)
  4. otherwise                          -> category of top class
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

import numpy as np

from .config import Label


@dataclass(frozen=True)
class Decision:
    category: str
    crop: str | None
    confidence: float
    reason: str


def decide(probs: Sequence[float], labels: Sequence[Label], t_conf: float, t_spoil: float) -> Decision:
    if len(probs) != len(labels):
        raise ValueError(f"expected {len(labels)} probabilities, got {len(probs)}")
    top = int(np.argmax(probs))  # first max on ties, like the Dart loop
    label = labels[top]

    if label.crop == "none":
        return Decision("uncertain", None, float(probs[top]), "unsupported")

    spoil = next(
        (l.index for l in labels if l.crop == label.crop and l.category == "spoilage_risk"),
        None,
    )
    if spoil is not None and probs[spoil] >= t_spoil:
        reason = "model" if spoil == top else "spoilage_override"
        return Decision("spoilage_risk", label.crop, float(probs[spoil]), reason)

    if probs[top] < t_conf:
        return Decision("uncertain", label.crop, float(probs[top]), "low_confidence")

    return Decision(label.category, label.crop, float(probs[top]), "model")


def decide_all(probs: np.ndarray, labels: Sequence[Label], t_conf: float, t_spoil: float) -> list[str]:
    """Predicted action category for each row of an (n, classes) array."""
    return [decide(p, labels, t_conf, t_spoil).category for p in probs]
