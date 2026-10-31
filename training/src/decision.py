"""Python mirror of app/lib/services/decision_mapper.dart (class DecisionMapper).

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
from collections.abc import Sequence

import numpy as np

from .config import Label


@dataclass(frozen=True)
class Decision:
    category: str
    crop: str | None
    confidence: float
    reason: str


class DecisionMapper:
    """Turns class probabilities into one triage action.

    Same class, method and rule order as `DecisionMapper` in
    app/lib/services/decision_mapper.dart, so the phone shows exactly what
    was evaluated here."""

    def __init__(self, labels: Sequence[Label], t_conf: float, t_spoil: float):
        self.labels, self.t_conf, self.t_spoil = list(labels), t_conf, t_spoil
        # Spoilage class of each crop, looked up once (Dart: ModelMeta.spoilageIndex).
        self._spoilage = {l.crop: l.index for l in self.labels if l.category == "spoilage_risk"}

    def map(self, probs: Sequence[float]) -> Decision:
        if len(probs) != len(self.labels):
            raise ValueError(f"expected {len(self.labels)} probabilities, got {len(probs)}")
        top = int(np.argmax(probs))  # first max on ties, like the Dart loop
        label = self.labels[top]

        if label.crop == "none":
            return Decision("uncertain", None, float(probs[top]), "unsupported")

        spoil = self._spoilage.get(label.crop)
        if spoil is not None and probs[spoil] >= self.t_spoil:
            reason = "model" if spoil == top else "spoilage_override"
            return Decision("spoilage_risk", label.crop, float(probs[spoil]), reason)

        if probs[top] < self.t_conf:
            return Decision("uncertain", label.crop, float(probs[top]), "low_confidence")

        return Decision(label.category, label.crop, float(probs[top]), "model")


def decide(probs: Sequence[float], labels: Sequence[Label], t_conf: float, t_spoil: float) -> Decision:
    return DecisionMapper(labels, t_conf, t_spoil).map(probs)


def decide_all(probs: np.ndarray, labels: Sequence[Label], t_conf: float, t_spoil: float) -> list[str]:
    """Predicted action category for each row of an (n, classes) array."""
    mapper = DecisionMapper(labels, t_conf, t_spoil)
    return [mapper.map(p).category for p in probs]
