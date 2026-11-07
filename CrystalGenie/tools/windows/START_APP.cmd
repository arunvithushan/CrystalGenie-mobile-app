@echo off
REM One click: starts the Crystal Genie API (own window), starts the emulator if needed, then runs the app on it.
REM Keep the "Crystal Genie API" window open while you use the app - closing it stops logins and scans.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cg.ps1" run-app
pause
