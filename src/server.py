"""
Flask API Server - wrapper untuk transcribe.py dan convert_pdf.py
Jalankan: python server.py
Server akan listen di 0.0.0.0:5000

Semua proses berat (transcribe) jalan di background thread.
HP hanya kirim request, semua file disimpan di server.
"""

import json
import logging
import os
import subprocess
import sys
import shutil
import threading
import time
import uuid
from datetime import datetime
from pathlib import Path

from flask import Flask, Response, jsonify, request, send_file, stream_with_context
from flask_cors import CORS
from tqdm import tqdm
from werkzeug.utils import secure_filename

from pdf_utils import get_pdf_files, merge_all_pdfs  # Fix H7: Shared PDF utilities
from utils import format_time_srt  # Fix M5: Use shared format_time utility

try:
    from pypdf import PdfWriter
except ImportError:
    PdfWriter = None  # Handle gracefully if not installed

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# Load .env file for environment variables (must be before any os.environ.get() calls)
from dotenv import load_dotenv

_env_path = Path(__file__).parent.parent / ".env"  # Project root
if _env_path.exists():
    load_dotenv(_env_path)
    print(f"✅ Loaded .env file from: {_env_path}")

# setup logging — pakai werkzeug logger biar rapi
log = logging.getLogger("werkzeug")
log.setLevel(logging.ERROR)  # Silence request logs (GET /api/...)


# pke print biasa aja buat log kita sendiri biar gak ikut ke-silence
def info(msg):
    print(f"ℹ️ {msg}")


# Fix M2: Constants for progress calculation (avoid magic numbers)
PROGRESS_MIN = 1
PROGRESS_MAX = 99
PROGRESS_LOADING = 1
PROGRESS_TRANSCRIBING_MIN = 1
PROGRESS_TRANSCRIBING_MAX = 99
PROGRESS_SAVING = 99
PROGRESS_COMPLETED = 100

# Fix M6: Rate limiting settings
RATE_LIMIT_REQUESTS = 100  # max requests per window
RATE_LIMIT_WINDOW = 60  # window in seconds
_rate_limit_cache = {}  # ip -> list of request timestamps
_rate_limit_lock = threading.Lock()


def _check_rate_limit(client_ip: str) -> bool:
    """
    Check if client IP has exceeded rate limit.
    Returns True if request is allowed, False if rate limited.
    """
    now = time.time()
    window_start = now - RATE_LIMIT_WINDOW

    with _rate_limit_lock:
        if client_ip not in _rate_limit_cache:
            _rate_limit_cache[client_ip] = []

        # Remove old timestamps outside window
        _rate_limit_cache[client_ip] = [
            ts for ts in _rate_limit_cache[client_ip] if ts > window_start
        ]

        # Fix H7: Cleanup empty entries to prevent memory leak
        if not _rate_limit_cache[client_ip]:
            del _rate_limit_cache[client_ip]
            _rate_limit_cache[client_ip] = []

        # Check if limit exceeded
        if len(_rate_limit_cache[client_ip]) >= RATE_LIMIT_REQUESTS:
            return False

        # Add current request
        _rate_limit_cache[client_ip].append(now)
        return True


def _cleanup_rate_limit_cache():
    """
    Periodic cleanup of rate limit cache to prevent memory leak.
    Remove IPs that haven't made requests in the last hour.
    """
    now = time.time()
    cleanup_threshold = 3600  # 1 hour

    with _rate_limit_lock:
        empty_ips = []
        for ip, timestamps in list(_rate_limit_cache.items()):
            # Keep only recent timestamps (last hour)
            recent_timestamps = [
                ts for ts in timestamps if ts > now - cleanup_threshold
            ]
            if recent_timestamps:
                _rate_limit_cache[ip] = recent_timestamps
            else:
                empty_ips.append(ip)

        # Remove IPs with no recent activity
        for ip in empty_ips:
            _rate_limit_cache.pop(ip, None)

        if empty_ips:
            info(f"🧹 Cleaned up {len(empty_ips)} inactive IPs from rate limit cache")


# Call cleanup periodically (every 1000 requests approximately)
_cleanup_counter = 0


def _get_client_ip() -> str:
    """Get client IP from request"""
    if request.headers.get("X-Forwarded-For"):
        return request.headers.get("X-Forwarded-For").split(",")[0].strip()
    return request.remote_addr or "unknown"


def _rate_limited_endpoint(f):
    """Decorator to add rate limiting to endpoints"""
    from functools import wraps

    global _cleanup_counter

    @wraps(f)
    def decorated_function(*args, **kwargs):
        global _cleanup_counter

        client_ip = _get_client_ip()
        if not _check_rate_limit(client_ip):
            info(f"⚠️ Rate limit exceeded for IP: {client_ip}")
            return jsonify(
                {
                    "error": "Rate limit exceeded. Please try again later.",
                    "limit": RATE_LIMIT_REQUESTS,
                    "window": f"{RATE_LIMIT_WINDOW}s",
                }
            ), 429

        # Fix H7: Periodic cleanup of rate limit cache (every 1000 requests)
        _cleanup_counter += 1
        if _cleanup_counter >= 1000:
            _cleanup_rate_limit_cache()
            _cleanup_counter = 0

        return f(*args, **kwargs)

    return decorated_function


# project imports
import importlib.util

import database as db

# Fix H7: Import shared utilities
from utils import find_ffmpeg, get_audio_info_technical, repair_audio_ffmpeg

# ============================================================
# setup DLL paths untuk CUDA (cublas, cudnn) — SEBELUM import faster_whisper
# ============================================================
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


_cuda_dirs = _setup_cuda_dll_paths()
if _cuda_dirs:
    print(f"\U0001f527 CUDA DLL paths: {len(_cuda_dirs)} folder")

from faster_whisper import WhisperModel

print("\u2705 faster_whisper imported (DLL OK)")

# Local model path - use pre-downloaded model from D:\model to save C: drive space
# If model not found locally, will auto-download to cache
LOCAL_MODEL_PATH = os.environ.get("WHISPER_MODEL_PATH", "D:\\model\\large-v3")

