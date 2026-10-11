# Run from training/. RUN=experiments/<run-name> for per-run steps.
PY ?= python
MODELS = efficientnet_lite0 mobilenet_v3_small efficientnet_v2_b0 resnet50
FOLDS = 0 1 2 3 4

.PHONY: test clean-data split cv classical compare final thresholds export demo smoke data-public public portal

test:
	$(PY) -m pytest -q tests

clean-data:
	$(PY) -m src.clean

split:
	$(PY) -m src.split

# Grouped 5-fold CV for every candidate (slow: 20 runs).
cv:
	for m in $(MODELS); do for f in $(FOLDS); do $(PY) -m src.train --model $$m --fold $$f || exit 1; done; done

classical:
	$(PY) -m src.classical

compare:
	$(PY) -m src.compare

# Final model: make final MODEL=efficientnet_lite0
final:
	$(PY) -m src.train --model $(MODEL)

thresholds:
	$(PY) -m src.thresholds --run $(RUN)

export:
	$(PY) -m src.export_tflite --run $(RUN)

demo:
	$(PY) -m src.export_tflite --demo

# End-to-end check on generated images (no real data needed).
smoke:
	$(PY) -m tools.smoke_test

# Public AgriFreshNET data and the interim model (see the notebook).
data-public:
	$(PY) -m tools.download_agrifreshnet

public: data-public
	$(PY) -m tools.public_experiment --source "sandbox/public/extracted/Processed Data" \
	    --models efficientnet_lite0 mobilenet_v3_small efficientnet_v2_b0 resnet50 --classical \
	    --install-in-app --no-install mobilenet

# Browser portal to upload labelled photos and train: http://127.0.0.1:8765
portal:
	$(PY) -m portal
