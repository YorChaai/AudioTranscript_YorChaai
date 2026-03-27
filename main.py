import os
import sys
import subprocess
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

BASE_DIR = Path(__file__).parent

def menu_transcribe():
    print("\n" + "-"*40)
    print("🎤 TRANSCRIBE AUDIO")
    print("-"*40)
    print("Pilih Mode:")
    print("  [1] Single (1 file)")
    print("  [2] Multiple (banyak file)")
    mode_choice = input("Pilih (1/2): ").strip()
    
    mode_map = {"1": "single", "2": "multiple"}
    if mode_choice not in mode_map:
        print("❌ Pilihan tidak valid. Kembali ke menu utama.")
        return
    mode = mode_map[mode_choice]

    print("\nPilih Bahasa Audio Asli:")
    print("  [1] id (Indonesian)")
    print("  [2] en (English)")
    print("  [3] ja (Japanese)")
    print("  [4] auto (Auto-detect / Campuran)")
    lang_choice = input("Pilih (1/2/3/4): ").strip()
    
    lang_map = {"1": "id", "2": "en", "3": "ja", "4": "auto"}
    if lang_choice not in lang_map:
        print("❌ Pilihan tidak valid. Kembali ke menu utama.")
        return
    language = lang_map[lang_choice]

    script_path = BASE_DIR / "transcribe.py"
    # Menjalankan script transcribe.py dengan argumen yang dipilih
    subprocess.run([sys.executable, str(script_path), mode, language])


def menu_summary():
    print("\n" + "-"*40)
    print("📝 GENERATE SUMMARY TEXT")
    print("-"*40)
    print("Pilih Mode:")
    print("  [1] Single (1 file)")
    print("  [2] Multiple (banyak file)")
    mode_choice = input("Pilih (1/2): ").strip()
    
    mode_map = {"1": "single", "2": "multiple"}
    if mode_choice not in mode_map:
        print("❌ Pilihan tidak valid. Kembali ke menu utama.")
        return
    mode = mode_map[mode_choice]
    
    script_path = BASE_DIR / "summarytext.py"
    # Menjalankan script summarytext.py
    subprocess.run([sys.executable, str(script_path), mode])


def menu_pdf():
    print("\n" + "-"*40)
    print("📄 CONVERT TXT TO PDF")
    print("-"*40)
    print("Pilih Mode:")
    print("  [1] Single (1 file)")
    print("  [2] Multiple (banyak file)")
    mode_choice = input("Pilih (1/2): ").strip()
    
    mode_map = {"1": "single", "2": "multiple"}
    if mode_choice not in mode_map:
        print("❌ Pilihan tidak valid. Kembali ke menu utama.")
        return
    mode = mode_map[mode_choice]
    
    script_path = BASE_DIR / "convert_pdf.py"
    # Menjalankan script convert_pdf.py
    subprocess.run([sys.executable, str(script_path), mode])


def main():
    while True:
        print("\n\n" + "="*50)
        print("        AUDIO CONVERT TO TXT - MASTER MENU        ")
        print("="*50)
        print("Pilih menu yang ingin dijalankan:\n")
        print("  [1] 🎤 Transcribe Audio (transcribe.py)")
        print("  [2] 📝 Generate Summary Text (summarytext.py)")
        print("  [3] 📄 Convert TXT to PDF (convert_pdf.py)")
        print("\n  [0] Keluar")
        print("="*50)

        choice = input("Pilihan Anda: ").strip()

        if choice == "1":
            menu_transcribe()
        elif choice == "2":
            menu_summary()
        elif choice == "3":
            menu_pdf()
        elif choice == "0":
            print("\n👋 Keluar dari program. Terima kasih!\n")
            break
        else:
            print("\n❌ Pilihan tidak valid. Silakan coba lagi.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n👋 Keluar dari program. Terima kasih!\n")
        sys.exit(0)
