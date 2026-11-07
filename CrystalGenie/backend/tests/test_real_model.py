"""Integration tests with the REAL trained model (skipped if TensorFlow or the model is missing)."""
from __future__ import annotations

import csv
import io
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
MODEL = ROOT / "models" / "gemstone_model.keras"
TEST_SPLIT = ROOT / "ml_training" / "data" / "splits" / "test.csv"
PROCESSED = ROOT / "ml_training" / "data" / "processed"

tf = pytest.importorskip("tensorflow")
pytestmark = pytest.mark.skipif(not MODEL.exists(), reason="trained model not found in models/")


@pytest.fixture(scope="module")
def real_classifier():
    from app.ml.classifier import KerasGemClassifier

    clf = KerasGemClassifier(ROOT / "models")
    clf.load()
    assert clf.loaded, clf.error
    return clf


def test_real_model_loads_with_13_classes(real_classifier):
    assert len(real_classifier.class_names) == 13
    assert 0.5 <= real_classifier.threshold < 1.0


@pytest.mark.skipif(not TEST_SPLIT.exists(), reason="test split not available")
def test_real_model_accuracy_on_held_out_sample(real_classifier):
    from PIL import Image

    with TEST_SPLIT.open(encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))[::3]  # every 3rd held-out image
    correct = 0
    for r in rows:
        res = real_classifier.predict(Image.open(PROCESSED / r["file"]))
        correct += res.best.class_name == r["label"]
    acc = correct / len(rows)
    assert acc > 0.6, f"held-out accuracy unexpectedly low: {acc:.2f}"


def test_real_model_through_api(client, auth_headers, real_classifier):
    from app.main import app
    from app.ml.classifier import get_classifier

    app.dependency_overrides[get_classifier] = lambda: real_classifier
    img = next(PROCESSED.glob("Lapis_Lazuli/*.jpg"), None)
    if img is None:
        pytest.skip("processed images not available")
    r = client.post("/api/predict", files={"file": (img.name, img.read_bytes(), "image/jpeg")}, headers=auth_headers)
    assert r.status_code == 201
    body = r.json()
    assert body["model_version"].startswith("cg-effv2b0-")
    assert abs(sum(t["confidence"] for t in body["top_predictions"])) <= 1.0001


def test_real_model_flags_noise_as_uncertain(real_classifier):
    import numpy as np
    from PIL import Image

    noise = Image.fromarray(np.random.default_rng(0).integers(0, 256, (300, 300, 3), dtype=np.uint8))
    res = real_classifier.predict(noise)
    print("noise ->", res.best.class_name, round(res.best.confidence, 3), "similarity:", res.similarity,
          "uncertain:", res.is_uncertain, res.uncertainty_reason)
    assert 0 <= res.best.confidence <= 1
    if real_classifier.similarity_threshold is not None:
        # With the feature-similarity guard (evaluate.py writes class_centroids.npy) noise must be rejected.
        assert res.is_uncertain
    _ = io
