"""
Master Menu - Audio Convert to TXT
Supports: Folder mode, Single file, Multiple files, File Explorer, Exclude mode

Features (updated from LOCALCTOLOCALD/main.py):
- File selection via File Explorer dialog
- File exclusion mode (skip specific files)
- Range selection (2-6) and multiple selection (1,3,5)
- "Process all files" option with confirmation
- Consistent numbering (indexed paths)
- Navigate back to main folder
"""

import os
import sys
import subprocess
import tkinter as tk
from tkinter import filedialog
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from config import BASE_DIR, AUDIO_EXTENSIONS, VIDEO_EXTENSIONS, MEDIA_EXTENSIONS, LANGUAGE_MENU

# Use centralized language choices
LANGUAGE_CHOICES = LANGUAGE_MENU

# ============================================================
# HELPER FUNCTIONS (from LOCALCTOLOCALD/main.py)
# ============================================================

def parse_selection(text: str, max_number: int) -> list[int]:
    """
    Parse selection string like "1,3,5" or "2-6" or "all"
    Returns list of 1-based numbers
    """
    cleaned = text.strip().lower()
    if cleaned in {"all"}:
        return list(range(1, max_number + 1))

    result: set[int] = set()
    for chunk in cleaned.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "-" in chunk:
            left, right = chunk.split("-", 1)
            start = int(left)
            end = int(right)
            if start > end:
                start, end = end, start
            for value in range(start, end + 1):
                if not 1 <= value <= max_number:
                    raise ValueError("Nomor di luar daftar.")
                result.add(value)
        else:
            value = int(chunk)
            if not 1 <= value <= max_number:
                raise ValueError("Nomor di luar daftar.")
            result.add(value)
    return sorted(result)


def ask_yes_no(prompt: str, default: bool = True) -> bool:
    """Ask yes/no question with default"""
    suffix = " [Y/n]: " if default else " [y/N]: "
    raw = input(prompt + suffix).strip().lower()
    if not raw:
        return default
    return raw in {"y", "yes", "ya"}


def handle_file_explorer() -> list[Path]:
    """
    Open Windows File Explorer dialog to select files directly.
    Returns list of selected file paths.
    """
    try:
        root = tk.Tk()
        root.withdraw()  # Hide main window
        root.attributes('-topmost', True)  # Bring to front

        # File type filters
        filetypes = [
            ("Audio files", "*.mp3 *.wav *.m4a *.flac *.ogg *.wma *.aac"),
            ("Video files", "*.mp4 *.mov *.mkv *.avi *.webm *.mpeg *.mpg *.m4v"),
            ("All media", "*.mp3 *.wav *.m4a *.flac *.ogg *.wma *.aac *.mp4 *.mov *.mkv *.avi *.webm *.mpeg *.mpg *.m4v"),
            ("All files", "*.*"),
        ]

        files = filedialog.askopenfilenames(
            title="Pilih File Audio/Video",
            filetypes=filetypes,
            initialdir=str(BASE_DIR)
        )

        root.destroy()

        return [Path(f) for f in files]

    except tk.TclError as e:
        print(f"⚠️  File Explorer tidak tersedia: {e}")
        return []


def handle_folder_dialog() -> Path | None:
    """Open folder selection dialog. Returns folder path or None."""
    try:
        root = tk.Tk()
        root.withdraw()
        root.attributes('-topmost', True)

        folder = filedialog.askdirectory(
            title="Pilih Folder Audio/Video",
            initialdir=str(BASE_DIR),
        )

        root.destroy()

        if not folder:
            return None  # User cancelled

        return Path(folder)

    except tk.TclError as e:
        print(f"⚠️  File Explorer tidak tersedia: {e}")
        return None