BASE_DIR = Path(__file__).parent.parent  # Project root (src/ is subdir)
AUDIO_FOLDER = BASE_DIR / "audio"
CONVERT_DIR = BASE_DIR / "output"
UPLOADS_DIR = BASE_DIR / "server" / "uploads"
VIDEO_UPLOAD_FOLDER = UPLOADS_DIR / "video"

# supported audio formats
AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".flac", ".ogg", ".wma", ".aac"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".mpeg", ".mpg", ".m4v"}

app = Flask(__name__)
CORS(app)

import os
from functools import wraps

API_KEY = os.environ.get("API_KEY", "YORCHAAI_SECRET_KEY")


def require_api_key(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if request.endpoint == "health_check":
            return f(*args, **kwargs)
        key = request.headers.get("X-Api-Key")
        if key == API_KEY:
            return f(*args, **kwargs)
        return jsonify({"error": "Unauthorized: Invalid API Key"}), 401

    return decorated_function


app.config["MAX_CONTENT_LENGTH"] = 500 * 1024 * 1024  # max upload 500MB

# ============================================================
# model dan transcribe reference (lazy load)
# ============================================================
_model = None
_model_lock = threading.Lock()
_cancel_flags = {}  # job_id -> bool, untuk cancel transcribe
_jobs_cache = {}  # in-memory cache agar polling status gak buka DB terus
_jobs_cache_lock = threading.Lock()  # Fix C5: thread-safe cache access


# Fix C5: Cleanup routine untuk jobs yang sudah selesai
def _cleanup_old_jobs(max_age_hours=24):
    """
    hapus jobs dari cache yang sudah selesai lebih dari max_age_hours
    Dipanggil secara periodic untuk mencegah memory leak
    """
    now = datetime.now()
    jobs_to_remove = []

    with _jobs_cache_lock:
        for job_id, job_data in _jobs_cache.items():
            # Hanya cleanup jobs yang sudah completed/error/cancelled
            if job_data.get("status") in ("completed", "error", "cancelled"):
                # Check age jika ada updated_at
                if "updated_at" in job_data:
                    try:
                        updated = datetime.fromisoformat(job_data["updated_at"])
                        age_hours = (now - updated).total_seconds() / 3600
                        if age_hours > max_age_hours:
                            jobs_to_remove.append(job_id)
                    except Exception:
                        # Jika parse gagal, hapus saja
                        jobs_to_remove.append(job_id)
                else:
                    # Tidak ada timestamp, asumsikan sudah lama
                    jobs_to_remove.append(job_id)

        for job_id in jobs_to_remove:
            _jobs_cache.pop(job_id, None)

        if jobs_to_remove:
            print(f"🧹 Cleaned up {len(jobs_to_remove)} old jobs from cache")

    return len(jobs_to_remove)


def _get_model():
    """load whisper model (singleton, lazy) — coba GPU dulu, fallback ke CPU"""
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                # Determine model source
                use_local = Path(LOCAL_MODEL_PATH).exists()

                if use_local:
                    print(f"\n🔄 Loading Whisper model from local: {LOCAL_MODEL_PATH}")
                    print("   💾 Saved ~3GB download time!")
                else:
                    print("\n🔄 Loading Whisper model (large-v3)...")
                    print(f"   ⚠️  Local model not found at: {LOCAL_MODEL_PATH}")
                    print("   📥 Will download automatically (~3GB)")

                try:
                    print("   📍 Attempting GPU (CUDA) mode...")
                    model_source = LOCAL_MODEL_PATH if use_local else "large-v3"
                    _model = WhisperModel(
                        model_source, device="cuda", compute_type="float16"
                    )
                    if use_local:
                        print(
                            "   ✅ Model loaded on GPU (CUDA) from LOCAL path - FAST! 🎉\n"
                        )
                    else:
                        print("   ✅ Model loaded on GPU (CUDA) - FAST! 🎉\n")
                except Exception as e:
                    print(f"   ⚠️ GPU not available: {e}")
                    print("   🐌 Fallback ke CPU (akan lebih lambat)...\n")
                    model_source = LOCAL_MODEL_PATH if use_local else "large-v3"
                    _model = WhisperModel(
                        model_source, device="cpu", compute_type="int8"
                    )
                    print("   ✅ Model loaded on CPU\n")
    return _model


def _ensure_media_dirs():
    AUDIO_FOLDER.mkdir(parents=True, exist_ok=True)
    VIDEO_UPLOAD_FOLDER.mkdir(parents=True, exist_ok=True)


def _unique_path(folder: Path, filename: str) -> Path:
    candidate = folder / filename
    if not candidate.exists():
        return candidate

    stem = candidate.stem
    suffix = candidate.suffix
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    counter = 1

    while True:
        alt = folder / f"{stem}_{timestamp}_{counter}{suffix}"
        if not alt.exists():
            return alt
        counter += 1


def _find_ffmpeg():
    # Fix H7: Use shared ffmpeg finder
    return find_ffmpeg(BASE_DIR)


def _convert_video_to_mp3(video_path: Path, target_dir: Path = None) -> tuple[Path, list[str]]:
    _ensure_media_dirs()
    
    if target_dir is None:
        target_dir = AUDIO_FOLDER

    mp3_name = f"{video_path.stem}.mp3"
    output_path = _unique_path(target_dir, mp3_name)
    ffmpeg_bin = _find_ffmpeg()

    command = [
        ffmpeg_bin,
        "-y",
        "-i",
        str(video_path),
        "-vn",
        "-acodec",
        "libmp3lame",
        "-q:a",
        "2",
        str(output_path),
    ]

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
    )

    logs = []
    if result.stdout.strip():
        logs.append(result.stdout.strip())
    if result.stderr.strip():
        logs.append(result.stderr.strip())

    if result.returncode != 0:
        raise RuntimeError(
            "FFmpeg gagal mengubah video ke MP3. "
            "Pastikan FFmpeg terinstall atau set FFMPEG_PATH dengan benar.\n"
            + "\n".join(logs[-2:])
        )

    if not output_path.exists() or output_path.stat().st_size == 0:
        raise RuntimeError("File MP3 hasil convert tidak berhasil dibuat.")

    return output_path, logs


# ============================================================
# HEALTH CHECK
# ============================================================
# Fix L2: Track health check calls for sampling
_health_check_count = 0
_health_check_last_log = 0


