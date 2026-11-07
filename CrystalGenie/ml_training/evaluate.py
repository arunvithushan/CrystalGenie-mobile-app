"""Evaluate the trained gemstone model, calibrate confidence and pick an uncertainty threshold.

Outputs (written to ../models and reports/):
  evaluation_report.json   train / validation / held-out test metrics, per-class report,
                           calibration, selective accuracy, out-of-distribution test, latency
  confusion_matrix.png     held-out test confusion matrix (counts and row-normalised)
  model_metadata.json      updated with temperature + confidence threshold

Calibration: temperature scaling fitted on the VALIDATION split (minimises NLL).
Threshold:   the smallest calibrated top-1 confidence for which validation accuracy among
             accepted predictions reaches --target-accuracy (default 0.90); never below 0.5.
             Below the threshold the API reports "Uncertain identification".
OOD check:   non-gemstone images (scikit-image sample photos + synthetic images + optional
             --ood-dir) are scored to see how often they are correctly flagged as uncertain.

Usage:
    python evaluate.py
    python evaluate.py --ood-dir "C:\\path\\to\\non_gem_photos"
"""
from __future__ import annotations

import argparse
import csv
import shutil
import time
from pathlib import Path

import numpy as np

from common import (
    DEFAULT_DATA_DIR,
    IMG_SIZE,
    MODELS_DIR,
    PROCESSED_DIR,
    REPORTS_DIR,
    SPLITS_DIR,
    center_square_np,
    configure_tensorflow,
    load_rgb,
    read_json,
    write_json,
)


# ----------------------------------------------------------------------------- helpers
def to_input(tf, img_uint8: np.ndarray) -> np.ndarray:
    sq = center_square_np(img_uint8)
    t = tf.image.resize(tf.convert_to_tensor(sq, tf.float32), (IMG_SIZE, IMG_SIZE), method="bilinear", antialias=True)
    return tf.clip_by_value(t, 0.0, 255.0).numpy()


