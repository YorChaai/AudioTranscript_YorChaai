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

import os
import sys
import convert_pdf
from pathlib import Path
from datetime import datetime
from faster_whisper import WhisperModel
from tqdm import tqdm
import math
from deep_translator import GoogleTranslator
import json

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# konfigurasi
MODEL_SIZE = "large-v3"
DEVICE = "cuda"
COMPUTE_TYPE = "float16"
AUTO_TRANSLATE_TARGET = "id"

# folder paths
BASE_DIR = Path(__file__).parent
AUDIO_FOLDER = BASE_DIR / "audio"
OUTPUT_SINGLE = BASE_DIR / "convert txt" / "single"
OUTPUT_MULTIPLE = BASE_DIR / "convert txt" / "multiple"

# supported audio formats
AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".flac", ".ogg", ".wma", ".aac", ".mp4"}

# supported languages
SUPPORTED_LANGS = {
    "id": "Indonesian",
    "en": "English",
    "ja": "Japanese",
    "auto": "Auto-detect (Mixed)"
}

# Glossary: English -> Indonesian
# Istilah in akan diproses menjadi: "Terjemahan (Istilah Asli)"
# Contoh: "data scientist" -> "ilmuwan data (data scientist)"


# Glossary loaded from assets/glossary.json
GLOSSARY = {
    "data scientist": "ilmuwan data",
    # default fallback if file not found
}

def load_glossary():
    """Load glossary from assets/glossary.json"""
    global GLOSSARY
    glossary_path = BASE_DIR / "assets" / "glossary.json"

    if glossary_path.exists():
        try:
            with open(glossary_path, "r", encoding="utf-8") as f:
                GLOSSARY = json.load(f)
            print(f"📘 Glossary loaded: {len(GLOSSARY)} terms")
        except Exception as e:
            print(f"⚠️ Failed to load glossary: {e}")
    else:
        print("⚠️ Glossary file not found, using minimal default.")


def format_time(seconds: float) -> str:
    """convert detik ke format MM:SS"""
    minutes = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{minutes:02d}:{secs:02d}"


# Fix H5: Model caching untuk avoid reload setiap run
_model_cache = None


def load_model():
    """
    load whisper model ke GPU dengan caching
    Model hanya dimuat sekali, subsequent calls return cached model
    """
    global _model_cache

    if _model_cache is not None:
        print("✅ Using cached model")
        return _model_cache

    print(f"🔄 Loading model '{MODEL_SIZE}'...")
    print("   (Download pertama kali bisa lama ~3GB)")

    _model_cache = WhisperModel(
        MODEL_SIZE,
        device=DEVICE,
        compute_type=COMPUTE_TYPE
    )

    print("✅ Model loaded!\n")
    return _model_cache


def apply_glossary_pre(text: str) -> tuple[str, dict]:
    """
    Ganti istilah teknis dengan marker sementara agar tidak diterjemahkan Google.
    Returns: (text_with_markers, mapping_marker_to_final_string)
    """
    import re

    mapping = {}
    modified_text = text

    # Sort by length descending to match longest phrases first
    sorted_terms = sorted(GLOSSARY.keys(), key=len, reverse=True)

    counter = 0
    for english_term in sorted_terms:
        # Case insensitive regex match for whole words
        pattern = re.compile(re.escape(english_term), re.IGNORECASE)

        matches = list(pattern.finditer(modified_text))
        if not matches:
            continue

        # Kita pakai marker unik, misal __GLOSSARY_0__
        # Tapi kita harus replace satu per satu dari text

        # Buat temporary placeholder
        marker = f"__GLOSS_ID_{counter}__"
        indonesian_term = GLOSSARY[english_term]

        # Format akhir: "Ilmuwan Data (Data Scientist)"
        # Kita perlu preserve casing asli dari english term jika memungkinkan, tapi untuk simplicity:
        # Kita simpan string final yang kita inginkan di mapping

        # Skenario: "I am a Data Scientist" -> "I am a __GLOSS_ID_0__"
        # Nanti setelah translate: "Saya adalah __GLOSS_ID_0__" -> "Saya adalah ilmuwan data (data scientist)"

        final_replacement = f"{indonesian_term} ({english_term})"
        mapping[marker] = final_replacement

        # Replace di text (case insensitive)
        modified_text = pattern.sub(marker, modified_text)
        counter += 1

    return modified_text, mapping


