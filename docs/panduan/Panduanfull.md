# 📘 Panduan Lengkap - Audio Convert to TXT

---

## 📁 STRUKTUR PROJECT (UPDATED)

```
audio convert to txt/
│
├── .env                     ← Environment variables (model path, cache)
├── .gitignore               ← Git ignore rules
├── requirements.txt         ← Python dependencies
├── run.bat                  ← LAUNCHER UTAMA (double-click untuk run)
│
├── src/                     ← SEMUA CORE PYTHON SCRIPTS
│   ├── main.py              ← Master menu
│   ├── transcribe.py        ← Transkripsi audio ke text
│   ├── server.py            ← Flask API server
│   ├── convert_pdf.py       ← Convert TXT ke PDF
│   ├── pdf_utils.py         ← PDF utilities
│   ├── utils.py             ← Shared utilities (ffmpeg, dll)
│   ├── summarytext.py       ← Generate summary text
│   ├── database.py          ← Database connection
│   └── glossary_list.py     ← Glossary management
│
├── scripts/                 ← LAUNCHER & UTILITY SCRIPTS
│   ├── start_app.bat        ← Start server + tunnel
│   ├── start_tunnel.ps1     ← Cloudflare tunnel
│   ├── set_model_size.bat   ← Set model size env var
│   ├── test_gpu.bat         ← Test GPU availability
│   ├── install_ffmpeg.ps1   ← Install ffmpeg
│   ├── test_server_script.py← Server test script
│   └── cloudflared.exe      ← Cloudflare tunnel binary
│
├── docs/                    ← DOKUMENTASI
│   ├── README.md
│   ├── CODE_ANALYSIS_REPORT_2.md
│   ├── FINAL_OPTIMIZATION_REPORT.md
│   ├── OPTIMIZATION_SUMMARY.txt
│   ├── PERFORMANCE_OPTIMIZATION_REPORT.md
│   ├── QUICK_FIX_GUIDE.md
│   ├── IMPLEMENTATION_SUMMARY.md
│   └── panduan/
│       └── Panduanfull.md
│
├── tools/                   ← MIGRATION & ANALYSIS TOOLS
│   └── LOCALCTOLOCALD/
│       ├── analyzer.py
│       ├── cleanup_c_cache.py
│       ├── fix_model_structure.py
│       ├── migrate_model.py
│       └── main.py
│
├── temp/                    ← TEMPORARY/DEBUG FILES
│   ├── analyze_all.py
│   └── output_log.txt
│
├── assets/                  ← CONFIG FILES
│   ├── glossary.json
│   └── ignore_list.json
│
├── audio/                   ← INPUT AUDIO FILES
│
├── output/                  ← HASIL TRANSCRIBED (dulu: convert txt)
│   ├── single/
│   ├── multiple/
│   └── custom/
│
├── server/                  ← SERVER DATA (dulu: data)
│   └── uploads/
│
├── summary/                 ← SUMMARY FILES
│
├── Sisa/                    ← BACKUP FILE (tidak terpakai tapi disimpan)
│
├── flutter_app/             ← FLUTTER MOBILE APP (project terpisah)
│
├── venv/                    ← PYTHON VIRTUAL ENVIRONMENT
│
└── __pycache__/             ← PYTHON BYTECODE CACHE (auto-generated)
```

---

## 🚀 QUICK START

### Cara Jalankan Program:

**Opsi 1 - Double-click:**
```
Klik 2x run.bat
```

**Opsi 2 - Terminal:**
```bash
cd "D:\2. Organize\1. Projects\audio convert to txt"
cd src
python main.py
```

---

## 🎯 MAIN MENU

```
============================================================
        AUDIO CONVERT TO TXT - MASTER MENU        
============================================================

📁 CARA MEMILIH AUDIO:

  [1] 📂 FOLDER MODE
      → 4 cara pilih: list audio/, file explorer, input path, browse
      → Setelah pilih folder, bisa exclude file & proses semua
      → Support: audio + video files

  [2] 📄 FILE MODE - SINGLE
      → Pilih 1 file dari folder audio/
      → Output: flat di output/single/

  [3] 📄 FILE MODE - MULTIPLE
      → Pilih beberapa file dari folder audio/
      → Output: batch folder

  [4] 📝 Generate Summary Text
  [5] 📄 Convert TXT to PDF

  [0] Keluar
============================================================
```

---

## 📂 FOLDER MODE (Pilih [1])

### Step 1: Pilih Cara Input Folder

```
============================================================
📂 FOLDER MODE - Pilih Folder
============================================================

  [1] 📁 Pilih dari list folder dalam audio/
  [2] 📂 Pilih folder via File Explorer
  [3] 📄 Pilih file langsung via File Explorer (skip folder)
  [4] 📂 Input path folder manual (copy-paste)

  [0] Kembali
============================================================
```

### Penjelasan Setiap Opsi:

#### **[1] Pilih dari list folder dalam audio/**
- Menampilkan semua folder di dalam `audio/`
- User pilih nomor folder

#### **[2] Pilih folder via File Explorer**
- Buka dialog Windows untuk pilih folder

#### **[3] Pilih file langsung via File Explorer (skip folder)**
- Langsung pilih file tanpa lewat folder
- Cocok untuk user yang sudah tahu file mana yang mau diproses

#### **[4] Input path folder manual**
- Ketik/paste path folder secara manual

