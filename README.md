# HarvestShelf AI

An offline Android app that sorts a phone photo of a tomato or green
banana into **Fresh · Sell Soon · Discount Today · Spoilage Risk ·
Uncertain**, for small market sellers in Nyabihu and Rusizi, Rwanda.
BSc Software Engineering project by Sage Muhodari. The full proposal is
`HarvestShelf_AI_Revised_Research_Proposal_Expanded_Evidence.docx`.

> The app judges **visible condition only**. It is not a food-safety check.

## The project notebook

**`training/notebooks/HarvestShelf_AI.ipynb`** is one notebook with everything: the problem, the system, the data, the training, **the outputs of the trained models** (metrics, confusion matrices, training curves, example predictions, a live run of the app's model), the comparison of all candidate models, the on-device results, app screenshots, limitations and how to reproduce. It was saved with its outputs, so you can read it without running anything. To re-run it:

```bash
cd training && .venv/bin/jupyter lab notebooks/HarvestShelf_AI.ipynb   # kernel: "HarvestShelf (training/.venv)"
```

## Repository layout

```
app/          Flutter Android app (offline; no INTERNET permission in release)
training/     Python/TensorFlow pipeline: clean → split → train → thresholds → evaluate → export
shared/       decision_cases.json: one decision rule, tested in both Dart and Python
data/         raw photos + metadata.csv (not committed)
docs/         labeling guide, data-collection protocol
evaluation/   SUS, seller-agreement study, on-device latency analysis
scripts/      copy_model_to_app.sh, build_release.sh
```

## How a scan works

```
photo (camera/gallery, ≤1280 px)
  → quality check: brightness 40–235, sharpness ≥ 50     fail → Uncertain (too dark / bright / blurry)
  → centre square crop, resize 224×224, RGB 0–255
  → TFLite model on the phone → 9 probabilities
       (tomato × 4, banana × 4, unusable)
  → decision rule:
       top = unusable                      → Uncertain
       P(spoilage of that crop) ≥ t_spoil  → Spoilage Risk
       top probability < t_conf            → Uncertain
       otherwise                           → top category
  → advice text from SQLite guidance_rule → scan saved to SQLite
```

`t_conf` and `t_spoil` are tuned on the validation set
(`src.thresholds`). `t_spoil` is the main lever for the
spoilage-recall ≥ 0.85 target. Both values ship in `model_meta.json`, so
retraining never needs Dart changes.

## Development environment

| Part | Setup | Check |
|---|---|---|
| App | Flutter **3.32.5** (pinned in `.fvmrc`; `pubspec.yaml` requires ≥ 3.32.0), Android SDK 36, NDK 27 | `cd app && flutter analyze && flutter test` |
| Training | Python **3.11** venv: `cd training && python3.11 -m venv .venv && .venv/bin/pip install -r requirements.txt` | `make test` |
| Training in Docker | `docker build -t harvestshelf-train:2.15 training/` then `docker run --rm -it -v "$PWD":/workspace -w /workspace/training harvestshelf-train:2.15` | `python -m pytest -q tests` (35 pass in the container) |
| Dataset | `cd training && make data-public` downloads AgriFreshNET (348 MB, CC BY 4.0) | |
| Notebook kernel | `.venv/bin/python -m ipykernel install --sys-prefix --name harvestshelf` | open `notebooks/HarvestShelf_AI.ipynb` |
| CI | `.github/workflows/ci.yml` runs the app tests and the Python tests plus a smoke test on every push | runs once the repo is pushed to GitHub |

## Quick start

### App

```bash
cd app
flutter test                 # 74 tests: accounts, PIN hashing, DB upgrade, decision rule, quality check, Pillow-exact resize, full app flow
flutter test integration_test/parity_test.dart -d <device>   # phone vs Python on real test photos
flutter run                  # on a connected Android phone
../scripts/build_release.sh  # release APKs; fails if INTERNET/phone/storage permissions sneak in
```

## Languages

English and **Kinyarwanda**, switched on the Welcome screen or in Profile → Language, and remembered on the phone. All text is in `app/lib/l10n/app_text.dart`, with English and Kinyarwanda side by side. **The Kinyarwanda must be reviewed by a native speaker before the field study.** Android's own system buttons stay in English, because Flutter has no built-in Kinyarwanda for them.

## Accounts (offline)

Accounts live only on the phone (SQLite), so the app still needs no internet.

- **Register / log in** with a name, a username and a 4–6 digit PIN. Obvious PINs (`1234`, `0000`, …) are refused.
  PINs are stored as PBKDF2-HMAC-SHA256 hashes (60,000 iterations, random salt), never in plain text.
- **The first account on a phone becomes the Researcher.** Later sign-ups are Sellers.
- **Researchers** can add users, change roles, reset PINs, delete users (along with their scans) and export the log.
  The last researcher can't be removed.
- **Sellers** see only their own scan history.
- **Five wrong PINs** lock the account for 30 seconds. A wrong username and a wrong PIN give the same error.
- **Sessions survive app restarts.** Log out from Profile.
- **The exported CSV** has an anonymous `user_id` number, but no names or usernames.
- **Upgrading from database v1 → v2** keeps existing scans. They have no owner, so they appear only in the export.

Note for the proposal: the app now stores each user's display name and username on the phone.

## Logo

`scripts/make_logo.py` draws the icon from basic shapes: a tomato and a hand of green cooking bananas on a market shelf, inside camera scan corners.
Regenerate it with `python scripts/make_logo.py && (cd app && dart run flutter_launcher_icons)`.
The font is Nunito (SIL Open Font License, `app/assets/fonts/OFL.txt`), bundled in the app.

## Current status (11 Oct 2026)

The app bundles an **interim model**: **EfficientNet-Lite0** (3.7 MB) trained on the public **AgriFreshNET** dataset (CC BY 4.0, Bangladesh). A notice in the app says so. **No Rwandan photos have been collected yet**, there are no Discount Today examples, and the bananas are mostly yellow dessert bananas photographed alone on a white cloth.

Test results on held-out capture sessions:

| Model | Macro-F1 | Spoilage recall | Phone size | Role |
|---|---|---|---|---|
| **EfficientNet-Lite0** | 0.822 | 0.957 | 3.7 MB | **in the app** |
| EfficientNetV2-B0 (replaces MobileNetV2) | 0.829 | 0.971 | 11.8 MB | just over the 10 MB limit |
| ResNet50 | 0.840 | 0.957 | 24.0 MB | accuracy reference |
| MobileNetV3-Small | 0.822 | 0.957 | 1.9 MB | baseline only (owner chose not to use MobileNet in the app) |
| Random Forest / SVM | 0.640 / 0.532 | 0.886 / 0.929 | n/a | classical baselines |
| *Target* | *≥ 0.80* | *≥ 0.85* | *< 10 MB* | |

Details, graphs and the requirements traceability matrix are in the notebook and in `docs/requirements_traceability.md`.

Rebuild everything: `cd training && make public`, then re-run the notebook.

## Proposal targets → where they are measured

| Target | Where |
|---|---|
| action macro-F1 ≥ 0.80, Spoilage recall ≥ 0.85 | `src.evaluate --split test` → `test_metrics.json` |
| inference < 1 s on a 3–4 GB phone | app log `inference_ms` → `analysis.py latency` |
| app < 50 MB, model < 10 MB | `build_release.sh`, `export_report.json` |
| SUS ≥ 68 (at least 15 sellers) | `analysis.py sus` |
| +15 pts agreement with experts | `analysis.py agreement` (see `evaluation/agreement_study/protocol.md`) |

Requirements FR1–FR6 and NFR1–NFR6 are referenced in comments next to
the code that implements them.
