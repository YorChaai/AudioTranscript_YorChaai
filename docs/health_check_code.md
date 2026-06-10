# Kode Pengecekan Kesehatan Sistem

Kode untuk fitur **🔍 Pengecekan Kesehatan Sistem** (Health Check) berada di dalam file [main.py](file:///d:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/src/main.py) pada fungsi `menu_check_setup()`.

Berikut adalah salinan kodenya:

```python
def menu_check_setup():
    """
    HEALTH CHECK: Memeriksa library, GPU, model, dan folder.
    """
    print("\n" + "=" * 60)
    print("🔍 PENGECEKAN KESEHATAN SISTEM")
    print("=" * 60)

    # 1. Cek Python & Venv
    print(f"🐍 Python Version: {sys.version.split()[0]}")
    print(f"🏠 Project Root: {BASE_DIR}")

    # 2. Cek Libraries
    print("\n📦 Memeriksa Library...")
    libs = {
        "faster_whisper": "faster-whisper",
        "deep_translator": "deep-translator",
        "dotenv": "python-dotenv",
        "torch": "torch",
        "ctranslate2": "ctranslate2"
    }

    import importlib
    all_libs_ok = True
    for mod_name, pkg_name in libs.items():
        try:
            importlib.import_module(mod_name)
            print(f"   ✅ {pkg_name} terinstal.")
        except ImportError:
            print(f"   ❌ {pkg_name} TIDAK DITEMUKAN!")
            all_libs_ok = False

    # 3. Cek GPU / CUDA
    print("\n🚀 Memeriksa GPU (CUDA)...")
    try:
        import torch
        if torch.cuda.is_available():
            print(f"   ✅ CUDA tersedia!")
            print(f"   📟 GPU: {torch.cuda.get_device_name(0)}")
            vram = torch.cuda.get_device_properties(0).total_memory / (1024**3)
            print(f"   💾 VRAM: {vram:.1f} GB")
        else:
            print("   ⚠️  CUDA tidak terdeteksi. Program akan berjalan di CPU (lambat).")
    except Exception as e:
        print(f"   ❌ Gagal mengecek GPU: {e}")

    # 4. Cek Model Whisper
    print("\n🧠 Memeriksa Model Whisper...")
    # Ambil path dari .env jika ada
    model_path = os.environ.get("WHISPER_MODEL_PATH", "D:\\model\\large-v3")
    if Path(model_path).exists():
        print(f"   ✅ Model ditemukan di: {model_path}")
    else:
        print(f"   ⚠️  Model TIDAK ditemukan di: {model_path}")
        print("      Program akan mendownload otomatis saat pertama kali dijalankan.")

    # 5. Cek Folder Dasar
    print("\n📂 Memeriksa Folder Proyek...")
    folders = ["audio", "output", "assets", "src"]
    for f in folders:
        p = BASE_DIR / f
        if p.exists():
            print(f"   ✅ Folder '{f}' tersedia.")
        else:
            print(f"   ⚠️  Folder '{f}' hilang. Membuat folder...")
            p.mkdir(parents=True, exist_ok=True)

    print("\n" + "=" * 60)
    if all_libs_ok:
        print("✅ SETUP SELESAI: Sistem siap digunakan!")
    else:
        print("❌ SETUP BERMASALAH: Harap instal library yang kurang.")
    print("=" * 60)
    input("\nTekan Enter untuk kembali ke menu...")
```

### Cara Kerja:
1. **Python Version**: Menampilkan versi Python yang sedang berjalan.
2. **Library Check**: Mencoba meng-import library utama yang dibutuhkan. Jika gagal, akan muncul tanda ❌.
3. **GPU/CUDA**: Menggunakan `torch` untuk mendeteksi apakah kartu grafis (NVIDIA) bisa digunakan. Ini penting agar proses transkripsi jadi cepat.
4. **Model Path**: Memastikan file model Whisper (`large-v3`) ada di lokasi yang benar.
5. **Folder Check**: Memastikan struktur folder proyek (`audio`, `output`, dll) sudah lengkap.


outputnya gini 
"
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
  [5] 📄 output to PDF
  [6] 🔍 Cek Setup & Kesehatan Sistem

  [0] Keluar
============================================================
Pilihan Anda: 6

============================================================
🔍 PENGECEKAN KESEHATAN SISTEM
============================================================
🐍 Python Version: 3.11.0
🏠 Project Root: D:\2. Organize\1. Projects\audio convert to txt

📦 Memeriksa Library...
   ✅ faster-whisper terinstal.
   ✅ deep-translator terinstal.
   ✅ python-dotenv terinstal.
   ✅ torch terinstal.
   ✅ ctranslate2 terinstal.

🚀 Memeriksa GPU (CUDA)...
   ✅ CUDA tersedia!
   📟 GPU: NVIDIA GeForce RTX 4070 Laptop GPU
   💾 VRAM: 8.0 GB

🧠 Memeriksa Model Whisper...
   ✅ Model ditemukan di: D:\model\large-v3

📂 Memeriksa Folder Proyek...
   ✅ Folder 'audio' tersedia.
   ✅ Folder 'output' tersedia.
   ✅ Folder 'assets' tersedia.
   ✅ Folder 'src' tersedia.

============================================================
✅ SETUP SELESAI: Sistem siap digunakan!
============================================================

Tekan Enter untuk kembali ke menu...
"
