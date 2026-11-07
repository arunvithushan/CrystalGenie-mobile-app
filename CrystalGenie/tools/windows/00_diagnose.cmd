@echo off
REM Diagnostic: writes diag.txt next to this file. Changes nothing else.
cd /d "%~dp0"
echo ==== diag %DATE% %TIME% > diag.txt
ver >> diag.txt 2>&1
echo dp0=%~dp0 >> diag.txt
where powershell >> diag.txt 2>&1
where pwsh >> diag.txt 2>&1
where py >> diag.txt 2>&1
where python >> diag.txt 2>&1
where flutter >> diag.txt 2>&1
echo ---- powershell hello >> diag.txt
powershell -NoProfile -Command "Write-Output hello; $PSVersionTable.PSVersion.ToString(); Get-ExecutionPolicy -List | Out-String" >> diag.txt 2>&1
echo powershell exit %ERRORLEVEL% >> diag.txt
echo ---- cg.ps1 check via -File >> diag.txt
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cg.ps1" check >> diag.txt 2>&1
echo cg exit %ERRORLEVEL% >> diag.txt
echo DONE >> diag.txt
echo.
echo Finished. Wrote %~dp0diag.txt
pause
