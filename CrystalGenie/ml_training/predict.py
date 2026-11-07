"""Predict the gemstone in one or more images with the trained model.

Uses exactly the same preprocessing, temperature calibration and uncertainty threshold
as the FastAPI backend (backend/app/ml/classifier.py).

Usage:
    python predict.py path\\to\\photo.jpg [more.jpg ...]
    python predict.py photo.jpg --model ..\\models\\gemstone_model.keras --top-k 3
"""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np

from common import IMG_SIZE, MODELS_DIR, center_square_np, configure_tensorflow, load_rgb, read_json


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("images", nargs="+", type=Path)
    ap.add_argument("--model", type=Path, default=MODELS_DIR / "gemstone_model.keras")
    ap.add_argument("--metadata", type=Path, default=MODELS_DIR / "model_metadata.json")
    ap.add_argument("--top-k", type=int, default=3)
    args = ap.parse_args(argv)

    tf, _, _ = configure_tensorflow(mixed_precision="off")
    model = tf.keras.models.load_model(args.model, compile=False)
    meta = read_json(args.metadata)
    class_names = meta["class_names"]
    temperature = float(meta.get("calibration", {}).get("temperature", 1.0))
    threshold = float(meta.get("calibration", {}).get("confidence_threshold", 0.5))
    ood = meta.get("ood_guard") or {}
    centroids_path = args.model.parent / ood.get("centroids_file", "class_centroids.npy")
    dual = centroids = None
    sim_thr = ood.get("similarity_threshold")
    if sim_thr is not None and centroids_path.exists():
        dual = tf.keras.Model(model.inputs, [model.get_layer(ood.get("embedding_layer", "avg_pool")).output, model.outputs[0]])
        centroids = np.load(centroids_path)

    for path in args.images:
        t0 = time.perf_counter()
        arr = center_square_np(np.asarray(load_rgb(path)))
        x = tf.image.resize(tf.convert_to_tensor(arr, tf.float32), (IMG_SIZE, IMG_SIZE), antialias=True)
        x = tf.clip_by_value(x, 0.0, 255.0)[None, ...]
        similarity = None
        if dual is not None:
            emb, out = dual(x, training=False)
            p = out.numpy()[0].astype(np.float64)
            e = emb.numpy()[0]
            similarity = float((centroids @ (e / max(np.linalg.norm(e), 1e-12))).max())
        else:
            p = model(x, training=False).numpy()[0].astype(np.float64)
        logits = np.log(np.clip(p, 1e-12, 1)) / temperature
        p = np.exp(logits - logits.max())
        p /= p.sum()
        order = np.argsort(-p)[: args.top_k]
        top = [{"class_name": class_names[i], "confidence": round(float(p[i]), 4)} for i in order]
        print(json.dumps({
            "image": str(path),
            "prediction": top[0]["class_name"],
            "confidence": top[0]["confidence"],
            "is_uncertain": top[0]["confidence"] < threshold or (similarity is not None and similarity < float(sim_thr)),
            "threshold": threshold,
            "similarity": None if similarity is None else round(similarity, 4),
            "similarity_threshold": sim_thr,
            "top_k": top,
            "latency_ms": round((time.perf_counter() - t0) * 1000, 1),
        }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
