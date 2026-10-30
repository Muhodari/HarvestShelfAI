# HarvestShelf AI

<img src="docs/screenshots/logo.png" alt="HarvestShelf AI logo" width="120">

**An offline Android app that tells small market sellers what to do with their produce, from one phone photo.**

| | |
|---|---|
| **GitHub repository** | [github.com/Muhodari/HarvestShelfAI](https://github.com/Muhodari/HarvestShelfAI) |
| **Demo video** | [youtu.be/yV0wDrwIIkw](https://youtu.be/yV0wDrwIIkw) |
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

---

## 1. Description

Small produce sellers in Rwanda lose income when tomatoes and green bananas spoil before they are sold. HarvestShelf AI lets a seller point a phone camera at one tomato or one hand of green bananas and get one clear action back:

| Action | Meaning for the seller |
|---|---|
| **Fresh** | Sell at the normal price |
| **Sell Soon** | Early signs of change: put it at the front and sell it first |
| **Discount Today** | Lower the price and sell it today |
| **Spoilage Risk** | Remove from sale; keep it away from fresh produce |
| **Uncertain** | Photo too dark or blurry, model unsure, or not a supported crop: retake the photo |

**Bananas** follow one ripeness scale for green cooking bananas: **green** is Fresh, **yellow** is Sell Soon, **spotted** is Discount Today, and **black or rotten** is Spoilage Risk. If a photo holds several items, the answer is for the **worst** one: one rotten banana in a bunch gives Spoilage Risk.

Built for sellers in **Nyabihu and Rusizi, Rwanda**. BSc Software Engineering project by **Sage Muhodari**.

| | |
|---|---|
| **Crops** | Tomato and green banana only |
| **Platform** | Android phone, Flutter app |
| **Internet** | Not needed: the model runs on the phone, and the release build has no INTERNET permission |
| **Languages** | English and Kinyarwanda |
| **Model** | EfficientNet-Lite0, TensorFlow Lite, 3.6 MB, trained on about 23,000 public photos from 6 datasets |
| **Accounts** | Stored on the phone only, with PIN login (Researcher and Seller roles) |
| **Training** | Python / TensorFlow pipeline, with a browser portal for uploading photos and retraining |

> **Important: only tomatoes and green bananas are supported.** Photos of anything else (oranges, potatoes, onions, …) are answered with **Uncertain**, never with a freshness result.

> **Warning:** the app judges **visible condition only**. It is **not a food-safety check**.

## 2. GitHub repository

**[https://github.com/Muhodari/HarvestShelfAI](https://github.com/Muhodari/HarvestShelfAI)**

```bash
git clone https://github.com/Muhodari/HarvestShelfAI.git
cd HarvestShelfAI
```

### Repository layout

```
app/          Flutter Android app (offline)
training/     Python/TensorFlow pipeline: clean → split → train → thresholds → evaluate → export
  portal/     browser portal to upload photos and train
  notebooks/  the project notebook
shared/       decision rule and quality-check cases, tested in both Dart and Python
data/         field photos + metadata.csv (not committed)
scripts/      copy_model_to_app.sh, build_release.sh, make_logo.py
```

## 3. Setting up the environment and the project

### Requirements

| Part | Setup | Check |
|---|---|---|
| **App** | Flutter **3.32.5** (pinned in `.fvmrc`), Android SDK 36, NDK 27 | `cd app && flutter analyze && flutter test` |
| **Training** | Python **3.11**: `cd training && python3.11 -m venv .venv && .venv/bin/pip install -r requirements.txt` | `make test PY=.venv/bin/python` |
| **Training in Docker** | `docker build -t harvestshelf-train:2.15 training/`, then `docker run --rm -it -v "$PWD":/workspace -w /workspace/training harvestshelf-train:2.15` | `python -m pytest -q tests` |
| **Public dataset** | `cd training && make data-public` downloads AgriFreshNET (348 MB, CC BY 4.0) | |
| **Large dataset** | `make data-large PY=.venv/bin/python` downloads 5 more public datasets (about 3 GB after unpacking). Needs a free Kaggle account: save your API key as `~/.kaggle/kaggle.json` | |
| **Apple Silicon GPU** (optional) | `.venv/bin/pip install tensorflow-metal==1.1.0` trains about 3× faster on M-series Macs | |
| **Notebook kernel** | `.venv/bin/python -m ipykernel install --sys-prefix --name harvestshelf` | open the notebook |
| **CI** | `.github/workflows/ci.yml` runs the app tests, the Python tests and a smoke test on every push | |

### Run the app

```bash
cd app
flutter test                                                   # unit, widget and full-app-flow tests
flutter test integration_test/parity_test.dart -d <device>     # phone vs Python on real test photos
flutter run                                                    # on a connected Android phone
../scripts/build_release.sh                                    # release APKs; fails if extra permissions sneak in
```

### Retrain from the command line

```bash
cd training
make large PY=.venv/bin/python      # all 6 public datasets + mixed scenes → train → test → install in the app (about 1 hour on an M3 GPU)
make public PY=.venv/bin/python     # AgriFreshNET only: train all candidate models and compare them
```

### Training portal (optional)

```bash
cd training && .venv/bin/python -m portal      # then open http://127.0.0.1:8765
```

See [Training portal](#training-portal-add-photos-and-retrain) below for what each tab does.

## 4. Designs

### Figma mockups

<!-- TODO: replace with the Figma link and an exported image of the mockups -->
**Figma file:** *link to be added*

### Circuit diagram

HarvestShelf AI is **software only**: it runs on an ordinary Android phone and uses no extra hardware, sensors or circuits, so there is no circuit diagram. The system architecture is shown instead:

```mermaid
flowchart LR
    subgraph Phone["Android phone (offline)"]
        CAM[Camera / gallery] --> QC[Quality check<br/>brightness, sharpness]
        QC --> PRE[Crop + resize<br/>224 x 224]
        PRE --> TFL[TFLite model<br/>EfficientNet-Lite0]
        TFL --> DEC[Decision rule<br/>t_conf, t_spoil]
        DEC --> UI[Result + advice]
        UI --> DB[(SQLite<br/>users, scans)]
        DB --> CSV[CSV export]
    end
    subgraph Laptop["Researcher laptop"]
        PORTAL[Training portal] --> DATA[(data/raw +<br/>metadata.csv)]
        DATA --> TRAIN[TensorFlow training<br/>+ evaluation]
        TRAIN --> EXP[model.tflite<br/>model_meta.json]
    end
    EXP -- rebuild APK --> TFL
```

### Screenshots of the app

| Scan tab | Spoilage Risk result | Fresh result |
|:-:|:-:|:-:|
| <img src="docs/screenshots/scan_tab.png" width="230"> | <img src="docs/screenshots/result_spoilage.png" width="230"> | <img src="docs/screenshots/result_fresh.png" width="230"> |

All five result types share the same layout: the photo, the action with its confidence, and what to do next. A photo that is not a tomato or a green banana is answered with **Uncertain**:

<img src="docs/screenshots/result_screens.png" alt="Result screens: Fresh, Uncertain, Spoilage Risk" width="900">

> **Note:** these screenshots were taken with the earlier model (October 2026). That model called yellow bananas Fresh; the current one calls them Sell Soon.

## 5. Deployment plan

The app is deployed **directly onto phones as an APK**, not through the Play Store, because it is a research tool used in a supervised field study and needs no internet.

| Step | What happens | Tool |
|---|---|---|
| **1. Test** | Every push runs the app tests, the Python tests and a training smoke test. | GitHub Actions ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) |
| **2. Train the model** | Collect labelled market photos with the training portal, retrain, and check the results against the targets (macro-F1 ≥ 0.80, spoilage recall ≥ 0.85, model < 10 MB). | `training/` pipeline, training portal |
| **3. Install the model** | Copy the exported model and its thresholds into the app. No app code changes are needed. | **Install in app** in the portal, or `scripts/copy_model_to_app.sh` |
| **4. Build the release** | Build one APK per CPU type (each under 50 MB). The build fails if the app asks for internet, phone or storage permissions. | `scripts/build_release.sh` |
| **5. Install on phones** | Copy the APK to each study phone (USB or `adb install`) and install it. The first account created on a phone is the Researcher. | `adb install app-arm64-v8a-release.apk` |
| **6. Field study** | Sellers in Nyabihu and Rusizi markets use the app. Everything stays on the phone. | the app |
| **7. Collect results** | The researcher exports the scan log as CSV (anonymous user IDs, inference time per scan) and compares it with the targets. | Profile → Export |
| **8. Update** | New field photos go back into the portal, the model is retrained, and a new APK is installed over the old one. Existing scans and accounts are kept. | steps 2–5 again |

**Before the field study:** the Kinyarwanda text must be reviewed by a native speaker, and the model should be fine-tuned on Rwandan market photos collected with the training portal (the current model has seen public photos only).

## 6. Scope alignment and feature validation

This section compares the finished project with the approved proposal. Requirement IDs (FR = functional, NFR = non-functional) are the ones cited in code comments next to the code that implements them.

### Feature status

| Planned feature | Intended purpose | Current status | Evidence |
|---|---|---|---|
| **FR1** Take or choose a photo | Let a seller check produce with the phone they already have | **Completed** | Camera and gallery buttons on the Scan tab ([`scan_screen.dart`](app/lib/screens/scan_screen.dart)); screenshot [`scan_tab.png`](docs/screenshots/scan_tab.png) |
| **FR2** Photo quality check | Reject dark, overexposed or blurred photos before they give a wrong answer | **Completed** | [`image_quality_service.dart`](app/lib/services/image_quality_service.dart); same results in Dart and Python ([`shared/quality_cases.json`](shared/quality_cases.json), `image_quality_test.dart`) |
| **FR3** On-device AI model | Classify the produce on the phone, with no internet | **Completed** | [`classifier_service.dart`](app/lib/services/classifier_service.dart); 3.6 MB TFLite model in [`app/assets/model/`](app/assets/model/); phone and Python give the same answer on 24 of 24 test photos (`integration_test/parity_test.dart`) |
| **FR4** One action with confidence and advice | Tell the seller what to do: Fresh, Sell Soon, Discount Today, Spoilage Risk or Uncertain | **Completed** | [`decision_mapper.dart`](app/lib/services/decision_mapper.dart), [`result_screen.dart`](app/lib/screens/result_screen.dart), [`guidance_rules.json`](app/assets/guidance_rules.json); screenshots in [Designs](#screenshots-of-the-app) |
| **FR5** Scan history | Let sellers look back at earlier results | **Completed** | [`history_screen.dart`](app/lib/screens/history_screen.dart), [`repositories.dart`](app/lib/data/repositories.dart); each seller sees only their own scans (`data_test.dart`) |
| **FR6** Anonymous test-log export | Give the researcher data to measure the app in the field study | **Completed** | [`export_service.dart`](app/lib/services/export_service.dart): CSV with an anonymous user ID, no names or photos (`data_test.dart`) |
| **Model accuracy** (Objective 3): macro-F1 ≥ 0.80, Spoilage Risk recall ≥ 0.85, model < 10 MB | Make sure the advice is reliable enough to act on | **Partial**: met on public test data (F1 0.92, recall 0.96, 3.6 MB); not yet measured in Rwandan markets | [Current status](#current-status); `training/sandbox/large/work/experiments/large_efficientnet_lite0/test_metrics.json` |
| **Model comparison** (Section 3.4.5) | Choose the best model for low-cost phones in a fair test | **Partial**: all six models compared on AgriFreshNET; only EfficientNet-Lite0 retrained on the large dataset | [Project notebook](training/notebooks/HarvestShelf_AI.ipynb); [`src/compare.py`](training/src/compare.py) |
| **Rwandan field photo dataset** | Train and test on the produce, light and markets sellers really have | **Partial**: photos collected at **Kimironko market (Kigali)**; not yet labelled, uploaded or used to train or test the model | Upload, labelling and retraining tool ready: [training portal](#training-portal-add-photos-and-retrain). The photos are not in this repository (`data/` is kept out of git) |
| **Labeller agreement check** (Cohen's kappa ≥ 0.70) | Make sure field labels are consistent before training on them | **Not implemented**: needs a second person to label the Kimironko photos | The check is built into [`clean.py`](training/src/clean.py) (`labeling.min_kappa` in [`config.yaml`](training/config.yaml)); the portal's Photos tab takes a second label |
| **Field study** in Nyabihu and Rusizi | Measure the app with real sellers | **Not implemented** | Planned in the [Deployment plan](#5-deployment-plan); the export it needs (FR6) is ready |
| **Figma mockups** | Design the screens before building them | **Not implemented** | Placeholder in [Designs](#figma-mockups); the built screens are shown in [screenshots](#screenshots-of-the-app) |
| **NFR1** Works offline | Markets often have poor or costly internet | **Completed** | No INTERNET permission in [`AndroidManifest.xml`](app/android/app/src/main/AndroidManifest.xml); [`build_release.sh`](scripts/build_release.sh) fails the build if one appears; release APK checked on 30 Oct 2026 |
| **NFR5** Privacy | Keep sellers' photos and data on their own phone | **Completed** | No phone or storage permissions; data in local SQLite; PINs hashed with PBKDF2 ([`pin_hasher.dart`](app/lib/services/auth/pin_hasher.dart)) |
| **NFR6** Explainable, cautious decisions | Never give a confident answer the model is unsure of | **Completed** | Decision rule with tuned thresholds ([How a scan works](#how-a-scan-works)); Python and Dart rules tested on the same cases ([`shared/decision_cases.json`](shared/decision_cases.json)) |
| **Fast scans** (< 1 s on a 3–4 GB phone) | Keep the queue moving at the stall | **Partial**: median 124 ms on a Pixel 8 emulator; not yet timed on a real low-cost phone | `PARITY SUMMARY median_ms=124` from `parity_test.dart`; the field export records `inference_ms` per scan |
| **Small app** (< 50 MB) | Fit on low-storage phones and share easily | **Completed**: 14–15 MB per APK | `flutter build apk --release --split-per-abi` (30 Oct 2026) |
| **Release-ready APK** | Install a trustworthy, updatable build on study phones | **Partial**: the release build is still signed with the debug key | `signingConfig = signingConfigs.getByName("debug")` in [`build.gradle.kts`](app/android/app/build.gradle.kts) |
| **English and Kinyarwanda** | Sellers can use the app in their own language | **Partial**: both languages built in; Kinyarwanda not yet checked by a native speaker | [`app_text.dart`](app/lib/l10n/app_text.dart); language switch on the Welcome screen |

### Scope changes and why

| Change | Type | Reason |
|---|---|---|
| Trained on six **public datasets** instead of Rwandan field photos | Change | The Kimironko photos are not labelled yet. Public data gives a working model now; it will be fine-tuned on the Kimironko photos with the training portal. |
| First field photos from **Kimironko market (Kigali)** | Change | Photos were collected in Kimironko rather than in Nyabihu or Rusizi. The field study is still planned in Nyabihu and Rusizi. |
| **EfficientNetV2-B0** instead of MobileNetV2 as a candidate model | Change | A newer model of similar size gives a fairer modern comparison ([`models.py`](training/src/models.py)). |
| **Local accounts** with Researcher and Seller roles | Added | Several sellers can share one study phone and each sees only their own history; still offline. |
| **Training portal** (browser tool) | Added | Lets the research team upload and label field photos and retrain without the command line. |
| **"Not produce" rejection and mixed-photo handling** | Added | Testing showed bottles and multi-item photos got wrong answers. The model now learns from non-produce images and multi-item scenes, and shows "No vegetable or fruit found" for non-produce. |
| **Green-banana ripeness scale** | Clarified | Yellow bananas are already ripening for a seller of green cooking bananas, so yellow is Sell Soon, not Fresh. |
| **iOS build** | Added | For testing on the iOS simulator. Android remains the target platform. |
| **Tomato Discount Today** answers | Limited | No public dataset has examples of it. It must come from field photos. |

### Still to do

1. **Label the Kimironko photos** with two people, upload them through the [training portal](#training-portal-add-photos-and-retrain), and check agreement (kappa ≥ 0.70).
2. **Fine-tune and re-test the model on them,** including the first tomato **Discount Today** examples, which no public dataset has.
3. **Time the app on a real low-cost phone** (3–4 GB RAM) and test the camera there.
4. **Have a native speaker review** the Kinyarwanda text.
5. **Sign the release APK** with a project key instead of the debug key.
6. **Add the Figma mockups** and **retake the screenshots** with the current model.
7. **Update the project notebook** with the large-dataset results, and retrain the other candidate models on the large dataset for a full comparison.
8. **Run the field study** in Nyabihu and Rusizi.

## 7. Architecture

Both halves of the project are split into small modules, each with one job. Dependencies point inwards (screens → services → data → models), and every service gets what it needs through its constructor, so it can be tested on its own.

```
app/lib/
  models/      plain data classes (Scan, TriageResult, ModelMeta, AppUser)
  data/        SQLite database and repositories: the only code that writes SQL
  services/    the scan pipeline: preprocessing, quality check, classifier, decision rule, triage; auth/ for accounts
  screens/     one file per screen; no business logic
  widgets/     reusable UI pieces, grouped by purpose (scan, layout, forms, users, brand)
  l10n/        all user-facing text, English and Kinyarwanda side by side
  core/        theme, asset paths, time formats
  app_services.dart   composition root: builds every service once at start-up

training/
  src/         one module per pipeline step: clean → split → train → thresholds → evaluate → export
  tools/large/ the large-dataset experiment: sources.py, dedupe.py, scenes.py
  portal/      the browser training portal (Flask)
  tests/       50 unit tests
```

## 8. Technical details

### Current status

*Last updated: 30 Oct 2026*

The app ships with a model trained on **six public datasets**: 23,024 photos after cleaning, plus 5,400 generated mixed scenes. **Field photos have been collected at Kimironko market (Kigali) but are not labelled or used in training yet.**

| Dataset | Licence | What it adds |
|---|---|---|
| [AgriFreshNET](https://doi.org/10.17632/42m5tb7yv9.1) | CC BY 4.0 | tomatoes and bananas at three freshness stages; other crops as "not supported" |
| [Banana Ripeness Classification](https://www.kaggle.com/datasets/shahriar26s/banana-ripeness-classification-dataset) | see Kaggle page | **green** bananas, and the only Discount Today examples (overripe) |
| [Fresh and Stale Fruits and Vegetables](https://www.kaggle.com/datasets/raghavrpotdar/fresh-and-stale-images-of-fruits-and-vegetables) | see Kaggle page | fresh/stale tomatoes, yellow and stale bananas, other produce |
| [Fruit and Vegetable Disease (Healthy vs Rotten)](https://www.kaggle.com/datasets/muhammad0subhan/fruit-and-vegetable-disease-healthy-vs-rotten) | CC0 | healthy/rotten tomatoes, rotten bananas, 9 other crops |
| [Garbage Classification](https://www.kaggle.com/datasets/asdasdasasdas/garbage-classification) | see Kaggle page | bottles, cans, glass, paper: things that are not produce |
| [Imagenette](https://github.com/fastai/imagenette) | ImageNet subset, research use | everyday objects and scenes |

How the data is prepared ([`tools/large_experiment.py`](training/tools/large_experiment.py)):

- **Duplicates are removed or kept together.** Exact copies are dropped. Near-identical photos (resized or re-encoded copies, video frames) are found with image hashing and kept in the same group, so a photo and its copy never end up on both sides of the train/test split.
- **Mixed scenes are generated.** Collages of 2–6 items on varied backgrounds are labelled by the worst item. Test scenes are built only from test photos.
- **Things that are not produce are in the training data,** so bottles, cans and other objects are answered with Uncertain.
- **Thresholds are chosen on the validation set** with an extra rule: at least 95% of "not supported" photos must be shown as Uncertain.

Test results on held-out photos (4,307 photos and scenes the model never saw):

| | Macro-F1 | Spoilage recall | Not-supported rejected |
|---|:-:|:-:|:-:|
| **Single photos** (3,607) | **0.957** | **0.973** | 0.930 |
| Mixed scenes (700) | 0.718 | 0.868 | 0.960 |
| **All test images** | **0.923** | **0.956** | 0.935 |
| Previous model (AgriFreshNET only, its own test set) | 0.822 | 0.957 | n/a |
| ***Target*** | ***≥ 0.80*** | ***≥ 0.85*** | |

Per action on the whole test set: Fresh F1 0.94, Sell Soon 0.90, Discount Today 0.88, Spoilage Risk 0.96. Bottles, cans and everyday objects in the test set were **all** rejected. On the phone (Pixel 8 emulator) the app gives the same answer as Python on all 24 check photos; the median scan takes 124 ms. Model size: 3.6 MB.

**Known limits**

- **Tomato Sell Soon** has only 287 photos (all from AgriFreshNET), and there are **no tomato Discount Today photos** in any public dataset. These are the weakest tomato answers.
- **Mixed scenes** are harder than single photos (F1 0.72). The app still asks for one item per photo.
- **A photo of several plastic bottles** can still be called Spoilage Risk; a single bottle is rejected.
- **The Fresh and Stale test score (0.99) is probably too high.** That dataset is built from video frames, so some near-identical frames may sit in both training and test.
- **The model has not been trained or tested on Rwandan market photos yet.** The Kimironko photos still need labelling; accuracy in Nyabihu and Rusizi must be measured in the field study.

**Next step:** label the Kimironko photos, upload them with the [training portal](#training-portal-add-photos-and-retrain), then fine-tune and re-test on them.

### Project notebook

[**`training/notebooks/HarvestShelf_AI.ipynb`**](training/notebooks/HarvestShelf_AI.ipynb) covers the whole project in one place:

- the problem and the system design
- the data and how it is cleaned and split
- training and the comparison of all candidate models
- results: metrics, confusion matrices, training curves and example predictions
- a live run of the model that is in the app
- on-device results, limitations, and how to reproduce everything

It is saved with its outputs, so you can **read it without running anything**. It documents the first model (AgriFreshNET only) and the comparison of model types; the current model's results are in [Current status](#current-status) and in `training/sandbox/large/work/experiments/large_efficientnet_lite0/`. To run it again:

```bash
cd training && .venv/bin/jupyter lab notebooks/HarvestShelf_AI.ipynb   # kernel: "HarvestShelf (training/.venv)"
```

### Training portal: add photos and retrain

A local web page for adding labelled photos and training new models, with no command line needed.

```bash
cd training && .venv/bin/python -m portal      # or: make portal PY=.venv/bin/python
```

Then open **http://127.0.0.1:8765**. The portal runs on your computer only.

| Tab | What you can do |
|---|---|
| **Upload** | Drop in photos and choose the crop (tomato, green banana or other), the label, market, date and batch. Files are saved to `data/raw/<date>_<market>/`, with one row each in `data/metadata.csv`. |
| **Photos** | See how many photos each label has against the 300-per-label target. Add a second person's label for the agreement check, filter, and delete photos. |
| **Train** | Pick a model and the number of epochs, then start a run and follow the live log. Each run shows its test results. **Install in app** copies the model into `app/assets/model`; rebuild the app to use it. |

> **Tip:** keep **Include public photos** ticked until you have photos from many separate batches. Training needs whole batches it can set aside for testing.
> Upload *Other produce* photos too, labelled **Unusable**. They teach the model to answer Uncertain for crops it does not support.

Portal runs are saved in `training/sandbox/portal/` (not committed).

### How a scan works

```
photo (camera or gallery, ≤ 1280 px)
  → quality check: brightness 40–235, sharpness ≥ 80      fail → Uncertain (too dark / too bright / blurry)
  → centre square crop, resize to 224×224, RGB 0–255
  → TFLite model on the phone → 9 probabilities
       (tomato × 4 actions, banana × 4 actions, unusable)
  → decision rule:
       top class = unusable                    → Uncertain   (not a tomato/green banana, or unusable photo)
       P(spoilage of that crop) ≥ t_spoil      → Spoilage Risk
       top probability < t_conf                → Uncertain
       otherwise                               → top action
  → advice text from the guidance rules → scan saved on the phone
```

`t_conf` and `t_spoil` are tuned on the validation set (`src.thresholds`); `t_spoil` is the main lever for reaching spoilage recall ≥ 0.85. Both values ship in `model_meta.json`, so retraining never needs app code changes.

### App features

#### Languages

English and **Kinyarwanda**. Switch on the Welcome screen or in Profile → Language; the choice is remembered on the phone. All text is in [`app/lib/l10n/app_text.dart`](app/lib/l10n/app_text.dart), with both languages side by side.

> **Note:** the Kinyarwanda text must be reviewed by a native speaker before the field study. Android's own system buttons stay in English, because Flutter has no built-in Kinyarwanda translations for them.

#### Accounts (offline)

Accounts are stored only on the phone (SQLite), so the app still needs no internet.

- **Register and log in** with a name, a username and a 4–6 digit PIN. Obvious PINs (`1234`, `0000`, …) are refused.
- **PINs are never stored in plain text.** They are hashed with PBKDF2-HMAC-SHA256 (60,000 iterations, random salt).
- **The first account on a phone becomes the Researcher.** Later sign-ups are Sellers.
- **Researchers** can add users, change roles, reset PINs, delete users (with their scans) and export the test log. The last researcher cannot be removed.
- **Sellers** see only their own scan history.
- **Five wrong PINs** lock the account for 30 seconds. A wrong username and a wrong PIN give the same error.
- **Sessions survive app restarts.** Log out from Profile.
- **The exported CSV** has an anonymous `user_id` number, with no names or usernames.
- **Upgrading the database from v1 to v2** keeps existing scans. They have no owner, so they appear only in the export.

### Targets and where they are measured

| Project target | Where it is measured |
|---|---|
| Action macro-F1 ≥ 0.80, spoilage recall ≥ 0.85 | `src.evaluate --split test` → `test_metrics.json` |
| Inference < 1 s on a 3–4 GB phone | `inference_ms` in the app's exported test log |
| App < 50 MB, model < 10 MB | `build_release.sh`, `export_report.json` |

Requirements FR1–FR6, NFR1, NFR5 and NFR6 are cited in comments next to the code that implements them.

### Logo and font

[`scripts/make_logo.py`](scripts/make_logo.py) draws the icon from basic shapes: a tomato and a hand of green cooking bananas on a market shelf, inside camera scan corners. To regenerate it:

```bash
python scripts/make_logo.py && (cd app && dart run flutter_launcher_icons)
```

The font is **Nunito** (SIL Open Font License, [`app/assets/fonts/OFL.txt`](app/assets/fonts/OFL.txt)), bundled with the app.
