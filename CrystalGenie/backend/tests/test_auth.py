from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt


def test_register_returns_tokens_and_hashes_password(client, engine):
    r = client.post("/api/auth/register", json={"full_name": "Jon Doe", "email": "Jon@Example.com", "password": "CrystalPass1"})
    assert r.status_code == 201
    body = r.json()
    assert body["token_type"] == "bearer"
    assert body["user"]["email"] == "jon@example.com"
    assert body["access_token"] and body["refresh_token"]
    from sqlalchemy import text

    with engine.connect() as c:
        stored = c.execute(text("SELECT password_hash FROM users")).scalar_one()
    assert stored.startswith("$argon2id$")
    assert "CrystalPass1" not in stored


def test_register_validation_errors(client):
    r = client.post("/api/auth/register", json={"full_name": "J", "email": "not-an-email", "password": "short"})
    assert r.status_code == 422
    err = r.json()["error"]
    assert err["code"] == "validation_error"
    fields = {d["field"] for d in err["details"]}
    assert {"full_name", "email", "password"} <= fields


def test_password_needs_letters_and_numbers(client):
    r = client.post("/api/auth/register", json={"full_name": "Jon", "email": "a@example.com", "password": "onlyletters"})
    assert r.status_code == 422


def test_duplicate_email_is_rejected_case_insensitive(client, register):
    register(email="dup@example.com")
    r = client.post("/api/auth/register", json={"full_name": "X Y", "email": "DUP@example.com", "password": "CrystalPass1"})
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "email_taken"


def test_login_success_and_failure(client, register):
    register(email="login@example.com", password="CrystalPass1")
    ok = client.post("/api/auth/login", json={"email": "LOGIN@example.com", "password": "CrystalPass1"})
    assert ok.status_code == 200
    bad = client.post("/api/auth/login", json={"email": "login@example.com", "password": "wrongpass1"})
    assert bad.status_code == 401
    assert bad.json()["error"]["code"] == "invalid_credentials"
    missing = client.post("/api/auth/login", json={"email": "nobody@example.com", "password": "CrystalPass1"})
    assert missing.status_code == 401
    assert missing.json()["error"]["message"] == bad.json()["error"]["message"]  # no account enumeration


def test_protected_route_requires_token(client):
    assert client.get("/api/users/me").status_code == 401
    r = client.get("/api/users/me", headers={"Authorization": "Bearer not-a-jwt"})
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "invalid_token"


def test_expired_and_forged_tokens_are_rejected(client, register):
    data, _ = register()
    secret = "test-secret-" + "x" * 40
    now = datetime.now(timezone.utc)
    expired = jwt.encode({"sub": data["user"]["id"], "type": "access", "tv": 0, "iss": "crystal-genie",
                          "iat": int((now - timedelta(hours=2)).timestamp()), "exp": int((now - timedelta(hours=1)).timestamp())},
                         secret, algorithm="HS256")
    r = client.get("/api/users/me", headers={"Authorization": f"Bearer {expired}"})
    assert r.status_code == 401 and r.json()["error"]["code"] == "token_expired"
    forged = jwt.encode({"sub": data["user"]["id"], "type": "access", "tv": 0, "iss": "crystal-genie",
                         "iat": int(now.timestamp()), "exp": int((now + timedelta(hours=1)).timestamp())},
                        "some-other-secret-value-xxxxxxxxxxxx", algorithm="HS256")
    assert client.get("/api/users/me", headers={"Authorization": f"Bearer {forged}"}).status_code == 401
    wrong_type = jwt.encode({"sub": data["user"]["id"], "type": "refresh", "tv": 0, "iss": "crystal-genie",
                             "iat": int(now.timestamp()), "exp": int((now + timedelta(hours=1)).timestamp())},
                            secret, algorithm="HS256")
    assert client.get("/api/users/me", headers={"Authorization": f"Bearer {wrong_type}"}).status_code == 401


