@echo off
echo ============================================================
echo         AUDIO CONVERT TO TXT - MODEL SIZE SELECTOR
echo ============================================================
echo.
echo Model Size Comparison:
echo ----------------------
echo   tiny    - Fastest, least accurate (good for quick tests)
echo   small   - Fast, decent accuracy
echo   medium  - Balanced (RECOMMENDED for most users)
echo   large-v3 - Slowest, most accurate (needs 4GB+ VRAM)
echo.
echo Current Model: %WHISPER_MODEL_SIZE% (default: large-v3)
echo.
echo ============================================================
echo.
echo Pilih Model Size:
echo.
echo   [1] tiny    (Super fast, ~150MB)
echo   [2] small   (Fast, ~240MB)
echo   [3] medium  (Balanced, ~760MB) - RECOMMENDED
echo   [4] large-v3 (Most accurate, ~3GB) - Needs good GPU
echo.
echo   [0] Cancel (use default)
echo ============================================================
echo.
set /p choice="Pilihan Anda: "

if "%choice%"=="1" (
    setx WHISPER_MODEL_SIZE "tiny"
    echo.
    echo ✅ Model size set to: tiny
    echo 🔄 Restart terminal untuk apply changes
) else if "%choice%"=="2" (
    setx WHISPER_MODEL_SIZE "small"
    echo.
    echo ✅ Model size set to: small
    echo 🔄 Restart terminal untuk apply changes
) else if "%choice%"=="3" (
    setx WHISPER_MODEL_SIZE "medium"
    echo.
    echo ✅ Model size set to: medium (RECOMMENDED)
    echo 🔄 Restart terminal untuk apply changes
) else if "%choice%"=="4" (
    setx WHISPER_MODEL_SIZE "large-v3"
    echo.
    echo ✅ Model size set to: large-v3
    echo 🔄 Restart terminal untuk apply changes
) else (
    echo.
    echo ℹ️  Using default model size (large-v3)
)

echo.
pause
