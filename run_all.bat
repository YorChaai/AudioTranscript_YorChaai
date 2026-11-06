@echo off
title Audio Convert - Full Stack Launcher
cd /d "%~dp0"

echo ===================================================
echo   MEMULAI APLIKASI AUDIO CONVERT (FULL STACK)
echo ===================================================
echo.

echo [1/2] Menyiapkan port 5000 dan menjalankan API Server Python...
:: Membersihkan proses yang menggantung di port 5000 jika ada
for /f "tokens=5" %%a in ('netstat -aon ^| findstr :5000 ^| findstr LISTENING') do (
    echo [INFO] Menghentikan proses lama di port 5000 (PID: %%a)...
    taskkill /F /PID %%a >nul 2>&1
)
timeout /t 1 >nul

:: Menggunakan start agar tidak memblokir proses selanjutnya
if exist venv\Scripts\python.exe (
    start "Backend Server (AudioTranscript)" cmd /k "venv\Scripts\python.exe src\server.py"
) else (
    start "Backend Server (AudioTranscript)" cmd /k "python src\server.py"
)

echo [2/2] Menjalankan Frontend Flutter (Desktop)...
cd flutter_app
echo Menunggu backend siap (3 detik)...
timeout /t 3 >nul
flutter run -d windows

echo.
echo Aplikasi telah ditutup.
pause
