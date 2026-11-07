"""Image decoding/validation shared by the API.

The model input pipeline mirrors ml_training/common.py + evaluate.py exactly:
EXIF transpose -> RGB (alpha on white) -> short side <= 512 (Lanczos) ->
centre square crop -> 224x224 bilinear+antialias -> float32 0..255.
"""
from __future__ import annotations

import io
import warnings
from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError

PREPROCESS_SHORT_SIDE = 512
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP", "MPO"}
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp", "application/octet-stream", None, ""}


class ImageValidationError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code, self.message = code, message


@dataclass
class DecodedImage:
    image: Image.Image  # RGB, orientation-corrected, full resolution
    source_format: str
    width: int
    height: int
    warnings: list[str] = field(default_factory=list)


def decode_upload(data: bytes, content_type: str | None, *, max_bytes: int, max_pixels: int, min_side: int) -> DecodedImage:
    if not data:
        raise ImageValidationError("empty_file", "The uploaded file is empty.")
    if len(data) > max_bytes:
        raise ImageValidationError("file_too_large", f"Image is larger than {max_bytes // (1024 * 1024)} MB.")
    ct = (content_type or "").split(";")[0].strip().lower()
    if ct and ct not in ALLOWED_CONTENT_TYPES:
        raise ImageValidationError("unsupported_type", "Only JPEG, PNG or WEBP images are supported.")

    try:
        with Image.open(io.BytesIO(data)) as probe:
            fmt = probe.format
            w, h = probe.size  # header only - no pixel data decoded yet
    except Image.DecompressionBombError:
        # Pillow refuses to even open images above 2x its own pixel limit.
        raise ImageValidationError("image_too_large", "Image dimensions are too large.") from None
    except (UnidentifiedImageError, OSError):
        raise ImageValidationError("not_an_image", "The file is not a readable image.") from None
    if fmt not in ALLOWED_FORMATS:
        raise ImageValidationError("unsupported_type", f"Unsupported image format ({fmt}). Use JPEG, PNG or WEBP.")
    if w * h > max_pixels:
        # Decompression-bomb protection: reject before decoding pixels.
        raise ImageValidationError("image_too_large", "Image dimensions are too large.")
    if min(w, h) < min_side:
        raise ImageValidationError("image_too_small", f"Image is too small (minimum {min_side}px on each side).")

    try:
        with Image.open(io.BytesIO(data)) as im:
            im.verify()
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as im:
                im.load()
                im = ImageOps.exif_transpose(im)
                if im.mode in ("RGBA", "LA", "P"):
                    im = im.convert("RGBA")
                    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
                    bg.alpha_composite(im)
                    im = bg
                rgb = im.convert("RGB")
    except (Image.DecompressionBombWarning, Image.DecompressionBombError):
        raise ImageValidationError("image_too_large", "Image dimensions are too large.") from None
    except Exception:  # noqa: BLE001 - truncated / malformed data
        raise ImageValidationError("corrupt_image", "The image appears to be corrupted.") from None

    decoded = DecodedImage(rgb, fmt, rgb.width, rgb.height)
    decoded.warnings = quality_warnings(rgb)
    return decoded


def downscale_short_side(img: Image.Image, short: int = PREPROCESS_SHORT_SIDE) -> Image.Image:
    w, h = img.size
    s = min(w, h)
    if s <= short:
        return img
    scale = short / s
    return img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.Resampling.LANCZOS)


def center_square(arr: np.ndarray) -> np.ndarray:
    h, w = arr.shape[:2]
    s = min(h, w)
    top, left = (h - s) // 2, (w - s) // 2
    return arr[top : top + s, left : left + s]


def quality_warnings(img: Image.Image) -> list[str]:
    """Cheap photo-quality hints (OpenCV). Never blocks a prediction."""
    out: list[str] = []
    try:
        import cv2

        small = np.asarray(downscale_short_side(img, 512))
        gray = cv2.cvtColor(small, cv2.COLOR_RGB2GRAY)
        sharpness = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        brightness = float(gray.mean())
        if sharpness < 40:
            out.append("blurry")
        if brightness < 45:
            out.append("too_dark")
        elif brightness > 235:
            out.append("overexposed")
    except Exception:  # noqa: BLE001 - OpenCV optional
        pass
    return out


def to_storage_jpeg(img: Image.Image, max_side: int = 1600, quality: int = 88) -> bytes:
    """Re-encode for storage: bounded size, no EXIF/GPS metadata."""
    im = img.copy()
    im.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=quality, optimize=True)
    return buf.getvalue()
