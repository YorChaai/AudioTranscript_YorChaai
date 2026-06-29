"""
Audio to Text Transcription using Faster-Whisper
Supports: Indonesian, English, Japanese, and Mixed (Code-Switching)
Model: large-v3 (GPU accelerated)

Modes:
  - single: Process 1 file (pilih dari list, ambil terakhir)
  - multiple: Process multiple files (pilih dari list)

Languages:
  - id: Indonesian only (faster, more accurate for pure Indo)
  - en: English only (faster, more accurate for pure English)
  - ja: Japanese only
  - auto: Auto-detect / mixed languages (for campur)
"""

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

from deep_translator import GoogleTranslator
from tqdm import tqdm

import convert_pdf

from core.ml_engine import MLEngine
from core.transcription import process_file, get_relative_path_from_audio
from core.translator import load_glossary


# Fix H7: Import shared utilities instead of duplicating code
from utils import (
    convert_video_to_mp3,
    convert_video_to_mp3_parallel,
    format_time_srt,
    get_audio_info_technical,  # NEW: Technical info
    repair_audio_ffmpeg,  # NEW: Audio repair
)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# HuggingFace Token for faster downloads (no rate limit)
# It's better to set this in .env or system environment variable
if not os.environ.get("HF_TOKEN"):
    # Fallback to a placeholder or common public model access if needed
    pass

# konfigurasi
# Model size options: tiny, small, medium, large-v3, large-v3-distil
# Default: large-v3 (best accuracy, slowest)
# For faster transcription, set env var: set WHISPER_MODEL_SIZE=medium
MODEL_SIZE = os.environ.get("WHISPER_MODEL_SIZE", "large-v3")

# Local model path - use pre-downloaded model from D:\model to save C: drive space
# If model not found locally, will auto-download to cache
LOCAL_MODEL_PATH = os.environ.get("WHISPER_MODEL_PATH", "D:\\model\\large-v3")

DEVICE = "cuda"
COMPUTE_TYPE = "float16"
AUTO_TRANSLATE_TARGET = "id"

# folder paths
BASE_DIR = Path(__file__).parent.parent  # Project root (src/ is subdir)
AUDIO_FOLDER = BASE_DIR / "audio"
OUTPUT_SINGLE = BASE_DIR / "output" / "single"
OUTPUT_MULTIPLE = BASE_DIR / "output" / "multiple"

# Load .env file for environment variables (WHISPER_MODEL_PATH, etc)
from dotenv import load_dotenv

env_path = BASE_DIR / ".env"
if env_path.exists():
    load_dotenv(env_path)
    print(f"✅ Loaded .env file from: {env_path}")

# supported audio formats
AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".flac", ".ogg", ".wma", ".aac", ".mp4"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".mpeg", ".mpg", ".m4v"}

# supported languages
SUPPORTED_LANGS = {
    "id": "Indonesian",
    "en": "English",
    "ja": "Japanese",
    "auto": "Auto-detect (Mixed)",
}

# Glossary: English -> Indonesian
# Istilah in akan diproses menjadi: "Terjemahan (Istilah Asli)"
# Contoh: "data scientist" -> "ilmuwan data (data scientist)"


# Glossary loaded from assets/glossary.json
GLOSSARY = {
    "data scientist": "ilmuwan data",
    # default fallback if file not found
}

# Pre-compiled glossary patterns for performance
_GLOSSARY_PATTERNS = {}
_GLOSSARY_MAPPING = {}










def get_audio_files(folder: Path, recursive: bool = False) -> list:
    """
    Get all audio/video files from folder (supports both audio and video)
    Args:
        folder: folder path
        recursive: jika True, scan semua subfolder (default: False)
    Returns:
        list of Path objects, sorted
    """
    if not folder.exists():
        return []

    # Use MEDIA_EXTENSIONS to include both audio and video files
    MEDIA_EXTENSIONS = {
        ".mp3",
        ".wav",
        ".m4a",
        ".flac",
        ".ogg",
        ".wma",
        ".aac",
        ".mp4",
        ".mov",
        ".mkv",
        ".avi",
        ".webm",
        ".mpeg",
        ".mpg",
        ".m4v",
    }

    files = []
    if recursive:
        # Use suffix-based filtering for accuracy
        for f in folder.rglob("*"):
            if f.is_file() and f.suffix.lower() in MEDIA_EXTENSIONS:
                files.append(f)
    else:
        # Level 1 saja
        for f in folder.iterdir():
            if f.is_file() and f.suffix.lower() in MEDIA_EXTENSIONS:
                files.append(f)

    return sorted(files)


def get_subfolders(folder: Path) -> list:
    """ambil semua subfolder dari folder audio (level 1 saja)"""
    if not folder.exists():
        return []
    folders = []
    for f in folder.iterdir():
        if f.is_dir():
            folders.append(f)
    return sorted(folders)


def get_all_subfolders_recursive(folder: Path) -> list:
    """
    ambil SEMUA folder di dalam folder secara rekursif (semua level)
    Return: list of Path objects
    """
    if not folder.exists():
        return []
    folders = []
    for f in folder.rglob("*"):
        if f.is_dir():
            folders.append(f)
    return sorted(folders)


def get_relative_path_from_audio(file_or_folder: Path) -> str:
    """
    dapatkan path relatif dari AUDIO_FOLDER
    Contoh: audio/asonis/folder1 -> "asonis/folder1"
    """
    try:
        return str(file_or_folder.relative_to(AUDIO_FOLDER))
    except ValueError:
        return file_or_folder.name


def display_folders(folders: list) -> None:
    """tampilkan daftar folder dengan nomor (hitung file rekursif)"""
    print(f"\n📂 Folders in audio/ ({len(folders)} folders):")
    print("-" * 50)
    for i, f in enumerate(folders, 1):
        # hitung jumlah file audio di folder secara rekursif
        audio_count = len(get_audio_files(f, recursive=True))
        print(f"  [{i}] {f.name} ({audio_count} audio files)")
    print("-" * 50)


