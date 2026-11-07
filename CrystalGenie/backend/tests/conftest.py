"""Test fixtures.

Database: uses TEST_DATABASE_URL (PostgreSQL recommended — the schema is created by running
the real Alembic migrations). Falls back to a temporary SQLite file if it is not set.

Model: API tests use `FakeClassifier`, an explicit TEST DOUBLE with deterministic output so the
HTTP/database behaviour can be tested without TensorFlow. Tests in test_real_model.py use the
real trained model and are skipped automatically when it is not available.
"""
from __future__ import annotations

import io
import os
import sys
import tempfile
from pathlib import Path

import pytest

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

_tmp = Path(tempfile.mkdtemp(prefix="cg_test_"))
os.environ["APP_ENV"] = "test"
os.environ["LOAD_MODEL_ON_STARTUP"] = "false"
os.environ["MEDIA_ROOT"] = str(_tmp / "media")
os.environ["OUTBOX_DIR"] = str(_tmp / "outbox")
os.environ["JWT_SECRET"] = "test-secret-" + "x" * 40
os.environ["EXPOSE_RESET_CODE_IN_RESPONSE"] = "true"
os.environ["MAX_UPLOAD_MB"] = "2"
os.environ["CORS_ORIGINS"] = ""


def _load_env_file_value(key: str) -> str:
    env = BACKEND / ".env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith(f"{key}="):
                return line.split("=", 1)[1].strip()
    return ""


TEST_DB_URL = os.environ.get("TEST_DATABASE_URL") or _load_env_file_value("TEST_DATABASE_URL") or f"sqlite:///{_tmp / 'test.db'}"
os.environ["DATABASE_URL"] = TEST_DB_URL

from PIL import Image  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app.core.config import get_settings  # noqa: E402

get_settings.cache_clear()

from app.core.rate_limit import login_limiter, sensitive_limiter  # noqa: E402
from app.database import session as db_session  # noqa: E402
from app.database.seed import seed_gemstones  # noqa: E402
from app.ml.classifier import ClassifierResult, ClassScore, get_classifier  # noqa: E402
from app.models import Base  # noqa: E402


class FakeClassifier:
    """Deterministic test double: picks a class from the image's dominant colour."""

    loaded = True
    error = None
    model_version = "test-double"
    threshold = 0.6
    temperature = 1.0
    metadata = {"architecture": "test double", "input_size": [224, 224, 3]}

    def __init__(self):
        self.class_names = ["Garnet", "Lapis_Lazuli", "Rose_Quartz", "Obsidian"]
        self.calls = 0

    def predict(self, image, top_k=3):
        self.calls += 1
        r, g, b = image.convert("RGB").resize((8, 8)).getpixel((4, 4))
        if r == g == b:  # flat grey: confident but unlike any training image -> OOD guard
            scores = [("Obsidian", 0.81), ("Garnet", 0.1), ("Rose_Quartz", 0.09)]
            return ClassifierResult(top=[ClassScore(c, p) for c, p in scores[:top_k]], is_uncertain=True,
                                    threshold=self.threshold, model_version=self.model_version, latency_ms=1.0,
                                    similarity=0.21, uncertainty_reason="unlike_training_data")
        if b > r and b > g:
            scores = [("Lapis_Lazuli", 0.91), ("Obsidian", 0.05), ("Garnet", 0.04)]
        elif r > 200 and g > 150:
            scores = [("Rose_Quartz", 0.45), ("Garnet", 0.35), ("Obsidian", 0.2)]  # uncertain
        else:
            scores = [("Garnet", 0.88), ("Rose_Quartz", 0.08), ("Obsidian", 0.04)]
        low = scores[0][1] < self.threshold
        return ClassifierResult(top=[ClassScore(c, p) for c, p in scores[:top_k]], is_uncertain=low,
                                threshold=self.threshold, model_version=self.model_version, latency_ms=1.0,
                                similarity=0.9, uncertainty_reason="low_confidence" if low else None)


class UnloadedClassifier(FakeClassifier):
    loaded = False
    error = "FileNotFoundError: model file not found"
    model_version = None

    def predict(self, image, top_k=3):  # pragma: no cover - must never be called
        raise AssertionError("predict called on unloaded model")


def make_image_bytes(color=(200, 30, 40), size=(320, 320), fmt="JPEG") -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, fmt)
    return buf.getvalue()


def _create_schema(engine) -> None:
    if engine.dialect.name == "postgresql":
        with engine.begin() as conn:
            conn.execute(text("DROP SCHEMA public CASCADE"))
            conn.execute(text("CREATE SCHEMA public"))
        from alembic import command
        from alembic.config import Config

        cfg = Config(str(BACKEND / "alembic.ini"))
        cfg.set_main_option("script_location", str(BACKEND / "alembic"))
        cfg.set_main_option("sqlalchemy.url", engine.url.render_as_string(hide_password=False))
        command.upgrade(cfg, "head")
    else:
        Base.metadata.drop_all(engine)
        Base.metadata.create_all(engine)


@pytest.fixture(scope="session")
def engine():
    eng = db_session.make_engine(TEST_DB_URL)
    _create_schema(eng)
    db_session.set_engine(eng)
    yield eng
    eng.dispose()


@pytest.fixture(autouse=True)
def clean_db(engine):
    tables = ["favorites", "saved_crystals", "predictions", "password_reset_tokens", "refresh_tokens", "user_settings",
              "users", "gemstones"]
    with engine.begin() as conn:
        if engine.dialect.name == "postgresql":
            conn.execute(text(f"TRUNCATE {', '.join(tables)} CASCADE"))
        else:
            for t in tables:
                conn.execute(text(f"DELETE FROM {t}"))
    with db_session.SessionLocal() as db:
        seed_gemstones(db)
    login_limiter.reset()
    sensitive_limiter.reset()
    yield


@pytest.fixture
def fake_classifier():
    return FakeClassifier()


@pytest.fixture
def client(engine, fake_classifier):
    from fastapi.testclient import TestClient

    from app.main import app

    app.dependency_overrides[get_classifier] = lambda: fake_classifier
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
def register(client):
    def _register(email="jon@example.com", password="CrystalPass1", name="Jon Doe"):
        r = client.post("/api/auth/register", json={"full_name": name, "email": email, "password": password})
        assert r.status_code == 201, r.text
        data = r.json()
        return data, {"Authorization": f"Bearer {data['access_token']}"}

    return _register


@pytest.fixture
def auth_headers(register):
    return register()[1]