def load_split(tf, split: str, splits_dir: Path, processed: Path):
    with (splits_dir / f"{split}.csv").open(encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    x = np.stack([to_input(tf, np.asarray(load_rgb(processed / r["file"]))) for r in rows]) if rows else np.zeros((0, IMG_SIZE, IMG_SIZE, 3))
    y = np.array([int(r["label_index"]) for r in rows])
    return x, y, rows


def apply_temperature(probs: np.ndarray, t: float) -> np.ndarray:
    logits = np.log(np.clip(probs, 1e-12, 1.0)) / t
    logits -= logits.max(axis=1, keepdims=True)
    e = np.exp(logits)
    return e / e.sum(axis=1, keepdims=True)


def nll(probs: np.ndarray, y: np.ndarray) -> float:
    return float(-np.mean(np.log(np.clip(probs[np.arange(len(y)), y], 1e-12, 1.0))))


def fit_temperature(probs: np.ndarray, y: np.ndarray) -> float:
    from scipy.optimize import minimize_scalar

    res = minimize_scalar(lambda t: nll(apply_temperature(probs, t), y), bounds=(0.2, 6.0), method="bounded")
    return float(res.x)


def ece(probs: np.ndarray, y: np.ndarray, bins: int = 10) -> float:
    conf = probs.max(1)
    pred = probs.argmax(1)
    edges = np.linspace(0, 1, bins + 1)
    total = 0.0
    for lo, hi in zip(edges[:-1], edges[1:], strict=True):
        m = (conf > lo) & (conf <= hi)
        if m.any():
            total += m.mean() * abs((pred[m] == y[m]).mean() - conf[m].mean())
    return float(total)


def choose_threshold(probs: np.ndarray, y: np.ndarray, target: float, floor: float = 0.5) -> dict:
    conf = probs.max(1)
    correct = probs.argmax(1) == y
    chosen = None
    curve = []
    for t in np.round(np.arange(0.30, 0.991, 0.01), 2):
        acc_mask = conf >= t
        cov = float(acc_mask.mean())
        acc = float(correct[acc_mask].mean()) if acc_mask.any() else float("nan")
        curve.append({"threshold": float(t), "coverage": cov, "accuracy": acc})
        if chosen is None and acc_mask.any() and acc >= target:
            chosen = float(t)
    if chosen is None:
        chosen = 0.9
    return {"threshold": max(floor, chosen), "target_accuracy": target, "curve": curve}


def selective(probs, y, t):
    conf = probs.max(1)
    m = conf >= t
    return {
        "threshold": t,
        "coverage": float(m.mean()) if len(m) else 0.0,
        "accuracy_on_accepted": float((probs.argmax(1)[m] == y[m]).mean()) if m.any() else None,
        "uncertain_fraction": float(1 - m.mean()) if len(m) else 0.0,
    }


def classification_metrics(probs, y, class_names):
    from sklearn.metrics import (
        accuracy_score,
        classification_report,
        confusion_matrix,
        f1_score,
        precision_score,
        recall_score,
        top_k_accuracy_score,
    )

    pred = probs.argmax(1)
    labels = list(range(len(class_names)))
    return {
        "n": int(len(y)),
        "accuracy": float(accuracy_score(y, pred)),
        "top3_accuracy": float(top_k_accuracy_score(y, probs, k=3, labels=labels)) if len(y) else None,
        "precision_macro": float(precision_score(y, pred, average="macro", zero_division=0, labels=labels)),
        "recall_macro": float(recall_score(y, pred, average="macro", zero_division=0, labels=labels)),
        "f1_macro": float(f1_score(y, pred, average="macro", zero_division=0, labels=labels)),
        "f1_weighted": float(f1_score(y, pred, average="weighted", zero_division=0, labels=labels)),
        "per_class": classification_report(y, pred, labels=labels, target_names=class_names, output_dict=True, zero_division=0),
        "confusion_matrix": confusion_matrix(y, pred, labels=labels).tolist(),
    }


def plot_confusion(cm: np.ndarray, class_names: list[str], out: Path, title: str) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    cmn = cm / np.maximum(cm.sum(axis=1, keepdims=True), 1)
    fig, axes = plt.subplots(1, 2, figsize=(18, 7.8))
    for ax, data, fmt, ttl in ((axes[0], cm, "d", "counts"), (axes[1], cmn, ".2f", "row-normalised (recall)")):
        im = ax.imshow(data, cmap="GnBu")
        ax.set_xticks(range(len(class_names)), labels=class_names, rotation=60, ha="right", fontsize=8)
        ax.set_yticks(range(len(class_names)), labels=class_names, fontsize=8)
        ax.set_xlabel("predicted")
        ax.set_ylabel("true")
        ax.set_title(f"{title} — {ttl}")
        vmax = data.max() if data.size else 1
        for i in range(data.shape[0]):
            for j in range(data.shape[1]):
                v = data[i, j]
                if v:
                    ax.text(j, i, format(v, fmt), ha="center", va="center", fontsize=7,
                            color="white" if v > vmax * 0.6 else "#003249")
        fig.colorbar(im, ax=ax, fraction=0.046)
    fig.tight_layout()
    fig.savefig(out, dpi=130)
    plt.close(fig)


def ood_images(ood_dir: Path | None) -> list[tuple[str, np.ndarray]]:
    """Non-gemstone images used to test the uncertainty threshold."""
    out: list[tuple[str, np.ndarray]] = []
    rng = np.random.default_rng(0)
    try:
        from skimage import data as skdata

        for name in ("astronaut", "coffee", "chelsea", "rocket", "camera", "hubble_deep_field",
                     "immunohistochemistry", "coins", "moon", "page", "text", "brick", "grass", "gravel"):
            try:
                img = getattr(skdata, name)()
                if img.ndim == 2:
                    img = np.stack([img] * 3, -1)
                out.append((f"skimage:{name}", img[..., :3].astype(np.uint8)))
            except Exception:  # noqa: BLE001 - some samples need a download
                pass
    except ImportError:
        pass
    h = w = 320
    out.append(("synthetic:uniform_noise", rng.integers(0, 256, (h, w, 3), dtype=np.uint8)))
    out.append(("synthetic:gaussian_noise", np.clip(rng.normal(128, 40, (h, w, 3)), 0, 255).astype(np.uint8)))
    for name, rgb in {"white": (255, 255, 255), "black": (0, 0, 0), "grey": (128, 128, 128),
                      "red": (220, 30, 30), "green": (30, 180, 60), "blue": (30, 60, 220), "skin": (224, 172, 140)}.items():
        out.append((f"synthetic:solid_{name}", np.full((h, w, 3), rgb, dtype=np.uint8)))
    grad = np.linspace(0, 255, w, dtype=np.uint8)[None, :, None].repeat(h, 0).repeat(3, 2)
    out.append(("synthetic:gradient", grad))
    checker = ((np.indices((h, w)).sum(0) // 20) % 2 * 255).astype(np.uint8)[..., None].repeat(3, 2)
    out.append(("synthetic:checkerboard", checker))
    # random coloured shapes and stripes (busy, colourful, non-gem)
    from PIL import Image, ImageDraw

    for k in range(3):
        im = Image.new("RGB", (w, h), tuple(int(c) for c in rng.integers(0, 256, 3)))
        d = ImageDraw.Draw(im)
        for _ in range(25):
            x0, y0 = rng.integers(0, w, 2)
            d.rectangle([int(x0), int(y0), int(x0 + rng.integers(10, 120)), int(y0 + rng.integers(10, 120))],
                        fill=tuple(int(c) for c in rng.integers(0, 256, 3)))
        out.append((f"synthetic:shapes_{k}", np.asarray(im)))
    stripes = np.zeros((h, w, 3), np.uint8)
    stripes[::8] = 255
    out.append(("synthetic:text_like_stripes", stripes))
    # non-gemstone design assets that ship with the project (person photo, polygon background)
    for extra in (DEFAULT_DATA_DIR.parent / "profile.png", DEFAULT_DATA_DIR.parent / "bg.png"):
        if extra.exists():
            try:
                out.append((f"asset:{extra.name}", np.asarray(load_rgb(extra))))
            except Exception:  # noqa: BLE001
                pass
    if ood_dir and ood_dir.is_dir():
        for p in sorted(ood_dir.iterdir()):
            if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp", ".bmp"}:
                try:
                    out.append((f"user:{p.name}", np.asarray(load_rgb(p))))
                except Exception:  # noqa: BLE001
                    pass
    return out


def l2n(a: np.ndarray) -> np.ndarray:
    return a / np.maximum(np.linalg.norm(a, axis=-1, keepdims=True), 1e-12)


def class_centroids(emb: np.ndarray, y: np.ndarray, n: int) -> np.ndarray:
    e = l2n(emb)
    return l2n(np.stack([e[y == c].mean(0) for c in range(n)]))


def max_similarity(emb: np.ndarray, centroids: np.ndarray) -> np.ndarray:
    return (l2n(emb) @ centroids.T).max(1)


def measure_latency(tf, model, n: int = 30) -> dict:
    x = np.random.default_rng(1).uniform(0, 255, (1, IMG_SIZE, IMG_SIZE, 3)).astype(np.float32)
    for _ in range(5):
        model(x, training=False)
    times = []
    for _ in range(n):
        t0 = time.perf_counter()
        model(x, training=False).numpy()
        times.append((time.perf_counter() - t0) * 1000)
    return {"batch_size": 1, "runs": n, "mean_ms": float(np.mean(times)), "p50_ms": float(np.median(times)),
            "p95_ms": float(np.percentile(times, 95)), "device": "GPU" if tf.config.list_physical_devices("GPU") else "CPU"}


# ----------------------------------------------------------------------------- main
def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", type=Path, default=MODELS_DIR / "gemstone_model.keras")
    ap.add_argument("--processed", type=Path, default=PROCESSED_DIR)
    ap.add_argument("--splits", type=Path, default=SPLITS_DIR)
    ap.add_argument("--batch-size", type=int, default=16)
    ap.add_argument("--target-accuracy", type=float, default=0.90)
    ap.add_argument("--ood-dir", type=Path, default=None)
    ap.add_argument("--ood-percentile", type=float, default=2.0,
                    help="feature-similarity guard: reject below this percentile of validation similarities")
    args = ap.parse_args(argv)

    tf, _, _ = configure_tensorflow(mixed_precision="off")
    model = tf.keras.models.load_model(args.model, compile=False)
    class_names = read_json(args.splits / "class_names.json")

    # One forward pass gives both the softmax and the 1280-d pooled embedding (used by the OOD guard).
    dual = tf.keras.Model(model.inputs, [model.get_layer("avg_pool").output, model.outputs[0]])

    results = {}
    probs_by_split = {}
    emb_by_split = {}
    for split in ("train", "val", "test"):
        x, y, _ = load_split(tf, split, args.splits, args.processed)
        if len(x):
            e, p = dual.predict(x, batch_size=args.batch_size, verbose=0)
        else:
            e, p = np.zeros((0, 1280)), np.zeros((0, len(class_names)))
        probs_by_split[split] = (p.astype(np.float64), y)
        emb_by_split[split] = e.astype(np.float32)
        print(f"{split}: n={len(y)} accuracy={(p.argmax(1) == y).mean():.4f}")

    # ---- feature-similarity OOD guard: cosine similarity to the nearest class centroid
    centroids = class_centroids(emb_by_split["train"], probs_by_split["train"][1], len(class_names))
    sim_val = max_similarity(emb_by_split["val"], centroids)
    sim_threshold = float(np.percentile(sim_val, args.ood_percentile))
    sim_test = max_similarity(emb_by_split["test"], centroids)
    np.save(MODELS_DIR / "class_centroids.npy", centroids.astype(np.float32))
    print(f"OOD similarity threshold={sim_threshold:.3f} (rejects {np.mean(sim_test < sim_threshold):.1%} of test images)")

    pv, yv = probs_by_split["val"]
    temperature = fit_temperature(pv, yv)
    thr = choose_threshold(apply_temperature(pv, temperature), yv, args.target_accuracy)
    threshold = thr["threshold"]
    print(f"temperature={temperature:.3f} threshold={threshold:.2f}")

    for split, (p, y) in probs_by_split.items():
        pc = apply_temperature(p, temperature)
        m = classification_metrics(pc, y, class_names)
        m["nll_raw"], m["nll_calibrated"] = nll(p, y), nll(pc, y)
        m["ece_raw"], m["ece_calibrated"] = ece(p, y), ece(pc, y)
        m["selective"] = selective(pc, y, threshold)
        sims = max_similarity(emb_by_split[split], centroids)
        acc_mask = (pc.max(1) >= threshold) & (sims >= sim_threshold)
        m["selective_with_ood_guard"] = {
            "coverage": float(acc_mask.mean()) if len(acc_mask) else 0.0,
            "accuracy_on_accepted": float((pc.argmax(1)[acc_mask] == y[acc_mask]).mean()) if acc_mask.any() else None,
            "rejected_by_similarity": float((sims < sim_threshold).mean()) if len(sims) else 0.0,
        }
        if split != "test":
            m.pop("per_class")
            m.pop("confusion_matrix")
        results[split] = m

    cm = np.array(results["test"]["confusion_matrix"])
    plot_confusion(cm, class_names, REPORTS_DIR / "confusion_matrix.png", "Held-out test set")
    shutil.copy(REPORTS_DIR / "confusion_matrix.png", MODELS_DIR / "confusion_matrix.png")

    # ---- out-of-distribution behaviour
    ood = ood_images(args.ood_dir)
    ood_rows = []
    if ood:
        x = np.stack([to_input(tf, img) for _, img in ood])
        e, p = dual.predict(x, verbose=0)
        p = apply_temperature(p.astype(np.float64), temperature)
        sims = max_similarity(e, centroids)
        for (name, _), row, sim in zip(ood, p, sims, strict=True):
            k = int(row.argmax())
            low_conf = bool(row[k] < threshold)
            unlike = bool(sim < sim_threshold)
            ood_rows.append({"image": name, "top1": class_names[k], "confidence": float(row[k]),
                             "similarity": float(sim), "low_confidence": low_conf, "unlike_training_data": unlike,
                             "flagged_uncertain": low_conf or unlike})
    ood_summary = {
        "n": len(ood_rows),
        "flagged_uncertain": sum(r["flagged_uncertain"] for r in ood_rows),
        "flagged_fraction": (sum(r["flagged_uncertain"] for r in ood_rows) / len(ood_rows)) if ood_rows else None,
        "mean_confidence": float(np.mean([r["confidence"] for r in ood_rows])) if ood_rows else None,
        "images": ood_rows,
        "flagged_by_confidence_only": sum(r["low_confidence"] for r in ood_rows),
        "flagged_by_similarity": sum(r["unlike_training_data"] for r in ood_rows),
        "note": "A closed-set classifier always picks one of the known classes. Two guards are used: the calibrated "
                "confidence threshold and a feature-similarity check against the class centroids. Images that resemble "
                "gemstones (colourful, glossy objects) can still pass both.",
    }
    print(f"OOD: {ood_summary['flagged_uncertain']}/{ood_summary['n']} non-gemstone images flagged as uncertain")

    latency = measure_latency(tf, model)
    print(f"latency: mean {latency['mean_ms']:.1f} ms, p95 {latency['p95_ms']:.1f} ms ({latency['device']})")

    report = {
        "model": str(args.model.name),
        "class_names": class_names,
        "ood_guard": {"method": "cosine similarity of the pooled EfficientNet embedding to the nearest class centroid",
                      "similarity_threshold": sim_threshold, "percentile_of_validation": args.ood_percentile,
                      "test_in_distribution_rejected": float(np.mean(sim_test < sim_threshold))},
        "calibration": {"method": "temperature scaling on validation split", "temperature": temperature,
                        "confidence_threshold": threshold, "target_accuracy_on_accepted": args.target_accuracy,
                        "threshold_curve_validation": thr["curve"]},
        "train": results["train"],
        "validation": results["val"],
        "test": results["test"],
        "out_of_distribution": ood_summary,
        "latency": latency,
        "notes": [
            "Test split is held out and grouped by near-duplicate hash (no specimen leakage).",
            "Training accuracy is measured without augmentation.",
            "Dataset labels are web-scraped and contain some noise (infographics, a few likely mislabelled photos).",
        ],
    }
    write_json(REPORTS_DIR / "evaluation_report.json", report)
    shutil.copy(REPORTS_DIR / "evaluation_report.json", MODELS_DIR / "evaluation_report.json")

    meta_path = MODELS_DIR / "model_metadata.json"
    meta = read_json(meta_path) if meta_path.exists() else {}
    meta["calibration"] = {"temperature": temperature, "confidence_threshold": threshold,
                           "method": "temperature scaling (validation NLL)", "target_accuracy": args.target_accuracy}
    meta["ood_guard"] = {"method": "cosine similarity to nearest class centroid (avg_pool embedding)",
                         "centroids_file": "class_centroids.npy", "similarity_threshold": sim_threshold,
                         "embedding_layer": "avg_pool"}
    meta["metrics"] = {
        "train_accuracy": results["train"]["accuracy"],
        "val_accuracy": results["val"]["accuracy"],
        "test_accuracy": results["test"]["accuracy"],
        "test_top3_accuracy": results["test"]["top3_accuracy"],
        "test_samples": results["test"]["n"],
        "test_f1_macro": results["test"]["f1_macro"],
        "test_precision_macro": results["test"]["precision_macro"],
        "test_recall_macro": results["test"]["recall_macro"],
        "test_selective": results["test"]["selective"],
        "test_selective_with_ood_guard": results["test"]["selective_with_ood_guard"],
        "ood_flagged_fraction": ood_summary["flagged_fraction"],
        "latency_ms_mean": latency["mean_ms"],
    }
    write_json(meta_path, meta)
    print("Test accuracy {:.4f} | macro F1 {:.4f} | top-3 {:.4f}".format(
        results["test"]["accuracy"], results["test"]["f1_macro"], results["test"]["top3_accuracy"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
