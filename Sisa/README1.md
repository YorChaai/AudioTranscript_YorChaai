📖 PANDUAN LENGKAP PENGGUNAAN APLIKASI

### 🎯 **MULAI DARI `main.py`**

---

## 1️⃣ **JALANKAN APLIKASI UTAMA**

```bash
python main.py
```

Kamu akan lihat menu utama:

```
==================================================
        AUDIO CONVERT TO TXT - MASTER MENU        
==================================================
Pilih menu yang ingin dijalankan:

  [1] 🎤 Transcribe Audio (transcribe.py)
  [2] 📝 Generate Summary Text (summarytext.py)
  [3] 📄 Convert TXT to PDF (convert_pdf.py)

  [0] Keluar
==================================================
Pilihan Anda: 
```

---

## 2️⃣ **MENU 1: TRANSCRIBE AUDIO (Ubah Suara ke Teks)**

### **Pilih Menu 1:**
```
Pilihan Anda: 1
```

### **Pilih Mode:**
```
----------------------------------------
🎤 TRANSCRIBE AUDIO
----------------------------------------
Pilih Mode:
  [1] Single (1 file)
  [2] Multiple (banyak file)
Pilih (1/2): 
```

**Penjelasan:**
- **[1] Single** → Proses 1 file audio saja
- **[2] Multiple** → Proses banyak file sekaligus

---

### **Pilih Bahasa:**
```
Pilih Bahasa Audio Asli:
  [1] id (Indonesian)
  [2] en (English)
  [3] ja (Japanese)
  [4] auto (Auto-detect / Campuran)
Pilih (1/2/3/4): 
```

**Penjelasan:**
- **[1] id** → Audio Bahasa Indonesia (lebih akurat)
- **[2] en** → Audio Bahasa Inggris (lebih akurat)
- **[3] ja** → Audio Bahasa Jepang
- **[4] auto** → Campuran/auto-detect (paling fleksibel)

---

### **Pilih Sumber Audio:**

Setelah pilih bahasa, sistem akan tanya:

```
==================================================
📁 PILIH SUMBER AUDIO
==================================================
Pilih dari folder? (1 = Ya, 0 = Tidak): 
```

#### **Opsi A: Pilih File Langsung (tekan 0)**

```
Pilih dari folder? (1 = Ya, 0 = Tidak): 0
```

**Jika pilih SINGLE:**
```
📂 Files in audio/ (5 files):
--------------------------------------------------
  [1] meeting1.mp3 (15.2 MB)
  [2] interview.wav (23.4 MB)
  [3] podcast.m4a (45.1 MB)
  [4] recording.mp3 (12.8 MB)
  [5] lecture.wav (67.3 MB)
--------------------------------------------------

📝 Mode: SINGLE (hanya file terakhir yang diproses)
Pilih nomor (contoh: 1 atau 1,2,3 - terakhir diambil): 3
```

**Jika pilih MULTIPLE:**
```
📂 Files in audio/ (5 files):
--------------------------------------------------
  [1] meeting1.mp3 (15.2 MB)
  [2] interview.wav (23.4 MB)
  [3] podcast.m4a (45.1 MB)
  [4] recording.mp3 (12.8 MB)
  [5] lecture.wav (67.3 MB)
--------------------------------------------------

📝 Mode: MULTIPLE (semua yang dipilih diproses)
Pilih nomor (pisah koma, contoh: 1,3,4,5): 1,3,5
```

---

#### **Opsi B: Pilih Folder (tekan 1)**

```
Pilih dari folder? (1 = Ya, 0 = Tidak): 1
```

Akan muncul pilihan mode folder:

```
==================================================
📁 PILIH MODE FOLDER
==================================================
  [1] Single Folder (1 folder saja, output flat)
  [2] Multiple Folders (pilih beberapa folder, struktur terjaga)

  [0] Kembali
==================================================
Pilihan Anda: 
```

**[1] Single Folder:**
- Pilih 1 folder
- Semua file di folder tersebut diproses
- Output disimpan flat (tidak ada subfolder)

**[2] Multiple Folders (BARU!):**
```
📂 Semua Folder dalam audio/ (6 folders):
----------------------------------------------------------------------
  [1] asonis (8 audio files)
    [2] asonis/folder1 (3 audio files)
    [3] asonis/folder2 (2 audio files)
    [4] asonis/folder3 (3 audio files)
  [5] meetings (5 audio files)
  [6] interviews (4 audio files)
----------------------------------------------------------------------
  [0] ✅ Selesai memilih dan mulai proses
----------------------------------------------------------------------

Pilih nomor folder (atau 0 untuk selesai): 2
✓ Folder 'folder1' dipilih

Pilih nomor folder (atau 0 untuk selesai): 3
✓ Folder 'folder2' dipilih

Pilih nomor folder (atau 0 untuk selesai): 0
```

