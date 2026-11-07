# Crystal Genie — AI gemstone identification

Flutter mobile app + FastAPI backend + PostgreSQL + an EfficientNetV2-B0 gemstone classifier trained on your
own dataset (13 classes, 961 photos).

```
CrystalGenie/
├─ mobile/            Flutter app (Riverpod, GoRouter, Dio, camera, image_picker, secure storage)
│  ├─ lib/app/        theme (Figma tokens), router, app widget
│  ├─ lib/core/       config (API base URL), Dio client + token refresh, storage
│  ├─ lib/features/   auth · splash · home · camera · results · explore · saved · profile
│  ├─ lib/shared/     models, glass widgets, cards, icons, paging controller
│  ├─ test/           unit + widget tests (fake repositories)
│  └─ integration_test/  full E2E against the real backend + model
├─ backend/           FastAPI + SQLAlchemy 2 + Alembic + Argon2 + JWT/refresh rotation
│  ├─ app/            api/ core/ database/ ml/ models/ schemas/ services/ data/
│  ├─ alembic/        migrations (0001_initial)
│  ├─ static/gemstones/  library images
│  ├─ tests/          pytest suite (PostgreSQL) + real-model tests
│  └─ scripts/e2e_smoke.py   API end-to-end check with the real model
├─ ml_training/       inspect_dataset.py · preprocess.py · train.py · evaluate.py · predict.py
├─ models/            gemstone_model.keras + class_names.json + model_metadata.json + reports
└─ docs/              WINDOWS_SETUP.md (all PowerShell commands) · figma_reference/ (captured frames)
```

Start here: **[docs/WINDOWS_SETUP.md](docs/WINDOWS_SETUP.md)**.

## Run the app (one click)

