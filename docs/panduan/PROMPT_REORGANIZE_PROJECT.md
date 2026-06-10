#  Prompt Template: Reorganize Project Structure

Copy-paste prompt ini untuk reorganize project lain dengan cara yang sama.

---

## 📝 PROMPT TEMPLATE

```
Saya mau reorganize project ini biar lebih rapi. Ikuti instruksi ini:

## TUJUAN:
- Bersihkan root folder dari file berantakan
- Pindahkan file ke folder yang sesuai
- Fix semua import/path yang berubah
- Test tidak ada bug/error
- FILE TIDAK BOLEH DIHAPUS, cuma dipindahkan

## INSTRUKSI STEP BY STEP:

### STEP 1: ANALISIS STRUKTUR
- List semua file dan folder di root
- Identifikasi file mana yang:
  - Core scripts (Python/JS utama)
  - Scripts launcher (bat/ps1/sh)
  - Dokumen (md, txt, pdf reports)
  - Temporary/debug files
  - Config files
  - Binary files
- Buat plan reorganisasi lengkap

### STEP 2: BUAT FOLDER STRUKTUR BARU
Buat folder-folder ini di root project:
- `src/` - Semua core scripts (Python/JS utama)
- `scripts/` - Launcher & utility scripts (bat, ps1, sh)
- `docs/` - Semua dokumentasi (README, reports, md files)
- `tools/` - Migration & analysis tools
- `temp/` - Temporary & debug files
- `Sisa/` - BACKUP folder (file yang "harus dihapus" tapi DISIMPAN sebagai backup)
- `output/` atau `dist/` - Output files (jika ada)

### STEP 3: PINDAHKAN FILE (JANGAN HAPUS!)
**PENTING: Tidak ada file yang dihapus! Semua file cuma DIPINDAHKAN.**

- Core scripts → `src/`
- Launcher scripts (bat/ps1/sh) → `scripts/`
- Dokumen & reports → `docs/`
- Temporary files → `temp/`
- File yang "tidak terpakai" → `Sisa/` (BACKUP, jangan dihapus!)
- Tools/migration scripts → `tools/`

### STEP 4: UPDATE PATH & IMPORTS
Karena file dipindah, fix hal-hal ini:

**a. BASE_DIR / ROOT PATH:**
Di setiap file di `src/`, ubah:
```python
# SEBELUM (file di root):
BASE_DIR = Path(__file__).parent

# SESUDAH (file di src/):
BASE_DIR = Path(__file__).parent.parent  # Point ke project root
```

**b. Update semua path references:**
- Ganti semua `Path(__file__).parent` → `Path(__file__).parent.parent` di file `src/`
- Update path ke folder: `audio/`, `output/`, `assets/`, dll
- Update path `.env` loading: harus pakai `BASE_DIR / '.env'`
- Pastikan `.env` loading SETELAH `BASE_DIR` didefinisikan

**c. Update batch/PS1 scripts:**
- Fix path di `.bat` dan `.ps1` files di `scripts/`
- Update relative path ke `src/main.py` atau `src/server.py`

**d. Buat launcher baru di root:**
Buat `run.bat` (atau `run.sh` untuk Linux/Mac):
```bat
@echo off
cd /d "%~dp0"
cd src && python main.py
pause
```

### STEP 5: FIX BUG & ERROR
Test semua file:
```bash
# Test syntax semua Python files:
python -m py_compile src/main.py
python -m py_compile src/transcribe.py
# ... test semua file

# Test import semua module:
cd src
python -c "import main; print('main OK')"
python -c "import transcribe; print('transcribe OK')"
# ... test semua import

# Test BASE_DIR paths:
python -c "import transcribe; print(transcribe.BASE_DIR)"
python -c "import transcribe; assert transcribe.BASE_DIR.joinpath('audio').exists()"
```

### STEP 6: VERIFIKASI FINAL
- Cek tidak ada file yang terhapus (bandingkan jumlah file sebelum & sesudah)
- Semua file harus ada di folder baru atau di `Sisa/`
- Test full import semua module
- Cek `.env` loading berhasil
- Cek semua path folder exists (audio, output, assets, dll)

### STEP 7: UPDATE DOKUMENTASI
Update `docs/panduan/Panduanfull.md` atau README dengan:
- Struktur folder baru
- Cara run program
- Perubahan yang dilakukan
- Daftar file yang dipindah

## OUTPUT YANG DIHARAPKAN:

1. ✅ Struktur folder rapi (root cuma 4-5 file: `.env`, `.gitignore`, `requirements.txt`, `run.bat`)
2. ✅ Semua file dipindah, TIDAK ADA yang dihapus
3. ✅ Semua import berhasil, tidak ada error
4. ✅ BASE_DIR di semua file pointing ke project root
5. ✅ `.env` loading berhasil
6. ✅ Semua path folder exists
7. ✅ `run.bat` bisa double-click untuk jalankan program
8. ✅ Dokumentasi updated

## ATURAN PENTING:
- ❌ JANGAN PERNAH HAPUS FILE
- ✅ Selalu pindahkan ke `Sisa/` kalau file "tidak terpakai"
- ✅ Test setiap perubahan sebelum lanjut
- ✅ Fix semua import & path references
- ✅ Verifikasi tidak ada bug sebelum selesai
```

---

## 📌 CONTOH PENGGUNAAN:

### Untuk Project Python:
```
[Copy-paste prompt di atas]

Project location: D:\path\to\your\project
Core files: main.py, app.py, utils.py, dll
Launcher: start.bat, run.ps1
```

### Untuk Project Node.js:
```
[Copy-paste prompt di atas]

Ganti:
- `src/` → `src/` (sama)
- `scripts/` → `scripts/` (sama)
- `run.bat` → `run.cmd` atau `package.json` script
- Python imports → Node.js require/import paths
- `.env` loading → dotenv config
```

### Untuk Project lain:
Sesuaikan nama folder dan file sesuai project kamu.

---

## ✅ CHECKLIST SETELAH REORGANIZE:

- [ ] Root folder bersih (cuma 4-5 file)
- [ ] Semua core scripts di `src/`
- [ ] Semua launcher di `scripts/`
- [ ] Semua docs di `docs/`
- [ ] File backup di `Sisa/` (tidak ada yang dihapus)
- [ ] `BASE_DIR` / root path updated di semua file
- [ ] Semua import berhasil (tidak ada error)
- [ ] `.env` loading berhasil
- [ ] `run.bat` / launcher works
- [ ] Dokumentasi updated

---

**Last Updated:** April 13, 2026
**Used in:** audio-convert-to-txt project
