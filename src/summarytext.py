import os
import sys
import requests
import time  # Fix L4: Import time untuk retry logic
from pathlib import Path
from datetime import datetime
from config import BASE_DIR, CONVERT_DIR, SUMMARY_DIR

# Alias for backward compatibility in this script
CONVERT_TXT_DIR = CONVERT_DIR

def get_installed_ollama_models(ollama_host=None):
    """Ambil daftar model yang benar-benar terinstall di Ollama lokal secara dinamis."""
    host = ollama_host or os.environ.get("OLLAMA_HOST", "http://localhost:11434")
    tags_url = f"{host.rstrip('/')}/api/tags"
    try:
        resp = requests.get(tags_url, timeout=3)
        if resp.status_code == 200:
            data = resp.json()
            models = []
            for m in data.get("models", []):
                name = m.get("name", "")
                details = m.get("details", {})
                param_size = details.get("parameter_size", "")
                models.append({
                    "name": name,
                    "model": m.get("model", name),
                    "size": m.get("size", 0),
                    "parameter_size": param_size,
                    "family": details.get("family", ""),
                    "display": f"{name} ({param_size})" if param_size else name
                })
            return models
    except Exception:
        pass
    return []

# Fallback models jika Ollama offline / gagal query
FALLBACK_OLLAMA_MODELS = [
    {"name": "qwen2.5:72b", "display": "Qwen 2.5 72B"},
    {"name": "qwen2.5:32b", "display": "Qwen 2.5 32B"},
    {"name": "qwen3:30b", "display": "Qwen 3 30B"},
    {"name": "qwen3:8b", "display": "Qwen 3 8B"},
    {"name": "llama3.1:70b", "display": "Llama 3.1 70B"},
]

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
    """Pilih model Ollama secara dinamis dari model yang terinstall"""
    installed = get_installed_ollama_models()
    print("\n🤖 Pilih Model Summary:")
    
    if installed:
        for idx, m in enumerate(installed, 1):
            print(f"  [{idx}] {m['display']}")
        print(f"  [{len(installed) + 1}] Input nama model custom secara manual")
        choice = input(f"\nPilih nomor (1-{len(installed) + 1}, Default=1): ").strip() or "1"
        if choice.isdigit():
            i = int(choice) - 1
            if 0 <= i < len(installed):
                return installed[i]["name"]
            elif i == len(installed):
                custom = input("Masukkan nama model Ollama: ").strip()
                if custom:
                    return custom
        return installed[0]["name"]
    else:
        print("  ⚠️ Tidak dapat mendeteksi model Ollama lokal (Ollama offline). Menggunakan daftar template:")
        for idx, m in enumerate(FALLBACK_OLLAMA_MODELS, 1):
            print(f"  [{idx}] {m['display']}")
        choice = input("\nPilih nomor (1-5, Default=1): ").strip() or "1"
        if choice.isdigit() and 1 <= int(choice) <= len(FALLBACK_OLLAMA_MODELS):
            return FALLBACK_OLLAMA_MODELS[int(choice) - 1]["name"]
        return FALLBACK_OLLAMA_MODELS[0]["name"]

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
    
    # Deteksi jika ada separator header
    start_reading = True
    if any("=" * 10 in line for line in lines[:20]):
        start_reading = False
        
    for line in lines:
        line_clean = line.strip()
        
        # Mulai baca setelah separator header
        if not start_reading:
            if "=" * 10 in line_clean:
                start_reading = True
            continue
            
        # Skip baris kosong
        if not line_clean:
            continue
            
        # Skip timestamp lines (misal: [00:01.000 --> 00:04.000])
        if "-->" in line_clean and "[" in line_clean and "]" in line_clean:
            continue
            
        # Skip numeric index subtitle
        if line_clean.isdigit():
            continue
            
        cleaned_lines.append(line_clean)
        
    return " ".join(cleaned_lines)

