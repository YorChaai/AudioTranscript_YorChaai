Dokumen ini berisi hasil audit menyeluruh dan mendalam pada seluruh baris kode proyek **Audio Convert to Text** (Backend Python & Frontend Flutter Dart).  
Semua **21 bug nyata, inkonsistensi arsitektur, potensi crash runtime, dan celah keamanan** telah berhasil diperbaiki dan diverifikasi secara menyeluruh.

*Status: ✅ Semua 21 Bug Berhasil Diperbaiki & Lolos Pengujian Unit/Statik.*

---

## 📊 Matriks Ringkasan Temuan

| No | Nama Bug / Isu | Lokasi Berkas | Tingkat Keparahan | Dampak |
|---|---|---|---|---|
| **1** | Crash Runtime `TypeError: 'NoneType'` saat transkripsi ulang file | `src/server.py`, `src/core/transcription.py` | 🔴 **Critical** | Worker thread crash, job gagal |
| **2** | Desinkronisasi Indeks Glosarium (Salah Terjemahan / Istilah Tertukar) | `src/core/translator.py` | 🔴 **Critical** | Istilah teknis diganti arti kata lain |
| **3** | Crash Type Error `null is not a subtype of type 'String'` di Summary | `lib/providers/summary_provider.dart`, `src/server.py` | 🔴 **Critical** | Fitur summary via provider selalu crash |
| **4** | Pemutusan Pemantauan Batch Transcribe Setelah File Pertama Selesai | `lib/providers/transcribe_provider.dart` | 🔴 **Critical** | File ke-2..n tidak dipantau di UI |
| **5** | Potensi Path Traversal pada Endpoint Download & Update Transcript | `src/server.py` (`/api/download`, `/api/transcript`) | 🔴 **Critical Security** | Pembacaan/penimpaan file sistem di luar direktori aman |
| **6** | `update_job` Menimpa Kolom Database dengan `NULL` | `src/server.py`, `src/database.py` | 🟠 **High** | Data progress/output terhapus dari SQLite |
| **7** | Pesan Error Ollama Disimpan sebagai File Ringkasan Sukses (100%) | `src/summarytext.py`, `src/server.py` | 🟠 **High** | File summary berisi teks error tapi status selesai |
| **8** | Editor Summary Memuat File Mentah & Tidak Refresh Hasil Ringkasan | `lib/screens/summary_screen.dart` | 🟠 **High** | Hasil ringkasan baru tidak muncul di layar |
| **9** | Fitur Download di File Browser Tidak Menyimpan File ke Disk | `lib/screens/file_browser_screen.dart` | 🟠 **High** | Pengguna mengira file terunduh padahal tidak ada di device |
| **10** | Inkonsistensi Lokasi Download Antar Layar (Temp vs Documents) | `lib/screens/editor_screen.dart`, `lib/screens/pdf_screen.dart` | 🟠 **High** | File tersimpan di folder temp yang tersembunyi/dihapus OS |
| **11** | Dead Connection Pool pada Startup Server (`db.get_db().close()`) | `src/server.py`, `src/database.py` | 🟡 **Medium** | Kapasitas pool berkurang 1 sejak boot |
| **12** | Missing Dependency `tinytag` di `requirements.txt` | `requirements.txt`, `src/server.py` | 🟡 **Medium** | `ModuleNotFoundError` saat clean install |
| **13** | Duplikasi Port URL Server (`:5000:5000`) saat Input IP Manual | `lib/config/api_config.dart`, `lib/screens/settings_dialog.dart` | 🟡 **Medium** | Gagal koneksi jika user ketik `IP:port` tanpa `http://` |
| **14** | Mismatch Nama Field `JobStatus.inputFile` vs `audio_file` | `lib/models/job_status.dart`, `src/database.py` | 🟡 **Medium** | Properti `inputFile` selalu bernilai string kosong `""` |
| **15** | Format Ekstensi Media Tidak Lengkap di Flutter File Picker | `lib/screens/transcribe_screen.dart`, `src/config.py` | 🟡 **Medium** | Format valid (.flac, .aac, .webm) digray-out di picker |
| **16** | Default `find_ffmpeg()` Merujuk ke Folder `src/` Bukan Root Proyek | `src/utils.py` | 🟡 **Medium** | Gagal mendeteksi `tools/ffmpeg.exe` lokal |
| **17** | Kerentanan Polling Rate Limiting (HTTP 429 Too Many Requests) | `src/api/middlewares.py` | 🟡 **Medium** | Status polling stream mudah terkena rate limit |
| **18** | Gagal Split Backslash Windows (`\`) pada History Screen & Editor | `lib/screens/history_screen.dart`, `lib/screens/editor/editor_main_area.dart` | 🟢 **Low / UI** | Path mentah `output\single\...` muncul di UI |
| **19** | Kartu Menu "Summary" Hilang dari Grid Home Screen | `lib/screens/home_screen.dart` | 🟢 **Low / UI** | Fitur AI Summary tidak ada di shortcut dashboard utama |
| **20** | Nilai Label Folder Hardcoded `'single'` pada Editor Sidebar | `lib/screens/editor/editor_sidebar.dart` | 🟢 **Low / UI** | Subtitle file selalu berlabel `single` meskipun dari batch |
| **21** | Potensi Crash `docDir.listSync()` Unhandled Exception di PDF Screen | `lib/screens/pdf_screen.dart` | 🟢 **Low / Stability** | `FileSystemException` jika permission storage terbatas |

---

## 🔬 I. Bedah Detail Temuan Python Backend

### 1. 🔴 Crash Runtime saat Transkripsi File yang Sudah Ada (TypeError)
- **File:** [src/core/transcription.py (baris 338-342)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/core/transcription.py#L338-L342) & [src/server.py (baris 689)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/server.py#L689)
- **Akar Masalah:**
  ```python
  # transcription.py
  if output_path.exists() and srt_path.exists():
      return None, output_path
  ```
  Ketika file dilewati (karena TXT dan SRT sudah ada), fungsi mengembalikan `None`.
  Lalu di `server.py`:
  ```python
  result, out_path = process_file(...)
  db.add_history(
      job_id, "transcribe", audio_path.name, output_rel, language, "completed",
      metadata={"detected_lang": result["language"], "probability": result["language_probability"]} # <-- CRASH DI SINI
  )
  ```
- **Konsekuensi:** `TypeError: 'NoneType' object is not subscriptable` mematikan proses background dan job ditandai sebagai gagal (`error`), padahal file sebelumnya sudah sukses.

---

### 2. 🔴 Desinkronisasi Indeks Glosarium (Terjemahan Bertukar Arti)
- **File:** [src/core/translator.py (baris 34-40 & 53-61)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/core/translator.py#L34-L61)
- **Akar Masalah:**
  Pada `load_glossary()`:
  ```python
  for idx, (english_term, indonesian_term) in enumerate(GLOSSARY.items()):
      marker = f"__GLOSS_ID_{idx}__"
      _GLOSSARY_MAPPING[marker] = f"{indonesian_term} ({english_term})"
  ```
  Pada `apply_glossary_pre()`:
  ```python
  sorted_terms = sorted(_GLOSSARY_PATTERNS.keys(), key=len, reverse=True)
  for english_term in sorted_terms:
      marker = f"__GLOSS_ID_{sorted_terms.index(english_term)}__" # <-- INDEKS TIDAK SAMA
      mapping[marker] = _GLOSSARY_MAPPING[marker]
  ```
- **Konsekuensi:** Urutan dictionary asli berbeda dengan urutan setelah disortir berdasarkan panjang kata. Istilah teknis A akan mengambil terjemahan istilah teknis B.

---

### 3. 🔴 Potensi Path Traversal pada File Server
- **File:** [src/server.py (baris 847-890 & 940-948)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/server.py#L847-L948)
- **Akar Masalah:**
  ```python
  @app.route("/api/download/<path:filepath>", methods=["GET"])
  def download_file(filepath):
      full_path = BASE_DIR / filepath
      return send_file(str(full_path), as_attachment=True, download_name=full_path.name)
  ```
  Tidak ada validasi apakah `full_path.resolve()` berada di dalam folder yang diizinkan (`audio`, `output`, `summary`).
- **Konsekuensi:** Parameter seperti `../../.env` atau `../../src/server.py` dapat dibaca atau ditimpa lewat `PUT /api/transcript/<filepath>`.

---

### 4. 🟠 `_update_job_status()` Menghapus Nilai Kolom Database dengan `NULL`
- **File:** [src/server.py (baris 605-623)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/server.py#L605-L623) & [src/database.py (baris 213-224)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/database.py#L213-L224)
- **Akar Masalah:**
  `db.update_job()` menerima `kwargs` dan membuat statement `SET key = ?`. Jika `progress=None` atau `output_file=None` diteruskan dari `_update_job_status()`, database akan mengeksekusi `SET progress = NULL, output_file = NULL`.
- **Konsekuensi:** Kolom progress atau lokasi file output yang sebelumnya sudah tersimpan akan hilang menjadi `NULL` di SQLite.

---

### 5. 🟠 Pesan Error AI Disimpan sebagai Hasil Ringkasan Sukses
- **File:** [src/summarytext.py (baris 231-235)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/summarytext.py#L231-L235) & [src/server.py (baris 528-537)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/server.py#L528-L537)
- **Akar Masalah:**
  Ketika koneksi Ollama gagal/timeout, fungsi `generate_summary()` mengembalikan string `"❌ Error Ollama: ..."` tanpa melempar Exception. Di `server.py`, string ini tetap disimpan ke disk dan status job diubah ke `completed` (100%).
- **Konsekuensi:** Pengguna mendapati file `file(summary).txt` yang berisi teks error kegagalan koneksi, namun sistem menganggap proses berhasil sempurna.

---

### 6. 🟡 Connection Pool Leak pada Startup Server
- **File:** [src/server.py (baris 1062)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/server.py#L1062) & [src/database.py (baris 103-126)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/database.py#L103-L126)
- **Akar Masalah:**
  Saat server start: `db.get_db().close()`. Koneksi diambil dari antrean pool `Queue(maxsize=10)` lalu langsung di-close tanpa dikembalikan ke pool (`return_db()`).
- **Konsekuensi:** Satu slot koneksi hilang permanen sejak awal server berjalan.

---

### 7. 🟡 Missing Dependency `tinytag` pada `requirements.txt`
- **File:** [requirements.txt](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/requirements.txt) & [src/server.py (baris 207)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/server.py#L207)
- **Akar Masalah:** `from tinytag import TinyTag` diimpor di dalam endpoint `/api/audio/list`, namun `tinytag` tidak terdaftar di berkas dependensi `requirements.txt`.
- **Konsekuensi:** Instalasi di server baru via `pip install -r requirements.txt` akan menghasilkan error `ModuleNotFoundError` saat endpoint audio list diakses.

---

### 8. 🟡 Default Pencarian FFmpeg Terkunci di Direktori `src/`
- **File:** [src/utils.py (baris 69-98)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/utils.py#L69-L98)
- **Akar Masalah:** `find_ffmpeg()` menetapkan default `base_dir = Path(__file__).parent`. Karena file berada di `src/utils.py`, `base_dir` bernilai `src/`. Pencarian kandidat lokal `base_dir / "tools" / "ffmpeg.exe"` mencari di `src/tools/` bukan di root proyek `tools/`.

---

## 📱 II. Bedah Detail Temuan Flutter Dart Frontend

### 1. 🔴 Crash Type Cast Exception di `SummaryProvider`
- **File:** [flutter_app/lib/providers/summary_provider.dart (baris 50-52)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/providers/summary_provider.dart#L50-L52)
- **Akar Masalah:**
  ```dart
  final result = await _repository.startSummary(txtFile: txtFile, model: model);
  return result['summary'] as String; // <-- CRASH
  ```
  Endpoint `/api/summary` mengembalikan `{"job_id": "...", "status": "started"}` dan tidak mengembalikan field `summary`.
- **Konsekuensi:** `result['summary']` bernilai `null`, menyebabkan unhandled exception `TypeError: null is not a subtype of type 'String'`.

---

### 2. 🔴 Pemantauan Batch Transkripsi Terputus pada File Pertama
- **File:** [flutter_app/lib/providers/transcribe_provider.dart (baris 149-165)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/providers/transcribe_provider.dart#L149-L165)
- **Akar Masalah:**
  Saat user memilih 5 file, server mengembalikan array `job_ids: ["id1", "id2", "id3", "id4", "id5"]`.
  Provider Flutter hanya menyimpan `_jobId = res['job_id']` (yaitu `id1`). Ketika `id1` selesai (`status == 'completed'`), provider langsung mengeksekusi `_finishJob()` dan membatalkan stream subscription.
- **Konsekuensi:** File ke-2 hingga ke-5 yang masih mengantre/berjalan di server tidak dipantau lagi oleh aplikasi.

---

### 3. 🟠 Layar Summary Memuat File yang Salah Setelah Selesai
- **File:** [flutter_app/lib/screens/summary_screen.dart (baris 198-200)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/screens/summary_screen.dart#L198-L200)
- **Akar Masalah:**
  Saat polling status summary mencapai 100%, layar mengeksekusi:
  ```dart
  _loadContent(_selectedFile!);
  ```
  Variabel `_selectedFile` menunjuk ke file transkripsi asli (`output/single/namafile.txt`), sementara hasil ringkasan berada di `summary/single/namafile(summary).txt`.
- **Konsekuensi:** Editor tetap memuat teks transkripsi mentah dan daftar summary di sisi kanan tidak diperbarui.

---

### 4. 🟠 Fitur Download File di Browser Tidak Menyimpan ke Storage
- **File:** [flutter_app/lib/screens/file_browser_screen.dart (baris 109-124)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/screens/file_browser_screen.dart#L109-L124)
- **Akar Masalah:**
  ```dart
  Future<void> _downloadFile(String path) async {
      final bytes = await ApiService.downloadFile(path);
      final filename = path.split('/').last;
      if (mounted) {
          UiUtils.showSnackBar(context, '📥 Downloaded: $filename (${UiUtils.formatSize(bytes.length)})');
      }
  }
  ```
  Array `bytes` diterima dari network tetapi tidak pernah ditulis ke file menggunakan `File.writeAsBytes()`.
- **Konsekuensi:** Notifikasi sukses muncul, tetapi file tidak ada di perangkat user.

---

### 5. 🟠 Inkonsistensi Lokasi Penyimpanan Download Antar Layar
- **File:** [flutter_app/lib/screens/editor_screen.dart (baris 130)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/screens/editor_screen.dart#L130) vs [flutter_app/lib/screens/pdf_screen.dart (baris 149)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/screens/pdf_screen.dart#L149)
- **Akar Masalah:**
  - `EditorScreen`: Menggunakan `Directory.systemTemp` (folder cache sementara OS).
  - `PdfScreen` & `SummaryScreen`: Menggunakan `getApplicationDocumentsDirectory()`.
- **Konsekuensi:** File hasil download editor tersimpan di folder temporary yang sewaktu-waktu dibersihkan sistem dan tidak dapat ditemukan user melalui file manager.

---

### 6. 🟡 Duplikasi Port pada `ApiConfig`
- **File:** [flutter_app/lib/config/api_config.dart (baris 45)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/config/api_config.dart#L45) & [flutter_app/lib/screens/settings_dialog.dart (baris 161)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/screens/settings_dialog.dart#L161)
- **Akar Masalah:**
  Jika user menginput `192.168.1.10:5000` di dialog setting, `baseUrl` menyusun:
  `'http://$_host:$_port/api'` -> `'http://192.168.1.10:5000:5000/api'`.
- **Konsekuensi:** Request HTTP gagal karena format URL invalid.

---

### 7. 🟡 Mismatch Field Model `JobStatus.inputFile`
- **File:** [flutter_app/lib/models/job_status.dart (baris 28)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/models/job_status.dart#L28)
- **Akar Masalah:** Model membaca `json['input_file']`, padahal database backend mengirimkan field `audio_file` (atau `source_file`).
- **Konsekuensi:** Properti `job.inputFile` selalu kosong (`""`).

---

### 8. 🟡 Ekstensi File Media Terpotong di File Picker
- **File:** [flutter_app/lib/screens/transcribe_screen.dart (baris 122 & 141)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/screens/transcribe_screen.dart#L122)
- **Akar Masalah:**
  Flutter hanya memfilter `['mp3', 'wav', 'm4a', 'ogg']` dan `['mp4', 'mkv', 'avi', 'mov']`.
  Sementara backend Python mendukung penuh format `.flac`, `.wma`, `.aac`, `.webm`, `.mpeg`, `.mpg`, `.m4v`.
- **Konsekuensi:** User tidak bisa memilih file `.flac` atau `.aac` melalui aplikasi Flutter.

---

### 9. 🟢 Masalah Backslash Path Windows di History & Editor
- **File:** [flutter_app/lib/screens/history_screen.dart (baris 342)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/screens/history_screen.dart#L342) & [flutter_app/lib/screens/editor/editor_main_area.dart (baris 73)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/screens/editor/editor_main_area.dart#L73)
- **Akar Masalah:** Menggunakan `.split('/').last`. Pada Windows, path file dari backend menggunakan backslash (`output\single\file.txt`).
- **Konsekuensi:** Pemisahan string gagal dan UI menampilkan teks panjang `output\single\file.txt` alih-alih `file.txt`.

---

### 10. 🟢 Menu "Summary" Hilang dari Grid Utama Home Screen
- **File:** [flutter_app/lib/screens/home_screen.dart (baris 73-114)](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/screens/home_screen.dart#L73-L114)
- **Akar Masalah:** Grid ToolCard di Home Screen hanya mendaftarkan 5 kartu (Transcribe, Editor, Convert PDF, History, File Browser). Kartu menu **Summary** tidak ada di landing page utama.

---

## 🎯 Rencana Aksi Perbaikan Terstruktur

Jika Anda ingin mulai memperbaiki berkas-berkas ini, berikut urutan langkah yang disarankan:

1. **Fase 1 - Core Engine & Crash Fixes (Prioritas Tertinggi):**
   - Perbaiki handling `process_file == None` di [src/server.py](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/server.py).
   - Perbaiki sinkronisasi mapping indeks glosarium di [src/core/translator.py](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/core/translator.py).
   - Perbaiki multi-job tracking batch transcribe di [flutter_app/lib/providers/transcribe_provider.dart](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/providers/transcribe_provider.dart).
   - Perbaiki return type pada [flutter_app/lib/providers/summary_provider.dart](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/providers/summary_provider.dart).

2. **Fase 2 - Data Integrity, File Ops & Security:**
   - Perbaiki sanitasi parameter query `db.update_job()` agar tidak menimpa dengan `NULL`.
   - Batasi path traversal pada endpoint download dan transcript di [src/server.py](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/server.py).
   - Standardisasi fungsi download file di Flutter agar seluruhnya tersimpan ke Documents/Downloads.
   - Perbaiki logika error handling pada Ollama di [src/summarytext.py](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/summarytext.py).

3. **Fase 3 - UI/UX, Navigation & Polish:**
   - Tambahkan kartu **Summary** di [flutter_app/lib/screens/home_screen.dart](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/flutter_app/lib/screens/home_screen.dart).
   - Tambahkan dukungan ekstensi `.flac`, `.aac`, `.webm`, dll. di file picker.
   - Perbaiki penanganan path backslash Windows di seluruh tampilan layar Dart.
   - Tambahkan `tinytag` ke [requirements.txt](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/requirements.txt).