Double-click `tools\windows\START_APP.cmd`. It starts the API in its own window ("Crystal Genie API"; keep it open),
starts the emulator if none is running, and runs this app on it with the right server address
(`http://10.0.2.2:8000` on the emulator, your PC's Wi-Fi IP on a phone).

The app is **Crystal Genie** with package id `com.crystalgenie.app`. The emulator also has an older, unrelated
`com.example.crystal_genie` app (from `Desktop\crystal_genie_app`) - that one does not talk to this backend, so its
login just waits. If login here says "Can't reach the Crystal Genie server at ...", the API window isn't running.

## Browse every photo on your computer ("This computer")

In the app tap **Upload > This computer** (or the laptop icon on the scan screen). You see your user folder
(C:\Users\ASUS) and your other drives (D:\ ...); open any folder and tap a photo to identify it. The backend reads the
photos for the app - read-only, JPG/PNG/WEBP only, hidden/system folders (AppData, Windows, Program Files, .git ...)
are skipped. It is switched on in `backend/.env` with `PC_BROWSE_ENABLED=true` and only answers requests from this PC
(the emulator). For a real phone on your Wi-Fi also set `PC_BROWSE_ALLOW_LAN=true` (then any signed-in account on your
network could browse your photos). `PC_BROWSE_ROOTS=C:\Users\ASUS\Pictures;D:\Gems` limits it to chosen folders.
It is refused in production (`APP_ENV=production`).

## Use photos from your computer

Put JPG/PNG/WEBP photos in `C:\Users\ASUS\Desktop\arun\Photos for Crystal Genie`. While the app is running
(START_APP.cmd starts a small minimized "photo sync" window), new photos are copied to the emulator within ~5 seconds;
in the app tap **Upload** and they are the newest photos at the top (album *FromPC*). Pick one and press **Done**.
To copy right away, double-click `tools\windows\SEND_PHOTOS_TO_APP.cmd`. The emulator's back camera is your laptop
webcam (`hw.camera.back=webcam0`); `tools\windows\cg.ps1 emu-setup` re-applies it and adds 26 held-out test photos.

## How a prediction works
1. The app uploads the photo (`multipart/form-data`) to `POST /api/predict` with the user's bearer token.
2. The API checks size (≤10 MB), real image format (JPEG/PNG/WEBP via Pillow — not the file name),
   pixel count before decoding (decompression-bomb guard) and minimum size; strips EXIF/GPS on storage.
3. Preprocessing is identical to evaluation: EXIF-rotate → RGB → short side ≤512 → centre square →
   224×224 → raw 0–255 into EfficientNetV2 (normalisation is inside the model).
4. Softmax is temperature-calibrated (fitted on the validation split). If the calibrated top-1 confidence is
   below the threshold chosen by `evaluate.py`, the API returns `is_uncertain=true` and the app shows
   **"Uncertain identification"** with photo tips instead of pretending.
5. The prediction (top-3, confidence, threshold, model version, latency, quality warnings from OpenCV)
   is stored for the user and joined with the verified gemstone library entry.

If the model files are missing, `/api/predict` returns **503** — there is no fake/random fallback.

## API
| Group | Endpoints |
|---|---|
| Auth | `POST /api/auth/register` `login` `refresh` `logout` `forgot-password` `reset-password` (+ `change-password`) |
| Users | `GET/PATCH/DELETE /api/users/me`, `POST /api/users/avatar`, `GET /api/users/me/avatar`, `GET/PATCH /api/users/settings` |
| Predictions | `POST /api/predict`, `GET /api/predictions`, `GET/DELETE /api/predictions/{id}`, `GET /api/predictions/{id}/image` |
| Library | `GET /api/gemstones`, `/api/gemstones/search`, `/api/gemstones/categories`, `/api/gemstones/colors`, `/api/gemstones/{id}` |
| Saved / Favorites | `GET/POST /api/saved`, `DELETE /api/saved/{id}`, `GET/POST /api/favorites`, `DELETE /api/favorites/{id}` |
| System | `GET /api/health`, `GET /api/model/status` |

Errors are always `{"error": {"code", "message", "details", "request_id"}}`. Interactive docs: `/docs`.

## Database (PostgreSQL, Alembic)
`users` · `user_settings` · `refresh_tokens` (hashed, rotated, family revocation on reuse) ·
`password_reset_tokens` (hashed 8-char codes, 20-min expiry, 5 attempts) · `gemstones` ·
`predictions` · `saved_crystals` · `favorites` — UUID keys, FKs with `ON DELETE CASCADE`,
unique constraints (case-insensitive e-mail, one save per prediction, one favourite per gem), indexes,
timestamps. Every query on user data is filtered by the authenticated user (ownership → 404).

## Security
Argon2id password hashing · 15-min HS256 access tokens with token-version revocation · opaque refresh
tokens stored as keyed SHA-256 hashes, rotated on every use with reuse detection · tokens in Android
Keystore-backed secure storage · rate limiting on auth endpoints · no account enumeration · strict upload
validation · EXIF stripped · CORS allow-list · secrets only from `.env` · production config guard ·
JSON logs with request ids and secret scrubbing · protected media served only to the owner.

## Gemstone facts
`backend/app/data/gemstones.json` holds the 13 library entries for the classes in your dataset
(formula, Mohs hardness, family, typical sources, care) with reference links. Traditional/metaphysical
meanings are kept in a separate field and always labelled in the app as **cultural beliefs, not scientific
or medical claims**.

## Design
Recreated from the Figma file (captured frames in `docs/figma_reference/`): Playfair Display + Montserrat,
mint/turquoise palette, frosted-glass cards, large teal titles behind glass header pills, floating
Home · Scan · Explore navigation, list + tiles layouts, the original splash artwork and genie logo.
The Figma file has no login/register screens; those were designed in the same visual language.

See the bottom of this file for the current verification status.

## Verification status (honest, as of 19 Oct 2026 — all run on this PC)

| Item | Status | Evidence |
|---|---|---|
| Dataset inspection | ✅ run | `ml_training/reports/dataset_report.md` — 961 images, 13 classes, 0 corrupt, 5 near-duplicate pairs |
| Preprocessing + leakage-free split | ✅ run | 671 / 145 / 145, no near-duplicate group shared between splits |
| Model training (EfficientNetV2-B0, phases 1–2; phase 3 skipped by rule) | ✅ run on this PC (CPU, TF 2.17.1) | `models/model_metadata.json`, `training_history.png` |
| Held-out test metrics | ✅ measured | accuracy **86.9%**, macro F1 **0.865**, top-3 **96.6%** (train 100% / val 84.1% — the model overfits the small dataset) |
| Calibration + uncertainty | ✅ | temperature 0.70, confidence threshold 0.54 |
| Non-gemstone (OOD) guard | ✅ measured | feature-similarity guard (`class_centroids.npy`, threshold 0.205): **28/31** non-gem images flagged uncertain; rejects 3.4% of real test gems |
| Inference latency | ✅ | mean 377 ms, p95 496 ms (CPU) |
| Backend tests (pytest) | ✅ **48/48 pass** | `tools\windows\logs\test-backend.log` (found + fixed a decompression-bomb crash) |
| API end-to-end with the real model | ✅ 11/11 steps | `tools\windows\logs\e2e.log` — Rose Quartz 97.3%, data persists after logout/login |
| Flutter analyze | ✅ no issues | `tools\windows\logs\test-flutter.log` |
| Flutter widget tests | ✅ **35/35 pass** | same log |
| App end-to-end on Android emulator (real backend + model) | ✅ pass | `tools\windows\logs\e2e-app.log` — register → scan (gallery pick) → real prediction → save → favorite → logout/login → persisted |
| Debug + release APK | ✅ built | `mobile\build\app\outputs\flutter-apk\app-debug.apk`, `app-release.apk` (61.5 MB) |
| Physical phone camera capture | ⏳ manual | install the APK, use Login › Server settings to point at `http://<PC LAN IP>:8000` |
| Database | SQLite dev DB used for these runs | PostgreSQL path ready: `tools\windows\4_setup_database.cmd` |

Re-run any step by double-clicking the numbered `.cmd` files, or list steps (e.g. `test-backend`, `e2e-app`)
in `tools\windows\run_steps.txt` and double-click `9_run_steps.cmd`.

`tools\windows\0_RUN_EVERYTHING.cmd` runs every pending item and writes logs to `tools\windows\logs\`.
Per-class test F1: Libyan Desert Glass 1.00, Herkimer 0.96, Tiger's Eye 0.96, Lapis 0.92, Red Jasper 0.92,
Smoky Quartz 0.86, Red Beryl 0.85, Goldstone 0.84, Rose Quartz 0.83, Garnet 0.80, Obsidian 0.78, Hematite 0.77,
Shungite 0.75 (the dataset is web-scraped; some images are infographics or likely mislabelled — see
`ml_training/exclude.txt` to quarantine them and retrain).
