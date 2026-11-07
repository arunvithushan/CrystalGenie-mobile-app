"""Shared constants and helpers for the Crystal Genie training pipeline.

The SAME preprocessing is implemented in backend/app/ml/preprocessing.py so that
inference in the API matches evaluation exactly:

  1. Decode with Pillow, apply EXIF orientation, convert to RGB.
  2. Downscale so the short side is at most PREPROCESS_SHORT_SIDE (Lanczos).
     (preprocess.py stores the dataset at this size.)
  3. Centre-crop the largest square and resize to IMG_SIZE x IMG_SIZE
     (bilinear + antialias, TensorFlow).
  4. Feed raw 0..255 float32 pixels: EfficientNetV2 has its ImageNet
     normalisation built in (include_preprocessing=True).
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

IMG_SIZE = 224
PREPROCESS_SHORT_SIDE = 512
SEED = 42
Image.MAX_IMAGE_PIXELS = 80_000_000

ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent
DEFAULT_DATA_DIR = Path(os.environ.get("CG_DATA_DIR", r"C:\Users\ASUS\Desktop\arun\images\a"))
PROCESSED_DIR = ROOT / "data" / "processed"
SPLITS_DIR = ROOT / "data" / "splits"
REPORTS_DIR = ROOT / "reports"
MODELS_DIR = PROJECT_ROOT / "models"
CHECKPOINT_DIR = ROOT / "checkpoints"


def load_rgb(path: str | Path, max_short_side: int | None = PREPROCESS_SHORT_SIDE) -> Image.Image:
    """Open any Pillow-readable image as an orientation-corrected RGB image."""
    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im)
        if im.mode in ("RGBA", "LA", "P"):
            # Composite transparency on white (product photos usually have white backgrounds)
            im = im.convert("RGBA")
            bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
            bg.alpha_composite(im)
            im = bg
        im = im.convert("RGB")
        if max_short_side:
            w, h = im.size
            s = min(w, h)
            if s > max_short_side:
                scale = max_short_side / s
                im = im.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.Resampling.LANCZOS)
        return im.copy()


def center_square_np(arr: np.ndarray) -> np.ndarray:
    h, w = arr.shape[:2]
    s = min(h, w)
    top, left = (h - s) // 2, (w - s) // 2
    return arr[top : top + s, left : left + s]


def read_json(path: Path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path: Path, data) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(data, indent=2), encoding="utf-8")


def configure_tensorflow(seed: int = SEED, mixed_precision: str = "auto"):
    """Import TF, enable GPU memory growth and (optionally) mixed precision.

    Returns (tf, using_gpu, mixed_precision_enabled).
    """
    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    import tensorflow as tf  # noqa: WPS433 - heavy import kept local

    gpus = tf.config.list_physical_devices("GPU")
    for gpu in gpus:
        try:
            tf.config.experimental.set_memory_growth(gpu, True)
        except RuntimeError:
            pass
    tf.keras.utils.set_random_seed(seed)
    use_mp = (mixed_precision == "on") or (mixed_precision == "auto" and bool(gpus))
    if use_mp:
        tf.keras.mixed_precision.set_global_policy("mixed_float16")
    return tf, bool(gpus), use_mp