**Fitur Khusus Multiple Folders:**
- ✅ Pilih banyak folder sekaligus
- ✅ Tekan nomor untuk pilih/batal
- ✅ Tekan **0** untuk selesai
- ✅ Output mengikuti struktur folder asli
- ✅ Folder kosong tetap dibuat dengan marker

---

### **Proses Transkripsi:**

Sistem akan memproses:

```
🔄 Loading model 'large-v3'...
   (Download pertama kali bisa lama ~3GB)
✅ Model loaded!

[1/3] Processing: audio1.mp3
🎤 Transcribing: audio1.mp3
   Language mode: Indonesian
   00:45|████████████████████| 245s/245s [04:05<00:00]
   Detected/Used: id (98.5%)
💾 Saved: audio1_transcript_20260327_143022.txt

[2/3] Processing: audio2.mp3
...
```

---

### **Convert ke PDF (Opsional):**

Setelah selesai transkripsi:

```
--------------------------------------------------
📄 PDF Conversion
Convert to PDF? (1 = Yes, 0 = No): 1

🔄 Generating PDFs...
   ✅ Saved: audio1_transcript_20260327_143022.pdf

✨ All PDF tasks completed.
```

---

## 3️⃣ **MENU 2: GENERATE SUMMARY TEXT (Ringkasan AI)**

### **Pilih Menu 2:**
```
Pilihan Anda: 2
```

### **Pilih Mode:**
```
----------------------------------------
📝 GENERATE SUMMARY TEXT
----------------------------------------
Pilih Mode:
  [1] Single (1 file)
  [2] Multiple (banyak file)
Pilih (1/2): 1
```

### **Pilih File Transcript:**
```
📂 Files found (15 files):
  [1] single/meeting_transcript_20260327_143022.txt
  [2] multiple/batch_001/interview_transcript.txt
  [3] multiple/asonis/folder1/audio1_transcript.txt
  ...

Pilih nomor file (contoh: 1): 1
```

### **Pilih Model AI:**
```
🤖 Pilih Model Summary:
  [1] Qwen 2.5 72B (Raja - Akurasi Tertinggi)
  [2] Qwen 2.5 32B (Pintar & Cepat)
  [3] Qwen 3 30B (Terbaru & Cepat)
  [4] Qwen 3 8B (Ringan & Akurat - Rekomendasi)
  [5] Qwen 2.5 14B (Balance Terbaik - 32GB RAM)
  [6] Qwen 2.5 7B (Paling Ringan)
  [7] Llama 3.1 70B (Raja Inggris)
  [8] Gemma 2 27B (Logika Google)

Pilih nomor (1-7, Default=1): 4
```

### **Proses Summary:**
```
🚀 Memulai proses ringkasan untuk 1 file...

📄 Memproses: single/meeting_transcript_20260327_143022.txt
   ℹ️  Bahasa terdeteksi: ID (Bahasa Indonesia)
   ⏳ Merangkas dengan qwen3:8b...
   ✅ Ringkasan berhasil disimpan ke file!

✨ Selesai!
```

**Output:** `summary/single/meeting_summary.md`

---

## 4️⃣ **MENU 3: CONVERT TXT TO PDF**

### **Pilih Menu 3:**
```
Pilihan Anda: 3
```

### **Pilih Mode:**
```
----------------------------------------
📄 CONVERT TXT TO PDF
----------------------------------------
Pilih Mode:
  [1] Single (1 file)
  [2] Multiple (banyak file)
Pilih (1/2): 1
```

### **Pilih File:**
```
------------------------------------------------------------
[1] meeting_transcript_20260327_143022.txt (single) - 45.2 KB
[2] interview_transcript.txt (multiple/batch_001) - 67.8 KB
[3] audio1_transcript.txt (asonis/folder1) - 34.5 KB
------------------------------------------------------------
Pilih nomor (contoh: 1 atau 1,3): 1

🔄 Converting: meeting_transcript_20260327_143022.txt ...
   🔤 Using Unicode font: UnicodeSans
   ✅ Saved: meeting_transcript_20260327_143022.pdf
```

---

## 📁 **STRUKTUR FOLDER**

```
audio convert to txt/
├── audio/                      # ← TARUH FILE AUDIO DI SINI
│   ├── meeting1.mp3
│   ├── interview.wav
│   └── asonis/
│       ├── folder1/
│       │   └── audio1.mp3
│       └── folder2/
│           └── audio2.mp3
│
├── convert txt/                # ← HASIL TRANSCRIPT
│   ├── single/
│   │   └── meeting_transcript.txt
│   └── multiple/
│       ├── batch_001/
│       │   └── interview_transcript.txt
│       └── asonis/
│           ├── folder1/
│           │   └── audio1_transcript.txt
│           └── folder2/
│               └── audio2_transcript.txt
│
├── summary/                    # ← HASIL SUMMARY AI
│   └── single/
│       └── meeting_summary.md
│
└── main.py                     # ← JALANKAN DARI SINI
```

