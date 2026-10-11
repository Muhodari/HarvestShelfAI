import numpy as np
from PIL import Image, ImageFilter

from src.quality import assess


def solid(v):
    return Image.new("RGB", (300, 200), (v, v, v))


def checkerboard():
    y, x = np.mgrid[0:200, 0:300]
    on = ((x // 4) + (y // 4)) % 2 == 0
    arr = np.where(on, 200, 60).astype(np.uint8)
    return Image.fromarray(np.stack([arr] * 3, -1))


T = dict(min_brightness=40, max_brightness=235, min_sharpness=50)


def test_dark():
    q = assess(solid(5))
    assert abs(q.brightness - 5) < 0.5
    assert q.failure(**T) == "too_dark"


def test_bright():
    assert assess(solid(250)).failure(**T) == "too_bright"


def test_flat_is_blurry():
    q = assess(solid(128))
    assert q.sharpness < 1e-6
    assert q.failure(**T) == "blurry"


def test_pattern_passes():
    q = assess(checkerboard())
    assert q.sharpness > 50
    assert q.failure(**T) is None


def test_blur_lowers_sharpness():
    sharp = assess(checkerboard()).sharpness
    blurred = assess(checkerboard().filter(ImageFilter.GaussianBlur(6))).sharpness
    assert blurred < sharp / 10
