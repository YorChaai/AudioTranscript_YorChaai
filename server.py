"""
Flask API Server - wrapper untuk transcribe.py dan convert_pdf.py
Jalankan: python server.py
Server akan listen di 0.0.0.0:5000

Semua proses berat (transcribe) jalan di background thread.
HP hanya kirim request, semua file disimpan di server.
"""

import os
import sys
import uuid
import logging
import threading
import time
import subprocess
from pathlib import Path
from datetime import datetime
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
from werkzeug.utils import secure_filename
from tqdm import tqdm
import shutil
import sqlite3
import json
from convert_pdf import txt_to_pdf
from pdf_utils import merge_all_pdfs, get_pdf_files  # Fix H7: Shared PDF utilities
try:
    from pypdf import PdfWriter
except ImportError:
    PdfWriter = None  # Handle gracefully if not installed

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# setup logging — pakai werkzeug logger biar rapi
log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)  # Silence request logs (GET /api/...)

# pke print biasa aja buat log kita sendiri biar gak ikut ke-silence
def info(msg):
    print(f"ℹ️ {msg}")


# project imports
import database as db
import importlib.util

# ============================================================
# setup DLL paths untuk CUDA (cublas, cudnn) — SEBELUM import faster_whisper
# ============================================================
_dll_handles = []

def _add_dll_path(path):
    path = str(path)
    if hasattr(os, 'add_dll_directory'):
        try:
            h = os.add_dll_directory(path)
            _dll_handles.append(h)
        except Exception:
            pass
    if path not in os.environ.get('PATH', ''):
        os.environ['PATH'] = path + os.pathsep + os.environ.get('PATH', '')

def _setup_cuda_dll_paths():
    dirs = []
    # nvidia packages (cublas, cudnn)
    spec = importlib.util.find_spec('nvidia')
    if spec and spec.submodule_search_locations:
        base = Path(spec.submodule_search_locations[0])
        for sub in base.iterdir():
            for d in [sub / 'bin', sub / 'lib']:
                if d.exists():
                    _add_dll_path(d)
                    dirs.append(str(d))
    # torch/lib
    spec = importlib.util.find_spec('torch')
    if spec and spec.submodule_search_locations:
        tlib = Path(spec.submodule_search_locations[0]) / 'lib'
        if tlib.exists():
            _add_dll_path(tlib)
            dirs.append(str(tlib))
    # ctranslate2
    spec = importlib.util.find_spec('ctranslate2')
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

BASE_DIR = Path(__file__).parent
AUDIO_FOLDER = BASE_DIR / "audio"
CONVERT_DIR = BASE_DIR / "convert txt"
UPLOADS_DIR = BASE_DIR / "data" / "uploads"
VIDEO_UPLOAD_FOLDER = UPLOADS_DIR / "video"

# supported audio formats
AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".flac", ".ogg", ".wma", ".aac"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".mpeg", ".mpg", ".m4v"}

app = Flask(__name__)
CORS(app)
app.config['MAX_CONTENT_LENGTH'] = 500 * 1024 * 1024  # max upload 500MB

# ============================================================
# model dan transcribe reference (lazy load)
# ============================================================
_model = None
_model_lock = threading.Lock()
_cancel_flags = {}  # job_id -> bool, untuk cancel transcribe
_jobs_cache = {}    # in-memory cache agar polling status gak buka DB terus
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
            if job_data.get('status') in ('completed', 'error', 'cancelled'):
                # Check age jika ada updated_at
                if 'updated_at' in job_data:
                    try:
                        updated = datetime.fromisoformat(job_data['updated_at'])
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
                try:
                    print("🔄 Loading Whisper model (large-v3) dengan GPU...")
                    _model = WhisperModel("large-v3", device="cuda", compute_type="float16")
                    print("✅ Model loaded (GPU)!")
                except Exception as e:
                    print(f"⚠️ GPU tidak tersedia: {e}")
                    print("🔄 Fallback ke CPU...")
                    _model = WhisperModel("large-v3", device="cpu", compute_type="int8")
                    print("✅ Model loaded (CPU)!")
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
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    counter = 1

    while True:
        alt = folder / f"{stem}_{timestamp}_{counter}{suffix}"
        if not alt.exists():
            return alt
        counter += 1


