"""User data isolation: nobody can read or modify another user's data."""
from __future__ import annotations

from conftest import make_image_bytes


def test_users_cannot_access_each_others_data(client, register):
    _, alice = register(email="alice@example.com")
    _, bob = register(email="bob@example.com")

    pred = client.post("/api/predict", files={"file": ("a.jpg", make_image_bytes(), "image/jpeg")}, headers=alice).json()
    saved = client.post("/api/saved", json={"prediction_id": pred["id"]}, headers=alice).json()
    fav = client.post("/api/favorites", json={"gemstone_id": pred["gemstone"]["id"]}, headers=alice).json()

    # Bob sees nothing of Alice's
    assert client.get("/api/predictions", headers=bob).json()["total"] == 0
    assert client.get("/api/saved", headers=bob).json()["total"] == 0
    assert client.get("/api/favorites", headers=bob).json()["total"] == 0
    assert client.get(f"/api/predictions/{pred['id']}", headers=bob).status_code == 404
    assert client.get(f"/api/predictions/{pred['id']}/image", headers=bob).status_code == 404

    # ...and cannot modify it
    assert client.post("/api/saved", json={"prediction_id": pred["id"]}, headers=bob).status_code == 404
    assert client.delete(f"/api/saved/{saved['id']}", headers=bob).status_code == 404
    assert client.delete(f"/api/favorites/{fav['id']}", headers=bob).status_code == 404
    assert client.delete(f"/api/predictions/{pred['id']}", headers=bob).status_code == 404

    # Alice's data is intact
    assert client.get("/api/saved", headers=alice).json()["total"] == 1
    assert client.get("/api/favorites", headers=alice).json()["total"] == 1
    assert client.get(f"/api/predictions/{pred['id']}", headers=alice).status_code == 200

    # Gemstone favourite flags are per-user
    gem = client.get(f"/api/gemstones/{pred['gemstone']['id']}", headers=bob).json()
    assert gem["is_favorite"] is False
