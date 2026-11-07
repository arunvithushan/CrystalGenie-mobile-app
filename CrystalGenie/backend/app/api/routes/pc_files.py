"""Development helper: browse the photos on this computer from the app (emulator or a phone on the LAN).

Safety rules:
* off unless PC_BROWSE_ENABLED=true, and refused when APP_ENV=production;
* signed-in users only, and only from this PC itself (loopback) unless PC_BROWSE_ALLOW_LAN=true;
* read-only; only folders and JPG/PNG/WEBP files under the configured roots are visible;
* hidden/system folders are skipped and paths are resolved (no "..", no symlink escape).
"""
from __future__ import annotations

import io
import os
import string
import sys
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Query, Request
from fastapi.responses import FileResponse, Response
from PIL import Image, ImageOps

from app.api.deps import CurrentUser
from app.core.config import get_settings
from app.core.errors import AppError, BadRequest, Forbidden, NotFound  # noqa: F401

router = APIRouter(prefix="/pc", tags=["pc files (development)"])

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
SKIP_DIRS = {"appdata", "application data", "$recycle.bin", "system volume information", "windows", "program files",
             "program files (x86)", "programdata", "recovery", "perflogs", "node_modules", "__pycache__", ".venv",
             "venv", "site-packages", "build", ".dart_tool", ".gradle", ".git"}
MAX_ENTRIES = 1000
THUMB_SIZE = 360
LOOPBACK = {"127.0.0.1", "::1", "localhost"}


def _roots() -> list[Path]:
    s = get_settings()
    if s.pc_browse_roots.strip():
        items = [Path(p.strip()).expanduser() for p in s.pc_browse_roots.split(";") if p.strip()]
    else:
        items = [Path.home()]
        if sys.platform.startswith("win"):
            home_drive = Path.home().anchor.upper()
            items += [Path(f"{d}:\\") for d in string.ascii_uppercase
                      if f"{d}:\\" != home_drive and d not in "AB" and os.path.isdir(f"{d}:\\")]
    out: list[Path] = []
    for r in items:
        try:
            rr = r.resolve(strict=True)
        except OSError:
            continue
        if rr.is_dir() and rr not in out:
            out.append(rr)
    return out


def _guard(request: Request) -> list[Path]:
    s = get_settings()
    if not s.pc_browse_enabled or s.is_production:
        raise AppError(404, "pc_browse_disabled", "Browsing this computer is turned off. Set PC_BROWSE_ENABLED=true "
                       "in backend/.env and restart the backend (START_APP.cmd).")
    host = request.client.host if request.client else ""
    if host not in LOOPBACK and not s.pc_browse_allow_lan:
        raise Forbidden("Browsing this computer is only allowed from the emulator on this PC "
                        "(set PC_BROWSE_ALLOW_LAN=true to allow a phone on your Wi-Fi).")
    roots = _roots()
    if not roots:
        raise AppError(503, "no_roots", "No folders are configured for browsing.")
    return roots


def _resolve(path: str, roots: list[Path]) -> Path:
    if not path or "\x00" in path:
        raise BadRequest("A path is required.")
    try:
        p = Path(path).expanduser().resolve(strict=True)
    except (OSError, RuntimeError):
        raise NotFound("File or folder") from None
    if not any(p == r or p.is_relative_to(r) for r in roots):
        raise Forbidden("That location is outside the folders you can browse.")
    for part in p.parts[len(next(r for r in roots if p == r or p.is_relative_to(r)).parts):]:
        if part.startswith(".") or part.lower() in SKIP_DIRS:
            raise Forbidden("That folder is hidden.")
    return p


def _hidden(entry: os.DirEntry) -> bool:
    name = entry.name
    if name.startswith((".", "$", "~")) or name.lower() in SKIP_DIRS or name.lower() in {"desktop.ini", "thumbs.db"}:
        return True
    attrs = getattr(entry.stat(follow_symlinks=False), "st_file_attributes", 0)
    return bool(attrs & (0x2 | 0x4))  # FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM


def _places(rs: list[Path]) -> list[Path]:
    """Desktop / Pictures / Downloads / Documents shortcuts (only with the default roots)."""
    if get_settings().pc_browse_roots.strip():
        return []
    home = Path.home()
    out = []
    for name in ("Desktop", "Pictures", "Downloads", "Documents"):
        for cand in (home / name, home / "OneDrive" / name):
            try:
                p = cand.resolve(strict=True)
            except OSError:
                continue
            if p.is_dir() and any(p.is_relative_to(r) for r in rs) and p not in out:
                out.append(p)
                break
    return out


@router.get("/roots")
def roots(request: Request, user: CurrentUser):
    rs = _guard(request)
    places = [{"name": p.name, "path": str(p), "kind": "place"} for p in _places(rs)]
    return {"roots": places + [{"name": (r.name or str(r)), "path": str(r), "kind": "root"} for r in rs]}


@router.get("/list")
def list_folder(request: Request, user: CurrentUser, path: str = Query(..., max_length=1024)):
    rs = _guard(request)
    folder = _resolve(path, rs)
    if not folder.is_dir():
        raise BadRequest("That is not a folder.")
    folders, images, truncated = [], [], False
    try:
        with os.scandir(folder) as it:
            for e in it:
                try:
                    if _hidden(e):
                        continue
                    if e.is_dir(follow_symlinks=False):
                        folders.append({"name": e.name, "path": os.path.join(folder, e.name)})
                    elif e.is_file(follow_symlinks=False) and Path(e.name).suffix.lower() in IMAGE_EXTS:
                        st = e.stat(follow_symlinks=False)
                        images.append({"name": e.name, "path": os.path.join(folder, e.name), "size": st.st_size,
                                       "modified": datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).isoformat()})
                except OSError:
                    continue
                if len(folders) + len(images) >= MAX_ENTRIES:
                    truncated = True
                    break
    except PermissionError:
        raise Forbidden("Windows does not allow reading this folder.") from None
    folders.sort(key=lambda f: f["name"].lower())
    images.sort(key=lambda f: f["modified"], reverse=True)  # newest photos first
    parent = None
    if not any(folder == r for r in rs):
        parent = str(folder.parent)
    return {"path": str(folder), "name": folder.name or str(folder), "parent": parent,
            "folders": folders, "images": images, "truncated": truncated}


@router.get("/image")
def image(request: Request, user: CurrentUser, path: str = Query(..., max_length=1024), thumb: bool = False):
    rs = _guard(request)
    f = _resolve(path, rs)
    if not f.is_file() or f.suffix.lower() not in IMAGE_EXTS:
        raise BadRequest("Only JPG, PNG and WEBP images can be opened.")
    if f.stat().st_size > 50 * 1024 * 1024:
        raise BadRequest("That image is too large (over 50 MB).")
    if not thumb:
        media = {".png": "image/png", ".webp": "image/webp"}.get(f.suffix.lower(), "image/jpeg")
        return FileResponse(f, media_type=media, filename=f.name, headers={"Cache-Control": "private, max-age=300"})
    try:
        with Image.open(f) as im:
            im.draft("RGB", (THUMB_SIZE, THUMB_SIZE))
            im = ImageOps.exif_transpose(im).convert("RGB")
            im.thumbnail((THUMB_SIZE, THUMB_SIZE))
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=80)
    except Exception:  # noqa: BLE001 - unreadable/corrupt image
        raise BadRequest("This image could not be read.") from None
    return Response(buf.getvalue(), media_type="image/jpeg", headers={"Cache-Control": "private, max-age=300"})