@app.route("/api/health", methods=["GET"])
@_rate_limited_endpoint  # Fix M6: Also rate limit health checks
def health_check():
    """cek server status"""
    # Fix L2: Only log every 100 health checks to reduce noise
    global _health_check_count, _health_check_last_log
    _health_check_count += 1

    if _health_check_count % 100 == 0:
        now = time.time()
        if now - _health_check_last_log > 60:  # Log at most once per minute
            info(f"📊 Health check called {_health_check_count} times")
            _health_check_last_log = now

    return jsonify(
        {
            "status": "ok",
            "timestamp": datetime.now().isoformat(),
            "model_loaded": _model is not None,
        }
    )


# ============================================================
# AUDIO FILES
# ============================================================
@app.route("/api/audio/list", methods=["GET"])
@require_api_key
def list_audio():
    """list semua file audio di folder audio/"""
    from tinytag import TinyTag
    target_path = request.args.get("path", "")
    target_dir = AUDIO_FOLDER
    if target_path:
        try:
            target_dir = (AUDIO_FOLDER / target_path).resolve()
            # Ensure it's within AUDIO_FOLDER
            if AUDIO_FOLDER.resolve() not in target_dir.parents and target_dir != AUDIO_FOLDER.resolve():
                return jsonify({"error": "Invalid path"}), 400
        except Exception:
            return jsonify({"error": "Invalid path"}), 400

    if not target_dir.exists():
        target_dir.mkdir(parents=True, exist_ok=True)
        return jsonify({"files": [], "folders": [], "current_path": target_path})

    files = []
    # Only show audio files, don't show videos as requested by user
    for f in sorted(target_dir.iterdir()):
        if f.is_file() and f.suffix.lower() in AUDIO_EXTENSIONS:
            file_info = {
                "name": f.name,
                "path": str(f.relative_to(BASE_DIR)),
                "size": f.stat().st_size,
                "modified": datetime.fromtimestamp(f.stat().st_mtime).isoformat(),
            }

            # Use TinyTag for fast duration loading instead of ffprobe
            try:
                tag = TinyTag.get(str(f))
                if tag.duration is not None:
                    file_info["duration"] = tag.duration
                if tag.bitrate is not None:
                    # TinyTag returns bitrate in kbits, ffprobe returns bps. So we convert to bps.
                    file_info["bitrate"] = int(tag.bitrate * 1000)
            except Exception:
                pass

            files.append(file_info)

    # list subfolders too
    folders = []
    for f in sorted(target_dir.iterdir()):
        if f.is_dir():
            # count audio files recursively
            count = sum(
                1
                for x in f.rglob("*")
                if x.is_file() and x.suffix.lower() in AUDIO_EXTENSIONS
            )
            folders.append(
                {
                    "name": f.name,
                    "path": str(f.relative_to(AUDIO_FOLDER)),
                    "file_count": count,
                }
            )

    return jsonify({"files": files, "folders": folders, "current_path": target_path})


@app.route("/api/folder/create", methods=["POST"])
@require_api_key
def create_playlist():
    """Create a new playlist (folder) in audio directory"""
    data = request.json or {}
    name = data.get("name", "").strip()
    target_path = data.get("path", "")
    
    if not name:
        return jsonify({"error": "Nama playlist tidak boleh kosong"}), 400
        
    # Validasi nama folder (hilangkan karakter aneh)
    safe_name = secure_filename(name)
    if not safe_name:
        safe_name = name.replace(" ", "_").replace("/", "").replace("\\", "")
        
    target_dir = AUDIO_FOLDER
    if target_path:
        try:
            target_dir = (AUDIO_FOLDER / target_path).resolve()
            if AUDIO_FOLDER.resolve() not in target_dir.parents and target_dir != AUDIO_FOLDER.resolve():
                target_dir = AUDIO_FOLDER
        except Exception:
            pass
            
    new_dir = target_dir / safe_name
    new_dir.mkdir(parents=True, exist_ok=True)
    
    return jsonify({
        "status": "ok", 
        "name": new_dir.name,
        "path": str(new_dir.relative_to(AUDIO_FOLDER))
    })


@app.route("/api/file/move", methods=["POST"])
@require_api_key
def move_files():
    """Move audio files to a different folder"""
    data = request.json or {}
    files = data.get("files", [])
    target_path = data.get("targetPath", "")
    
    if not isinstance(files, list) or not files:
        return jsonify({"error": "Daftar file kosong"}), 400
        
    target_dir = AUDIO_FOLDER
    if target_path:
        try:
            target_dir = (AUDIO_FOLDER / target_path).resolve()
            if AUDIO_FOLDER.resolve() not in target_dir.parents and target_dir != AUDIO_FOLDER.resolve():
                target_dir = AUDIO_FOLDER
        except Exception:
            pass
            
    target_dir.mkdir(parents=True, exist_ok=True)
    
    moved = []
    errors = []
    for file_path in files:
        try:
            # list_audio returns file paths relative to BASE_DIR (e.g. 'audio/filename.mp3')
            file_path_str = str(file_path)
            if file_path_str.startswith("audio/") or file_path_str.startswith("audio\\"):
                src = (BASE_DIR / file_path_str).resolve()
            else:
                src = (AUDIO_FOLDER / file_path_str).resolve()
                
            if AUDIO_FOLDER.resolve() not in src.parents:
                errors.append(f"{file_path} tidak valid (bukan di dalam folder audio)")
                continue
                
            if src.exists() and src.is_file():
                dest = _unique_path(target_dir, src.name)
                shutil.move(str(src), str(dest))
                moved.append(file_path)
            else:
                errors.append(f"{file_path} tidak ditemukan di server")
        except Exception as e:
            errors.append(f"{file_path}: {str(e)}")
            
    return jsonify({"status": "ok", "moved": moved, "errors": errors})


