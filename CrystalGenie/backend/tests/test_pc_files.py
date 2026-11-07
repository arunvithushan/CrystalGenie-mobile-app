"""'Browse this computer' API: off by default, local-only, read-only, images only, no path escapes."""
from __future__ import annotations

import io

import pytest
from PIL import Image

from app.core.config import get_settings


def _jpeg(path, color=(200, 80, 90), size=(800, 600)):
    Image.new("RGB", size, color).save(path, "JPEG")


@pytest.fixture
def pc(tmp_path, monkeypatch):
    root = tmp_path / "pc"
    (root / "Gems").mkdir(parents=True)
    (root / ".secret").mkdir()
    (root / "AppData").mkdir()
    _jpeg(root / "Gems" / "garnet.jpg")
    (root / "Gems" / "notes.txt").write_text("not an image")
    (tmp_path / "outside.jpg").write_bytes(b"x")
    s = get_settings()
    monkeypatch.setattr(s, "pc_browse_enabled", True)
    monkeypatch.setattr(s, "pc_browse_roots", str(root))
    monkeypatch.setattr(s, "pc_browse_allow_lan", True)  # TestClient's host is "testclient", not loopback
    return root


def test_disabled_by_default(client, auth_headers, monkeypatch):
    monkeypatch.setattr(get_settings(), "pc_browse_enabled", False)
    assert client.get("/api/pc/roots", headers=auth_headers).status_code == 404


def test_requires_sign_in(client, pc):
    assert client.get("/api/pc/roots").status_code == 401


def test_only_local_requests_unless_lan_allowed(client, auth_headers, pc, monkeypatch):
    monkeypatch.setattr(get_settings(), "pc_browse_allow_lan", False)
    r = client.get("/api/pc/roots", headers=auth_headers)
    assert r.status_code == 403


def test_lists_folders_and_images_only(client, auth_headers, pc):
    roots = client.get("/api/pc/roots", headers=auth_headers).json()["roots"]
    assert [r["path"] for r in roots] == [str(pc.resolve())]
    top = client.get("/api/pc/list", params={"path": roots[0]["path"]}, headers=auth_headers).json()
    assert [f["name"] for f in top["folders"]] == ["Gems"]  # .secret and AppData are hidden
    assert top["parent"] is None
    gems = client.get("/api/pc/list", params={"path": top["folders"][0]["path"]}, headers=auth_headers).json()
    assert [i["name"] for i in gems["images"]] == ["garnet.jpg"]  # notes.txt is not shown
    assert gems["parent"] == str(pc.resolve())


def test_thumbnail_and_full_image(client, auth_headers, pc):
    p = str(pc / "Gems" / "garnet.jpg")
    t = client.get("/api/pc/image", params={"path": p, "thumb": True}, headers=auth_headers)
    assert t.status_code == 200 and t.headers["content-type"] == "image/jpeg"
    assert max(Image.open(io.BytesIO(t.content)).size) <= 360
    full = client.get("/api/pc/image", params={"path": p}, headers=auth_headers)
    assert full.status_code == 200 and Image.open(io.BytesIO(full.content)).size == (800, 600)


@pytest.mark.parametrize("rel", ["../outside.jpg", "Gems/../../outside.jpg"])
def test_no_escape_outside_roots(client, auth_headers, pc, rel):
    r = client.get("/api/pc/image", params={"path": str(pc / rel)}, headers=auth_headers)
    assert r.status_code == 403


def test_hidden_folders_and_non_images_refused(client, auth_headers, pc):
    assert client.get("/api/pc/list", params={"path": str(pc / ".secret")}, headers=auth_headers).status_code == 403
    assert client.get("/api/pc/list", params={"path": str(pc / "AppData")}, headers=auth_headers).status_code == 403
    r = client.get("/api/pc/image", params={"path": str(pc / "Gems" / "notes.txt")}, headers=auth_headers)
    assert r.status_code == 400
