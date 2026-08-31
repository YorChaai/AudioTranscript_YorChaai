"""
Audio to Text Transcription using Faster-Whisper
Supports: Indonesian, English, Japanese, and Mixed (Code-Switching)
Model: large-v3 (GPU accelerated)

Modes:
  - single: Process 1 file
  - multiple: Process multiple files
  - folder: Process all files in a folder
  - custom_folder: Internal mode for main.py integration
"""

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import List

from tqdm import tqdm

from core.ml_engine import MLEngine
from core.transcription import process_file, get_relative_path_from_audio
from core.translator import load_glossary
from config import (
    BASE_DIR, AUDIO_FOLDER, OUTPUT_SINGLE, OUTPUT_MULTIPLE,
    AUDIO_EXTENSIONS, VIDEO_EXTENSIONS, SUPPORTED_LANGS,
    MODEL_SIZE, LOCAL_MODEL_PATH, DEVICE, COMPUTE_TYPE, AUTO_TRANSLATE_TARGET
)
from utils import (
    convert_video_to_mp3,
    convert_video_to_mp3_parallel,
    get_audio_info_technical,
    repair_audio_ffmpeg,
    handle_pdf_conversion_prompt,
    wait_for_downloads,
)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# ============================================================
# HELPER FUNCTIONS
# ============================================================

def parse_selection(input_str: str, max_num: int) -> List[int]:
    """Parse selection string like '1,3,4' into list of integers."""
    numbers = []
    parts = input_str.replace(" ", "").split(",")
    for part in parts:
        try:
            num = int(part)
            if 1 <= num <= max_num:
                numbers.append(num)
        except ValueError:
            pass
    return sorted(list(set(numbers)))

def get_audio_files(folder: Path, recursive: bool = False) -> List[Path]:
    """Get all media files from folder."""
    if not folder.exists():
        return []

    MEDIA_EXTENSIONS = AUDIO_EXTENSIONS | VIDEO_EXTENSIONS
    files = []
    scanner = folder.rglob if recursive else folder.iterdir

    for f in scanner("*") if recursive else scanner():
        if f.is_file() and f.suffix.lower() in MEDIA_EXTENSIONS:
            files.append(f)
    return sorted(files)

def get_next_batch_number() -> int:
    """Find the next batch number for output folder."""
    if not OUTPUT_MULTIPLE.exists():
        return 1
    existing = [d for d in OUTPUT_MULTIPLE.iterdir() if d.is_dir() and d.name.startswith("batch_")]
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

# ============================================================
# INTERACTIVE MODES
# ============================================================

def mode_single(model, language: str, do_translate: bool = False, target_lang: str = "id"):
    files = get_audio_files(AUDIO_FOLDER)
    if not files:
        print(f"❌ Tidak ada file audio di: {AUDIO_FOLDER}")
        return []

    print(f"\n📂 Files in audio/ ({len(files)} files):")
    for i, f in enumerate(files, 1):
        print(f"  [{i}] {f.name}")

    user_input = input("\nPilih nomor: ").strip()
    numbers = parse_selection(user_input, len(files))
    if not numbers:
        return []

    audio_file = files[numbers[-1] - 1]
    _, output_path = process_file(model, audio_file, OUTPUT_SINGLE, language, do_translate, target_lang)
    return [output_path]

def mode_multiple(model, language: str, do_translate: bool = False, target_lang: str = "id", files_override=None):
    files = files_override or get_audio_files(AUDIO_FOLDER)
    if not files:
        print(f"❌ Tidak ada file audio di: {AUDIO_FOLDER}")
        return []

    if not files_override:
        print(f"\n📂 Files in audio/ ({len(files)} files):")
        for i, f in enumerate(files, 1):
            print(f"  [{i}] {f.name}")
        user_input = input("\nPilih nomor (pisah koma, contoh: 1,3): ").strip()
        numbers = parse_selection(user_input, len(files))
        selected_files = [files[n - 1] for n in numbers]
    else:
        selected_files = files

    if not selected_files:
        return []

    batch_folder = OUTPUT_MULTIPLE / f"batch_{get_next_batch_number():03d}"
    batch_folder.mkdir(parents=True, exist_ok=True)

    generated_files = []
    for i, audio_file in enumerate(selected_files, 1):
        print(f"\n[{i}/{len(selected_files)}] Processing: {audio_file.name}")
        _, out_path = process_file(model, audio_file, batch_folder, language, do_translate, target_lang)
        generated_files.append(out_path)

    return generated_files