@app.route("/api/audio/upload", methods=["POST"])
@require_api_key
def upload_audio():
    """upload file audio dari HP ke server"""
    if "file" not in request.files:
        return jsonify({"error": "File tidak ditemukan"}), 400

    file = request.files["file"]
    if file.filename == "":
        return jsonify({"error": "Filename kosong"}), 400

    ext = Path(file.filename).suffix.lower()
    if ext not in AUDIO_EXTENSIONS:
        return jsonify({"error": f"Format audio tidak didukung: {ext}"}), 400

    filename = secure_filename(file.filename)
    
    target_path = request.form.get("path", "")
    target_dir = AUDIO_FOLDER
    if target_path:
        try:
            target_dir = (AUDIO_FOLDER / target_path).resolve()
            if AUDIO_FOLDER.resolve() not in target_dir.parents and target_dir != AUDIO_FOLDER.resolve():
                target_dir = AUDIO_FOLDER
        except Exception:
            pass
            
    target_dir.mkdir(parents=True, exist_ok=True)
    _ensure_media_dirs()
    save_path = _unique_path(target_dir, filename)

    # Fix M9: Save file with progress tracking for large files
    file_size = file.content_length or 0
    chunk_size = 1024 * 1024  # 1MB chunks
    uploaded = 0

    with open(save_path, "wb") as f:
        while True:
            chunk = file.stream.read(chunk_size)
            if not chunk:
                break
            f.write(chunk)
            uploaded += len(chunk)

            # Log progress for large files (>10MB)
            if file_size > 10 * 1024 * 1024:
                progress = (uploaded / file_size) * 100
                if uploaded % (10 * 1024 * 1024) < chunk_size:  # Log every 10MB
                    info(
                        f"📤 Upload progress: {progress:.1f}% ({uploaded}/{file_size} bytes)"
                    )

    return jsonify(
        {
            "status": "ok",
            "media_type": "audio",
            "filename": save_path.name,
            "path": str(save_path.relative_to(BASE_DIR)),
            "size": save_path.stat().st_size,
        }
    )


@app.route("/api/video/upload-convert", methods=["POST"])
@require_api_key
def upload_and_convert_video():
    """upload video, convert ke mp3, lalu hapus file video asli"""
    if "file" not in request.files:
        return jsonify({"error": "File tidak ditemukan"}), 400

    file = request.files["file"]
    if file.filename == "":
        return jsonify({"error": "Filename kosong"}), 400

    ext = Path(file.filename).suffix.lower()
    if ext not in VIDEO_EXTENSIONS:
        return jsonify({"error": f"Format video tidak didukung: {ext}"}), 400

    filename = secure_filename(file.filename)
    
    target_path = request.form.get("path", "")
    target_dir = AUDIO_FOLDER
    if target_path:
        try:
            target_dir = (AUDIO_FOLDER / target_path).resolve()
            if AUDIO_FOLDER.resolve() not in target_dir.parents and target_dir != AUDIO_FOLDER.resolve():
                target_dir = AUDIO_FOLDER
        except Exception:
            pass

    target_dir.mkdir(parents=True, exist_ok=True)
    _ensure_media_dirs()
    temp_video_path = _unique_path(VIDEO_UPLOAD_FOLDER, filename)

    try:
        file.save(str(temp_video_path))
        info(f"🎬 Video uploaded: {temp_video_path.name}")

        mp3_path, logs = _convert_video_to_mp3(temp_video_path, target_dir)
        info(f"🎵 Video converted to MP3: {mp3_path.name}")

        return jsonify(
            {
                "status": "ok",
                "media_type": "video_converted",
                "source_deleted": True,
                "source_filename": filename,
                "filename": mp3_path.name,
                "path": str(mp3_path.relative_to(BASE_DIR)),
                "size": mp3_path.stat().st_size,
                "message": "Video berhasil di-convert ke MP3 dan dipindahkan ke folder audio",
            }
        )
    except Exception as e:
        info(f"❌ Video upload/convert error: {e}")
        return jsonify(
            {
                "error": str(e),
                "media_type": "video_converted",
            }
        ), 500
    finally:
        # Fix C3: Guaranteed cleanup of temp video file
        try:
            if temp_video_path.exists():
                temp_video_path.unlink(missing_ok=True)
                info(f"🗑️ Temp video cleaned up: {temp_video_path.name}")
        except Exception as cleanup_err:
            info(f"⚠️ Failed to cleanup temp video: {cleanup_err}")


# ============================================================
# SUMMARY API
# ============================================================
from summarytext import (
    clean_transcript,
    extract_metadata,
    generate_summary,
    save_summary,
)


@app.route("/api/summary", methods=["POST"])
@require_api_key
def start_summary():
    """mulai membuat summary (ringkasan) via Ollama"""
    data = request.get_json()
    if not data:
        return jsonify({"error": "Body JSON required"}), 400

    txt_file = data.get("txt_file")  # contoh: output/single/file.txt
    model_name = data.get("model", "qwen3:8b")

    if not txt_file:
        return jsonify({"error": "txt_file required"}), 400

    txt_path = BASE_DIR / txt_file
    if not txt_path.exists():
        return jsonify({"error": f"File tidak ditemukan: {txt_file}"}), 404

    # buat job
    job_id = str(uuid.uuid4())[:8]
    db.create_job(job_id, "summary", txt_file, "auto", False, "id")

    def _run_summary(j_id, t_path, m_name):
        try:
            now = datetime.now().isoformat()
            with _jobs_cache_lock:
                _jobs_cache[j_id] = {
                    "id": j_id,
                    "status": "generating_summary",
                    "progress": 10,
                    "created_at": now,
                    "updated_at": now,
                }

            with open(t_path, "r", encoding="utf-8") as f:
                raw_text = f.read()

            metadata = extract_metadata(raw_text)
            cleaned_text = clean_transcript(raw_text)

            with _jobs_cache_lock:
                _jobs_cache[j_id]["progress"] = 30
                _jobs_cache[j_id]["status"] = "waiting_ollama"

            summary = generate_summary(
                cleaned_text, m_name, language=metadata.get("language", "id")
            )

            with _jobs_cache_lock:
                _jobs_cache[j_id]["progress"] = 90
                _jobs_cache[j_id]["status"] = "saving"

            save_summary(t_path, summary, m_name)

            # Update DB & Cache
            db.update_job(j_id, "completed", error=None)
            with _jobs_cache_lock:
                _jobs_cache[j_id]["progress"] = 100
                _jobs_cache[j_id]["status"] = "completed"
                _jobs_cache[j_id]["updated_at"] = datetime.now().isoformat()

        except Exception as e:
            print(f"Error summary {j_id}: {e}")
            db.update_job(j_id, "failed", error=str(e))
            with _jobs_cache_lock:
                _jobs_cache[j_id]["status"] = "failed"
                _jobs_cache[j_id]["error"] = str(e)

    thread = threading.Thread(
        target=_run_summary, args=(job_id, txt_path, model_name), daemon=True
    )
    thread.start()

    return jsonify({"job_id": job_id, "status": "started"})


