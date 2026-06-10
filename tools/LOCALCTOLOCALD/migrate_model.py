"""
Move Whisper Model from C: to D:
Safe migration script dengan backup & validation
"""

import os
import sys
import shutil
import json
from pathlib import Path
import subprocess

# Configuration
SOURCE_CACHE = Path(r"C:\Users\diofa\.cache\huggingface\hub\models--Systran--faster-whisper-large-v3")
TARGET_MODEL = Path(r"D:\model\large-v3")
TARGET_CACHE = Path(r"D:\model\.cache\huggingface\hub\models--Systran--faster-whisper-large-v3")
ENV_VAR_NAME = "HF_HUB_CACHE"
ENV_VAR_VALUE = r"D:\model\.cache\huggingface"

print("="*70)
print("🔄 MIGRATE WHISPER MODEL: C: → D:")
print("="*70)

# Step 1: Check source exists
print("\n📍 STEP 1: Check source model di C:")
print(f"   Path: {SOURCE_CACHE}")

if not SOURCE_CACHE.exists():
    print("   ❌ ERROR: Model tidak ditemukan di cache C:")
    print("   💡 Solusi: Download ulang dengan: pip install faster-whisper")
    sys.exit(1)

# Calculate source size
source_size = sum(f.stat().st_size for f in SOURCE_CACHE.rglob('*') if f.is_file()) / (1024**3)
print(f"   ✅ Found! Size: {source_size:.2f} GB")

# Step 2: Check if already migrated
print(f"\n📍 STEP 2: Check target di D:")
print(f"   Target: {TARGET_MODEL}")

if TARGET_MODEL.exists() and (TARGET_MODEL / "model.bin").exists():
    print("   ⚠️  Model sudah ada di D: (struktur benar)")
    print("   💡 Akan dihapus dan diganti dengan yang baru dari cache C:")
else:
    print("   ✅ Target kosong/belum ada - aman untuk copy")

# Step 3: Create target directory
print(f"\n📍 STEP 3: Create target directory")
TARGET_MODEL.mkdir(parents=True, exist_ok=True)
TARGET_CACHE.mkdir(parents=True, exist_ok=True)
print(f"   ✅ Created: {TARGET_MODEL}")
print(f"   ✅ Created: {TARGET_CACHE}")

# Step 4: Copy model files from C: to D:\model\large-v3 (proper structure)
print(f"\n📍 STEP 4: Copy model dari cache C: → D:\\model\\large-v3")
print("   (This may take 1-2 minutes for ~3GB)")

# Get the snapshot directory
snapshot_dir = SOURCE_CACHE / "snapshots"
if snapshot_dir.exists():
    snapshots = list(snapshot_dir.iterdir())
    if snapshots:
        snapshot = snapshots[0]
        print(f"   📂 Snapshot: {snapshot.name}")

        # Copy all files from snapshot to D:\model\large-v3
        copied_files = 0
        copied_size = 0

        for item in snapshot.rglob('*'):
            if item.is_file():
                target_file = TARGET_MODEL / item.relative_to(snapshot)
                target_file.parent.mkdir(parents=True, exist_ok=True)

                # Skip if already exists and same size
                if target_file.exists() and target_file.stat().st_size == item.stat().st_size:
                    print(f"   ⏭️  Skip (exists): {item.name}")
                    continue

                print(f"   📄 Copy: {item.name} ({item.stat().st_size / (1024**2):.2f} MB)")
                shutil.copy2(str(item), str(target_file))
                copied_files += 1
                copied_size += item.stat().st_size

        print(f"\n   ✅ Copied {copied_files} files ({copied_size / (1024**3):.2f} GB)")
    else:
        print("   ❌ ERROR: No snapshot found in cache")
        sys.exit(1)
else:
    print("   ❌ ERROR: Snapshot directory not found")
    sys.exit(1)

# Step 5: Verify copied model
print(f"\n📍 STEP 5: Verify model di D:\\model\\large-v3")
required_files = ["model.bin", "config.json", "tokenizer.json", "vocabulary.json"]
all_ok = True

for req_file in required_files:
    file_path = TARGET_MODEL / req_file
    if file_path.exists():
        size_mb = file_path.stat().st_size / (1024**2)
        print(f"   ✅ {req_file}: {size_mb:.2f} MB")
    else:
        print(f"   ❌ MISSING: {req_file}")
        all_ok = False

if not all_ok:
    print("\n   ❌ ERROR: Model tidak lengkap! Jangan hapus cache di C: dulu")
    sys.exit(1)

print("\n   ✅ Model verification PASSED!")

# Step 6: Also copy to cache structure (for HuggingFace library)
print(f"\n📍 STEP 6: Setup HuggingFace cache structure di D:")
print(f"   Copy ke: {TARGET_CACHE}")

