@echo off
title Audio Convert to TXT
cd /d "%~dp0"

echo [DEBUG] Mencoba menjalankan aplikasi...

if exist venv\Scripts\python.exe (
    echo [OK] Menggunakan Python dari venv...
    cd src && ..\venv\Scripts\python.exe main.py
) else (
    echo [!] venv tidak ditemukan. Mencoba Python sistem...
    cd src && python main.py
)

if errorlevel 1 (
    echo.
    echo [ERROR] Program berhenti dengan kesalahan.
)

echo.
pause

