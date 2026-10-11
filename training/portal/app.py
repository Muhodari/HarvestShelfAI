"""Flask server for the training portal. Local use only (binds 127.0.0.1)."""

from __future__ import annotations

import io
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
from datetime import datetime
from pathlib import Path

from flask import Flask, abort, jsonify, request, send_file, send_from_directory
from PIL import Image, ImageOps

from src.config import TRAINING_DIR, Config
from src.models import ARCHITECTURES

from . import dataset
from .train_job import JOBS_DIR, PORTAL_DIR, PUBLIC_SOURCE, STAGES, Job, now

REPO = TRAINING_DIR.parent
APP_MODEL_DIR = REPO / "app" / "assets" / "model"
THUMBS_DIR = PORTAL_DIR / "thumbs"
STATIC = Path(__file__).resolve().parent / "static"
FONTS = REPO / "app" / "assets" / "fonts"
MODELS = {k: v for k, v in ARCHITECTURES.items() if k != "demo"}
_RUN_NAME = re.compile(r"^[A-Za-z0-9_.-]+$")


def create_app(cfg: Config | None = None) -> Flask:
    cfg = cfg or Config()
    app = Flask(__name__, static_folder=None)
    app.config["MAX_CONTENT_LENGTH"] = 1024 * 1024 * 1024  # 1 GB per upload request
    proc_lock = threading.Lock()

    # ---------- pages and assets ----------

    @app.get("/")
    def index():
        return send_from_directory(STATIC, "index.html")

    @app.get("/fonts/<name>")
    def font(name):
        return send_from_directory(FONTS, name)

    # ---------- dataset ----------

    @app.get("/api/dataset")
    def get_dataset():
        df = dataset.read_metadata(cfg)
        rows = df.iloc[::-1].to_dict("records")  # newest first
        return jsonify({
            "summary": dataset.summary(cfg),
            "photos": rows,
            "crops": [*cfg["crops"], "other"],
            "labels": [*cfg["categories"], "unusable"],
            "public_available": PUBLIC_SOURCE.exists(),
        })

    @app.post("/api/photos")
    def upload():
        f = request.form
        fields = dataset.PhotoFields(
            crop=f.get("crop", ""), label=f.get("label", ""),
            market=f.get("market", "").strip().lower(), district=f.get("district", "").strip().lower(),
            date=f.get("date", ""), phone_model=f.get("phone_model", "").strip(),
            batch_id=f.get("batch_id", "").strip().lower(), notes=f.get("notes", "").strip(),
        )
        files = [(u.filename or "photo.jpg", u.read()) for u in request.files.getlist("photos")]
        try:
            rows = dataset.add_photos(cfg, files, fields)
        except dataset.UploadError as e:
            return jsonify(error=str(e)), 400
        return jsonify(saved=len(rows), photos=rows)

    @app.patch("/api/photos/<image_id>")
    def edit(image_id):
        try:
            row = dataset.update_photo(cfg, image_id, request.get_json(force=True))
        except KeyError:
            abort(404)
        except dataset.UploadError as e:
            return jsonify(error=str(e)), 400
        return jsonify(row)

    @app.delete("/api/photos/<image_id>")
    def delete(image_id):
        try:
            dataset.delete_photo(cfg, image_id)
        except KeyError:
            abort(404)
        return jsonify(ok=True)

    @app.get("/thumb/<path:file>")
    def thumb(file):
        raw = cfg.path_of("raw_dir")
        src = (raw / file).resolve()
        if not src.is_relative_to(raw) or not src.is_file():
            abort(404)
        out = THUMBS_DIR / f"{file.replace('/', '__')}.jpg"
        if not out.exists() or out.stat().st_mtime < src.stat().st_mtime:
            out.parent.mkdir(parents=True, exist_ok=True)
            im = ImageOps.exif_transpose(Image.open(src)).convert("RGB")
            im.thumbnail((320, 320))
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=82)
            out.write_bytes(buf.getvalue())
        return send_file(out, mimetype="image/jpeg", max_age=3600)

    # ---------- training ----------

    def jobs() -> list[dict]:
        out = []
        for d in sorted(JOBS_DIR.glob("*/job.json"), reverse=True):
            info = json.loads(d.read_text())
            if info.get("status") == "running" and not _alive(info.get("pid")):
                info["status"] = "stopped"
                Job(info["name"]).update(status="stopped", finished=info.get("finished") or now())
            out.append(info)
        return out

    def installed_version() -> str | None:
        meta = APP_MODEL_DIR / "model_meta.json"
        return json.loads(meta.read_text()).get("model_version") if meta.exists() else None

    @app.get("/api/train")
    def train_state():
        return jsonify({
            "jobs": jobs(),
            "stages": STAGES,
            "models": MODELS,
            "defaults": {k: cfg["train"][k] for k in ("head_epochs", "finetune_epochs")},
            "installed": installed_version(),
            "public_available": PUBLIC_SOURCE.exists(),
        })

    @app.post("/api/train")
    def start():
        body = request.get_json(force=True)
        model = body.get("model")
        if model not in MODELS:
            return jsonify(error=f"unknown model {model!r}"), 400
        with proc_lock:
            if any(j["status"] == "running" for j in jobs()):
                return jsonify(error="a training run is already in progress"), 409
            name = f"{datetime.now():%Y%m%d-%H%M%S}_{model}"
            job = Job(name)
            job.dir.mkdir(parents=True)
            settings = {
                "public": bool(body.get("public")),
                "head_epochs": _int(body.get("head_epochs")),
                "finetune_epochs": _int(body.get("finetune_epochs")),
                "strict_kappa": bool(body.get("strict_kappa")),
            }
            job.update(name=name, model=model, status="running", stage="queued",
                       started=now(), settings=settings)
            cmd = [sys.executable, "-u", "-m", "portal.train_job", "--name", name, "--model", model]
            if settings["public"]:
                cmd.append("--public")
            if settings["head_epochs"] is not None:
                cmd += ["--head-epochs", str(settings["head_epochs"])]
            if settings["finetune_epochs"] is not None:
                cmd += ["--finetune-epochs", str(settings["finetune_epochs"])]
            if settings["strict_kappa"]:
                cmd.append("--strict-kappa")
            log = open(job.dir / "log.txt", "w")
            p = subprocess.Popen(cmd, cwd=TRAINING_DIR, stdout=log, stderr=subprocess.STDOUT,
                                 start_new_session=True)
            job.update(pid=p.pid)
        return jsonify(name=name)

    @app.post("/api/train/<name>/stop")
    def stop(name):
        job = _job_or_404(name)
        info = job.read()
        if info.get("status") == "running" and _alive(info.get("pid")):
            os.killpg(info["pid"], signal.SIGTERM)
        job.update(status="stopped", finished=now())
        return jsonify(ok=True)

    @app.get("/api/train/<name>/log")
    def log(name):
        job = _job_or_404(name)
        path = job.dir / "log.txt"
        text = path.read_text(errors="replace") if path.exists() else ""
        # Keras rewrites progress lines with \r; keep only the last state of each.
        lines = [ln.split("\r")[-1] for ln in text.splitlines()]
        return jsonify(log="\n".join(lines[-400:]), job=job.read())

    @app.get("/api/train/<name>/confusion.png")
    def confusion(name):
        info = _job_or_404(name).read()
        img = Path(info.get("run_dir", "")) / "test_confusion.png"
        if not info.get("run_dir") or not img.exists():
            abort(404)
        return send_file(img, mimetype="image/png")

    @app.post("/api/train/<name>/install")
    def install(name):
        info = _job_or_404(name).read()
        if info.get("status") != "done":
            return jsonify(error="only finished runs can be installed"), 400
        src = Path(info["run_dir"]) / "tflite"
        exports = TRAINING_DIR / "exports"
        exports.mkdir(exist_ok=True)
        for f in ("model.tflite", "labels.json", "model_meta.json", "export_report.json"):
            shutil.copy(src / f, exports / f)
        r = subprocess.run([str(REPO / "scripts" / "copy_model_to_app.sh")], capture_output=True, text=True)
        if r.returncode:
            return jsonify(error=r.stderr or r.stdout), 500
        return jsonify(installed=installed_version(), output=r.stdout)

    @app.delete("/api/train/<name>")
    def remove(name):
        job = _job_or_404(name)
        info = job.read()
        if info.get("status") == "running":
            return jsonify(error="stop the run first"), 400
        if info.get("run_dir"):
            shutil.rmtree(info["run_dir"], ignore_errors=True)
        shutil.rmtree(job.dir, ignore_errors=True)
        return jsonify(ok=True)

    return app


def _job_or_404(name: str) -> Job:
    job = Job(name)
    if not _RUN_NAME.match(name) or not job.file.exists():
        abort(404)
    return job


def _alive(pid) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    # A finished child stays a zombie until reaped; reap it so it reads as dead.
    try:
        done, _ = os.waitpid(pid, os.WNOHANG)
        return done == 0
    except ChildProcessError:
        return True


def _int(v) -> int | None:
    try:
        return max(0, int(v)) if v not in (None, "") else None
    except (TypeError, ValueError):
        return None
