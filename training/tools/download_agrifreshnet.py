"""Downloads and extracts the AgriFreshNET "Processed Data" archive.

    python -m tools.download_agrifreshnet

Risdin, F., Salauddin, H., Tufa, T. A., & Hossain, M. J. (2026). AgriFreshNET
Freshness and Shelf-Life Image Dataset (Version 1). Mendeley Data.
https://doi.org/10.17632/42m5tb7yv9.1. Licence: CC BY 4.0.

Writes sandbox/public/download/agrifreshnet_processed.zip (about 348 MB) and
extracts it to sandbox/public/extracted/. Safe to re-run: skips finished steps.
"""

from __future__ import annotations

import argparse
import urllib.request
import zipfile
from pathlib import Path

from src.config import TRAINING_DIR

URL = ("https://data.mendeley.com/public-files/datasets/42m5tb7yv9/files/"
       "7b216853-8f3b-47fd-b1ae-df88a367a1d1/file_downloaded")
EXPECTED_BYTES = 347_828_971
ROOT = TRAINING_DIR / "sandbox" / "public"


def download(dest: Path) -> None:
    if dest.exists() and dest.stat().st_size == EXPECTED_BYTES:
        print(f"already downloaded: {dest}")
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(".part")
    print(f"downloading {URL}\n  -> {dest}")
    with urllib.request.urlopen(URL) as r, open(tmp, "wb") as f:
        done = 0
        while chunk := r.read(1 << 20):
            f.write(chunk)
            done += len(chunk)
            print(f"\r  {done / 1e6:6.0f} / {EXPECTED_BYTES / 1e6:.0f} MB", end="", flush=True)
    print()
    if tmp.stat().st_size != EXPECTED_BYTES:
        raise SystemExit(f"unexpected size {tmp.stat().st_size} (expected {EXPECTED_BYTES}); the file may have changed")
    tmp.rename(dest)


def extract(archive: Path, out: Path) -> Path:
    target = out / "Processed Data"
    if target.exists() and any(target.iterdir()):
        print(f"already extracted: {target}")
        return target
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for member in z.namelist():  # refuse paths that escape the folder
            if member.startswith("/") or ".." in Path(member).parts:
                raise SystemExit(f"unsafe path in archive: {member}")
        z.extractall(out)
    print(f"extracted to {target}")
    return target


def main() -> None:
    argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter).parse_args()
    archive = ROOT / "download" / "agrifreshnet_processed.zip"
    download(archive)
    target = extract(archive, ROOT / "extracted")
    print(f'\nNext: python -m tools.public_experiment --source "{target.relative_to(TRAINING_DIR)}" --install-in-app')


if __name__ == "__main__":
    main()
