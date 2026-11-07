"""Train the Crystal Genie gemstone classifier (EfficientNetV2B0, ImageNet weights).

Phase 1  feature extraction   backbone frozen, train the classification head
Phase 2  fine-tuning          unfreeze the upper backbone blocks (BatchNorm stays frozen),
                              lower learning rate with warm-up + cosine decay
Phase 3  controlled           unfreeze the rest of the backbone (BatchNorm still frozen) with a
                              very low learning rate - ONLY if phase 2 improved validation loss
                              and the train/val gap is acceptable; kept only if it improves again.

The checkpoint with the lowest validation loss across all phases is exported to
../models/gemstone_model.keras, then evaluate.py runs on the held-out test split.

Usage (PowerShell, from CrystalGenie/ml_training, after preprocess.py):
    python train.py                       # sensible defaults for a 4 GB GPU / CPU
    python train.py --batch-size 8        # if you hit GPU out-of-memory
    python train.py --epochs1 3 --epochs2 3 --no-phase3   # quick smoke run
"""
from __future__ import annotations

import argparse
import csv
import math
import platform
import shutil
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from common import (
    CHECKPOINT_DIR,
    IMG_SIZE,
    MODELS_DIR,
    PROCESSED_DIR,
    REPORTS_DIR,
    SEED,
    SPLITS_DIR,
    configure_tensorflow,
    read_json,
    write_json,
)


def read_manifest(path: Path) -> tuple[list[str], list[int]]:
    with path.open(encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    return [r["file"] for r in rows], [int(r["label_index"]) for r in rows]


def build_datasets(tf, processed_dir: Path, splits_dir: Path, num_classes: int, batch_size: int):
    AUTOTUNE = tf.data.AUTOTUNE
    rot = tf.keras.layers.RandomRotation(0.08, fill_mode="reflect", seed=SEED)

    def decode(path):
        raw = tf.io.read_file(path)
        img = tf.io.decode_jpeg(raw, channels=3)
        return img

    def eval_transform(img):
        shape = tf.shape(img)
        h, w = shape[0], shape[1]
        s = tf.minimum(h, w)
        img = tf.image.crop_to_bounding_box(img, (h - s) // 2, (w - s) // 2, s, s)
        img = tf.image.resize(img, (IMG_SIZE, IMG_SIZE), method="bilinear", antialias=True)
        return tf.clip_by_value(img, 0.0, 255.0)

    def train_transform(img):
        begin, size, _ = tf.image.sample_distorted_bounding_box(
            tf.shape(img),
            bounding_boxes=tf.constant([[[0.0, 0.0, 1.0, 1.0]]]),
            min_object_covered=0.25,
            aspect_ratio_range=(0.75, 1.333),
            area_range=(0.40, 1.0),
            max_attempts=20,
            use_image_if_no_bounding_boxes=True,
        )
        img = tf.slice(img, begin, size)
        img = tf.image.resize(img, (IMG_SIZE, IMG_SIZE), method="bilinear", antialias=True)
        img = tf.image.random_flip_left_right(img)
        img = tf.image.random_flip_up_down(img)
        img = tf.image.rot90(img, k=tf.random.uniform([], 0, 4, dtype=tf.int32))
        img = rot(img[None, ...], training=True)[0]
        # Mild photometric jitter. Hue is kept tiny because colour is a key cue for gems.
        img = img / 255.0
        img = tf.image.random_brightness(img, 0.12)
        img = tf.image.random_contrast(img, 0.85, 1.15)
        img = tf.image.random_saturation(img, 0.85, 1.15)
        img = tf.image.random_hue(img, 0.015)
        return tf.clip_by_value(img, 0.0, 1.0) * 255.0

    def make(split: str, training: bool):
        files, labels = read_manifest(splits_dir / f"{split}.csv")
        paths = [str(processed_dir / f) for f in files]
        ds = tf.data.Dataset.from_tensor_slices((paths, labels))
        if training:
            ds = ds.shuffle(len(paths), seed=SEED, reshuffle_each_iteration=True)

        def _load(p, y):
            img = tf.cast(decode(p), tf.float32)
            img = train_transform(img) if training else eval_transform(img)
            return img, tf.one_hot(y, num_classes)

        ds = ds.map(_load, num_parallel_calls=AUTOTUNE)
        if not training:
            ds = ds.cache()
        return ds.batch(batch_size).prefetch(AUTOTUNE), np.array(labels)

    train_ds, y_train = make("train", True)
    val_ds, y_val = make("val", False)
    return train_ds, val_ds, y_train, y_val


def build_model(tf, num_classes: int, dropout: float):
    keras = tf.keras
    base = keras.applications.EfficientNetV2B0(
        include_top=False,
        weights="imagenet",
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_preprocessing=True,  # expects raw 0..255 RGB
    )
    base.trainable = False
    inputs = keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3), name="image")
    x = base(inputs, training=False)  # keeps BatchNorm in inference mode in every phase
    x = keras.layers.GlobalAveragePooling2D(name="avg_pool")(x)
    x = keras.layers.Dropout(dropout, name="head_dropout")(x)
    outputs = keras.layers.Dense(num_classes, activation="softmax", dtype="float32", name="predictions")(x)
    return keras.Model(inputs, outputs, name="crystal_genie_effnetv2b0"), base


