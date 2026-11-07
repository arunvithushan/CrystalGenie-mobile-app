"""End-to-end check against a RUNNING backend with the REAL model.

Covers: register -> login -> upload a gemstone photo -> real prediction -> gemstone details ->
save to My Finds -> add to Favorites -> list My Finds -> logout -> login again -> data persists.

Usage (PowerShell, backend running on port 8000):
    python scripts\\e2e_smoke.py --base-url http://127.0.0.1:8000 --image ..\\ml_training\\data\\processed\\Rose_Quartz\\000010.jpg
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
from pathlib import Path

import httpx


def step(name: str, ok: bool, detail: str = "") -> None:
    print(f"[{'PASS' if ok else 'FAIL'}] {name}{' — ' + detail if detail else ''}")
    if not ok:
        sys.exit(1)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://127.0.0.1:8000")
    ap.add_argument("--image", type=Path, required=True)
    args = ap.parse_args()

    api = args.base_url.rstrip("/") + "/api"
    c = httpx.Client(timeout=60)
    email = f"e2e-{uuid.uuid4().hex[:8]}@example.com"
    password = "E2eCrystal123"

    h = c.get(f"{api}/health").json()
    step("health", h["database"] == "ok" and h["model_loaded"], json.dumps(h))
    ms = c.get(f"{api}/model/status").json()
    step("model status", ms["loaded"] and ms["num_classes"] > 0, f"{ms['model_version']} ({ms['num_classes']} classes)")

    r = c.post(f"{api}/auth/register", json={"full_name": "E2E Tester", "email": email, "password": password})
    step("1. register", r.status_code == 201, email)

    r = c.post(f"{api}/auth/login", json={"email": email, "password": password})
    step("2. login", r.status_code == 200)
    tokens = r.json()
    auth = {"Authorization": f"Bearer {tokens['access_token']}"}

    t0 = time.perf_counter()
    with args.image.open("rb") as fh:
        r = c.post(f"{api}/predict", files={"file": (args.image.name, fh, "image/jpeg")}, headers=auth)
    step("3-4. upload photo", r.status_code == 201, f"{(time.perf_counter() - t0) * 1000:.0f} ms round trip")
    pred = r.json()
    top = ", ".join(f"{t['display_name']} {t['confidence']:.1%}" for t in pred["top_predictions"])
    step("5. real AI prediction", pred["model_version"] != "test-double" and pred["id"] is not None,
         f"{pred['display_name']} ({pred['confidence']:.1%}, uncertain={pred['is_uncertain']}) | top-3: {top}")

    gem = pred["gemstone"]
    step("6. gemstone details", gem is not None and bool(gem["description"]),
         f"{gem['name']} — hardness {gem['hardness_label']}, family: {gem['mineral_family']}")

    r = c.post(f"{api}/saved", json={"prediction_id": pred["id"]}, headers=auth)
    step("7. save to My Finds", r.status_code == 201)
    r = c.post(f"{api}/favorites", json={"gemstone_id": gem["id"]}, headers=auth)
    step("8. add to Favorites", r.status_code == 201)
    finds = c.get(f"{api}/saved", headers=auth).json()
    step("9. open My Finds", finds["total"] == 1 and finds["items"][0]["prediction"]["id"] == pred["id"])

    r = c.post(f"{api}/auth/logout", json={"refresh_token": tokens["refresh_token"]}, headers=auth)
    step("10a. logout", r.status_code == 200)
    r = c.post(f"{api}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    step("10b. old refresh token rejected", r.status_code == 401)
    r = c.post(f"{api}/auth/login", json={"email": email, "password": password})
    step("10c. login again", r.status_code == 200)
    auth = {"Authorization": f"Bearer {r.json()['access_token']}"}

    finds = c.get(f"{api}/saved", headers=auth).json()
    favs = c.get(f"{api}/favorites", headers=auth).json()
    hist = c.get(f"{api}/predictions", headers=auth).json()
    step("11. saved data persists", finds["total"] == 1 and favs["total"] == 1 and hist["total"] == 1,
         f"my finds={finds['total']} favorites={favs['total']} history={hist['total']}")

    r = c.request("DELETE", f"{api}/users/me", json={"password": password, "confirm": "DELETE"}, headers=auth)
    step("cleanup: delete test account", r.status_code == 200)
    print("\nEnd-to-end workflow verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
