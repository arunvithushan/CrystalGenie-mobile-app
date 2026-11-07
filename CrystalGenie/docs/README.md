# CrystalGenie

This project contains the mobile Flutter app, the FastAPI backend, and the gemstone model training pipeline for Crystal Genie.

## Structure

- `mobile/` – Flutter app
- `backend/` – FastAPI services and data layer
- `ml_training/` – dataset inspection and TensorFlow training scripts
- `images/` – local gemstone dataset copied from the user source folder

## Quick start

1. Create and activate a Python virtual environment.
2. Install backend dependencies: `pip install -r backend/requirements.txt`
3. Start the API: `uvicorn backend.app.main:app --reload --host 0.0.0.0 --port 8000`
4. Run Flutter: `cd mobile && flutter pub get && flutter run`

This repository intentionally uses SQLite for local development and PostgreSQL-compatible models for production deployment.
