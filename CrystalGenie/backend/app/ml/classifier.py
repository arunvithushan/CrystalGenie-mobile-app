"""Gemstone classifier service: loads the trained Keras model once and runs real inference.

There is deliberately NO fallback that invents predictions: if the model files are missing
or TensorFlow is not installed, the classifier reports `loaded=False` and /api/predict
returns HTTP 503.
"""
from __future__ import annotations

import json
import logging
import os
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol

import numpy as np
from PIL import Image

from app.ml.preprocessing import center_square, downscale_short_side

log = logging.getLogger("app.ml")
IMG_SIZE = 224


@dataclass
class ClassScore:
    class_name: str
    confidence: float


@dataclass
class ClassifierResult:
    top: list[ClassScore]
    is_uncertain: bool
    threshold: float
    model_version: str
    latency_ms: float
    raw_top1: float = 0.0
    similarity: float | None = None
    uncertainty_reason: str | None = None  # "low_confidence" | "unlike_training_data"
    extra: dict = field(default_factory=dict)

    @property
    def best(self) -> ClassScore:
        return self.top[0]


class Classifier(Protocol):
    loaded: bool
    error: str | None
    class_names: list[str]
    model_version: str | None
    threshold: float
    temperature: float
    metadata: dict

    def predict(self, image: Image.Image, top_k: int = 3) -> ClassifierResult: ...


def calibrate(probs: np.ndarray, temperature: float) -> np.ndarray:
    logits = np.log(np.clip(probs.astype(np.float64), 1e-12, 1.0)) / max(temperature, 1e-3)
    logits -= logits.max()
    e = np.exp(logits)
    return e / e.sum()


class KerasGemClassifier:
    """Wraps gemstone_model.keras + class_names.json + model_metadata.json."""

    def __init__(self, model_dir: Path, model_file: str = "gemstone_model.keras", threshold_override: float | None = None):
        self.model_dir = Path(model_dir)
        self.model_file = model_file
        self.threshold_override = threshold_override
        self.loaded = False
        self.error: str | None = None
        self.class_names: list[str] = []
        self.model_version: str | None = None
        self.threshold = 0.5
        self.temperature = 1.0
        self.metadata: dict = {}
        self._model = None
        self._dual = None  # same model with an extra output: the pooled embedding (OOD guard)
        self._centroids: np.ndarray | None = None
        self.similarity_threshold: float | None = None
        self._tf = None
        self._lock = threading.Lock()

    def load(self) -> None:
        model_path = self.model_dir / self.model_file
        meta_path = self.model_dir / "model_metadata.json"
        names_path = self.model_dir / "class_names.json"
        try:
            if not model_path.exists():
                raise FileNotFoundError(f"model file not found: {model_path}")
            os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
            import tensorflow as tf  # heavy import, only when a model exists

            self._tf = tf
            t0 = time.perf_counter()
            self._model = tf.keras.models.load_model(model_path, compile=False)
            self.metadata = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else {}
            if names_path.exists():
                self.class_names = json.loads(names_path.read_text(encoding="utf-8"))
            else:
                self.class_names = list(self.metadata.get("class_names", []))
            n_out = int(self._model.outputs[0].shape[-1])
            if n_out != len(self.class_names):
                raise ValueError(f"model has {n_out} outputs but {len(self.class_names)} class names")
            cal = self.metadata.get("calibration", {})
            self.temperature = float(cal.get("temperature", 1.0))
            self.threshold = float(self.threshold_override if self.threshold_override is not None
                                   else cal.get("confidence_threshold", 0.5))
            self.model_version = self.metadata.get("model_version") or model_path.stem
            ood = self.metadata.get("ood_guard") or {}
            cpath = self.model_dir / ood.get("centroids_file", "class_centroids.npy")
            if ood.get("similarity_threshold") is not None and cpath.exists():
                try:
                    self._dual = tf.keras.Model(self._model.inputs,
                                                [self._model.get_layer(ood.get("embedding_layer", "avg_pool")).output,
                                                 self._model.outputs[0]])
                    self._centroids = np.load(cpath).astype(np.float32)
                    self.similarity_threshold = float(ood["similarity_threshold"])
                except Exception as exc:  # noqa: BLE001 - guard is optional
                    log.warning("OOD guard disabled: %s", exc)
                    self._dual, self._centroids, self.similarity_threshold = None, None, None
            # warm-up so the first user request is not slow
            self._model(np.zeros((1, IMG_SIZE, IMG_SIZE, 3), np.float32), training=False)
            self.loaded, self.error = True, None
            log.info("model loaded: %s (%d classes) in %.1fs", self.model_version, len(self.class_names), time.perf_counter() - t0)
        except Exception as exc:  # noqa: BLE001
            self.loaded, self.error = False, f"{type(exc).__name__}: {exc}"
            log.error("model not loaded: %s", self.error)

    def preprocess(self, image: Image.Image) -> np.ndarray:
        tf = self._tf
        arr = center_square(np.asarray(downscale_short_side(image.convert("RGB"))))
        x = tf.image.resize(tf.convert_to_tensor(arr, tf.float32), (IMG_SIZE, IMG_SIZE), method="bilinear", antialias=True)
        return tf.clip_by_value(x, 0.0, 255.0).numpy()[None, ...]

    def predict(self, image: Image.Image, top_k: int = 3) -> ClassifierResult:
        if not self.loaded:
            raise RuntimeError(self.error or "model not loaded")
        t0 = time.perf_counter()
        x = self.preprocess(image)
        similarity = None
        with self._lock:
            if self._dual is not None and self._centroids is not None:
                emb, out = self._dual(x, training=False)
                raw = out.numpy()[0]
                e = emb.numpy()[0].astype(np.float32)
                e = e / max(float(np.linalg.norm(e)), 1e-12)
                similarity = float((self._centroids @ e).max())
            else:
                raw = self._model(x, training=False).numpy()[0]
        probs = calibrate(raw, self.temperature)
        order = np.argsort(-probs)[: max(1, top_k)]
        top = [ClassScore(self.class_names[i], float(probs[i])) for i in order]
        latency = (time.perf_counter() - t0) * 1000
        reason = None
        if top[0].confidence < self.threshold:
            reason = "low_confidence"
        elif similarity is not None and self.similarity_threshold is not None and similarity < self.similarity_threshold:
            reason = "unlike_training_data"
        return ClassifierResult(
            top=top,
            is_uncertain=reason is not None,
            threshold=self.threshold,
            model_version=self.model_version or "unknown",
            latency_ms=round(latency, 1),
            raw_top1=float(raw[order[0]]),
            similarity=similarity,
            uncertainty_reason=reason,
        )


_classifier: Classifier | None = None


def get_classifier() -> Classifier:
    global _classifier
    if _classifier is None:
        from app.core.config import get_settings

        s = get_settings()
        clf = KerasGemClassifier(s.model_dir, s.model_file, s.threshold_override)
        clf.load()
        _classifier = clf
    return _classifier


def set_classifier(clf: Classifier | None) -> None:
    """Replace the global classifier (used by tests and for hot-reload)."""
    global _classifier
    _classifier = clf
