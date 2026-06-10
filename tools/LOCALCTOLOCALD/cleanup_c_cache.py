"""
Cleanup Old Cache di C:
Hapus cache HuggingFace lama setelah model berhasil dipindah ke D:
"""

import os
import shutil
from pathlib import Path

# Cache locations to clean
OLD_CACHE_PATHS = [
    Path(r"C:\Users\diofa\.cache\huggingface\hub\models--Systran--faster-whisper-large-v3"),
]

# PIP cache (optional, can be large)
PIP_CACHE = Path(r"C:\Users\diofa\AppData\Local\pip\Cache")

# Temp files
TEMP_DIR = Path(os.environ.get("TEMP", r"C:\Users\diofa\AppData\Local\Temp"))

print("="*70)
print("🧹 CLEANUP OLD CACHE DI C:")
print("="*70)

total_freed = 0

# 1. Clean HuggingFace model cache
print(f"\n📍 STEP 1: Clean HuggingFace model cache")
for cache_path in OLD_CACHE_PATHS:
    print(f"\n   Path: {cache_path}")

    if not cache_path.exists():
        print(f"   ⏭️  Not found (already clean)")
        continue

    # Calculate size
    try:
        size = sum(f.stat().st_size for f in cache_path.rglob('*') if f.is_file()) / (1024**3)
        print(f"   📊 Size: {size:.2f} GB")

        # Delete
        shutil.rmtree(str(cache_path))
        print(f"   ✅ DELETED! Freed {size:.2f} GB")
        total_freed += size
    except Exception as e:
        print(f"   ❌ Failed to delete: {e}")

# 2. Clean PIP cache
print(f"\n📍 STEP 2: Clean PIP cache")
if PIP_CACHE.exists():
    try:
        size = sum(f.stat().st_size for f in PIP_CACHE.rglob('*') if f.is_file()) / (1024**3)
        print(f"   📊 Size: {size:.2f} GB")

        # Option to delete
        choice = input(f"   🗑️  Delete PIP cache? (y/n): ").strip().lower()
        if choice == 'y':
            shutil.rmtree(str(PIP_CACHE))
            print(f"   ✅ DELETED! Freed {size:.2f} GB")
            total_freed += size
        else:
            print(f"   ⏭️  Skipped")
    except Exception as e:
        print(f"   ❌ Failed: {e}")
else:
    print(f"   ⏭️  Not found")

# 3. Clean Temp files
print(f"\n📍 STEP 3: Clean Temp files")
if TEMP_DIR.exists():
    try:
        # Count files
        temp_files = list(TEMP_DIR.glob('*'))
        print(f"   📊 Files: {len(temp_files):,}")

        # Calculate size (sample)
        sample_size = sum(f.stat().st_size for f in temp_files[:100] if f.is_file())
        estimated_size = (sample_size / 100) * len(temp_files) / (1024**3) if temp_files else 0
        print(f"   📊 Estimated size: {estimated_size:.2f} GB")

        choice = input(f"   🗑️  Delete temp files? (y/n): ").strip().lower()
        if choice == 'y':
            deleted = 0
            for f in temp_files:
                try:
                    if f.is_file():
                        f.unlink()
                        deleted += 1
                    elif f.is_dir():
                        shutil.rmtree(str(f), ignore_errors=True)
                        deleted += 1
                except:
                    pass
            print(f"   ✅ DELETED {deleted:,} files!")
            total_freed += estimated_size
        else:
            print(f"   ⏭️  Skipped")
    except Exception as e:
        print(f"   ❌ Failed: {e}")
else:
    print(f"   ⏭️  Not found")

# Summary
print(f"\n\n{'='*70}")
print("✅ CLEANUP COMPLETE!")
print(f"{'='*70}")
print(f"\n💾 Total space freed: ~{total_freed:.2f} GB")
print(f"\n💡 Tips:")
print(f"   • Model sekarang ada di D:\\model\\large-v3 (2.88 GB)")
print(f"   • Cache HuggingFace di D:\\model\\.cache\\huggingface")
print(f"   • C: drive sudah lebih lega!")
print(f"{'='*70}")
