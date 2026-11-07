from __future__ import annotations

import io

from PIL import Image

from conftest import UnloadedClassifier, make_image_bytes


def _upload(client, headers=None, data=None, name="gem.jpg", ctype="image/jpeg"):
    return client.post("/api/predict", files={"file": (name, data if data is not None else make_image_bytes(), ctype)},
                       headers=headers or {})


def test_predict_stores_history_for_user(client, auth_headers, fake_classifier):
    r = _upload(client, auth_headers)
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["id"] and body["stored"] is True
    assert body["predicted_class"] == "Garnet" and body["display_name"] == "Garnet"
    assert body["is_uncertain"] is False and body["uncertainty_message"] is None
    assert len(body["top_predictions"]) == 3
    assert body["gemstone"]["name"] == "Garnet" and body["gemstone"]["hardness_label"] == "6.5–7.5"
    assert body["model_version"] == "test-double"
    assert fake_classifier.calls == 1

    listed = client.get("/api/predictions", headers=auth_headers).json()
    assert listed["total"] == 1 and listed["items"][0]["id"] == body["id"]
    one = client.get(f"/api/predictions/{body['id']}", headers=auth_headers)
    assert one.status_code == 200
    img = client.get(body["image_url"], headers=auth_headers)
    assert img.status_code == 200 and img.headers["content-type"] == "image/jpeg"


def test_low_confidence_is_reported_as_uncertain(client, auth_headers):
    r = _upload(client, auth_headers, make_image_bytes((250, 200, 210)))
    body = r.json()
    assert body["is_uncertain"] is True
    assert body["uncertainty_message"].startswith("Uncertain identification")
    assert body["confidence"] < body["threshold"]


def test_unlike_training_data_is_uncertain_even_with_high_confidence(client, auth_headers):
    body = _upload(client, auth_headers, make_image_bytes((128, 128, 128), fmt="PNG"), "grey.png", "image/png").json()
    assert body["is_uncertain"] is True and body["uncertainty_reason"] == "unlike_training_data"
    assert body["confidence"] > body["threshold"]
    assert "does not look like" in body["uncertainty_message"]
    stored = client.get(f"/api/predictions/{body['id']}", headers=auth_headers).json()
    assert stored["uncertainty_reason"] == "unlike_training_data" and stored["similarity"] == 0.21


def test_anonymous_prediction_is_not_stored(client):
    r = _upload(client, None, make_image_bytes((20, 40, 220)))
    assert r.status_code == 201
    body = r.json()
    assert body["id"] is None and body["stored"] is False and body["predicted_class"] == "Lapis_Lazuli"


def test_rejects_non_image_and_unsupported_types(client, auth_headers):
    assert _upload(client, auth_headers, b"this is not an image", "x.jpg").status_code == 400
    assert _upload(client, auth_headers, b"GIF89a....", "x.gif", "image/gif").status_code == 415
    buf = io.BytesIO()
    Image.new("RGB", (300, 300)).save(buf, "GIF")
    assert _upload(client, auth_headers, buf.getvalue(), "x.gif", "image/octet-stream").status_code in (400, 415)
    assert _upload(client, auth_headers, b"", "empty.jpg").status_code == 400


def test_rejects_truncated_image(client, auth_headers):
    data = make_image_bytes(size=(600, 600))
    assert _upload(client, auth_headers, data[: len(data) // 2]).status_code == 400


def test_rejects_tiny_and_oversized_images(client, auth_headers):
    assert _upload(client, auth_headers, make_image_bytes(size=(20, 20))).status_code == 400
    big = b"\xff\xd8" + b"0" * (3 * 1024 * 1024)  # > MAX_UPLOAD_MB=2 in tests
    assert _upload(client, auth_headers, big).status_code == 413


def test_decompression_bomb_is_rejected(client, auth_headers):
    # 10000x10000 PNG of a single colour compresses to a few KB but would decode to 300 MB.
    buf = io.BytesIO()
    Image.new("L", (10000, 10000)).save(buf, "PNG", optimize=True)
    r = _upload(client, auth_headers, buf.getvalue(), "bomb.png", "image/png")
    assert r.status_code == 413
    assert r.json()["error"]["code"] == "image_too_large"


def test_predict_returns_503_when_model_not_loaded(client, auth_headers):
    from app.main import app
    from app.ml.classifier import get_classifier

    app.dependency_overrides[get_classifier] = lambda: UnloadedClassifier()
    r = _upload(client, auth_headers)
    assert r.status_code == 503 and r.json()["error"]["code"] == "model_unavailable"
    status = client.get("/api/model/status").json()
    assert status["loaded"] is False and status["error"]


def test_delete_prediction(client, auth_headers):
    pid = _upload(client, auth_headers).json()["id"]
    assert client.delete(f"/api/predictions/{pid}", headers=auth_headers).status_code == 200
    assert client.get(f"/api/predictions/{pid}", headers=auth_headers).status_code == 404


def test_predictions_pagination(client, auth_headers):
    for _ in range(5):
        _upload(client, auth_headers)
    p1 = client.get("/api/predictions?page=1&page_size=2", headers=auth_headers).json()
    assert p1["total"] == 5 and len(p1["items"]) == 2 and p1["has_more"] is True
    p3 = client.get("/api/predictions?page=3&page_size=2", headers=auth_headers).json()
    assert len(p3["items"]) == 1 and p3["has_more"] is False
