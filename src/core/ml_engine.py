import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
import os
import threading
import importlib.util
from pathlib import Path

# Setup DLL paths BEFORE importing faster_whisper
_dll_handles = []

def _add_dll_path(path):
    path = str(path)
    if hasattr(os, "add_dll_directory"):
        try:
            h = os.add_dll_directory(path)
            _dll_handles.append(h)
        except Exception:
            pass
    if path not in os.environ.get("PATH", ""):
        os.environ["PATH"] = path + os.pathsep + os.environ.get("PATH", "")

def _setup_cuda_dll_paths():
    dirs = []
    # nvidia packages (cublas, cudnn)
    spec = importlib.util.find_spec("nvidia")
    if spec and spec.submodule_search_locations:
        base = Path(spec.submodule_search_locations[0])
        for sub in base.iterdir():
            for d in [sub / "bin", sub / "lib"]:
                if d.exists():
                    _add_dll_path(d)
                    dirs.append(str(d))
    # torch/lib
    spec = importlib.util.find_spec("torch")
    if spec and spec.submodule_search_locations:
        tlib = Path(spec.submodule_search_locations[0]) / "lib"
        if tlib.exists():
            _add_dll_path(tlib)
            dirs.append(str(tlib))
    # ctranslate2
    spec = importlib.util.find_spec("ctranslate2")
    if spec and spec.submodule_search_locations:
        ct2 = Path(spec.submodule_search_locations[0])
        if ct2.exists():
            _add_dll_path(ct2)
            dirs.append(str(ct2))
    return dirs

from config import MODEL_SIZE, LOCAL_MODEL_PATH, DEVICE, COMPUTE_TYPE

class MLEngine:
    """Singleton pattern to manage Whisper model lazy loading and GPU fallback."""
    _instance = None
    _model = None
    _model_lock = threading.Lock()

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(MLEngine, cls).__new__(cls)
        return cls._instance

    @classmethod
    def get_model(cls, verbose=True):
        """Load whisper model (singleton, lazy) — try GPU first, fallback to CPU."""
        if cls._model is None:
            with cls._model_lock:
                if cls._model is None:
                    use_local = Path(LOCAL_MODEL_PATH).exists()
                    model_source = LOCAL_MODEL_PATH if use_local else MODEL_SIZE

                    _cuda_dirs = _setup_cuda_dll_paths()
                    if _cuda_dirs and verbose:
                        print(f"🔧 CUDA DLL paths loaded: {len(_cuda_dirs)} folders")

                    from faster_whisper import WhisperModel

                    if verbose:
                        if use_local:
                            print(f"\n🔄 Loading Whisper model from local: {LOCAL_MODEL_PATH}")
                            print("   💾 Saved ~3GB download time!")
                        else:
                            print(f"\n🔄 Loading Whisper model '{MODEL_SIZE}'...")
                            print(f"   ⚠️  Local model not found at: {LOCAL_MODEL_PATH}")
                            print("   📥 Will download automatically (~3GB)")
                        print("   🚀 Attempting to load on GPU (CUDA)...")

                    try:
                        # Check CUDA availability
                        try:
                            import torch
                            if not torch.cuda.is_available():
                                raise RuntimeError("CUDA not available")
                            if verbose:
                                gpu_name = torch.cuda.get_device_name(0)
                                gpu_memory = torch.cuda.get_device_properties(0).total_memory / (1024**3)
                                print(f"    GPU detected: {gpu_name} ({gpu_memory:.1f} GB VRAM)")
                        except ImportError:
                            if verbose:
                                print("   ⚠️  PyTorch not found, cannot verify GPU")
                        except Exception as e:
                            if verbose:
                                print(f"   ⚠️  GPU check failed: {e}")

                        cls._model = WhisperModel(
                            model_source, device=DEVICE, compute_type=COMPUTE_TYPE
                        )

                        if verbose:
                            msg_source = "LOCAL path" if use_local else "cloud"
                            print(f"   ✅ Model loaded on GPU (CUDA) from {msg_source} - FAST! 🎉\n")

                    except Exception as gpu_error:
                        if verbose:
                            print(f"   ⚠️  GPU loading failed: {gpu_error}")
                            print("   🐌 Fallback to CPU (will be slower but more stable)...\n")
                        
                        cls._model = WhisperModel(
                            model_source, device="cpu", compute_type="int8"
                        )
                        if verbose:
                            print("   ✅ Model loaded on CPU\n")
                            
        return cls._model