def _find_ffmpeg():
    env_path = os.environ.get("FFMPEG_PATH")
    if env_path and Path(env_path).exists():
        return env_path

    local_candidates = [
        BASE_DIR / "ffmpeg.exe",
        BASE_DIR / "bin" / "ffmpeg.exe",
        BASE_DIR / "tools" / "ffmpeg.exe",
        BASE_DIR / "tools" / "ffmpeg" / "bin" / "ffmpeg.exe",
    ]
    for candidate in local_candidates:
        if candidate.exists():
            return str(candidate)

    return "ffmpeg"


def _convert_video_to_mp3(video_path: Path) -> tuple[Path, list[str]]:
    _ensure_media_dirs()

    mp3_name = f"{video_path.stem}.mp3"
    output_path = _unique_path(AUDIO_FOLDER, mp3_name)
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
@app.route('/api/health', methods=['GET'])
def health_check():
    """cek server status"""
    return jsonify({
        "status": "ok",
        "timestamp": datetime.now().isoformat(),
        "model_loaded": _model is not None
    })


# ============================================================
# AUDIO FILES
# ============================================================
@app.route('/api/audio/list', methods=['GET'])
def list_audio():
    """list semua file audio di folder audio/"""
    if not AUDIO_FOLDER.exists():
        AUDIO_FOLDER.mkdir(parents=True, exist_ok=True)
        return jsonify({"files": [], "folders": []})

    files = []
    for f in sorted(AUDIO_FOLDER.iterdir()):
        if f.is_file() and f.suffix.lower() in AUDIO_EXTENSIONS:
            files.append({
                "name": f.name,
                "path": str(f.relative_to(BASE_DIR)),
                "size": f.stat().st_size,
                "modified": datetime.fromtimestamp(f.stat().st_mtime).isoformat()
            })

    # list subfolders too
    folders = []
    for f in sorted(AUDIO_FOLDER.iterdir()):
        if f.is_dir():
            # count audio files recursively
            count = sum(1 for x in f.rglob("*") if x.is_file() and x.suffix.lower() in AUDIO_EXTENSIONS)
            folders.append({
                "name": f.name,
                "path": str(f.relative_to(BASE_DIR)),
                "file_count": count
            })

    return jsonify({"files": files, "folders": folders})


@app.route('/api/audio/upload', methods=['POST'])
def upload_audio():
    """upload file audio dari HP ke server"""
    if 'file' not in request.files:
        return jsonify({"error": "File tidak ditemukan"}), 400

    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "Filename kosong"}), 400

    ext = Path(file.filename).suffix.lower()
    if ext not in AUDIO_EXTENSIONS:
        return jsonify({"error": f"Format audio tidak didukung: {ext}"}), 400

    filename = secure_filename(file.filename)
    _ensure_media_dirs()
    save_path = _unique_path(AUDIO_FOLDER, filename)

    file.save(str(save_path))

    return jsonify({
        "status": "ok",
        "media_type": "audio",
        "filename": save_path.name,
        "path": str(save_path.relative_to(BASE_DIR)),
        "size": save_path.stat().st_size
    })