def set_trainable(tf, base, mode: str, unfreeze_from: str) -> int:
    """mode: 'frozen' | 'upper' | 'all'. BatchNorm layers are always kept frozen."""
    base.trainable = mode != "frozen"
    started = mode == "all"
    count = 0
    for layer in base.layers:
        if mode == "upper" and layer.name.startswith(unfreeze_from):
            started = True
        trainable = mode != "frozen" and started and not isinstance(layer, tf.keras.layers.BatchNormalization)
        layer.trainable = trainable
        count += int(trainable and bool(layer.weights))
    return count


def compile_model(tf, model, lr, weight_decay, label_smoothing):
    model.compile(
        optimizer=tf.keras.optimizers.AdamW(learning_rate=lr, weight_decay=weight_decay, clipnorm=1.0),
        loss=tf.keras.losses.CategoricalCrossentropy(label_smoothing=label_smoothing),
        metrics=[
            tf.keras.metrics.CategoricalAccuracy(name="accuracy"),
            tf.keras.metrics.TopKCategoricalAccuracy(k=3, name="top3"),
        ],
    )


def warmup_cosine(tf, base_lr: float, total_steps: int, warmup_steps: int):
    keras = tf.keras

    class WarmupCosine(keras.optimizers.schedules.LearningRateSchedule):
        def __init__(self):
            self.base_lr, self.total, self.warm = base_lr, max(1, total_steps), max(1, warmup_steps)

        def __call__(self, step):
            step = tf.cast(step, tf.float32)
            warm = self.base_lr * step / self.warm
            prog = tf.clip_by_value((step - self.warm) / max(1, self.total - self.warm), 0.0, 1.0)
            cos = 0.5 * self.base_lr * (1.0 + tf.cos(math.pi * prog))
            return tf.where(step < self.warm, warm, tf.maximum(cos, self.base_lr * 0.02))

        def get_config(self):
            return {"base_lr": self.base_lr, "total_steps": self.total, "warmup_steps": self.warm}

    return WarmupCosine()


def run_phase(tf, model, name, train_ds, val_ds, epochs, class_weight, lr, args, steps_per_epoch, patience):
    ckpt = CHECKPOINT_DIR / f"{name}_best.keras"
    callbacks = [
        tf.keras.callbacks.ModelCheckpoint(str(ckpt), monitor="val_loss", save_best_only=True, verbose=1),
        tf.keras.callbacks.EarlyStopping(monitor="val_loss", patience=patience, restore_best_weights=True, verbose=1),
        tf.keras.callbacks.CSVLogger(str(REPORTS_DIR / f"history_{name}.csv")),
        tf.keras.callbacks.TerminateOnNaN(),
    ]
    if name == "phase1":
        callbacks.append(tf.keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.3, patience=2, min_lr=1e-6, verbose=1))
        schedule = lr
    else:
        total = steps_per_epoch * epochs
        schedule = warmup_cosine(tf, lr, total, warmup_steps=steps_per_epoch)
    compile_model(tf, model, schedule, args.weight_decay, args.label_smoothing)
    t0 = time.time()
    hist = model.fit(train_ds, validation_data=val_ds, epochs=epochs, class_weight=class_weight, callbacks=callbacks, verbose=2)
    h = {k: [float(v) for v in vals] for k, vals in hist.history.items()}
    best_epoch = int(np.argmin(h["val_loss"]))
    return {
        "name": name,
        "epochs_run": len(h["val_loss"]),
        "best_epoch": best_epoch + 1,
        "best_val_loss": h["val_loss"][best_epoch],
        "best_val_accuracy": h["val_accuracy"][best_epoch],
        "train_accuracy_at_best": h["accuracy"][best_epoch],
        "seconds": round(time.time() - t0, 1),
        "checkpoint": str(ckpt),
        "history": h,
    }


