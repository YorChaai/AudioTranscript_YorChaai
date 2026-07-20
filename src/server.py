"""
Flask API Server
Jalankan: python server.py
Server akan listen di 0.0.0.0:5000
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

# Import shared modules
from config import BASE_DIR, UPLOADS_DIR, VIDEO_UPLOAD_FOLDER, AUDIO_EXTENSIONS, VIDEO_EXTENSIONS, AUDIO_FOLDER, CONVERT_DIR, SUMMARY_DIR
from api.middlewares import rate_limited_endpoint, require_api_key
from core.ml_engine import MLEngine
import database as db
from utils import find_ffmpeg, get_audio_info_technical, repair_audio_ffmpeg, format_time_srt
from pdf_utils import get_pdf_files, merge_all_pdfs

try:
    from pypdf import PdfWriter
except ImportError:
    PdfWriter = None

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# setup logging — pakai werkzeug logger biar rapi
log = logging.getLogger("werkzeug")
log.setLevel(logging.DEBUG)

def info(msg):
    print(f"ℹ️ {msg}")

# Progress constants
PROGRESS_MIN = 1
PROGRESS_MAX = 99
PROGRESS_LOADING = 1
PROGRESS_TRANSCRIBING_MIN = 1
PROGRESS_TRANSCRIBING_MAX = 99
PROGRESS_SAVING = 99
PROGRESS_COMPLETED = 100

app = Flask(__name__)
CORS(app)
app.config["MAX_CONTENT_LENGTH"] = 500 * 1024 * 1024

_cancel_flags = {}  # job_id -> bool
_jobs_cache = {}
_jobs_cache_lock = threading.Lock()

def _cleanup_old_jobs(max_age_hours=24):
    now = datetime.now()
    jobs_to_remove = []
    with _jobs_cache_lock:
        for job_id, job_data in _jobs_cache.items():
            if job_data.get("status") in ("completed", "error", "cancelled"):
                if "updated_at" in job_data:
                    try:
                        updated = datetime.fromisoformat(job_data["updated_at"])
                        if (now - updated).total_seconds() / 3600 > max_age_hours:
                            jobs_to_remove.append(job_id)
                    except Exception:
                        jobs_to_remove.append(job_id)
                else:
                    jobs_to_remove.append(job_id)

        for job_id in jobs_to_remove:
            _jobs_cache.pop(job_id, None)

        if jobs_to_remove:
            print(f"🧹 Cleaned up {len(jobs_to_remove)} old jobs from cache")
    return len(jobs_to_remove)

def _get_model():
    return MLEngine.get_model()


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
@rate_limited_endpoint  # Fix M6: Also rate limit health checks
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
            "model_loaded": getattr(MLEngine, "_model", None) is not None,
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
            _update_job_status(j_id, "generating_summary", progress=10)

            with open(t_path, "r", encoding="utf-8") as f:
                raw_text = f.read()

            metadata = extract_metadata(raw_text)
            cleaned_text = clean_transcript(raw_text)

            _update_job_status(j_id, "waiting_ollama", progress=30)

            summary = generate_summary(
                cleaned_text, m_name, language=metadata.get("language", "id")
            )

            _update_job_status(j_id, "saving", progress=90)

            save_summary(t_path, summary, m_name)

            _update_job_status(j_id, "completed", progress=100)

        except Exception as e:
            print(f"Error summary {j_id}: {e}")
            _update_job_status(j_id, "failed", error=str(e))

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


def _update_job_status(job_id, status, progress=None, error=None, output_file=None):
    """Update job status in both memory cache and database."""
    now = datetime.now().isoformat()
    with _jobs_cache_lock:
        if job_id not in _jobs_cache:
            _jobs_cache[job_id] = {"id": job_id, "created_at": now}

        _jobs_cache[job_id]["status"] = status
        _jobs_cache[job_id]["updated_at"] = now
        if progress is not None:
            _jobs_cache[job_id]["progress"] = progress
        if error is not None:
            _jobs_cache[job_id]["error"] = error
        if output_file is not None:
            _jobs_cache[job_id]["output_file"] = output_file

    # Sync to DB
    db.update_job(job_id, status=status, progress=progress, error=error, output_file=output_file)


def _run_transcribe(job_id, audio_path, language, do_translate, target_lang):
    """background task untuk transcribe — real-time progress via callback + in-memory cache"""
    try:
        _update_job_status(job_id, "loading_model", progress=1)
        info(f"🔄 Job {job_id}: loading model...")

        if not audio_path.exists():
            error_msg = f"Audio file not found: {audio_path}"
            info(f"❌ Job {job_id}: {error_msg}")
            _update_job_status(job_id, "error", progress=0, error=error_msg)
            db.add_history(job_id, "transcribe", audio_path.name, None, language, "error", metadata={"error": error_msg})
            return

        _cleanup_old_jobs(max_age_hours=24)
        model = _get_model()

        if _cancel_flags.get(job_id):
            _update_job_status(job_id, "cancelled", progress=0)
            _cancel_flags.pop(job_id, None)
            return

        _update_job_status(job_id, "transcribing")

        try:
            rel_path = audio_path.parent.relative_to(AUDIO_FOLDER)
            output_dir = CONVERT_DIR / "single" / rel_path
        except ValueError:
            output_dir = CONVERT_DIR / "single"

        from core.transcription import process_file
        last_update = 0

        def progress_callback(pct):
            nonlocal last_update
            if pct - last_update > 2 or pct >= 100:
                last_update = pct
                prog = PROGRESS_TRANSCRIBING_MIN + (pct / 100) * (PROGRESS_TRANSCRIBING_MAX - PROGRESS_TRANSCRIBING_MIN)
                _update_job_status(job_id, "transcribing", progress=min(prog, PROGRESS_MAX))
            
            if _cancel_flags.get(job_id):
                raise InterruptedError("Cancelled")

        try:
            result, out_path = process_file(
                model=model, audio_file=audio_path, output_folder=output_dir,
                language=language, do_translate=do_translate, target_lang=target_lang,
                progress_callback=progress_callback
            )
        except InterruptedError:
            _update_job_status(job_id, "cancelled", progress=0)
            _cancel_flags.pop(job_id, None)
            info(f"🛑 Job {job_id} dibatalkan")
            return
        
        output_rel = str(out_path.relative_to(BASE_DIR))
        _update_job_status(job_id, "completed", progress=PROGRESS_COMPLETED, output_file=output_rel)

        # Update duration in DB
        job_data = db.get_job(job_id)
        duration = (datetime.now() - datetime.fromisoformat(job_data["created_at"])).total_seconds()
        db.update_job(job_id, status="completed", duration_seconds=duration)

        db.add_history(
            job_id, "transcribe", audio_path.name, output_rel, language, "completed",
            metadata={"detected_lang": result["language"], "probability": result["language_probability"]}
        )
        info(f"✅ Job {job_id} selesai: {out_path.name}")

    except Exception as e:
        info(f"❌ Job {job_id} error: {e}")
        _update_job_status(job_id, "error", progress=0, error=str(e))
        db.add_history(job_id, "transcribe", audio_path.name, None, language, "error", metadata={"error": str(e)})


@app.route("/api/transcribe/status/<job_id>", methods=["GET"])
@rate_limited_endpoint  # Fix M6: Add rate limiting to prevent polling abuse
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
    target_dir = CONVERT_DIR
    
    if target_path:
        try:
            target_dir = (CONVERT_DIR / target_path).resolve()
            if CONVERT_DIR.resolve() not in target_dir.parents and target_dir != CONVERT_DIR.resolve():
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
                    "path": str(f.relative_to(CONVERT_DIR)),
                    "file_count": count,
                }
            )

    return jsonify({"files": files, "folders": folders, "current_path": target_path})


@app.route("/api/summary/list", methods=["GET"])
@require_api_key
def list_summaries():
    """list semua file summary .md / .txt"""
    target_path = request.args.get("path", "")
    target_dir = SUMMARY_DIR
    
    if target_path:
        try:
            target_dir = (SUMMARY_DIR / target_path).resolve()
            if SUMMARY_DIR.resolve() not in target_dir.parents and target_dir != SUMMARY_DIR.resolve():
                return jsonify({"error": "Invalid path"}), 400
        except Exception:
            return jsonify({"error": "Invalid path"}), 400

    if not target_dir.exists():
        return jsonify({"files": [], "folders": [], "current_path": target_path})

    files = []
    folders = []
    
    for f in sorted(target_dir.iterdir()):
        if f.is_file() and (f.suffix.lower() == ".md" or f.suffix.lower() == ".txt"):
            files.append(
                {
                    "name": f.name,
                    "path": str(f.relative_to(BASE_DIR)),
                    "size": f.stat().st_size,
                    "modified": datetime.fromtimestamp(f.stat().st_mtime).isoformat(),
                }
            )
        elif f.is_dir():
            count = sum(1 for x in f.rglob("*.*") if x.is_file() and (x.suffix.lower() == ".md" or x.suffix.lower() == ".txt"))
            folders.append(
                {
                    "name": f.name,
                    "path": str(f.relative_to(SUMMARY_DIR)),
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
        # Normalize newline: hapus \r supaya tidak ada CRLF double di Windows
        content = content.replace('\r\n', '\n').replace('\r', '\n')
        full_path.write_text(content, encoding="utf-8", newline='\n')
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
