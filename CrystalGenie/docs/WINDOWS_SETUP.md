# Crystal Genie — Windows setup & run guide (PowerShell)

All commands assume the project lives at `C:\Users\ASUS\Desktop\arun\CrystalGenie` and are run in
**Windows PowerShell** or the VS Code terminal (PowerShell). Lines starting with `#` are comments.

| Part | Folder | Python env |
|---|---|---|
| ML training | `ml_training\` | `ml_training\.venv` |
| Backend API | `backend\` | `backend\.venv` |
| Mobile app | `mobile\` | (Flutter) |
| Trained model | `models\` | — |

## One-click helpers

`tools\windows\` contains double-click scripts that run the commands below and write logs to
`tools\windows\logs\`:

| Script | What it does |
|---|---|
| `0_RUN_EVERYTHING.cmd` | setup → evaluate model → database → backend tests → API end-to-end check → Flutter tests → APKs |
| `1_check_tools.cmd` | lists Python / Flutter / Android SDK / PostgreSQL / GPU (changes nothing) |
| `2_setup.cmd` | creates both Python venvs, installs requirements, `flutter pub get` |
| `3_train_model.cmd` | inspect + preprocess + train + evaluate |
| `4_setup_database.cmd` | PostgreSQL role/databases, `.env`, migrations, seed (asks for the postgres password) |
| `5_test_backend.cmd` · `6_e2e_api_check.cmd` · `7_test_flutter.cmd` · `8_build_apk.cmd` | tests and builds |
| `run_backend.cmd` | starts the API on port 8000 for the app |

---

## 0. Prerequisites (one time)

| Tool | Version | Check |
|---|---|---|
| Python | 3.10.x (64-bit) | `py -3.10 --version` |
| PostgreSQL | 15 or 16 | `psql --version` |
| Flutter | 3.27 or newer (stable) | `flutter --version` |
| Android Studio | with Android SDK 34/35, SDK Command-line tools, an emulator | `flutter doctor -v` |
| Git | any | `git --version` |

```powershell
# Allow local virtual-env activation scripts (once per user)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# Go to the project
cd C:\Users\ASUS\Desktop\arun\CrystalGenie
```

Install PostgreSQL from https://www.postgresql.org/download/windows/ (remember the `postgres` password you set),
or with winget: `winget install PostgreSQL.PostgreSQL.16`.

---

## 1. Flutter project

The Flutter project is already in `mobile\` (lib, tests, Android config). To (re)generate any missing
platform boilerplate **without overwriting the existing code**:

```powershell
cd C:\Users\ASUS\Desktop\arun\CrystalGenie\mobile
flutter create --platforms=android --org com.crystalgenie --project-name crystal_genie .
flutter pub get
```

> `flutter create .` only adds files that do not exist yet (e.g. `gradlew`, `local.properties`).
> If it ever asks to overwrite, answer **no**.

---

## 2. Python virtual environments

```powershell
# ---- ML training env
cd C:\Users\ASUS\Desktop\arun\CrystalGenie\ml_training
py -3.10 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
deactivate

# ---- Backend env
cd C:\Users\ASUS\Desktop\arun\CrystalGenie\backend
py -3.10 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

---

## 3. GPU check

```powershell
cd C:\Users\ASUS\Desktop\arun\CrystalGenie\ml_training
.\.venv\Scripts\Activate.ps1
nvidia-smi
python -c "import tensorflow as tf; print(tf.__version__, tf.config.list_physical_devices('GPU'))"
```

**Important — TensorFlow and Windows GPUs:** TensorFlow 2.11+ does **not** support CUDA GPUs on native
Windows. On native Windows the line above prints `[]` and training runs on the CPU. That is fine for this
dataset (~1,000 images; roughly 30–60 minutes on a laptop CPU). To use the RTX 3050:

