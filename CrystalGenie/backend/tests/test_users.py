from __future__ import annotations

from conftest import make_image_bytes


def test_get_and_update_profile(client, auth_headers):
    me = client.get("/api/users/me", headers=auth_headers).json()
    assert me["full_name"] == "Jon Doe" and me["avatar_url"] is None
    r = client.patch("/api/users/me", json={"full_name": "  Jonathan   Doe "}, headers=auth_headers)
    assert r.status_code == 200 and r.json()["full_name"] == "Jonathan Doe"
    r = client.patch("/api/users/me", json={"full_name": "X"}, headers=auth_headers)
    assert r.status_code == 422


def test_email_change_conflict(client, register):
    register(email="taken@example.com")
    _, headers = register(email="me@example.com")
    r = client.patch("/api/users/me", json={"email": "TAKEN@example.com"}, headers=headers)
    assert r.status_code == 409


def test_avatar_upload_and_fetch(client, auth_headers):
    r = client.post("/api/users/avatar", files={"file": ("me.png", make_image_bytes((10, 120, 200), (400, 300), "PNG"), "image/png")},
                    headers=auth_headers)
    assert r.status_code == 200, r.text
    url = r.json()["avatar_url"]
    assert url.startswith("/api/users/me/avatar")
    img = client.get(url, headers=auth_headers)
    assert img.status_code == 200 and img.headers["content-type"] == "image/jpeg"
    assert client.get(url).status_code == 401


def test_avatar_rejects_non_image(client, auth_headers):
    r = client.post("/api/users/avatar", files={"file": ("x.txt", b"hello world", "text/plain")}, headers=auth_headers)
    assert r.status_code == 415


def test_settings_defaults_and_update(client, auth_headers):
    s = client.get("/api/users/settings", headers=auth_headers).json()
    assert s["notifications_enabled"] is True and s["language"] == "en"
    r = client.patch("/api/users/settings", json={"notifications_enabled": False, "language": "ta"}, headers=auth_headers)
    assert r.status_code == 200
    assert r.json()["notifications_enabled"] is False and r.json()["language"] == "ta"
    assert client.patch("/api/users/settings", json={"language": "xx"}, headers=auth_headers).status_code == 422


def test_delete_account_requires_password_and_cascades(client, register, engine):
    data, headers = register(email="del@example.com", password="DelPass123")
    pred = client.post("/api/predict", files={"file": ("g.jpg", make_image_bytes(), "image/jpeg")}, headers=headers).json()
    client.post("/api/saved", json={"prediction_id": pred["id"]}, headers=headers)
    gem_id = pred["gemstone"]["id"]
    client.post("/api/favorites", json={"gemstone_id": gem_id}, headers=headers)

    bad = client.request("DELETE", "/api/users/me", json={"password": "wrong", "confirm": "DELETE"}, headers=headers)
    assert bad.status_code == 400
    no_confirm = client.request("DELETE", "/api/users/me", json={"password": "DelPass123", "confirm": "yes"}, headers=headers)
    assert no_confirm.status_code == 422
    ok = client.request("DELETE", "/api/users/me", json={"password": "DelPass123", "confirm": "DELETE"}, headers=headers)
    assert ok.status_code == 200
    assert client.get("/api/users/me", headers=headers).status_code == 401
    assert client.post("/api/auth/login", json={"email": "del@example.com", "password": "DelPass123"}).status_code == 401
    from sqlalchemy import text

    with engine.connect() as c:
        for table in ("predictions", "saved_crystals", "favorites", "refresh_tokens", "user_settings"):
            assert c.execute(text(f"SELECT COUNT(*) FROM {table}")).scalar_one() == 0, table
        assert c.execute(text("SELECT COUNT(*) FROM gemstones")).scalar_one() == 13
