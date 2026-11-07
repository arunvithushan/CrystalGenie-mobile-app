@echo off
REM Inspects + preprocesses the dataset and trains/evaluates the model (CPU on Windows: 30-90 min).
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0cg.ps1' train *>&1 | Tee-Object -FilePath '%~dp0last_output_train.txt'"
echo.
echo Finished. Log: %~dp0logs\train.log
pause
