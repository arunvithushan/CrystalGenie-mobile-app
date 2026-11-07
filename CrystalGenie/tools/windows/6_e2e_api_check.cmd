@echo off
REM Starts the API with the real model and runs the end-to-end API workflow.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0cg.ps1' e2e *>&1 | Tee-Object -FilePath '%~dp0last_output_e2e.txt'"
echo.
echo Finished. Log: %~dp0logs\e2e.log
pause
