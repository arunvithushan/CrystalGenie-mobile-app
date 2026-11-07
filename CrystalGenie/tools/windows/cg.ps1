<#
  Crystal Genie - Windows helper. Every step logs to tools\windows\logs\<step>.log
  Usage (PowerShell):  powershell -ExecutionPolicy Bypass -File tools\windows\cg.ps1 <step>
  Steps: all | sync-photos | watch-photos | emu-setup | check | setup | train | evaluate | dbinit | migrate | test-backend | run-backend | run-app | e2e | e2e-app | test-flutter | build-apk
  Or just double-click the numbered .cmd files next to this script.
#>
param([Parameter(Mandatory = $true)][string]$Step)

$ErrorActionPreference = 'Continue'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LogDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir "$Step.log"
"==== $Step  $(Get-Date -Format s)  root=$Root" | Out-File -FilePath $Log -Encoding utf8

function Say([string]$msg) { $msg | Tee-Object -FilePath $Log -Append | Write-Host -ForegroundColor Cyan }

function Run {
  param([string]$Exe, [string[]]$ArgList, [string]$Cwd = $Root)
  Say ">> $Exe $($ArgList -join ' ')   (in $Cwd)"
  Push-Location $Cwd
  try {
    & $Exe @ArgList 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $Log -Append | Write-Host
    $code = $LASTEXITCODE
  } catch {
    "ERROR: $_" | Tee-Object -FilePath $Log -Append | Write-Host -ForegroundColor Red
    $code = 1
  } finally { Pop-Location }
  Say "<< exit code $code"
  return $code
}

function Find-Python {
  foreach ($v in '3.10', '3.11', '3.12') {
    $p = & py "-$v" -c "import sys; print(sys.executable)" 2>$null
    if ($LASTEXITCODE -eq 0 -and $p) { return @{ Version = $v; Exe = $p.Trim() } }
  }
  $p = (Get-Command python -ErrorAction SilentlyContinue)
  if ($p) { return @{ Version = 'default'; Exe = $p.Source } }
  return $null
}

$MlPy = Join-Path $Root 'ml_training\.venv\Scripts\python.exe'
$BePy = Join-Path $Root 'backend\.venv\Scripts\python.exe'
$Mobile = Join-Path $Root 'mobile'
$DataDir = (Resolve-Path (Join-Path $Root '..\images\a') -ErrorAction SilentlyContinue).Path

# Make Flutter usable even if its bin folder is not on PATH (common install locations).
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  foreach ($d in 'C:\flutter', 'C:\src\flutter', "$env:USERPROFILE\flutter", "$env:USERPROFILE\dev\flutter", "$env:USERPROFILE\Documents\flutter") {
    if (Test-Path "$d\bin\flutter.bat") { $env:Path = "$d\bin;" + $env:Path; break }
  }
}

function Set-EnvKey([string]$File, [string]$Key, [string]$Value) {
  $lines = @()
  if (Test-Path $File) { $lines = Get-Content $File }
  $found = $false
  $lines = $lines | ForEach-Object { if ($_ -match "^$Key=") { $found = $true; "$Key=$Value" } else { $_ } }
  if (-not $found) { $lines += "$Key=$Value" }
  $lines | Set-Content $File -Encoding utf8
}

function Find-Psql {
  $psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
  if (-not $psql) {
    $cand = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if ($cand) { $psql = $cand.FullName }
  }
  return $psql
}

function Ensure-BackendEnv {
  $be = Join-Path $Root 'backend'
  if (-not (Test-Path "$be\.env")) { Copy-Item "$be\.env.example" "$be\.env" }
  $cur = (Get-Content "$be\.env" | Where-Object { $_ -match '^JWT_SECRET=' }) -replace '^JWT_SECRET=', ''
  if (-not $cur -or $cur -like 'change-me*' -or $cur.Length -lt 32) {
    $secret = & $BePy -c "import secrets; print(secrets.token_urlsafe(64))"
    Set-EnvKey "$be\.env" 'JWT_SECRET' $secret
    Say 'Set a random JWT_SECRET in backend\.env'
  }
}

