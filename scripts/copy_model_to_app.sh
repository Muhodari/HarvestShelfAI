#!/usr/bin/env bash
# Copies the exported model into the Flutter app's assets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/training/exports"
DST="$ROOT/app/assets/model"

for f in model.tflite labels.json model_meta.json; do
  [[ -f "$SRC/$f" ]] || { echo "missing $SRC/$f (run src.export_tflite first)" >&2; exit 1; }
done

mkdir -p "$DST"
cp "$SRC/model.tflite" "$SRC/labels.json" "$SRC/model_meta.json" "$DST/"
echo "Copied to $DST:"
python3 -c "import json,sys; m=json.load(open('$DST/model_meta.json')); print(f\"  version={m['model_version']}  demo={m['is_demo']}  t_conf={m['t_conf']}  t_spoil={m['t_spoil']}\")"
ls -lh "$DST"