def test_refresh_rotation_and_reuse_detection(client, register):
    data, _ = register()
    r1 = client.post("/api/auth/refresh", json={"refresh_token": data["refresh_token"]})
    assert r1.status_code == 200
    new_refresh = r1.json()["refresh_token"]
    assert new_refresh != data["refresh_token"]
    # Reusing the old (rotated) token is detected and kills the whole family.
    reuse = client.post("/api/auth/refresh", json={"refresh_token": data["refresh_token"]})
    assert reuse.status_code == 401 and reuse.json()["error"]["code"] == "refresh_token_reused"
    after = client.post("/api/auth/refresh", json={"refresh_token": new_refresh})
    assert after.status_code == 401


def test_logout_revokes_refresh_token(client, register):
    data, headers = register()
    r = client.post("/api/auth/logout", json={"refresh_token": data["refresh_token"]}, headers=headers)
    assert r.status_code == 200
    assert client.post("/api/auth/refresh", json={"refresh_token": data["refresh_token"]}).status_code == 401


def test_logout_all_devices_invalidates_access_tokens(client, register):
    data, headers = register()
    client.post("/api/auth/logout", json={"all_devices": True}, headers=headers)
    assert client.get("/api/users/me", headers=headers).status_code == 401


def test_forgot_and_reset_password_flow(client, register):
    register(email="reset@example.com", password="OldPass123")
    r = client.post("/api/auth/forgot-password", json={"email": "reset@example.com"})
    assert r.status_code == 202
    code = r.json()["dev_reset_code"]
    assert code and len(code) == 8
    unknown = client.post("/api/auth/forgot-password", json={"email": "unknown@example.com"})
    assert unknown.status_code == 202 and unknown.json()["dev_reset_code"] is None
    assert unknown.json()["message"] == r.json()["message"]

    bad = client.post("/api/auth/reset-password", json={"email": "reset@example.com", "code": "WRONGCOD", "new_password": "NewPass456"})
    assert bad.status_code == 400
    ok = client.post("/api/auth/reset-password", json={"email": "reset@example.com", "code": code.lower(), "new_password": "NewPass456"})
    assert ok.status_code == 200
    assert client.post("/api/auth/login", json={"email": "reset@example.com", "password": "OldPass123"}).status_code == 401
    assert client.post("/api/auth/login", json={"email": "reset@example.com", "password": "NewPass456"}).status_code == 200
    # code is single-use
    again = client.post("/api/auth/reset-password", json={"email": "reset@example.com", "code": code, "new_password": "Another789"})
    assert again.status_code == 400


def test_reset_code_locks_after_too_many_attempts(client, register):
    register(email="lock@example.com", password="OldPass123")
    code = client.post("/api/auth/forgot-password", json={"email": "lock@example.com"}).json()["dev_reset_code"]
    from app.core.rate_limit import sensitive_limiter

    for _ in range(5):
        sensitive_limiter.reset()
        client.post("/api/auth/reset-password", json={"email": "lock@example.com", "code": "AAAAAAAA", "new_password": "NewPass456"})
    sensitive_limiter.reset()
    r = client.post("/api/auth/reset-password", json={"email": "lock@example.com", "code": code, "new_password": "NewPass456"})
    assert r.status_code == 400


def test_change_password_returns_new_tokens(client, register):
    _, headers = register(password="OldPass123")
    r = client.post("/api/auth/change-password", json={"current_password": "OldPass123", "new_password": "NewPass456"}, headers=headers)
    assert r.status_code == 200
    assert client.get("/api/users/me", headers=headers).status_code == 401  # old access token invalid
    new_headers = {"Authorization": f"Bearer {r.json()['access_token']}"}
    assert client.get("/api/users/me", headers=new_headers).status_code == 200


def test_login_rate_limit(client, register):
    register(email="rl@example.com")
    codes = [client.post("/api/auth/login", json={"email": "rl@example.com", "password": "wrongpass1"}).status_code
             for _ in range(12)]
    assert 429 in codes
