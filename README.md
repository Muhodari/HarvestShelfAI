# HarvestShelf AI

[![CI](https://github.com/Muhodari/HarvestShelfAI/actions/workflows/ci.yml/badge.svg)](https://github.com/Muhodari/HarvestShelfAI/actions/workflows/ci.yml)

<img src="docs/screenshots/logo.png" alt="HarvestShelf AI logo" width="120">

**An offline Android app that tells small market sellers what to do with their produce, from one phone photo.**

**[Technical report](https://drive.google.com/file/d/1YiQ53JR2ZipCdPhxwCKYiUp9FxvTOzZ_/view?usp=sharing)**

| | |
|---|---|
| **GitHub repository** | [github.com/Muhodari/HarvestShelfAI](https://github.com/Muhodari/HarvestShelfAI) |
| **Demo video** | [youtube.com/watch?v=JMLj4KbZb0w](https://www.youtube.com/watch?v=JMLj4KbZb0w) |
| **Technical report** | [drive.google.com/file/d/1YiQ53JR2ZipCdPhxwCKYiUp9FxvTOzZ_](https://drive.google.com/file/d/1YiQ53JR2ZipCdPhxwCKYiUp9FxvTOzZ_/view?usp=sharing) |
| **Project notebook** | [`training/notebooks/HarvestShelf_AI.ipynb`](training/notebooks/HarvestShelf_AI.ipynb) |

---

## Contents

1. [Description](#1-description)
2. [GitHub repository](#2-github-repository)
3. [Setting up the environment and the project](#3-setting-up-the-environment-and-the-project)
4. [Designs](#4-designs)
5. [Deployment plan](#5-deployment-plan)
6. [Scope alignment and feature validation](#6-scope-alignment-and-feature-validation)
7. [Architecture](#7-architecture)
8. [Technical details](#8-technical-details)
9. [Testing, validation and performance](#9-testing-validation-and-performance)
10. [Algorithms and technical problem-solving](#10-algorithms-and-technical-problem-solving)

---

## 1. Description

A seller photographs one tomato or one hand of green bananas and gets one action:

| Action | Meaning |
|---|---|
| **Fresh** | Sell at the normal price |
| **Sell Soon** | Early signs of change: sell it first |
| **Discount Today** | Lower the price, sell today |
| **Spoilage Risk** | Remove from sale |
| **Uncertain** | Bad photo, model unsure, or unsupported crop: retake |

Bananas: green = Fresh, yellow = Sell Soon, spotted = Discount Today, black = Spoilage Risk. With several items, the **worst** one decides.

| | |
|---|---|
| **Crops** | Tomato and green banana only (anything else → Uncertain) |
| **Platform** | Android, Flutter |
| **Internet** | Not needed: no INTERNET permission in the release build |
| **Languages** | English, Kinyarwanda |
| **Model** | EfficientNet-Lite0, TensorFlow Lite, 3.6 MB |
| **Accounts** | On the phone only, PIN login, Researcher and Seller roles |

> Judges **visible condition only**. Not a food-safety check.

BSc Software Engineering project by **Sage Muhodari**, for sellers in Nyabihu and Rusizi, Rwanda.

## 2. GitHub repository

```bash
git clone https://github.com/Muhodari/HarvestShelfAI.git
```

```
app/        Flutter app (offline)
training/   Python/TensorFlow pipeline, training portal, notebook
shared/     decision and quality-check cases tested in Dart and Python
scripts/    build_release.sh, copy_model_to_app.sh
data/       field photos (not committed)
```

## 3. Setting up the environment and the project

| Part | Setup | Check |
|---|---|---|
| **App** | Flutter 3.32.5 (`.fvmrc`), Android SDK 36, NDK 27 | `cd app && flutter analyze && flutter test` |
| **Training** | Python 3.11: `cd training && python3.11 -m venv .venv && .venv/bin/pip install -r requirements.txt` | `make test PY=.venv/bin/python` |
| **Docker** (optional) | `docker build -t harvestshelf-train:2.15 training/` | `python -m pytest -q tests` |
| **Data** | `make data-public` and `make data-large` (Kaggle key in `~/.kaggle/kaggle.json`) | |

```bash
cd app
flutter run                                              # on a connected Android phone
flutter test integration_test/parity_test.dart -d <id>   # phone vs Python on real photos
../scripts/build_release.sh                              # release APKs; fails on extra permissions

cd ../training
.venv/bin/python -m portal                               # training portal → http://127.0.0.1:8765
make large PY=.venv/bin/python                           # full retrain from the command line (~1 h on M3 GPU)
```

## 4. Designs

**Screen design:** low-fidelity wireframes in the proposal (Figure 10), built in Flutter. Every result screen has the same layout: photo, action and confidence, what to do.

**Circuit diagram:** none. The project is software only on an ordinary phone, so the system architecture is shown instead.

<img src="docs/architecture/system_architecture.png" alt="System architecture: offline Android app and training pipeline" width="900">

**Screenshots** (Pixel 8 emulator; [photo credits](docs/screenshots/CREDITS.md)):

| Welcome | Scan | History |
|:-:|:-:|:-:|
| <img src="docs/screenshots/welcome.png" width="230"> | <img src="docs/screenshots/scan_tab.png" width="230"> | <img src="docs/screenshots/history.png" width="230"> |

| Banana: Fresh | Banana: Sell Soon | Banana: Spoilage Risk |
|:-:|:-:|:-:|
| <img src="docs/screenshots/result_fresh_banana.png" width="230"> | <img src="docs/screenshots/result_sell_soon_banana.png" width="230"> | <img src="docs/screenshots/result_spoilage_banana.png" width="230"> |

| Tomato: Fresh | Tomato: Spoilage Risk | Bottle: not produce |
|:-:|:-:|:-:|
| <img src="docs/screenshots/result_fresh_tomato.png" width="230"> | <img src="docs/screenshots/result_spoilage_tomato.png" width="230"> | <img src="docs/screenshots/result_not_produce.png" width="230"> |

## 5. Deployment plan

Installed **directly as an APK** on study phones (no Play Store, no internet).

| Step | Action | Tool |
|---|---|---|
| 1. Test | Tests and lint on every push | GitHub Actions |
| 2. Train | Upload labelled photos, retrain, check targets | Training portal |
| 3. Install model | Copy model + thresholds into the app; no code change | **Install in app** / `copy_model_to_app.sh` |
| 4. Build | One APK per CPU type (< 50 MB); fails on extra permissions | `build_release.sh` |
| 5. Install | `adb install app-arm64-v8a-release.apk`; first account = Researcher | adb |
| 6. Field study | Sellers in Nyabihu and Rusizi use the app | the app |
| 7. Collect | Export anonymous CSV scan log | Profile → Export |
| 8. Update | Retrain on new photos, install the new APK over the old one | steps 2–5 |

## 6. Scope alignment and feature validation

Requirement IDs match the comments beside the code that implements them.

| Feature (proposal) | Status | Evidence |
|---|---|---|
| **FR1** Take or choose a photo | Completed | [`scan_screen.dart`](app/lib/screens/scan_screen.dart) |
| **FR2** Photo quality check | Completed | [`image_quality_service.dart`](app/lib/services/image_quality_service.dart); same cases in Dart and Python |
| **FR3** On-device model | Completed | [`classifier_service.dart`](app/lib/services/classifier_service.dart); phone = Python on 24/24 photos |
| **FR4** Action, confidence, advice | Completed | [`decision_mapper.dart`](app/lib/services/decision_mapper.dart), [`guidance_rules.json`](app/assets/guidance_rules.json) |
| **FR5** Scan history | Completed | [`repositories.dart`](app/lib/data/repositories.dart); sellers see only their own scans |
| **FR6** Anonymous export | Completed | [`export_service.dart`](app/lib/services/export_service.dart) |
| **NFR1** Offline | Completed | No INTERNET permission; `build_release.sh` enforces it |
| **NFR5** Privacy | Completed | Local SQLite; PBKDF2-hashed PINs |
| **NFR6** Cautious decisions | Completed | Tuned thresholds; [`shared/decision_cases.json`](shared/decision_cases.json) |
| Accuracy: macro-F1 ≥ 0.80, spoilage recall ≥ 0.85 | Met on held-out test set: **0.923 / 0.956** | [Results](#results) |
| Speed < 1 s, model < 10 MB, app < 50 MB | Met: 124 ms (emulator), 3.6 MB, 14–15 MB | [Performance](#performance) |
| Model comparison | Completed for 4 CNNs + SVM + Random Forest | [Notebook](training/notebooks/HarvestShelf_AI.ipynb), [`compare.py`](training/src/compare.py) |
| English and Kinyarwanda | Completed; native-speaker review pending | [`app_text.dart`](app/lib/l10n/app_text.dart) |
| Screen designs | Completed with proposal wireframes | [Designs](#4-designs) |
| Market photo dataset, kappa ≥ 0.70 | Partial: Kimironko photos collected, labelling pending | Kappa check in [`clean.py`](training/src/clean.py); portal takes a second label |
| Field study with sellers | Planned | Export (FR6) ready |
| Signed release APK | Partial: debug key | [`build.gradle.kts`](app/android/app/build.gradle.kts) |

## 7. Architecture

Small modules with one job each. Dependencies point one way: **screens → services → data → models**.

<img src="docs/architecture/app_layers.png" alt="Flutter app layers: screens, services, data, models" width="900">

| OOP principle | Where |
|---|---|
| **Abstraction** | `TriageService` depends on the `ImageClassifier` interface; the app uses `ClassifierService`, tests use `FixedClassifier` |
| **Single responsibility** | `QualityReport`, `prepareImage`, `ClassifierService`, `DecisionMapper`, `TriageService`, `ScanRepository`, `PinHasher`, `AuthService` |
| **Encapsulation** | Only [`repositories.dart`](app/lib/data/repositories.dart) touches SQL |
| **Dependency injection** | [`app_services.dart`](app/lib/app_services.dart) builds and wires every service through constructors |
| **Immutable value objects** | `Scan`, `TriageResult`, `ModelMeta`, `AppUser` are `const` classes with factories |
| **Data-driven** | Thresholds and advice load from `model_meta.json` and `guidance_rules.json` |

<img src="docs/architecture/training_pipeline.png" alt="Training pipeline from photos to the model in the app" width="900">

```
app/lib/   models/ · data/ (SQLite) · services/ (scan pipeline, auth/) · screens/ · widgets/ · l10n/ · core/
training/  src/ (clean → split → train → thresholds → evaluate → export) · tools/ · portal/ · tests/
```

## 8. Technical details

### How a scan works

```
photo (≤ 1280 px)
  → quality check (brightness 40–235, sharpness ≥ 80)     fail → Uncertain
  → centre crop 224×224 → TFLite model → 9 probabilities (2 crops × 4 actions + unusable)
  → decision rule:  unusable → Uncertain
                    P(spoilage) ≥ t_spoil → Spoilage Risk
                    top < t_conf → Uncertain
                    else → top action
  → advice → saved on the phone
```

`t_conf` and `t_spoil` are tuned on the validation set and shipped in `model_meta.json`.

### Results

23,024 training photos after cleaning, plus 5,400 generated multi-item scenes. Tested on 4,307 held-out images:

| Test images | Macro-F1 | Spoilage recall | Non-produce rejected |
|---|:-:|:-:|:-:|
| Single photos (3,607) | 0.957 | 0.973 | 0.930 |
| Multi-item scenes (700) | 0.718 | 0.868 | 0.960 |
| **All** | **0.923** | **0.956** | **0.935** |
| *Target* | *≥ 0.80* | *≥ 0.85* | |

Per action F1: Fresh 0.94, Sell Soon 0.90, Discount Today 0.88, Spoilage Risk 0.96.

**Limits:** multi-item photos are harder (the app asks for one item); tomato Sell Soon and Discount Today have few examples; accuracy in Rwandan markets still has to be measured.

<details>
<summary>Data sources and licences</summary>

| Dataset | Licence |
|---|---|
| [AgriFreshNET](https://doi.org/10.17632/42m5tb7yv9.1) | CC BY 4.0 |
| [Banana Ripeness Classification](https://www.kaggle.com/datasets/shahriar26s/banana-ripeness-classification-dataset) | see page |
| [Fresh and Stale Fruits and Vegetables](https://www.kaggle.com/datasets/raghavrpotdar/fresh-and-stale-images-of-fruits-and-vegetables) | see page |
| [Fruit and Vegetable Disease](https://www.kaggle.com/datasets/muhammad0subhan/fruit-and-vegetable-disease-healthy-vs-rotten) | CC0 |
| [Garbage Classification](https://www.kaggle.com/datasets/asdasdasasdas/garbage-classification) | see page |
| [Imagenette](https://github.com/fastai/imagenette) | research use |

</details>

### Training portal

`cd training && .venv/bin/python -m portal`, then open http://127.0.0.1:8765 (local only).

| Tab | Use |
|---|---|
| **Upload** | Add photos with crop, label, market, date, batch |
| **Photos** | Counts vs 300-per-label target; second label for the kappa check |
| **Train** | Pick model and epochs, follow the live log; **Install in app** copies the model, then rebuild |

### Accounts

PIN 4–6 digits (obvious PINs refused), PBKDF2-HMAC-SHA256 with 60,000 iterations, five wrong PINs → 30 s lockout. First account is the Researcher (manages users, exports); Sellers see only their own scans.

### Project notebook

[`HarvestShelf_AI.ipynb`](training/notebooks/HarvestShelf_AI.ipynb) is saved with outputs: data, training, model comparison, confusion matrices, example predictions.

## 9. Testing, validation and performance

**125 tests pass** (75 Flutter, 50 Python); `flutter analyze` and `ruff` clean; CI runs everything on every push.

### Strategies

| Strategy | Proves | Where |
|---|---|---|
| Unit | Decision rule, quality check, resize, PBKDF2 (test vectors), repositories | `app/test/`, `training/tests/` |
| Widget | Each result renders the right action and advice | `widget_test.dart` |
| App flow | Register → home → history → profile → log out → log in; language switch | `app_navigation_test.dart` |
| Migration | DB v1 → v2 → v3 keeps data | `data_test.dart` |
| Cross-language | Dart and Python agree on shared cases | [`shared/`](shared/) |
| On-device parity | Phone TFLite = Python on real photos (24/24) | `integration_test/parity_test.dart` |
| Pipeline | clean → train → export smoke test | `tools/smoke_test.py` |
| Model | Held-out test set, never used for tuning | `src.evaluate --split test` |

### Edge cases

| Case | Behaviour |
|---|---|
| Black, white or flat photo | Uncertain, model not run |
| Confidence exactly at threshold | Accepted |
| Wrong number of model outputs | Error, not a silent answer |
| Spoilage high but not top class | Spoilage Risk wins |
| Bottle or non-produce | "No vegetable or fruit found" |
| Obvious PIN, duplicate username | Refused |
| Wrong PIN vs unknown user | Same error |
| Five wrong PINs | 30 s lockout |
| Removing the last researcher | Refused |

### Compatibility

| Environment | Result |
|---|---|
| 360 × 640 small phone · 412 × 915 at text 1.6 and 2.0 · 915 × 412 landscape | All screens fit (`layout_test.dart`) |
| Screen reader | Key controls labelled |
| Android (Pixel 8 emulator) · iOS simulator | App runs |
| Ubuntu (CI) · macOS | All tests pass |

### Performance

| Measure | Result | Target |
|---|---|---|
| Inference on phone (median) | **124 ms** | < 1 s |
| Full scan shown to user | 299–408 ms | < 1 s |
| Model / APK size | 3.6 MB / 14–15 MB | < 10 MB / < 50 MB |
| Candidates on laptop CPU | Lite0 8.6 ms · MobileNetV3-S 2.4 ms · EffNetV2-B0 20.4 ms · ResNet-50 36.6 ms | |

## 10. Algorithms and technical problem-solving

| Problem | Solution | Code |
|---|---|---|
| Missing spoilage costs most | Decision rule checks spoilage **before** confidence | [`decision_mapper.dart`](app/lib/services/decision_mapper.dart) |
| Choosing thresholds | Grid search: max macro-F1 with spoilage recall ≥ 0.85, Uncertain ≤ 15 %, non-produce rejected ≥ 95 % | [`thresholds.py`](training/src/thresholds.py) |
| Blur check rejected 43 % of sharp tomatoes | Laplacian variance of the **sharpest tile** in a 4 × 4 grid | [`image_quality_service.dart`](app/lib/services/image_quality_service.dart) |
| Photo copies leaking into the test set | Difference hashing + banding (no n² compare) + **union-find** groups; grouped split | [`dedupe.py`](training/tools/large/dedupe.py) |
| Multi-item photos | Generated scenes labelled by the worst item | [`scenes.py`](training/tools/large/scenes.py) |
| Phone and Python must see the same pixels | Dart resize matching Pillow's BOX filter, tested against it | [`resize.dart`](app/lib/services/resize.dart) |
| Smooth UI | Image work on a background isolate | [`preprocessing_service.dart`](app/lib/services/preprocessing_service.dart) |
| PINs on a shared phone | PBKDF2 + salt, uniform errors, lockout | [`pin_hasher.dart`](app/lib/services/auth/pin_hasher.dart) |
