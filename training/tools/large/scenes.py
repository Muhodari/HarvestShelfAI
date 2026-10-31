"""Mixed scenes: collages of 2-6 items, labelled by the worst item.

Real photos often hold several items. Scenes are generated *within one
split* from that split's photos only, so test scenes never reuse training
photos. One rotten banana among fresh ones makes the scene Spoilage Risk;
a scene with no tomato or banana (other produce, bottles) is unusable.
"""

from __future__ import annotations

import random
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image, ImageDraw, ImageFilter, ImageOps

from src.config import UNUSABLE

SEVERITY = ["fresh", "sell_soon", "discount_today", "spoilage_risk"]
OTHER = ("other", UNUSABLE)
BACKGROUND_COLOURS = [(236, 232, 224), (222, 214, 200), (200, 170, 130), (150, 110, 75), (60, 90, 60),
                      (190, 60, 50), (40, 70, 140), (235, 235, 235), (120, 120, 120)]


def scene_label(items: list[tuple[str, str]]) -> tuple[str, str]:
    """(crop, label) of each item -> (crop, label) of the scene: the worst tomato/banana item."""
    produce = [(c, l) for c, l in items if l != UNUSABLE]
    if not produce:
        return OTHER
    return max(produce, key=lambda cl: SEVERITY.index(cl[1]))


class SceneGenerator:
    """Draws scenes from the photos of one split. Deterministic for a given seed and split."""

    SIZE = 320

    def __init__(self, split_df: pd.DataFrame, split_name: str, processed: Path, seed: int):
        self.split_name = split_name
        self.rng = random.Random(f"{seed}-{split_name}")
        self.pool = {(c, l): [processed / p for p in g.path] for (c, l), g in split_df.groupby(["crop", "label"])}
        self.target_keys = [k for k in self.pool if k[1] != UNUSABLE]
        unusable = split_df[split_df.label == UNUSABLE]
        self.produce = [processed / p for p in unusable[unusable.notes == "produce"].path]
        self.objects = [processed / p for p in unusable[unusable.notes == "object"].path]

    # -- what goes in a scene

    def _items(self) -> tuple[list[tuple[str, str]], bool]:
        """Item labels for one scene, and whether "other" items must be objects only."""
        rng = self.rng
        crop = rng.choice(["tomato", "banana"])
        keys = [k for k in self.target_keys if k[0] == crop]
        k = rng.randint(2, 6)
        r = rng.random()
        if r < 0.35:    # one crop, mixed stages
            return [rng.choice(keys) for _ in range(k)], False
        if r < 0.50:    # one crop, one stage
            return [rng.choice(keys)] * k, False
        if r < 0.62:    # both crops
            return [rng.choice(self.target_keys) for _ in range(k)], False
        if r < 0.78:    # crop + other produce / objects
            n_t = rng.randint(1, k - 1)
            return [rng.choice(keys) for _ in range(n_t)] + [OTHER] * (k - n_t), False
        return [OTHER] * k, rng.random() < 0.5  # nothing supported: other produce, or only objects

    def _file_for(self, key: tuple[str, str], only_objects: bool) -> Path:
        if key == OTHER:
            return self.rng.choice(self.objects if only_objects else self.produce + self.objects)
        return self.rng.choice(self.pool[key])

    # -- drawing

    def _background(self) -> Image.Image:
        rng, size = self.rng, self.SIZE
        if rng.random() < 0.35 and self.objects:  # blurred real scene
            with Image.open(rng.choice(self.objects)) as im:
                blur = ImageFilter.GaussianBlur(rng.uniform(4, 12))
                return ImageOps.fit(im.convert("RGB"), (size, size)).filter(blur)
        base = np.array(rng.choice(BACKGROUND_COLOURS), dtype=np.float32)
        noise = np.random.default_rng(rng.randrange(1 << 30)).normal(0, rng.uniform(3, 14), (size, size, 1))
        return Image.fromarray(np.clip(base + noise, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1))

    def _patch(self, path: Path, side: int) -> tuple[Image.Image, Image.Image]:
        """The item cut from its photo, with a soft round mask."""
        rng = self.rng
        with Image.open(path) as im:
            im = im.convert("RGB")
            s = min(im.size)
            crop = rng.uniform(0.6, 0.9) * s  # tighter than the photo, around the item
            cx, cy = im.width / 2 + rng.uniform(-0.05, 0.05) * s, im.height / 2 + rng.uniform(-0.05, 0.05) * s
            im = im.crop((int(cx - crop / 2), int(cy - crop / 2), int(cx + crop / 2), int(cy + crop / 2)))
        im = im.resize((side, side), Image.BILINEAR).rotate(rng.choice([0, 90, 180, 270]))
        mask = Image.new("L", (side, side), 0)
        m = int(side * rng.uniform(0.02, 0.08))
        ImageDraw.Draw(mask).ellipse((m, m, side - m, side - m), fill=255)
        return im, mask.filter(ImageFilter.GaussianBlur(side * 0.05))

    def _compose(self, files: list[Path]) -> Image.Image:
        """Places the items on a jittered grid over a background."""
        rng, size, k = self.rng, self.SIZE, len(files)
        canvas = self._background()
        cols = 2 if k <= 4 else 3
        rows = (k + cols - 1) // cols
        cell = size // max(cols, rows)
        slots = [(c, r) for r in range(rows) for c in range(cols)]
        rng.shuffle(slots)
        x0, y0 = (size - cols * cell) // 2, (size - rows * cell) // 2
        for f, (c, r) in zip(files, slots[:len(files)], strict=True):
            side = int(cell * rng.uniform(0.85, 1.05))
            patch, mask = self._patch(f, side)
            x = x0 + c * cell + (cell - side) // 2 + rng.randint(-cell // 10, cell // 10)
            y = y0 + r * cell + (cell - side) // 2 + rng.randint(-cell // 10, cell // 10)
            canvas.paste(patch, (x, y), mask)
        return canvas

    # -- public

    def generate(self, n: int, out_dir: Path) -> pd.DataFrame:
        """Writes `n` scenes to `out_dir` and returns their split rows."""
        out_dir.mkdir(parents=True, exist_ok=True)
        rows = []
        for i in range(n):
            items, only_objects = self._items()
            files = [self._file_for(key, only_objects) for key in items]
            crop, label = scene_label(items)
            image_id = f"scene_{self.split_name}_{i:05d}"
            self._compose(files).save(out_dir / f"{image_id}.jpg", quality=90)
            rows.append({
                "image_id": image_id, "file": "", "market": "scene", "district": "public", "date": "",
                "crop": crop, "phone_model": "synthetic", "label_a": label, "label_b": None, "final_label": label,
                "batch_id": image_id, "notes": "scene", "label": label,
                "class_id": UNUSABLE if label == UNUSABLE else f"{crop}_{label}",
                "path": f"scenes/{image_id}.jpg", "split": self.split_name, "fold": -1,
            })
        return pd.DataFrame(rows)
