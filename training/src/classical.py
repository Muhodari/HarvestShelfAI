"""Classical baselines: SVM and Random Forest on hand-crafted colour and
texture features. They show whether deep learning is needed at all.

    python -m src.classical                 # grouped CV over train+val
    python -m src.classical --test --confirm-test   # final test evaluation
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime

import numpy as np
import pandas as pd
from PIL import Image
from skimage.feature import graycomatrix, graycoprops
from sklearn.ensemble import RandomForestClassifier
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC

from .config import Config
from .metrics import format_summary, summarize
from .quality import assess

FEATURE_SIZE = 128


def features(path) -> np.ndarray:
    im = Image.open(path).convert("RGB")
    s = min(im.size)
    left, top = (im.width - s) // 2, (im.height - s) // 2
    im = im.crop((left, top, left + s, top + s)).resize((FEATURE_SIZE, FEATURE_SIZE), Image.BOX)

    hsv = np.asarray(im.convert("HSV"))
    hist = [
        np.histogram(hsv[..., 0], bins=16, range=(0, 256))[0],
        np.histogram(hsv[..., 1], bins=8, range=(0, 256))[0],
        np.histogram(hsv[..., 2], bins=8, range=(0, 256))[0],
    ]
    hist = np.concatenate(hist).astype(np.float64) / (FEATURE_SIZE * FEATURE_SIZE)

    gray = np.asarray(im.convert("L"))
    glcm = graycomatrix(gray // 8, distances=[1, 3], angles=[0, np.pi / 4, np.pi / 2, 3 * np.pi / 4],
                        levels=32, symmetric=True, normed=True)
    tex = [graycoprops(glcm, p).mean(axis=1) for p in ["contrast", "homogeneity", "energy", "correlation"]]
    q = assess(im)
    return np.concatenate([hist, np.concatenate(tex), [q.brightness / 255, np.log1p(q.sharpness)]])


def feature_matrix(cfg: Config, df: pd.DataFrame) -> np.ndarray:
    base = cfg.path_of("processed_dir")
    return np.stack([features(base / p) for p in df.path])


def make_models(seed: int) -> dict:
    return {
        "svm": make_pipeline(StandardScaler(), SVC(kernel="rbf", C=10, class_weight="balanced",
                                                   probability=True, random_state=seed)),
        "random_forest": RandomForestClassifier(n_estimators=300, class_weight="balanced",
                                                random_state=seed, n_jobs=-1),
    }


def full_probs(clf, X: np.ndarray, n_classes: int) -> np.ndarray:
    """predict_proba only covers classes seen in training; pad the rest with 0."""
    p = np.zeros((len(X), n_classes))
    p[:, clf.classes_] = clf.predict_proba(X)
    return p


def run(cfg: Config, test: bool) -> dict:
    d = cfg.path_of("splits_dir")
    train, val = pd.read_csv(d / "train.csv"), pd.read_csv(d / "val.csv")
    tv = pd.concat([train, val], ignore_index=True)
    index = {c: i for i, c in enumerate(cfg.class_ids)}
    n = len(cfg.labels)
    th = cfg["thresholds"]
    seed = cfg["split"]["seed"]

    print(f"extracting features for {len(tv)} images...")
    X_tv, y_tv = feature_matrix(cfg, tv), tv.class_id.map(index).to_numpy()
    results: dict = {}

    for name, _ in make_models(seed).items():
        if test:
            te = pd.read_csv(d / "test.csv")
            clf = make_models(seed)[name].fit(X_tv, y_tv)
            m = summarize(te.class_id.map(index).to_numpy(), full_probs(clf, feature_matrix(cfg, te), n),
                          cfg.labels, th["default_t_conf"], th["default_t_spoil"])
            m["split"] = "test"
            results[name] = m
        else:
            folds = []
            for k in sorted(tv.fold.unique()):
                tr, va = tv.fold != k, tv.fold == k
                clf = make_models(seed)[name].fit(X_tv[tr], y_tv[tr])
                m = summarize(y_tv[va], full_probs(clf, X_tv[va], n), cfg.labels,
                              th["default_t_conf"], th["default_t_spoil"])
                m.update(arch=name, fold=int(k), split="val")
                folds.append(m)
            results[name] = folds
        print(f"\n== {name} ==")
        for m in results[name] if isinstance(results[name], list) else [results[name]]:
            print(format_summary(m))

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    for name, res in results.items():
        out = cfg.path_of("experiments_dir") / f"{stamp}_{name}_{'test' if test else 'cv'}"
        out.mkdir(parents=True, exist_ok=True)
        if isinstance(res, list):
            for m in res:
                (out / f"metrics_fold{m['fold']}.json").write_text(json.dumps(m, indent=2))
        else:
            (out / "test_metrics.json").write_text(json.dumps(res, indent=2))
    return results


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--test", action="store_true")
    ap.add_argument("--confirm-test", action="store_true")
    ap.add_argument("--config", default=None)
    a = ap.parse_args()
    if a.test and not a.confirm_test:
        raise SystemExit("The test set is for the final evaluation only. Add --confirm-test if that is now.")
    run(Config(a.config) if a.config else Config(), a.test)


if __name__ == "__main__":
    main()