def display_all_folders_with_selection(folders: list, selected_indices: set) -> None:
    """
    tampilkan SEMUA folder di semua level dengan status seleksi
    selected_indices: set berisi index folder yang sudah dipilih (0-based)
    """
    print(f"\n📂 Semua Folder dalam audio/ ({len(folders)} folders):")
    print("-" * 70)

    if not folders:
        print("  (Tidak ada folder)")
    else:
        for i, f in enumerate(folders):
            rel_path = get_relative_path_from_audio(f)
            audio_count = len(get_audio_files(f, recursive=True))
            status = "✓ Sudah dipilih" if i in selected_indices else ""

            # Tampilkan path relatif dengan indentasi berdasarkan depth
            depth = rel_path.count("/") + 1
            prefix = "  " * depth

            print(f"{prefix}[{i + 1}] {rel_path} ({audio_count} audio files) {status}")

    print("-" * 70)
    print("  [0] ✅ Selesai memilih dan mulai proses")
    print("-" * 70)


def display_files(files: list) -> None:
    """tampilkan daftar file dengan nomor"""
    print(f"\n📂 Files in audio/ ({len(files)} files):")
    print("-" * 50)
    for i, f in enumerate(files, 1):
        # tampilkan ukuran file
        size_mb = f.stat().st_size / (1024 * 1024)
        print(f"  [{i}] {f.name} ({size_mb:.1f} MB)")
    print("-" * 50)