def mode_folder(model, language: str, do_translate: bool = False, target_lang: str = "id"):
    subfolders = sorted([f for f in AUDIO_FOLDER.iterdir() if f.is_dir()])
    if not subfolders:
        print(f"❌ Tidak ada folder di: {AUDIO_FOLDER}")
        return []

    print("\n📂 Folders in audio/:")
    for i, f in enumerate(subfolders, 1):
        print(f"  [{i}] {f.name}")

    user_input = input("\nPilih nomor folder: ").strip()
    try:
        folder_idx = int(user_input) - 1
        selected_folder = subfolders[folder_idx]
    except (ValueError, IndexError):
        return []

    audio_files = get_audio_files(selected_folder, recursive=True)
    return mode_multiple(model, language, do_translate, target_lang, files_override=audio_files)

# ============================================================
# MAIN EXECUTION logic
# ============================================================

def handle_custom_folder(args, model):
    """Special handling for custom_folder mode used by main.py"""
    folder_path = Path(args.folder_path)
    if args.file_list.endswith('.txt') and Path(args.file_list).exists():
        with open(args.file_list, 'r', encoding='utf-8') as f:
            media_files = [Path(line.strip()) for line in f if line.strip()]
    else:
        media_files = [Path(f) for f in args.file_list.split(",")]
        
    media_files = [f for f in media_files if f.exists()]

    if not media_files:
        print("❌ Tidak ada file valid")
        return []

    # Separate existing audio and videos to convert
    existing_audio = [f for f in media_files if f.suffix.lower() in AUDIO_EXTENSIONS]
    videos = [f for f in media_files if f.suffix.lower() in VIDEO_EXTENSIONS]

    print("\n" + "=" * 50)
    print("📊 SUMMARY SEBELUM PROSES")
    print("=" * 50)
    print(f"Total file yang akan diproses: {len(media_files)}")
    print(f"  🎵 Audio : {len(existing_audio)} files")
    print(f"  🎬 Video : {len(videos)} files (Akan di-convert ke MP3)")
    print(f"Lokasi output: {OUTPUT_MULTIPLE.name}")
    print("=" * 50)
    
    proceed = input("\nLanjutkan proses? (1 = Yes, 0 = No): ").strip()
    if proceed == "0":
        print("❌ Proses dibatalkan oleh pengguna.")
        return []

    # Wait for files to be fully downloaded from cloud/OneDrive
    wait_for_downloads(media_files)

    converted_audio = []
    if videos:
        print(f"\n⚡ Converting {len(videos)} video(s) to MP3...")
        converted_audio = convert_video_to_mp3_parallel(videos, max_workers=4)
        converted_audio = [f for f in converted_audio if f]

    all_audio = existing_audio + converted_audio

    if args.translate:
        load_glossary()

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    generated_files = []

    for i, audio_file in enumerate(all_audio, 1):
        print(f"\n[{i}/{len(all_audio)}] Transcribing: {audio_file.name}")
        try:
            _, out_path = process_file(
                model, audio_file, OUTPUT_MULTIPLE, args.language,
                args.translate, args.target_lang,
                preserve_structure=True, selected_folder=folder_path,
                timestamp=timestamp, audio_base_folder=AUDIO_FOLDER
            )
            generated_files.append(out_path)
        except Exception as e:
            print(f"   ❌ Error: {e}")

    # Cleanup converted MP3s if requested
    if converted_audio:
        print("\n🗑️ Cleanup Converted MP3 Files")
        cleanup = input("Keep the converted MP3 files? (1 = Yes, 0 = No): ").strip()
        if cleanup == "0":
            for f in converted_audio:
                try: f.unlink()
                except: pass
            print(f"✅ Deleted {len(converted_audio)} temporary files.")

    return generated_files

