from __future__ import annotations

from conftest import make_image_bytes


def _predict(client, headers, color=(200, 30, 40)):
    r = client.post("/api/predict", files={"file": ("g.jpg", make_image_bytes(color), "image/jpeg")}, headers=headers)
    assert r.status_code == 201
    return r.json()


def test_save_list_and_delete_my_finds(client, auth_headers):
    pred = _predict(client, auth_headers)
    r = client.post("/api/saved", json={"prediction_id": pred["id"], "note": "From the beach"}, headers=auth_headers)
    assert r.status_code == 201
    saved = r.json()
    assert saved["prediction"]["id"] == pred["id"] and saved["note"] == "From the beach"
    assert saved["prediction"]["is_saved"] is True
    # idempotent
    again = client.post("/api/saved", json={"prediction_id": pred["id"]}, headers=auth_headers)
    assert again.status_code == 200 and again.json()["id"] == saved["id"]

    listing = client.get("/api/saved", headers=auth_headers).json()
    assert listing["total"] == 1
    assert client.get("/api/saved?q=garnet", headers=auth_headers).json()["total"] == 1
    assert client.get("/api/saved?q=lapis", headers=auth_headers).json()["total"] == 0
    assert client.get(f"/api/predictions/{pred['id']}", headers=auth_headers).json()["is_saved"] is True

    assert client.delete(f"/api/saved/{saved['id']}", headers=auth_headers).status_code == 200
    assert client.get("/api/saved", headers=auth_headers).json()["total"] == 0


def test_favorites_add_toggle_remove(client, auth_headers):
    gems = client.get("/api/gemstones?page_size=50").json()["items"]
    gem = next(g for g in gems if g["slug"] == "obsidian")
    r = client.post("/api/favorites", json={"gemstone_id": gem["id"]}, headers=auth_headers)
    assert r.status_code == 201
    fav = r.json()
    assert client.post("/api/favorites", json={"gemstone_id": gem["id"]}, headers=auth_headers).status_code == 200
    detail = client.get(f"/api/gemstones/{gem['id']}", headers=auth_headers).json()
    assert detail["is_favorite"] is True
    assert client.get("/api/favorites", headers=auth_headers).json()["total"] == 1
    # remove by gemstone id (toggle use-case)
    assert client.delete(f"/api/favorites/{gem['id']}", headers=auth_headers).status_code == 200
    assert client.get("/api/favorites", headers=auth_headers).json()["total"] == 0
    assert client.delete(f"/api/favorites/{fav['id']}", headers=auth_headers).status_code == 404


def test_favorite_unknown_gemstone(client, auth_headers):
    r = client.post("/api/favorites", json={"gemstone_id": "00000000-0000-0000-0000-000000000000"}, headers=auth_headers)
    assert r.status_code == 404


def test_saved_and_favorites_persist_across_sessions(client, register):
    data, headers = register(email="persist@example.com", password="Persist123")
    pred = _predict(client, headers)
    client.post("/api/saved", json={"prediction_id": pred["id"]}, headers=headers)
    client.post("/api/favorites", json={"gemstone_id": pred["gemstone"]["id"]}, headers=headers)
    client.post("/api/auth/logout", json={"refresh_token": data["refresh_token"]}, headers=headers)

    login = client.post("/api/auth/login", json={"email": "persist@example.com", "password": "Persist123"}).json()
    h2 = {"Authorization": f"Bearer {login['access_token']}"}
    assert client.get("/api/saved", headers=h2).json()["total"] == 1
    assert client.get("/api/favorites", headers=h2).json()["total"] == 1
    assert client.get("/api/predictions", headers=h2).json()["total"] == 1
