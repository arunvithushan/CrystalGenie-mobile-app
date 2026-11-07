@echo off
REM Builds debug and release APKs.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0cg.ps1' build-apk *>&1 | Tee-Object -FilePath '%~dp0last_output_build-apk.txt'"
echo.
echo Finished. Log: %~dp0logs\build-apk.log
pause