@app.route('/api/video/upload-convert', methods=['POST'])
def upload_and_convert_video():
    """upload video, convert ke mp3, lalu hapus file video asli"""
    if 'file' not in request.files:
        return jsonify({"error": "File tidak ditemukan"}), 400

    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "Filename kosong"}), 400

    ext = Path(file.filename).suffix.lower()
    if ext not in VIDEO_EXTENSIONS:
        return jsonify({"error": f"Format video tidak didukung: {ext}"}), 400

    filename = secure_filename(file.filename)
    _ensure_media_dirs()
    temp_video_path = _unique_path(VIDEO_UPLOAD_FOLDER, filename)

    try:
        file.save(str(temp_video_path))
        info(f"🎬 Video uploaded: {temp_video_path.name}")

        mp3_path, logs = _convert_video_to_mp3(temp_video_path)
        info(f"🎵 Video converted to MP3: {mp3_path.name}")

        try:
            temp_video_path.unlink(missing_ok=True)
            info(f"🗑️ Source video deleted: {temp_video_path.name}")
        except Exception as delete_err:
            info(f"⚠️ Gagal hapus video source: {delete_err}")

        return jsonify({
            "status": "ok",
            "media_type": "video_converted",
            "source_deleted": True,
            "source_filename": filename,
            "filename": mp3_path.name,
            "path": str(mp3_path.relative_to(BASE_DIR)),
            "size": mp3_path.stat().st_size,
            "message": "Video berhasil di-convert ke MP3 dan dipindahkan ke folder audio"
        })
    except Exception as e:
        try:
            if temp_video_path.exists():
                temp_video_path.unlink()
        except Exception:
            pass

        return jsonify({
            "error": str(e),
            "media_type": "video_converted",
        }), 500


# ============================================================
# TRANSCRIBE
# ============================================================
@app.route('/api/transcribe', methods=['POST'])
def start_transcribe():
    """mulai transcribe audio — berjalan di background thread"""
    data = request.get_json()
    if not data:
        return jsonify({"error": "Body JSON required"}), 400

    audio_file = data.get("audio_file")  # relative path dari BASE_DIR
    language = data.get("language", "auto")
    do_translate = data.get("translate", False)
    target_lang = data.get("target_lang", "id")

    if not audio_file:
        return jsonify({"error": "audio_file required"}), 400

    audio_path = BASE_DIR / audio_file
    if not audio_path.exists():
        return jsonify({"error": f"File tidak ditemukan: {audio_file}"}), 404

    # buat job
    job_id = str(uuid.uuid4())[:8]
    db.create_job(job_id, "transcribe", audio_file, language, do_translate, target_lang)

    # jalankan di background
    thread = threading.Thread(
        target=_run_transcribe,
        args=(job_id, audio_path, language, do_translate, target_lang),
        daemon=True
    )
    thread.start()

    return jsonify({"job_id": job_id, "status": "started"})


