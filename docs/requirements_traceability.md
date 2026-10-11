# Requirements traceability

Each requirement from the proposal (Section 3.3) is linked to the code that implements it, the tests that check it, and the evidence. Paths are relative to the repository root. Measured results are in `training/notebooks/HarvestShelf_AI.ipynb`.

Status: ✅ done and verified · 🟡 done, waiting on field data · ⬜ not started

## Functional requirements

| ID | Requirement | Implementation | Tests | Evidence | Status |
|---|---|---|---|---|---|
| FR1 | Capture a photo with the camera or choose one from the gallery | `app/lib/screens/scan_screen.dart` (`image_picker`, max 1280 px, no re-compression) | `app/test/app_navigation_test.dart` (home renders the scan actions) | Emulator: gallery scan and camera scan (notebook §12) | ✅ |
| FR2 | Check image quality; reject photos that are too dark, too bright, blurred or unsupported | `app/lib/services/image_quality_service.dart` (brightness, sharpest-tile sharpness), `unusable` class in the model | `app/test/image_quality_test.dart` (incl. matching Python on `shared/quality_cases.json`), `training/tests/test_quality*.py` | Blur check rejects 0.8% of in-focus photos and catches 91–100% of blurred ones; 100% of other produce rejected on the test set (notebook §5.4, §8) | ✅ |
| FR3 | Run the bundled TFLite model on the phone; return class and confidence | `app/lib/services/classifier_service.dart` (`tflite_flutter`, background isolate), `app/lib/services/preprocessing_service.dart`, `app/lib/services/resize.dart` | `app/integration_test/parity_test.dart` (on device), `app/test/resize_test.dart` (Pillow-exact) | Phone and Python showed the same action on 18/18 photos (notebook §11) | ✅ |
| FR4 | Map the result to Fresh / Sell Soon / Discount Today / Spoilage Risk / Uncertain, with guidance text | `app/lib/services/decision_mapper.dart`, `app/assets/guidance_rules.json`, `app/lib/screens/result_screen.dart` | `app/test/decision_mapper_test.dart` and `training/tests/test_decision.py` (same cases from `shared/decision_cases.json`), `app/test/widget_test.dart` | Notebook §4 shows every decision case passing | ✅ |
| FR5 | Save each scan (crop, action, confidence, time) in SQLite; let the seller view past scans | `app/lib/data/database.dart` (v2 schema), `app/lib/data/repositories.dart`, `app/lib/screens/history_screen.dart` | `app/test/data_test.dart` (per-user history, database upgrade v1→v2) | Screenshots in `docs/screenshots/` | ✅ |
| FR6 | Researcher exports an anonymous test log | `app/lib/services/export_service.dart`, Profile → Export test log (researchers only) | `app/test/data_test.dart` (CSV has no names), `app/test/app_navigation_test.dart` (sellers don't see export) | `evaluation/analysis.py latency` reads the CSV | ✅ |
| FR7 *(new)* | Local accounts: register, log in/out, roles, PIN reset, delete user | `app/lib/services/auth/` (PBKDF2 PINs, lockout), `app/lib/screens/auth/`, `app/lib/screens/manage_users_screen.dart` | `app/test/auth_test.dart`, `app/test/pin_hasher_test.dart` (matches Python), `app/test/app_navigation_test.dart` (full flow) | Notebook §12 | ✅ |

## Non-functional requirements

| ID | Requirement | How it's met | Check | Evidence | Status |
|---|---|---|---|---|---|
| NFR1 | Works offline | No INTERNET permission; model and data are bundled | `scripts/build_release.sh` fails if INTERNET appears | Release manifest permission list | ✅ |
| NFR2 | Inference < 1 s on a 3–4 GB phone | Small TFLite model, background isolate, 4 threads | `parity_test.dart` logs timing; app CSV `inference_ms` | About 110 ms median, 152 ms max on the emulator (notebook §11). Not yet measured on a real 3–4 GB phone. | 🟡 |
| NFR3 | Usability: simple words and colours; SUS ≥ 68 | Clean 3-tab design, one main action per screen, accessible colours, large text | Large-text and landscape layout tests | SUS needs at least 15 sellers (`evaluation/`) | 🟡 |
| NFR4 | App < 50 MB | Split-per-ABI APKs, model under 10 MB | `scripts/build_release.sh` prints sizes | About 13–15 MB APK | ✅ |
| NFR5 | Privacy: no data leaves the phone | No network permission; phone/storage permissions removed; export has no names | `build_release.sh` permission check; CSV test | The app now stores display names and usernames **on the phone** (proposal update needed) | ✅ |
| NFR6 | Reliability: Uncertain instead of a guess | Quality check, `unusable` class, `t_conf` | `decision_mapper_test.dart`, shared cases | Notebook §7–8 | ✅ |

## Objectives and research questions

| Proposal item | Delivered | Where |
|---|---|---|
| Objective 1: labeling guide and requirements | ✅ | `docs/labeling_guide.md`, `docs/data_collection.md`, this file |
| Objective 2: offline prototype with on-device TFLite, decision rules, local history | ✅ | `app/` |
| Objective 3: macro-F1 ≥ 0.80, Spoilage recall ≥ 0.85 | 🟡 Met on public data; Rwandan photos still needed | Notebook §2, §7 |
| Objective 3: SUS ≥ 68, +15 points agreement | 🟡 Protocols and analysis ready | `evaluation/`, notebook §13 |
| RQ1: categories, data and user needs | ✅ | Labeling guide, proposal |
| RQ2: integrating capture, preprocessing, TFLite and SQLite offline | ✅ | App architecture (notebook §4) |
| RQ3: how far the targets are met | 🟡 Public data now; field results pending | Notebook |

## Model comparison (proposal Section 3.4.5)

| Candidate | Status |
|---|---|
Test results on held-out AgriFreshNET capture sessions (public data, not Rwandan markets):

| Candidate | Macro-F1 | Spoilage recall | Phone size | Role |
|---|---|---|---|---|
| **EfficientNet-Lite0** | 0.822 | 0.957 | 3.7 MB | **Installed in the app** |
| MobileNetV3-Small | 0.822 | 0.957 | 1.9 MB | Baseline only; excluded from the app at the project owner's request |
| ~~MobileNetV2~~ → **EfficientNetV2-B0** | 0.829 | 0.971 | 11.8 MB | Replaced at the project owner's request; just over the 10 MB limit |
| ResNet50 | 0.840 | 0.957 | 24.0 MB | Accuracy reference; too large for the phone |
| Random Forest | 0.640 | 0.886 | n/a | Classical baseline |
| SVM | 0.532 | 0.929 | n/a | Classical baseline |

The deep models beat the classical baselines by about 0.2–0.3 macro-F1, which supports the proposal's choice of a CNN. The phone model is chosen by the rule in `training/tools/public_experiment.py`: fits within 10 MB, its TFLite agrees with Keras, then the best macro-F1 among models meeting spoilage recall.
