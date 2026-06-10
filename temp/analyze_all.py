from glossary_list import get_txt_files, suggest_terms
import sys

# Redirect stdout to ensure we capture utf-8 correctly on windows terminals if needed, 
# though run_command usually handles it.
sys.stdout.reconfigure(encoding='utf-8')

files = get_txt_files()
combined_text = ""
print(f"Analyzing {len(files)} files...")

for f in files:
    try:
        with open(f['path'], "r", encoding="utf-8") as file:
            combined_text += file.read() + " "
    except Exception as e:
        print(f"Error reading {f['name']}: {e}")

print("Text loaded. Running analysis...")
suggest_terms(combined_text, top_n=30)
