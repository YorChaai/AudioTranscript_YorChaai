@echo off
echo ============================================================
echo         CUDA / GPU CHECK
echo ============================================================
echo.

REM Check if torch is installed
python -c "import torch" 2>nul
if errorlevel 1 (
    echo [X] PyTorch not installed!
    echo     Install with: pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
    pause
    exit /b 1
)

echo [+] PyTorch is installed
echo.

REM Check CUDA availability
python -c "import torch; print('CUDA Available:', torch.cuda.is_available())"
python -c "import torch; print('CUDA Version:', torch.version.cuda)"
python -c "import torch; print('GPU Count:', torch.cuda.device_count())"
python -c "import torch; gpu_name = torch.cuda.get_device_name(0) if torch.cuda.device_count() > 0 else 'None'; print('GPU Name:', gpu_name)"
python -c "import torch; gpu_mem = torch.cuda.get_device_properties(0).total_memory / (1024**3) if torch.cuda.device_count() > 0 else 0; print(f'GPU VRAM: {gpu_mem:.1f} GB')"

echo.
echo ============================================================
echo         FASTER-WHISPER MODEL TEST
echo ============================================================
echo.
echo Testing model load (this will take a moment)...
echo.

REM Test with current model size
python -c "from faster_whisper import WhisperModel; print('Loading model...'); model = WhisperModel('tiny', device='cuda', compute_type='float16'); print('SUCCESS!')" 2>&1

if errorlevel 1 (
    echo.
    echo [X] Failed to load model on GPU
    echo     Trying CPU...
    python -c "from faster_whisper import WhisperModel; print('Loading model on CPU...'); model = WhisperModel('tiny', device='cpu', compute_type='int8'); print('SUCCESS on CPU!')"
)

echo.
echo ============================================================
pause
