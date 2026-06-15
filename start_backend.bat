@echo off
cd /d "%~dp0"
title Audio Convert API Server
echo Starting Audio Convert API Server...
echo ==================================================
call venv\Scripts\activate.bat
if errorlevel 1 (
    echo [ERROR] Gagal mengaktifkan virtual environment venv.
    echo Pastikan folder venv ada di direktori ini.
    pause
    exit /b 1
)

python src\server.py

echo.
echo Server telah berhenti.
pause