def handle_folder_input() -> list[Path]:
    """Ask user to input folder path manually. Returns files in that folder."""
    print("\n" + "=" * 72)
    print("📂 INPUT PATH FOLDER MANUAL")
    print("=" * 72)
    print("💡 Tips: Copy path dari Windows Explorer (Shift + Right Click > Copy as path)")

    folder_path = input("Masukkan path folder: ").strip()
    folder_path = folder_path.strip('"').strip("'")  # Remove quotes

    custom_dir = Path(folder_path)

    if not custom_dir.exists():
        print("❌ Folder tidak ditemukan!")
        return []

    if not custom_dir.is_dir():
        print("❌ Path bukan folder!")
        return []

    # Find media files (recursive scan)
    found_files = []
    for item in custom_dir.rglob('*'):
        if item.is_file() and item.suffix.lower() in MEDIA_EXTENSIONS:
            found_files.append(item)

    found_files.sort(key=lambda p: p.name.lower())

    if not found_files:
        print("❌ Tidak ada file audio/video ditemukan di folder tersebut.")
        return []

    print(f"\n✅ Ditemukan {len(found_files)} media files di {custom_dir}")
    return found_files


def handle_exclude_mode(indexed_paths: list[tuple[int, Path]]) -> list[tuple[int, Path]]:
    """
    Exclude mode - filter files that should be SKIPPED.
    User inputs numbers of files to EXCLUDE.
    Returns filtered list with original indices preserved.
    """
    print("\n" + "=" * 72)
    print("🚫 MODE PENGECUALIAN - Pilih file yang TIDAK ingin diproses")
    print("=" * 72)
    print("Masukkan nomor file yang DI-SKIP:")
    print("  Contoh: 4,5,6 atau 2-5 atau 3")
    exclude_input = input("> ").strip()

    try:
        max_number = max(idx for idx, _ in indexed_paths)
        exclude_numbers = parse_selection(exclude_input, max_number)

        filtered_paths = [
            (orig_idx, path) for orig_idx, path in indexed_paths
            if orig_idx not in exclude_numbers
        ]

        if not filtered_paths:
            print("❌ Semua file di-exclude! Tidak ada file yang tersisa.")
            return indexed_paths

        print(f"\n✅ File yang akan diproses ({len(filtered_paths)} files):")
        for orig_idx, path in filtered_paths:
            media_type = "🎬" if path.suffix.lower() in VIDEO_EXTENSIONS else "🎵"
            print(f"   {orig_idx:>3}. {media_type} {path.name}")

        return filtered_paths

    except ValueError as exc:
        print(f"❌ Input tidak valid: {exc}")
        return indexed_paths


def print_file_list_with_indices(indexed_paths: list[tuple[int, Path]], folder_label: str = "") -> None:
    """Print file list with consistent numbering"""
    if folder_label:
        print(f"\n📂 Folder: {folder_label}")

    print("\n" + "-" * 72)
    for orig_idx, path in indexed_paths:
        media_type = "🎬" if path.suffix.lower() in VIDEO_EXTENSIONS else "🎵"
        size_mb = path.stat().st_size / (1024 * 1024)
        print(f"  [{orig_idx:>3}] {media_type} {path.name} ({size_mb:.1f} MB)")
    print("-" * 72)


def print_menu_options(has_folder_context: bool = False) -> None:
    """Print additional menu options for file selection"""
    print("\n  a. 📂 Input path folder lain (ketik manual)")
    print("  b. 🔍 Pilih folder via File Explorer")
    print("  c. 📄 Pilih file langsung via File Explorer (skip list)")
    print("  d. 🚫 Pengecualian file (skip file tertentu)")
    print("  e. ✅ Proses semua file")
    if has_folder_context:
        print("  f. 🔙 Kembali ke folder utama")
    print("  0. ❌ Kembali")