### GPU training with WSL2 (optional)
```powershell
wsl --install -d Ubuntu-22.04        # once, then reboot and create the Ubuntu user
```
Inside Ubuntu (the Windows NVIDIA driver already provides CUDA to WSL2 — do **not** install a Linux driver):
```bash
sudo apt update && sudo apt install -y python3.10-venv python3-pip
cd /mnt/c/Users/ASUS/Desktop/arun/CrystalGenie/ml_training
python3.10 -m venv .venv-wsl && source .venv-wsl/bin/activate
pip install --upgrade pip
pip install "tensorflow[and-cuda]==2.17.1" numpy==1.26.4 scipy==1.13.1 scikit-learn==1.5.2 scikit-image==0.24.0 pillow==11.3.0 matplotlib==3.9.3 opencv-python-headless==4.10.0.84
python -c "import tensorflow as tf; print(tf.config.list_physical_devices('GPU'))"
export CG_DATA_DIR=/mnt/c/Users/ASUS/Desktop/arun/images/a
python train.py --batch-size 16      # mixed precision is enabled automatically on GPU
```
4 GB VRAM: batch 16 at 224×224 fits EfficientNetV2-B0 with mixed precision. If you see
`ResourceExhaustedError` / OOM, use `--batch-size 8`.

---

## 4. Inspect the dataset

```powershell
cd C:\Users\ASUS\Desktop\arun\CrystalGenie\ml_training
.\.venv\Scripts\Activate.ps1
python inspect_dataset.py --data-dir "C:\Users\ASUS\Desktop\arun\images\a" --out reports
# -> reports\dataset_report.md, dataset_report.json, image_hashes.csv
```

## 5. Preprocess + split (originals are never modified)

```powershell
python preprocess.py --data-dir "C:\Users\ASUS\Desktop\arun\images\a"
# -> data\processed\<class>\*.jpg  and  data\splits\{train,val,test}.csv, class_names.json, split_summary.json
```
Optional: list images to quarantine (infographics, mislabelled photos) in `exclude.txt`, then re-run.

## 6. Train + evaluate

```powershell
python train.py                      # phases 1-3, then evaluate.py runs automatically
# quick smoke run:  python train.py --epochs1 2 --epochs2 2 --no-phase3
# re-evaluate only: python evaluate.py
# predict a photo:  python predict.py "C:\path\to\photo.jpg"
```
Outputs in `..\models\`: `gemstone_model.keras`, `class_names.json`, `model_metadata.json`,
`evaluation_report.json`, `confusion_matrix.png`, `training_history.png`.

---

## 7. Create the database

```powershell
# Open psql as the postgres superuser (enter the password you chose during install)
psql -U postgres
```
```sql
CREATE ROLE crystal WITH LOGIN PASSWORD 'crystal_dev_password';
CREATE DATABASE crystal_genie OWNER crystal;
CREATE DATABASE crystal_genie_test OWNER crystal;
\q
```
If `psql` is not found, add `C:\Program Files\PostgreSQL\16\bin` to PATH (see Troubleshooting).

## 8. Configure + migrate + seed

```powershell
cd C:\Users\ASUS\Desktop\arun\CrystalGenie\backend
.\.venv\Scripts\Activate.ps1
Copy-Item .env.example .env
# Generate a secret and paste it into .env as JWT_SECRET=...
python -c "import secrets; print(secrets.token_urlsafe(64))"
notepad .env

alembic upgrade head               # creates all tables
python -m app.database.seed        # loads the 13 verified gemstone library entries
```

## 9. Start FastAPI

```powershell
# Emulator only (localhost):
uvicorn app.main:app --reload --port 8000
# Emulator AND physical phone on the same Wi-Fi (listens on your LAN IP):
uvicorn app.main:app --host 0.0.0.0 --port 8000
```
- API docs: http://127.0.0.1:8000/docs
- Health: http://127.0.0.1:8000/api/health  (`model_loaded` must be `true`)
- Allow Python through **Windows Defender Firewall** (private networks) when prompted, otherwise a phone
  cannot connect.

## 10. Backend tests

```powershell
cd C:\Users\ASUS\Desktop\arun\CrystalGenie\backend
.\.venv\Scripts\Activate.ps1
pytest                              # uses TEST_DATABASE_URL (PostgreSQL) from .env
# end-to-end check with the real model (server must be running):
python scripts\e2e_smoke.py --base-url http://127.0.0.1:8000 --image ..\ml_training\data\processed\Rose_Quartz\000037.jpg
```

---

## 11. Run the Flutter app

```powershell
cd C:\Users\ASUS\Desktop\arun\CrystalGenie\mobile
flutter pub get
flutter devices

# Android emulator (10.0.2.2 = your PC's localhost; this is the default):
flutter run

