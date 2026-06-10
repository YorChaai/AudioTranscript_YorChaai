# 🚀 Aplikasi Flutter & API Server
**(Update Baru: UI Modern & Integrasi HP)**

Aplikasi ini sekarang memiliki antarmuka (UI) modern berbasis Flutter yang bisa dijalankan di **Laptop (Windows)** dan **HP (Android)**. Laptop bertindak sebagai server (pemroses audio), sedangkan HP dan Laptop bisa menjadi client.

---

## 🏗️ Cara Menjalankan (Step-by-Step)

### 1. Jalankan Server (Wajib di Laptop)
Server ini yang akan memproses transkripsi (menggunakan GPU Laptop).

1. Buka terminal di folder proyek ini (`audio convert to txt`).
2. Aktifkan virtual environment & jalankan server:
   ```powershell
   .\venv\Scripts\activate
   pip install -r requirements.txt  # (Jika belum install library)
   python server.py
   ```
3. Tunggu sampai muncul: `Running on http://0.0.0.0:5000`.
4. **Catat IP Address** laptop kamu yang muncul di terminal (contoh: `192.168.1.10` atau `192.168.68.61`).

---

### 2. Jalankan Aplikasi Client

Kamu bisa menjalankan aplikasi di Laptop (Windows) atau di HP (Android).

#### 💻 Di Laptop (Windows)
1. Buka terminal baru.
2. Masuk ke folder aplikasi Flutter:
   ```powershell
   cd flutter_app
   ```
3. Jalankan aplikasi:
   ```powershell
   flutter run -d windows
   ```
   *(Aplikasi akan otomatis connect ke `localhost:5000`)*.

#### 📱 Di HP (Android)
**Syarat:** HP dan Laptop harus konek ke **WiFi yang sama**.

1. Sambungkan HP ke laptop via kabel data (USB).
2. Pastikan **USB Debugging** aktif di HP.
3. Di terminal folder `flutter_app`, jalankan:
   ```powershell
   flutter run
   ```
   (Pilih device HP kamu jika diminta).
4. **Setting IP Server di HP:**
   - Setelah aplikasi terbuka di HP, kemungkinan statusnya **"Server Offline"** (merah).
   - Klik ikon **Settings** (gerigi) di pojok kiri bawah (atau di menu).
   - Masukkan **IP Address Laptop** yang tadi dicatat (langkah 1), contoh: `192.168.68.61`.
   - Port biarkan `5000`.
   - Klik **Simpan**.
   - Indikator harusnya berubah jadi hijau (**Online**).

---

## 🛠️ Fitur Baru
- **Transcribe**: Upload audio dari HP, proses di laptop, pantau progress real-time.
- **Editor**: Edit teks hasil transkripsi langsung di aplikasi.
- **PDF**: Convert hasil edit ke PDF.
- **File Browser**: Jelajahi dan download file hasil dari server ke HP.
- **History**: Lihat riwayat transkripsi sebelumnya.

---
---

# 📖 Panduan Script CLI (Manual)
*(Di bawah ini adalah panduan lama untuk penggunaan script manual tanpa aplikasi)*

## 🎤 Audio to Text Transcription

Mengubah file audio (MP3, WAV, dll) menjadi teks.

---

## 📋 Daftar Isi

