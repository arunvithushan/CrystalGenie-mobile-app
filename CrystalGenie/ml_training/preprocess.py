"""Prepare the gemstone dataset for training (originals are never modified).

Steps
  1. Read the inspection output (reports/image_hashes.csv). Run inspect_dataset.py first.
  2. Skip corrupted files and anything listed in exclude.txt (optional quarantine list,
     one dataset-relative path per line, e.g. `Rose_Quartz/000123.jpg`).
  3. Normalise every image: EXIF orientation, RGB (transparency composited on white),
     short side <= 512 px, saved as JPEG (quality 95) under data/processed/<class>/.
  4. Group-aware stratified split (train/val/test = 70/15/15 by default): images in the
     same near-duplicate group always land in the same split, so no near-identical
     specimen photo leaks between training and evaluation.
  5. Write data/splits/{train,val,test}.csv, class_names.json and split_summary.json.

Usage (PowerShell, from CrystalGenie/ml_training):
    python preprocess.py --data-dir "C:\\Users\\ASUS\\Desktop\\arun\\images\\a"
"""
from __future__ import annotations

import argparse
import csv
import random
import sys
from collections import defaultdict
from pathlib import Path

from common import (
    DEFAULT_DATA_DIR,
    PROCESSED_DIR,
    REPORTS_DIR,
    SEED,
    SPLITS_DIR,
    load_rgb,
    write_json,
)


def read_inspection(reports_dir: Path) -> list[dict]:
    csv_path = reports_dir / "image_hashes.csv"
    if not csv_path.exists():
        sys.exit(f"{csv_path} not found. Run inspect_dataset.py first.")
    with csv_path.open(encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def read_exclusions(path: Path) -> set[str]:
    if not path.exists():
        return set()
    out = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip().replace("\\", "/")
        if line:
            out.add(line)
    return out


def split_groups(rows: list[dict], val_frac: float, test_frac: float, seed: int) -> dict[str, str]:
    """Return {path: split}. Allocation is per class over near-duplicate groups."""
    rng = random.Random(seed)
    by_class: dict[str, dict[str, list[dict]]] = defaultdict(lambda: defaultdict(list))
    for r in rows:
        by_class[r["label"]][r["group_id"]].append(r)

    assignment: dict[str, str] = {}
    for label in sorted(by_class):
        groups = list(by_class[label].values())
        rng.shuffle(groups)
        total = sum(len(g) for g in groups)
        n_test = max(1, round(total * test_frac))
        n_val = max(1, round(total * val_frac))
        counts = {"test": 0, "val": 0, "train": 0}
        for g in groups:
            if counts["test"] + len(g) <= n_test and counts["test"] < n_test:
                split = "test"
            elif counts["val"] + len(g) <= n_val and counts["val"] < n_val:
                split = "val"
            else:
                split = "train"
            counts[split] += len(g)
            for r in g:
                assignment[r["path"]] = split
    return assignment


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    ap.add_argument("--reports", type=Path, default=REPORTS_DIR)
    ap.add_argument("--out", type=Path, default=PROCESSED_DIR)
    ap.add_argument("--splits", type=Path, default=SPLITS_DIR)
    ap.add_argument("--exclude", type=Path, default=Path(__file__).with_name("exclude.txt"))
    ap.add_argument("--val", type=float, default=0.15)
    ap.add_argument("--test", type=float, default=0.15)
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--min-short-side", type=int, default=96, help="skip images smaller than this")
    args = ap.parse_args(argv)

    rows = read_inspection(args.reports)
    excluded = read_exclusions(args.exclude)
    usable, skipped = [], []
    for r in rows:
        if r.get("ok") not in ("True", True):
            skipped.append({"path": r["path"], "reason": "corrupted: " + (r.get("error") or "")})
        elif r["path"] in excluded:
            skipped.append({"path": r["path"], "reason": "listed in exclude.txt"})
        elif min(int(r["width"]), int(r["height"])) < args.min_short_side:
            skipped.append({"path": r["path"], "reason": f"short side < {args.min_short_side}px"})
        else:
            usable.append(r)

    class_names = sorted({r["label"] for r in usable})
    assignment = split_groups(usable, args.val, args.test, args.seed)

    args.out.mkdir(parents=True, exist_ok=True)
    args.splits.mkdir(parents=True, exist_ok=True)
    manifests: dict[str, list[dict]] = {"train": [], "val": [], "test": []}
    used_names: set[str] = set()
    for i, r in enumerate(usable, 1):
        src = args.data_dir / r["path"]
        stem = Path(r["path"]).stem
        dst_rel = f"{r['label']}/{stem}.jpg"
        if dst_rel in used_names:  # e.g. 0001.png and 0001.jpg in the same folder
            dst_rel = f"{r['label']}/{stem}_{Path(r['path']).suffix.lstrip('.')}.jpg"
        used_names.add(dst_rel)
        dst = args.out / dst_rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if not dst.exists():
            try:
                load_rgb(src).save(dst, "JPEG", quality=95, optimize=True)
            except Exception as exc:  # noqa: BLE001
                skipped.append({"path": r["path"], "reason": f"conversion failed: {exc}"})
                continue
        split = assignment[r["path"]]
        manifests[split].append(
            {
                "file": dst.relative_to(args.out).as_posix(),
                "label": r["label"],
                "label_index": class_names.index(r["label"]),
                "group_id": r["group_id"],
                "source": r["path"],
            }
        )
        if i % 100 == 0:
            print(f"  processed {i}/{len(usable)}")

    for split, items in manifests.items():
        with (args.splits / f"{split}.csv").open("w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=["file", "label", "label_index", "group_id", "source"])
            w.writeheader()
            w.writerows(items)

    # leakage check: no group may appear in two splits
    group_split: dict[str, set[str]] = defaultdict(set)
    for split, items in manifests.items():
        for it in items:
            group_split[it["group_id"]].add(split)
    leaks = [g for g, s in group_split.items() if len(s) > 1]
    if leaks:
        sys.exit(f"Leakage detected for groups {leaks[:10]}")

    summary = {
        "data_dir": str(args.data_dir),
        "processed_dir": str(args.out),
        "seed": args.seed,
        "fractions": {"train": 1 - args.val - args.test, "val": args.val, "test": args.test},
        "class_names": class_names,
        "counts": {
            split: {c: sum(1 for it in items if it["label"] == c) for c in class_names}
            for split, items in manifests.items()
        },
        "totals": {split: len(items) for split, items in manifests.items()},
        "skipped": skipped,
        "group_leakage": "none",
    }
    write_json(args.splits / "class_names.json", class_names)
    write_json(args.splits / "split_summary.json", summary)
    print(f"Classes: {len(class_names)}  train={summary['totals']['train']} "
          f"val={summary['totals']['val']} test={summary['totals']['test']}  skipped={len(skipped)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
