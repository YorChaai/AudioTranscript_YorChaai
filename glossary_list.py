import sys
import json
import string
from pathlib import Path
from collections import Counter

# File paths
BASE_DIR = Path(__file__).parent
GLOSSARY_PATH = BASE_DIR / "assets" / "glossary.json"
IGNORE_PATH = BASE_DIR / "assets" / "ignore_list.json"

def load_glossary():
    """Load current glossary."""
    if GLOSSARY_PATH.exists():
        try:
            with open(GLOSSARY_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}

def load_ignore_list():
    """Load ignored terms."""
    if IGNORE_PATH.exists():
        try:
            with open(IGNORE_PATH, "r", encoding="utf-8") as f:
                return set(json.load(f))
        except Exception:
            return set()
    return set()

def save_ignore_list(ignore_set):
    """Save ignored terms to file."""
    IGNORE_PATH.parent.mkdir(parents=True, exist_ok=True)
    try:
        # Sort for readability
        data = sorted(list(ignore_set))
        with open(IGNORE_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4)
        print(f"✅ Added {len(data)} terms to permanent ignore list.")
    except Exception as e:
        print(f"❌ Failed to save ignore list: {e}")

def suggest_terms(text: str, top_n: int = 50):
    """Analyze text and suggest new terms."""
    print("⏳ Loading NLTK and analyzing text...", flush=True)

    # Lazy import to avoid startup delay/crash
    import nltk
    from nltk.corpus import stopwords
    from nltk import ngrams

    # Fix H6: Pre-download dengan timeout dan error handling
    def ensure_stopwords():
        """Ensure stopwords downloaded dengan retry logic"""
        max_retries = 2
        for attempt in range(max_retries):
            try:
                nltk.data.find('corpora/stopwords')
                return True
            except LookupError:
                try:
                    print(f"⏳ Downloading NLTK stopwords... (attempt {attempt + 1}/{max_retries})")
                    nltk.download('stopwords', quiet=True, timeout=30)
                    # Verify download succeeded
                    nltk.data.find('corpora/stopwords')
                    print("✅ Stopwords downloaded successfully")
                    return True
                except Exception as e:
                    print(f"⚠️ Warning: Stopwords download failed: {e}")
                    if attempt == max_retries - 1:
                        print("⚠️ Using fallback stopword list")
                        return False
        return False

    stopwords_available = ensure_stopwords()

    if stopwords_available:
        stop_words = set(stopwords.words('english'))
    else:
        # Fallback minimal stopword list
        stop_words = {'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
                      'of', 'with', 'by', 'from', 'is', 'are', 'was', 'were', 'be', 'been',
                      'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
                      'could', 'should', 'may', 'might', 'must', 'shall', 'can', 'need',
                      'it', 'its', 'this', 'that', 'these', 'those', 'i', 'you', 'he',
                      'she', 'we', 'they', 'what', 'which', 'who', 'whom', 'whose', 'where',
                      'when', 'why', 'how', 'all', 'each', 'every', 'both', 'few', 'more',
                      'most', 'other', 'some', 'such', 'no', 'nor', 'not', 'only', 'own',
                      'same', 'so', 'than', 'too', 'very', 'just', 'as', 'if'}

    # 0. Pre-process: Extract only TIMESTAMPS section (English) and clean markers
    if "TIMESTAMPS:" in text:
        # Take everything after TIMESTAMPS:
        parts = text.split("TIMESTAMPS:", 1)
        body = parts[1]

        # If TRANSLATION (ID): exists, cut it off
        if "TRANSLATION (ID):" in body:
            body = body.split("TRANSLATION (ID):", 1)[0]

        # Remove timestamp markers like [00:00 - 00:05]
        import re
        body = re.sub(r'\[\d+:\d+\s*-\s*\d+:\d+\]', '', body)
        text_to_analyze = body
    else:
        # Fallback if structure is different
        text_to_analyze = text

    # 1. Normalize
    text_clean = text_to_analyze.lower()
    text_clean = text_clean.translate(str.maketrans('', '', string.punctuation))
    words = text_clean.split()

    # Load existing
    current_glossary = load_glossary()
    current_keys = set(k.lower() for k in current_glossary.keys())

    # Load ignore list
    ignore_list = load_ignore_list()
    ignore_list_lower = set(k.lower() for k in ignore_list)

    # Combined exclusion set
    exclusion_set = current_keys.union(ignore_list_lower)

    # 2. Filter Unigrams (Single Words)
    candidates = []
    for w in words:
        if len(w) < 4: continue
        if w in stop_words: continue
        if w in exclusion_set: continue
        if w.isdigit(): continue
        candidates.append(w)

    # 3. Filter Bigrams (2-Word Phrases)
    bigram_candidates = []
    # Generate bigrams
    if len(words) > 1:
        for b1, b2 in ngrams(words, 2):
            # Both words must not be stopwords
            if b1 in stop_words or b2 in stop_words: continue
            # Both words should have some length (e.g., > 2) to avoid noise
            if len(b1) < 3 or len(b2) < 3: continue

            phrase = f"{b1} {b2}"
            if phrase in exclusion_set: continue

            bigram_candidates.append(phrase)

    # 4. Count & Display
    uni_counts = Counter(candidates).most_common(top_n)
    bi_counts = Counter(bigram_candidates).most_common(top_n)

    all_suggestions = []

    # helper to add to list
    def add_to_list(source_list, label):
        nonlocal all_suggestions
        if not source_list: return
        all_suggestions.append(f"--- [ {label} ] ---")
        for term, count in source_list:
            all_suggestions.append({"term": term, "count": count})

    if uni_counts or bi_counts:
        print("\n💡 Suggested Glossary Terms (Frequently used & not in glossary):")
        print("-" * 60)

        # Flatten list for selection
        flat_list = []

        idx = 1
        if bi_counts:
            print(f"   [ 2-Word Phrases ]")
            for term, count in bi_counts:
                print(f"   [{idx}] {term} (freq: {count})")
                flat_list.append(term)
                idx += 1
            print("")

        if uni_counts:
            print(f"   [ Single Words ]")
            for term, count in uni_counts:
                print(f"   [{idx}] {term} (freq: {count})")
                flat_list.append(term)
                idx += 1

        print("-" * 60)
        print("💡 STEP 1: GLOSSARY (Pilih nomor yang mau di-translate)")
        print("   (Contoh: 1,3,5 atau tekan ENTER untuk skip)")

        sel_glossary = input("Glossary >> ").strip()

        print("\n🗑️ STEP 2: IGNORE (Pilih nomor yang MAU DIBUANG selamanya)")
        print("   (Contoh: 2,4,6 atau tekan ENTER untuk skip)")

        sel_ignore = input("Ignore >> ").strip()

        # Process Glossary Selection
        if sel_glossary:
            selected_indices = []
            parts = sel_glossary.replace(" ", "").split(",")
            for p in parts:
                if p.isdigit():
                    val = int(p)
                    if 1 <= val <= len(flat_list):
                        selected_indices.append(val - 1)

            if selected_indices:
                print("\n⏳ Auto-translating selected terms...")
                from deep_translator import GoogleTranslator
                translator = GoogleTranslator(source='en', target='id')

                print("\n📋 Copy-paste ini ke glossary.json:")
                print("==========================================")

                for i in selected_indices:
                    term = flat_list[i]
                    try:
                        trans = translator.translate(term).lower()
                        print(f'    "{term}": "{trans}",')
                    except:
                        print(f'    "{term}": "",  # Gagal translate otomatis')
                print("==========================================\n")

        # Process Ignore Selection
        if sel_ignore:
            ignored_indices = []
            parts = sel_ignore.replace(" ", "").split(",")
            for p in parts:
                if p.isdigit():
                    val = int(p)
                    if 1 <= val <= len(flat_list):
                        ignored_indices.append(val - 1)

            if ignored_indices:
                new_ignored = [flat_list[i] for i in ignored_indices]
                current_ignore_list = load_ignore_list()
                updated_ignore_list = current_ignore_list.union(set(new_ignored))
                save_ignore_list(updated_ignore_list)
            else:
                print("⚠️ Tidak ada nomor valid untuk di-ignore.")

    else:
        print("\n✅ No new terms found.")

