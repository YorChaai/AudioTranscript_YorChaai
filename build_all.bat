@echo off
title Build Audio Convert Flutter App
cd /d "%~dp0"

echo Mendeteksi IP Address Komputer (WiFi/LAN)...
set LOCAL_IP=127.0.0.1
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4 Address"') do (
    set LOCAL_IP=%%a
)
set LOCAL_IP=%LOCAL_IP: =%
set ANDROID_API_URL=http://%LOCAL_IP%:5000/api

echo IP Address otomatis untuk Android APK: %ANDROID_API_URL%
echo.

cd flutter_app

echo ==================================================
echo MULAI BUILD APLIKASI WINDOWS (.exe)
echo ==================================================
call flutter build windows --dart-define=API_URL=http://127.0.0.1:5000/api
echo.
echo Build Windows Selesai!
echo Lokasi File: flutter_app\build\windows\x64\runner\Release\
echo.

echo ==================================================
echo MULAI BUILD APLIKASI ANDROID (.apk)
echo ==================================================
call flutter build apk --dart-define=API_URL=%ANDROID_API_URL%
echo.
echo Build Android Selesai!
echo Lokasi File: flutter_app\build\app\outputs\flutter-apk\app-release.apk
echo.

pause
