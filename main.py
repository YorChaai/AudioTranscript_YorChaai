import os
import sys
import subprocess
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

BASE_DIR = Path(__file__).parent

# Supported media extensions
AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".flac", ".ogg", ".wma", ".aac"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".mpeg", ".mpg", ".m4v"}
MEDIA_EXTENSIONS = AUDIO_EXTENSIONS | VIDEO_EXTENSIONS


def get_media_files_from_folder(folder_path: Path) -> list:
    """
    Get all media files (audio + video) from folder recursively
    """
    if not folder_path.exists():
        return []

    media_files = []
    for f in folder_path.rglob("*"):
        if f.is_file() and f.suffix.lower() in MEDIA_EXTENSIONS:
            media_files.append(f)

    return sorted(media_files)


def menu_transcribe_folder():
    """
    FOLDER MODE dengan CUSTOM PATH INPUT
    - Pilih dari list
    - Input path manual (copy-paste)
    - Browse folder lain
    """
    print("\n" + "="*60)
    print("📂 FOLDER MODE - Pilih Folder")
    print("="*60)
    print("\n  [1] 📁 Pilih dari list folder dalam audio/")
    print("  [2] 📂 Input path folder manual (copy-paste)")
    print("  [3] 🔍 Browse folder lain di komputer")
    print("\n  [0] Kembali")
    print("="*60)

    choice = input("Pilihan Anda: ").strip()

    selected_folder = None

    if choice == "0":
        return
    elif choice == "1":
        # Pilih dari list dalam audio/
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
            media_count = len(get_media_files_from_folder(f))
            rel_path = f.relative_to(audio_folder)
            print(f"  [{i}] {rel_path} ({media_count} media files)")
        print("-" * 60)

        folder_num = input("Pilih nomor folder: ").strip()
        try:
            selected_folder = folders[int(folder_num) - 1]
        except (IndexError, ValueError):
            print("❌ Pilihan tidak valid")
            return

    elif choice == "2":
        # Input path manual
        print("\n💡 Tips: Copy path dari Windows Explorer (Shift + Right Click > Copy as path)")
        custom_path = input("\nMasukkan path folder: ").strip()

        # Remove quotes if present
        custom_path = custom_path.strip('"').strip("'")

        selected_folder = Path(custom_path)

        if not selected_folder.exists():
            print(f"❌ Folder tidak ditemukan: {custom_path}")
            return

        if not selected_folder.is_dir():
            print(f"❌ Path bukan folder: {custom_path}")
            return

    elif choice == "3":
        # Browse folder (gunakan dialog Windows)
        print("\n🔍 Membuka file browser...")
        try:
            import tkinter as tk
            from tkinter import filedialog

            root = tk.Tk()
            root.withdraw()  # Hide main window
            root.attributes('-topmost', True)  # Bring to front

            selected_folder = Path(filedialog.askdirectory(
                title="Pilih Folder Audio/Video",
                initialdir=str(BASE_DIR)
            ))

            root.destroy()

            if not selected_folder or not selected_folder.exists():
                print("❌ Folder tidak dipilih")
                return

        except Exception as e:
            print(f"❌ Error membuka browser: {e}")
            print("   Gunakan opsi [2] untuk input path manual")
            return

    else:
        print("❌ Pilihan tidak valid")
        return

    # Validate folder has media files
    print(f"\n🔍 Scanning folder: {selected_folder}...")
    media_files = get_media_files_from_folder(selected_folder)

    if not media_files:
        print(f"❌ Tidak ada file audio/video di folder ini")
        return

    # Count by type
    audio_count = sum(1 for f in media_files if f.suffix.lower() in AUDIO_EXTENSIONS)
    video_count = sum(1 for f in media_files if f.suffix.lower() in VIDEO_EXTENSIONS)

    print(f"\n✅ Folder ditemukan: {selected_folder.name}")
    print(f"📊 Total media files: {len(media_files)}")
    print(f"   🎵 Audio: {audio_count} files")
    print(f"   🎬 Video: {video_count} files")

    if video_count > 0:
        print(f"\n⚠️  Video files akan di-convert ke MP3 dulu sebelum transkripsi")

    print(f"\n🔄 Memproses SEMUA {len(media_files)} files otomatis...\n")

    # Lanjut ke language selection
    select_language_and_process(
        mode="custom_folder",
        selected_folder=selected_folder,
        media_files=media_files
    )


