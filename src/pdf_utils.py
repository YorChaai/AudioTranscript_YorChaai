"""
PDF utilities - shared functions untuk PDF operations
Digunakan oleh convert_pdf.py dan server.py
"""

import os
import sys
from pathlib import Path
from datetime import datetime
from fpdf import FPDF

try:
    from pypdf import PdfWriter
except ImportError:
    PdfWriter = None

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Paths
BASE_DIR = Path(__file__).parent.parent  # Project root (src/ is subdir)
CONVERT_DIR = BASE_DIR / "output"
WINDOWS_FONTS_DIR = Path(os.environ.get("WINDIR", r"C:\Windows")) / "Fonts"
UNICODE_FONT_CANDIDATES = [
    WINDOWS_FONTS_DIR / "malgun.ttf",
    WINDOWS_FONTS_DIR / "arial.ttf",
]

# Cache font path
_cached_font_path = None


def _contains_non_latin1(text: str) -> bool:
    return any(ord(ch) > 255 for ch in text)


def _find_unicode_font():
    """Find unicode font with caching to avoid repeated I/O"""
    global _cached_font_path

    if _cached_font_path is not None:
        return _cached_font_path

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


def txt_to_pdf(txt_path):
    """
    Convert a single TXT file to PDF.
    Returns True if successful, False otherwise.
    """
    txt_path = Path(txt_path)
    if not txt_path.exists():
        print(f"❌ File not found: {txt_path}")
        return False

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
            pdf.cell(0, 0, border="T")  # Draw separator line
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

        # 3. Save and validate
        # Save in same folder, same name, but .pdf
        output_path = txt_path.with_suffix(".pdf")

        try:
            pdf_output = pdf.output(output_path)
            # Fix M8: Validate PDF output
            if output_path.exists() and output_path.stat().st_size > 0:
                print(f"   ✅ Saved: {output_path.name}")
                return True
            else:
                print("   ❌ Failed to create PDF (empty file)")
                return False
        except PermissionError:
            print("   ⚠️  File locked (open in reader?). Saving as copy...")
            # Fallback: Save as _new.pdf
            output_path = txt_path.with_name(txt_path.stem + "_new.pdf")
            pdf_output = pdf.output(output_path)
            if output_path.exists() and output_path.stat().st_size > 0:
                print(f"   ✅ Saved: {output_path.name}")
                return True
            else:
                print("   ❌ Failed to create PDF (empty file)")
                return False
        except Exception as pdf_err:
            print(f"   ❌ PDF output error: {pdf_err}")
            return False

    except Exception as e:
        print(f"   ❌ Conversion failed: {e}")
        return False


def merge_all_pdfs(convert_dir=None, output_filename_pattern="Merged_Book_{timestamp}.pdf"):
    """
    Gabungkan semua file PDF di folder convert jadi satu
    Fix H7: Stream merge untuk avoid OOM pada large PDFs

    Args:
        convert_dir: folder PDF (default: CONVERT_DIR)
        output_filename_pattern: pattern nama file output

    Returns:
        dict dengan status, path, filename, count atau error
    """
    if PdfWriter is None:
        return {
            "status": "error",
            "error": "Library 'pypdf' belum terinstall. Jalankan: pip install pypdf"
        }

    if convert_dir is None:
        convert_dir = CONVERT_DIR

    if not convert_dir.exists():
        return {"status": "error", "error": "Folder output belum ada"}

    try:
        # Cari semua PDF kecuali hasil merge sebelumnya
        all_pdfs = sorted(
            [p for p in convert_dir.rglob("*.pdf") if "Merged_Book" not in p.name],
            key=lambda x: x.name
        )

        if not all_pdfs:
            return {"status": "error", "error": "Tidak ada PDF untuk digabung"}

        writer = PdfWriter()
        count = 0
        skipped = []

        # Fix H7: Process PDFs one by one with explicit cleanup
        for i, pdf_path in enumerate(all_pdfs, 1):
            try:
                print(f"   Merging [{i}/{len(all_pdfs)}]: {pdf_path.name}")
                writer.append(pdf_path)
                count += 1

                # Fix H7: Cleanup memory every 10 files for large batches
                if i % 10 == 0:
                    import gc
                    gc.collect()

            except MemoryError:
                msg = f"Out of memory while processing {pdf_path.name}"
                skipped.append((pdf_path.name, msg))
                print(f"⚠️ Skip merge {pdf_path.name}: Out of memory")
                # Continue with next file instead of failing completely
                continue
            except Exception as e:
                skipped.append((pdf_path.name, str(e)))
                print(f"⚠️ Skip merge {pdf_path.name}: {e}")
                continue

        if count == 0:
            return {
                "status": "error",
                "error": "Gagal membaca semua PDF",
                "skipped": skipped
            }

        # Save merged file
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = output_filename_pattern.format(timestamp=timestamp)
        output_path = convert_dir / filename

        writer.write(output_path)
        writer.close()

        return {
            "status": "ok",
            "path": str(output_path.relative_to(BASE_DIR)) if BASE_DIR in output_path.parents else str(output_path),
            "filename": filename,
            "count": count,
            "skipped": skipped if skipped else None
        }

    except Exception as e:
        return {"status": "error", "error": str(e)}


def get_pdf_files(convert_dir=None):
    """
    List semua file PDF di folder convert

    Returns:
        list of dict dengan info file
    """
    if convert_dir is None:
        convert_dir = CONVERT_DIR

    if not convert_dir.exists():
        return []

    files = []
    all_pdfs = sorted(
        [p for p in convert_dir.rglob("*.pdf") if "Merged_Book" not in p.name],
        key=lambda x: x.stat().st_mtime,
        reverse=True
    )

    for path in all_pdfs:
        try:
            rel = path.relative_to(BASE_DIR) if BASE_DIR in path.parents else path
            label = path.relative_to(convert_dir).parts[0] if len(path.relative_to(convert_dir).parts) > 1 else "root"
            files.append({
                "name": path.name,
                "path": str(rel),
                "label": label,
                "size": path.stat().st_size,
                "modified": datetime.fromtimestamp(path.stat().st_mtime).isoformat()
            })
        except Exception:
            continue

    return files
