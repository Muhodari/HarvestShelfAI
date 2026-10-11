"""Guards shared/quality_cases.json, which app/test/image_quality_test.dart also checks."""

import json
from pathlib import Path

import pytest
from PIL import Image

from src.quality import assess

SHARED = Path(__file__).resolve().parents[2] / "shared"
CASES = json.loads((SHARED / "quality_cases.json").read_text())


@pytest.mark.parametrize("case", CASES["cases"], ids=[c["file"] for c in CASES["cases"]])
def test_shared_quality_case(case):
    q = assess(Image.open(SHARED / "quality_fixtures" / case["file"]).convert("RGB"))
    assert q.brightness == pytest.approx(case["brightness"], abs=1e-6)
    assert q.sharpness == pytest.approx(case["sharpness"], abs=1e-4)
    t = CASES["thresholds"]
    assert q.failure(t["min_brightness"], t["max_brightness"], t["min_sharpness"]) == case["failure"]


def test_smooth_in_focus_tomato_is_not_blurry():
    """Regression: the old whole-image measure rejected this photo."""
    tomato = next(c for c in CASES["cases"] if c["file"] == "tomato_smooth.png")
    assert tomato["failure"] is None
