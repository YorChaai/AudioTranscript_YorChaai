import sys
import warnings
from pathlib import Path

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

# Fix H3/H4: Import shared PDF utilities instead of duplicating code
from pdf_utils import txt_to_pdf
from config import BASE_DIR, CONVERT_DIR


def get_txt_files():
    """Recursively find .txt files in output folder."""
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

        # Fix M8: Track success/failure for batch PDF conversion
        success_count = 0
        fail_count = 0
        failed_files = []

        for p in parts:
            if p.isdigit():
                idx = int(p) - 1
                if 0 <= idx < len(files):
                    target = files[idx]
                    print(f"\n🔄 Converting: {target['name']}...")
                    if txt_to_pdf(target['path']):
                        success_count += 1
                    else:
                        fail_count += 1
                        failed_files.append(target['name'])

        # Summary
        print("\n" + "=" * 60)
        print(f"✅ Completed: {success_count} succeeded, {fail_count} failed")
        if failed_files:
            print("\n❌ Failed files:")
            for f in failed_files:
                print(f"   - {f}")
        print("=" * 60)

if __name__ == "__main__":
    main()