def plot_history(phases: list[dict], out: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(1, 2, figsize=(13, 4.8))
    offset = 0
    colors = {"phase1": "#34A0A3", "phase2": "#003249", "phase3": "#EFAD4F"}
    for ph in phases:
        h = ph["history"]
        xs = np.arange(offset + 1, offset + len(h["loss"]) + 1)
        c = colors.get(ph["name"], "gray")
        axes[0].plot(xs, h["loss"], "--", color=c, label=f"{ph['name']} train")
        axes[0].plot(xs, h["val_loss"], "-", color=c, label=f"{ph['name']} val")
        axes[1].plot(xs, h["accuracy"], "--", color=c, label=f"{ph['name']} train")
        axes[1].plot(xs, h["val_accuracy"], "-", color=c, label=f"{ph['name']} val")
        offset += len(h["loss"])
        for ax in axes:
            ax.axvline(offset + 0.5, color="#bbbbbb", lw=0.8)
    axes[0].set_title("Loss (train dashed, validation solid)")
    axes[1].set_title("Accuracy (train dashed, validation solid)")
    for ax in axes:
        ax.set_xlabel("epoch (cumulative)")
        ax.grid(alpha=0.25)
        ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(out, dpi=140)
    plt.close(fig)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--processed", type=Path, default=PROCESSED_DIR)
    ap.add_argument("--splits", type=Path, default=SPLITS_DIR)
    ap.add_argument("--batch-size", type=int, default=16)
    ap.add_argument("--epochs1", type=int, default=25)
    ap.add_argument("--epochs2", type=int, default=30)
    ap.add_argument("--epochs3", type=int, default=12)
    ap.add_argument("--lr1", type=float, default=1e-3)
    ap.add_argument("--lr2", type=float, default=1e-4)
    ap.add_argument("--lr3", type=float, default=1.5e-5)
    ap.add_argument("--weight-decay", type=float, default=1e-4)
    ap.add_argument("--label-smoothing", type=float, default=0.05)
    ap.add_argument("--dropout", type=float, default=0.35)
    ap.add_argument("--unfreeze-from", default="block5", help="phase-2 unfreezes layers from this block upward")
    ap.add_argument("--no-phase3", action="store_true")
    ap.add_argument("--max-gap", type=float, default=0.15, help="max train-val accuracy gap allowed to start phase 3")
    ap.add_argument("--mixed-precision", choices=["auto", "on", "off"], default="auto")
    ap.add_argument("--no-class-weights", action="store_true")
    ap.add_argument("--skip-eval", action="store_true")
    args = ap.parse_args(argv)

    tf, using_gpu, mp = configure_tensorflow(SEED, args.mixed_precision)
    print(f"TensorFlow {tf.__version__} | GPU: {using_gpu} | mixed precision: {mp}")
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    class_names = read_json(args.splits / "class_names.json")
    num_classes = len(class_names)
    train_ds, val_ds, y_train, y_val = build_datasets(tf, args.processed, args.splits, num_classes, args.batch_size)
    steps = math.ceil(len(y_train) / args.batch_size)
    print(f"{num_classes} classes | train {len(y_train)} | val {len(y_val)} | batch {args.batch_size}")

    class_weight = None
    if not args.no_class_weights:
        from sklearn.utils.class_weight import compute_class_weight

        w = compute_class_weight("balanced", classes=np.arange(num_classes), y=y_train)
        class_weight = {i: float(v) for i, v in enumerate(w)}
        print("class weights:", {class_names[i]: round(v, 2) for i, v in class_weight.items()})

    model, base = build_model(tf, num_classes, args.dropout)
    phases = []

    # ---------------- Phase 1: feature extraction
    set_trainable(tf, base, "frozen", args.unfreeze_from)
    p1 = run_phase(tf, model, "phase1", train_ds, val_ds, args.epochs1, class_weight, args.lr1, args, steps, patience=5)
    phases.append(p1)
    print(f"Phase 1 best val_loss={p1['best_val_loss']:.4f} val_acc={p1['best_val_accuracy']:.4f}")

    # ---------------- Phase 2: fine-tune upper backbone
    n = set_trainable(tf, base, "upper", args.unfreeze_from)
    print(f"Phase 2: {n} backbone layers trainable (BatchNorm frozen)")
    p2 = run_phase(tf, model, "phase2", train_ds, val_ds, args.epochs2, class_weight, args.lr2, args, steps, patience=6)
    phases.append(p2)
    print(f"Phase 2 best val_loss={p2['best_val_loss']:.4f} val_acc={p2['best_val_accuracy']:.4f}")

    # ---------------- Phase 3: controlled further fine-tuning
    phase3_decision = "skipped (--no-phase3)"
    if not args.no_phase3:
        improved = p2["best_val_loss"] < p1["best_val_loss"] - 0.01
        gap = p2["train_accuracy_at_best"] - p2["best_val_accuracy"]
        if improved and gap <= args.max_gap:
            n = set_trainable(tf, base, "all", args.unfreeze_from)
            print(f"Phase 3: {n} backbone layers trainable (BatchNorm frozen), gap={gap:.3f}")
            p3 = run_phase(tf, model, "phase3", train_ds, val_ds, args.epochs3, class_weight, args.lr3, args, steps, patience=4)
            phases.append(p3)
            phase3_decision = (
                "ran and improved validation loss" if p3["best_val_loss"] < p2["best_val_loss"] else
                "ran but did not improve validation loss; phase-2 checkpoint kept"
            )
        else:
            phase3_decision = (
                f"skipped: phase-2 val-loss improvement={p1['best_val_loss'] - p2['best_val_loss']:.4f}, "
                f"train-val gap={gap:.3f} (max {args.max_gap})"
            )
    print("Phase 3:", phase3_decision)

    best = min(phases, key=lambda p: (p["best_val_loss"], -p["best_val_accuracy"]))
    print(f"Best checkpoint: {best['name']} (val_loss={best['best_val_loss']:.4f}, val_acc={best['best_val_accuracy']:.4f})")
    best_model = tf.keras.models.load_model(best["checkpoint"], compile=False)
    # Save with a float32 policy-agnostic graph (mixed precision layers still load fine on CPU).
    model_path = MODELS_DIR / "gemstone_model.keras"
    best_model.save(model_path)
    shutil.copy(args.splits / "class_names.json", MODELS_DIR / "class_names.json")

    plot_history(phases, REPORTS_DIR / "training_history.png")
    shutil.copy(REPORTS_DIR / "training_history.png", MODELS_DIR / "training_history.png")

    import sklearn  # noqa: F401

    version = "cg-effv2b0-" + datetime.now(timezone.utc).strftime("%Y%m%d-%H%M")
    split_summary = read_json(args.splits / "split_summary.json")
    metadata = {
        "model_version": version,
        "architecture": "EfficientNetV2B0 (ImageNet pretrained) + GAP + Dropout + Dense softmax",
        "input_size": [IMG_SIZE, IMG_SIZE, 3],
        "input_range": "RGB float32 0..255 (normalisation is inside the model)",
        "preprocessing": [
            "EXIF transpose, RGB (alpha composited on white)",
            "downscale short side to <= 512 px (Lanczos)",
            "centre square crop, resize to 224x224 (bilinear, antialias)",
        ],
        "class_names": class_names,
        "num_classes": num_classes,
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "framework": {"tensorflow": tf.__version__, "keras": tf.keras.__version__ if hasattr(tf.keras, "__version__") else None,
                      "python": platform.python_version()},
        "hardware": {"gpu": using_gpu, "mixed_precision": mp, "platform": platform.platform()},
        "hyperparameters": {k: (str(v) if isinstance(v, Path) else v) for k, v in vars(args).items()},
        "class_weights": class_weight,
        "dataset": {"totals": split_summary["totals"], "counts": split_summary["counts"], "skipped": len(split_summary["skipped"])},
        "phases": [{k: v for k, v in p.items() if k != "history"} for p in phases],
        "phase3_decision": phase3_decision,
        "selected_phase": best["name"],
        "calibration": {"temperature": 1.0, "confidence_threshold": 0.5, "note": "updated by evaluate.py"},
    }
    write_json(MODELS_DIR / "model_metadata.json", metadata)
    write_json(REPORTS_DIR / "training_phases.json", phases)
    print(f"Saved {model_path}")

    if not args.skip_eval:
        import evaluate

        evaluate.main(["--batch-size", str(args.batch_size)])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
