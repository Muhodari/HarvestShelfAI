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


def by_timestamp(files: list[Path], prefix: str, gap_s: int = 60) -> list[tuple[Path, str]]:
    """Phone photos named YYYYMMDD_HHMMSS: shots less than `gap_s` apart are one group
    (usually the same fruit photographed several times)."""
    from datetime import datetime
    out, group, last = [], 0, None
    for f in sorted(files, key=lambda p: p.name):
        m = re.match(r"(\d{8}_\d{6})", f.stem)
        t = datetime.strptime(m.group(1), "%Y%m%d_%H%M%S") if m else None
        if t is None or last is None or (t - last).total_seconds() > gap_s:
            group += 1
        last = t
        out.append((f, f"{prefix}_t{group}"))
    return out


class TomatoQuality(DatasetSource):
    """CC BY 4.0 (Kaggle sujaykapadnis). Single tomatoes on a table, original photos only:
    Fresh -> fresh, Rotten -> spoilage_risk. The in-field maturity half is not used."""

    name = "tomato_quality"
    LABEL = {"fresh": "fresh", "rotten": "spoilage_risk"}

    @property
    def root(self) -> Path:
        return EXTRA / "tomato_maturity"

    def _photos(self) -> list[Photo]:
        out = []
        for folder in sorted(self.root.rglob("Original Dataset/*")):
            label = self.LABEL.get(folder.name.lower())
            if folder.is_dir() and label:
                for f, g in by_timestamp(images_in(folder), folder.name):
                    out.append(self._photo(f, "tomato", label, g, TARGET))
        return out


def numbered_blocks(files: list[Path], prefix: str, size: int) -> list[tuple[Path, str]]:
    """Like `in_blocks`, but orders 'Green_2' before 'Green_10' (numeric, not text, order)."""
    def num(p: Path) -> int:
        m = re.search(r"(\d+)", p.stem)
        return int(m.group(1)) if m else 0
    return [(f, f"{prefix}_b{i // size}") for i, f in enumerate(sorted(files, key=num))]


class BananaDays(DatasetSource):
    """CC BY 4.0 (Mendeley d5tczj7fs7). 36 bananas photographed daily from day 0 to day 7.
    They start yellow, so: day 0-1 -> sell_soon, day 3-4 -> discount_today,
    day 7 -> spoilage_risk. Days 2, 5 and 6 sit on stage boundaries and are left out."""

    name = "banana_days"
    DAY = {0: "sell_soon", 1: "sell_soon", 3: "discount_today", 4: "discount_today", 7: "spoilage_risk"}

    @property
    def root(self) -> Path:
        return EXTRA / "banana_day0_7"

    def _photos(self) -> list[Photo]:
        out = []
        for f in images_in(self.root):
            m = re.fullmatch(r"Day_(\d)", f.stem)
            label = self.DAY.get(int(m.group(1))) if m else None
            if label:  # one group per banana: all its days stay in one split
                out.append(self._photo(f, "banana", label, f.parent.name, TARGET))
        return out


class BananaBD(DatasetSource):
    """CC BY 4.0 (BananaImageBD, Mendeley ptfscwtnyz), original photos only.
    Green -> fresh, Semi-ripe / Ripe -> sell_soon. 'Overripe' mixes spotted and fully
    black fruit (two different steps of the scale), so it is not used."""

    name = "banana_bd"
    STAGE = {"green": "fresh", "semi-ripe": "sell_soon", "ripe": "sell_soon"}

    @property
    def root(self) -> Path:
        return EXTRA / "banana_bd"

    def _photos(self) -> list[Photo]:
        out = []
        for folder in sorted(d for d in self.root.rglob("*") if d.is_dir()):
            label = self.STAGE.get(folder.name.lower())
            if label:
                for f, g in numbered_blocks(images_in(folder), folder.name, 5):
                    out.append(self._photo(f, "banana", label, g, TARGET))
        return out


class BananaAnnotated(DatasetSource):
    """CC BY 4.0 (Mendeley 56c75hvm7r). One banana per photo, class in the file name:
    unripe -> fresh, ripe -> sell_soon, overripe -> discount_today."""

    name = "banana_annotated"
    STAGE = {"unripe": "fresh", "ripe": "sell_soon", "overripe": "discount_today"}

    @property
    def root(self) -> Path:
        return EXTRA / "banana_annotated"

    def _photos(self) -> list[Photo]:
        by_cls = defaultdict(list)
        for f in images_in(self.root):
            cls = re.sub(r"_\d+$", "", f.stem).lower()
            if cls in self.STAGE:
                by_cls[cls].append(f)
        out = []
        for cls, files in sorted(by_cls.items()):
            for f, g in numbered_blocks(files, cls, 5):
                out.append(self._photo(f, "banana", self.STAGE[cls], g, TARGET))
        return out


class TomatoDetection(DatasetSource):
    """CC BY 4.0 (Mendeley vy5y8p2kdb, Roboflow export). Fresh -> fresh, Rotten -> spoilage_risk.
    Roboflow made rotated copies of each photo; one copy per original is kept,
    preferring an un-augmented one from the valid/test folders."""

    name = "tomato_detection"
    LABEL = {"fresh": "fresh", "rotten": "spoilage_risk"}

    @property
    def root(self) -> Path:
        return EXTRA / "tomato_detection"

    def _photos(self) -> list[Photo]:
        best: dict[str, Path] = {}
        for f in images_in(self.root):
            m = re.match(r"(Fresh|Rotten)-(\d+)-", f.name)
            if not m:
                continue
            key = f"{m.group(1)}-{m.group(2)}"
            if key not in best or (best[key].parent.parent.name == "train" and f.parent.parent.name != "train"):
                best[key] = f
        out = []
        for key, f in sorted(best.items()):
            cls, n = key.split("-")
            out.append(self._photo(f, "tomato", self.LABEL[cls.lower()], f"{cls}_b{int(n) // 5}", TARGET))
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
            blocks = in_blocks(images_in(synset), synset.name, 30)
            out += [self._photo(f, "other", UNUSABLE, g, OBJECT) for f, g in blocks]
        return out


def default_sources() -> list[DatasetSource]:
    return [
        AgriFreshNet(),
        BananaRipeness(),
        ProduceAggregate("fresh_stale", block=40, banana_good="sell_soon"),  # its fresh bananas are all yellow
        ProduceAggregate("healthy_rotten", block=25),
        TomatoQuality(),
        TomatoDetection(),
        BananaDays(),
        BananaBD(),
        BananaAnnotated(),
        Garbage(),
        Imagenette(),
    ]
