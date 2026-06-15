import os
import sys
import requests
import time  # Fix L4: Import time untuk retry logic
from pathlib import Path
from datetime import datetime

# Folder paths
BASE_DIR = Path(__file__).parent.parent  # Project root (src/ is subdir)
CONVERT_TXT_DIR = BASE_DIR / "output"
SUMMARY_DIR = BASE_DIR / "summary"

# Available Models in Ollama
MODELS = {
    "1": {"name": "qwen2.5:72b", "display": "Qwen 2.5 72B (Raja - Akurasi Tertinggi)"},
    "2": {"name": "qwen2.5:32b", "display": "Qwen 2.5 32B (Pintar & Cepat)"},
    "3": {"name": "qwen3:30b", "display": "Qwen 3 30B (Terbaru & Cepat)"},
    "4": {"name": "qwen3:8b", "display": "Qwen 3 8B (Ringan & Akurat - Rekomendasi)"},
    "5": {"name": "qwen2.5:14b", "display": "Qwen 2.5 14B (Balance Terbaik - 32GB RAM)"},
    "6": {"name": "qwen2.5:7b", "display": "Qwen 2.5 7B (Paling Ringan)"},
    "7": {"name": "llama3.1:70b", "display": "Llama 3.1 70B (Raja Inggris)"},
    "8": {"name": "gemma2:27b", "display": "Gemma 2 27B (Logika Google)"}
}

def get_txt_files():
    """Ambil semua file .txt dari folder output (single & multiple)"""
    txt_files = []
    # Cari di 'single'
    single_dir = CONVERT_TXT_DIR / "single"
    if single_dir.exists():
        for f in single_dir.glob("*.txt"):
            txt_files.append({"path": f, "name": f"single/{f.name}"})

    # Cari di 'multiple' (batch subdirs)
    multiple_dir = CONVERT_TXT_DIR / "multiple"
    if multiple_dir.exists():
        for batch_dir in multiple_dir.iterdir():
            if batch_dir.is_dir():
                for f in batch_dir.glob("*.txt"):
                    txt_files.append({"path": f, "name": f"multiple/{batch_dir.name}/{f.name}"})

    return sorted(txt_files, key=lambda x: x['path'].stat().st_mtime, reverse=True)

def select_files(files, mode="single"):
    """Pilih file berdasarkan mode"""
    if not files:
        print("❌ Tidak ada file transkripsi ditemukan.")
        return []

    print(f"\n📂 Files found ({len(files)} files):")
    for i, f in enumerate(files[:20], 1): # Tampilkan 20 terbaru
        print(f"  [{i}] {f['name']}")

    if len(files) > 20:
        print(f"  ... and {len(files)-20} more.")

    prompt = "Pilih nomor file (contoh: 1): " if mode == "single" else "Pilih nomor file (pisah koma, contoh: 1,2,3): "
    choice = input(f"\n{prompt}").strip()

    selected = []
    try:
        if mode == "single":
            idx = int(choice) - 1
            if 0 <= idx < len(files):
                selected.append(files[idx])
        else:
            indices = [int(x.strip()) - 1 for x in choice.split(",") if x.strip().isdigit()]
            for idx in indices:
                if 0 <= idx < len(files):
                    selected.append(files[idx])
    except ValueError:
        print("❌ Input tidak valid.")

    return selected

def select_model():
    """Pilih model Ollama"""
    print("\n🤖 Pilih Model Summary:")
    for k, v in MODELS.items():
        print(f"  [{k}] {v['display']}")

    choice = input("\nPilih nomor (1-7, Default=1): ").strip() or "1"
    return MODELS.get(choice, MODELS["1"])["name"]

def extract_metadata(text):
    """Ekstrak metadata dari header file transcript"""
    lines = text.split("\n")
    metadata = {"language": "id"} # Default to Indonesian

    for line in lines[:20]: # Cek 20 baris pertama saja untuk header
        line = line.strip()
        if line.startswith("Detected:"):
            # Format: Detected: id (100.0%) or Detected: en (99.9%)
            parts = line.split(":", 1)[1].strip().split(" ")
            if parts:
                metadata["language"] = parts[0].strip().lower()

    return metadata

def clean_transcript(text):
    """Bersihkan teks dari timestamps dan header agar model fokus pada konten"""
    lines = text.split("\n")
    cleaned_lines = []
    in_timestamps = False

    for line in lines:
        line = line.strip()
        if not line: continue

        # Skip header info
        if any(line.startswith(h) for h in ["Source:", "Language Mode:", "Detected:", "Transcribed:", "====", "TIMESTAMPS:", "TRANSLATION:"]):
            if line.startswith("TIMESTAMPS:"): in_timestamps = True
            continue

        # Skip timestamp lines like [00:10 - 00:20]
        if line.startswith("[") and " - " in line and "]" in line:
            continue

        if not in_timestamps:
            cleaned_lines.append(line)

    return " ".join(cleaned_lines)

