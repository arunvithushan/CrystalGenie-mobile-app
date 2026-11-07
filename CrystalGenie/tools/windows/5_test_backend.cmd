@echo off
REM Runs the backend pytest suite.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0cg.ps1' test-backend *>&1 | Tee-Object -FilePath '%~dp0last_output_test-backend.txt'"
echo.
echo Finished. Log: %~dp0logs\test-backend.log
pause