# Physical phone (USB debugging on, same Wi-Fi as the PC). Find your PC IP with: ipconfig
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
```
You can also change the server address inside the app: **Login → Server settings** (with a *Test* button).
Never use `localhost` from a physical phone — it points at the phone itself.

## 12. Flutter tests

```powershell
flutter analyze
flutter test                                        # unit + widget tests (fake repositories)
# Full end-to-end on an emulator against the real backend + model:
flutter test integration_test/app_e2e_test.dart --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## 13. Build APKs

```powershell
# Debug APK
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.20:8000
# -> build\app\outputs\flutter-apk\app-debug.apk

# Release APK (signed with the debug key unless android\key.properties exists)
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.20:8000
# -> build\app\outputs\flutter-apk\app-release.apk

# Install on a connected phone
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

### Release signing (for distribution)
```powershell
keytool -genkey -v -keystore $env:USERPROFILE\crystal-genie-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias crystalgenie
```
Create `mobile\android\key.properties` (never commit it):
```
storePassword=<password>
keyPassword=<password>
keyAlias=crystalgenie
storeFile=C:\\Users\\ASUS\\crystal-genie-release.jks
```
For a production HTTPS backend also set `cg.allowCleartext=false` in `mobile\android\gradle.properties`.

---

## Troubleshooting (Windows)

| Problem | Fix |
|---|---|
| `flutter` is not recognized | Add `C:\src\flutter\bin` (your Flutter folder) to PATH: *Start → "Edit the system environment variables" → Environment Variables → Path → New*, then open a new terminal. |
| `psql` is not recognized | Add `C:\Program Files\PostgreSQL\16\bin` to PATH the same way. |
| `Activate.ps1 cannot be loaded because running scripts is disabled` | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| `py -3.10` not found | Install Python 3.10 (64-bit) from python.org and tick *Add to PATH*; or use the full path `C:\Users\ASUS\AppData\Local\Programs\Python\Python310\python.exe`. |
| `flutter doctor` → Android SDK / licenses | Android Studio → *More Actions → SDK Manager*: install *Android SDK Platform 35*, *Command-line Tools*, *Build-Tools*. Then `flutter config --android-sdk "$env:LOCALAPPDATA\Android\Sdk"` and `flutter doctor --android-licenses`. |
| Gradle: `Unsupported class file major version` / JDK errors | Use the JDK bundled with Android Studio: `flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"`. |
| Gradle download is slow / fails | Check proxy/firewall; delete `%USERPROFILE%\.gradle\wrapper\dists\gradle-8.14.3-all` and retry. |
| `tf.config.list_physical_devices('GPU')` is `[]` | Expected on native Windows (see §3). Use WSL2 for GPU, or train on CPU. |
| GPU out of memory (WSL2) | `python train.py --batch-size 8`; close other GPU apps; mixed precision is already on. |
| `model_loaded: false` in /api/health | Check `MODEL_DIR` in `.env` points to `..\models` and that `gemstone_model.keras` exists; see the server log line `model not loaded: ...`. |
| Phone cannot reach the API | Start uvicorn with `--host 0.0.0.0`, allow Python in Windows Firewall (Private), use the PC's Wi-Fi IPv4 from `ipconfig`, and make sure phone and PC are on the same network. |
| `password authentication failed for user "crystal"` | Re-run the SQL in §7 or fix `DATABASE_URL` in `.env`. |
| Camera black screen on emulator | In AVD Manager set *Back camera → Webcam0* or *VirtualScene*, or use the gallery button. |
| `Your project's Gradle version (…) is lower than Flutter's minimum` | Already fixed for Flutter 3.47: Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.20 (`android/gradle/wrapper/gradle-wrapper.properties`, `android/settings.gradle.kts`). Flutter warns these "will soon be dropped"; moving to AGP 9 / Gradle 9 needs plugin updates (camera, image_cropper, permission_handler) first. |
| `Building with plugins requires symlink support` | Settings → System → For developers → **Developer Mode** On. |
| Running `flutter create .` again adds `kotlin\com\crystalgenie\crystal_genie\MainActivity.kt` | Delete that duplicate; the real activity is `com.crystalgenie.app.MainActivity`. `cg.ps1 setup` no longer re-runs `flutter create`. |