def select_files_with_menu(
    paths: list[Path],
    allow_many: bool = True,
    folder_label: str = "",
    main_folder_paths: list[Path] | None = None,
) -> list[Path]:
    """
    Advanced file selection menu with options a-f.
    Supports: folder input, file explorer, exclude mode, process all, return to main.

    Args:
        paths: Initial file list
        allow_many: If True, allow multiple selection. If False, single file only.
        folder_label: Label to display (folder path or name)
        main_folder_paths: Original paths for "return to main" option

    Returns:
        List of selected Path objects
    """
    if not paths:
        print("❌ Tidak ada file ditemukan.")
        return []

    # Create indexed paths: (original_index, path) for consistent numbering
    indexed_paths: list[tuple[int, Path]] = [(i + 1, p) for i, p in enumerate(paths)]

    # Store original folder context for "return to main"
    original_folder_path = folder_label
    original_indexed_paths = indexed_paths[:]

    while True:
        has_folder_context = (original_folder_path != folder_label) or (main_folder_paths is not None)

        # Display file list
        print_file_list_with_indices(indexed_paths, folder_label)

        # Display menu options
        print_menu_options(has_folder_context=has_folder_context)

        # Build prompt
        if allow_many:
            prompt = "\nPilih nomor file (contoh: 1 atau 1,3,5 atau 2-6 atau all): "
        else:
            prompt = "\nPilih nomor file (tepat 1): "

        raw = input(prompt).strip().lower()

        # ---- Option A: Input path folder lain ----
        if raw == "a":
            custom_files = handle_folder_input()
            if custom_files:
                original_folder_path = str(custom_files[0].parent)
                folder_label = original_folder_path
                indexed_paths = [(i + 1, p) for i, p in enumerate(custom_files)]
                main_folder_paths = None  # Can't return to main from here
                continue
            else:
                print("❌ Folder tidak valid atau tidak ada file yang cocok.")
                continue

        # ---- Option B: Pilih folder via File Explorer ----
        elif raw == "b":
            selected_folder = handle_folder_dialog()
            if selected_folder is None:
                continue  # User cancelled, show list again

            # Scan folder for media files
            folder_files = []
            for item in selected_folder.rglob('*'):
                if item.is_file() and item.suffix.lower() in MEDIA_EXTENSIONS:
                    folder_files.append(item)
            folder_files.sort(key=lambda p: p.name.lower())

            if folder_files:
                original_folder_path = str(selected_folder)
                folder_label = original_folder_path
                indexed_paths = [(i + 1, p) for i, p in enumerate(folder_files)]
                main_folder_paths = None
                print(f"\n✅ Ditemukan {len(folder_files)} files di {selected_folder.name}")
                continue
            else:
                print("❌ Tidak ada file audio/video di folder tersebut.")
                continue

        # ---- Option C: Pilih file langsung via File Explorer ----
        elif raw == "c":
            explorer_files = handle_file_explorer()
            if explorer_files:
                return explorer_files  # Direct return, no list display
            else:
                print("❌ Tidak ada file yang dipilih.")
                continue

        # ---- Option D: Pengecualian file ----
        elif raw == "d":
            indexed_paths = handle_exclude_mode(indexed_paths)
            continue

        # ---- Option E: Proses semua file ----
        elif raw == "e":
            if ask_yes_no(f"Proses semua file ({len(indexed_paths)} files)?", default=True):
                return [path for _, path in indexed_paths]
            else:
                continue

        # ---- Option F: Kembali ke folder utama ----
        elif raw == "f" and has_folder_context and main_folder_paths is not None:
            indexed_paths = [(i + 1, p) for i, p in enumerate(main_folder_paths)]
            folder_label = original_folder_path
            print("\n🔙 Kembali ke folder utama")
            continue

        # ---- Option 0: Kembali ----
        elif raw == "0":
            return []

        # ---- Number selection ----
        try:
            max_number = max(idx for idx, _ in indexed_paths)
            picked_numbers = parse_selection(raw, max_number)

            if not allow_many and len(picked_numbers) != 1:
                print("❌ Pilih tepat satu file.")
                continue

            result = []
            for number in picked_numbers:
                for orig_idx, path in indexed_paths:
                    if orig_idx == number:
                        result.append(path)
                        break

            if not result:
                print("❌ File tidak ditemukan.")
                continue

            return result

        except ValueError as exc:
            print(f"❌ Input tidak valid: {exc}")


# ============================================================
# MAIN MENU FUNCTIONS
# ============================================================

