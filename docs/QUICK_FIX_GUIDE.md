# 🚀 QUICK FIX GUIDE - Audio Convert to TXT

## ⚡ MASALAH: Aplikasi Lemot / Stuck

### Solusi Cepat (Pilih 1):

#### 1️⃣ Ganti Model ke "medium" (RECOMMENDED)
```batch
set WHISPER_MODEL_SIZE=medium
python main.py
```

**Atau gunakan GUI:**
```batch
set_model_size.bat
# Pilih [3] medium
# Restart terminal
# Run python main.py
```

---

#### 2️⃣ Test GPU Dulu
```batch
test_gpu.bat
```

**Jika GPU test GAGAL:**
- Gunakan model `medium` atau `small`
- Atau force CPU mode (lihat bawah)

---

#### 3️⃣ Force CPU Mode (Stabil tapi lambat)
Edit `transcribe.py` baris 44-46:
```python
DEVICE = "cpu"      # ganti dari "cuda"
COMPUTE_TYPE = "int8"  # ganti dari "float16"
```

---

## 📊 PERFORMANCE COMPARISON

| Model Size | VRAM Needed | Speed | Accuracy | Recommended For |
|------------|-------------|-------|----------|-----------------|
| **tiny**   | 0.5 GB      | ⚡⚡ Fastest | ⭐ Low | Quick tests |
| **small**  | 1 GB        | ⚡⚡ Fast | ⭐⭐ Decent | Fast transcription |
| **medium** | 2 GB        | ⚡ Balanced | ⭐⭐⭐ Good | **MOST USERS** |
| **large-v3** | 4 GB      | ⚡ Slow | ⭐⭐⭐⭐ Best | High accuracy needs |

---

## 🔧 OPTIMIZATIONS APPLIED

### ✅ Fixed (Automatic):
1. **Translation 10x faster** - Batch processing (10 lines per API call)
2. **Folder scanning 5-10x faster** - Pattern-specific glob
3. **Glossary 5x faster** - Pre-compiled regex patterns
4. **File validation** - Skip missing files instead of crash
5. **GPU VRAM check** - Warn if model too large

### ⚠️ Manual Fixes Needed:
1. **server.py** - Job cache race condition (line 586)
2. **database.py** - Connection pool recovery (line 103)
3. **glossary_list.py** - Exception handling (line 145)

---

## 🎯 COMMON ISSUES

### Issue: "Stuck at Loading Model"
**Cause:** GPU loading timeout or VRAM insufficient

**Fix:**
```batch
# Use smaller model
set WHISPER_MODEL_SIZE=medium
python main.py
```

---

### Issue: "CUDA out of memory"
**Cause:** Model too large for GPU VRAM

**Fix:**
```batch
# Check GPU first
test_gpu.bat

# If VRAM < 4GB, use medium
set WHISPER_MODEL_SIZE=medium
```

---

### Issue: "Translation very slow"
**Cause:** Line-by-line API calls (OLD code)

**Fix:** ✅ Already fixed! Now uses batch processing (10x faster)

---

### Issue: "Folder scanning takes forever"
**Cause:** Scanning ALL files instead of just audio

**Fix:** ✅ Already fixed! Now uses pattern-specific glob (5-10x faster)

---

## 📝 COMMAND REFERENCE

### Set Model Size (Temporary)
```batch
set WHISPER_MODEL_SIZE=medium
python main.py
```

### Set Model Size (Permanent)
```batch
setx WHISPER_MODEL_SIZE medium
# Restart terminal
python main.py
```

### Check GPU Status
```batch
test_gpu.bat
```

### View Performance Report
```
Open: PERFORMANCE_OPTIMIZATION_REPORT.md
```

---

## 🎛️ MODEL SELECTION GUIDE

### Choose **tiny** if:
- You need FAST tests
- Accuracy not critical
- GPU VRAM < 1GB

### Choose **small** if:
- You want FAST transcription
- Good enough accuracy
- GPU VRAM 1-2GB

### Choose **medium** if: **(RECOMMENDED)**
- You want BALANCED speed & accuracy
- Good for Indonesian language
- GPU VRAM 2-4GB

### Choose **large-v3** if:
- You need BEST accuracy
- Speed not important
- GPU VRAM > 4GB

---

## 📈 EXPECTED PERFORMANCE

### Before Optimization:
```
76 files → 6-8 hours ❌
- Translation: 2-3 min/file
- Folder scan: 30 sec
- Model load: 3-5 min/file
```

### After Optimization:
```
76 files → 1-2 hours ✅
- Translation: 15-20 sec/file (10x faster)
- Folder scan: 3-5 sec (10x faster)
- Model load: ONCE per batch
```

---

## 🆘 EMERGENCY FIXES

### If App Crashes Immediately:
```batch
# Force CPU mode (slow but stable)
set WHISPER_MODEL_SIZE=tiny
set FORCE_CPU=1
python main.py
```

### If Translation Fails:
```batch
# Skip translation
# Edit transcribe.py, set do_translate = False
```

### If Folder Mode Fails:
```batch
# Use File Mode instead
python main.py
# Choose [2] or [3] for single/multiple files
```

---

## 📞 SUPPORT

### Check Logs:
```
output_log.txt - Application logs
```

### Debug Mode:
```batch
python debug.py
```

### System Requirements:
- Python 3.10+
- GPU: NVIDIA with 2GB+ VRAM (recommended)
- RAM: 8GB minimum
- Disk: 10GB free space

---

**Last Updated:** 2026-03-27
**Version:** 2.0 (Optimized)
