"""
C: Drive Space Analyzer - Python, Models, Cache
Analisis file/folder di C: yang bisa dipindah ke D: untuk hemat space

Output: Laporan lengkap dengan rekomendasi aman/tidak untuk dipindah
"""

import os
import sys
from pathlib import Path
from datetime import datetime

# Configuration - what to scan
SCAN_PATHS = {
    "Python Installations": [
        r"C:\Users\diofa\AppData\Local\Programs\Python",
        r"C:\Python*",
    ],
    "Python Cache (pip)": [
        r"C:\Users\diofa\AppData\Local\pip\Cache",
    ],
    "HuggingFace Model Cache": [
        r"C:\Users\diofa\.cache\huggingface",
        r"C:\Users\diofa\.cache\huggingface\hub",
    ],
    "Python Packages (site-packages)": [
        r"C:\Users\diofa\AppData\Local\Programs\Python\Python311\Lib\site-packages",
        r"C:\Users\diofa\AppData\Local\Programs\Python\Python310\Lib\site-packages",
        r"C:\Users\diofa\AppData\Local\Programs\Python\Python312\Lib\site-packages",
    ],
    "Temp Files": [
        r"C:\Users\diofa\AppData\Local\Temp",
    ],
    "Python Bytecode Cache": [
        r"C:\Users\diofa\AppData\Local\Programs\Python\Python311\Lib\__pycache__",
        r"C:\Users\diofa\AppData\Local\Programs\Python\Python311\Lib\site-packages\__pycache__",
    ],
}

# Safe to move (will not affect performance)
SAFE_TO_MOVE = {
    "HuggingFace Model Cache": {
        "safe": True,
        "reason": "Model cache bisa di mana saja, performa SAMA (load ke RAM)",
        "how_to": "Set env var: HF_HUB_CACHE=D:\\model\\.cache\\huggingface",
    },
    "Python Cache (pip)": {
        "safe": True,
        "reason": "Cache download package, bisa dihapus kapan saja",
        "how_to": "pip cache purge (hapus semua), atau set PIP_CACHE_DIR=D:\\pip_cache",
    },
    "Temp Files": {
        "safe": True,
        "reason": "File sementara, aman dihapus",
        "how_to": "Disk Cleanup atau hapus manual %TEMP%",
    },
    "Python Bytecode Cache": {
        "safe": True,
        "reason": "Auto-generated .pyc files, tidak perlu dipindah (kecil)",
        "how_to": "Tidak perlu dipindah, auto-regenerate",
    },
}

# NOT safe to move (will break things)
NOT_SAFE_TO_MOVE = {
    "Python Installations": {
        "safe": False,
        "reason": "Python harus di C: agar PATH, registry, dan virtual env bekerja",
        "risk": "Bisa break semua script, pip, dan virtual environment",
        "alternative": "Uninstall Python di C:, install ulang di D: (tapi harus reinstall semua packages)",
    },
    "Python Packages (site-packages)": {
        "safe": False,
        "reason": "Package terikat dengan Python installation path",
        "risk": "Import akan gagal jika dipindah manual",
        "alternative": "Gunakan virtual environment di D: (venv di D:)",
    },
}


def get_folder_size(path_str):
    """Hitung ukuran folder (GB)"""
    try:
        path = Path(path_str)
        if not path.exists():
            return None, 0, 0

        total_size = 0
        file_count = 0
        folder_count = 0

        for item in path.rglob('*'):
            try:
                if item.is_file():
                    total_size += item.stat().st_size
                    file_count += 1
                elif item.is_dir():
                    folder_count += 1
            except (PermissionError, OSError):
                continue

        size_gb = total_size / (1024**3)
        return size_gb, file_count, folder_count
    except Exception as e:
        return None, 0, 0


def format_size(size_gb):
    """Format ukuran jadi human readable"""
    if size_gb < 0.001:
        return f"{size_gb * 1024 * 1024:.2f} KB"
    elif size_gb < 1:
        return f"{size_gb * 1024:.2f} MB"
    else:
        return f"{size_gb:.2f} GB"