---

## 🎯 **CONTOH WORKFLOW LENGKAP**

### **Skenario: Transkripsi Meeting dengan Struktur Folder**

1. **Taruh file audio:**
   ```
   audio/asonis/folder1/meeting1.mp3
   audio/asonis/folder2/meeting2.mp3
   ```

2. **Jalankan main.py:**
   ```bash
   python main.py
   ```

3. **Pilih menu:**
   ```
   Pilihan Anda: 1  (Transcribe)
   ```

4. **Pilih mode:**
   ```
   Pilih (1/2): 2  (Multiple)
   ```

5. **Pilih bahasa:**
   ```
   Pilih (1/2/3/4): 1  (Indonesian)
   ```

6. **Pilih dari folder:**
   ```
   Pilih dari folder? (1 = Ya, 0 = Tidak): 1
   ```

7. **Pilih mode folder:**
   ```
   Pilihan Anda: 2  (Multiple Folders)
   ```

8. **Pilih folder:**
   ```
   [1] asonis (2 audio files)
     [2] asonis/folder1 (1 audio files)
     [3] asonis/folder2 (1 audio files)
   
   Pilih nomor folder (atau 0 untuk selesai): 2
   ✓ Folder 'folder1' dipilih
   
   Pilih nomor folder (atau 0 untuk selesai): 3
   ✓ Folder 'folder2' dipilih
   
   Pilih nomor folder (atau 0 untuk selesai): 0
   ```

9. **Konfirmasi:**
   ```
   📋 RINGKASAN SEBELUM PROSES
   ======================================================================
   📂 Folder terpilih: 2
      - asonis/folder1 (1 file)
      - asonis/folder2 (1 file)
   
   🎵 Total file audio: 2
   📁 Output: convert txt/multiple/asonis/...
   ======================================================================
   
   Lanjutkan proses? (Enter = Ya, 'n' = Batal): [Enter]
   ```

10. **Proses:**
    ```
    [1/2] Processing: meeting1.mp3
    🎤 Transcribing: meeting1.mp3
    ...
    💾 Saved: convert txt/multiple/asonis/folder1/meeting1_transcript_....txt
    
    [2/2] Processing: meeting2.mp3
    ...
    💾 Saved: convert txt/multiple/asonis/folder2/meeting2_transcript_....txt
    
    ✅ Folder processing complete!
       Folder diproses: 2
       File diproses: 2
    ```

11. **Convert PDF (opsional):**
    ```
    Convert to PDF? (1 = Yes, 0 = No): 1
    ```

12. **Hasil akhir:**
    ```
    convert txt/multiple/asonis/
    ├── folder1/
    │   ├── meeting1_transcript_20260327_143022.txt
    │   └── meeting1_transcript_20260327_143022.pdf
    └── folder2/
        ├── meeting2_transcript_20260327_143022.txt
        └── meeting2_transcript_20260327_143022.pdf
    ```

---

## ⚡ **TIPS & TRICKS**

### **1. Model Loading Pertama Kali**
- Download pertama: **~3GB** (bisa 10-30 menit)
- Setelah itu: **~5 detik** (cached)

### **2. Pilih Bahasa yang Tepat**
- Audio Indonesia → pilih **[1] id** (lebih akurat)
- Audio Inggris → pilih **[2] en** (lebih akurat)
- Campuran → pilih **[4] auto**

### **3. Mode Folder vs File**
- File sedikit → pilih file langsung
- Banyak file terstruktur → pilih folder mode

### **4. Multiple Folders**
- Bisa pilih/batal dengan tekan nomor yang sama
- Tekan **0** untuk selesai
- Struktur folder terjaga di output

### **5. Translation**
- Otomatis translate ke Indonesia jika audio bukan Indonesia
- Glossary istilah teknis sudah included

---

## 🐛 **TROUBLESHOOTING**

### **Error: "Tidak ada file audio"**
```
❌ Tidak ada file audio di: D:\...\audio
```
**Solusi:** Taruh file MP3/WAV di folder `audio/`

---

### **Error: "Model tidak ditemukan"**
```
❌ Error: Model file not found
```
**Solusi:** Tunggu download selesai (pertama kali)

---

### **Error: "Ollama tidak jalan"**
```
❌ Error Ollama: Connection error
```
**Solusi:** Jalankan Ollama dulu:
```bash
ollama serve
```

---

### **Error: "PDF gagal convert"**
```
⚠️ Unicode font tidak ditemukan
```
**Solusi:** Install font Arial atau Malgun Gothic

---

## 📞 **BANTUAN LEBIH LANJUT**

Kalau ada error atau bingung, kasih tau saya:
1. Screenshot error
2. Langkah yang dilakukan
3. Output yang diharapkan

Saya bantu fix! 🚀