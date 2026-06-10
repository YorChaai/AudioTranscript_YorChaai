"""
Fix Model Migration - Simple Version
Copy model file from D:\model to proper structure
"""

import os
import shutil
from pathlib import Path

SOURCE_FILE = Path(r"D:\model\large-v3\69f74147e3334731bc3a76048724833325d2ec74642fb52620eda87352e3d4f1")
TARGET_MODEL_DIR = Path(r"D:\model\large-v3")
CACHE_BLOBS_DIR = Path(r"C:\Users\diofa\.cache\huggingface\hub\models--Systran--faster-whisper-large-v3\blobs")

print("="*70)
print("🔧 FIX MODEL STRUCTURE")
print("="*70)

# Step 1: Check source file
print(f"\n📍 STEP 1: Check source model file")
print(f"   Path: {SOURCE_FILE}")

if not SOURCE_FILE.exists():
    print(f"   ❌ File not found!")
    exit(1)

size_gb = SOURCE_FILE.stat().st_size / (1024**3)
print(f"   ✅ Found! Size: {size_gb:.2f} GB")

# Step 2: Copy to blobs folder in cache
print(f"\n📍 STEP 2: Copy to HuggingFace cache blobs")
print(f"   Target: {CACHE_BLOBS_DIR}")

CACHE_BLOBS_DIR.mkdir(parents=True, exist_ok=True)
target_blob = CACHE_BLOBS_DIR / SOURCE_FILE.name

if target_blob.exists():
    print(f"   ⏭️  Already exists, skip copy")
else:
    print(f"   📄 Copying ({size_gb:.2f} GB, ini akan memakan waktu...)")
    shutil.copy2(str(SOURCE_FILE), str(target_blob))
    print(f"   ✅ Copied to blobs folder")

# Step 3: Create proper model directory structure at D:\model\large-v3
print(f"\n📍 STEP 3: Create proper model structure at D:\\model\\large-v3")
TARGET_MODEL_DIR.mkdir(parents=True, exist_ok=True)

# Copy metadata files from snapshot
SNAPSHOT_DIR = Path(r"C:\Users\diofa\.cache\huggingface\hub\models--Systran--faster-whisper-large-v3\snapshots\edaa852ec7e145841d8ffdb056a99866b5f0a478")

metadata_files = ["config.json", "preprocessor_config.json", "tokenizer.json", "vocabulary.json"]
for meta_file in metadata_files:
    source = SNAPSHOT_DIR / meta_file
    target = TARGET_MODEL_DIR / meta_file

    if source.exists():
        if target.exists() and target.stat().st_size == source.stat().st_size:
            print(f"   ⏭️  Skip {meta_file} (exists)")
        else:
            shutil.copy2(str(source), str(target))
            print(f"   ✅ Copy {meta_file}")

# Create model.bin as copy (not symlink for portability)
model_bin_target = TARGET_MODEL_DIR / "model.bin"
if model_bin_target.exists():
    print(f"   ⏭️  Skip model.bin (exists)")
else:
    print(f"   📄 Copy model.bin ({size_gb:.2f} GB, ini akan memakan waktu...)")
    shutil.copy2(str(SOURCE_FILE), str(model_bin_target))
    print(f"   ✅ Created model.bin")

# Step 4: Verify structure
print(f"\n📍 STEP 4: Verify model structure")
required_files = ["model.bin", "config.json", "tokenizer.json", "vocabulary.json", "preprocessor_config.json"]
all_ok = True

for req_file in required_files:
    file_path = TARGET_MODEL_DIR / req_file
    if file_path.exists():
        size = file_path.stat().st_size
        if size > 1024**2:  # > 1MB
            print(f"   ✅ {req_file}: {size / (1024**3):.2f} GB")
        else:
            print(f"   ✅ {req_file}: {size / (1024**2):.2f} MB")
    else:
        print(f"   ❌ MISSING: {req_file}")
        all_ok = False

if not all_ok:
    print(f"\n   ❌ ERROR: Model structure incomplete!")
    exit(1)

print(f"\n   ✅ Model structure VALID!")

# Step 5: Set environment variables
print(f"\n📍 STEP 5: Set environment variables")

# For current session
os.environ["WHISPER_MODEL_PATH"] = str(TARGET_MODEL_DIR)
os.environ["HF_HUB_CACHE"] = r"D:\model\.cache\huggingface"

print(f"   ✅ WHISPER_MODEL_PATH = {TARGET_MODEL_DIR}")
print(f"   ✅ HF_HUB_CACHE = D:\\model\\.cache\\huggingface")

# Set permanent via setx
try:
    import subprocess
    subprocess.run(['setx', 'WHISPER_MODEL_PATH', str(TARGET_MODEL_DIR)], capture_output=True)
    subprocess.run(['setx', 'HF_HUB_CACHE', r'D:\model\.cache\huggingface'], capture_output=True)
    print(f"   ✅ Environment variables set (permanent, berlaku di terminal baru)")
except Exception as e:
    print(f"   ⚠️  Failed to set permanent: {e}")
    print(f"   💡 Set manual via System Properties → Environment Variables")

# Step 6: Create .env file
print(f"\n📍 STEP 6: Create .env file for project")
env_file = Path(r"D:\2. Organize\1. Projects\audio convert to txt\.env")
env_content = f"""# Environment Configuration - Auto-generated
# Whisper model location
WHISPER_MODEL_PATH={TARGET_MODEL_DIR}

# HuggingFace cache location
HF_HUB_CACHE=D:\\model\\.cache\\huggingface

# Model size (change if needed)
WHISPER_MODEL_SIZE=large-v3
"""

with open(env_file, 'w', encoding='utf-8') as f:
    f.write(env_content)

print(f"   ✅ Created: {env_file}")

# Summary
print(f"\n\n{'='*70}")
print("✅ MIGRATION SUCCESSFUL!")
print(f"{'='*70}")

print(f"""
📊 MODEL LOCATION:
   • Model: D:\\model\\large-v3
   • Structure: ✅ Complete (model.bin + metadata)
   • Size: {size_gb:.2f} GB

⚡ ENVIRONMENT VARIABLES:
   • WHISPER_MODEL_PATH = D:\\model\\large-v3
   • HF_HUB_CACHE = D:\\model\\.cache\\huggingface

🎯 NEXT STEPS:
   1. ✅ RESTART TERMINAL (supaya env var aktif)
   2. ✅ Test model load: python transcribe.py
   3. ✅ Kalau sukses, bisa hapus cache lama di C:

      rmdir /s /q "C:\\Users\\diofa\\.cache\\huggingface\\hub\\models--Systran--faster-whisper-large-v3"

💾 SPACE SAVINGS:
   • Model di D: ~{size_gb:.2f} GB
   • Bisa hapus cache di C: untuk hemat space
""")

print(f"{'='*70}")
print("🎉 DONE!")
print(f"{'='*70}")