def apply_glossary_post(text: str, mapping: dict) -> str:
    """Restore marker dengan format final"""
    for marker, replacement in mapping.items():
        text = text.replace(marker, replacement)
    return text


def translate_text(text: str, target_lang: str = 'id') -> str:
    """Translate text using Google Translator (handles long text)"""
    translator = GoogleTranslator(source='auto', target=target_lang)

    # split by lines to avoid char limit issues
    lines = text.split('\n')
    translated_lines = []

    print(f"   ⏳ Translating to '{target_lang}' (with glossary)...")

    for line in tqdm(lines, desc="Translating", unit="line", leave=False):
        if not line.strip():
            translated_lines.append("")
            continue

        try:
            # 1. Pre-process: Ganti istilah teknis dengan marker
            line_marked, mapping = apply_glossary_pre(line)

            # 2. Translate text yang sudah ada marker
            res = translator.translate(line_marked)

            # 3. Post-process: Balikin marker jadi "Indo (Inggris)"
            final_res = apply_glossary_post(res, mapping)

            translated_lines.append(final_res)
        except Exception as e:
            translated_lines.append(f"[Translation Error: {e}]")

    return "\n".join(translated_lines)


def resolve_translation_target(detected_language: str | None, do_translate: bool, target_lang: str) -> tuple[bool, str]:
    """Default: semua bahasa non-Indonesia otomatis diterjemahkan ke Indonesia."""
    detected = (detected_language or "").lower().strip()
    requested_target = (target_lang or AUTO_TRANSLATE_TARGET).lower().strip()

    if do_translate:
        if detected and detected == requested_target:
            return False, requested_target
        return True, requested_target

    if detected and detected != AUTO_TRANSLATE_TARGET:
        return True, AUTO_TRANSLATE_TARGET

    return False, requested_target


# Fix H1: Merge redundant functions dengan parameter recursive
def get_audio_files(folder: Path, recursive: bool = False) -> list:
    """
    ambil semua file audio dari folder
    Args:
        folder: folder path
        recursive: jika True, scan semua subfolder (default: False)
    Returns:
        list of Path objects, sorted
    """
    if not folder.exists():
        return []

    files = []
    if recursive:
        # Scan semua subfolder
        for f in folder.rglob("*"):
            if f.is_file() and f.suffix.lower() in AUDIO_EXTENSIONS:
                files.append(f)
    else:
        # Level 1 saja
        for f in folder.iterdir():
            if f.is_file() and f.suffix.lower() in AUDIO_EXTENSIONS:
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


def transcribe_audio(model, audio_path: Path, language: str = None) -> dict:
    """transkripsi file audio ke teks"""
    print(f"🎤 Transcribing: {audio_path.name}")

    # set language (None = auto-detect)
    lang_param = None if language == "auto" else language
    lang_display = SUPPORTED_LANGS.get(language, "Auto-detect")
    print(f"   Language mode: {lang_display}")

    # Get generator and info immediately
    # info.duration provides the EXACT duration of the audio as seen by Whisper
    segments, info = model.transcribe(
        str(audio_path),
        language=lang_param,
        beam_size=5,
        word_timestamps=True,
        vad_filter=True,
    )

    total_duration = info.duration
    detected = info.language
    prob = info.language_probability

    # progress bar using accurate duration
    pbar = tqdm(total=total_duration, unit="s", unit_scale=True, bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}]")

    full_text = ""
    all_segments = []

    last_end = 0

    for segment in segments:
        text = segment.text.strip()
        full_text += text + "\n"
        all_segments.append({
            "start": segment.start,
            "end": segment.end,
            "text": text
        })

        # update pbar based on segment progress
        increment = segment.end - last_end
        if increment > 0:
            pbar.update(increment)
        last_end = segment.end

    # ensure 100% completion visual
    pbar.update(total_duration - last_end)
    pbar.close()

    print(f"   Detected/Used: {detected} ({prob:.1%})")

    return {
        "text": full_text.strip(),
        "language": detected,
        "language_mode": language,
        "language_probability": prob,
        "segments": all_segments
    }