def analyze_path(name, path, recommendation):
    """Analisis satu path"""
    print(f"\n{'='*70}")
    print(f"📁 {name}")
    print(f"   Path: {path}")
    print(f"{'='*70}")

    if not Path(path.replace('*', '')).exists():
        # Try glob for wildcard paths
        import glob
        matches = glob.glob(path)
        if not matches:
            print(f"   ⚠️  Tidak ditemukan")
            return None

        for match in matches:
            size_gb, files, folders = get_folder_size(match)
            if size_gb is not None:
                print(f"   📂 Found: {match}")
                print(f"   💾 Size: {format_size(size_gb)}")
                print(f"   📄 Files: {files:,} | 📁 Folders: {folders:,}")
                return size_gb
        return None

    size_gb, files, folders = get_folder_size(path)

    if size_gb is not None:
        print(f"   💾 Size: {format_size(size_gb)}")
        print(f"   📄 Files: {files:,} | 📁 Folders: {folders:,}")

        # Print recommendation
        if recommendation['safe']:
            print(f"   ✅ AMAN DIPINDAH KE D:")
            print(f"   📝 Alasan: {recommendation['reason']}")
            print(f"   🔧 Cara: {recommendation['how_to']}")
            print(f"   ⚡ Performa: SAMA (tidak ada penurunan)")
        else:
            print(f"   ❌ TIDAK DISARANKAN DIPINDAH")
            print(f"   📝 Alasan: {recommendation['reason']}")
            print(f"   ⚠️  Risiko: {recommendation['risk']}")
            print(f"   💡 Alternatif: {recommendation['alternative']}")

        return size_gb
    else:
        print(f"   ⚠️  Tidak bisa dibaca (permission error)")
        return None


def main():
    print("="*70)
    print("🔍 C: DRIVE SPACE ANALYZER")
    print("="*70)
    print(f"📅 Scan time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"💻 User: diofa")
    print("="*70)

    total_size = 0
    results = []

    # Scan all paths
    for category, paths in SCAN_PATHS.items():
        if category in SAFE_TO_MOVE:
            rec = SAFE_TO_MOVE[category]
        elif category in NOT_SAFE_TO_MOVE:
            rec = NOT_SAFE_TO_MOVE[category]
        else:
            rec = {"safe": True, "reason": "Unknown", "how_to": "Manual check"}

        for path in paths:
            size = analyze_path(category, path, rec)
            if size is not None:
                total_size += size
                results.append({
                    "category": category,
                    "path": path,
                    "size_gb": size,
                    "safe": rec['safe']
                })

    # Summary
    print(f"\n\n{'='*70}")
    print("📊 RINGKASAN")
    print(f"{'='*70}")

    safe_total = sum(r['size_gb'] for r in results if r['safe'])
    not_safe_total = sum(r['size_gb'] for r in results if not r['safe'])

    print(f"\n💾 TOTAL SPACE DI C: {format_size(total_size)}")
    print(f"\n✅ AMAN DIPINDAH: {format_size(safe_total)}")
    print(f"❌ TIDAK AMAN: {format_size(not_safe_total)}")

    # Detailed breakdown
    print(f"\n\n{'='*70}")
    print("📋 DETAIL PER KATEGORI")
    print(f"{'='*70}")

    for r in results:
        status = "✅ SAFE" if r['safe'] else "❌ NOT SAFE"
        print(f"   {r['category']}: {format_size(r['size_gb'])} [{status}]")

    # Recommendations
    print(f"\n\n{'='*70}")
    print("🎯 REKOMENDASI PRIORITAS")
    print(f"{'='*70}")

    print("""
1️⃣  **MODEL HUGGINGFACE** (Paling Besar & Aman)
    - Lokasi: C:\\Users\\diofa\\.cache\\huggingface
    - Bisa dipindah ke D:\\model\\.cache\\huggingface
    - Performa: SAMA PERSIS
    - Cara: Set env var HF_HUB_CACHE=D:\\cache\\huggingface

2️⃣  **PIP CACHE** (Aman, tapi kecil)
    - Lokasi: C:\\Users\\diofa\\AppData\\Local\\pip\\Cache
    - Bisa dihapus: pip cache purge
    - Atau dipindah: set PIP_CACHE_DIR=D:\\pip_cache

3️⃣  **TEMP FILES** (Aman dihapus)
    - Lokasi: C:\\Users\\diofa\\AppData\\Local\\Temp
    - Cara: Tekan Win+R → %TEMP% → hapus semua

4️⃣  **PYTHON INSTALLATION** (TIDAK AMAN dipindah)
    - Python HARUS di C: untuk PATH & registry
    - Alternatif: Uninstall dari C:, install di D:
    - Konsekuensi: Harus reinstall SEMUA packages

5️⃣  **VIRTUAL ENV DI D:** (Solusi Terbaik)
    - Buat venv di D: bukan di C:
    - python -m venv D:\\myproject\\venv
    - Semua packages akan di D: bukan C:
""")

    print(f"{'='*70}")
    print("✅ Analysis Complete!")
    print(f"{'='*70}")


if __name__ == "__main__":
    main()
