"""Brightness and sharpness, computed the same way as the app
(app/lib/services/image_quality_service.dart), so thresholds tuned on the
dataset carry over to the phone."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

QUALITY_WIDTH = 256
# Sharpness is the Laplacian variance of the sharpest tile in a TILES x TILES
# grid. The whole-image variance wrongly rejected 43% of in-focus tomato
# photos: a smooth fruit on a plain cloth has few edges overall, but its
# outline is crisp. A blurred photo has no crisp tile anywhere.
TILES = 4


@dataclass(frozen=True)
class Quality:
    brightness: float
    sharpness: float

    def failure(self, min_brightness: float, max_brightness: float, min_sharpness: float) -> str | None:
        if self.brightness < min_brightness:
            return "too_dark"
        if self.brightness > max_brightness:
            return "too_bright"
        if self.sharpness < min_sharpness:
            return "blurry"
        return None


def load_rgb(path: str | Path) -> Image.Image:
    """Opens a photo upright (EXIF rotation applied, like bakeOrientation)."""
    with Image.open(path) as im:
        return ImageOps.exif_transpose(im).convert("RGB")


def assess(image: Image.Image) -> Quality:
    if image.width > QUALITY_WIDTH:
        h = round(image.height * QUALITY_WIDTH / image.width)
        image = image.resize((QUALITY_WIDTH, h), Image.BOX)
    rgb = np.asarray(image.convert("RGB"), dtype=np.float64)
    gray = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    brightness = float(gray.mean())
    if gray.shape[0] < 3 or gray.shape[1] < 3:
        return Quality(brightness, 0.0)
    lap = (
        4 * gray[1:-1, 1:-1]
        - gray[1:-1, :-2]
        - gray[1:-1, 2:]
        - gray[:-2, 1:-1]
        - gray[2:, 1:-1]
    )
    return Quality(brightness, sharpest_tile_variance(lap))


def sharpest_tile_variance(lap: np.ndarray, tiles: int = TILES) -> float:
    h, w = lap.shape
    th, tw = h // tiles, w // tiles
    if th == 0 or tw == 0:
        return float(lap.var())
    return float(max(
        lap[i * th:(i + 1) * th, j * tw:(j + 1) * tw].var()
        for i in range(tiles) for j in range(tiles)
    ))
