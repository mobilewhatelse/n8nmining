@echo off
REM Starts Docker (if needed), starts the n8n container, waits until n8n is
REM reachable, then opens the Solar Mining ROI Dashboard in the browser.
REM Opening the webhook URL triggers a fresh run of the workflow.

setlocal enabledelayedexpansion

set N8N_URL=http://localhost:5678
set DASHBOARD_URL=%N8N_URL%/webhook/mining-dashboard
REM Docker Desktop can take a while to fully init on a cold boot (WSL2 backend etc).
set DOCKER_MAX_TRIES=150
set MAX_TRIES=60

echo === Solar Mining ROI Dashboard Starter ===

REM --- 1. Make sure Docker Desktop is running ---
docker info >nul 2>&1
if errorlevel 1 (
    echo Docker laeuft nicht, starte Docker Desktop...
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
) else (
    echo Docker laeuft bereits.
)

set /a TRIES=0
:waitdocker
docker info >nul 2>&1
if not errorlevel 1 goto dockerready
set /a TRIES+=1
if !TRIES! GEQ %DOCKER_MAX_TRIES% (
    echo Docker ist nach %DOCKER_MAX_TRIES% Versuchen nicht gestartet. Abbruch.
    timeout /t 15 >nul
    exit /b 1
)
timeout /t 2 >nul
goto waitdocker
:dockerready
echo Docker ist bereit.

REM --- 2. Start n8n via docker compose. This recreates the container from
REM     docker-compose.yml if it's missing entirely (e.g. after a Docker
REM     Desktop reset), not just if it's stopped - no manual fix needed.
echo Starte n8n ueber docker compose...
pushd "%~dp0"
docker compose up -d
if errorlevel 1 (
    echo docker compose up fehlgeschlagen.
    popd
    timeout /t 15 >nul
    exit /b 1
)
popd

REM --- 3. Wait until n8n answers on localhost:5678 ---
echo Warte auf n8n unter %N8N_URL% ...
set /a TRIES=0
:waitn8n
curl -s -o nul -w "%%{http_code}" %N8N_URL% > "%TEMP%\n8n_status.txt" 2>nul
set /p STATUS=<"%TEMP%\n8n_status.txt"
if "%STATUS%"=="200" goto n8nready
set /a TRIES+=1
if !TRIES! GEQ %MAX_TRIES% (
    echo n8n antwortet nach %MAX_TRIES% Versuchen nicht. Abbruch.
    del "%TEMP%\n8n_status.txt" >nul 2>&1
    timeout /t 15 >nul
    exit /b 1
)
timeout /t 2 >nul
goto waitn8n
:n8nready
del "%TEMP%\n8n_status.txt" >nul 2>&1
echo n8n ist erreichbar.

REM --- 4. Open the dashboard. This GET request triggers the workflow. ---
echo Oeffne Dashboard: %DASHBOARD_URL%
start "" "%DASHBOARD_URL%"

endlocal
