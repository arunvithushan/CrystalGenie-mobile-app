@echo off
REM Creates Python virtual envs, installs requirements, runs flutter pub get.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0cg.ps1' setup *>&1 | Tee-Object -FilePath '%~dp0last_output_setup.txt'"
echo.
echo Finished. Log: %~dp0logs\setup.log
pause
