"""Inspect the Crystal Genie gemstone dataset and write a report.

Usage (PowerShell, from CrystalGenie/ml_training):
    python inspect_dataset.py --data-dir "C:\\Users\\ASUS\\Desktop\\arun\\images\\a" --out reports

The dataset is expected to be organised as one sub-folder per class:
    <data-dir>/<ClassName>/<image files>

Nothing in the dataset is modified. The script reports:
  * total image count, class names, images per class, class imbalance
  * image dimensions, file extensions and colour modes
  * corrupted / unreadable files
  * exact duplicates (SHA-256) and near-duplicates (64-bit perceptual hash)
  * duplicates that appear under two different class labels (label conflicts)

Outputs (in --out):
  dataset_report.json   machine-readable report (also used by preprocess.py)
  dataset_report.md     human-readable report
  image_hashes.csv      per-file hashes (used by preprocess.py for leakage-free splits)
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import statistics
import sys
import warnings
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".tif", ".tiff"}
# Guard against decompression bombs while still allowing large camera photos.
Image.MAX_IMAGE_PIXELS = 80_000_000


def phash64(img: Image.Image) -> int:
    """64-bit DCT perceptual hash (same idea as imagehash.phash, no extra deps)."""
    g = ImageOps.exif_transpose(img).convert("L").resize((32, 32), Image.Resampling.LANCZOS)
    a = np.asarray(g, dtype=np.float64)
    n = 32
    k = np.arange(n)
    basis = np.cos(np.pi * (2 * k[None, :] + 1) * k[:, None] / (2 * n))  # DCT-II basis
    dct = basis @ a @ basis.T
    low = dct[:8, :8].flatten()
    med = np.median(low[1:])
    bits = low > med
    return int("".join("1" if b else "0" for b in bits), 2)


def hamming(a: int, b: int) -> int:
    return bin(a ^ b).count("1")


class UnionFind:
    def __init__(self, n: int):
        self.p = list(range(n))

    def find(self, x: int) -> int:
        while self.p[x] != x:
            self.p[x] = self.p[self.p[x]]
            x = self.p[x]
        return x

    def union(self, a: int, b: int) -> None:
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.p[rb] = ra


def inspect(data_dir: Path, near_dup_threshold: int) -> tuple[dict, list[dict]]:
    class_dirs = sorted([d for d in data_dir.iterdir() if d.is_dir() and not d.name.startswith((".", "_"))])
    loose_files = sorted(f.name for f in data_dir.iterdir() if f.is_file())
    rows: list[dict] = []
    corrupted: list[dict] = []
    non_image: list[str] = []

    for cdir in class_dirs:
        for f in sorted(cdir.rglob("*")):
            if not f.is_file():
                continue
            rel = f.relative_to(data_dir).as_posix()
            if f.suffix.lower() not in IMAGE_EXTS:
                non_image.append(rel)
                continue
            row = {"path": rel, "label": cdir.name, "ext": f.suffix.lower(), "bytes": f.stat().st_size}
            try:
                raw = f.read_bytes()
                row["sha256"] = hashlib.sha256(raw).hexdigest()
                with Image.open(f) as im:
                    im.verify()  # structural check
                with warnings.catch_warnings():
                    warnings.simplefilter("error", Image.DecompressionBombWarning)
                    with Image.open(f) as im:
                        im.load()  # full decode (catches truncated files)
                        row["format"] = im.format
                        row["mode"] = im.mode
                        w, h = ImageOps.exif_transpose(im).size
                        row["width"], row["height"] = w, h
                        row["phash"] = f"{phash64(im):016x}"
                row["ok"] = True
            except Exception as exc:  # noqa: BLE001 - we want to record every failure
                row["ok"] = False
                row["error"] = f"{type(exc).__name__}: {exc}"[:300]
                corrupted.append({"path": rel, "error": row["error"]})
            rows.append(row)

    ok_rows = [r for r in rows if r["ok"]]

    # ---- exact duplicates
    by_sha: dict[str, list[int]] = defaultdict(list)
    for i, r in enumerate(ok_rows):
        by_sha[r["sha256"]].append(i)
    exact_groups = [[ok_rows[i]["path"] for i in idx] for idx in by_sha.values() if len(idx) > 1]

    # ---- near duplicates via pHash (O(n^2) is fine for a few thousand images)
    hashes = np.array([int(r["phash"], 16) for r in ok_rows], dtype=np.uint64)
    uf = UnionFind(len(ok_rows))
    near_pairs = []
    for i in range(len(ok_rows)):
        x = np.bitwise_xor(hashes[i + 1 :], hashes[i])
        # popcount on uint64
        d = np.array([bin(int(v)).count("1") for v in x], dtype=np.int32) if len(x) else np.array([], dtype=np.int32)
        for j_off in np.nonzero(d <= near_dup_threshold)[0]:
            j = i + 1 + int(j_off)
            uf.union(i, j)
            near_pairs.append((ok_rows[i]["path"], ok_rows[j]["path"], int(d[j_off])))
    for idx in by_sha.values():
        for k in idx[1:]:
            uf.union(idx[0], k)

    groups: dict[int, list[int]] = defaultdict(list)
    for i in range(len(ok_rows)):
        groups[uf.find(i)].append(i)
    group_id_of = {}
    for gid, (_root, members) in enumerate(sorted(groups.items(), key=lambda kv: kv[0])):
        for m in members:
            group_id_of[m] = gid
    for i, r in enumerate(ok_rows):
        r["group_id"] = group_id_of[i]
    dup_groups = [[ok_rows[m]["path"] for m in members] for members in groups.values() if len(members) > 1]
    conflict_groups = [g for g in dup_groups if len({p.split("/")[0] for p in g}) > 1]

    # ---- statistics
    per_class = Counter(r["label"] for r in ok_rows)
    counts = [per_class[c.name] for c in class_dirs]
    widths = [r["width"] for r in ok_rows]
    heights = [r["height"] for r in ok_rows]
    short_side = [min(r["width"], r["height"]) for r in ok_rows]

    def dist(vals):
        if not vals:
            return {}
        return {
            "min": int(min(vals)),
            "p05": int(np.percentile(vals, 5)),
            "median": int(statistics.median(vals)),
            "p95": int(np.percentile(vals, 95)),
            "max": int(max(vals)),
        }

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "data_dir": str(data_dir),
        "structure": "one sub-folder per class (folder name = label)",
        "loose_files_in_root_ignored": loose_files,
        "total_files_scanned": len(rows) + len(non_image),
        "total_images_readable": len(ok_rows),
        "num_classes": len(class_dirs),
        "class_names": [c.name for c in class_dirs],
        "images_per_class": {c.name: per_class[c.name] for c in class_dirs},
        "imbalance": {
            "max_class": max(per_class, key=per_class.get) if per_class else None,
            "min_class": min(per_class, key=per_class.get) if per_class else None,
            "max_count": max(counts) if counts else 0,
            "min_count": min(counts) if counts else 0,
            "ratio_max_to_min": round(max(counts) / max(1, min(counts)), 2) if counts else None,
        },
        "extensions": dict(Counter(r["ext"] for r in rows)),
        "formats": dict(Counter(r.get("format", "unreadable") for r in rows)),
        "color_modes": dict(Counter(r.get("mode", "unreadable") for r in rows)),
        "width": dist(widths),
        "height": dist(heights),
        "short_side": dist(short_side),
        "images_with_short_side_below_224": sum(1 for s in short_side if s < 224),
        "non_image_files": non_image,
        "corrupted_count": len(corrupted),
        "corrupted": corrupted,
        "exact_duplicate_groups": exact_groups,
        "exact_duplicate_extra_copies": sum(len(g) - 1 for g in exact_groups),
        "near_duplicate_threshold_bits": near_dup_threshold,
        "near_duplicate_groups": dup_groups,
        "near_duplicate_group_count": len(dup_groups),
        "images_in_near_duplicate_groups": sum(len(g) for g in dup_groups),
        "cross_class_duplicate_groups": conflict_groups,
        "unique_groups": len(groups),
    }
    return report, ok_rows + [r for r in rows if not r["ok"]]


def write_markdown(report: dict, path: Path) -> None:
    lines = [
        "# Crystal Genie — Dataset Inspection Report",
        "",
        f"Generated: {report['generated_at']}  ",
        f"Dataset: `{report['data_dir']}`  ",
        f"Structure: {report['structure']}",
        "",
        "## Summary",
        "",
        f"* Readable images: **{report['total_images_readable']}** (files scanned: {report['total_files_scanned']})",
        f"* Classes: **{report['num_classes']}**",
        f"* Corrupted / unreadable: **{report['corrupted_count']}**",
        f"* Exact duplicate extra copies: **{report['exact_duplicate_extra_copies']}**",
        f"* Near-duplicate groups (pHash ≤ {report['near_duplicate_threshold_bits']} bits): "
        f"**{report['near_duplicate_group_count']}** covering {report['images_in_near_duplicate_groups']} images",
        f"* Duplicate groups spanning two labels: **{len(report['cross_class_duplicate_groups'])}**",
        f"* Class imbalance (max/min): **{report['imbalance']['ratio_max_to_min']}** "
        f"({report['imbalance']['max_class']} {report['imbalance']['max_count']} vs "
        f"{report['imbalance']['min_class']} {report['imbalance']['min_count']})",
        f"* Images with short side < 224 px: **{report['images_with_short_side_below_224']}**",
        "",
        "## Images per class",
        "",
        "| Class | Images |",
        "|---|---:|",
    ]
    for k, v in report["images_per_class"].items():
        lines.append(f"| {k} | {v} |")
    lines += [
        "",
        "## Formats",
        "",
        f"* Extensions: {report['extensions']}",
        f"* Decoded formats: {report['formats']}",
        f"* Colour modes: {report['color_modes']}",
        "",
        "## Dimensions (pixels)",
        "",
        "| | min | p05 | median | p95 | max |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for key in ("width", "height", "short_side"):
        d = report[key]
        if d:
            lines.append(f"| {key} | {d['min']} | {d['p05']} | {d['median']} | {d['p95']} | {d['max']} |")
    if report["loose_files_in_root_ignored"]:
        lines += ["", "## Files in dataset root (not part of any class, ignored)", ""]
        lines += [f"* {f}" for f in report["loose_files_in_root_ignored"]]
    if report["corrupted"]:
        lines += ["", "## Corrupted files", ""]
        lines += [f"* `{c['path']}` — {c['error']}" for c in report["corrupted"]]
    if report["cross_class_duplicate_groups"]:
        lines += ["", "## Duplicates found under different labels (please review)", ""]
        for g in report["cross_class_duplicate_groups"]:
            lines.append("* " + ", ".join(f"`{p}`" for p in g))
    if report["near_duplicate_groups"]:
        lines += ["", "## Near-duplicate groups (kept together in one split)", ""]
        for g in report["near_duplicate_groups"][:200]:
            lines.append("* " + ", ".join(f"`{p}`" for p in g))
        if len(report["near_duplicate_groups"]) > 200:
            lines.append(f"* … {len(report['near_duplicate_groups']) - 200} more groups in dataset_report.json")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data-dir", required=True, type=Path)
    ap.add_argument("--out", default=Path("reports"), type=Path)
    ap.add_argument("--near-dup-threshold", type=int, default=6, help="max pHash Hamming distance (bits)")
    args = ap.parse_args(argv)

    if not args.data_dir.is_dir():
        print(f"Dataset folder not found: {args.data_dir}", file=sys.stderr)
        return 2
    args.out.mkdir(parents=True, exist_ok=True)
    report, rows = inspect(args.data_dir, args.near_dup_threshold)

    (args.out / "dataset_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    write_markdown(report, args.out / "dataset_report.md")
    fields = ["path", "label", "ext", "bytes", "ok", "format", "mode", "width", "height", "sha256", "phash", "group_id", "error"]
    with (args.out / "image_hashes.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)

    print(f"Classes ({report['num_classes']}): {', '.join(report['class_names'])}")
    print(f"Readable images: {report['total_images_readable']}  corrupted: {report['corrupted_count']}")
    print(f"Exact dup extra copies: {report['exact_duplicate_extra_copies']}  near-dup groups: {report['near_duplicate_group_count']}")
    print(f"Imbalance max/min: {report['imbalance']['ratio_max_to_min']}")
    print(f"Report written to {args.out.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
