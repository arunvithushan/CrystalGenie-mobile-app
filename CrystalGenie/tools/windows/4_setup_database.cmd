@echo off
REM Creates the PostgreSQL role/databases, backend\.env, runs migrations and seeds gemstones. Asks for the postgres password.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0cg.ps1' dbinit *>&1 | Tee-Object -FilePath '%~dp0last_output_dbinit.txt'"
echo.
echo Finished. Log: %~dp0logs\dbinit.log
pause
