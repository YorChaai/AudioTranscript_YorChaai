@echo off
title Audio Convert - Full Stack Launcher
cd /d "%~dp0"

echo ===================================================
echo   MEMULAI APLIKASI AUDIO CONVERT (FULL STACK)
echo ===================================================
echo.

echo [1/2] Menjalankan API Server Python di jendela baru...
:: Menggunakan start agar tidak memblokir proses selanjutnya
if exist venv\Scripts\python.exe (
    start "Backend Server" cmd /k "venv\Scripts\python.exe src\server.py"
) else (
    start "Backend Server" cmd /k "python src\server.py"
)

echo [2/2] Menjalankan Frontend Flutter (Desktop)...
cd flutter_app
echo Menunggu backend siap (3 detik)...
timeout /t 3 >nul
flutter run -d windows

echo.
echo Aplikasi telah ditutup.
pause