def display_language_selection() -> str | None:
    """
    Display language selection menu and return selected language code.
    """
    print("\nPilih Bahasa Audio Asli:")
    for key, lang in LANGUAGE_CHOICES.items():
        print(f"  [{key}] {lang['code']} ({lang['name']})")

    lang_choice = input("Pilih (1/2/3/4): ").strip()

    if lang_choice not in LANGUAGE_CHOICES:
        print("❌ Pilihan tidak valid")
        return None

    return LANGUAGE_CHOICES[lang_choice]["code"]


def get_media_files_from_folder(folder_path: Path, recursive: bool = False) -> list:
    """
    Get all media files (audio + video) from folder
    """
    if not folder_path.exists():
        return []

    media_files = []
    scanner = folder_path.rglob if recursive else folder_path.glob
    for f in scanner("*"):
        if f.is_file() and f.suffix.lower() in MEDIA_EXTENSIONS:
            media_files.append(f)

    return sorted(media_files)


def select_language_and_process(mode, selected_folder=None, media_files=None, selected_file=None, selected_files=None):
    """
    Unified language selection + process
    """
    language = display_language_selection()

    if language is None:
        return

    script_path = BASE_DIR / "src" / "transcribe.py"

    if mode == "custom_folder":
        try:
            subprocess.run([
                sys.executable, str(script_path),
                "custom_folder",
                language,
                str(selected_folder),
                ",".join([str(f) for f in media_files])
            ], timeout=86400)  # 24 hour max timeout
        except subprocess.TimeoutExpired:
            print("❌ Transcription timed out (>24 hours)")
        except Exception as e:
            print(f"❌ Error running transcription: {e}")

    elif mode == "folder":
        try:
            subprocess.run([sys.executable, str(script_path), "folder", language], timeout=86400)
        except subprocess.TimeoutExpired:
            print("❌ Transcription timed out (>24 hours)")
    elif mode == "single":
        try:
            # Pass single file path if provided
            if selected_file:
                subprocess.run([
                    sys.executable, str(script_path),
                    "single", language, str(selected_file)
                ], timeout=86400)
            else:
                subprocess.run([sys.executable, str(script_path), "single", language], timeout=86400)
        except subprocess.TimeoutExpired:
            print("❌ Transcription timed out (>24 hours)")
    elif mode == "multiple":
        try:
            # Pass selected files list if provided (from File Explorer)
            if selected_files:
                subprocess.run([
                    sys.executable, str(script_path),
                    "multiple", language,
                    ",".join([str(f) for f in selected_files])
                ], timeout=86400)
            else:
                subprocess.run([sys.executable, str(script_path), "multiple", language], timeout=86400)
        except subprocess.TimeoutExpired:
            print("❌ Transcription timed out (>24 hours)")