def generate_summary(text, model_name, language="id"):
    """Kirim teks ke Ollama API untuk diringkas dengan instruksi spesifik bahasa"""

    # Fix M3: Configurable API URL dengan environment variable
    ollama_url = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/generate")

    # Fix L4: Retry logic dengan exponential backoff
    max_retries = 3
    retry_delay = 2  # detik

    # Prompt logic based on detected language
    lang_info = "Bahasa Inggris" if language == "en" else "Bahasa Indonesia"
    print(f"   ℹ️  Bahasa terdeteksi: {language.upper()} ({lang_info})")

    if language == "en":
        target_instruction = "Teks asli dalam Bahasa Inggris. Tolong buat ringkasan dalam Bahasa Indonesia yang akurat."
    else:
        target_instruction = "Teks asli dalam Bahasa Indonesia. Buat ringkasan yang akurat."

    print(f"   ⏳ Merangkas dengan {model_name}...")
    prompt = f"""
{target_instruction}

BAHASA OUTPUT: WAJIB BAHASA INDONESIA. Meskipun transkripsi dalam Bahasa Inggris, output HARUS ditulis dalam Bahasa Indonesia yang natural dan profesional.

TUGAS: Tulis ulang semua informasi dari transkripsi ini dalam bentuk catatan lengkap dengan paragraf dan mindmap deskriptif. SEMUA OUTPUT HARUS DALAM BAHASA INDONESIA.

ATURAN FORMAT:
1. JANGAN gunakan bold, italic, atau formatting markdown apapun di bagian paragraf
2. JANGAN gunakan bullet points atau daftar di bagian paragraf
3. Tulis dalam bentuk PARAGRAF yang mengalir natural seperti artikel
4. Setiap topik baru, mulai paragraf baru
5. Tulis SEMUA nama, angka, judul buku, nama channel, nama kursus, tips, dan contoh yang disebutkan
6. Jangan meringkas, tulis selengkap mungkin
7. Di bagian akhir WAJIB buat mindmap mermaid yang sangat detail dan deskriptif

CONTOH OUTPUT YANG BENAR:

---
Bagian 1 - Gambaran Umum

Pembicara adalah seorang ibu dengan dua anak yang bekerja di luar negeri dengan jam kerja panjang dan tekanan tinggi. Ia berbagi pengalaman pribadinya tentang bagaimana waktu malamnya yang dulunya terbuang sia-sia, kini bisa dimanfaatkan dengan lebih bermakna melalui lima kebiasaan sederhana.

Bagian 2 - Isi Lengkap

Kebiasaan Pertama adalah mengubah tujuan pertama saat sampai rumah. Pembicara menjelaskan bahwa masalah utamanya bukan malas, melainkan kebiasaan otomatis. Ketika pulang kerja, tubuh secara refleks langsung menuju sofa dan membuka handphone untuk cek email atau scrolling sosial media dengan alasan butuh hiburan. Kebiasaan ini bisa memakan waktu satu sampai dua jam tanpa terasa. Solusi yang ia terapkan adalah langsung pergi ke kamar mandi begitu sampai rumah untuk mandi, ganti baju, dan melakukan skincare.

Kebiasaan Kedua adalah memprioritaskan satu hal yang ingin dilakukan malam itu. Pembicara menjelaskan bahwa jika malam tidak punya tujuan, malam akan mengikuti apa yang paling mudah dilakukan seperti kerja lagi atau scrolling sosial media. Makanya ia merencanakan satu hal kecil di pagi atau siang hari untuk dikerjakan malam itu di luar rutinitas biasa.

Bagian 3 - Sumber yang Disebutkan

Pembicara menyebutkan menggunakan device atau perangkat untuk melacak kualitas tidur yang bisa menampilkan data seperti durasi deep sleep, stress level, dan resting heart rate. Ia juga menyebutkan memiliki komunitas gratis dan template gratis untuk membantu membangun kebiasaan baru.

Bagian 4 - Tips Praktis

Tips pertama adalah mengubah tujuan pertama saat sampai rumah dengan langsung ke kamar mandi untuk mandi dan ganti baju, bukan ke sofa. Tips kedua untuk yang bekerja dari rumah adalah tutup laptop kantor lalu jalan kaki keluar rumah 20 sampai 30 menit dengan mindset bahwa setelah kembali sudah menjadi waktu pribadi.

---

```mermaid
mindmap
  root((5 Kebiasaan Produktif Setelah Pulang Kerja))
    Kebiasaan 1: Ubah Tujuan Pertama
      Masalah bukan malas tapi kebiasaan otomatis
        Pulang langsung ke sofa adalah refleks yang sulit dihindari
        Buka handphone dengan alasan butuh hiburan padahal bisa 1-2 jam
      Solusi: Langsung ke kamar mandi
        Mandi dan ganti baju membantu otak transisi dari kerja ke istirahat
      Untuk Work From Home
        Tutup laptop kantor sebagai tanda kerja selesai
        Jalan kaki 20-30 menit keluar rumah untuk transisi mental
    Kebiasaan 2: Prioritaskan Satu Hal
      Tanpa tujuan malam akan ikut yang paling gampang
        Scrolling atau kerja lagi jadi default
      Rencanakan di pagi atau siang hari
        Satu hal saja karena gampang dimulai
        Contoh: belajar 20-30 menit, bantu anak belajar, telepon orang tua
```
---

Ikuti format contoh di atas. Mindmap harus SANGAT DETAIL dengan penjelasan di setiap cabang.

---
TRANSKRIPSI:
{text}
"""

    # Fix L4: Retry logic
    # Create payload for Ollama API
    payload = {
        "model": model_name,
        "prompt": prompt,
        "stream": False
    }

    for attempt in range(max_retries):
        try:
            response = requests.post(ollama_url, json=payload, timeout=300)
            response.raise_for_status()
            return response.json().get("response", "Gagal menghasilkan ringkasan.")
        except requests.exceptions.Timeout:
            print(f"   ⚠️ Timeout (attempt {attempt + 1}/{max_retries})")
            if attempt < max_retries - 1:
                time.sleep(retry_delay * (attempt + 1))  # Exponential backoff
        except requests.exceptions.ConnectionError:
            print(f"   ⚠️ Connection error (attempt {attempt + 1}/{max_retries})")
            if attempt < max_retries - 1:
                time.sleep(retry_delay * (attempt + 1))
        except Exception as e:
            if attempt == max_retries - 1:
                return f"❌ Error Ollama: {e}\n(Pastikan Ollama sudah jalan dan model sudah di-'pull')"

    return "❌ Error: Max retries exceeded"

