import os
import sys
import warnings
from pathlib import Path
from fpdf import FPDF

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

warnings.filterwarnings(
    "ignore",
    message=r"cmap value too big/small: .*",
    category=UserWarning,
    module=r"fpdf\.ttfonts",
)

# Paths
BASE_DIR = Path(__file__).parent
CONVERT_DIR = BASE_DIR / "convert txt"
WINDOWS_FONTS_DIR = Path(os.environ.get("WINDIR", r"C:\Windows")) / "Fonts"
UNICODE_FONT_CANDIDATES = [
    WINDOWS_FONTS_DIR / "malgun.ttf",
    WINDOWS_FONTS_DIR / "arial.ttf",
]

# Fix H4: Cache font path untuk avoid I/O overhead
_cached_font_path = None


def _contains_non_latin1(text: str) -> bool:
    return any(ord(ch) > 255 for ch in text)


def _find_unicode_font():
    """Find unicode font with caching to avoid repeated I/O"""
    global _cached_font_path

    # Return cached result if available
    if _cached_font_path is not None:
        return _cached_font_path

    # Search for font
    for candidate in UNICODE_FONT_CANDIDATES:
        if candidate.exists():
            _cached_font_path = candidate
            return candidate

    _cached_font_path = None
    return None


def _select_pdf_font(pdf: FPDF, text: str):
    if not _contains_non_latin1(text):
        return "Helvetica", False

    font_path = _find_unicode_font()
    if font_path is None:
        print("⚠️ Unicode font tidak ditemukan. Karakter Jepang/CJK bisa berubah saat PDF dibuat.")
        return "Helvetica", False

    pdf.add_font("UnicodeSans", "", str(font_path), uni=True)
    return "UnicodeSans", True

def get_txt_files():
    """Recursively find .txt files in convert txt folder."""
    if not CONVERT_DIR.exists():
        print(f"❌ Directory not found: {CONVERT_DIR}")
        return []

    files = []
    for path in CONVERT_DIR.rglob("*.txt"):
        try:
            rel_path = path.relative_to(CONVERT_DIR)
            label = rel_path.parts[0] if rel_path.parts else "root"
            files.append({
                "path": path,
                "name": path.name,
                "label": label,
                "size": path.stat().st_size
            })
        except Exception:
            continue

    files.sort(key=lambda x: x["path"].stat().st_mtime, reverse=True)
    return files

def txt_to_pdf(txt_path):
    """Convert a single TXT file to PDF."""
    txt_path = Path(txt_path)
    if not txt_path.exists():
        print(f"❌ File not found: {txt_path}")
        return

    print(f"🔄 Converting: {txt_path.name} ...")

    try:
        # 1. Read Text
        with open(txt_path, "r", encoding="utf-8") as f:
            text = f.read()

        # 2. Setup PDF
        pdf = FPDF()
        pdf.add_page()
        pdf.set_auto_page_break(auto=True, margin=15)
        font_family, use_unicode_font = _select_pdf_font(pdf, f"{txt_path.stem}\n{text}")

        if use_unicode_font:
            print(f"   🔤 Using Unicode font: {font_family}")

        # Helper: sanitize text only when using Latin-1 built-in fonts
        def prepare_text(value):
            if not isinstance(value, str):
                return ""
            if use_unicode_font:
                return value
            return value.encode("latin-1", "replace").decode("latin-1")

        # Title
        pdf.set_font(font_family, size=14)
        pdf.multi_cell(0, 10, prepare_text(txt_path.stem))
        pdf.ln(5)

        # Helper: keep original line breaks, just strip trailing whitespace
        def clean_section(text_chunk):
            """Preserve all original line breaks from TXT file."""
            lines = text_chunk.split('\n')
            cleaned = [line.rstrip() for line in lines]
            return '\n'.join(cleaned)

        # Split Header vs Body to preserve Header formatting
        if "=" * 10 in text:
            # Assuming the first separator divides header
            parts = text.split("=" * 10, 1)
            header = parts[0]
            body = parts[1]

            # Print Header (keep lines)
            pdf.set_font(font_family, size=10)
            pdf.multi_cell(0, 6, prepare_text(header.strip()))
            pdf.ln(5)
            pdf.cell(0, 0, border="T") # Draw separator line
            pdf.ln(5)

            # Print Body (clean/unwrap)
            pdf.set_font(font_family, size=11)
            safe_body = prepare_text(body)

            # We process the body to fix the "choppy" lines
            final_body = clean_section(safe_body)
            pdf.multi_cell(0, 7, final_body)

        else:
            # Fallback for files without header structure
            pdf.set_font(font_family, size=11)
            safe_text = prepare_text(text)
            final_text = clean_section(safe_text)
            pdf.multi_cell(0, 7, final_text)

        # 3. Save
        # Save in same folder, same name, but .pdf
        output_path = txt_path.with_suffix(".pdf")

        try:
            pdf.output(output_path)
            print(f"   ✅ Saved: {output_path.name}")
        except PermissionError:
            print(f"   ⚠️  File locked (open in reader?). Saving as copy...")
            # Fallback: Save as _new.pdf
            output_path = txt_path.with_name(txt_path.stem + "_new.pdf")
            pdf.output(output_path)
            print(f"   ✅ Saved: {output_path.name}")

    except Exception as e:
        print(f"   ❌ Failed to convert: {e}")

def main():
    print("📄 TXT to PDF Converter (Batch)\n")

    if len(sys.argv) < 2:
        print("Usage:")
        print("  python convert_pdf.py single   -> Pilih 1 file")
        print("  python convert_pdf.py multiple -> Pilih banyak file")
        print("  python convert_pdf.py <file>   -> Langsung proses file")
        return

    arg = sys.argv[1].lower()

    # Direct file
    if arg.endswith(".txt"):
        txt_to_pdf(arg)
        return

    # Interactive
    if arg in ["single", "multiple"]:
        files = get_txt_files()
        if not files:
            print("❌ No files found.")
            return

        print("-" * 60)
        for i, f in enumerate(files, 1):
            kb = f['size'] / 1024
            print(f"[{i}] {f['name']} ({f['label']}) - {kb:.1f} KB")
        print("-" * 60)

        sel = input("Pilih nomor (contoh: 1 atau 1,3): ").strip()
        if not sel: return

        parts = [p.strip() for p in sel.split(",")]

        for p in parts:
            if p.isdigit():
                idx = int(p) - 1
                if 0 <= idx < len(files):
                    target = files[idx]
                    txt_to_pdf(target['path'])

if __name__ == "__main__":
    main()