def _run_transcribe(job_id, audio_path, language, do_translate, target_lang):
    """background task untuk transcribe — real-time progress via tqdm + in-memory cache"""
    try:
        now = datetime.now().isoformat()
        with _jobs_cache_lock:
            _jobs_cache[job_id] = {"id": job_id, "status": "loading_model", "progress": 1, "created_at": now, "updated_at": now}
        print(f"🔄 Job {job_id}: loading model...")

        # Fix C5: Cleanup old jobs periodic (setiap ada job baru)
        _cleanup_old_jobs(max_age_hours=24)

        model = _get_model()

        # cek cancel sebelum mulai transcribe
        if _cancel_flags.get(job_id):
            with _jobs_cache_lock:
                _jobs_cache[job_id] = {"id": job_id, "status": "cancelled", "progress": 0, "updated_at": datetime.now().isoformat()}
            db.update_job(job_id, status="cancelled", progress=0)
            _cancel_flags.pop(job_id, None)
            return

        with _jobs_cache_lock:
            _jobs_cache[job_id]["status"] = "transcribing"

        # transcribe — dapatkan generator (JANGAN di-list()!)
        lang_param = None if language == "auto" else language

        def _start_transcribe(mdl):
            """mulai transcribe, return (generator, info) — BUKAN list!"""
            segs_gen, inf = mdl.transcribe(
                str(audio_path),
                language=lang_param,
                beam_size=5,
                word_timestamps=True,
                vad_filter=True,
            )
            return segs_gen, inf

        try:
            segs_gen, info = _start_transcribe(model)
        except Exception as cuda_err:
            if "cublas" in str(cuda_err).lower() or "cuda" in str(cuda_err).lower():
                print(f"⚠️ GPU gagal saat transcribe: {cuda_err}")
                print("🔄 Reload model ke CPU dan coba ulang...")
                _jobs_cache[job_id] = {"id": job_id, "status": "loading_model", "progress": 1,
                                       "error": "GPU gagal, switching ke CPU..."}
                global _model
                _model = WhisperModel("large-v3", device="cpu", compute_type="int8")
                model = _model
                print("✅ Model loaded (CPU)!")
                _jobs_cache[job_id]["status"] = "transcribing"
                segs_gen, info = _start_transcribe(model)
            else:
                raise

        total_duration = info.duration
        detected = info.language
        prob = info.language_probability

        print(f"🎤 Job {job_id}: transcribing {audio_path.name} ({total_duration:.0f}s, lang={detected})")

        full_text = ""
        all_segments = []
        last_end = 0

        # tqdm progress bar di terminal
        pbar = tqdm(
            total=total_duration,
            unit="s",
            unit_scale=True,
            desc=f"Job {job_id}",
            bar_format="{l_bar}{bar}| {n:.0f}/{total:.0f}s [{elapsed}<{remaining}]"
        )

        for segment in segs_gen:
            # cek cancel di tengah transcribe
            if _cancel_flags.get(job_id):
                pbar.close()
                with _jobs_cache_lock:
                    _jobs_cache[job_id] = {"id": job_id, "status": "cancelled", "progress": 0, "updated_at": datetime.now().isoformat()}
                db.update_job(job_id, status="cancelled", progress=0)
                _cancel_flags.pop(job_id, None)
                print(f"🛑 Job {job_id} dibatalkan")
                return

            text = segment.text.strip()
            full_text += text + "\n"
            all_segments.append({
                "start": segment.start,
                "end": segment.end,
                "text": text
            })

            # update tqdm di terminal
            increment = segment.end - last_end
            if increment > 0:
                pbar.update(increment)

            # update progress di memory (TANPA DB — polling baca dari sini)
            if total_duration > 0:
                progress = 1 + (segment.end / total_duration) * 98
                with _jobs_cache_lock:
                    _jobs_cache[job_id] = {
                        "id": job_id,
                        "status": "transcribing",
                        "progress": min(progress, 99),
                        "updated_at": datetime.now().isoformat()
                    }
            last_end = segment.end

        # pastikan tqdm 100%
        remaining = total_duration - last_end
        if remaining > 0:
            pbar.update(remaining)
        pbar.close()

        with _jobs_cache_lock:
            _jobs_cache[job_id] = {"id": job_id, "status": "saving", "progress": 99, "updated_at": datetime.now().isoformat()}
        print(f"💾 Job {job_id}: menyimpan hasil...")

        # translate jika diminta
        translated_text = None
        final_target_lang = target_lang
        import transcribe as tr
        should_translate, final_target_lang = tr.resolve_translation_target(detected, do_translate, target_lang)
        if should_translate:
            with _jobs_cache_lock:
                _jobs_cache[job_id] = {"id": job_id, "status": "translating", "progress": 99, "updated_at": datetime.now().isoformat()}
            print(f"🌐 Job {job_id}: translating ke {target_lang}...")
            try:
                tr.load_glossary()
                translated_text = tr.translate_text(full_text.strip(), final_target_lang)
            except Exception as te:
                print(f"Translation error: {te}")

        db.update_job(job_id, progress=99)

        # simpan file output
        output_dir = CONVERT_DIR / "single"
        output_dir.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_name = f"{audio_path.stem}_transcript_{timestamp}.txt"
        output_path = output_dir / output_name

        # tulis file transcript
        SUPPORTED_LANGS = {
            "id": "Indonesian",
            "en": "English",
            "ja": "Japanese",
            "auto": "Auto-detect (Mixed)",
        }
        lang_mode = SUPPORTED_LANGS.get(language, 'Auto')

        def format_time(seconds):
            minutes = int(seconds // 60)
            secs = int(seconds % 60)
            return f"{minutes:02d}:{secs:02d}"

        with open(output_path, "w", encoding="utf-8") as f:
            f.write(f"Source: {audio_path.name}\n")
            f.write(f"Language Mode: {lang_mode}\n")
            f.write(f"Detected: {detected} ({prob:.1%})\n")
            f.write(f"Transcribed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write("=" * 50 + "\n\n")

            semicolon_text = " ; ".join([s['text'].strip() for s in all_segments])
            f.write(semicolon_text)

            f.write("\n\n" + "=" * 50 + "\n")
            f.write("TIMESTAMPS:\n\n")
            for seg in all_segments:
                f.write(f"[{format_time(seg['start'])} - {format_time(seg['end'])}]\n{seg['text']}\n\n")

            if translated_text:
                f.write("=" * 50 + "\n\n")
                f.write(f"TRANSLATION ({final_target_lang.upper()}):\n\n")
                f.write(translated_text)
                f.write("\n\n")

        # update job selesai — tulis ke DB + cache
        db.update_job(
            job_id,
            status="completed",
            progress=100,
            output_file=str(output_path.relative_to(BASE_DIR)),
            duration_seconds=(datetime.now() - datetime.fromisoformat(db.get_job(job_id)['created_at'])).total_seconds()
        )
        with _jobs_cache_lock:
            _jobs_cache[job_id] = {
                "id": job_id,
                "status": "completed",
                "progress": 100,
                "output_file": str(output_path.relative_to(BASE_DIR)),
                "updated_at": datetime.now().isoformat()
            }

        # simpan history
        db.add_history(
            job_id, "transcribe", audio_path.name,
            str(output_path.relative_to(BASE_DIR)),
            language, "completed",
            metadata={"detected_lang": detected, "probability": prob, "duration": total_duration}
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
                "updated_at": datetime.now().isoformat()
            }
        db.update_job(job_id, status="error", error=str(e))
        db.add_history(job_id, "transcribe", str(audio_path.name), None, language, "error",
                       metadata={"error": str(e)})


@app.route('/api/transcribe/status/<job_id>', methods=['GET'])
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


@app.route('/api/transcribe/cancel/<job_id>', methods=['POST'])
def cancel_transcribe(job_id):
    """batalkan transcribe yang sedang berjalan"""
    job = db.get_job(job_id)
    if not job:
        return jsonify({"error": "Job tidak ditemukan"}), 404
    if job['status'] in ('completed', 'error', 'cancelled'):
        return jsonify({"error": "Job sudah selesai"}), 400
    _cancel_flags[job_id] = True
    return jsonify({"status": "cancelling", "job_id": job_id})


# ============================================================
# TRANSCRIPT FILES
# ============================================================
@app.route('/api/transcript/list', methods=['GET'])
def list_transcripts():
    """list semua file transcript"""
    if not CONVERT_DIR.exists():
        return jsonify({"files": []})

    files = []
    for path in sorted(CONVERT_DIR.rglob("*.txt"), key=lambda x: x.stat().st_mtime, reverse=True):
        try:
            rel = path.relative_to(BASE_DIR)
            label = path.relative_to(CONVERT_DIR).parts[0] if len(path.relative_to(CONVERT_DIR).parts) > 1 else "root"
            files.append({
                "name": path.name,
                "path": str(rel),
                "label": label,
                "size": path.stat().st_size,
                "modified": datetime.fromtimestamp(path.stat().st_mtime).isoformat()
            })
        except Exception:
            continue

    return jsonify({"files": files})


@app.route('/api/transcript/<path:filepath>', methods=['GET'])
def get_transcript(filepath):
    """baca isi file transcript"""
    full_path = BASE_DIR / filepath
    if not full_path.exists() or not full_path.is_file():
        return jsonify({"error": "File tidak ditemukan"}), 404

    try:
        content = full_path.read_text(encoding='utf-8')
        return jsonify({
            "name": full_path.name,
            "path": filepath,
            "content": content,
            "size": full_path.stat().st_size
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/api/transcript/<path:filepath>', methods=['PUT'])
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
        full_path.write_text(content, encoding='utf-8')
        return jsonify({
            "status": "ok",
            "path": filepath,
            "size": full_path.stat().st_size
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ============================================================
# CONVERT PDF
# ============================================================
@app.route('/api/convert-pdf', methods=['POST'])
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
            return jsonify({
                "status": "ok",
                "pdf_path": str(pdf_path.relative_to(BASE_DIR)),
                "pdf_name": pdf_path.name,
                "size": pdf_path.stat().st_size
            })
        else:
            return jsonify({"error": "PDF tidak berhasil dibuat"}), 500

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ============================================================
# DOWNLOAD FILE
# ============================================================
@app.route('/api/download/<path:filepath>', methods=['GET'])
def download_file(filepath):
    """download file (TXT/PDF) ke HP"""
    full_path = BASE_DIR / filepath
    if not full_path.exists() or not full_path.is_file():
        return jsonify({"error": "File tidak ditemukan"}), 404

    return send_file(
        str(full_path),
        as_attachment=True,
        download_name=full_path.name
    )


# ============================================================
# HISTORY
# ============================================================
@app.route('/api/history', methods=['GET'])
def get_history():
    """ambil riwayat proses"""
    limit = request.args.get('limit', 50, type=int)
    history = db.get_history(limit)
    return jsonify({"history": history})



# ============================================================
# PDF OPERATIONS
# ============================================================
# Note: /api/convert-pdf route sudah didefinisikan di atas (line 690)
# Section ini untuk PDF merge dan list operations


@app.route('/api/pdf/merge', methods=['POST'])
def merge_pdfs():
    """gabungin semua file PDF di convert folder jadi satu"""
    # Fix H7: Use shared utility function
    result = merge_all_pdfs()

    if result['status'] == 'ok':
        return jsonify(result)
    else:
        return jsonify(result), 500 if 'error' in result else 404


@app.route('/api/pdf/list', methods=['GET'])
def list_pdfs():
    """list semua file PDF"""
    # Fix H7: Use shared utility function
    files = get_pdf_files()
    info(f"📄 PDF list: found {len(files)} PDF files")
    return jsonify({"files": files})


# ============================================================
# FILE BROWSER
# ============================================================
@app.route('/api/files/browse', methods=['GET'])
def browse_files():
    """browse folder project"""
    folder = request.args.get('folder', '')

    # restrict ke folder yang aman
    allowed_roots = ['audio', 'convert txt', 'summary']
    if folder:
        root = folder.split('/')[0].split('\\')[0]
        if root not in allowed_roots:
            return jsonify({"error": "Folder tidak diizinkan"}), 403
        target = BASE_DIR / folder
    else:
        # return overview of allowed folders
        result = []
        for root_name in allowed_roots:
            root_path = BASE_DIR / root_name
            if root_path.exists():
                count = sum(1 for _ in root_path.rglob("*") if _.is_file())
                result.append({
                    "name": root_name,
                    "path": root_name,
                    "is_dir": True,
                    "file_count": count
                })
        return jsonify({"items": result, "current": ""})

    if not target.exists():
        return jsonify({"error": "Folder tidak ditemukan"}), 404

    items = []
    for item in sorted(target.iterdir()):
        info = {
            "name": item.name,
            "path": str(item.relative_to(BASE_DIR)),
            "is_dir": item.is_dir()
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
if __name__ == '__main__':
    print("=" * 50)
    print("🚀 Audio Convert API Server")
    print("=" * 50)

    # buat folder yang dibutuhkan
    AUDIO_FOLDER.mkdir(parents=True, exist_ok=True)
    CONVERT_DIR.mkdir(parents=True, exist_ok=True)
    (BASE_DIR / "data").mkdir(parents=True, exist_ok=True)

    # inisialisasi database
    db.get_db().close()
    print("✅ Database ready")

    # tampilkan IP address
    import socket
    hostname = socket.gethostname()
    local_ip = socket.gethostbyname(hostname)
    print(f"📡 Server: http://{local_ip}:5000")
    print(f"📡 Local:  http://localhost:5000")
    print("=" * 50)

    app.run(host='0.0.0.0', port=5000, debug=False)
