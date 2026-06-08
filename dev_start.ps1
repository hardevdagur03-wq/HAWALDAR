<#
.SYNOPSIS
    Hawaldar Master Reset & Audit Script.

.DESCRIPTION
    1. Kills stale processes on backend (8000) and frontend (3001) ports.
    2. Creates logs/ directory if missing.
    3. Starts FastAPI backend and TanStack frontend as background jobs.
    4. Routes all stdout/stderr to logs/audit.log.
    5. Prints a green status banner.

.USAGE
    .\dev_start.ps1
#>

# ── Strict mode ──────────────────────────────────────────────────────────────
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Paths ────────────────────────────────────────────────────────────────────
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LogFile     = Join-Path $ProjectRoot "logs\audit.log"
$LogsDir     = Split-Path -Parent $LogFile
$FrontendDir = Join-Path $ProjectRoot "autonomous-flow-suite-main"

$BackendPort  = 8000
$FrontendPort = 8080

# ── Helper: Kill processes occupying a port ──────────────────────────────────
function Stop-PortOccupants {
    param([int]$Port)

    $conns = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
             Where-Object { $_.State -eq "Listen" }

    if (-not $conns) { return }

    foreach ($conn in $conns) {
        $procId = $conn.OwningProcess
        if ($procId -and $procId -ne 0) {
            $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if ($proc) {
                Write-Host "  [kill] PID $procId ($($proc.ProcessName)) on port $Port" -ForegroundColor Yellow
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# ── 1. Kill stale processes ─────────────────────────────────────────────────
Write-Host "`n[Hawaldar] Cleaning up stale processes..." -ForegroundColor Cyan

Stop-PortOccupants -Port $BackendPort
Stop-PortOccupants -Port $FrontendPort

# Also kill any orphaned node/uvicorn processes from previous dev sessions
Get-Process -Name "node" -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "*autonomous-flow-suite*" } |
    ForEach-Object {
        Write-Host "  [kill] orphaned node PID $($_.Id)" -ForegroundColor Yellow
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }

Start-Sleep -Seconds 1
Write-Host "  Ports $BackendPort and $FrontendPort are free.`n" -ForegroundColor Green

# ── 2. Create logs directory ────────────────────────────────────────────────
if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
    Write-Host "  [log] Created $LogsDir" -ForegroundColor DarkGray
}

# Rotate old log: append timestamp
if (Test-Path $LogFile) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $archive   = Join-Path $LogsDir "audit_$timestamp.log"
    try {
        Move-Item -Path $LogFile -Destination $archive -Force
        Write-Host "  [log] Rotated old log to $archive" -ForegroundColor DarkGray
    } catch {
        Write-Host "  [log] Could not rotate log (file may be locked), continuing..." -ForegroundColor DarkGray
    }
}

# Touch the new log file
try {
    "" | Out-File -FilePath $LogFile -Encoding UTF8 -NoNewline
} catch {
    Write-Host "  [log] Could not create new log file (file may be locked), continuing..." -ForegroundColor DarkGray
}

# Load or default API key
$apiKey = "change_me_in_production"
$envPath = Join-Path $ProjectRoot ".env"
if (Test-Path $envPath) {
    $line = Get-Content $envPath | Where-Object { $_ -like "HAWALDAR_API_KEY=*" }
    if ($line) {
        $apiKey = $line.Split("=", 2)[1].Trim()
    }
}
$env:HAWALDAR_API_KEY = $apiKey
$env:VITE_API_KEY = $apiKey

# ── 3. Start FastAPI backend ────────────────────────────────────────────────
Write-Host "[Hawaldar] Starting FastAPI backend on port $BackendPort..." -ForegroundColor Cyan

$backendCmd = "python -m uvicorn main:app --host 127.0.0.1 --port $BackendPort --reload"
Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -Command `"$backendCmd 2>&1 | Tee-Object -FilePath '$LogFile' -Append`"" `
    -WorkingDirectory $ProjectRoot `
    -WindowStyle Hidden `
    -PassThru | Out-Null

Start-Sleep -Seconds 2

# ── 4. Start TanStack frontend ──────────────────────────────────────────────
Write-Host "[Hawaldar] Starting TanStack frontend on port $FrontendPort..." -ForegroundColor Cyan

$npmPath = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source
if (-not $npmPath) { $npmPath = "npm.cmd" }
$env:VITE_API_BASE_URL = "http://127.0.0.1:$BackendPort/api/v1"
Start-Process -FilePath "$npmPath" `
    -ArgumentList "run dev" `
    -WorkingDirectory $FrontendDir `
    -WindowStyle Hidden `
    -PassThru | Out-Null

Start-Sleep -Seconds 3

# ── 5. Status check ─────────────────────────────────────────────────────────
$backendUp  = $false
$frontendUp = $false

try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$BackendPort/api/v1/health" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
    $backendUp = $resp.StatusCode -eq 200
} catch {
    $backendUp = $false
}

try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$FrontendPort/" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
    $frontendUp = $resp.StatusCode -lt 500
} catch {
    $frontendUp = $false
}

# ── 6. Print status banner ──────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                   HAWALDAR DEV ENVIRONMENT                 ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green

if ($backendUp) {
    Write-Host "║  Backend   : http://localhost:$BackendPort  [UP]            ║" -ForegroundColor Green
} else {
    Write-Host "║  Backend   : http://localhost:$BackendPort  [DOWN]          ║" -ForegroundColor Red
}

if ($frontendUp) {
    Write-Host "║  Frontend  : http://localhost:$FrontendPort  [UP]           ║" -ForegroundColor Green
} else {
    Write-Host "║  Frontend  : http://localhost:$FrontendPort  [DOWN]         ║" -ForegroundColor Red
}

Write-Host "║  Health    : http://localhost:$BackendPort/api/v1/health     ║" -ForegroundColor Green
Write-Host "║  Logs      : $LogsDir\audit.log    ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "[Hawaldar] Dev environment ready. All output logs to logs/audit.log" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+C to stop all servers." -ForegroundColor DarkGray
Write-Host ""

# Keep terminal open until user presses Ctrl+C
try {
    while ($true) {
        Start-Sleep -Seconds 5

        # Check if backend is still alive
        try {
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$BackendPort/api/v1/health" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
            if ($resp.StatusCode -ne 200) {
                Write-Host "[Hawaldar] Backend not responding, restarting..." -ForegroundColor Yellow
                Stop-PortOccupants -Port $BackendPort
                Start-Process -FilePath "powershell.exe" `
                    -ArgumentList "-NoProfile -Command `"$backendCmd 2>&1 | Tee-Object -FilePath '$LogFile' -Append`"" `
                    -WorkingDirectory $ProjectRoot `
                    -WindowStyle Hidden `
                    -PassThru | Out-Null
            }
        } catch {
            Write-Host "[Hawaldar] Backend not responding, restarting..." -ForegroundColor Yellow
            Stop-PortOccupants -Port $BackendPort
            Start-Process -FilePath "powershell.exe" `
                -ArgumentList "-NoProfile -Command `"$backendCmd 2>&1 | Tee-Object -FilePath '$LogFile' -Append`"" `
                -WorkingDirectory $ProjectRoot `
                -WindowStyle Hidden `
                -PassThru | Out-Null
        }
    }
} finally {
    Write-Host "[Hawaldar] Shutting down..." -ForegroundColor Cyan
    Stop-PortOccupants -Port $BackendPort
    Stop-PortOccupants -Port $FrontendPort
}
