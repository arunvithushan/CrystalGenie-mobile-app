@echo off
REM Runs the cg.ps1 steps listed in run_steps.txt (one per line), then closes. Logs: logs\<step>.log
cd /d "%~dp0"
if exist "%~dp0logs\run_steps.done" del "%~dp0logs\run_steps.done"
for /f "usebackq tokens=*" %%s in ("%~dp0run_steps.txt") do (
  echo ===== %%s =====
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cg.ps1" %%s
)
echo done> "%~dp0logs\run_steps.done"
