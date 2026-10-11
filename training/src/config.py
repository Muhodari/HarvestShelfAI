"""Loads config.yaml and derives the class list."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml

TRAINING_DIR = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = TRAINING_DIR / "config.yaml"
UNUSABLE = "unusable"


@dataclass(frozen=True)
class Label:
    index: int
    id: str
    crop: str  # "none" for unusable
    category: str  # "uncertain" for unusable

    def to_json(self) -> dict:
        return {"index": self.index, "id": self.id, "crop": self.crop, "category": self.category}


class Config:
    def __init__(self, path: str | Path = DEFAULT_CONFIG):
        self.path = Path(path).resolve()
        self.raw = yaml.safe_load(self.path.read_text())
        self.base = self.path.parent

    def __getitem__(self, key):
        return self.raw[key]

    def path_of(self, key: str) -> Path:
        return (self.base / self.raw["paths"][key]).resolve()

    @property
    def labels(self) -> list[Label]:
        labels = []
        for crop in self.raw["crops"]:
            for cat in self.raw["categories"]:
                labels.append(Label(len(labels), f"{crop}_{cat}", crop, cat))
        labels.append(Label(len(labels), UNUSABLE, "none", "uncertain"))
        return labels

    @property
    def class_ids(self) -> list[str]:
        return [l.id for l in self.labels]


def class_id(crop: str, label: str) -> str:
    """Model class for a metadata row: `tomato` + `sell_soon` -> `tomato_sell_soon`."""
    return UNUSABLE if label == UNUSABLE else f"{crop}_{label}"
