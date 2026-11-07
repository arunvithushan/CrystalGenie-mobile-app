@echo off
REM Starts the API for the app (port 8000, reachable from emulator and phone).
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0cg.ps1' run-backend *>&1 | Tee-Object -FilePath '%~dp0last_output_run-backend.txt'"
echo.
echo Finished. Log: %~dp0logs\run-backend.log
pause
