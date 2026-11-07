from __future__ import annotations

import json
from pathlib import Path


def test_health(client):
    r = client.get("/api/health")
    assert r.status_code == 200
    body = r.json()
    assert body["database"] == "ok" and body["model_loaded"] is True and body["status"] == "ok"
    assert r.headers["x-content-type-options"] == "nosniff"
    assert "x-request-id" in r.headers


def test_model_status(client):
    s = client.get("/api/model/status").json()
    assert s["loaded"] is True and s["num_classes"] == 4 and s["confidence_threshold"] == 0.6


def test_library_lists_all_seeded_gemstones_sorted(client):
    r = client.get("/api/gemstones?page_size=100").json()
    assert r["total"] == 13
    names = [g["name"] for g in r["items"]]
    assert names == sorted(names, key=str.lower)
    desc = client.get("/api/gemstones?page_size=100&sort=name_desc").json()["items"]
    assert [g["name"] for g in desc] == names[::-1]
    assert all(g["image_url"].startswith("/static/gemstones/") for g in r["items"])


def test_seed_matches_model_classes(client):
    """Every class in the dataset has a library entry (class_name)."""
    classes = {"Garnet", "Goldstone", "Hematite", "Herkimer_Diamond", "Lapis_Lazuli", "Libyan_Desert_Glass", "Obsidian",
                "Red_Beryl", "Red_Jasper", "Rose_Quartz", "Shungite", "Smokey_Quartz", "Tigers_Eye"}
    seed = json.loads((Path(__file__).resolve().parents[1] / "app" / "data" / "gemstones.json").read_text(encoding="utf-8"))
    assert {g["class_name"] for g in seed} == classes
    for g in seed:
        assert "belief" in g["traditional_meanings"].lower() or "tradition" in g["traditional_meanings"].lower()
        assert (Path(__file__).resolve().parents[1] / "static" / "gemstones" / g["image_file"]).exists()


def test_pagination_search_filter(client):
    p = client.get("/api/gemstones?page=2&page_size=5").json()
    assert p["page"] == 2 and len(p["items"]) == 5 and p["has_more"] is True
    s = client.get("/api/gemstones/search?q=quartz").json()
    assert {g["slug"] for g in s["items"]} >= {"rose-quartz", "smoky-quartz"}
    cats = client.get("/api/gemstones/categories").json()
    assert {"name": "Natural glass", "count": 2} in cats
    glass = client.get("/api/gemstones?category=Natural glass").json()
    assert {g["slug"] for g in glass["items"]} == {"obsidian", "libyan-desert-glass"}
    red = client.get("/api/gemstones?color=red&page_size=50").json()
    assert "red-jasper" in {g["slug"] for g in red["items"]}
    synthetic = client.get("/api/gemstones?natural=false").json()
    assert [g["slug"] for g in synthetic["items"]] == ["goldstone"]
    assert client.get("/api/gemstones/search").status_code == 422


def test_gemstone_detail_and_404(client):
    gid = client.get("/api/gemstones/search?q=red beryl").json()["items"][0]["id"]
    d = client.get(f"/api/gemstones/{gid}").json()
    assert d["chemical_formula"].startswith("Be₃Al₂Si₆O₁₈")
    assert d["hardness_label"] == "7.5–8" and d["sources"]
    assert client.get("/api/gemstones/00000000-0000-0000-0000-000000000000").status_code == 404
    assert client.get("/api/gemstones/not-a-uuid").status_code == 422


def test_static_gem_image_served(client):
    r = client.get("/static/gemstones/garnet.jpg")
    assert r.status_code == 200 and r.headers["content-type"] == "image/jpeg"


def test_unknown_route_has_json_error(client):
    r = client.get("/api/does-not-exist")
    assert r.status_code == 404 and r.json()["error"]["code"] == "not_found"
