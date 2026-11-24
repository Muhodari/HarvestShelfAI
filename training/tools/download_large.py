"""Downloads and unpacks the extra public datasets for tools.large_experiment.

    python -m tools.download_large            # needs ~/.kaggle/kaggle.json (free Kaggle account)

Writes sandbox/extra/<name>/ and deletes each zip once it is unpacked.
Only the folders the experiment uses are kept from the large aggregates,
to save disk space. AgriFreshNET comes from `make data-public`.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path

from src.config import TRAINING_DIR

EXTRA = TRAINING_DIR / "sandbox" / "extra"
KAGGLE = {
    "banana_ripeness": "shahriar26s/banana-ripeness-classification-dataset",
    "garbage": "asdasdasasdas/garbage-classification",
    "fresh_stale": "raghavrpotdar/fresh-and-stale-images-of-fruits-and-vegetables",
    "healthy_rotten": "muhammad0subhan/fruit-and-vegetable-disease-healthy-vs-rotten",
    "tomato_maturity": "sujaykapadnis/tomato-maturity-detection-and-quality-grading",  # CC BY 4.0
}
# Mendeley Data (all CC BY 4.0): name -> (dataset id, files to fetch; None = all).
MENDELEY = {
    "banana_day0_7": ("d5tczj7fs7", None),
    "banana_bd": ("ptfscwtnyz", ["Banana Ripeness Detection Dataset.zip"]),  # originals, not augmented
    "banana_annotated": ("56c75hvm7r", ["BANANA_DATASET.zip"]),
    "tomato_detection": ("vy5y8p2kdb", None),
}
MENDELEY_API = "https://data.mendeley.com/public-api/datasets/"
# Mendeley refuses Python's default User-Agent with 403; any plain client name works.
HEADERS = {"User-Agent": "dataset-downloader/1.0"}


def fetch(url: str, dest: Path | None = None):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=120) as r:
        if dest is None:
            return r.read()
        with open(dest, "wb") as f:
            shutil.copyfileobj(r, f, length=1 << 20)
IMAGENETTE = "https://s3.amazonaws.com/fast-ai-imageclas/imagenette2-160.tgz"


def kaggle(name: str, ref: str) -> None:
    out = EXTRA / name
    if out.exists() and any(out.rglob("*.jp*g")):
        print(f"{name}: already present")
        return
    dl = EXTRA / "download"
    dl.mkdir(parents=True, exist_ok=True)
    zip_path = dl / f"{ref.split('/')[1]}.zip"
    if not zip_path.exists():
        exe = Path(sys.executable).with_name("kaggle")
        subprocess.run([str(exe), "datasets", "download", "-d", ref, "-p", str(dl)], check=True)
    print(f"{name}: unpacking")
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(out)
    zip_path.unlink()


def imagenette() -> None:
    out = EXTRA / "imagenette"
    if out.exists() and any(out.rglob("*.JPEG")):
        print("imagenette: already present")
        return
    out.mkdir(parents=True, exist_ok=True)
    tgz = EXTRA / "download" / "imagenette2-160.tgz"
    if not tgz.exists():
        tgz.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(IMAGENETTE, tgz)
    with tarfile.open(tgz) as t:
        t.extractall(out, filter="data")
    shutil.rmtree(next(out.glob("*/val")), ignore_errors=True)  # train half is plenty
    tgz.unlink()


def mendeley(name: str, dataset_id: str, wanted: list[str] | None) -> None:
    import json
    out = EXTRA / name
    if out.exists() and any(f.suffix.lower() in {".jpg", ".jpeg", ".png"} for f in out.rglob("*")):
        print(f"{name}: already present")
        return
    files = json.loads(fetch(MENDELEY_API + dataset_id))["files"]
    dl = EXTRA / "download"
    dl.mkdir(parents=True, exist_ok=True)
    for f in files:
        if wanted and f["filename"] not in wanted:
            continue
        zip_path = dl / f"{name}_{f['filename']}"
        if not zip_path.exists():
            print(f"{name}: downloading {f['filename']}")
            part = zip_path.with_suffix(".part")
            fetch(f["content_details"]["download_url"], part)
            part.rename(zip_path)
        print(f"{name}: unpacking {f['filename']}")
        with zipfile.ZipFile(zip_path) as z:
            z.extractall(out)
        zip_path.unlink()


def main() -> None:
    for name, ref in KAGGLE.items():
        kaggle(name, ref)
    for name, (dataset_id, wanted) in MENDELEY.items():
        mendeley(name, dataset_id, wanted)
    imagenette()
    print(f"done -> {EXTRA}")


if __name__ == "__main__":
    main()