# ============================================================
# TRANSCRIBE
# ============================================================
@app.route("/api/transcribe", methods=["POST"])
@require_api_key
def start_transcribe():
    """mulai transcribe audio — berjalan di background thread"""
    data = request.get_json()
    if not data:
        return jsonify({"error": "Body JSON required"}), 400

    audio_files = data.get("audio_files")
    if not audio_files:
        audio_file = data.get("audio_file")  # backward compatibility
        if audio_file:
            audio_files = [audio_file]

    if not audio_files or not isinstance(audio_files, list):
        return jsonify({"error": "audio_files (list of paths) required"}), 400

    language = data.get("language", "auto")
    do_translate = data.get("translate", False)
    target_lang = data.get("target_lang", "id")

    job_ids = []
    valid_files = []

    for f in audio_files:
        audio_path = BASE_DIR / f
        if not audio_path.exists():
            return jsonify({"error": f"File tidak ditemukan: {f}"}), 404

        job_id = str(uuid.uuid4())[:8]
        db.create_job(job_id, "transcribe", f, language, do_translate, target_lang)
        job_ids.append(job_id)
        valid_files.append((job_id, audio_path))

    # jalankan di background secara sekuensial agar tidak OOM VRAM GPU
    def process_batch():
        for j_id, a_path in valid_files:
            _run_transcribe(j_id, a_path, language, do_translate, target_lang)

    thread = threading.Thread(target=process_batch, daemon=True)
    thread.start()

    # kembalikan job_id tunggal untuk backward compatibility, dan job_ids array
    return jsonify(
        {
            "job_id": job_ids[0] if job_ids else None,
            "job_ids": job_ids,
            "status": "started",
        }
    )