def select_language_and_process(mode, selected_folder=None, media_files=None, selected_file=None):
    """
    Unified language selection + process
    """
    print("\nPilih Bahasa Audio Asli:")
    print("  [1] id (Indonesian)")
    print("  [2] en (English)")
    print("  [3] ja (Japanese)")
    print("  [4] auto (Auto-detect / Campuran)")

    lang_choice = input("Pilih (1/2/3/4): ").strip()
    lang_map = {"1": "id", "2": "en", "3": "ja", "4": "auto"}

    if lang_choice not in lang_map:
        print("❌ Pilihan tidak valid")
        return

    language = lang_map[lang_choice]

    # Call transcribe.py dengan parameter yang tepat
    script_path = BASE_DIR / "transcribe.py"

    if mode == "custom_folder":
        # Pass folder path dan file list
        subprocess.run([
            sys.executable, str(script_path),
            "custom_folder",
            language,
            str(selected_folder),
            ",".join([str(f) for f in media_files])
        ])
    elif mode == "folder":
        subprocess.run([sys.executable, str(script_path), "folder", language])
    elif mode == "single":
        subprocess.run([sys.executable, str(script_path), "single", language])
    elif mode == "multiple":
        subprocess.run([sys.executable, str(script_path), "multiple", language])


def menu_transcribe_single():
    """
    SINGLE FILE: Pilih 1 file dari list
    """
    print("\n" + "="*60)
    print("📄 SINGLE FILE - Pilih 1 File")
    print("="*60)

    audio_folder = BASE_DIR / "audio"
    if not audio_folder.exists():
        print("❌ Folder audio/ tidak ditemukan")
        return

    files = [f for f in audio_folder.iterdir()
             if f.is_file() and f.suffix.lower() in MEDIA_EXTENSIONS]

    if not files:
        print("❌ Tidak ada file audio/video di audio/")
        return

    print("\n📂 Files dalam audio/:")
    print("-" * 60)
    for i, f in enumerate(files, 1):
        size_mb = f.stat().st_size / (1024 * 1024)
        media_type = "🎬" if f.suffix.lower() in VIDEO_EXTENSIONS else "🎵"
        print(f"  [{i}] {media_type} {f.name} ({size_mb:.1f} MB)")
    print("-" * 60)

    file_num = input("Pilih 1 file: ").strip()

    try:
        selected_file = files[int(file_num) - 1]
        print(f"\n✅ File: {selected_file.name}")

        select_language_and_process(
            mode="single",
            selected_file=selected_file
        )
    except (IndexError, ValueError):
        print("❌ Pilihan tidak valid")


def menu_transcribe_multiple():
    """
    MULTIPLE FILES: Pilih beberapa file dari list
    """
    print("\n" + "="*60)
    print("📄 MULTIPLE FILES - Pilih Beberapa File")
    print("="*60)

    audio_folder = BASE_DIR / "audio"
    if not audio_folder.exists():
        print("❌ Folder audio/ tidak ditemukan")
        return

    files = [f for f in audio_folder.iterdir()
             if f.is_file() and f.suffix.lower() in MEDIA_EXTENSIONS]

    if not files:
        print("❌ Tidak ada file audio/video di audio/")
        return

    print("\n📂 Files dalam audio/:")
    print("-" * 60)
    for i, f in enumerate(files, 1):
        size_mb = f.stat().st_size / (1024 * 1024)
        media_type = "🎬" if f.suffix.lower() in VIDEO_EXTENSIONS else "🎵"
        print(f"  [{i}] {media_type} {f.name} ({size_mb:.1f} MB)")
    print("-" * 60)

    choices = input("Pilih nomor (pisah koma, contoh: 1,3,5): ").strip()

    numbers = []
    for part in choices.replace(" ", "").split(","):
        try:
            num = int(part)
            if 1 <= num <= len(files):
                numbers.append(num)
        except ValueError:
            pass

    if not numbers:
        print("❌ Tidak ada nomor valid")
        return

    selected_files = [files[n - 1] for n in sorted(set(numbers))]

    print(f"\n✅ Files selected: {len(selected_files)} files")
    for f in selected_files:
        print(f"   - {f.name}")

    select_language_and_process(
        mode="multiple",
        selected_files=selected_files
    )