def wrap_text_by_words(text: str, max_words: int = 15) -> str:
    """Wrap text to roughly max_words per line"""
    words = text.split()
    lines = []
    current_line = []

    for word in words:
        current_line.append(word)
        if len(current_line) >= max_words:
            lines.append(" ".join(current_line))
            current_line = []

    if current_line:
        lines.append(" ".join(current_line))

    return "\n".join(lines)


def save_transcript(result: dict, output_path: Path, source_file: str, translated_text: str = None, target_lang: str = None):
    """simpan hasil transkripsi ke file txt"""
    output_path.parent.mkdir(parents=True, exist_ok=True)

    lang_mode = SUPPORTED_LANGS.get(result['language_mode'], 'Auto')


    with open(output_path, "w", encoding="utf-8") as f:
        f.write(f"Source: {source_file}\n")
        f.write(f"Language Mode: {lang_mode}\n")
        f.write(f"Detected: {result['language']} ({result['language_probability']:.1%})\n")
        f.write(f"Transcribed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write("=" * 50 + "\n\n")

        # main text with semicolons (satu baris, PDF auto-wrap)
        semicolon_text = " ; ".join([s['text'].strip() for s in result['segments']])
        f.write(semicolon_text)

        f.write("\n\n" + "=" * 50 + "\n")
        f.write("TIMESTAMPS:\n\n")
        for seg in result["segments"]:
            f.write(f"[{format_time(seg['start'])} - {format_time(seg['end'])}]\n{seg['text']}\n\n")

        if translated_text:
            f.write("=" * 50 + "\n\n")
            f.write(f"TRANSLATION ({target_lang.upper()}):\n\n")
            f.write(translated_text)
            f.write("\n\n")

    print(f"💾 Saved: {output_path.name}\n")


def get_next_batch_number() -> int:
    """cari nomor batch berikutnya"""
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


def get_mirror_output_path(audio_file: Path, selected_folder: Path, timestamp: str) -> Path:
    """
    buat path output yang mencerminkan struktur folder sumber
    Contoh:
      audio_file = audio/asonis/folder1/audio1.mp3
      selected_folder = audio/asonis
      timestamp = 20260327_143022
      Return: convert txt/asonis/folder1/audio1_transcript_20260327_143022.txt
    """
    # dapatkan path relatif dari selected_folder ke audio_file
    rel_path = audio_file.relative_to(selected_folder)

    # buat folder output di dalam OUTPUT_MULTIPLE dengan struktur yang sama
    # OUTPUT_MULTIPLE = convert txt/multiple
    output_base = OUTPUT_MULTIPLE / get_relative_path_from_audio(selected_folder)
    output_folder = output_base / rel_path.parent

    # create folder jika belum ada
    output_folder.mkdir(parents=True, exist_ok=True)

    # buat nama file dengan timestamp
    output_name = f"{audio_file.stem}_transcript_{timestamp}.txt"
    output_path = output_folder / output_name

    return output_path


def process_file(model, audio_file: Path, output_folder: Path, language: str, do_translate: bool = False, target_lang: str = 'id', preserve_structure: bool = False, selected_folder: Path = None, timestamp: str = None):
    """
    process satu file audio
    preserve_structure: jika True, output akan mengikuti struktur folder sumber
    selected_folder: folder sumber yang dipilih (hanya digunakan jika preserve_structure=True)
    timestamp: timestamp untuk nama file (hanya digunakan jika preserve_structure=True)
    """
    result = transcribe_audio(model, audio_file, language)

    # tambah timestamp ke nama file
    if timestamp is None:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

    # tentukan output path berdasarkan mode
    if preserve_structure and selected_folder:
        output_path = get_mirror_output_path(audio_file, selected_folder, timestamp)
    else:
        output_name = f"{audio_file.stem}_transcript_{timestamp}.txt"
        output_path = output_folder / output_name

    translated_text = None
    should_translate, final_target_lang = resolve_translation_target(
        result["language"], do_translate, target_lang
    )
    if should_translate:
        load_glossary()
        if do_translate:
            print(f"   🌐 Translating transcript to '{final_target_lang}'...")
        else:
            print(f"   🌐 Auto-translating detected '{result['language']}' transcript to '{final_target_lang}'...")
        translated_text = translate_text(result["text"], final_target_lang)

    save_transcript(result, output_path, audio_file.name, translated_text, final_target_lang)

    return result, output_path


def mode_single(model, language: str, do_translate: bool = False, target_lang: str = 'id'):
    """process mode single - pilih 1 file dari daftar"""
    files = get_audio_files(AUDIO_FOLDER)

    if not files:
        print(f"❌ Tidak ada file audio di: {AUDIO_FOLDER}")
        print(f"   Taruh file MP3/WAV di folder tersebut, lalu run lagi.")
        return

    # tampilkan daftar file
    display_files(files)

    # minta input user
    print("\n📝 Mode: SINGLE (hanya file terakhir yang diproses)")
    user_input = input("Pilih nomor (contoh: 1 atau 1,2,3 - terakhir diambil): ").strip()

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
    print(f"\n📁 Mode: SINGLE")
    print(f"🌐 Language: {lang_display}")
    if do_translate:
        print(f"🔤 Translate to: {target_lang}")
    print(f"📂 Selected: [{selected_num}] {audio_file.name}")
    print("=" * 50 + "\n")

    result, output_path = process_file(model, audio_file, OUTPUT_SINGLE, language, do_translate, target_lang)

    print("=" * 50)
    # print("📝 FULL TRANSCRIPT:")
    # print("=" * 50)
    # print(result["text"])
    # print("=" * 50)
    print(f"\n✅ Done! Output: {output_path}")
    return [output_path]


def mode_multiple(model, language: str, do_translate: bool = False, target_lang: str = 'id'):
    """process mode multiple - pilih beberapa file dari daftar"""
    files = get_audio_files(AUDIO_FOLDER)

    if not files:
        print(f"❌ Tidak ada file audio di: {AUDIO_FOLDER}")
        print(f"   Taruh file MP3/WAV di folder tersebut, lalu run lagi.")
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
    print(f"\n📁 Mode: MULTIPLE (Batch)")
    print(f"🌐 Language: {lang_display}")
    if do_translate:
        print(f"🔤 Translate to: {target_lang}")
    print(f"📂 Output folder: {batch_folder}")
    print(f"📋 Selected files: {len(selected_files)}")
    for n, f in zip(numbers, selected_files):
        print(f"   [{n}] {f.name}")
    print("=" * 50 + "\n")

    generated_files = []

    for i, audio_file in enumerate(selected_files, 1):
        print(f"\n[{i}/{len(selected_files)}] Processing...")
        print("-" * 40)

        _, out_path = process_file(model, audio_file, batch_folder, language, do_translate, target_lang)
        generated_files.append(out_path)

    print("\n" + "=" * 50)
    print("✅ Batch complete!")
    print(f"   Processed: {len(selected_files)} files")
    print(f"   Language: {lang_display}")
    print(f"   Output: {batch_folder}")
    print("=" * 50)
    return generated_files


def mode_folder_single(model, language: str, do_translate: bool = False, target_lang: str = 'id'):
    """process mode single folder - pilih 1 folder dan extract semua file di dalamnya"""
    folders = get_subfolders(AUDIO_FOLDER)

    if not folders:
        print(f"❌ Tidak ada folder di: {AUDIO_FOLDER}")
        print(f"   Buat subfolder di dalam 'audio/', taruh file audio, lalu run lagi.")
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
    print(f"\n📁 Mode: SINGLE FOLDER")
    print(f"📂 Source folder: {selected_folder.name}")
    print(f"🌐 Language: {lang_display}")
    if do_translate:
        print(f"🔤 Translate to: {target_lang}")
    print(f"📂 Output folder: {batch_folder}")
    print(f"📋 Files to process: {len(audio_files)}")
    for i, f in enumerate(audio_files, 1):
        size_mb = f.stat().st_size / (1024 * 1024)
        print(f"   [{i}] {f.name} ({size_mb:.1f} MB)")
    print("=" * 50 + "\n")

    generated_files = []

    for i, audio_file in enumerate(audio_files, 1):
        print(f"\n[{i}/{len(audio_files)}] Processing...")
        print("-" * 40)

        _, out_path = process_file(model, audio_file, batch_folder, language, do_translate, target_lang)
        generated_files.append(out_path)

    print("\n" + "=" * 50)
    print("✅ Folder processing complete!")
    print(f"   Folder: {selected_folder.name}")
    print(f"   Processed: {len(audio_files)} files")
    print(f"   Output: {batch_folder}")
    print("=" * 50)
    return generated_files


def mode_folder_multiple(model, language: str, do_translate: bool = False, target_lang: str = 'id'):
    """
    process mode multiple folders - pilih beberapa folder dengan tekan 0 untuk selesai
    output mengikuti struktur folder sumber (preserve structure)
    """
    # ambil SEMUA folder di semua level
    all_folders = get_all_subfolders_recursive(AUDIO_FOLDER)

    if not all_folders:
        print(f"❌ Tidak ada folder di: {AUDIO_FOLDER}")
        print(f"   Buat subfolder di dalam 'audio/', taruh file audio, lalu run lagi.")
        return

    selected_indices = set()  # set untuk menyimpan index folder yang dipilih (0-based)

    lang_display = SUPPORTED_LANGS.get(language, "Auto")

    print(f"\n📁 Mode: MULTIPLE FOLDERS (Preserve Structure)")
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
        root_folder = get_relative_path_from_audio(selected_folders[0]).split('/')[0]
        print(f"📁 Output: convert txt/multiple/{root_folder}/...")
    else:
        print("📁 Output: convert txt/multiple/")

    print("=" * 70)

    # konfirmasi
    confirm = input("\nLanjutkan proses? (Enter = Ya, 'n' = Batal): ").strip().lower()
    if confirm == 'n':
        print("❌ Proses dibatalkan")
        return

    # proses semua file
    generated_files = []
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

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
            timestamp=timestamp
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
                f.write(f"Folder kosong - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write(f"Source: {get_relative_path_from_audio(folder)}\n")
            empty_folders_created += 1

    print("\n" + "=" * 70)
    print("✅ Folder processing complete!")
    print(f"   Folder diproses: {len(selected_folders)}")
    print(f"   File diproses: {len(all_audio_files)}")
    print(f"   Folder kosong dibuat: {empty_folders_created}")
    print(f"   Output: convert txt/multiple/")
    print("=" * 70)

    return generated_files


def mode_folder(model, language: str, do_translate: bool = False, target_lang: str = 'id'):
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

    # validate mode
    if mode not in ("single", "multiple"):
        print(f"❌ Mode tidak valid: {mode}")
        print("   Gunakan: single atau multiple")
        sys.exit(1)

    # validate language
    if language not in SUPPORTED_LANGS:
        print(f"❌ Language tidak valid: {language}")
        print("   Gunakan: id, en, ja, atau auto")
        sys.exit(1)

    # check for translation arguments
    do_translate = False
    target_lang = 'id'

    if len(sys.argv) >= 5:
        if sys.argv[3].lower() == 'tr':
            do_translate = True
            target_lang = sys.argv[4].lower()
            # load glossary only if translating
            load_glossary()

    # load model
    model = load_model()

    # ask user: folder or file selection?
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
        print("\n" + "-"*50)
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