---

### Step 2: Pilih File yang Mau Diproses

```
📋 Pilih file yang akan diproses:

📂 Folder: Margin Call - Episode 1

--------------------------------------------------------------------
  [  1] 🎵 Margin Call Audio.mp3 (45.2 MB)
  [  2] 🎬 Margin Call Video.mp4 (120.5 MB)
--------------------------------------------------------------------

  a. 📂 Input path folder lain (ketik manual)
  b. 🔍 Pilih folder via File Explorer
  c. 📄 Pilih file langsung via File Explorer (skip list)
  d. 🚫 Pengecualian file (skip file tertentu)
  e. ✅ Proses semua file
  0. ❌ Kembali

Pilih nomor file (contoh: 1 atau 1,3,5 atau 2-6 atau all): _
```

### Cara Pilih File:

| Input | Artinya |
|-------|---------|
| `1` | Pilih file #1 saja |
| `1,3,5` | Pilih file #1, #3, #5 |
| `2-6` | Pilih file #2 sampai #6 |
| `all` | Pilih semua file |

### Opsi Tambahan (a-f):

| Opsi | Fungsi |
|------|--------|
| `a` | Input path folder lain |
| `b` | Browse folder via dialog |
| `c` | Pilih file langsung via Explorer |
| `d` | Exclude/skip file tertentu |
| `e` | Proses semua file |
| `0` | Kembali |

---

### Step 3: Pilih Bahasa Audio

```
Pilih Bahasa Audio Asli:
  [1] id (Indonesian)
  [2] en (English)
  [3] ja (Japanese)
  [4] auto (Auto-detect / Campuran)
Pilih (1/2/3/4): _
```

---

### Step 4: Proses Transkripsi

**Yang dilakukan:**
1. ✅ Load model dari `D:\model\large-v3` (2.88 GB)
2. 🔄 Convert video ke MP3 (kalau ada)
3. 🎤 Transkripsi setiap file
4. 💾 Simpan hasil ke `output/`

---

## 📄 SINGLE FILE MODE (Pilih [2])

```
📂 Files dalam audio/:
--------------------------------------------------------------------
  [  1] 🎵 podcast_ep1.mp3 (45.2 MB)
  [  2] 🎬 video_tutorial.mp4 (120.5 MB)
--------------------------------------------------------------------

Pilih nomor file (tepat 1): _
```

**Output:** `output/single/[nama_file].txt`

---

## 📄 MULTIPLE FILES MODE (Pilih [3])

```
📂 Files dalam audio/:
--------------------------------------------------------------------
  [  1] 🎵 podcast_ep1.mp3 (45.2 MB)
  [  2] 🎬 video_tutorial.mp4 (120.5 MB)
  [  3] 🎵 interview.wav (88.3 MB)
--------------------------------------------------------------------

Pilih nomor file (contoh: 1 atau 1,3,5 atau 2-6 atau all): _
```

**Output:** `output/multiple/batch_001/`

---

## ❌ CARA BATALKAN

| Di Step Mana | Cara Batal | Hasil |
|--------------|-----------|-------|
| **Main Menu** | Tekan `0` | Keluar |
| **Pilih folder** | Tekan `0` | Balik ke Main Menu |
| **Pilih file** | Tekan `0` | Balik ke pemilihan folder |
| **Saat transkripsi** | `Ctrl+C` | Force stop |

---

## ✅ HASIL BERHASIL

### Output Structure:

```
output/
├── single/              ← Hasil Single File mode
│   └── [nama_file].txt
│
├── multiple/            ← Hasil Multiple Files mode
│   └── batch_001/
│       ├── [file1].txt
│       └── [file2].txt
│
└── custom/              ← Hasil Folder mode
    └── [nama_folder]/
        ├── [file1].txt
        └── [file2].txt
```

---

## ⚙️ TECHNICAL INFO

### Model Location:
- **Path:** `D:\model\large-v3`
- **Size:** 2.88 GB

### Environment Variables (di .env):
```
WHISPER_MODEL_PATH=D:\model\large-v3
HF_HUB_CACHE=D:\model\.cache\huggingface
WHISPER_MODEL_SIZE=large-v3
```

### Supported Formats:
- **Audio:** `.mp3`, `.wav`, `.m4a`, `.flac`, `.ogg`, `.wma`, `.aac`
- **Video:** `.mp4`, `.mov`, `.mkv`, `.avi`, `.webm`, `.mpeg`, `.mpg`, `.m4v`

---

## 📝 REORGANIZATION NOTES

### Perubahan Struktur (April 2026):

| Sebelum | Sesudah |
|---------|---------|
| 29 file berantakan di root | 4 file saja (`.env`, `.gitignore`, `requirements.txt`, `run.bat`) |
| Python scripts di root | Semua di `src/` |
| Report files di root | Semua di `docs/` |
| Launcher scripts di root | Semua di `scripts/` |
| `convert txt/` | Rename jadi `output/` |
| `data/` | Rename jadi `server/` |
| File temporary di root | Semua di `temp/` |
| File tidak terpakai | Dipindah ke `Sisa/` (backup) |

### Benefit:
- ✅ Root folder bersih (cuma 4 file)
- ✅ Struktur jelas dan profesional
- ✅ Mudah cari file
- ✅ Flutter app tetap terpisah

---

**Last Updated:** April 13, 2026