def menu_transcribe_folder():
    """
    FOLDER MODE dengan 4 CARA INPUT
    [1] Pilih dari list folder dalam audio/
    [2] Pilih folder via File Explorer
    [3] Pilih file langsung via File Explorer (skip folder)
    [4] Input path folder manual (copy-paste)
    """
    print("\n" + "=" * 60)
    print("📂 FOLDER MODE - Pilih Folder")
    print("=" * 60)
    print("\n  [1] 📁 Pilih dari list folder dalam audio/")
    print("  [2] 📂 Pilih folder via File Explorer")
    print("  [3] 📄 Pilih file langsung via File Explorer (skip folder)")
    print("  [4] 📂 Input path folder manual (copy-paste)")
    print("\n  [0] Kembali")
    print("=" * 60)

    choice = input("Pilihan Anda: ").strip()
    selected_folder = None
    selected_files_explorer = None

    if choice == "0":
        return

    # ---- Option 1: Pilih dari list dalam audio/ ----
    elif choice == "1":
        audio_folder = BASE_DIR / "audio"
        if not audio_folder.exists():
            print("❌ Folder audio/ tidak ditemukan")
            return

        folders = [f for f in audio_folder.rglob("*") if f.is_dir()]
        if not folders:
            print("❌ Tidak ada folder dalam audio/")
            return

        print("\n📂 Folder dalam audio/:")
        print("-" * 60)
        for i, f in enumerate(folders, 1):
            media_count = len(get_media_files_from_folder(f, recursive=True))
            rel_path = f.relative_to(audio_folder)
            print(f"  [{i}] {rel_path} ({media_count} media files)")
        print("-" * 60)

        folder_num = input("Pilih nomor folder: ").strip()
        try:
            selected_folder = folders[int(folder_num) - 1]
        except (IndexError, ValueError):
            print("❌ Pilihan tidak valid")
            return

    # ---- Option 2: Pilih folder via File Explorer ----
    elif choice == "2":
        print("\n📂 Membuka File Explorer - pilih folder...")
        selected_folder = handle_folder_dialog()
        if not selected_folder:
            print("❌ Folder tidak dipilih")
            return

    # ---- Option 3: Pilih file langsung via File Explorer (skip folder) ----
    elif choice == "3":
        print("\n📄 Membuka File Explorer - pilih file audio/video...")
        selected_files_explorer = handle_file_explorer()

        if not selected_files_explorer:
            print("❌ Tidak ada file yang dipilih")
            return

        print(f"\n✅ {len(selected_files_explorer)} file(s) dipilih:")
        for f in selected_files_explorer:
            media_type = "🎬" if f.suffix.lower() in VIDEO_EXTENSIONS else "🎵"
            print(f"   {media_type} {f.name}")

        # Langsung ke language selection (skip folder scan)
        select_language_and_process(
            mode="multiple",
            selected_files=selected_files_explorer
        )
        return  # Langsung return, tidak lanjut ke bawah

    # ---- Option 4: Input path manual ----
    elif choice == "4":
        print("\n💡 Tips: Copy path dari Windows Explorer (Shift + Right Click > Copy as path)")
        custom_path = input("\nMasukkan path folder: ").strip()
        custom_path = custom_path.strip('"').strip("'")
        selected_folder = Path(custom_path)

        if not selected_folder.exists():
            print(f"❌ Folder tidak ditemukan: {custom_path}")
            return
        if not selected_folder.is_dir():
            print(f"❌ Path bukan folder: {custom_path}")
            return

    else:
        print("❌ Pilihan tidak valid")
        return

    # Scan folder for media files
    print(f"\n🔍 Scanning folder (including subfolders): {selected_folder}...")
    media_files = get_media_files_from_folder(selected_folder, recursive=True)

    if not media_files:
        print("❌ Tidak ada file audio/video di folder ini")
        return

    # Count by type
    audio_count = sum(1 for f in media_files if f.suffix.lower() in AUDIO_EXTENSIONS)
    video_count = sum(1 for f in media_files if f.suffix.lower() in VIDEO_EXTENSIONS)

    print(f"\n✅ Folder ditemukan: {selected_folder.name}")
    print(f"📊 Total media files: {len(media_files)}")
    print(f"   🎵 Audio: {audio_count} files")
    print(f"   🎬 Video: {video_count} files")

    if video_count > 0:
        print("\n⚠️  Video files akan di-convert ke MP3 dulu sebelum transkripsi")

    # Advanced file selection with options a-f
    print("\n📋 Pilih file yang akan diproses:")
    selected_files = select_files_with_menu(
        paths=media_files,
        allow_many=True,
        folder_label=selected_folder.name,
        main_folder_paths=media_files,
    )

    if not selected_files:
        print("❌ Dibatalkan")
        return

    print(f"\n✅ {len(selected_files)} file(s) dipilih:")
    for f in selected_files:
        media_type = "🎬" if f.suffix.lower() in VIDEO_EXTENSIONS else "🎵"
        print(f"   {media_type} {f.name}")

    # Process with language selection
    select_language_and_process(
        mode="custom_folder",
        selected_folder=selected_folder,
        media_files=selected_files
    )


