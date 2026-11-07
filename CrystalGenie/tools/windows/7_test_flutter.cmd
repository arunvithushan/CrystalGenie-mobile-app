@echo off
REM flutter analyze + flutter test.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0cg.ps1' test-flutter *>&1 | Tee-Object -FilePath '%~dp0last_output_test-flutter.txt'"
echo.
echo Finished. Log: %~dp0logs\test-flutter.log
pause
