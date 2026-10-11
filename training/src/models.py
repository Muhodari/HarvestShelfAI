"""Candidate CNNs. Every model takes RGB 0-255 and does its own rescaling,
so the phone always sends the same input whichever model wins."""

from __future__ import annotations

import json
from pathlib import Path

import tensorflow as tf

HUB_EFFICIENTNET_LITE0 = "https://tfhub.dev/tensorflow/efficientnet/lite0/feature-vector/2"

ARCHITECTURES = {
    "efficientnet_lite0": "main candidate (TF Hub, ImageNet weights)",
    "mobilenet_v3_small": "lightweight baseline",
    "efficientnet_v2_b0": "modern efficient alternative (replaces MobileNetV2 from the proposal)",
    "resnet50": "accuracy reference (too large for low-cost phones)",
    "demo": "UNTRAINED placeholder for app integration only",
}

L = tf.keras.layers


def _hub_layer_class():
    """hub.KerasLayer cannot fine-tune TF1-format Hub models such as
    EfficientNet-Lite0. This subclass registers the module's variables
    itself (the approach used by TFLite Model Maker), so the backbone can
    be frozen for stage 1 and unfrozen for stage 2."""
    import tensorflow_hub as hub

    class HubKerasLayerV1V2(hub.KerasLayer):
        def _setup_layer(self, trainable=False, **kwargs):
            if not self._is_hub_module_v1:
                return super()._setup_layer(trainable, **kwargs)
            super(hub.KerasLayer, self).__init__(trainable=trainable, **kwargs)
            seen = set()
            for dep in self._func._self_unconditional_checkpoint_dependencies:
                if dep.name == "variables":
                    for v in dep.ref:
                        if id(v) not in seen:
                            self._add_existing_weight(v, trainable=True)
                            seen.add(id(v))
            for v in getattr(self._func, "variables", []):
                if id(v) not in seen:
                    self._add_existing_weight(v, trainable=False)
                    seen.add(id(v))

        def _check_trainability(self):
            if self._is_hub_module_v1:
                return
            super()._check_trainability()

    return HubKerasLayerV1V2


def build(arch: str, num_classes: int, image_size: int, dropout: float) -> tuple[tf.keras.Model, tf.keras.layers.Layer]:
    """Returns (model, base). `base` is frozen; unfreeze it for fine-tuning."""
    shape = (image_size, image_size, 3)
    inp = tf.keras.Input(shape, name="image")  # RGB, 0-255

    if arch == "efficientnet_lite0":
        x = L.Rescaling(1 / 255.0)(inp)  # hub model expects [0, 1]
        # Built trainable so its variables are registered, then frozen.
        base = _hub_layer_class()(HUB_EFFICIENTNET_LITE0, trainable=True, name="efficientnet_lite0")
        base.trainable = False
        feats = base(x)
    elif arch == "mobilenet_v3_small":
        base = tf.keras.applications.MobileNetV3Small(
            input_shape=shape, include_top=False, weights="imagenet", pooling="avg", include_preprocessing=True
        )
        base.trainable = False
        feats = base(inp, training=False)
    elif arch == "efficientnet_v2_b0":
        base = tf.keras.applications.EfficientNetV2B0(
            input_shape=shape, include_top=False, weights="imagenet", pooling="avg", include_preprocessing=True
        )  # takes RGB 0-255 like the others
        base.trainable = False
        feats = base(inp, training=False)
    elif arch == "resnet50":
        x = L.Lambda(tf.keras.applications.resnet50.preprocess_input, name="resnet_preprocess")(inp)
        base = tf.keras.applications.ResNet50(input_shape=shape, include_top=False, weights="imagenet", pooling="avg")
        base.trainable = False
        feats = base(x, training=False)
    elif arch == "demo":
        base = tf.keras.applications.MobileNetV3Small(
            input_shape=shape, include_top=False, weights=None, pooling="avg", include_preprocessing=True,
            minimalistic=True,
        )
        feats = base(inp)
    else:
        raise ValueError(f"unknown architecture {arch!r}; choose from {list(ARCHITECTURES)}")

    x = L.Dropout(dropout)(feats)
    out = L.Dense(num_classes, activation="softmax", name="probs")(x)
    return tf.keras.Model(inp, out, name=arch), base


def save_run_model(model: tf.keras.Model, run_dir: Path) -> None:
    model.save(run_dir / "model")  # TF SavedModel directory


def load_run_model(run_dir: Path) -> tf.keras.Model:
    arch = json.loads((run_dir / "run.json").read_text())["arch"]
    custom = {}
    if arch == "efficientnet_lite0":
        custom["HubKerasLayerV1V2"] = _hub_layer_class()
    return tf.keras.models.load_model(run_dir / "model", custom_objects=custom, compile=False)
