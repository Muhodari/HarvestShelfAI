"""Metrics used for every model, so the comparison table is like-for-like.

Headline metrics follow the proposal's targets and are computed on the
*action* the phone would show (after the decision rule), over usable
images only. A usable image shown as Uncertain counts as a miss, which
keeps the numbers honest:

  action_macro_f1  >= 0.80   macro-F1 over fresh/sell_soon/discount_today/spoilage_risk
  spoilage_recall  >= 0.85   share of true spoilage images shown as Spoilage Risk
"""

from __future__ import annotations

from typing import Sequence

import numpy as np
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, precision_recall_fscore_support

from .config import Label
from .decision import decide_all

ACTIONS = ["fresh", "sell_soon", "discount_today", "spoilage_risk"]
ALL_ACTIONS = ACTIONS + ["uncertain"]
TARGETS = {"action_macro_f1": 0.80, "spoilage_recall": 0.85}


def summarize(y_true: Sequence[int], probs: np.ndarray, labels: Sequence[Label], t_conf: float, t_spoil: float) -> dict:
    y_true = np.asarray(y_true)
    probs = np.asarray(probs)
    true_action = np.array([labels[i].category for i in y_true])
    pred_action = np.array(decide_all(probs, labels, t_conf, t_spoil))
    usable = true_action != "uncertain"

    out: dict = {
        "n": int(len(y_true)),
        "n_usable": int(usable.sum()),
        "t_conf": t_conf,
        "t_spoil": t_spoil,
        # Raw classifier quality (argmax over all classes, no decision rule).
        "class_accuracy": float(accuracy_score(y_true, probs.argmax(1))),
        "class_macro_f1": float(
            f1_score(y_true, probs.argmax(1), labels=list(range(len(labels))), average="macro", zero_division=0)
        ),
    }

    if usable.any():
        t, p = true_action[usable], pred_action[usable]
        # Average only over actions present in the ground truth, so a dataset
        # without e.g. discount_today examples is not scored as F1 = 0 there.
        present = [a for a in ACTIONS if (t == a).any()]
        out["actions_present"] = present
        out["action_macro_f1"] = float(f1_score(t, p, labels=present, average="macro", zero_division=0))
        out["action_accuracy"] = float((t == p).mean())
        out["uncertain_rate"] = float((p == "uncertain").mean())
        spoil = t == "spoilage_risk"
        out["spoilage_recall"] = float((p[spoil] == "spoilage_risk").mean()) if spoil.any() else None
        answered = p != "uncertain"
        out["answered_macro_f1"] = (
            float(f1_score(t[answered], p[answered], labels=present, average="macro", zero_division=0))
            if answered.any() else None
        )
        prec, rec, f1, sup = precision_recall_fscore_support(t, p, labels=ACTIONS, zero_division=0)
        out["per_action"] = {
            a: {"precision": float(prec[i]), "recall": float(rec[i]), "f1": float(f1[i]), "support": int(sup[i])}
            for i, a in enumerate(ACTIONS)
        }
        out["confusion_actions"] = {
            "rows_true": ACTIONS,
            "cols_pred": ALL_ACTIONS,
            "matrix": confusion_matrix(t, p, labels=ALL_ACTIONS)[: len(ACTIONS)].tolist(),
        }

    if (~usable).any():
        out["unusable_rejected_rate"] = float((pred_action[~usable] == "uncertain").mean())

    out["meets_targets"] = {k: (out.get(k) is not None and out[k] >= v) for k, v in TARGETS.items()}
    return out


def format_summary(m: dict) -> str:
    def f(v):
        return "n/a" if v is None else f"{v:.3f}"

    lines = [
        f"images: {m['n']} (usable {m['n_usable']})   thresholds: t_conf={m['t_conf']}, t_spoil={m['t_spoil']}",
        f"action macro-F1   {f(m.get('action_macro_f1'))}   target >= {TARGETS['action_macro_f1']}",
        f"spoilage recall   {f(m.get('spoilage_recall'))}   target >= {TARGETS['spoilage_recall']}",
        f"uncertain rate    {f(m.get('uncertain_rate'))}   answered macro-F1 {f(m.get('answered_macro_f1'))}",
        f"unusable rejected {f(m.get('unusable_rejected_rate'))}",
        f"class macro-F1    {f(m['class_macro_f1'])}   (argmax, before decision rule)",
    ]
    return "\n".join(lines)