def _run_transcribe(job_id, audio_path, language, do_translate, target_lang):
    """background task untuk transcribe — real-time progress via tqdm + in-memory cache"""
    try:
        now = datetime.now().isoformat()
        # Fix C1: Initialize job with .update() pattern for consistency
        with _jobs_cache_lock:
            _jobs_cache[job_id] = {
                "id": job_id,
                "status": "loading_model",
                "progress": 1,
                "created_at": now,
                "updated_at": now,
            }
        print(f"🔄 Job {job_id}: loading model...")

        # Fix M10: Check if audio file still exists before processing
        if not audio_path.exists():
            error_msg = f"Audio file not found: {audio_path}"
            print(f"❌ Job {job_id}: {error_msg}")
            with _jobs_cache_lock:
                _jobs_cache[job_id] = {
                    "id": job_id,
                    "status": "error",
                    "progress": 0,
                    "error": error_msg,
                    "updated_at": datetime.now().isoformat(),
                }
            db.update_job(job_id, status="error", error=error_msg)
            db.add_history(
                job_id,
                "transcribe",
                str(audio_path.name),
                None,
                language,
                "error",
                metadata={"error": error_msg},
            )
            return

        # Fix C5: Cleanup old jobs periodic (setiap ada job baru)
        _cleanup_old_jobs(max_age_hours=24)

        model = _get_model()

        # cek cancel sebelum mulai transcribe
        if _cancel_flags.get(job_id):
            with _jobs_cache_lock:
                _jobs_cache[job_id] = {
                    "id": job_id,
                    "status": "cancelled",
                    "progress": 0,
                    "updated_at": datetime.now().isoformat(),
                }
            db.update_job(job_id, status="cancelled", progress=0)
            _cancel_flags.pop(job_id, None)
            return

        with _jobs_cache_lock:
            _jobs_cache[job_id]["status"] = "transcribing"

        # transcribe — dapatkan generator (JANGAN di-list()!)
        lang_param = None if language == "auto" else language

        # --- PRE-CHECK TEKNIS ---
        tech_info = get_audio_info_technical(audio_path)
        actual_audio_path = audio_path
        is_temp = False

        def _start_transcribe(mdl, path):
            """mulai transcribe, return (generator, info) — BUKAN list!"""
            segs_gen, inf = mdl.transcribe(
                str(path),
                language=lang_param,
                beam_size=5,
                word_timestamps=True,
                vad_filter=True,
            )
            return segs_gen, inf

        try:
            segs_gen, info = _start_transcribe(model, actual_audio_path)
        except Exception as cuda_err:
            if "cublas" in str(cuda_err).lower() or "cuda" in str(cuda_err).lower():
                print(f"⚠️ GPU gagal saat transcribe: {cuda_err}")
                print("🔄 Reload model ke CPU dan coba ulang...")
                # Fix C1: Use .update() to avoid race condition
                with _jobs_cache_lock:
                    if job_id in _jobs_cache:
                        _jobs_cache[job_id].update(
                            {
                                "status": "loading_model",
                                "progress": 1,
                                "error": "GPU gagal, switching ke CPU...",
                            }
                        )
                global _model
                model_source = (
                    LOCAL_MODEL_PATH if Path(LOCAL_MODEL_PATH).exists() else "large-v3"
                )
                _model = WhisperModel(model_source, device="cpu", compute_type="int8")
                model = _model
                print("✅ Model loaded (CPU)!")
                with _jobs_cache_lock:
                    if job_id in _jobs_cache:
                        _jobs_cache[job_id]["status"] = "transcribing"
                segs_gen, info = _start_transcribe(model, actual_audio_path)
            else:
                raise

        total_duration = info.duration

        # --- AUTO-REPAIR LOGIC ---
        if tech_info["success"] and abs(total_duration - tech_info["duration"]) > 10:
            print(
                f"⚠️ Job {job_id}: MISMATCH DETECTED! Whisper reads {total_duration:.1f}s but file is {tech_info['duration']:.1f}s."
            )
            print(f"🚀 Job {job_id}: AUTO-REPAIR starting...")

            repaired_path = repair_audio_ffmpeg(audio_path)
            if repaired_path:
                actual_audio_path = repaired_path
                is_temp = True

                # Re-transcribe dengan file yang sudah diperbaiki
                segs_gen, info = _start_transcribe(model, actual_audio_path)
                total_duration = info.duration
                print(
                    f"✅ Job {job_id}: Retrying with repaired file. New duration: {total_duration:.1f}s"
                )
            else:
                print(
                    f"❌ Job {job_id}: Auto-repair failed. Continuing with original file."
                )

        detected = info.language
        prob = info.language_probability

        print(
            f"🎤 Job {job_id}: transcribing {audio_path.name} ({total_duration:.0f}s, lang={detected})"
        )

        full_text = ""
        all_segments = []
        last_end = 0
        segment_num = (
            0  # Counter for performance optimization (update every N segments)
        )

        # tqdm progress bar di terminal
        pbar = tqdm(
            total=total_duration,
            unit="s",
            unit_scale=True,
            desc=f"Job {job_id}",
            bar_format="{l_bar}{bar}| {n:.0f}/{total:.0f}s [{elapsed}<{remaining}]",
        )

        for segment in segs_gen:
            segment_num += 1  # Increment segment counter
            # cek cancel di tengah transcribe
            if _cancel_flags.get(job_id):
                pbar.close()
                # Fix C1: Use .update() to avoid race condition
                with _jobs_cache_lock:
                    if job_id in _jobs_cache:
                        _jobs_cache[job_id].update(
                            {
                                "status": "cancelled",
                                "progress": 0,
                                "updated_at": datetime.now().isoformat(),
                            }
                        )
                db.update_job(job_id, status="cancelled", progress=0)
                _cancel_flags.pop(job_id, None)
                print(f"🛑 Job {job_id} dibatalkan")
                return

            text = segment.text.strip()
            full_text += text + "\n"
            all_segments.append(
                {"start": segment.start, "end": segment.end, "text": text}
            )

            # update tqdm di terminal
            increment = segment.end - last_end
            if increment > 0:
                pbar.update(increment)

            # update progress di memory (TANPA DB — polling baca dari sini)
            # Fix C1: Update only changed fields to avoid race condition (performance optimization)
            if total_duration > 0:
                progress = PROGRESS_TRANSCRIBING_MIN + (
                    segment.end / total_duration
                ) * (PROGRESS_TRANSCRIBING_MAX - PROGRESS_TRANSCRIBING_MIN)
                # Update every 5 segments to reduce lock contention (performance optimization)
                if segment_num % 5 == 0:
                    with _jobs_cache_lock:
                        if job_id in _jobs_cache:
                            _jobs_cache[job_id]["progress"] = min(
                                progress, PROGRESS_MAX
                            )
                            _jobs_cache[job_id]["status"] = "transcribing"
                            _jobs_cache[job_id]["updated_at"] = (
                                datetime.now().isoformat()
                            )
            last_end = segment.end

        # pastikan tqdm 100%
        remaining = total_duration - last_end
        if remaining > 0:
            pbar.update(remaining)
        pbar.close()

        # Cleanup temp file if created
        if is_temp and actual_audio_path.exists():
            try:
                actual_audio_path.unlink()
                print(f"🧹 Cleaned up temporary repaired file for job {job_id}.")
            except Exception as e:
                print(f"⚠️ Could not delete temp file: {e}")

        # Fix C1: Use .update() to avoid race condition
        with _jobs_cache_lock:
            if job_id in _jobs_cache:
                _jobs_cache[job_id].update(
                    {
                        "status": "saving",
                        "progress": PROGRESS_SAVING,
                        "updated_at": datetime.now().isoformat(),
                    }
                )
        print(f"💾 Job {job_id}: menyimpan hasil...")

        # translate jika diminta
        translated_text = None
        final_target_lang = target_lang
        import transcribe as tr

        should_translate, final_target_lang = tr.resolve_translation_target(
            detected, do_translate, target_lang
        )
        if should_translate:
            # Fix C1: Use .update() to avoid race condition
            with _jobs_cache_lock:
                if job_id in _jobs_cache:
                    _jobs_cache[job_id].update(
                        {
                            "status": "translating",
                            "progress": PROGRESS_SAVING,
                            "updated_at": datetime.now().isoformat(),
                        }
                    )
            print(f"🚀 [VERSI BARU 2.1] Job {job_id}: translating ke {target_lang}...")
            try:
                tr.load_glossary()
                # USE SMART TEXT for translation to get natural context
                smart_text = tr.prepare_smart_text(all_segments, detected)
                # Pass detected language to tr.translate_text
                translated_text = tr.translate_text(
                    smart_text, final_target_lang, source_lang=detected
                )
            except Exception as te:
                print(f"Translation error: {te}")

        db.update_job(job_id, progress=PROGRESS_SAVING)

        # simpan file output sesuai struktur folder audio
        try:
            rel_path = audio_path.parent.relative_to(AUDIO_FOLDER)
            output_dir = CONVERT_DIR / "single" / rel_path
        except ValueError:
            output_dir = CONVERT_DIR / "single"
            
        output_dir.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_name = f"{audio_path.stem}_transcript_{timestamp}.txt"
        output_path = output_dir / output_name

        # tulis file transcript
        SUPPORTED_LANGS = {
            "id": "Indonesian",
            "en": "English",
            "ja": "Japanese",
            "auto": "Auto-detect (Mixed)",
        }
        lang_mode = SUPPORTED_LANGS.get(language, "Auto")

        # Fix M5: Use shared format_time from utils.py
        # (duplicate function removed)

        with open(output_path, "w", encoding="utf-8") as f:
            f.write(f"Source: {audio_path.name}\n")
            f.write(f"Language Mode: {lang_mode}\n")
            f.write(f"Detected: {detected} ({prob:.1%})\n")
            f.write(f"Transcribed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write("=" * 50 + "\n\n")

            semicolon_text = " ; ".join([s["text"].strip() for s in all_segments])
            f.write(semicolon_text)

            f.write("\n\n" + "=" * 50 + "\n")
            f.write("TIMESTAMPS (SRT Format):\n\n")
            for i, seg in enumerate(all_segments, 1):
                start = format_time_srt(seg["start"])
                end = format_time_srt(seg["end"])
                f.write(f"{i}\n")
                f.write(f"{start} --> {end}\n")
                f.write(f"{seg['text'].strip()}\n\n")

            if translated_text:
                f.write("=" * 50 + "\n\n")
                f.write(f"TRANSLATION ({final_target_lang.upper()}):\n\n")
                f.write(translated_text)
                f.write("\n\n")

        # 2. Save pure SRT (VLC/Player Format)
        srt_path = output_path.with_suffix(".srt")
        with open(srt_path, "w", encoding="utf-8") as f:
            for i, seg in enumerate(all_segments, 1):
                start = format_time_srt(seg["start"])
                end = format_time_srt(seg["end"])
                f.write(f"{i}\n")
                f.write(f"{start} --> {end}\n")
                f.write(f"{seg['text'].strip()}\n\n")

        # update job selesai — tulis ke DB + cache
        db.update_job(
            job_id,
            status="completed",
            progress=PROGRESS_COMPLETED,
            output_file=str(output_path.relative_to(BASE_DIR)),
            duration_seconds=(
                datetime.now()
                - datetime.fromisoformat(db.get_job(job_id)["created_at"])
            ).total_seconds(),
        )
        # Fix M2: Use constants instead of magic numbers
        with _jobs_cache_lock:
            _jobs_cache[job_id] = {
                "id": job_id,
                "status": "completed",
                "progress": PROGRESS_COMPLETED,
                "output_file": str(output_path.relative_to(BASE_DIR)),
                "updated_at": datetime.now().isoformat(),
            }

        # simpan history
        db.add_history(
            job_id,
            "transcribe",
            audio_path.name,
            str(output_path.relative_to(BASE_DIR)),
            language,
            "completed",
            metadata={
                "detected_lang": detected,
                "probability": prob,
                "duration": total_duration,
            },
        )

        print(f"✅ Job {job_id} selesai: {output_path.name}")

    except Exception as e:
        print(f"❌ Job {job_id} error: {e}")
        with _jobs_cache_lock:
            _jobs_cache[job_id] = {
                "id": job_id,
                "status": "error",
                "progress": 0,
                "error": str(e),
                "updated_at": datetime.now().isoformat(),
            }
        db.update_job(job_id, status="error", error=str(e))
        db.add_history(
            job_id,
            "transcribe",
            str(audio_path.name),
            None,
            language,
            "error",
            metadata={"error": str(e)},
        )


@app.route("/api/transcribe/status/<job_id>", methods=["GET"])
@_rate_limited_endpoint  # Fix M6: Add rate limiting to prevent polling abuse
def transcribe_status(job_id):
    """cek progress transcribe — baca dari memory, bukan DB"""
    cached = _jobs_cache.get(job_id)
    if cached:
        return jsonify(cached)
    # fallback ke DB kalau bukan active job
    job = db.get_job(job_id)
    if not job:
        return jsonify({"error": "Job tidak ditemukan"}), 404
    return jsonify(job)


@app.route("/api/transcribe/stream/<job_id>", methods=["GET"])
@require_api_key
def transcribe_stream(job_id):
    """Server-Sent Events (SSE) endpoint untuk progress realtime"""

    def generate():
        last_data = None
        while True:
            cached = _jobs_cache.get(job_id)
            data_dict = cached if cached else db.get_job(job_id)

            if not data_dict:
                yield f"data: {json.dumps({'error': 'Job tidak ditemukan'})}\n\n"
                break

            # Hanya kirim data jika berubah untuk menghemat bandwidth
            current_data = json.dumps(data_dict)
            if current_data != last_data:
                yield f"data: {current_data}\n\n"
                last_data = current_data

            status = data_dict.get("status")
            if status in ("completed", "error", "failed", "cancelled"):
                break

            time.sleep(0.5)

    return Response(stream_with_context(generate()), mimetype="text/event-stream")


@app.route("/api/transcribe/cancel/<job_id>", methods=["POST"])
@require_api_key
def cancel_transcribe(job_id):
    """batalkan transcribe yang sedang berjalan"""
    job = db.get_job(job_id)
    if not job:
        return jsonify({"error": "Job tidak ditemukan"}), 404
    if job["status"] in ("completed", "error", "cancelled"):
        return jsonify({"error": "Job sudah selesai"}), 400
    _cancel_flags[job_id] = True
    return jsonify({"status": "cancelling", "job_id": job_id})


# ============================================================
# TRANSCRIPT FILES
# ============================================================
@app.route("/api/transcript/list", methods=["GET"])
@require_api_key
def list_transcripts():
    """list semua file transcript .txt"""
    target_path = request.args.get("path", "")
    target_dir = CONVERT_DIR / "single"
    
    if target_path:
        try:
            target_dir = (CONVERT_DIR / "single" / target_path).resolve()
            if (CONVERT_DIR / "single").resolve() not in target_dir.parents and target_dir != (CONVERT_DIR / "single").resolve():
                return jsonify({"error": "Invalid path"}), 400
        except Exception:
            return jsonify({"error": "Invalid path"}), 400

    if not target_dir.exists():
        return jsonify({"files": [], "folders": [], "current_path": target_path})

    files = []
    folders = []
    
    for f in sorted(target_dir.iterdir()):
        if f.is_file() and f.suffix.lower() == ".txt":
            files.append(
                {
                    "name": f.name,
                    "path": str(f.relative_to(BASE_DIR)),
                    "size": f.stat().st_size,
                    "modified": datetime.fromtimestamp(f.stat().st_mtime).isoformat(),
                }
            )
        elif f.is_dir():
            count = sum(1 for x in f.rglob("*.txt") if x.is_file())
            folders.append(
                {
                    "name": f.name,
                    "path": str(f.relative_to(CONVERT_DIR / "single")),
                    "file_count": count,
                }
            )

    return jsonify({"files": files, "folders": folders, "current_path": target_path})


@app.route("/api/transcript/<path:filepath>", methods=["GET"])
@require_api_key
def get_transcript(filepath):
    """baca isi file transcript"""
    full_path = BASE_DIR / filepath
    if not full_path.exists() or not full_path.is_file():
        return jsonify({"error": "File tidak ditemukan"}), 404

    try:
        content = full_path.read_text(encoding="utf-8")
        return jsonify(
            {
                "name": full_path.name,
                "path": filepath,
                "content": content,
                "size": full_path.stat().st_size,
            }
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/transcript/<path:filepath>", methods=["PUT"])
@require_api_key
def update_transcript(filepath):
    """edit/update isi transcript"""
    full_path = BASE_DIR / filepath
    if not full_path.exists():
        return jsonify({"error": "File tidak ditemukan"}), 404

    data = request.get_json()
    content = data.get("content")
    if content is None:
        return jsonify({"error": "content required"}), 400

    try:
        full_path.write_text(content, encoding="utf-8")
        return jsonify(
            {"status": "ok", "path": filepath, "size": full_path.stat().st_size}
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ============================================================
# CONVERT PDF
# ============================================================
@app.route("/api/convert-pdf", methods=["POST"])
@require_api_key
def convert_to_pdf():
    """convert transcript txt ke PDF"""
    data = request.get_json()
    filepath = data.get("filepath")  # relative path

    if not filepath:
        return jsonify({"error": "filepath required"}), 400

    full_path = BASE_DIR / filepath
    if not full_path.exists():
        return jsonify({"error": "File tidak ditemukan"}), 404

    try:
        import convert_pdf

        convert_pdf.txt_to_pdf(str(full_path))

        # cek output pdf
        pdf_path = full_path.with_suffix(".pdf")
        if not pdf_path.exists():
            # mungkin di-save sebagai _new.pdf
            pdf_path = full_path.with_name(full_path.stem + "_new.pdf")

        if pdf_path.exists():
            return jsonify(
                {
                    "status": "ok",
                    "pdf_path": str(pdf_path.relative_to(BASE_DIR)),
                    "pdf_name": pdf_path.name,
                    "size": pdf_path.stat().st_size,
                }
            )
        else:
            return jsonify({"error": "PDF tidak berhasil dibuat"}), 500

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ============================================================
# DOWNLOAD FILE
# ============================================================
@app.route("/api/download/<path:filepath>", methods=["GET"])
@require_api_key
def download_file(filepath):
    """download file (TXT/PDF) ke HP"""
    full_path = BASE_DIR / filepath
    if not full_path.exists() or not full_path.is_file():
        return jsonify({"error": "File tidak ditemukan"}), 404

    return send_file(str(full_path), as_attachment=True, download_name=full_path.name)


# ============================================================
# HISTORY
# ============================================================
@app.route("/api/history", methods=["GET"])
@require_api_key
def get_history():
    """ambil riwayat proses"""
    limit = request.args.get("limit", 50, type=int)
    history = db.get_history(limit)
    return jsonify({"history": history})


# ============================================================
# PDF OPERATIONS
# ============================================================
# Note: /api/convert-pdf route sudah didefinisikan di atas (line 690)
# Section ini untuk PDF merge dan list operations


@app.route("/api/pdf/merge", methods=["POST"])
@require_api_key
def merge_pdfs():
    """gabungin semua file PDF di convert folder jadi satu"""
    # Fix H7: Use shared utility function
    result = merge_all_pdfs()

    if result["status"] == "ok":
        return jsonify(result)
    else:
        return jsonify(result), 500 if "error" in result else 404


@app.route("/api/pdf/list", methods=["GET"])
@require_api_key
def list_pdfs():
    """list semua file PDF"""
    target_path = request.args.get("path", "")
    # Fix H7: Use shared utility function
    result = get_pdf_files(target_path)
    info(f"📄 PDF list: found {len(result['files'])} PDF files")
    return jsonify({"files": result['files'], "folders": result['folders'], "current_path": target_path})


# ============================================================
# FILE BROWSER
# ============================================================
@app.route("/api/files/browse", methods=["GET"])
@require_api_key
def browse_files():
    """browse folder project"""
    folder = request.args.get("folder", "")

    # restrict ke folder yang aman
    allowed_roots = ["audio", "output", "summary"]
    if folder:
        # Check if the folder starts with one of the allowed roots
        parts = Path(folder).parts
        if not parts or parts[0] not in allowed_roots:
            return jsonify({"error": "Folder tidak diizinkan"}), 403
        target = BASE_DIR / folder
    else:
        # return overview of allowed folders
        result = []
        for root_name in allowed_roots:
            root_path = BASE_DIR / root_name
            if root_path.exists():
                count = sum(1 for _ in root_path.rglob("*") if _.is_file())
                result.append(
                    {
                        "name": root_name,
                        "path": root_name,
                        "is_dir": True,
                        "file_count": count,
                    }
                )
        return jsonify({"items": result, "current": ""})

    if not target.exists():
        return jsonify({"error": "Folder tidak ditemukan"}), 404

    items = []
    for item in sorted(target.iterdir()):
        info = {
            "name": item.name,
            "path": str(item.relative_to(BASE_DIR)),
            "is_dir": item.is_dir(),
        }
        if item.is_file():
            info["size"] = item.stat().st_size
            info["modified"] = datetime.fromtimestamp(item.stat().st_mtime).isoformat()
        else:
            info["file_count"] = sum(1 for _ in item.rglob("*") if _.is_file())
        items.append(info)

    return jsonify({"items": items, "current": folder})


# ============================================================
# RUN SERVER
# ============================================================
if __name__ == "__main__":
    print("=" * 50)
    print("🚀 Audio Convert API Server")
    print("=" * 50)

    # buat folder yang dibutuhkan
    AUDIO_FOLDER.mkdir(parents=True, exist_ok=True)
    CONVERT_DIR.mkdir(parents=True, exist_ok=True)
    (BASE_DIR / "server").mkdir(parents=True, exist_ok=True)

    # inisialisasi database
    db.get_db().close()
    print("✅ Database ready")

    # tampilkan IP address
    import socket

    hostname = socket.gethostname()
    local_ip = socket.gethostbyname(hostname)
    print(f"📡 Server: http://{local_ip}:5000")
    print("📡 Local:  http://localhost:5000")
    print("=" * 50)

    app.run(host="0.0.0.0", port=5000, debug=False)
