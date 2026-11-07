@echo off
REM Runs everything: setup, model evaluation, database, backend tests, API end-to-end check, Flutter tests, APK build.
REM Takes 20-40 minutes. If PostgreSQL is installed you will be asked for the postgres password once at the start.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0cg.ps1' all *>&1 | Tee-Object -FilePath '%~dp0last_output_all.txt'"
echo.
echo Finished. Logs: %~dp0logs
pause