1. [Cara Cepat (Quick Start)](#cara-cepat)
2. [Format Perintah](#format-perintah)
3. [Contoh Perintah](#contoh-perintah)
4. [Ambil Hasil](#ambil-hasil)

---

## Cara Cepat

Langsung copy-paste perintah ini di terminal PowerShell:

```powershell
cd "d:\2. Organize\1. Projects\audio convert to txt"
.\venv\Scripts\activate
pip install -r requirements.txt
```

---

## Format Perintah

```powershell
python transcribe.py <mode> <bahasa> [tr <bahasa_target>]
```

| Parameter | Pilihan | Penjelasan |
| :--- | :--- | :--- |
| **mode** | `single` | 1 file (akan diproses yang terakhir dipilih) |
| | `multiple` | Banyak file (tulis list angka dipisah koma) |
| | `folder` | Pilih folder → extract semua file di dalamnya (batch) |
| **bahasa** | `id` | Sumber suara: Indonesia |
| | `en` | Sumber suara: Inggris |
| | `ja` | Sumber suara: Jepang |
| | `auto` | Campur / Auto-detect |
| **[optional]** | `tr id` | Translate hasil ke Indonesia |
| | `tr en` | Translate hasil ke Inggris |

---

## Contoh Perintah

### Tanpa Translate

```powershell
# Audio Indonesian, 1 file
python transcribe.py single id

# Audio English, 1 file
python transcribe.py single en

# Audio Campur, 1 file
python transcribe.py single auto

# Audio Japanese, 1 file
python transcribe.py single ja

# Audio Indonesian, banyak file
python transcribe.py multiple id

# Audio English, banyak file
python transcribe.py multiple en

# Audio Japanese, banyak file
python transcribe.py multiple ja

# Audio Campur, banyak file
python transcribe.py multiple auto

# Process folder (semua file di dalam subfolder audio/)
python transcribe.py folder id

# Process folder, audio English
python transcribe.py folder en
```

### Dengan Translate

```powershell
# Audio English with translate id, 1 file
python transcribe.py single en tr id

# Audio English with translate id, banyak file
python transcribe.py multiple en tr id

# Folder mode with translate
python transcribe.py folder en tr id
```

---

## 🔍 Pencari Kata Baru (Glossary Suggester)

Alat ini membantu Anda mencari kata-kata teknis dalam transkrip yang belum ada di `glossary.json`.

```powershell
# Mode 1 File: Pilih satu file transkrip
python glossary_list.py single

# Mode Banyak File: Gabung beberapa file untuk analisa
python glossary_list.py multiple

# Mode Langsung
python glossary_list.py "path/to/file.txt"
```

---

## 🧠 Smart Summary (Ringkasan Otomatis)

Buat ringkasan cerdas dari hasil transkripsi menggunakan AI (Ollama). Fitur ini otomatis mendeteksi bahasa dan memastikan output ringkasan selalu dalam Bahasa Indonesia.

**Fitur Utama:**
- **Auto-Detect Language**: Membaca metadata file untuk tahu bahasa asli (ID/EN).
- **Auto-Translation**: Jika sumber English, otomatis diringkas ke Bahasa Indonesia.
- **Mindmap Visualization**: Membuat kode visualisasi struktur poin (Mermaid) di akhir ringkasan.

```powershell
# Mode 1 File
python summarytext.py single

# Mode Banyak File
python summarytext.py multiple
```

---

## 📄 Konverter PDF (TXT to PDF)

Ubah hasil transkrip menjadi PDF biar lebih rapi dan mudah dibaca/print. Output PDF akan muncul di folder yang sama dengan file TXT aslinya.

```powershell
# Mode 1 File
python convert_pdf.py single

# Mode Banyak File (Batch)
python convert_pdf.py multiple
```

---

## Ambil Hasil

Hasil transkripsi akan ada di folder `convert txt`.

1. **Mode Single**: `convert txt/single/`
2. **Mode Multiple**: `convert txt/multiple/batch_XXX/`

File output juga sudah diperbarui dengan format **Semikolon (;)** untuk memudahkan copy-paste ke Excel/Docs.

---

## 📁 Struktur Folder

```
audio convert to txt/
│
├── audio/                    ← TARUH AUDIO DI SINI
│   ├── (file audio)          ← untuk mode single/multiple
│   └── my_folder/            ← subfolder untuk mode folder
│       └── (file audio)
│
├── convert txt/              ← HASIL DI SINI
│   ├── single/
│   └── multiple/
│
├── transcribe.py             ← Script Convert Audio
├── glossary_list.py          ← Script Cari Kata
├── convert_pdf.py            ← Script PDF
├── requirements.txt          ← Daftar library
└── flutter_app/              ← APLIKASI FLUTTER (Baru)
```