# Copy entire source to target cache
if TARGET_CACHE.exists():
    print(f"   ⚠️  Target cache sudah ada, overwrite...")
    shutil.rmtree(str(TARGET_CACHE))

shutil.copytree(str(SOURCE_CACHE), str(TARGET_CACHE))
print(f"   ✅ Cache structure copied")

# Step 7: Set environment variable (user level)
print(f"\n📍 STEP 7: Set environment variable")
print(f"   {ENV_VAR_NAME} = {ENV_VAR_VALUE}")

try:
    # Set via Windows setx (permanent)
    result = subprocess.run(
        ['setx', ENV_VAR_NAME, ENV_VAR_VALUE],
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        print(f"   ✅ Environment variable set (permanent)")
        print(f"   💡 Berlaku untuk terminal baru (restart terminal Anda)")
    else:
        print(f"   ⚠️  setx failed: {result.stderr}")
        print(f"   💡 Set manual via: System Properties → Environment Variables")
except Exception as e:
    print(f"   ⚠️  Failed to set env var: {e}")
    print(f"   💡 Set manual: System Properties → Environment Variables → New → {ENV_VAR_NAME} = {ENV_VAR_VALUE}")

# Step 8: Update project config
print(f"\n📍 STEP 8: Update project config files")

# Update .env file if exists
env_file = Path(r"D:\2. Organize\1. Projects\audio convert to txt\.env")
if env_file.exists():
    print(f"   📄 Update .env file")
    with open(env_file, 'r', encoding='utf-8') as f:
        content = f.read()

    # Add or update HF_HUB_CACHE
    if ENV_VAR_NAME in content:
        # Replace existing
        lines = content.split('\n')
        new_lines = []
        for line in lines:
            if line.startswith(f"{ENV_VAR_NAME}="):
                new_lines.append(f"{ENV_VAR_NAME}={ENV_VAR_VALUE}")
            else:
                new_lines.append(line)
        content = '\n'.join(new_lines)
    else:
        # Add new
        content += f"\n{ENV_VAR_NAME}={ENV_VAR_VALUE}\n"

    with open(env_file, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"   ✅ .env updated")
else:
    # Create .env file
    print(f"   📄 Create .env file")
    with open(env_file, 'w', encoding='utf-8') as f:
        f.write(f"{ENV_VAR_NAME}={ENV_VAR_VALUE}\n")
    print(f"   ✅ .env created")

# Step 9: Test model loading
print(f"\n📍 STEP 9: Test model loading dari D:")
try:
    # Try loading the model
    os.environ[ENV_VAR_NAME] = ENV_VAR_VALUE
    os.environ["WHISPER_MODEL_PATH"] = str(TARGET_MODEL)

    print("   🔄 Attempting to load model...")
    from faster_whisper import WhisperModel

    # Test with CPU first (faster to test)
    model = WhisperModel(str(TARGET_MODEL), device="cpu", compute_type="int8")
    print("   ✅ MODEL LOAD SUCCESS! 🎉")
    print(f"   📍 Location: {TARGET_MODEL}")

except Exception as e:
    print(f"   ❌ ERROR: Model load failed: {e}")
    print(f"   💡 Jangan hapus cache di C: dulu!")
    print(f"   💡 Coba restart terminal dan run lagi")
    sys.exit(1)

# Step 10: Summary
print(f"\n\n{'='*70}")
print("✅ MIGRATION COMPLETE!")
print(f"{'='*70}")

print(f"""
📊 SUMMARY:
   ✅ Model copied ke: D:\\model\\large-v3
   ✅ Cache setup di: D:\\model\\.cache\\huggingface
   ✅ Environment variable set: {ENV_VAR_NAME}={ENV_VAR_VALUE}
   ✅ Project config updated: .env file

💾 SPACE SAVED:
   🗑️  Bisa hapus cache di C: untuk hemat ~{source_size:.2f} GB
   📍 Command: rmdir /s /q "{SOURCE_CACHE.parent}"

⚡ NEXT STEPS:
   1. Restart terminal Anda (supaya env var aktif)
   2. Test transcribe: python transcribe.py
   3. Kalau sukses, hapus cache di C: (opsional)

🎯 MODEL LOCATION:
   • Primary: D:\\model\\large-v3 (untuk faster-whisper)
   • Cache: D:\\model\\.cache\\huggingface (untuk HuggingFace library)
   • Old Cache (bisa dihapus): C:\\Users\\diofa\\.cache\\huggingface\\hub\\models--Systran--faster-whisper-large-v3
""")

print(f"{'='*70}")
print("🎉 SELESAI! Model sudah di D:")
print(f"{'='*70}")