def get_txt_files():
    """Recursively find .txt files."""
    convert_dir = BASE_DIR / "convert txt"
    if not convert_dir.exists():
        print(f"❌ Directory not found: {convert_dir}")
        return []

    files = []
    # rglog for recursive
    for path in convert_dir.rglob("*.txt"):
        try:
            rel_path = path.relative_to(convert_dir)
            # detect category from first parent folder
            label = rel_path.parts[0] if rel_path.parts else "root"

            files.append({
                "path": path,
                "name": path.name,
                "label": label,
                "size": path.stat().st_size
            })
        except Exception as e:
            print(f"⚠️ Error reading file stats: {path} ({e})")

    # Newest first
    files.sort(key=lambda x: x["path"].stat().st_mtime, reverse=True)
    return files

def main():
    print("� Starting Glossary Tool...", flush=True)

    if len(sys.argv) < 2:
        print("\nUsage:")
        print("  python glossary_list.py single   -> Pilih 1 file")
        print("  python glossary_list.py multiple -> Pilih banyak file")
        return

    arg = sys.argv[1].lower()

    # Direct file
    if arg.endswith(".txt"):
        p = Path(arg)
        if p.exists():
            with open(p, "r", encoding="utf-8") as f:
                suggest_terms(f.read())
        else:
            print(f"❌ File path not found: {p}")
        return

    # Interactive
    if arg in ["single", "multiple"]:
        print(f"📂 Scanning folder: {BASE_DIR / 'convert txt'} ...")
        files = get_txt_files()

        if not files:
            print("❌ No .txt files found.")
            return

        print("\n� Daftar File Transcript:")
        print("-" * 60)
        for i, f in enumerate(files, 1):
            kb = f['size'] / 1024
            print(f"[{i}] {f['name']} ({f['label']}) - {kb:.1f} KB")
        print("-" * 60)

        sel = input("Pilih nomor (contoh: 1 atau 1,3): ").strip()
        if not sel: return

        parts = [p.strip() for p in sel.split(",")]
        combined_text = ""
        count = 0

        for p in parts:
            if p.isdigit():
                idx = int(p) - 1
                if 0 <= idx < len(files):
                    target = files[idx]
                    print(f"📖 Reading: {target['name']}")
                    try:
                        with open(target['path'], "r", encoding="utf-8") as f:
                            combined_text += f.read() + " "
                        count += 1
                        if arg == "single": break # single mode only takes first valid selection
                    except Exception as e:
                        print(f"❌ Error: {e}")

        if count > 0:
            suggest_terms(combined_text)
        else:
            print("❌ Selection invalid.")

if __name__ == "__main__":
    main()