def generate_summary(text, model_name, language="id", provider="auto", api_key=None):
    """
    Kirim teks ke Ollama atau Cloud AI (Gemini, Grok, OpenAI) untuk diringkas.
    """
    # Detect provider if set to auto
    m_lower = model_name.lower()
    if provider == "auto":
        if "gemini" in m_lower:
            provider = "gemini"
        elif "grok" in m_lower:
            provider = "grok"
        elif "gpt" in m_lower or "o1" in m_lower or "o3" in m_lower:
            provider = "openai"
        elif "claude" in m_lower:
            provider = "claude"
        else:
            provider = "ollama"

    # Prompt logic based on detected language
    lang_info = "Bahasa Inggris" if language == "en" else "Bahasa Indonesia"
    print(f"   ℹ️  Bahasa terdeteksi: {language.upper()} ({lang_info})")

    if language == "en":
        target_instruction = "Teks asli dalam Bahasa Inggris. Tolong buat ringkasan dalam Bahasa Indonesia yang akurat."
    else:
        target_instruction = "Teks asli dalam Bahasa Indonesia. Buat ringkasan yang akurat."

    print(f"   ⏳ Merangkum dengan {model_name} (Provider: {provider.upper()})...")
    prompt = f"""{target_instruction}

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
```
---

Ikuti format contoh di atas. Mindmap harus SANGAT DETAIL dengan penjelasan di setiap cabang.

---
TRANSKRIPSI:
{text}
"""

    # --- 1. GOOGLE GEMINI ---
    if provider == "gemini":
        key = api_key or os.environ.get("GEMINI_API_KEY")
        if not key:
            raise ValueError("API Key Google Gemini belum diisi. Masukkan Gemini API Key Anda.")
        
        gemini_url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={key}"
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.3}
        }
        res = requests.post(gemini_url, json=payload, timeout=120)
        if res.status_code != 200:
            err_msg = res.json().get("error", {}).get("message", res.text)
            raise RuntimeError(f"Error Gemini API: {err_msg}")
        data = res.json()
        try:
            return data["candidates"][0]["content"]["parts"][0]["text"]
        except Exception:
            raise RuntimeError("Gemini mengembalikan struktur respons yang tidak valid.")

    # --- 2. xAI GROK ---
    elif provider == "grok":
        key = api_key or os.environ.get("GROK_API_KEY")
        if not key:
            raise ValueError("API Key xAI Grok belum diisi. Masukkan Grok API Key Anda.")
        
        grok_url = "https://api.x.ai/v1/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        payload = {
            "model": model_name,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.3
        }
        res = requests.post(grok_url, json=payload, headers=headers, timeout=120)
        if res.status_code != 200:
            err_msg = res.json().get("error", {}).get("message", res.text)
            raise RuntimeError(f"Error Grok API: {err_msg}")
        return res.json()["choices"][0]["message"]["content"]

    # --- 3. OPENAI GPT ---
    elif provider == "openai":
        key = api_key or os.environ.get("OPENAI_API_KEY")
        if not key:
            raise ValueError("API Key OpenAI belum diisi. Masukkan OpenAI API Key Anda.")
        
        openai_url = "https://api.openai.com/v1/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        payload = {
            "model": model_name,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.3
        }
        res = requests.post(openai_url, json=payload, headers=headers, timeout=120)
        if res.status_code != 200:
            err_msg = res.json().get("error", {}).get("message", res.text)
            raise RuntimeError(f"Error OpenAI API: {err_msg}")
        return res.json()["choices"][0]["message"]["content"]

    # --- 4. ANTHROPIC CLAUDE ---
    elif provider == "claude":
        key = api_key or os.environ.get("CLAUDE_API_KEY") or os.environ.get("ANTHROPIC_API_KEY")
        if not key:
            raise ValueError("API Key Anthropic Claude belum diisi. Masukkan Claude API Key Anda.")
        
        claude_url = "https://api.anthropic.com/v1/messages"
        headers = {
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
        payload = {
            "model": model_name,
            "max_tokens": 4096,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.3
        }
        res = requests.post(claude_url, json=payload, headers=headers, timeout=120)
        if res.status_code != 200:
            err_msg = res.json().get("error", {}).get("message", res.text)
            raise RuntimeError(f"Error Claude API: {err_msg}")
        data = res.json()
        try:
            return data["content"][0]["text"]
        except Exception:
            raise RuntimeError("Claude mengembalikan respons yang tidak terduga.")

    # --- 5. LOCAL OLLAMA (DEFAULT) ---
    else:
        ollama_url = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/generate")
        max_retries = 3
        retry_delay = 2

        payload = {
            "model": model_name,
            "prompt": prompt,
            "stream": False
        }

        last_error = None
        for attempt in range(max_retries):
            try:
                response = requests.post(ollama_url, json=payload, timeout=300)
                response.raise_for_status()
                res_text = response.json().get("response", "")
                if not res_text.strip():
                    raise RuntimeError("Ollama mengembalikan respons kosong.")
                return res_text
            except requests.exceptions.Timeout as e:
                last_error = f"Timeout: {e}"
                print(f"   ⚠️ Timeout (attempt {attempt + 1}/{max_retries})")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay * (attempt + 1))
            except requests.exceptions.ConnectionError as e:
                last_error = f"Connection error: {e}"
                print(f"   ⚠️ Connection error (attempt {attempt + 1}/{max_retries})")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay * (attempt + 1))
            except Exception as e:
                last_error = str(e)
                if attempt == max_retries - 1:
                    raise RuntimeError(f"Error Ollama: {e} (Pastikan Ollama sudah jalan dan model '{model_name}' sudah di-'pull')")

        raise RuntimeError(f"Gagal menghubungi Ollama setelah {max_retries} percobaan: {last_error}")

def save_summary(original_path, summary, model_name):
    """Simpan summary ke folder summary dengan struktur yang sama"""
    try:
        # Hitung path relatif dari folder output
        # Contoh: D:\...\output\single\file.txt -> single\file.txt
        try:
            relative_path = original_path.relative_to(CONVERT_TXT_DIR)
        except ValueError:
            relative_path = Path("single") / original_path.name

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
        return new_path
    except Exception as e:
        print(f"❌ Gagal menyimpan summary: {e}")
        return None

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