function Need-Flutter {
  $f = Get-Command flutter -ErrorAction SilentlyContinue
  if (-not $f) { Say 'FLUTTER NOT FOUND on PATH. Install Flutter and add its bin folder to PATH (docs\WINDOWS_SETUP.md).'; exit 2 }
}

# ---- PC photos -> emulator gallery ------------------------------------------------------------
$PhotoDir = Join-Path (Split-Path $Root -Parent) 'Photos for Crystal Genie'
$PhotoState = Join-Path $LogDir 'photo_sync_state.txt'
function Get-Adb { $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\sdk" }; "$sdk\platform-tools\adb.exe" }
function Sync-Photos([switch]$Quiet) {
  # Copies new/changed images from "Photos for Crystal Genie" (next to the CrystalGenie folder) to the
  # emulator/phone album Pictures/FromPC so they show up in the app's Upload picker.
  $adb = Get-Adb
  New-Item -ItemType Directory -Force -Path $PhotoDir | Out-Null
  $dev = (& $adb devices) | Where-Object { $_ -match '^(\S+)\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] } | Select-Object -First 1
  if (-not $dev) { if (-not $Quiet) { Say 'No emulator/phone is running - start it with START_APP.cmd first.' }; return 0 }
  $done = @{}
  if (Test-Path $PhotoState) { Get-Content $PhotoState | ForEach-Object { $done[$_] = $true } }
  # Sync folder (with sub-folders) + photos lying directly on the Windows Desktop.
  $desktop = [Environment]::GetFolderPath('Desktop')
  $files = @(Get-ChildItem $PhotoDir -Recurse -File) + @(if ($desktop -and (Test-Path $desktop)) { Get-ChildItem $desktop -File })
  $files = $files | Where-Object { $_.Extension -match '^\.(jpe?g|png|webp)$' -and $_.Length -le 10MB }
  $n = 0
  foreach ($f in $files) {
    $key = "$dev|$($f.FullName)|$($f.Length)|$($f.LastWriteTimeUtc.Ticks)"
    if ($done.ContainsKey($key)) { continue }
    $name = ($f.Name -replace '[^A-Za-z0-9._-]', '_')
    $remote = "/sdcard/Pictures/FromPC/$name"
    & $adb -s $dev shell mkdir -p /sdcard/Pictures/FromPC 2>&1 | Out-Null
    & $adb -s $dev push "$($f.FullName)" $remote 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
      # Mark it as new so it is first in the phone's photo picker (adb push keeps the old PC date).
      & $adb -s $dev shell touch "$remote" 2>&1 | Out-Null
      & $adb -s $dev shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$remote" 2>&1 | Out-Null
      Add-Content -Path $PhotoState -Value $key
      $n++
      Say "Sent to app gallery: $($f.Name)"
    }
  }
  if (-not $Quiet) { Say "Photos from $PhotoDir and your Desktop ($desktop): $(@($files).Count) photos, $n newly copied. In the app: Upload > Phone gallery." }
  return $n
}

function Start-PhotoWatch {
  # Starts the background photo sync (minimized window) unless it is already running.
  $pidFile = Join-Path $LogDir 'watch-photos.pid'
  $old = if (Test-Path $pidFile) { Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
  if ($old -and (Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue)) { Say 'Photo sync already running.'; return }
  Start-Process -FilePath 'powershell' -WindowStyle Minimized -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", 'watch-photos' | Out-Null
  Say 'Photo sync is on: put photos in "Photos for Crystal Genie" and they appear in the app (Upload > newest photos).'
}

switch ($Step) {
  'check' {
    Run 'py' @('-0p') | Out-Null
    Run 'cmd' @('/c', 'where python & where flutter & where dart & where java & where adb & where psql & where git') | Out-Null
    Run 'cmd' @('/c', 'flutter --version') | Out-Null
    Run 'cmd' @('/c', 'java -version') | Out-Null
    Run 'nvidia-smi' @() | Out-Null
    Say "ANDROID_HOME=$env:ANDROID_HOME  LOCALAPPDATA SDK exists: $(Test-Path "$env:LOCALAPPDATA\Android\Sdk")"
    Say "PostgreSQL folders: $((Get-ChildItem 'C:\Program Files\PostgreSQL' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ', ')"
    Get-Service | Where-Object { $_.Name -like 'postgres*' } | ForEach-Object { Say "service $($_.Name): $($_.Status)" }
    foreach ($d in 'C:\src\flutter', "$env:USERPROFILE\flutter", "$env:USERPROFILE\Documents\flutter", 'C:\flutter', "$env:USERPROFILE\dev\flutter") {
      if (Test-Path "$d\bin\flutter.bat") { Say "Flutter SDK found at $d" }
    }
    foreach ($u in 'https://pypi.org/simple/pip/', 'https://pub.dev/api/packages/dio', 'https://storage.googleapis.com/') {
      try { $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 15; Say "net $u -> $($r.StatusCode)" } catch { Say "net $u -> FAILED $($_.Exception.Message)" }
    }
    Run 'cmd' @('/c', 'flutter doctor -v') | Out-Null
  }

  'setup' {
    $py = Find-Python
    if (-not $py) { Say 'Python 3.10/3.11/3.12 not found. Install Python 3.10 (64-bit) from python.org.'; exit 2 }
    Say "Using Python $($py.Version): $($py.Exe)"
    foreach ($part in 'ml_training', 'backend') {
      $dir = Join-Path $Root $part
      if (-not (Test-Path "$dir\.venv\Scripts\python.exe")) { Run $py.Exe @('-m', 'venv', '.venv') $dir | Out-Null }
      $vpy = "$dir\.venv\Scripts\python.exe"
      Run $vpy @('-m', 'pip', 'install', '--upgrade', 'pip') $dir | Out-Null
      Run $vpy @('-m', 'pip', 'install', '-r', 'requirements.txt') $dir | Out-Null
    }
    if (Get-Command flutter -ErrorAction SilentlyContinue) {
      # Only scaffold the Android shell once; re-running 'flutter create' adds a duplicate MainActivity.
      if (-not (Test-Path "$Mobile\android\app\build.gradle.kts")) {
        Run 'cmd' @('/c', 'flutter create --platforms=android --org com.crystalgenie --project-name crystal_genie .') $Mobile | Out-Null
      }
      Run 'cmd' @('/c', 'flutter pub get') $Mobile | Out-Null
    } else { Say 'Flutter not on PATH - skipped mobile setup.' }
    Say 'SETUP DONE'
  }

  'train' {
    if (-not (Test-Path $MlPy)) { Say 'Run setup first.'; exit 2 }
    if (-not $DataDir) { Say 'Dataset folder ..\images\a not found.'; exit 2 }
    $ml = Join-Path $Root 'ml_training'
    Run $MlPy @('-c', "import tensorflow as tf; print('TF', tf.__version__, 'GPUs:', tf.config.list_physical_devices('GPU'))") $ml | Out-Null
    Run $MlPy @('inspect_dataset.py', '--data-dir', $DataDir, '--out', 'reports') $ml | Out-Null
    Run $MlPy @('preprocess.py', '--data-dir', $DataDir) $ml | Out-Null
    $c = Run $MlPy @('train.py') $ml
    Say "TRAIN DONE (exit $c)"
  }

  'evaluate' {
    $ml = Join-Path $Root 'ml_training'
    if (-not (Test-Path (Join-Path $Root 'models\gemstone_model.keras'))) { Say 'No trained model yet - run train.'; exit 2 }
    $c = Run $MlPy @('evaluate.py') $ml
    Say "EVALUATE DONE (exit $c)"
  }

  'migrate' {
    $be = Join-Path $Root 'backend'
    Ensure-BackendEnv
    $db = (Get-Content "$be\.env" | Where-Object { $_ -match '^DATABASE_URL=' }) -replace '^DATABASE_URL=', ''
    if (-not $db -or $db -like 'sqlite*') {
      # Development fallback when PostgreSQL is not installed: a fresh SQLite file managed by Alembic.
      Set-EnvKey "$be\.env" 'DATABASE_URL' 'sqlite:///./var/crystal_genie_dev.db'
      New-Item -ItemType Directory -Force -Path "$be\var" | Out-Null
      Say 'DATABASE_URL -> sqlite:///./var/crystal_genie_dev.db (PostgreSQL not configured; run 4_setup_database.cmd for PostgreSQL)'
    }
    Run $BePy @('-m', 'alembic', 'upgrade', 'head') $be | Out-Null
    Run $BePy @('-m', 'app.database.seed') $be | Out-Null
    Say 'MIGRATE DONE'
  }

  'all' {
    $self = $PSCommandPath
    $psql = Find-Psql
    if ($psql) {
      Say 'PostgreSQL found - configuring it first (you will be asked for the postgres password once).'
      & powershell -NoProfile -ExecutionPolicy Bypass -File $self 'setup'
      & powershell -NoProfile -ExecutionPolicy Bypass -File $self 'dbinit'
    } else {
      Say 'PostgreSQL not found - the backend will use a local SQLite database for this run.'
      & powershell -NoProfile -ExecutionPolicy Bypass -File $self 'setup'
    }
    foreach ($st in 'check', 'evaluate', 'migrate', 'test-backend', 'e2e', 'test-flutter', 'build-apk') {
      Say "===== step $st ====="
      & powershell -NoProfile -ExecutionPolicy Bypass -File $self $st
    }
    Say 'ALL STEPS FINISHED - logs are in tools\windows\logs'
  }

  'dbinit' {
    if (-not (Test-Path $BePy)) { Say 'Run setup first.'; exit 2 }
    $psql = Find-Psql
    if (-not $psql) { Say 'PostgreSQL (psql) not found. Install PostgreSQL 16 first (docs\WINDOWS_SETUP.md section 0).'; exit 2 }
    Say "psql: $psql"
    $sec = Read-Host -AsSecureString 'Enter the password of the PostgreSQL "postgres" superuser (typed characters are hidden)'
    $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    $sql = @"
DO `$`$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'crystal') THEN
    CREATE ROLE crystal WITH LOGIN PASSWORD 'crystal_dev_password';
  END IF;
END `$`$;
"@
    $tmp = Join-Path $env:TEMP 'cg_role.sql'; $sql | Out-File -FilePath $tmp -Encoding ascii
    Run $psql @('-U', 'postgres', '-h', 'localhost', '-v', 'ON_ERROR_STOP=1', '-f', $tmp) | Out-Null
    foreach ($db in 'crystal_genie', 'crystal_genie_test') {
      $exists = & $psql -U postgres -h localhost -tAc "SELECT 1 FROM pg_database WHERE datname='$db'" 2>$null
      if ("$exists".Trim() -ne '1') { Run $psql @('-U', 'postgres', '-h', 'localhost', '-c', "CREATE DATABASE $db OWNER crystal") | Out-Null }
      else { Say "database $db already exists" }
    }
    Remove-Item Env:\PGPASSWORD
    $be = Join-Path $Root 'backend'
    Ensure-BackendEnv
    Set-EnvKey "$be\.env" 'DATABASE_URL' 'postgresql+psycopg://crystal:crystal_dev_password@localhost:5432/crystal_genie'
    Set-EnvKey "$be\.env" 'TEST_DATABASE_URL' 'postgresql+psycopg://crystal:crystal_dev_password@localhost:5432/crystal_genie_test'
    Say 'backend\.env now points at PostgreSQL (crystal_genie / crystal_genie_test)'
    Run $BePy @('-m', 'alembic', 'upgrade', 'head') $be | Out-Null
    Run $BePy @('-m', 'app.database.seed') $be | Out-Null
    Say 'DB INIT DONE'
  }

  'test-backend' {
    $be = Join-Path $Root 'backend'
    $c = Run $BePy @('-m', 'pytest', '-q', '-rs') $be
    Say "BACKEND TESTS EXIT $c"
  }

  'run-backend' {
    $be = Join-Path $Root 'backend'
    Say 'Starting API on http://0.0.0.0:8000  (docs: http://127.0.0.1:8000/docs). Close this window to stop.'
    Run $BePy @('-m', 'uvicorn', 'app.main:app', '--host', '0.0.0.0', '--port', '8000') $be | Out-Null
  }

  'run-app' {
    # One click: make sure the API is up (own window), make sure a device is running, then `flutter run` pointed at the API.
    Need-Flutter
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\sdk" }
    $adb = "$sdk\platform-tools\adb.exe"; $emu = "$sdk\emulator\emulator.exe"
    $be = Join-Path $Root 'backend'
    $up = $false
    try { if (Invoke-RestMethod http://127.0.0.1:8000/api/health -TimeoutSec 3) { $up = $true } } catch {}
    if ($up) {
      # Restart the API if its code or .env changed since it was started (so new features are live).
      $owner = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -First 1
      $proc = if ($owner) { Get-Process -Id $owner -ErrorAction SilentlyContinue } else { $null }
      $newest = (@(Get-ChildItem (Join-Path $be 'app') -Recurse -Filter *.py) + @(Get-Item (Join-Path $be '.env') -ErrorAction SilentlyContinue) |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
      if ($proc -and $proc.StartTime -lt $newest) {
        Say 'Backend code changed - restarting the API...'
        Stop-Process -Id $proc.Id -Force
        Start-Sleep -Seconds 2
        $up = $false
      }
    }
    if ($up) { Say 'Backend already running on port 8000.' }
    else {
      Say 'Starting backend in its own window (keep it open while you use the app)...'
      Start-Process -FilePath 'cmd' -ArgumentList '/k', "title Crystal Genie API && cd /d `"$be`" && `"$BePy`" -m uvicorn app.main:app --host 0.0.0.0 --port 8000" | Out-Null
      for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 2; try { if (Invoke-RestMethod http://127.0.0.1:8000/api/health -TimeoutSec 3) { $up = $true; break } } catch {} }
      if (-not $up) { Say 'Backend did not start - look at the "Crystal Genie API" window for the error.'; exit 3 }
      Say 'Backend is up: http://127.0.0.1:8000/docs'
    }
    function Get-AdbDevice { (& $adb devices) | Where-Object { $_ -match '^(\S+)\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] } | Select-Object -First 1 }
    $dev = Get-AdbDevice
    if (-not $dev) {
      $avd = (& $emu -list-avds 2>$null | Where-Object { $_ -and $_ -notmatch '^INFO' } | Select-Object -First 1)
      if (-not $avd) { Say 'No phone/emulator found. Plug in a phone (USB debugging on) or create an AVD in Android Studio.'; exit 2 }
      Say "Starting emulator $avd ..."
      Start-Process -FilePath $emu -ArgumentList '-avd', $avd, '-no-boot-anim' | Out-Null
      & $adb wait-for-device
      for ($i = 0; $i -lt 120; $i++) { $b = "$(& $adb shell getprop sys.boot_completed 2>$null)".Trim(); if ($b -eq '1') { break }; Start-Sleep -Seconds 3 }
      $dev = Get-AdbDevice
    }
    $isEmu = $dev -like 'emulator-*'
    if ($isEmu) { $url = 'http://10.0.2.2:8000' }
    else {
      $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' } |
        Where-Object { $_.InterfaceAlias -notmatch 'vEthernet|WSL|Loopback' } | Select-Object -First 1).IPAddress
      $url = "http://${ip}:8000"
      Say 'Physical phone: it must be on the same Wi-Fi as this PC, and Windows Firewall must allow port 8000 (see docs\WINDOWS_SETUP.md).'
    }
    Say "Device: $dev   API: $url"
    Say 'Third-party apps on the device (check you open "Crystal Genie" = com.crystalgenie.app):'
    (& $adb -s $dev shell pm list packages -3) | ForEach-Object { Say "   $_" }
    # (Re)start the photo sync so it always runs the current version of this script.
    $pidFile = Join-Path $LogDir 'watch-photos.pid'
    if (Test-Path $pidFile) { $old = Get-Content $pidFile | Select-Object -First 1; if ($old) { Stop-Process -Id ([int]$old) -Force -ErrorAction SilentlyContinue }; Remove-Item $pidFile -Force -ErrorAction SilentlyContinue }
    Sync-Photos | Out-Null
    Start-PhotoWatch
    # The debug build is ~170 MB and the emulator's storage is nearly full, so install the much smaller release build
    # (same app, no hot reload). Set CG_DEBUG_BUILD=1 to get the debug build instead.
    $mode = if ($env:CG_DEBUG_BUILD -eq '1') { '' } else { ' --release' }
    if ($mode) { Say 'Installing the release build (smaller; first build takes a few minutes)...' }
    Run 'cmd' @('/c', "flutter run$mode -d $dev --dart-define=API_BASE_URL=$url") $Mobile | Out-Null
  }

  'stop-backend' {
    # Stops whatever is serving port 8000 (the Crystal Genie API window) so START_APP can start a fresh one.
    $pids = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($p in $pids) { $proc = Get-Process -Id $p -ErrorAction SilentlyContinue; if ($proc) { Say "Stopping $($proc.ProcessName) (pid $p) on port 8000"; Stop-Process -Id $p -Force } }
    if (-not $pids) { Say 'Nothing listening on port 8000.' }
  }

  'adb-script' {
    # Dev helper: runs each line of adb_script.txt as `adb shell <line>` ("sleep N" pauses), then saves a screenshot.
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\sdk" }
    $adb = "$sdk\platform-tools\adb.exe"
    (& $adb devices 2>&1) | ForEach-Object { Say "devices: $_" }
    foreach ($line in Get-Content (Join-Path $PSScriptRoot 'adb_script.txt')) {
      $l = $line.Trim(); if (-not $l) { continue }
      if ($l -match '^sleep (\d+)$') { Start-Sleep -Seconds $Matches[1]; continue }
      Say "adb shell $l"; & $adb shell $l 2>&1 | ForEach-Object { Say "  $_" }
    }
    $out = Join-Path $LogDir 'emu_screen.png'
    cmd /c "`"$adb`" exec-out screencap -p > `"$out`""
    Say "Saved $out"
  }

  'sync-photos' {
    Sync-Photos | Out-Null
  }

  'start-photo-watch' {
    Start-PhotoWatch
  }

  'restart-photo-watch' {
    $pidFile = Join-Path $LogDir 'watch-photos.pid'
    if (Test-Path $pidFile) { $old = Get-Content $pidFile | Select-Object -First 1; if ($old) { Stop-Process -Id ([int]$old) -Force -ErrorAction SilentlyContinue } ; Remove-Item $pidFile -Force -ErrorAction SilentlyContinue }
    Sync-Photos | Out-Null
    Start-PhotoWatch
  }

  'watch-photos' {
    # Runs in a small background window started by START_APP; copies new PC photos every 5 seconds.
    "$PID" | Out-File (Join-Path $LogDir 'watch-photos.pid') -Encoding ascii
    Say "Watching $PhotoDir - new photos appear in the app under Upload > FromPC. Close this window to stop."
    while ($true) { try { Sync-Photos -Quiet | Out-Null } catch { }; Start-Sleep -Seconds 5 }
  }

  'emu-setup' {
    # Applies emulator hardware changes (laptop webcam as back camera) with a cold boot, then copies
    # held-out gemstone test photos into the emulator gallery (Pictures/CrystalGenie) for the Upload button.
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\sdk" }
    $adb = "$sdk\platform-tools\adb.exe"; $emu = "$sdk\emulator\emulator.exe"
    Say 'Webcams the emulator can use:'
    (& $emu -webcam-list 2>&1) | ForEach-Object { Say "   $_" }
    $avd = (& $emu -list-avds 2>$null | Where-Object { $_ -and $_ -notmatch '^INFO' } | Select-Object -First 1)
    $running = (& $adb devices) | Where-Object { $_ -match '^emulator-\d+\s+device$' }
    if ($running) { Say 'Closing the running emulator...'; & $adb emu kill | Out-Null; Start-Sleep -Seconds 8 }
    # A frozen emulator shows as "offline" and ignores `adb emu kill`: end its processes so it can boot again (its data is kept).
    $stuck = Get-Process -Name 'qemu-system-*', 'emulator' -ErrorAction SilentlyContinue
    if ($stuck) { Say 'Ending the frozen emulator...'; $stuck | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 5; & $adb kill-server | Out-Null }
    Say "Cold-booting $avd so the new camera setting is used (1-3 minutes)..."
    Start-Process -FilePath $emu -ArgumentList '-avd', $avd, '-no-snapshot-load', '-no-boot-anim' | Out-Null
    & $adb wait-for-device
    for ($i = 0; $i -lt 120; $i++) { $b = "$(& $adb shell getprop sys.boot_completed 2>$null)".Trim(); if ($b -eq '1') { break }; Start-Sleep -Seconds 3 }
    Start-Sleep -Seconds 5
    & $adb shell input keyevent 224 | Out-Null
    Say ('Emulator cameras: ' + ((& $adb shell getprop qemu.camera.back 2>$null) -join ''))
    $src = Join-Path $PSScriptRoot 'sample_photos'
    if (Test-Path $src) {
      & $adb shell mkdir -p /sdcard/Pictures/CrystalGenie | Out-Null
      $n = 0
      Get-ChildItem $src -Filter *.jpg | ForEach-Object {
        & $adb push $_.FullName "/sdcard/Pictures/CrystalGenie/$($_.Name)" 2>&1 | Out-Null
        & $adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///sdcard/Pictures/CrystalGenie/$($_.Name)" 2>&1 | Out-Null
        $n++
      }
      Say "Copied $n sample gemstone photos to the emulator gallery (Pictures > CrystalGenie)."
    }
    Say 'Free space on the emulator:'
    (& $adb shell df -h /data 2>&1) | ForEach-Object { Say "   $_" }
  }

  'emu-shot' {
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\sdk" }
    $adb = "$sdk\platform-tools\adb.exe"
    $out = Join-Path $LogDir 'emu_screen.png'
    cmd /c "`"$adb`" exec-out screencap -p > `"$out`""
    (& $adb shell pm list packages -3) | ForEach-Object { Say "pkg: $_" }
    (& $adb shell dumpsys activity activities) | Select-String 'mResumedActivity|topResumedActivity' | ForEach-Object { Say "$_" }
    Say "Saved $out"
  }

  'e2e' {
    $be = Join-Path $Root 'backend'
    # assets\test\sample_gem.jpg is a held-out (test split) Rose Quartz photo the model never trained on
    $img = Get-Item (Join-Path $Root 'mobile\assets\test\sample_gem.jpg')
    $srv = Start-Process -FilePath $BePy -ArgumentList '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8000' `
      -WorkingDirectory $be -PassThru -WindowStyle Minimized -RedirectStandardOutput (Join-Path $LogDir 'e2e_server.out.log') `
      -RedirectStandardError (Join-Path $LogDir 'e2e_server.err.log')
    $ok = $false
    for ($i = 0; $i -lt 90; $i++) {
      Start-Sleep -Seconds 2
      try { $h = Invoke-RestMethod http://127.0.0.1:8000/api/health -TimeoutSec 3; if ($h) { $ok = $true; break } } catch {}
    }
    if (-not $ok) { Say 'Server did not start - see logs\e2e_server.err.log' }
    else { Run $BePy @('scripts\e2e_smoke.py', '--base-url', 'http://127.0.0.1:8000', '--image', $img.FullName) $be | Out-Null }
    Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue
    Say 'E2E DONE'
  }

  'test-flutter' {
    Need-Flutter
    Run 'cmd' @('/c', 'flutter pub get') $Mobile | Out-Null
    Run 'cmd' @('/c', 'flutter analyze') $Mobile | Out-Null
    $c = Run 'cmd' @('/c', 'flutter test --reporter expanded') $Mobile
    Say "FLUTTER TESTS EXIT $c"
  }

  'build-apk' {
    Need-Flutter
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' } |
      Where-Object { $_.InterfaceAlias -notmatch 'vEthernet|WSL|Loopback' } | Select-Object -First 1).IPAddress
    $url = if ($ip) { "http://${ip}:8000" } else { 'http://10.0.2.2:8000' }
    Say "API_BASE_URL baked into the APKs: $url (change later in the app: Login > Server settings)"
    Run 'cmd' @('/c', "flutter build apk --debug --dart-define=API_BASE_URL=$url") $Mobile | Out-Null
    Run 'cmd' @('/c', "flutter build apk --release --dart-define=API_BASE_URL=$url") $Mobile | Out-Null
    Get-ChildItem (Join-Path $Mobile 'build\app\outputs\flutter-apk') -Filter *.apk -ErrorAction SilentlyContinue |
      ForEach-Object { Say "APK: $($_.FullName)  $([math]::Round($_.Length/1MB,1)) MB" }
  }

  'e2e-app' {
    # Full app E2E on an Android emulator/phone against the real backend + model (integration_test/app_e2e_test.dart).
    Need-Flutter
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\sdk" }
    $adb = "$sdk\platform-tools\adb.exe"; $emu = "$sdk\emulator\emulator.exe"
    function Get-AdbDevice { (& $adb devices) | Where-Object { $_ -match '^(\S+)\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] } | Select-Object -First 1 }
    $dev = Get-AdbDevice
    if (-not $dev) {
      $avd = (& $emu -list-avds 2>$null | Where-Object { $_ -and $_ -notmatch '^INFO' } | Select-Object -First 1)
      if (-not $avd) { Say 'No running device and no emulator (AVD) found. Create one in Android Studio > Device Manager.'; exit 2 }
      Say "Starting emulator $avd (cold boot can take a few minutes)"
      Start-Process -FilePath $emu -ArgumentList '-avd', $avd, '-no-snapshot-save', '-no-boot-anim' | Out-Null
      & $adb wait-for-device
      for ($i = 0; $i -lt 120; $i++) { $b = "$(& $adb shell getprop sys.boot_completed 2>$null)".Trim(); if ($b -eq '1') { break }; Start-Sleep -Seconds 3 }
      Start-Sleep -Seconds 5
      $dev = Get-AdbDevice
    }
    Say "Device: $dev"
    $isEmu = $dev -like 'emulator-*'
    $bind = if ($isEmu) { '127.0.0.1' } else { '0.0.0.0' }
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' } |
      Where-Object { $_.InterfaceAlias -notmatch 'vEthernet|WSL|Loopback' } | Select-Object -First 1).IPAddress
    $url = if ($isEmu) { 'http://10.0.2.2:8000' } else { "http://${ip}:8000" }
    $be = Join-Path $Root 'backend'
    $srv = Start-Process -FilePath $BePy -ArgumentList '-m', 'uvicorn', 'app.main:app', '--host', $bind, '--port', '8000' `
      -WorkingDirectory $be -PassThru -WindowStyle Minimized -RedirectStandardOutput (Join-Path $LogDir 'e2e_app_server.out.log') `
      -RedirectStandardError (Join-Path $LogDir 'e2e_app_server.err.log')
    $ok = $false
    for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 2; try { if (Invoke-RestMethod http://127.0.0.1:8000/api/health -TimeoutSec 3) { $ok = $true; break } } catch {} }
    if (-not $ok) { Say 'Server did not start - see logs\e2e_app_server.err.log' }
    else {
      $c = Run 'cmd' @('/c', "flutter test integration_test/app_e2e_test.dart -d $dev --dart-define=API_BASE_URL=$url") $Mobile
      Say "APP E2E EXIT $c"
    }
    Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue
  }

  default { Say "Unknown step $Step" ; exit 1 }
}
