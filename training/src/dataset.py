"""tf.data pipelines. Images are fed as RGB floats in 0-255; each model
rescales internally, so the app always sends the same input."""

from __future__ import annotations

import pandas as pd
import tensorflow as tf

from .config import Config


def load_split(cfg: Config, name: str) -> pd.DataFrame:
    return pd.read_csv(cfg.path_of("splits_dir") / f"{name}.csv")


def train_val_frames(cfg: Config, fold: int | None) -> tuple[pd.DataFrame, pd.DataFrame]:
    """fold=None: train.csv vs val.csv. fold=k: grouped CV fold k of train+val."""
    train, val = load_split(cfg, "train"), load_split(cfg, "val")
    if fold is None:
        return train, val
    tv = pd.concat([train, val], ignore_index=True)
    if fold not in set(tv.fold):
        raise ValueError(f"fold {fold} not found; available {sorted(set(tv.fold))}")
    return tv[tv.fold != fold].reset_index(drop=True), tv[tv.fold == fold].reset_index(drop=True)


def _center_square(img: tf.Tensor) -> tf.Tensor:
    h, w = tf.shape(img)[0], tf.shape(img)[1]
    s = tf.minimum(h, w)
    return tf.image.crop_to_bounding_box(img, (h - s) // 2, (w - s) // 2, s, s)


def _random_square(img: tf.Tensor) -> tf.Tensor:
    h, w = tf.shape(img)[0], tf.shape(img)[1]
    side = tf.cast(tf.minimum(h, w), tf.float32)
    size = tf.cast(side * tf.random.uniform([], 0.75, 1.0), tf.int32)
    return tf.image.random_crop(img, tf.stack([size, size, 3]))


def preprocess(img: tf.Tensor, image_size: int, training: bool) -> tf.Tensor:
    """Eval path matches the app: centre square crop, then resize."""
    img = tf.cast(img, tf.float32)
    if training:
        img = _random_square(img)
    else:
        img = _center_square(img)
    img = tf.image.resize(img, [image_size, image_size], method="bilinear", antialias=True)
    if training:
        img = tf.image.random_flip_left_right(img)
        img = tf.image.rot90(img, k=tf.random.uniform([], 0, 4, dtype=tf.int32))
        img = tf.image.random_brightness(img, 0.15 * 255)
        img = tf.image.random_contrast(img, 0.8, 1.2)
        img = tf.clip_by_value(img, 0.0, 255.0)
    return img


def make_dataset(df: pd.DataFrame, cfg: Config, training: bool, batch_size: int | None = None, seed: int = 0) -> tf.data.Dataset:
    base = cfg.path_of("processed_dir")
    paths = [str(base / p) for p in df.path]
    index = {c: i for i, c in enumerate(cfg.class_ids)}
    y = [index[c] for c in df.class_id]
    size = cfg["image_size"]

    def load(path, label):
        img = tf.io.decode_jpeg(tf.io.read_file(path), channels=3)
        return preprocess(img, size, training), label

    ds = tf.data.Dataset.from_tensor_slices((paths, y))
    if training:
        ds = ds.shuffle(len(paths), seed=seed, reshuffle_each_iteration=True)
    ds = ds.map(load, num_parallel_calls=tf.data.AUTOTUNE)
    return ds.batch(batch_size or cfg["train"]["batch_size"]).prefetch(tf.data.AUTOTUNE)
