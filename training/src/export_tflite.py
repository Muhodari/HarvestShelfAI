"""Step 6: convert the chosen model to TensorFlow Lite for the app.

    python -m src.export_tflite --run experiments/<run>
    python -m src.export_tflite --demo     # untrained placeholder, no data needed

Writes exports/model.tflite, labels.json and model_meta.json, then checks
that the TFLite model agrees with the Keras model. Copy them into the app
with scripts/copy_model_to_app.sh.
"""

from __future__ import annotations

import argparse
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import tensorflow as tf

from .config import Config
from .models import build, load_run_model


QUANTIZATION = ("dynamic", "int8", "float16", "none")
MIN_AGREEMENT = 0.95  # TFLite must pick the same class as Keras this often


def convert(model: tf.keras.Model, quantization: str, representative: np.ndarray | None = None) -> bytes:
    """dynamic: int8 weights, float activations (default; ~4x smaller, near-identical outputs).
    int8: also int8 activations, calibrated on `representative` (smallest, can lose accuracy).
    float16: half-size weights. none: float32."""
    if quantization not in QUANTIZATION:
        raise ValueError(f"quantization must be one of {QUANTIZATION}")
    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    if quantization != "none":
        conv.optimizations = [tf.lite.Optimize.DEFAULT]
    if quantization == "float16":
        conv.target_spec.supported_types = [tf.float16]
    if quantization == "int8":
        if representative is None:
            raise ValueError("int8 quantization needs representative images")

        def gen():
            for img in representative:
                yield [img[None].astype(np.float32)]

        conv.representative_dataset = gen  # input and output stay float32
    return conv.convert()


def verify(tflite: bytes, model: tf.keras.Model, images: np.ndarray) -> dict:
    interp = tf.lite.Interpreter(model_content=tflite)
    interp.allocate_tensors()
    inp, out = interp.get_input_details()[0], interp.get_output_details()[0]
    keras_probs = model.predict(images, verbose=0)
    lite_probs, times = [], []
    for img in images:
        interp.set_tensor(inp["index"], img[None].astype(np.float32))
        t = time.perf_counter()
        interp.invoke()
        times.append((time.perf_counter() - t) * 1000)
        lite_probs.append(interp.get_tensor(out["index"])[0])
    lite_probs = np.array(lite_probs)
    return {
        "input_shape": inp["shape"].tolist(),
        "output_shape": out["shape"].tolist(),
        "top1_agreement": float((keras_probs.argmax(1) == lite_probs.argmax(1)).mean()),
        "max_abs_prob_diff": float(np.abs(keras_probs - lite_probs).max()),
        "laptop_cpu_ms_median": float(np.median(times)),
    }


def _sample_images(cfg: Config, split: str, n: int) -> np.ndarray:
    from .dataset import load_split, make_dataset

    df = load_split(cfg, split)
    df = df.sample(min(n, len(df)), random_state=0)
    return np.concatenate([x.numpy() for x, _ in make_dataset(df, cfg, training=False, batch_size=32)])


def run(cfg: Config, run_dir: Path | None, demo: bool, notice: str | None = None) -> Path:
    size = cfg["image_size"]
    th = cfg["thresholds"]
    if demo:
        model, _ = build("demo", len(cfg.labels), size, cfg["train"]["dropout"])
        rng = np.random.default_rng(0)
        check = rng.uniform(0, 255, (8, size, size, 3)).astype(np.float32)
        rep = check
        version, arch = "demo-untrained", "demo (MobileNetV3-Small, random weights)"
        t_conf, t_spoil, val = th["default_t_conf"], th["default_t_spoil"], None
    else:
        run_info = json.loads((run_dir / "run.json").read_text())
        if run_info["class_ids"] != cfg.class_ids:
            raise SystemExit("class order in config.yaml differs from the run; refusing to export")
        model = load_run_model(run_dir)
        rep = (_sample_images(cfg, "train", cfg["export"]["representative_samples"])
               if cfg["export"].get("quantization", "dynamic") == "int8" else None)
        check = _sample_images(cfg, "val", 64)
        version, arch = run_dir.name, run_info["arch"]
        tfile = run_dir / "thresholds.json"
        if not tfile.exists():
            raise SystemExit(f"{tfile} missing: run `python -m src.thresholds --run {run_dir}` first")
        t = json.loads(tfile.read_text())
        t_conf, t_spoil, val = t["t_conf"], t["t_spoil"], t["val_metrics"]

    quant = cfg["export"].get("quantization", "dynamic")
    tflite = convert(model, quant, rep)
    report = verify(tflite, model, check)
    # Some architectures (e.g. MobileNetV3's hard-swish) lose accuracy when
    # quantized; fall back to safer formats so the phone runs the model
    # that was evaluated.
    for fallback in ("float16", "none"):
        if demo or report["top1_agreement"] >= MIN_AGREEMENT:
            break
        print(f"{quant}: TFLite agrees with Keras on {report['top1_agreement']:.1%}; retrying with {fallback}")
        quant = fallback
        tflite = convert(model, quant, rep)
        report = verify(tflite, model, check)
    mb = len(tflite) / 1e6
    report["size_mb"] = round(mb, 2)
    report["quantization"] = quant

    out = cfg.path_of("exports_dir")
    out.mkdir(parents=True, exist_ok=True)
    (out / "model.tflite").write_bytes(tflite)
    (out / "labels.json").write_text(json.dumps([l.to_json() for l in cfg.labels], indent=2))
    meta = {
        "model_version": version,
        "architecture": arch,
        "input_size": size,
        "input_range": "0_255",
        "num_classes": len(cfg.labels),
        "t_conf": t_conf,
        "t_spoil": t_spoil,
        "is_demo": demo,
        "notice": notice,
        "quantization": quant,
        "quality": cfg["quality"],
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "val_action_macro_f1": None if val is None else val.get("action_macro_f1"),
        "val_spoilage_recall": None if val is None else val.get("spoilage_recall"),
    }
    (out / "model_meta.json").write_text(json.dumps(meta, indent=2))
    (out / "export_report.json").write_text(json.dumps(report, indent=2))
    if run_dir is not None:
        (run_dir / "export.json").write_text(json.dumps(report, indent=2))

    print(json.dumps(report, indent=2))
    if mb > cfg["export"]["max_model_mb"]:
        print(f"WARNING: model is {mb:.1f} MB, above the {cfg['export']['max_model_mb']} MB target")
    if not demo and report["top1_agreement"] < MIN_AGREEMENT:
        print("WARNING: TFLite and Keras disagree on >5% of images; try export.quantization: float16 or none")
    print(f"-> {out}")
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--run", type=Path)
    g.add_argument("--demo", action="store_true")
    ap.add_argument("--notice", default=None, help="warning banner text shown in the app")
    ap.add_argument("--config", default=None)
    a = ap.parse_args()
    run(Config(a.config) if a.config else Config(), a.run.resolve() if a.run else None, a.demo, a.notice)


if __name__ == "__main__":
    main()