def main():
    parser = argparse.ArgumentParser(description="Audio to Text Transcription CLI")
    parser.add_argument("mode", choices=["single", "multiple", "folder", "custom_folder"], help="Transcription mode")
    parser.add_argument("language", help="Source language (id, en, ja, auto)")
    parser.add_argument("path_arg", nargs="?", help="Folder path or single file path")
    parser.add_argument("list_arg", nargs="?", help="Comma separated file list")
    parser.add_argument("--translate", action="store_true", help="Enable translation")
    parser.add_argument("--target_lang", default="id", help="Target language for translation")

    # Handle legacy 'tr' argument format: transcribe.py single id tr en
    if len(sys.argv) >= 5 and sys.argv[3].lower() == "tr":
        # Transform legacy format to work with argparse or handle manually
        mode = sys.argv[1].lower()
        lang = sys.argv[2].lower()
        do_tr = True
        target = sys.argv[4].lower()
        args = parser.parse_args([mode, lang, "--translate", "--target_lang", target])
    else:
        # Standard argparse
        try:
            # First try parsing everything
            args = parser.parse_args()
        except SystemExit:
            # Fallback for how main.py calls it: mode, language, file_list, folder_path
            # We check manually for 'tr' keyword in the arguments list
            do_tr = False
            target = "id"
            if "tr" in sys.argv:
                tr_idx = sys.argv.index("tr")
                do_tr = True
                if tr_idx + 1 < len(sys.argv):
                    target = sys.argv[tr_idx+1]
                # Filter out 'tr' and target_lang from argv for argparse
                filtered_argv = [v for i, v in enumerate(sys.argv) if i != tr_idx and i != tr_idx + 1]
                args = parser.parse_args(filtered_argv[1:])
                args.translate = do_tr
                args.target_lang = target
            else:
                # Re-raise or handle as default
                if len(sys.argv) < 3:
                    parser.print_help()
                    return
                # Manual simple parse for unconventional argument patterns
                args = parser.parse_args(sys.argv[1:])

    # Load Model
    model = MLEngine.get_model()
    generated_files = []

    if args.mode == "custom_folder":
        # main.py passes: mode language folder_path file_list
        args.folder_path = args.path_arg
        args.file_list = args.list_arg
        generated_files = handle_custom_folder(args, model)
    elif args.mode == "single":
        if args.path_arg and not args.path_arg.startswith("--"):
            # Direct file path provided
            _, out_path = process_file(model, Path(args.path_arg), OUTPUT_SINGLE, args.language, args.translate, args.target_lang)
            generated_files = [out_path]
        else:
            generated_files = mode_single(model, args.language, args.translate, args.target_lang)
    elif args.mode == "multiple":
        if args.path_arg and not args.path_arg.startswith("--"):
            # main.py passes: mode language file_list
            if args.path_arg.endswith('.txt') and Path(args.path_arg).exists():
                with open(args.path_arg, 'r', encoding='utf-8') as f:
                    files = [Path(line.strip()) for line in f if line.strip() and Path(line.strip()).exists()]
            else:
                files = [Path(f) for f in args.path_arg.split(",") if Path(f).exists()]
            generated_files = mode_multiple(model, args.language, args.translate, args.target_lang, files_override=files)
        else:
            generated_files = mode_multiple(model, args.language, args.translate, args.target_lang)
    elif args.mode == "folder":
        generated_files = mode_folder(model, args.language, args.translate, args.target_lang)

    # Common PDF Prompt (Deduplicated)
    if generated_files:
        handle_pdf_conversion_prompt(generated_files)

if __name__ == "__main__":
    main()
