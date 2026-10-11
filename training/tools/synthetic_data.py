"""Generates a fake dataset in the real folder/metadata format.

Used only to test the pipeline end to end before field photos exist. The
images are coloured blobs, not produce; nothing trained on them means
anything.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image, ImageDraw, ImageFilter

# Base colour per crop/category: tomato red->dark, banana green->brown.
COLOURS = {
    ("tomato", "fresh"): (200, 30, 30),
    ("tomato", "sell_soon"): (220, 90, 40),
    ("tomato", "discount_today"): (150, 50, 40),
    ("tomato", "spoilage_risk"): (90, 60, 40),
    ("banana", "fresh"): (60, 150, 50),
    ("banana", "sell_soon"): (110, 150, 50),
    ("banana", "discount_today"): (120, 110, 50),
    ("banana", "spoilage_risk"): (70, 50, 30),
}


def _image(rng: np.random.Generator, crop: str, label: str, w=640, h=480) -> Image.Image:
    bg = tuple(int(v) for v in rng.integers(150, 230, 3))
    im = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(im)
    if label == "unusable":
        if rng.random() < 0.5:
            return Image.new("RGB", (w, h), (8, 8, 8))  # too dark
        d.rectangle([100, 100, 500, 400], fill=(30, 60, 200))  # not produce
        return im.filter(ImageFilter.GaussianBlur(12))
    base = np.array(COLOURS[(crop, label)]) + rng.integers(-15, 16, 3)
    cx, cy, r = w // 2 + rng.integers(-40, 40), h // 2 + rng.integers(-30, 30), rng.integers(140, 190)
    if crop == "tomato":
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=tuple(int(v) for v in base))
    else:
        d.rounded_rectangle([cx - r, cy - r // 3, cx + r, cy + r // 3], radius=40, fill=tuple(int(v) for v in base))
    for _ in range(int(rng.integers(20, 60))):  # texture so photos are not "blurry"
        x, y = rng.integers(0, w), rng.integers(0, h)
        d.point((int(x), int(y)), fill=(255, 255, 255))
    n_spots = {"fresh": 0, "sell_soon": 2, "discount_today": 6, "spoilage_risk": 14}[label]
    for _ in range(n_spots):
        sx, sy, sr = cx + rng.integers(-r // 2, r // 2), cy + rng.integers(-r // 4, r // 4), rng.integers(6, 18)
        d.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=(40, 30, 20))
    # Sensor-like noise so the sharpness check sees a real-looking photo.
    arr = np.asarray(im, dtype=np.float64) + rng.normal(0, 10, (h, w, 3))
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def make(root: Path, per_class: int = 24, batches_per_class: int = 8, seed: int = 0) -> Path:
    """Writes root/raw/... and root/metadata.csv; returns the metadata path."""
    rng = np.random.default_rng(seed)
    rows = []
    specs = [(c, l) for (c, l) in COLOURS] + [("other", "unusable")]
    markets = ["kamembe", "mukamira", "bugarama"]
    for crop, label in specs:
        for i in range(per_class):
            batch = i % batches_per_class
            market = markets[batch % len(markets)]
            date = f"2026-11-{1 + batch:02d}"
            image_id = f"{crop}_{label}_{i:03d}"
            rel = Path(f"{date}_{market}") / f"{image_id}.jpg"
            (root / "raw" / rel.parent).mkdir(parents=True, exist_ok=True)
            _image(rng, crop, label).save(root / "raw" / rel, quality=90)
            # Labeler B disagrees on ~10% of a 25% double-labelled sample.
            double = rng.random() < 0.25
            label_b = label if not double or rng.random() > 0.1 else "sell_soon"
            rows.append({
                "image_id": image_id, "file": str(rel), "market": market, "district": "synthetic",
                "date": date, "crop": crop, "phone_model": "synthetic",
                "label_a": label, "label_b": label_b if double else None,
                "final_label": label if double and label_b != label else None,
                "batch_id": f"{crop}_{label}_b{batch}", "notes": "SYNTHETIC",
            })
    meta = root / "metadata.csv"
    pd.DataFrame(rows).to_csv(meta, index=False)
    return meta
