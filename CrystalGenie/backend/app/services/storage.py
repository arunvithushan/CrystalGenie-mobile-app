"""Local media storage for uploaded images (outside the static folder, served only to owners)."""
from __future__ import annotations

import shutil
import uuid
from pathlib import Path

from app.core.config import get_settings


def _root() -> Path:
    root = get_settings().media_root
    root.mkdir(parents=True, exist_ok=True)
    return root


def save_bytes(kind: str, user_id: uuid.UUID, data: bytes, ext: str = "jpg") -> str:
    """Store data and return the path relative to MEDIA_ROOT (always forward slashes)."""
    if kind not in {"predictions", "avatars"}:
        raise ValueError("invalid media kind")
    rel = Path(kind) / str(user_id) / f"{uuid.uuid4().hex}.{ext}"
    dest = _root() / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(".tmp")
    tmp.write_bytes(data)
    tmp.replace(dest)
    return rel.as_posix()


def resolve(rel_path: str | None) -> Path | None:
    """Return the absolute path for a stored file, refusing anything outside MEDIA_ROOT."""
    if not rel_path:
        return None
    root = _root().resolve()
    p = (root / rel_path).resolve()
    if root not in p.parents or not p.is_file():
        return None
    return p


def delete(rel_path: str | None) -> None:
    p = resolve(rel_path)
    if p:
        p.unlink(missing_ok=True)


def delete_user_media(user_id: uuid.UUID) -> None:
    for kind in ("predictions", "avatars"):
        d = _root() / kind / str(user_id)
        if d.is_dir():
            shutil.rmtree(d, ignore_errors=True)