def menu_transcribe_single():
    """
    SINGLE FILE: Pilih 1 file dengan advanced selection menu
    """
    print("\n" + "=" * 60)
    print("📄 SINGLE FILE - Pilih 1 File")
    print("=" * 60)

    audio_folder = BASE_DIR / "audio"
    if not audio_folder.exists():
        print("❌ Folder audio/ tidak ditemukan")
        return

    files = [f for f in audio_folder.iterdir()
             if f.is_file() and f.suffix.lower() in MEDIA_EXTENSIONS]

    if not files:
        print("❌ Tidak ada file audio/video di audio/")
        return

    # Advanced file selection (single mode)
    print("\n📋 Pilih 1 file:")
    selected_files = select_files_with_menu(
        paths=files,
        allow_many=False,
        folder_label="audio/",
        main_folder_paths=files,
    )

    if not selected_files:
        print("❌ Dibatalkan")
        return

    selected_file = selected_files[0]
    print(f"\n✅ File: {selected_file.name}")

    select_language_and_process(
        mode="single",
        selected_file=selected_file
    )


def menu_transcribe_multiple():
    """
    MULTIPLE FILES: Pilih beberapa file dengan advanced selection
    """
    print("\n" + "=" * 60)
    print("📄 MULTIPLE FILES - Pilih Beberapa File")
    print("=" * 60)

    audio_folder = BASE_DIR / "audio"
    if not audio_folder.exists():
        print("❌ Folder audio/ tidak ditemukan")
        return

    files = [f for f in audio_folder.iterdir()
             if f.is_file() and f.suffix.lower() in MEDIA_EXTENSIONS]

    if not files:
        print("❌ Tidak ada file audio/video di audio/")
        return

    # Advanced file selection (multiple mode)
    print("\n📋 Pilih file:")
    selected_files = select_files_with_menu(
        paths=files,
        allow_many=True,
        folder_label="audio/",
        main_folder_paths=files,
    )

    if not selected_files:
        print("❌ Dibatalkan")
        return

    print(f"\n✅ Files selected: {len(selected_files)} files")
    for f in selected_files:
        media_type = "🎬" if f.suffix.lower() in VIDEO_EXTENSIONS else "🎵"
        print(f"   {media_type} {f.name}")

    select_language_and_process(
        mode="multiple",
        selected_files=selected_files
    )


def menu_summary():
    print("\n" + "-" * 40)
    print("📝 GENERATE SUMMARY TEXT")
    print("-" * 40)
    print("Pilih Mode:")
    print("  [1] Single (1 file)")
    print("  [2] Multiple (banyak file)")
    mode_choice = input("Pilih (1/2): ").strip()

    mode_map = {"1": "single", "2": "multiple"}
    if mode_choice not in mode_map:
        print("❌ Pilihan tidak valid. Kembali ke menu utama.")
        return
    mode = mode_map[mode_choice]

    script_path = BASE_DIR / "src" / "summarytext.py"
    subprocess.run([sys.executable, str(script_path), mode])


def menu_pdf():
    print("\n" + "-" * 40)
    print("📄 output TO PDF")
    print("-" * 40)
    print("Pilih Mode:")
    print("  [1] Single (1 file)")
    print("  [2] Multiple (banyak file)")
    mode_choice = input("Pilih (1/2): ").strip()

    mode_map = {"1": "single", "2": "multiple"}
    if mode_choice not in mode_map:
        print("❌ Pilihan tidak valid. Kembali ke menu utama.")
        return
    mode = mode_map[mode_choice]

    script_path = BASE_DIR / "src" / "convert_pdf.py"
    subprocess.run([sys.executable, str(script_path), mode])


