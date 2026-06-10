@echo off
title STARTING APP...
cd /d "%~dp0.."
echo [*] Launching Audio Convert App...

start "Audio Server (Python)" cmd /k "cd src && python server.py"
start "Cloudflare Tunnel" cmd /k "powershell -ExecutionPolicy Bypass -File scripts/start_tunnel.ps1"

echo ===================================================
echo [*] Server and Tunnel launched in separate windows!
echo [!] Check the 'Cloudflare Tunnel' window for the URL.
echo [!] Check 'Audio Server' window for logs.
echo ===================================================
echo.
pause