def save_summary(original_path, summary, model_name):
    """Simpan summary ke folder summary dengan struktur yang sama"""
    try:
        # Hitung path relatif dari folder output
        # Contoh: D:\...\output\single\file.txt -> single\file.txt
        relative_path = original_path.relative_to(CONVERT_TXT_DIR)

        # Buat path baru di folder summary
        # Contoh: D:\...\summary\single\file(summary).txt
        new_path = SUMMARY_DIR / relative_path
        new_path = new_path.with_name(f"{original_path.stem}(summary).txt")

        # Pastikan parent directory ada
        new_path.parent.mkdir(parents=True, exist_ok=True)

        with open(new_path, "w", encoding="utf-8") as f:
            f.write(f"# Summary: {original_path.stem}\n")
            f.write(f"**Model:** {model_name}\n")
            f.write(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write("-" * 50 + "\n\n")
            f.write(summary)
            f.write("\n")

        print(f"   📂 Disimpan di: summary/{relative_path.parent.name}/{new_path.name}")
        return True
    except Exception as e:
        print(f"❌ Gagal menyimpan summary ke {new_path}: {e}")
        return False

def main():
    if len(sys.argv) < 2:
        print("Usage: python summarytext.py <single|multiple>")
        sys.exit(1)

    mode = sys.argv[1].lower()
    if mode not in ["single", "multiple"]:
        print("❌ Mode harus 'single' atau 'multiple'")
        sys.exit(1)

    files = get_txt_files()
    selected_files = select_files(files, mode)

    if not selected_files:
        return

    model_name = select_model()

    print(f"\n🚀 Memulai proses ringkasan untuk {len(selected_files)} file...")

    for item in selected_files:
        path = item['path']
        print(f"\n📄 Memproses: {item['name']}")

        with open(path, "r", encoding="utf-8") as f:
            raw_text = f.read()

        metadata = extract_metadata(raw_text)
        cleaned_text = clean_transcript(raw_text)

        if not cleaned_text.strip():
            print("   ⚠️ File kosong atau tidak ada konten yang bisa diringkas.")
            continue

        summary = generate_summary(cleaned_text, model_name, language=metadata.get("language", "id"))

        if save_summary(path, summary, model_name):
            print("   ✅ Ringkasan berhasil disimpan ke file!")

    print("\n" + "=" * 50)
    print("✨ Selesai!")

if __name__ == "__main__":
    main()