def _get_audio_info_technical_unused(audio_path: Path) -> dict:
    """
    Gunakan ffprobe untuk mendapatkan durasi asli dan info teknis file.
    Membantu mendeteksi jika file corrupt atau terpotong.
    """
    import json
    import subprocess

    try:
        cmd = [
            "ffprobe",
            "-v",
            "quiet",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
            str(audio_path),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        data = json.loads(result.stdout)

        # Ambil durasi dari format atau stream
        duration = float(data.get("format", {}).get("duration", 0))
        bitrate = int(data.get("format", {}).get("bit_rate", 0))

        # Ambil sample rate dari stream audio pertama
        sample_rate = 0
        for stream in data.get("streams", []):
            if stream.get("codec_type") == "audio":
                sample_rate = int(stream.get("sample_rate", 0))
                break

        return {
            "success": True,
            "duration": duration,
            "bitrate": bitrate,
            "sample_rate": sample_rate,
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


def parse_selection(input_str: str, max_num: int) -> list:
    """parse input user seperti '1,3,4,5' jadi list of integers"""
    numbers = []
    parts = input_str.replace(" ", "").split(",")

    for part in parts:
        try:
            num = int(part)
            if 1 <= num <= max_num:
                numbers.append(num)
        except ValueError:
            pass

    return numbers





def get_next_batch_number() -> int:
    """cari nomor batch berikutnya"""
    if not OUTPUT_MULTIPLE.exists():
        return 1
    existing = [
        d
        for d in OUTPUT_MULTIPLE.iterdir()
        if d.is_dir() and d.name.startswith("batch_")
    ]
    if not existing:
        return 1

    numbers = []
    for d in existing:
        try:
            num = int(d.name.split("_")[1])
            numbers.append(num)
        except (IndexError, ValueError):
            pass

    return max(numbers, default=0) + 1




def mode_single(
    model, language: str, do_translate: bool = False, target_lang: str = "id"
):
    """process mode single - pilih 1 file dari daftar"""
    files = get_audio_files(AUDIO_FOLDER)

    if not files:
        print(f"❌ Tidak ada file audio di: {AUDIO_FOLDER}")
        print("   Taruh file MP3/WAV di folder tersebut, lalu run lagi.")
        return

    # tampilkan daftar file
    display_files(files)

    # minta input user
    print("\n📝 Mode: SINGLE (hanya file terakhir yang diproses)")
    user_input = input(
        "Pilih nomor (contoh: 1 atau 1,2,3 - terakhir diambil): "
    ).strip()

    if not user_input:
        print("❌ Tidak ada input")
        return

    # parse dan ambil nomor terakhir
    numbers = parse_selection(user_input, len(files))

    if not numbers:
        print("❌ Tidak ada nomor valid")
        return

    # ambil nomor terakhir
    selected_num = numbers[-1]
    audio_file = files[selected_num - 1]

    lang_display = SUPPORTED_LANGS.get(language, "Auto")
    print("\n📁 Mode: SINGLE")
    print(f"🌐 Language: {lang_display}")
    if do_translate:
        print(f"🔤 Translate to: {target_lang}")
    print(f"📂 Selected: [{selected_num}] {audio_file.name}")
    print("=" * 50 + "\n")

    result, output_path = process_file(
        model, audio_file, OUTPUT_SINGLE, language, do_translate, target_lang
    )

    print("=" * 50)
    # print("📝 FULL TRANSCRIPT:")
    # print("=" * 50)
    # print(result["text"])
    # print("=" * 50)
    print(f"\n✅ Done! Output: {output_path}")
    return [output_path]


def mode_multiple(
    model, language: str, do_translate: bool = False, target_lang: str = "id"
):
    """process mode multiple - pilih beberapa file dari daftar"""
    files = get_audio_files(AUDIO_FOLDER)

    if not files:
        print(f"❌ Tidak ada file audio di: {AUDIO_FOLDER}")
        print("   Taruh file MP3/WAV di folder tersebut, lalu run lagi.")
        return

    # tampilkan daftar file
    display_files(files)

    # minta input user
    print("\n📝 Mode: MULTIPLE (semua yang dipilih diproses)")
    user_input = input("Pilih nomor (pisah koma, contoh: 1,3,4,5): ").strip()

    if not user_input:
        print("❌ Tidak ada input")
        return

    # parse semua nomor
    numbers = parse_selection(user_input, len(files))

    if not numbers:
        print("❌ Tidak ada nomor valid")
        return

    # hapus duplikat dan sort
    numbers = sorted(set(numbers))
    selected_files = [files[n - 1] for n in numbers]

    # buat batch folder
    batch_num = get_next_batch_number()
    batch_folder = OUTPUT_MULTIPLE / f"batch_{batch_num:03d}"
    batch_folder.mkdir(parents=True, exist_ok=True)

    lang_display = SUPPORTED_LANGS.get(language, "Auto")
    print("\n📁 Mode: MULTIPLE (Batch)")
    print(f"🌐 Language: {lang_display}")
    if do_translate:
        print(f"🔤 Translate to: {target_lang}")
    print(f"📂 Output folder: {batch_folder.resolve()}")
    print(f"📋 Selected files: {len(selected_files)}")
    for n, f in zip(numbers, selected_files):
        print(f"   [{n}] {f.name}")
    print("=" * 50 + "\n")

    generated_files = []

    for i, audio_file in enumerate(selected_files, 1):
        print(f"\n[{i}/{len(selected_files)}] Processing...")
        print("-" * 40)

        _, out_path = process_file(
            model, audio_file, batch_folder, language, do_translate, target_lang
        )
        generated_files.append(out_path)

    print("\n" + "=" * 50)
    print("✅ Batch complete!")
    print(f"   Processed: {len(selected_files)} files")
    print(f"   Language: {lang_display}")
    print(f"   Output: {batch_folder}")
    print("=" * 50)
    return generated_files


def mode_folder_single(
    model, language: str, do_translate: bool = False, target_lang: str = "id"
):
    """process mode single folder - pilih 1 folder dan extract semua file di dalamnya"""
    folders = get_subfolders(AUDIO_FOLDER)

    if not folders:
        print(f"❌ Tidak ada folder di: {AUDIO_FOLDER}")
        print("   Buat subfolder di dalam 'audio/', taruh file audio, lalu run lagi.")
        return

    # tampilkan daftar folder
    display_folders(folders)

    # minta input user
    print("\n📝 Mode: SINGLE FOLDER (semua file dalam folder akan diproses)")
    user_input = input("Pilih nomor folder: ").strip()

    if not user_input:
        print("❌ Tidak ada input")
        return

    # parse nomor folder
    try:
        folder_num = int(user_input)
        if folder_num < 1 or folder_num > len(folders):
            print(f"❌ Nomor tidak valid: {folder_num}")
            return
    except ValueError:
        print("❌ Input harus berupa nomor")
        return

    selected_folder = folders[folder_num - 1]
    # gunakan recursive untuk cari file di semua subfolder
    audio_files = get_audio_files(selected_folder, recursive=True)

    if not audio_files:
        print(f"❌ Tidak ada file audio di folder: {selected_folder.name}")
        return

    # buat batch folder
    batch_num = get_next_batch_number()
    batch_folder = OUTPUT_MULTIPLE / f"batch_{batch_num:03d}"
    batch_folder.mkdir(parents=True, exist_ok=True)

    lang_display = SUPPORTED_LANGS.get(language, "Auto")
    print("\n📁 Mode: SINGLE FOLDER")
    print(f"📂 Source folder: {selected_folder.name}")
    print(f"🌐 Language: {lang_display}")
    if do_translate:
        print(f"🔤 Translate to: {target_lang}")
    print(f"📂 Output folder: {batch_folder.resolve()}")
    print(f"📋 Files to process: {len(audio_files)}")
    for i, f in enumerate(audio_files, 1):
        size_mb = f.stat().st_size / (1024 * 1024)
        print(f"   [{i}] {f.name} ({size_mb:.1f} MB)")
    print("=" * 50 + "\n")

    generated_files = []

    for i, audio_file in enumerate(audio_files, 1):
        print(f"\n[{i}/{len(audio_files)}] Processing...")
        print("-" * 40)

        _, out_path = process_file(
            model, audio_file, batch_folder, language, do_translate, target_lang
        )
        generated_files.append(out_path)

    print("\n" + "=" * 50)
    print("✅ Folder processing complete!")
    print(f"   Folder: {selected_folder.name}")
    print(f"   Processed: {len(audio_files)} files")
    print(f"   Output: {batch_folder}")
    print("=" * 50)
    return generated_files


def mode_folder_multiple(
    model, language: str, do_translate: bool = False, target_lang: str = "id"
):
    """
    process mode multiple folders - pilih beberapa folder dengan tekan 0 untuk selesai
    output mengikuti struktur folder sumber (preserve structure)
    """
    # ambil SEMUA folder di semua level
    all_folders = get_all_subfolders_recursive(AUDIO_FOLDER)

    if not all_folders:
        print(f"❌ Tidak ada folder di: {AUDIO_FOLDER}")
        print("   Buat subfolder di dalam 'audio/', taruh file audio, lalu run lagi.")
        return

    selected_indices = set()  # set untuk menyimpan index folder yang dipilih (0-based)

    lang_display = SUPPORTED_LANGS.get(language, "Auto")

    print("\n📁 Mode: MULTIPLE FOLDERS (Preserve Structure)")
    print(f"🌐 Language: {lang_display}")
    if do_translate:
        print(f"🔤 Translate to: {target_lang}")
    print("\n📌 Cara memilih:")
    print("   - Masukkan nomor folder untuk memilih/membatalkan")
    print("   - Tekan 0 untuk selesai dan mulai proses")
    print("=" * 70)

    # loop untuk multi-select
    while True:
        # tampilkan semua folder dengan status seleksi
        display_all_folders_with_selection(all_folders, selected_indices)

        user_input = input("Pilih nomor folder (atau 0 untuk selesai): ").strip()

        if not user_input:
            print("⚠️ Input kosong, silakan masukkan nomor atau 0 untuk selesai")
            continue

        try:
            choice = int(user_input)

            # jika 0, selesai memilih
            if choice == 0:
                if not selected_indices:
                    print("⚠️ Belum ada folder yang dipilih!")
                    continue
                break

            # validasi nomor folder
            if choice < 1 or choice > len(all_folders):
                print(f"❌ Nomor tidak valid: {choice} (max: {len(all_folders)})")
                continue

            # toggle seleksi (0-based index)
            folder_index = choice - 1
            if folder_index in selected_indices:
                # batal pilih
                selected_indices.discard(folder_index)
                print(f"✓ Folder '{all_folders[folder_index].name}' dibatalkan")
            else:
                # pilih folder
                selected_indices.add(folder_index)
                print(f"✓ Folder '{all_folders[folder_index].name}' dipilih")

        except ValueError:
            print("❌ Input harus berupa nomor")

    # kumpulkan semua file audio dari folder yang dipilih
    selected_folders = [all_folders[i] for i in sorted(selected_indices)]
    all_audio_files = []
    folder_file_map = {}  # map folder ke list file untuk reporting

    for folder in selected_folders:
        audio_files = get_audio_files(folder, recursive=True)
        folder_file_map[folder] = audio_files
        all_audio_files.extend(audio_files)

    # hapus duplikat (jika ada file yang masuk multiple folder)
    all_audio_files = sorted(set(all_audio_files))

    if not all_audio_files:
        print("\n❌ Tidak ada file audio di folder yang dipilih")
        return

    # tampilkan ringkasan
    print("\n" + "=" * 70)
    print("📋 RINGKASAN SEBELUM PROSES")
    print("=" * 70)
    print(f"📂 Folder terpilih: {len(selected_folders)}")
    for folder in selected_folders:
        rel_path = get_relative_path_from_audio(folder)
        file_count = len(folder_file_map.get(folder, []))
        print(f"   - {rel_path} ({file_count} file)")
    print(f"\n🎵 Total file audio: {len(all_audio_files)}")

    # Fix C3: Defensive programming untuk selected_folders[0]
    if selected_folders:
        root_folder = get_relative_path_from_audio(selected_folders[0]).split("/")[0]
        print(f"📁 Output: {(OUTPUT_MULTIPLE / root_folder).resolve()}")
    else:
        print(f"📁 Output: {OUTPUT_MULTIPLE.resolve()}")

    print("=" * 70)

    # konfirmasi
    confirm = input("\nLanjutkan proses? (Enter = Ya, 'n' = Batal): ").strip().lower()
    if confirm == "n":
        print("❌ Proses dibatalkan")
        return

    # proses semua file
    generated_files = []
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    for i, audio_file in enumerate(all_audio_files, 1):
        print(f"\n[{i}/{len(all_audio_files)}] Processing: {audio_file.name}")
        print("-" * 40)

        # cari folder induk yang dipilih untuk file ini
        parent_folder = None
        for folder in selected_folders:
            try:
                audio_file.relative_to(folder)
                parent_folder = folder
                break
            except ValueError:
                continue

        # process dengan preserve_structure=True
        _, out_path = process_file(
            model,
            audio_file,
            OUTPUT_MULTIPLE,  # tidak digunakan karena preserve_structure=True
            language,
            do_translate,
            target_lang,
            preserve_structure=True,
            selected_folder=parent_folder,
            timestamp=timestamp,
        )
        generated_files.append(out_path)

    # buat folder kosong untuk folder yang tidak punya file audio
    empty_folders_created = 0
    for folder in selected_folders:
        if not folder_file_map.get(folder, []):
            # buat folder kosong dengan marker
            output_base = OUTPUT_MULTIPLE / get_relative_path_from_audio(folder)
            output_base.mkdir(parents=True, exist_ok=True)
            marker_file = output_base / ".empty_folder_marker.txt"
            with open(marker_file, "w", encoding="utf-8") as f:
                f.write(
                    f"Folder kosong - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
                )
                f.write(f"Source: {get_relative_path_from_audio(folder)}\n")
            empty_folders_created += 1

    print("\n" + "=" * 70)
    print("✅ Folder processing complete!")
    print(f"   Folder diproses: {len(selected_folders)}")
    print(f"   File diproses: {len(all_audio_files)}")
    print(f"   Folder kosong dibuat: {empty_folders_created}")
    print(f"   Output: {OUTPUT_MULTIPLE.resolve()}")
    print("=" * 70)

    return generated_files


def mode_folder(
    model, language: str, do_translate: bool = False, target_lang: str = "id"
):
    """
    wrapper untuk mode folder - tampilkan pilihan single vs multiple
    """
    print("\n" + "=" * 50)
    print("📁 PILIH MODE FOLDER")
    print("=" * 50)
    print("  [1] Single Folder (1 folder saja, output flat)")
    print("  [2] Multiple Folders (pilih beberapa folder, struktur terjaga)")
    print("\n  [0] Kembali")
    print("=" * 50)

    choice = input("Pilihan Anda: ").strip()

    if choice == "1":
        return mode_folder_single(model, language, do_translate, target_lang)
    elif choice == "2":
        return mode_folder_multiple(model, language, do_translate, target_lang)
    else:
        print("❌ Pilihan tidak valid. Kembali ke menu utama.")
        return []


def show_help():
    """tampilkan help"""
    print("""
╔══════════════════════════════════════════════════════════════╗
║         AUDIO TO TEXT TRANSCRIPTION (Faster-Whisper)         ║
╠══════════════════════════════════════════════════════════════╣
║  Usage:                                                      ║
║    python transcribe.py <mode> <language> [tr <target>]      ║
╠══════════════════════════════════════════════════════════════╣
║  Modes:                                                      ║
║    single   - Process 1 file (pilih dari list)               ║
║    multiple - Process multiple files (pilih dari list)       ║
║                                                              ║
║  Note: Di awal akan ditanya pilih folder atau file           ║
║    - 1 = Pilih folder → ada 2 mode:                          ║
║          [1] Single Folder (1 folder, output flat)           ║
║          [2] Multiple Folders (pilih beberapa folder,        ║
║                               struktur folder terjaga)       ║
║    - 0 = Pilih file langsung (single/multiple)               ║
╠══════════════════════════════════════════════════════════════╣
║  Languages (Audio Source):                                   ║
║    id   - Indonesian only                                    ║
║    en   - English only                                       ║
║    auto - Auto-detect / Mixed                                ║
╠══════════════════════════════════════════════════════════════╣
║  Translation (Optional):                                     ║
║    tr id - Translate result to Indonesian                    ║
║    tr en - Translate result to English                       ║
╠══════════════════════════════════════════════════════════════╣
║  Examples:                                                   ║
║    # Audio Indonesian, 1 file                                ║
║    python transcribe.py single id                            ║
║                                                              ║
║    # Audio English, banyak file                              ║
║    python transcribe.py multiple en                          ║
║                                                              ║
║    # Audio English with translate id                         ║
║    python transcribe.py multiple en tr id                    ║
╚══════════════════════════════════════════════════════════════╝
""")


def main():
    if len(sys.argv) < 3:
        show_help()
        sys.exit(0)

    mode = sys.argv[1].lower()
    language = sys.argv[2].lower()

    # Fix: Handle custom_folder mode dengan video conversion
    if mode == "custom_folder":
        # custom_folder mode: langsung proses folder dengan path custom
        if len(sys.argv) < 5:
            print("❌ custom_folder mode requires: path dan file list")
            sys.exit(1)

        folder_path = Path(sys.argv[3])
        files_str = sys.argv[4]
        media_files = [Path(f) for f in files_str.split(",")]

        # validate files
        media_files = [f for f in media_files if f.exists()]

        if not media_files:
            print("❌ Tidak ada file valid")
            sys.exit(1)

        # validate language
        if language not in SUPPORTED_LANGS:
            print(f"❌ Language tidak valid: {language}")
            print("   Gunakan: id, en, ja, atau auto")
            sys.exit(1)

        # check for translation arguments
        do_translate = False
        target_lang = "id"

        if len(sys.argv) >= 7 and sys.argv[5].lower() == "tr":
            do_translate = True
            target_lang = sys.argv[6].lower()
            load_glossary()

        # process dengan custom folder mode
        print("\n📁 Mode: CUSTOM FOLDER")
        print(f"📂 Source: {folder_path}")
        print(f"🌐 Language: {SUPPORTED_LANGS.get(language, 'Auto')}")
        if do_translate:
            print(f"🔤 Translate to: {target_lang}")
        print(f"📋 Files to process: {len(media_files)}")
        print("=" * 60 + "\n")

        # Categorize files: existing audio vs video to convert
        existing_audio_files = []
        video_files_to_convert = []

        for f in media_files:
            if f.suffix.lower() in VIDEO_EXTENSIONS:
                video_files_to_convert.append(f)
            elif f.suffix.lower() in AUDIO_EXTENSIONS:
                existing_audio_files.append(f)

        # Convert video to MP3 in the SAME folder as the video
        converted_audio_files = []
        skipped_conversions = []  # Track videos that already have MP3

        if video_files_to_convert:
            print("📊 File breakdown:")
            print(f"   🎵 Existing audio files: {len(existing_audio_files)}")
            print(f"   🎬 Video files to convert: {len(video_files_to_convert)}")
            print(
                f"\n⚡ Converting {len(video_files_to_convert)} video(s) to MP3 (PARALLEL 4 THREADS)..."
            )
            print("   (MP3 will be saved in the same folder as the video)\n")

            # NEW FEATURE: Check which videos already have MP3 (skip conversion)
            videos_to_convert = []
            for video_file in video_files_to_convert:
                # Check if MP3 with same name already exists
                mp3_path = video_file.with_suffix(".mp3")

                # Also check for numbered versions (e.g., file_1.mp3, file_2.mp3)
                mp3_exists = mp3_path.exists()
                counter = 1
                while not mp3_exists:
                    mp3_path_numbered = (
                        video_file.parent / f"{video_file.stem}_{counter}.mp3"
                    )
                    if mp3_path_numbered.exists():
                        mp3_path = mp3_path_numbered
                        mp3_exists = True
                        break
                    counter += 1
                    if counter > 100:  # Prevent infinite loop
                        break

                if mp3_exists:
                    print(
                        f"⏭️  SKIP: {video_file.name} (MP3 already exists: {mp3_path.name})"
                    )
                    skipped_conversions.append({"video": video_file, "mp3": mp3_path})
                    converted_audio_files.append(mp3_path)  # Use existing MP3
                else:
                    videos_to_convert.append(video_file)

            # Convert only videos that don't have MP3 yet
            if videos_to_convert:
                # NEW FEATURE: Parallel conversion (4 files at once)
                if len(videos_to_convert) >= 4:
                    # Use parallel conversion for batch (4+ files)
                    print(
                        f"\n🚀 Using PARALLEL conversion for {len(videos_to_convert)} file(s)...\n"
                    )
                    converted_results = convert_video_to_mp3_parallel(
                        videos_to_convert,
                        max_workers=4,  # 4 parallel threads
                    )

                    # Collect successful conversions
                    success_count = 0
                    for video, audio_path in zip(videos_to_convert, converted_results):
                        if audio_path:
                            converted_audio_files.append(audio_path)
                            success_count += 1
                        else:
                            print(f"   ❌ Failed: {video.name}")

                    if success_count > 0:
                        print(
                            f"   ✅ Successfully converted {success_count} video(s) to MP3."
                        )
                else:
                    # Sequential conversion for small batches (< 4 files)
                    for i, video_file in enumerate(videos_to_convert, 1):
                        print(
                            f"   [{i}/{len(videos_to_convert)}] Converting: {video_file.name}"
                        )
                        audio_path = convert_video_to_mp3(
                            video_file, output_folder=video_file.parent
                        )
                        if audio_path:
                            converted_audio_files.append(audio_path)
                            print(
                                f"   ✅ Converted: {audio_path.name} (saved in same folder)\n"
                            )
                        else:
                            print(f"   ❌ Failed to convert: {video_file.name}\n")
            else:
                print("\n✅ All videos already have MP3 files! Skipping conversion.\n")

            # Summary
            if converted_audio_files:
                print("\n✅ Conversion summary:")
                print(f"   • Converted: {len(videos_to_convert)} video(s)")
                print(
                    f"   • Skipped (already exist): {len(skipped_conversions)} video(s)"
                )
                print(f"   • Total MP3 ready: {len(converted_audio_files)} file(s)\n")
            else:
                print(
                    "⚠️ No videos were converted. Continuing with existing audio files only.\n"
                )

        # Combine all audio files (existing + converted)
        all_audio_files = existing_audio_files + converted_audio_files

        # Load model AFTER video conversion (to avoid long wait before conversion)
        print("\n" + "=" * 60)
        print("🔄 Loading Whisper model for transcription...")
        model = MLEngine.get_model()
        print("=" * 60 + "\n")

        # Process all audio files
        generated_files = []
        skipped_files = []
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        # Check if any files were already transcribed and ask user once
        any_existing = False
        for audio_file in all_audio_files:
            try:
                rel_path = audio_file.relative_to(folder_path)
            except ValueError:
                rel_path = Path(audio_file.name)

            output_subfolder = OUTPUT_MULTIPLE / folder_path.name / rel_path.parent
            if list(output_subfolder.glob(f"{audio_file.stem}_transcript_*.txt")):
                any_existing = True
                break

        reprocess_all = False
        if any_existing:
            print("\n" + "!" * 60)
            print("⚠️  BEBERAPA FILE SUDAH PERNAH DI-TRANSKRIP")
            print(
                "   Jika diproses ulang, file baru akan dibuat dengan timestamp baru."
            )
            print("!" * 60)
            choice = (
                input(
                    "\nProses ulang semua file? (y = Ya, n = Lewati yang sudah ada [Default]): "
                )
                .strip()
                .lower()
            )
            if choice == "y":
                reprocess_all = True
                print("🚀 Oke, semua file akan diproses ulang!")
            else:
                print("⏭️  Oke, melewati file yang sudah ada.")

        # NEW FEATURE: Parallel transcription (4 files at once)
        files_to_transcribe = []
        files_to_transcribe_info = []

        # First pass: identify files to transcribe
        for i, audio_file in enumerate(all_audio_files, 1):
            # Validate file exists
            if not audio_file.exists():
                print(f"⚠️ SKIP: {audio_file.name} (file no longer exists)")
                continue

            # Skip if output TXT already exists (unless reprocess_all is True)
            try:
                rel_path = audio_file.relative_to(folder_path)
            except ValueError:
                rel_path = Path(audio_file.name)

            output_subfolder = OUTPUT_MULTIPLE / folder_path.name / rel_path.parent
            existing_transcripts = list(
                output_subfolder.glob(f"{audio_file.stem}_transcript_*.txt")
            )

            if existing_transcripts and not reprocess_all:
                print(f"⏭️  SKIP: {rel_path} (already transcribed)")
                skipped_files.append(
                    {"audio": audio_file, "transcripts": existing_transcripts}
                )
                generated_files.append(existing_transcripts[-1])
                continue
            else:
                files_to_transcribe.append(audio_file)
                files_to_transcribe_info.append(
                    {"index": i, "audio": audio_file, "rel_path": rel_path}
                )

        # Transcribe files
        if files_to_transcribe:
            if len(files_to_transcribe) == 1:
                # Single file: Process directly for better log clarity and performance
                audio_file = files_to_transcribe[0]
                print(f"\n🎤 Processing single file: {audio_file.name}...")
                try:
                    _, out_path = process_file(
                        model,
                        audio_file,
                        OUTPUT_MULTIPLE,
                        language,
                        do_translate,
                        target_lang,
                        True,  # preserve_structure
                        folder_path,  # selected_folder
                        timestamp,
                    )
                    generated_files.append(out_path)
                    print(f"   ✅ Completed: {audio_file.name}")
                except Exception as e:
                    print(f"   ❌ Error processing {audio_file.name}: {e}")
            else:
                # Multiple files: Use parallel transcription (4 threads)
                print(
                    f"\n⚡ Starting parallel transcription ({len(files_to_transcribe)} files)...\n"
                )
                from concurrent.futures import ThreadPoolExecutor, as_completed

                def transcribe_single_file(args):
                    """Wrapper for parallel transcription"""
                    (
                        model,
                        audio_file,
                        output_folder,
                        language,
                        do_translate,
                        target_lang,
                        preserve_structure,
                        selected_folder,
                        timestamp,
                    ) = args
                    try:
                        _, out_path = process_file(
                            model,
                            audio_file,
                            output_folder,
                            language,
                            do_translate,
                            target_lang,
                            preserve_structure,
                            selected_folder,
                            timestamp,
                            verbose=False,  # Quiet in parallel
                        )
                        return (audio_file, out_path, None)  # Success
                    except Exception as e:
                        return (audio_file, None, e)  # Error

                # Prepare arguments for parallel processing
                task_args = [
                    (
                        model,
                        audio_file,
                        OUTPUT_MULTIPLE,
                        language,
                        do_translate,
                        target_lang,
                        True,  # preserve_structure
                        folder_path,  # selected_folder
                        timestamp,
                    )
                    for audio_file in files_to_transcribe
                ]

                # Execute in parallel (4 threads)
                with ThreadPoolExecutor(max_workers=4) as executor:
                    futures = {
                        executor.submit(transcribe_single_file, args): audio_file
                        for args, audio_file in zip(task_args, files_to_transcribe)
                    }

                    for future in tqdm(
                        as_completed(futures),
                        total=len(futures),
                        desc="Transcribing",
                        unit="file",
                        leave=False,
                    ):
                        audio_file = futures[future]
                        try:
                            result_audio, out_path, error = future.result()
                            if out_path:
                                generated_files.append(out_path)
                                # Just let tqdm handle the progress in parallel
                            else:
                                print(f"\n   ❌ Failed: {audio_file.name} - {error}")
                        except Exception as e:
                            print(f"\n   ❌ Error processing {audio_file.name}: {e}")

            print(
                f"\n✅ Transcription complete: {len(generated_files) - len(skipped_files)} files processed"
            )
        else:
            print("\n⏭️  All files already transcribed! Skipping transcription.")

        print("\n" + "=" * 60)
        print("✅ Custom folder processing complete!")
        print("   📊 Summary:")
        print(f"      • Total files scanned: {len(all_audio_files)}")
        print(
            f"      • ✅ Newly transcribed: {len(all_audio_files) - len(skipped_files)}"
        )
        print(f"      • ⏭️  Skipped (already exist): {len(skipped_files)}")
        print(f"      • 📂 Output : {(OUTPUT_MULTIPLE / folder_path.name).resolve()}")
        print("=" * 60)

        # Show skipped files detail
        if skipped_files:
            print(f"\n📋 Skipped Files ({len(skipped_files)} files):")
            for item in skipped_files[:10]:  # Show first 10
                try:
                    rel_path = item["audio"].relative_to(folder_path)
                    print(f"   ⏭️  {rel_path}")
                except ValueError:
                    print(f"   ⏭️  {item['audio'].name}")
            if len(skipped_files) > 10:
                print(f"   ... and {len(skipped_files) - 10} more")
            print()

        # PDF Conversion Prompt
        pdf_generated = False
        if generated_files:
            print("\n" + "-" * 50)
            print("📄 PDF Conversion")
            choice = input("Convert to PDF? (1 = Yes, 0 = No): ").strip()
            if choice == "1":
                print("\n🔄 Generating PDFs...")
                for txt_path in generated_files:
                    convert_pdf.txt_to_pdf(txt_path)
                print("\n✨ All PDF tasks completed.")
                pdf_generated = True
            else:
                print("👌 Skipped PDF conversion.")

        # Cleanup Prompt - Delete converted MP3 files?
        if converted_audio_files and len(converted_audio_files) > 0:
            print("\n" + "-" * 50)
            print("🗑️ Cleanup Converted MP3 Files")
            print("=" * 50)
            print("⚠️  SAFETY NOTICE:")
            print("   - Only MP3 files CONVERTED from VIDEO will be deleted")
            print(
                f"   - {len(existing_audio_files)} original MP3/audio files are SAFE (will NOT be deleted)"
            )
            print("=" * 50)
            print(
                f"\n   You have {len(converted_audio_files)} MP3 file(s) from video conversion:"
            )
            for mp3_file in converted_audio_files[:5]:  # Show first 5
                # Show relative path for better readability
                try:
                    rel_path = mp3_file.relative_to(folder_path)
                    print(f"   - {rel_path}")
                except ValueError:
                    print(f"   - {mp3_file.name}")
            if len(converted_audio_files) > 5:
                print(f"   ... and {len(converted_audio_files) - 5} more")

            print("\n📝 These are the files that WILL BE DELETED if you choose '1':")
            print("   (Original MP3 files are NOT included)")

            cleanup_choice = input(
                "\nDelete these converted MP3 files? (1 = Yes, 0 = No): "
            ).strip()

            if cleanup_choice == "1":
                print("\n🗑️ Deleting converted MP3 files...")
                deleted_count = 0
                for mp3_file in converted_audio_files:
                    try:
                        if mp3_file.exists():
                            mp3_file.unlink()
                            deleted_count += 1
                            # Show relative path
                            try:
                                rel_path = mp3_file.relative_to(folder_path)
                                print(f"   ✅ Deleted: {rel_path}")
                            except ValueError:
                                print(f"   ✅ Deleted: {mp3_file.name}")
                    except Exception as e:
                        print(f"   ❌ Failed to delete {mp3_file.name}: {e}")

                if deleted_count > 0:
                    print(f"\n✅ Successfully deleted {deleted_count} MP3 file(s)")
                    print(
                        f"👍 Original {len(existing_audio_files)} audio files are SAFE!"
                    )
                else:
                    print("\n⚠️ No files were deleted")
            else:
                print(
                    f"\n👌 Keeping {len(converted_audio_files)} converted MP3 file(s)"
                )
                print("👍 All files (original + converted) are SAFE!")
        else:
            # No converted files, but show info about existing audio
            if existing_audio_files:
                print("\n" + "-" * 50)
                print("ℹ️  No converted MP3 files to clean up")
                print(
                    f"👍 All {len(existing_audio_files)} original audio files are SAFE!"
                )

        return generated_files

    # validate mode
    if mode not in ("single", "multiple", "folder"):
        print(f"❌ Mode tidak valid: {mode}")
        print("   Gunakan: single, multiple, atau folder")
        sys.exit(1)

    # validate language
    if language not in SUPPORTED_LANGS:
        print(f"❌ Language tidak valid: {language}")
        print("   Gunakan: id, en, ja, atau auto")
        sys.exit(1)

    # check for translation arguments
    do_translate = False
    target_lang = "id"
    preselected_files = None  # Files passed from main.py

    if len(sys.argv) >= 4:
        # Check if 4th argument is file list (for multiple mode from main.py)
        if mode == "multiple" and "," in sys.argv[3]:
            # File list passed directly: multiple,language,file1,file2,...
            files_str = sys.argv[3]
            preselected_files = [
                Path(f) for f in files_str.split(",") if Path(f).exists()
            ]
            if preselected_files:
                print(f"✅ {len(preselected_files)} file(s) received from main.py")
                for f in preselected_files:
                    print(f"   📄 {f.name}")
        elif len(sys.argv) >= 5 and sys.argv[3].lower() == "tr":
            do_translate = True
            target_lang = sys.argv[4].lower()
            # load glossary only if translating
            load_glossary()

    # load model
    model = MLEngine.get_model()

    # If files were preselected (from main.py), skip user prompt
    if preselected_files:
        print("\n📁 Mode: MULTIPLE (Pre-selected)")
        print(f"🌐 Language: {SUPPORTED_LANGS.get(language, 'Auto')}")
        print(f"📂 Output folder: {OUTPUT_MULTIPLE.resolve()}")
        print(f"📋 Files: {len(preselected_files)}")
        print("=" * 50 + "\n")

        # Create batch folder
        batch_num = get_next_batch_number()
        batch_folder = OUTPUT_MULTIPLE / f"batch_{batch_num:03d}"
        batch_folder.mkdir(parents=True, exist_ok=True)

        generated_files = []
        for i, audio_file in enumerate(preselected_files, 1):
            print(f"\n[{i}/{len(preselected_files)}] Processing...")
            print("-" * 40)
            _, out_path = process_file(
                model, audio_file, batch_folder, language, do_translate, target_lang
            )
            generated_files.append(out_path)

        print("\n" + "=" * 50)
        print("✅ Batch complete!")
        print(f"   Processed: {len(preselected_files)} files")
        print(f"   Output: {batch_folder}")
        print("=" * 50)

        # PDF conversion
        if generated_files:
            print("\n" + "-" * 50)
            print("📄 PDF Conversion")
            choice = input("Convert to PDF? (1 = Yes, 0 = No): ").strip()
            if choice == "1":
                print("\n🔄 Generating PDFs...")
                for txt_path in generated_files:
                    convert_pdf.txt_to_pdf(txt_path)
                print("\n✨ All PDF tasks completed.")
            else:
                print("👌 Skipped PDF conversion.")
        return

    # ask user: folder or file selection?
    # Skip menu if file path(s) are provided via command line
    has_file_args = (
        len(sys.argv) > 3
        and mode in ("single", "multiple")
        and not sys.argv[3].startswith("/")
    )

    if has_file_args:
        # File path(s) already provided via command line, skip menu
        new_files = []

        if mode == "single":
            # Single file mode - file path is in sys.argv[3]
            file_path = Path(sys.argv[3])
            if not file_path.exists():
                print(f"❌ File tidak ditemukan: {file_path}")
                sys.exit(1)

            lang_display = SUPPORTED_LANGS.get(language, "Auto")
            print("\n📁 Mode: SINGLE")
            print(f"🌐 Language: {lang_display}")
            if do_translate:
                print(f"🔤 Translate to: {target_lang}")
            print(f"📂 File: {file_path.name}")
            print("=" * 50 + "\n")

            result, output_path = process_file(
                model, file_path, OUTPUT_SINGLE, language, do_translate, target_lang
            )
            print(f"\n✅ Done! Output: {output_path}")
            new_files = [output_path]

        elif mode == "multiple":
            # Multiple files mode - file paths are comma-separated in sys.argv[3]
            files_str = sys.argv[3]
            file_paths = [Path(f) for f in files_str.split(",")]

            # Validate files
            file_paths = [f for f in file_paths if f.exists()]
            if not file_paths:
                print("❌ Tidak ada file valid")
                sys.exit(1)

            lang_display = SUPPORTED_LANGS.get(language, "Auto")
            print("\n📁 Mode: MULTIPLE")
            print(f"🌐 Language: {lang_display}")
            if do_translate:
                print(f"🔤 Translate to: {target_lang}")
            print(f"📋 Files to process: {len(file_paths)}")
            print("=" * 50 + "\n")

            # Create batch folder
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            batch_folder = OUTPUT_MULTIPLE / f"batch_{timestamp}"
            batch_folder.mkdir(parents=True, exist_ok=True)

            # Process all files
            for i, audio_file in enumerate(file_paths, 1):
                print(f"\n[{i}/{len(file_paths)}] Processing: {audio_file.name}")
                _, out_path = process_file(
                    model, audio_file, batch_folder, language, do_translate, target_lang
                )
                new_files.append(out_path)

            print(f"\n✅ Done! Processed {len(new_files)} files")
            print(f"📂 Output folder: {batch_folder.resolve()}")
    else:
        # No file args provided, show interactive menu
        print("\n" + "=" * 50)
        print("📁 PILIH SUMBER AUDIO")
        print("=" * 50)
        folder_choice = input("Pilih dari folder? (1 = Ya, 0 = Tidak): ").strip()

        new_files = []

        if folder_choice == "1":
            # mode folder - pilih subfolder lalu extract semua file di dalamnya
            new_files = mode_folder(model, language, do_translate, target_lang)
        else:
            # mode file - pilih file individual
            if mode == "single":
                new_files = mode_single(model, language, do_translate, target_lang)
            elif mode == "multiple":
                new_files = mode_multiple(model, language, do_translate, target_lang)

    # PDF Conversion Prompt
    if new_files:
        print("\n" + "-" * 50)
    # PDF Conversion Prompt
    if new_files:
        print("\n" + "-" * 50)
        print("📄 PDF Conversion")
        choice = input("Convert to PDF? (1 = Yes, 0 = No): ").strip()
        if choice == "1":
            print("\n🔄 Generating PDFs...")
            for txt_path in new_files:
                convert_pdf.txt_to_pdf(txt_path)
            print("\n✨ All PDF tasks completed.")
        else:
            print("👌 Skipped PDF conversion.")


if __name__ == "__main__":
    main()
