"""Public datasets as interchangeable sources.

Each source knows where its photos live, how its folders map onto
HarvestShelf labels, and how to group photos that were taken together
(so the split never separates them). The experiment only sees the common
`DatasetSource` interface, so adding a dataset means adding one subclass.

Bananas follow one ripeness scale for green cooking bananas everywhere:
green -> fresh, yellow -> sell_soon, spotted / overripe -> discount_today,
black / rotten -> spoilage_risk.
"""

from __future__ import annotations

import re
from abc import ABC, abstractmethod
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

from src.config import TRAINING_DIR, UNUSABLE

EXTRA = TRAINING_DIR / "sandbox" / "extra"
AGRI = TRAINING_DIR / "sandbox" / "public" / "extracted" / "Processed Data"
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

TARGET, PRODUCE, OBJECT = "target", "produce", "object"  # what a photo shows


@dataclass(frozen=True)
class Photo:
    """One labelled photo before cleaning."""

    src: str
    crop: str       # tomato | banana | other
    label: str      # fresh | sell_soon | discount_today | spoilage_risk | unusable
    group: str      # "<source>:<capture group>"
    source: str
    kind: str       # TARGET | PRODUCE | OBJECT

    def to_dict(self) -> dict:
        return self.__dict__.copy()


def images_in(folder: Path) -> list[Path]:
    return sorted(f for f in folder.rglob("*") if f.suffix.lower() in IMAGE_EXT and not f.name.startswith("."))


def in_blocks(files: list[Path], prefix: str, size: int) -> list[tuple[Path, str]]:
    """Consecutive file names -> one group per block (video frames sit next to each other)."""
    return [(f, f"{prefix}_b{i // size}") for i, f in enumerate(sorted(files, key=lambda p: p.name))]


def parse_produce_folder(name: str) -> tuple[str | None, str | None]:
    """'stale_tomato', 'Tomato__Rotten', 'freshbanana' -> (crop, 'good' | 'bad')."""
    n = name.lower().replace("_", " ").replace("-", " ")
    state = "good" if re.search(r"fresh|healthy|good", n) else "bad" if re.search(r"stale|rotten|bad", n) else None
    crop = re.sub(r"fresh|healthy|good|stale|rotten|bad|\(.*\)", " ", n).split()
    return (crop[0] if crop else None), state


class DatasetSource(ABC):
    """A folder of public photos that can be turned into labelled `Photo`s."""

    name: str

    @property
    @abstractmethod
    def root(self) -> Path: ...

    def available(self) -> bool:
        return self.root.exists()

    @abstractmethod
    def _photos(self) -> list[Photo]: ...

    def photos(self) -> list[Photo]:
        return self._photos() if self.available() else []

    def _photo(self, path: Path, crop: str, label: str, group: str, kind: str) -> Photo:
        return Photo(str(path), crop, label, f"{self.name}:{group}", self.name, kind)


class AgriFreshNet(DatasetSource):
    """CC BY 4.0. Three freshness stages; bananas are yellow dessert bananas."""

    name = "agrifreshnet"
    TOMATO = {"fresh": "fresh", "semi": "sell_soon", "rotten": "spoilage_risk"}
    BANANA = {"fresh": "sell_soon", "semi": "discount_today", "rotten": "spoilage_risk"}

    @property
    def root(self) -> Path:
        return AGRI

    def _photos(self) -> list[Photo]:
        from tools.public_experiment import is_augmented, parse_folder, session_of
        out = []
        for folder in sorted(p for p in self.root.iterdir() if p.is_dir()):
            stage, crop = parse_folder(folder.name)
            for f in images_in(folder):
                if is_augmented(f.name):
                    continue
                g = session_of(f"{crop}_{stage}", f.name)
                if crop == "tomato":
                    out.append(self._photo(f, "tomato", self.TOMATO[stage], g, TARGET))
                elif crop == "banana":
                    out.append(self._photo(f, "banana", self.BANANA[stage], g, TARGET))
                else:
                    out.append(self._photo(f, "other", UNUSABLE, g, PRODUCE))
        return out


class BananaRipeness(DatasetSource):
    """Roboflow export: green (unripe) to rotten bananas, several augmented copies per original."""

    name = "banana_ripeness"
    STAGE = {"unripe": "fresh", "ripe": "sell_soon", "overripe": "discount_today", "rotten": "spoilage_risk"}
    MAX_COPIES = 2

    @property
    def root(self) -> Path:
        return EXTRA / "banana_ripeness"

    def _photos(self) -> list[Photo]:
        out, copies = [], defaultdict(int)
        for f in images_in(self.root):
            cls = f.parent.name.lower()
            if cls not in self.STAGE:
                continue
            original = re.sub(r"_(jpg|jpeg|png)\.rf\..*$", "", f.name)
            copies[original] += 1
            if copies[original] <= self.MAX_COPIES:
                out.append(self._photo(f, "banana", self.STAGE[cls], original, TARGET))
        return out


class ProduceAggregate(DatasetSource):
    """Kaggle datasets with '<state>_<crop>' or '<Crop>__<State>' folders.

    `banana_good` is the label for their fresh bananas, or None when those
    mix green and yellow fruit (different steps of the scale)."""

    def __init__(self, name: str, block: int, banana_good: str | None = None):
        self.name, self.block, self.banana_good = name, block, banana_good

    @property
    def root(self) -> Path:
        return EXTRA / self.name

    def _photos(self) -> list[Photo]:
        out = []
        folders = [d for d in self.root.rglob("*")
                   if d.is_dir() and any(f.suffix.lower() in IMAGE_EXT for f in d.iterdir())]
        for folder in sorted(folders):
            crop, state = parse_produce_folder(folder.name)
            if crop is None or state is None:
                continue
            crop = {"tomatoes": "tomato", "bananas": "banana"}.get(crop, crop)
            for f, g in in_blocks(images_in(folder), f"{folder.parent.name}_{folder.name}", self.block):
                if crop == "tomato":
                    out.append(self._photo(f, "tomato", "fresh" if state == "good" else "spoilage_risk", g, TARGET))
                elif crop == "banana":
                    label = "spoilage_risk" if state == "bad" else self.banana_good
                    if label:
                        out.append(self._photo(f, "banana", label, g, TARGET))
                else:
                    out.append(self._photo(f, "other", UNUSABLE, g, PRODUCE))
        return out


class Garbage(DatasetSource):
    """Bottles, cans, glass, paper: things that are not produce."""

    name = "garbage"

    @property
    def root(self) -> Path:
        return EXTRA / "garbage"

    def _photos(self) -> list[Photo]:
        return [self._photo(f, "other", UNUSABLE, f"{f.parent.name}_{g}", OBJECT)
                for f, g in in_blocks(images_in(self.root), "garbage", 25)]


class Imagenette(DatasetSource):
    """Ten everyday ImageNet classes (train half only)."""

    name = "imagenette"

    @property
    def root(self) -> Path:
        return EXTRA / "imagenette"

    def _photos(self) -> list[Photo]:
        out = []
        for synset in sorted(d for d in self.root.glob("*/train/*") if d.is_dir()):
            out += [self._photo(f, "other", UNUSABLE, g, OBJECT) for f, g in in_blocks(images_in(synset), synset.name, 30)]
        return out


def default_sources() -> list[DatasetSource]:
    return [
        AgriFreshNet(),
        BananaRipeness(),
        ProduceAggregate("fresh_stale", block=40, banana_good="sell_soon"),  # its fresh bananas are all yellow
        ProduceAggregate("healthy_rotten", block=25),
        Garbage(),
        Imagenette(),
    ]
