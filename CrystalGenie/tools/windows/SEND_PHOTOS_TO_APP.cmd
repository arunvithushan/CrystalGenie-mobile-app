@echo off
REM Copies the photos in "Photos for Crystal Genie" (next to the CrystalGenie folder) to the running emulator/phone.
REM In the app: Upload, then the album "FromPC".
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cg.ps1" sync-photos
pause
