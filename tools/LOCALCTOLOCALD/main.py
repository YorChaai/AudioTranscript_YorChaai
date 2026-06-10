"""
Terminal launcher untuk semua tool Python di project ini.

Fitur:
1. Menampilkan menu tool utama.
2. Mencari file berdasarkan ekstensi (pdf, excel, txt, jpg, png, dan lain-lain).
3. Memilih file dengan nomor, list nomor, atau range.
4. Menjalankan script yang relevan langsung dari terminal.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tkinter as tk
from dataclasses import dataclass
from pathlib import Path
from tkinter import filedialog
from typing import Callable

try:
    import fitz  # PyMuPDF - untuk hitung halaman PDF
except ImportError:
    fitz = None


BASE_DIR = Path(__file__).resolve().parent
PYTHON_EXE = sys.executable
SUPPORTED_FILE_TYPES = {
    "pdf": [".pdf"],
    "excel": [".xlsx", ".xls", ".csv"],
    "text": [".txt", ".md"],
    "image": [".jpg", ".jpeg", ".png", ".bmp", ".webp"],
    "docx": [".docx"],
    "python": [".py"],
    "all": [],
}
SKIP_DIRS = {
    "__pycache__",
    ".git",
    ".venv",
    "venv",
    "ocr_output",
}


@dataclass
class ToolEntry:
    key: str
    name: str
    description: str
    script_name: str
    handler: Callable[["ToolEntry"], None]


def clear_screen() -> None:
    os.system("cls" if os.name == "nt" else "clear")


def pause() -> None:
    input("\nTekan Enter untuk kembali ke menu...")


def print_header(title: str) -> None:
    print("=" * 72)
    print(title)
    print("=" * 72)


def find_files(extensions: list[str] | None = None) -> list[Path]:
    matches: list[Path] = []
    for path in BASE_DIR.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if extensions and path.suffix.lower() not in extensions:
            continue
        matches.append(path)
    matches.sort(key=lambda item: str(item.relative_to(BASE_DIR)).lower())
    return matches


def list_python_scripts() -> list[Path]:
    scripts = []
    for path in find_files([".py"]):
        if path.name == Path(__file__).name:
            continue
        scripts.append(path)
    return scripts


def print_numbered_paths(paths: list[Path]) -> None:
    for index, path in enumerate(paths, start=1):
        try:
            relative = path.relative_to(BASE_DIR)
        except ValueError:
            relative = path
        print(f"{index:>3}. {relative}")


def parse_selection(text: str, max_number: int) -> list[int]:
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


def _print_file_list_with_indices(
    indexed_paths: list[tuple[int, Path]], file_type_label: str, folder_path: str | None = None
) -> None:
    """Print daftar file dengan nomor asli (tidak berubah setelah exclude)."""
    if folder_path:
        print(f"\nfolder : {folder_path}")
    print(f"\nDaftar {file_type_label}:")
    for original_idx, path in indexed_paths:
        try:
            relative = path.relative_to(BASE_DIR)
        except ValueError:
            relative = path
        print(f"{original_idx:>3}. {relative}")


def _print_menu_options(has_folder_context: bool = False) -> None:
    """Print opsi tambahan di menu pemilihan file.

    Jika sudah dalam konteks folder custom, tampilkan opsi kembali ke folder utama.
    """
    print(f"\na. Input path folder lain (ketik manual)")
    print(f"b. Pilih folder via File Explorer")
    print(f"c. Pilih file langsung via File Explorer (skip list)")
    print(f"d. Pengecualian file (skip file tertentu)")
    print(f"e. Proses semua file")
    if has_folder_context:
        print(f"f. Kembali ke folder utama")
    print(f"0. Hentikan program")


def handle_folder_dialog(extensions: list[str], file_type_label: str) -> list[Path] | None:
    """
    Buka dialog pilih folder. Return list file di folder tersebut.
    Return None jika user cancel.
    """
    try:
        root = tk.Tk()
        root.withdraw()

        folder = filedialog.askdirectory(
            title=f"Pilih folder yang berisi {file_type_label}",
            initialdir=str(BASE_DIR),
        )

        root.destroy()

        if not folder:
            return None  # User cancel

        folder_path = Path(folder)
        ext_list = extensions if extensions else []

        # Cari file di folder tersebut (non-recursive)
        found_files: list[Path] = []
        try:
            for item in folder_path.iterdir():
                if not item.is_file():
                    continue
                if ext_list and item.suffix.lower() not in ext_list:
                    continue
                found_files.append(item)
        except PermissionError:
            print("⚠️  Tidak punya akses ke folder tersebut.")
            return []

        found_files.sort(key=lambda p: p.name.lower())

        if not found_files:
            print(f"Tidak ada {file_type_label} ditemukan di folder tersebut.")
            return []

        return found_files

    except tk.TclError as e:
        print(f"⚠️  File Explorer tidak tersedia: {e}")
        print("   Gunakan opsi 'a' untuk input path folder manual.")
        return []


def _handle_exclude_mode(
    indexed_paths: list[tuple[int, Path]],
) -> list[tuple[int, Path]]:
    """Handle mode pengecualian - filter file yang di-skip.

    FIX: Gunakan indexed_paths (original_idx, path) agar nomor tidak berubah
    setelah exclude. Nomor asli tetap ditampilkan.
    """
    print("\n" + "=" * 72)
    print("MODE PENGECUALIAN")
    print("=" * 72)
    print("Masukkan nomor file yang TIDAK ingin diproses:")
    exclude_input = input("(Contoh: 4,5,6 atau 2-5): ").strip()

    try:
        exclude_numbers = parse_selection(exclude_input, max(indexed_paths, key=lambda x: x[0])[0])

        filtered_paths = [
            (orig_idx, path) for orig_idx, path in indexed_paths
            if orig_idx not in exclude_numbers
        ]

        if not filtered_paths:
            print("Semua file di-exclude! Tidak ada file yang tersisa.")
            return indexed_paths

        print(f"\nFile yang akan diproses:")
        for orig_idx, path in filtered_paths:
            print(f"{orig_idx:>3}. {path.name}")
        print(f"Total: {len(filtered_paths)} file")

        return filtered_paths

    except ValueError as exc:
        print(f"Input tidak valid: {exc}")
        return indexed_paths


def _handle_number_selection(
    indexed_paths: list[tuple[int, Path]],
    raw: str,
    allow_many: bool,
) -> list[Path] | list[tuple[int, Path]]:
    """Handle pemilihan file berdasarkan nomor.

    Returns list[Path] jika valid, atau indexed_paths asli jika invalid (untuk retry).
    """
    max_number = max(idx for idx, _ in indexed_paths)
    picked_numbers = parse_selection(raw, max_number)
    if not allow_many and len(picked_numbers) != 1:
        print("Pilih tepat satu file.")
        return indexed_paths  # Return original untuk continue loop

    result = []
    for number in picked_numbers:
        for orig_idx, path in indexed_paths:
            if orig_idx == number:
                result.append(path)
                break
    return result


def select_paths_with_folder_option(
    paths: list[Path],
    allow_many: bool = True,
    file_type_label: str = "file",
    extensions: list[str] | None = None,
) -> list[Path]:
    """
    Tampilkan daftar file dengan opsi tambahan:
    a. Input path folder lain (ketik manual)
    b. Pilih folder via File Explorer
    c. Pilih file langsung via File Explorer (skip list)
    d. Pengecualian file (skip file tertentu)
    e. Proses semua file
    0. Hentikan program

    FIX: Tambah guard untuk empty list agar tidak infinite loop.
    FIX: Gunakan indexed_paths agar nomor tidak berubah setelah exclude.
    FIX: Tambah dialog folder + file langsung.
    """
    # FIX BUG 1: Guard untuk empty list
    if not paths:
        print(f"Tidak ada {file_type_label} ditemukan.")
        return []

    # Buat indexed paths: (original_index, path) agar nomor tidak berubah
    indexed_paths: list[tuple[int, Path]] = [(i + 1, p) for i, p in enumerate(paths)]

    # Simpan folder path utama dan original paths untuk opsi kembali
    original_folder_path: str | None = None
    original_indexed_paths = indexed_paths[:]

    while True:
        # Tentukan apakah kita dalam konteks folder custom
        has_folder_context = original_folder_path is not None
        display_folder_path = original_folder_path

        _print_file_list_with_indices(indexed_paths, file_type_label, display_folder_path)
        _print_menu_options(has_folder_context)

        if allow_many:
            prompt = "\nPilih nomor file (contoh: 1 atau 1,3,5 atau 2-6 atau all): "
        else:
            prompt = "\nPilih nomor file (contoh: 1): "

        raw = input(prompt).strip().lower()

        # Handle opsi a: Input path folder lain (ketik manual)
        if raw == "a":
            ext = extensions[0] if extensions else ""
            custom_paths = handle_folder_input(file_type_label, ext)
            if custom_paths:
                # Simpan folder path untuk indikator
                if custom_paths:
                    original_folder_path = str(custom_paths[0].parent)
                # Re-index dengan nomor baru
                indexed_paths = [(i + 1, p) for i, p in enumerate(custom_paths)]
                continue
            else:
                print("Folder tidak valid atau tidak ada file yang cocok.")
                continue

        # Handle opsi b: Pilih folder via File Explorer
        elif raw == "b":
            ext_list = extensions if extensions else []
            folder_files = handle_folder_dialog(ext_list, file_type_label)
            if folder_files is None:
                continue  # User cancel, tampilkan list lagi
            if folder_files:
                # Simpan folder path untuk indikator
                original_folder_path = str(folder_files[0].parent)
                # Re-index dengan nomor baru
                indexed_paths = [(i + 1, p) for i, p in enumerate(folder_files)]
                continue
            else:
                print("Tidak ada file yang ditemukan di folder tersebut.")
                continue

        # Handle opsi c: Pilih file langsung via File Explorer (skip list)
        elif raw == "c":
            ext_list = extensions if extensions else []
            explorer_files = handle_file_explorer(ext_list, file_type_label)
            if explorer_files:
                # LANGSUNG return, tidak tampilkan list lagi
                return explorer_files
            else:
                print("Tidak ada file yang dipilih.")
                continue

        # Handle opsi d: Pengecualian file
        elif raw == "d":
            indexed_paths = _handle_exclude_mode(indexed_paths)
            continue

        # Handle opsi e: Proses semua file
        elif raw == "e":
            if ask_yes_no(f"Semua file ({len(indexed_paths)} file) akan diproses. Lanjut?", default=True):
                return [path for _, path in indexed_paths]
            else:
                continue

        # Handle opsi f: Kembali ke folder utama (hanya jika dalam konteks folder custom)
        elif raw == "f" and has_folder_context:
            indexed_paths = original_indexed_paths[:]
            original_folder_path = None
            continue

        # Handle opsi 0: Hentikan program
        elif raw == "0":
            print("Program dihentikan.")
            return []

        # Handle pilihan nomor
        try:
            result = _handle_number_selection(indexed_paths, raw, allow_many)
            if result is indexed_paths:
                continue  # Invalid selection, retry
            return result
        except ValueError as exc:
            print(f"Input tidak valid: {exc}")


def handle_file_explorer(extensions: list[str], file_type_label: str) -> list[Path]:
    """
    Buka dialog file explorer untuk pilih file manual.

    FIX: Tambah try/except untuk headless environment.
    """
    try:
        root = tk.Tk()
        root.withdraw()  # Sembunyikan window utama tkinter

        # Buat filter file types berdasarkan ekstensi
        filetypes = []
        if ".pdf" in extensions:
            filetypes.append(("PDF files", "*.pdf"))
        if ".jpg" in extensions or ".jpeg" in extensions:
            filetypes.append(("Image files", "*.jpg *.jpeg"))
        if ".png" in extensions:
            filetypes.append(("PNG files", "*.png"))
        if ".bmp" in extensions:
            filetypes.append(("BMP files", "*.bmp"))
        if ".webp" in extensions:
            filetypes.append(("WebP files", "*.webp"))
        if ".docx" in extensions:
            filetypes.append(("Word documents", "*.docx"))
        if ".py" in extensions:
            filetypes.append(("Python files", "*.py"))
        filetypes.append(("All files", "*.*"))

        # Buka dialog pilih banyak file
        files = filedialog.askopenfilenames(
            title=f"Pilih {file_type_label}",
            filetypes=filetypes,
            initialdir=str(BASE_DIR)
        )

        root.destroy()

        # Convert ke list Path
        return [Path(f) for f in files]

    except tk.TclError as e:
        print(f"⚠️  File Explorer tidak tersedia: {e}")
        print("   Gunakan opsi 'a' untuk input path folder, atau ketik nomor file langsung.")
        return []


def handle_folder_input(file_type_label: str, file_extension: str) -> list[Path]:
    """
    Minta user input path folder, lalu cari file dengan ekstensi yang relevan.

    FIX: Handle unmapped labels dengan fallback ke file_extension atau semua file.
    """
    print("\n" + "=" * 72)
    print("INPUT PATH FOLDER")
    print("=" * 72)

    folder_path = input("Masukkan path folder: ").strip()

    # Coba handle path dengan quotes jika user copy-paste dari Windows Explorer
    folder_path = folder_path.strip('"').strip("'")

    custom_dir = Path(folder_path)

    if not custom_dir.exists():
        print("Folder tidak ditemukan!")
        return []

    if not custom_dir.is_dir():
        print("Path bukan folder!")
        return []

    # Tentukan ekstensi yang akan dicari berdasarkan tipe file
    extension_map = {
        "pdf": [".pdf"],
        "file pdf": [".pdf"],
        "jpg": [".jpg", ".jpeg"],
        "file jpg/jpeg": [".jpg", ".jpeg"],
        "png": [".png"],
        "file png": [".png"],
        "gambar": [".jpg", ".jpeg", ".png", ".bmp", ".webp"],
        "file gambar": [".jpg", ".jpeg", ".png", ".bmp", ".webp"],
        "docx": [".docx"],
        "file docx": [".docx"],
        "python": [".py"],
        "file python": [".py"],
        "script python": [".py"],
        "file excel": [".xlsx", ".xls", ".csv"],
        "excel": [".xlsx", ".xls", ".csv"],
        "file text": [".txt", ".md"],
        "text": [".txt", ".md"],
        "file image": [".jpg", ".jpeg", ".png", ".bmp", ".webp"],
        "image": [".jpg", ".jpeg", ".png", ".bmp", ".webp"],
        "file all": [],
        "all": [],
    }

    # FIX BUG 4: Cari ekstensi dengan fallback yang lebih aman
    label_lower = file_type_label.lower()
    extensions_to_find = extension_map.get(label_lower)

    if not extensions_to_find and file_extension:
        extensions_to_find = [file_extension.lower()]

    # FIX: Jika masih tidak ada mapping, tampilkan warning dan cari semua file
    if not extensions_to_find:
        print(f"⚠️  Tipe file '{file_type_label}' tidak dikenal. Mencari semua file.")
        extensions_to_find = []

    # Cari file di folder custom (non-recursive, hanya file langsung di folder)
    found_files: list[Path] = []
    try:
        for item in custom_dir.iterdir():
            if not item.is_file():
                continue
            if extensions_to_find and item.suffix.lower() not in extensions_to_find:
                continue
            found_files.append(item)
    except PermissionError:
        print("⚠️  Tidak punya akses ke folder tersebut.")
        return []

    # Sort berdasarkan nama file
    found_files.sort(key=lambda p: p.name.lower())

    if not found_files:
        print(f"Tidak ada {file_type_label} ditemukan di folder tersebut.")
        return []

    print(f"\nDitemukan {len(found_files)} {file_type_label} di {custom_dir}:")
    for index, path in enumerate(found_files, start=1):
        print(f"{index:>3}. {path.name}")

    return found_files


def ask_yes_no(prompt: str, default: bool = True) -> bool:
    suffix = " [Y/n]: " if default else " [y/N]: "
    raw = input(prompt + suffix).strip().lower()
    if not raw:
        return default
    return raw in {"y", "yes", "ya"}


def ask_text(prompt: str, default: str = "") -> str:
    label = f"{prompt} [{default}]: " if default else f"{prompt}: "
    raw = input(label).strip()
    return raw or default


def print_dpi_guide(default: str) -> None:
    print("\nPanduan DPI OCR:")
    print("  low  : 150-220 (lebih cepat, cocok untuk teks besar/jelas)")
    print("  mid  : 221-300 (seimbang, rekomendasi umum)")
    print("  high : 301-400 (untuk scan kecil/buram, lebih berat)")
    print(f"  default saat ini: {default}")


def run_command(command: list[str]) -> None:
    print("\nMenjalankan:")
    print(" ".join(f'"{part}"' if " " in part else part for part in command))
    print("-" * 72)
    completed = subprocess.run(command, cwd=BASE_DIR)
    print("-" * 72)
    print(f"Exit code: {completed.returncode}")


def handle_batch_tool(tool: ToolEntry) -> None:
    """
    Handler untuk script batch convert.
    User bisa pilih file tertentu atau jalankan untuk semua file di folder.
    """
    # Tentukan ekstensi file berdasarkan script
    extension_map = {
        "convert_pdf_to_jpg.py": ([".pdf"], "file PDF"),
        "convert_jpg_to_png.py": ([".jpg", ".jpeg"], "file JPG/JPEG"),
        "convert_img_to_pdf.py": ([".jpg", ".jpeg", ".png", ".bmp", ".webp"], "file Gambar"),
        "convert_docx_to_jpg.py": ([".docx"], "file DOCX"),
    }

    extensions, file_label = extension_map.get(tool.script_name, ([], "file"))

    files = find_files(extensions)
    if not files:
        print(f"Tidak ada {file_label} ditemukan.")
        return

    selected_files = select_paths_with_folder_option(
        files, allow_many=True, file_type_label=file_label, extensions=extensions
    )

    if not selected_files:
        print("Kembali ke menu utama.")
        return

    # Jalankan script dengan file yang dipilih
    for file_path in selected_files:
        command = [
            PYTHON_EXE,
            str(BASE_DIR / tool.script_name),
            "--input",
            str(file_path),
        ]
        run_command(command)


def handle_ocr_tool(tool: ToolEntry) -> None:
    pdf_files = find_files([".pdf"])
    if not pdf_files:
        print("Tidak ada file PDF ditemukan.")
        return

    selected_files = select_paths_with_folder_option(
        pdf_files, allow_many=True, file_type_label="file PDF", extensions=[".pdf"]
    )

    if not selected_files:
        print("Kembali ke menu utama.")
        return

    print_dpi_guide("240")
    dpi = ask_text("Masukkan DPI render OCR", "240")
    gpu_mode = ask_text("Mode GPU (auto/on/off)", "auto").lower()
    min_score = ask_text("Confidence minimum OCR", "0.50")
    lang = ask_text("Bahasa model OCR (contoh: id atau en; 'latin' akan dipetakan ke id)", "id")

    for pdf_path in selected_files:
        command = [
            PYTHON_EXE,
            str(BASE_DIR / tool.script_name),
            "--input",
            str(pdf_path),
            "--dpi",
            dpi,
            "--gpu",
            gpu_mode,
            "--min-score",
            min_score,
            "--lang",
            lang,
        ]
        run_command(command)


def handle_tesseract_ocr_tool(tool: ToolEntry) -> None:
    pdf_files = find_files([".pdf"])
    if not pdf_files:
        print("Tidak ada file PDF ditemukan.")
        return

    selected_files = select_paths_with_folder_option(
        pdf_files, allow_many=True, file_type_label="file PDF", extensions=[".pdf"]
    )

    if not selected_files:
        print("Kembali ke menu utama.")
        return

    # Parameter global (sekali saja, berlaku untuk semua file)
    print("\n" + "=" * 72)
    print("PARAMETER GLOBAL (berlaku untuk semua file)")
    print("=" * 72)
    print_dpi_guide("220")
    dpi = ask_text("DPI render OCR", "220")
    lang = ask_text("Bahasa Tesseract OCR (ind/eng/both/jpn)", "ind")
    min_text_length = ask_text("Minimal panjang teks sebelum fallback OCR", "30")
    tesseract_cmd = ask_text("Path tesseract.exe (boleh kosong jika sudah ada di PATH)", "")

    # STEP 1: Kumpulkan parameter halaman untuk SEMUA file dulu
    print("\n" + "=" * 72)
    print("KUMPULKAN PARAMETER HALAMAN")
    print("=" * 72)

    file_configs: list[tuple[Path, str, str]] = []

    for idx, pdf_path in enumerate(selected_files, start=1):
        # Buka PDF untuk hitung jumlah halaman
        if fitz:
            try:
                doc = fitz.open(str(pdf_path))
                total_halaman = len(doc)
                doc.close()
            except Exception:
                total_halaman = "?"
        else:
            total_halaman = "?"

        print(f"\n────────────────────────────────────────────────────────────────────────")
        print(f"File {idx}/{len(selected_files)}: {pdf_path.name} ({total_halaman} halaman)")
        print(f"────────────────────────────────────────────────────────────────────────")

        # Tanya halaman untuk file ini
        page_start = ask_text(f"Halaman mulai (1-{total_halaman})", "1")
        page_end = ask_text(f"Halaman akhir (0 = semua)", "0")

        file_configs.append((pdf_path, page_start, page_end))

    # STEP 2: Tampilkan rangkuman semua file yang akan diproses
    print("\n" + "=" * 72)
    print("RANGKUMAN PROSES")
    print("=" * 72)
    print(f"\nTotal file: {len(file_configs)}")
    print(f"DPI: {dpi} | Bahasa: {lang} | Min teks: {min_text_length}\n")

    for idx, (pdf_path, page_start, page_end) in enumerate(file_configs, start=1):
        end_display = page_end if page_end != "0" else "semua"
        print(f"  {idx}. {pdf_path.name}")
        print(f"     Halaman: {page_start} - {end_display}")

    if not ask_yes_no("\nLanjutkan proses?", default=True):
        print("Proses dibatalkan.")
        return

    # STEP 3: Proses semua file
    print("\n" + "=" * 72)
    print("PROSES")
    print("=" * 72)

    for idx, (pdf_path, page_start, page_end) in enumerate(file_configs, start=1):
        print(f"\n── Memproses File {idx}/{len(file_configs)}: {pdf_path.name} ──\n")

        command = [
            PYTHON_EXE,
            str(BASE_DIR / tool.script_name),
            "--input",
            str(pdf_path),
            "--dpi",
            dpi,
            "--lang",
            lang,
            "--min-text-length",
            min_text_length,
            "--page-start",
            page_start,
            "--page-end",
            page_end,
        ]
        if tesseract_cmd:
            command.extend(["--tesseract-cmd", tesseract_cmd])
        run_command(command)

    print("\n" + "=" * 72)
    print("Selesai! Semua file diproses.")
    print("=" * 72)


def handle_translate_tool(tool: ToolEntry) -> None:
    """Handler untuk translate PDF. Sekarang script support --input optional."""
    pdf_files = find_files([".pdf"])
    if not pdf_files:
        print("Tidak ada file PDF ditemukan.")
        return

    selected_files = select_paths_with_folder_option(
        pdf_files, allow_many=True, file_type_label="file PDF", extensions=[".pdf"]
    )

    if not selected_files:
        print("Kembali ke menu utama.")
        return

    # Parameter global
    print("\n" + "=" * 72)
    print("PARAMETER TRANSLATE")
    print("=" * 72)
    font_scale = ask_text("Font scale (0.5 = 50% dari asli)", "0.5")
    source_lang = ask_text("Bahasa sumber (en)", "en")
    target_lang = ask_text("Bahasa target (id)", "id")
    page_start = ask_text("Halaman mulai (1)", "1")
    page_end = ask_text("Halaman akhir (0 = semua)", "0")
    delay = ask_text("Delay antar request (detik)", "0.3")

    for pdf_path in selected_files:
        command = [
            PYTHON_EXE,
            str(BASE_DIR / tool.script_name),
            "--input",
            str(pdf_path),
            "--font-scale",
            font_scale,
            "--source",
            source_lang,
            "--target",
            target_lang,
            "--page-start",
            page_start,
            "--page-end",
            page_end,
            "--delay",
            delay,
        ]
        run_command(command)


def handle_extract_pages_tool(tool: ToolEntry) -> None:
    """Handler untuk extract halaman PDF. Sekarang script support --input optional."""
    pdf_files = find_files([".pdf"])
    if not pdf_files:
        print("Tidak ada file PDF ditemukan.")
        return

    selected_files = select_paths_with_folder_option(
        pdf_files, allow_many=False, file_type_label="file PDF", extensions=[".pdf"]
    )

    if not selected_files:
        print("Kembali ke menu utama.")
        return

    pdf_path = selected_files[0]

    # Tanya mode dan parameter
    print("\n" + "=" * 72)
    print("MODE EXTRACT")
    print("=" * 72)
    print("1. Range isi dokumen (dengan offset)")
    print("2. Range nomor halaman PDF viewer")
    print("3. Batch split (banyak bagian)")
    mode_choice = ask_text("Pilih mode (1/2/3)", "2")

    mode_map = {"1": "range", "2": "pdf-range", "3": "batch"}
    mode = mode_map.get(mode_choice, "pdf-range")

    command = [
        PYTHON_EXE,
        str(BASE_DIR / tool.script_name),
        "--input",
        str(pdf_path),
        "--mode",
        mode,
    ]

    if mode == "range":
        start = ask_text("Halaman mulai isi dokumen", "1")
        end = ask_text("Halaman akhir isi dokumen (0 = terakhir)", "0")
        offset = ask_text("Offset halaman depan", "0")
        command.extend(["--start", start, "--end", end, "--offset", offset])
    elif mode == "pdf-range":
        pdf_start = ask_text("Halaman mulai PDF viewer", "1")
        pdf_end = ask_text("Halaman akhir PDF viewer (0 = terakhir)", "0")
        command.extend(["--pdf-start", pdf_start])
        if pdf_end != "0":
            command.extend(["--pdf-end", pdf_end])
    elif mode == "batch":
        batch_input = ask_text('Format batch (contoh: "Cover:1-16;Bab 1:17-23")', "")
        if batch_input:
            command.extend(["--batch", batch_input])
        else:
            print("⚠️  Mode batch memerlukan input. Menggunakan default.")

    prefix = ask_text("Prefix nama output", "Extract")
    command.extend(["--prefix", prefix])

    run_command(command)


def handle_fast_extract_tool(tool: ToolEntry) -> None:
    """Handler untuk ekstrak teks PDF cepat (Direct Text, tanpa OCR)."""
    pdf_files = find_files([".pdf"])
    if not pdf_files:
        print("Tidak ada file PDF ditemukan.")
        return

    selected_files = select_paths_with_folder_option(
        pdf_files, allow_many=True, file_type_label="file PDF", extensions=[".pdf"]
    )

    if not selected_files:
        print("Kembali ke menu utama.")
        return

    # Kumpulkan parameter halaman untuk SEMUA file dulu
    print("\n" + "=" * 72)
    print("KUMPULKAN PARAMETER HALAMAN")
    print("=" * 72)

    file_configs: list[tuple[Path, str, str]] = []

    for idx, pdf_path in enumerate(selected_files, start=1):
        # Buka PDF untuk hitung jumlah halaman
        if fitz:
            try:
                doc = fitz.open(str(pdf_path))
                total_halaman = len(doc)
                doc.close()
            except Exception:
                total_halaman = "?"
        else:
            total_halaman = "?"

        print(f"\n{'─' * 72}")
        print(f"File {idx}/{len(selected_files)}: {pdf_path.name} ({total_halaman} halaman)")
        print(f"{'─' * 72}")

        # Tanya halaman untuk file ini
        page_start = ask_text(f"Halaman mulai (1-{total_halaman})", "1")
        page_end = ask_text(f"Halaman akhir (0 = semua)", "0")

        file_configs.append((pdf_path, page_start, page_end))

    # Tampilkan rangkuman semua file yang akan diproses
    print("\n" + "=" * 72)
    print("RANGKUMAN PROSES")
    print("=" * 72)
    print(f"\nTotal file: {len(file_configs)}")

    for idx, (pdf_path, page_start, page_end) in enumerate(file_configs, start=1):
        end_display = page_end if page_end != "0" else "semua"
        print(f"  {idx}. {pdf_path.name}")
        print(f"     Halaman: {page_start} - {end_display}")

    if not ask_yes_no("\nLanjutkan proses?", default=True):
        print("Proses dibatalkan.")
        return

    # Proses semua file
    print("\n" + "=" * 72)
    print("PROSES")
    print("=" * 72)

    for idx, (pdf_path, page_start, page_end) in enumerate(file_configs, start=1):
        print(f"\n── Memproses File {idx}/{len(file_configs)}: {pdf_path.name} ──\n")

        command = [
            PYTHON_EXE,
            str(BASE_DIR / tool.script_name),
            "--input",
            str(pdf_path),
            "--page-start",
            page_start,
            "--page-end",
            page_end,
        ]
        run_command(command)

    print("\n" + "=" * 72)
    print("Selesai! Semua file diproses.")
    print("=" * 72)


def handle_generic_python_runner(_: ToolEntry) -> None:
    scripts = list_python_scripts()
    if not scripts:
        print("Tidak ada script Python lain ditemukan.")
        return

    selected = select_paths_with_folder_option(
        scripts, allow_many=False, file_type_label="script Python", extensions=[".py"]
    )

    if not selected:
        print("Kembali ke menu utama.")
        return

    script_path = selected[0]

    # FIX BUG 9: Cegah recursive launch main.py
    if script_path.name == Path(__file__).name:
        print("⚠️  Tidak bisa menjalankan main.py dari dalam main.py.")
        print("   Jalankan script lain saja.")
        return

    extra_args = ask_text("Argumen tambahan untuk script ini (boleh kosong)", "")

    command = [PYTHON_EXE, str(script_path)]
    if extra_args:
        command.extend(extra_args.split())
    run_command(command)


def handle_file_browser(_: ToolEntry) -> None:
    print("\nTipe file yang bisa dicari:")
    file_types = list(SUPPORTED_FILE_TYPES.keys())
    for index, file_type in enumerate(file_types, start=1):
        print(f"{index:>3}. {file_type}")

    while True:
        raw = input("\nPilih tipe file: ").strip()
        if raw.isdigit() and 1 <= int(raw) <= len(file_types):
            file_type = file_types[int(raw) - 1]
            break
        print("Pilihan tidak valid.")

    keyword = ask_text("Filter nama file (boleh kosong)", "").lower()
    extensions = SUPPORTED_FILE_TYPES[file_type]
    paths = find_files(extensions if extensions else None)
    if keyword:
        paths = [path for path in paths if keyword in path.name.lower()]

    if not paths:
        print("Tidak ada file yang cocok.")
        return

    print(f"\nDitemukan {len(paths)} file:")
    print_numbered_paths(paths)

    if ask_yes_no("Mau pilih file tertentu untuk ditampilkan path lengkapnya?", default=True):
        ext_list = extensions if extensions else []
        selected = select_paths_with_folder_option(
            paths, allow_many=True, file_type_label=f"file {file_type}", extensions=ext_list
        )

        if not selected:
            print("Kembali ke menu utama.")
            return

        print("")
        for path in selected:
            print(path)


def build_tools() -> list[ToolEntry]:
    return [
        ToolEntry(
            key="1",
            name="OCR PDF ke TXT/MD/JSON",
            description="PaddleOCR untuk ambil semua teks PDF scan/gambar.",
            script_name="extract_pdf_to_text_ocr.py",
            handler=handle_ocr_tool,
        ),
        ToolEntry(
            key="2",
            name="OCR PDF ke TXT (Tesseract Hybrid)",
            description="Ambil teks asli per halaman lalu fallback ke Tesseract jika perlu.",
            script_name="extract_pdf_to_text_tesseract.py",
            handler=handle_tesseract_ocr_tool,
        ),
        ToolEntry(
            key="3",
            name="Ekstrak Teks PDF Cepat",
            description="Ambil teks langsung dari PDF (tanpa OCR), sangat cepat.",
            script_name="extract_text_fast.py",
            handler=handle_fast_extract_tool,
        ),
        ToolEntry(
            key="4",
            name="Convert PDF ke JPG",
            description="Konversi semua PDF di folder utama menjadi JPG.",
            script_name="convert_pdf_to_jpg.py",
            handler=handle_batch_tool,
        ),
        ToolEntry(
            key="5",
            name="Convert JPG ke PNG",
            description="Konversi semua JPG/JPEG di folder utama menjadi PNG.",
            script_name="convert_jpg_to_png.py",
            handler=handle_batch_tool,
        ),
        ToolEntry(
            key="6",
            name="Convert Gambar ke PDF",
            description="Konversi semua JPG/PNG di folder utama menjadi PDF.",
            script_name="convert_img_to_pdf.py",
            handler=handle_batch_tool,
        ),
        ToolEntry(
            key="7",
            name="Convert DOCX ke JPG",
            description="Konversi semua DOCX di folder utama menjadi JPG.",
            script_name="convert_docx_to_jpg.py",
            handler=handle_batch_tool,
        ),
        ToolEntry(
            key="8",
            name="Extract Halaman PDF",
            description="Jalankan script pemotongan halaman PDF yang sudah ada.",
            script_name="extract_pdf_pages.py",
            handler=handle_extract_pages_tool,
        ),
        ToolEntry(
            key="9",
            name="Translate PDF",
            description="Jalankan script translate PDF yang sudah ada.",
            script_name="translate_pdf.py",
            handler=handle_translate_tool,
        ),
        ToolEntry(
            key="10",
            name="Cari File",
            description="Cari file pdf, excel, txt, jpg, png, docx, dan py.",
            script_name="",
            handler=handle_file_browser,
        ),
        ToolEntry(
            key="11",
            name="Jalankan Script Python Lain",
            description="Deteksi semua file .py lalu pilih script mana yang mau dijalankan.",
            script_name="",
            handler=handle_generic_python_runner,
        ),
    ]


def main() -> None:
    tools = build_tools()

    while True:
        clear_screen()
        print_header("MAIN MENU - TERMINAL CONTROLLER")
        print(f"Folder kerja : {BASE_DIR}")
        print(f"Python       : {PYTHON_EXE}")
        print("")

        for tool in tools:
            print(f"{tool.key}. {tool.name}")
            print(f"   {tool.description}")

        print("0. Keluar")

        choice = input("\nPilih menu: ").strip()
        if choice == "0":
            print("Selesai.")
            return

        selected_tool = next((tool for tool in tools if tool.key == choice), None)
        if not selected_tool:
            print("Menu tidak dikenal.")
            pause()
            continue

        clear_screen()
        print_header(selected_tool.name)
        selected_tool.handler(selected_tool)
        pause()


if __name__ == "__main__":
    main()