def menu_check_setup():
    """
    HEALTH CHECK: Memeriksa library, GPU, model, dan folder.
    """
    print("\n" + "=" * 60)
    print("🔍 PENGECEKAN KESEHATAN SISTEM")
    print("=" * 60)

    # 1. Cek Python & Venv
    print(f"🐍 Python Version: {sys.version.split()[0]}")
    print(f"🏠 Project Root: {BASE_DIR}")

    # 2. Cek Libraries
    print("\n📦 Memeriksa Library...")
    libs = {
        "faster_whisper": "faster-whisper",
        "deep_translator": "deep-translator",
        "dotenv": "python-dotenv",
        "torch": "torch",
        "ctranslate2": "ctranslate2"
    }

    import importlib
    all_libs_ok = True
    for mod_name, pkg_name in libs.items():
        try:
            importlib.import_module(mod_name)
            print(f"   ✅ {pkg_name} terinstal.")
        except ImportError:
            print(f"   ❌ {pkg_name} TIDAK DITEMUKAN!")
            all_libs_ok = False

    # 3. Cek GPU / CUDA
    print("\n🚀 Memeriksa GPU (CUDA)...")
    try:
        import torch
        if torch.cuda.is_available():
            print("   ✅ CUDA tersedia!")
            print(f"   📟 GPU: {torch.cuda.get_device_name(0)}")
            vram = torch.cuda.get_device_properties(0).total_memory / (1024**3)
            print(f"   💾 VRAM: {vram:.1f} GB")
        else:
            print("   ⚠️  CUDA tidak terdeteksi. Program akan berjalan di CPU (lambat).")
    except Exception as e:
        print(f"   ❌ Gagal mengecek GPU: {e}")

    # 4. Cek Model Whisper
    print("\n🧠 Memeriksa Model Whisper...")
    # Ambil path dari .env jika ada
    model_path = os.environ.get("WHISPER_MODEL_PATH", "D:\\model\\large-v3")
    if Path(model_path).exists():
        print(f"   ✅ Model ditemukan di: {model_path}")
    else:
        print(f"   ⚠️  Model TIDAK ditemukan di: {model_path}")
        print("      Program akan mendownload otomatis saat pertama kali dijalankan.")

    # 5. Cek Folder Dasar
    print("\n📂 Memeriksa Folder Proyek...")
    folders = ["audio", "output", "assets", "src"]
    for f in folders:
        p = BASE_DIR / f
        if p.exists():
            print(f"   ✅ Folder '{f}' tersedia.")
        else:
            print(f"   ⚠️  Folder '{f}' hilang. Membuat folder...")
            p.mkdir(parents=True, exist_ok=True)

    print("\n" + "=" * 60)
    if all_libs_ok:
        print("✅ SETUP SELESAI: Sistem siap digunakan!")
    else:
        print("❌ SETUP BERMASALAH: Harap instal library yang kurang.")
    print("=" * 60)
    input("\nTekan Enter untuk kembali ke menu...")


def main():
    while True:
        print("\n\n" + "=" * 60)
        print("        AUDIO CONVERT TO TXT - MASTER MENU        ")
        print("=" * 60)
        print("\n📁 CARA MEMILIH AUDIO:\n")

        print("  [1] 📂 FOLDER MODE")
        print("      → 4 cara pilih: list audio/, file explorer, input path, browse")
        print("      → Setelah pilih folder, bisa exclude file & proses semua")
        print("      → Support: audio + video files\n")

        print("  [2] 📄 FILE MODE - SINGLE")
        print("      → Pilih 1 file dari folder audio/")
        print("      → Output: flat di output/single/\n")

        print("  [3] 📄 FILE MODE - MULTIPLE")
        print("      → Pilih beberapa file dari folder audio/")
        print("      → Output: batch folder\n")

        print("  [4] 📝 Generate Summary Text")
        print("  [5] 📄 output to PDF")
        print("  [6] 🔍 Cek Setup & Kesehatan Sistem")
        print("\n  [0] Keluar")
        print("=" * 60)

        choice = input("Pilihan Anda: ").strip()

        if choice == "1":
            menu_transcribe_folder()
        elif choice == "2":
            menu_transcribe_single()
        elif choice == "3":
            menu_transcribe_multiple()
        elif choice == "4":
            menu_summary()
        elif choice == "5":
            menu_pdf()
        elif choice == "6":
            menu_check_setup()
        elif choice == "0":
            print("\n👋 Keluar dari program. Terima kasih!\n")
            break
        else:
            print("\n❌ Pilihan tidak valid. Silakan coba lagi.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n👋 Keluar dari program. Terima kasih!\n")
        sys.exit(0)