def menu_transcribe():
    """Old menu - kept for backward compatibility"""
    print("\n" + "-"*40)
    print("🎤 TRANSCRIBE AUDIO")
    print("-"*40)
    print("Pilih Mode:")
    print("  [1] Single (1 file)")
    print("  [2] Multiple (banyak file)")
    mode_choice = input("Pilih (1/2): ").strip()

    mode_map = {"1": "single", "2": "multiple"}
    if mode_choice not in mode_map:
        print("❌ Pilihan tidak valid. Kembali ke menu utama.")
        return
    mode = mode_map[mode_choice]

    print("\nPilih Bahasa Audio Asli:")
    print("  [1] id (Indonesian)")
    print("  [2] en (English)")
    print("  [3] ja (Japanese)")
    print("  [4] auto (Auto-detect / Campuran)")
    lang_choice = input("Pilih (1/2/3/4): ").strip()

    lang_map = {"1": "id", "2": "en", "3": "ja", "4": "auto"}
    if lang_choice not in lang_map:
        print("❌ Pilihan tidak valid. Kembali ke menu utama.")
        return
    language = lang_map[lang_choice]

    script_path = BASE_DIR / "transcribe.py"
    subprocess.run([sys.executable, str(script_path), mode, language])


def menu_summary():
    print("\n" + "-"*40)
    print("📝 GENERATE SUMMARY TEXT")
    print("-"*40)
    print("Pilih Mode:")
    print("  [1] Single (1 file)")
    print("  [2] Multiple (banyak file)")
    mode_choice = input("Pilih (1/2): ").strip()

    mode_map = {"1": "single", "2": "multiple"}
    if mode_choice not in mode_map:
        print("❌ Pilihan tidak valid. Kembali ke menu utama.")
        return
    mode = mode_map[mode_choice]

    script_path = BASE_DIR / "summarytext.py"
    # Menjalankan script summarytext.py
    subprocess.run([sys.executable, str(script_path), mode])


def menu_pdf():
    print("\n" + "-"*40)
    print("📄 CONVERT TXT TO PDF")
    print("-"*40)
    print("Pilih Mode:")
    print("  [1] Single (1 file)")
    print("  [2] Multiple (banyak file)")
    mode_choice = input("Pilih (1/2): ").strip()

    mode_map = {"1": "single", "2": "multiple"}
    if mode_choice not in mode_map:
        print("❌ Pilihan tidak valid. Kembali ke menu utama.")
        return
    mode = mode_map[mode_choice]

    script_path = BASE_DIR / "convert_pdf.py"
    # Menjalankan script convert_pdf.py
    subprocess.run([sys.executable, str(script_path), mode])


def main():
    while True:
        print("\n\n" + "="*60)
        print("        AUDIO CONVERT TO TXT - MASTER MENU        ")
        print("="*60)
        print("\n📁 CARA MEMILIH AUDIO:\n")

        print("  [1] 📂 FOLDER MODE")
        print("      → Pilih folder (local/custom path), SEMUA file diproses otomatis")
        print("      → Support: audio + video files")
        print("      → Output: struktur folder terjaga\n")

        print("  [2] 📄 FILE MODE - SINGLE")
        print("      → Pilih 1 file dari folder audio/")
        print("      → Output: flat di convert txt/single/\n")

        print("  [3] 📄 FILE MODE - MULTIPLE")
        print("      → Pilih beberapa file dari folder audio/")
        print("      → Output: batch folder\n")

        print("  [4] 📝 Generate Summary Text")
        print("  [5] 📄 Convert TXT to PDF")
        print("\n  [0] Keluar")
        print("="*60)

        choice = input("Pilihan Anda: ").strip()

        if choice == "1":
            menu_transcribe_folder()      # ← Folder mode dengan custom path
        elif choice == "2":
            menu_transcribe_single()      # ← Single file
        elif choice == "3":
            menu_transcribe_multiple()    # ← Multiple files
        elif choice == "4":
            menu_summary()
        elif choice == "5":
            menu_pdf()
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
