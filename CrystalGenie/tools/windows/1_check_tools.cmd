@echo off
REM Lists installed tools (Python, Flutter, Android SDK, PostgreSQL, GPU). Changes nothing.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0cg.ps1' check *>&1 | Tee-Object -FilePath '%~dp0last_output_check.txt'"
echo.
echo Finished. Log: %~dp0logs\check.log
pause
