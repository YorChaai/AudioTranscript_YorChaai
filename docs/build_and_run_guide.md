# Panduan Menjalankan & Lokasi Build Aplikasi (Audio Convert to Text)

Dokumen ini berisi informasi mengenai cara menjalankan server backend dengan cepat, serta lokasi file hasil build (Windows & Android) yang siap digunakan.

## 1. Menjalankan Server Backend

Untuk menjalankan server backend Python, Anda tidak perlu lagi membuka terminal dan mengetikkan perintah secara manual.

- **Lokasi File:** Di dalam folder utama proyek (`D:\2. Organize\1. Projects\audio convert to txt`) terdapat file bernama `start_backend.bat`.
- **Cara Penggunaan:** Cukup **klik 2x (double-click)** pada file `start_backend.bat` tersebut.
- **Apa yang terjadi:** File ini akan secara otomatis:
  1. Mengaktifkan _Virtual Environment_ (venv) Python Anda.
  2. Menjalankan skrip `src\server.py`.
  3. Mencegah terminal langsung tertutup jika terjadi error (sehingga Anda bisa membaca pesan errornya).

---

## 2. Lokasi File Build Flutter (Siap Pakai)

Jika Anda sudah melakukan proses build melalui Flutter (`flutter build windows` atau `flutter build apk`), berikut adalah direktori letak file hasil akhirnya:

### 💻 Aplikasi Windows (Laptop)

File aplikasi executable (`.exe`) yang siap dijalankan di sistem operasi Windows dapat ditemukan di:

> `D:\2. Organize\1. Projects\audio convert to txt\flutter_app\build\windows\x64\runner\Release\audio_convert_app.exe`

Anda bisa membuat _shortcut_ dari file `audio_convert_app.exe` ini dan meletakkannya di Desktop Anda agar mudah diakses kapan saja.

### 📱 Aplikasi Android (HP)

File instalasi Android (`.apk`) yang siap dikirim dan di-install ke HP Android Anda dapat ditemukan di:

> `D:\2. Organize\1. Projects\audio convert to txt\flutter_app\build\app\outputs\flutter-apk\app-release.apk`

Anda bisa memindahkan file `app-release.apk` ini ke HP Anda (melalui kabel USB, WhatsApp, atau Google Drive) dan langsung meng-installnya.

flutter build windows; flutter build apk

PS D:\2. Organize\1. Projects\audio convert to txt\flutter_app> flutter build apk
Font asset "CupertinoIcons.ttf" was tree-shaken, reducing it from 257628 to 848 bytes (99.7% reduction). Tree-shaking can be disabled by providing the --no-tree-shake-icons flag when building your app.
Font asset "MaterialIcons-Regular.otf" was tree-shaken, reducing it from 1645184 to 8512 bytes (99.5% reduction). Tree-shaking can be disabled by providing the --no-tree-shake-icons flag when building your app.
Running Gradle task 'assembleRelease'... 59.0s
√ Built build\app\outputs\flutter-apk\app-release.apk (55.9MB)
PS D:\2. Organize\1. Projects\audio convert to txt\flutter_app> flutter install
Installing app-release.apk to 2506BPN68G...
Uninstalling old version...
Installing build\app\outputs\flutter-apk\app-release.apk... 7.4s
PS D:\2. Organize\1. Projects\audio convert to txt\flutter_app> flutter build windows
Nuget.exe not found, trying to download or use cached version.
Building Windows application... 57.3s
√ Built build\windows\x64\runner\Release\audio_convert_app.exe
PS D:\2. Organize\1. Projects\audio convert to txt\flutter_app>
