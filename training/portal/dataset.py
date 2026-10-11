"""Field photos: saved to data/raw/<date>_<market>/ with one row each in
data/metadata.csv (the layout src.clean expects), so the
command-line pipeline (src.clean, src.split, ...) reads them unchanged."""

from __future__ import annotations

import io
import re
import threading
from dataclasses import dataclass
from datetime import date as Date
from pathlib import Path

import pandas as pd
from PIL import Image, UnidentifiedImageError

from src.config import UNUSABLE, Config

COLUMNS = ["image_id", "file", "market", "district", "date", "crop", "phone_model",
           "label_a", "label_b", "final_label", "batch_id", "notes"]
ID_PREFIX = {"tomato": "T", "banana": "B", "other": "X"}
EXTENSIONS = {".jpg", ".jpeg", ".png"}
_SLUG = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
_lock = threading.Lock()


class UploadError(ValueError):
    pass


@dataclass
class PhotoFields:
    crop: str
    label: str
    market: str
    district: str
    date: str
    phone_model: str
    batch_id: str
    notes: str = ""

    def validate(self, cfg: Config) -> None:
        if self.crop not in [*cfg["crops"], "other"]:
            raise UploadError(f"crop must be one of {[*cfg['crops'], 'other']}")
        if self.label not in [*cfg["categories"], UNUSABLE]:
            raise UploadError(f"label must be one of {[*cfg['categories'], UNUSABLE]}")
        if self.crop == "other" and self.label != UNUSABLE:
            raise UploadError("other produce is always labelled 'unusable'")
        for name in ("market", "batch_id"):
            if not _SLUG.match(getattr(self, name)):
                raise UploadError(f"{name} must be lowercase letters, digits, '-' or '_' (e.g. kamembe)")
        try:
            Date.fromisoformat(self.date)
        except ValueError:
            raise UploadError("date must be YYYY-MM-DD") from None


def read_metadata(cfg: Config) -> pd.DataFrame:
    path = cfg.path_of("metadata")
    if not path.exists() or path.stat().st_size == 0:
        return pd.DataFrame(columns=COLUMNS)
    return pd.read_csv(path, dtype=str, keep_default_na=False)


def _write_metadata(cfg: Config, df: pd.DataFrame) -> None:
    path = cfg.path_of("metadata")
    tmp = path.with_suffix(".csv.tmp")
    df[COLUMNS].to_csv(tmp, index=False)
    tmp.replace(path)


def next_ids(existing: pd.Series, crop: str, n: int) -> list[str]:
    """T0001, T0002, ... continuing after the highest id with that prefix."""
    prefix = ID_PREFIX[crop]
    nums = [int(m.group(1)) for v in existing if (m := re.fullmatch(rf"{prefix}(\d+)", v))]
    start = max(nums, default=0) + 1
    return [f"{prefix}{i:04d}" for i in range(start, start + n)]


def _check_image(name: str, data: bytes) -> str:
    ext = Path(name).suffix.lower()
    if ext not in EXTENSIONS:
        raise UploadError(f"{name}: only JPG and PNG photos are accepted")
    try:
        Image.open(io.BytesIO(data)).verify()
    except (UnidentifiedImageError, OSError):
        raise UploadError(f"{name}: not a readable image") from None
    return ".jpg" if ext == ".jpeg" else ext


def add_photos(cfg: Config, files: list[tuple[str, bytes]], fields: PhotoFields) -> list[dict]:
    """Saves every file or none of them, and appends one metadata row each."""
    if not files:
        raise UploadError("no photos selected")
    fields.validate(cfg)
    exts = [_check_image(name, data) for name, data in files]

    with _lock:
        df = read_metadata(cfg)
        ids = next_ids(df.image_id, fields.crop, len(files))
        folder = f"{fields.date}_{fields.market}"
        raw = cfg.path_of("raw_dir") / folder
        raw.mkdir(parents=True, exist_ok=True)
        rows = []
        for image_id, ext, (_, data) in zip(ids, exts, files):
            (raw / f"{image_id}{ext}").write_bytes(data)
            rows.append({
                "image_id": image_id, "file": f"{folder}/{image_id}{ext}", "market": fields.market,
                "district": fields.district, "date": fields.date, "crop": fields.crop,
                "phone_model": fields.phone_model, "label_a": fields.label, "label_b": "",
                "final_label": "", "batch_id": fields.batch_id, "notes": fields.notes,
            })
        _write_metadata(cfg, pd.concat([df, pd.DataFrame(rows)], ignore_index=True))
    return rows


def update_photo(cfg: Config, image_id: str, changes: dict[str, str]) -> dict:
    """Edits the second label, final label or notes of one photo."""
    allowed = {"label_b", "final_label", "notes"}
    if set(changes) - allowed:
        raise UploadError(f"only {sorted(allowed)} can be edited")
    labels = {"", *cfg["categories"], UNUSABLE}
    for k in ("label_b", "final_label"):
        if k in changes and changes[k] not in labels:
            raise UploadError(f"{k} must be one of {sorted(labels - {''})} or empty")
    with _lock:
        df = read_metadata(cfg)
        hit = df.image_id == image_id
        if not hit.any():
            raise KeyError(image_id)
        for k, v in changes.items():
            df.loc[hit, k] = v
        _write_metadata(cfg, df)
        return df[hit].iloc[0].to_dict()


def delete_photo(cfg: Config, image_id: str) -> None:
    with _lock:
        df = read_metadata(cfg)
        hit = df.image_id == image_id
        if not hit.any():
            raise KeyError(image_id)
        path = cfg.path_of("raw_dir") / df[hit].iloc[0].file
        _write_metadata(cfg, df[~hit])
    path.unlink(missing_ok=True)


def effective_label(row: pd.Series) -> str:
    """The label src.clean will use, or '' while two labelers disagree."""
    if row.final_label:
        return row.final_label
    if row.label_b and row.label_b != row.label_a:
        return ""
    return row.label_a


def summary(cfg: Config) -> dict:
    df = read_metadata(cfg)
    labels = [*cfg["categories"], UNUSABLE]
    counts = {c: {l: 0 for l in labels} for c in [*cfg["crops"], "other"]}
    disagreements = 0
    for _, row in df.iterrows():
        label = effective_label(row)
        if not label:
            disagreements += 1
            continue
        if row.crop in counts:
            counts[row.crop][UNUSABLE if row.crop == "other" else label] += 1
    double = df[(df.label_b != "")] if len(df) else df
    return {
        "total": len(df),
        "counts": counts,
        "batches": int(df.batch_id.nunique()) if len(df) else 0,
        "double_labelled": len(double),
        "disagreements": disagreements,
    }
