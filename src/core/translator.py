import json
import os
import re
import random
import time
from typing import Optional, Callable
from tqdm import tqdm
from deep_translator import GoogleTranslator
from config import BASE_DIR, AUTO_TRANSLATE_TARGET

# Global glossary state
GLOSSARY = {
    "data scientist": "ilmuwan data",
}
_GLOSSARY_PATTERNS = {}
_GLOSSARY_MAPPING = {}

def load_glossary():
    """Load glossary from assets/glossary.json and pre-compile regex patterns"""
    global GLOSSARY, _GLOSSARY_PATTERNS, _GLOSSARY_MAPPING
    glossary_path = BASE_DIR / "assets" / "glossary.json"

    if glossary_path.exists():
        try:
            with open(glossary_path, "r", encoding="utf-8") as f:
                GLOSSARY = json.load(f)
            print(f"📘 Glossary loaded: {len(GLOSSARY)} terms")
        except Exception as e:
            print(f"⚠️ Failed to load glossary: {e}")
    else:
        print("⚠️ Glossary file not found, using minimal default.")

    _GLOSSARY_PATTERNS = {}
    _GLOSSARY_MAPPING = {}
    for english_term, indonesian_term in GLOSSARY.items():
        try:
            pattern = re.compile(re.escape(english_term), re.IGNORECASE)
            _GLOSSARY_PATTERNS[english_term] = pattern
            _GLOSSARY_MAPPING[english_term] = f"{indonesian_term} ({english_term})"
        except Exception as e:
            print(f"⚠️ Warning: Could not compile pattern for '{english_term}': {e}")


def apply_glossary_pre(text: str) -> tuple[str, dict]:
    """Replace technical terms with temporary markers"""
    mapping = {}
    modified_text = text

    if not _GLOSSARY_PATTERNS:
        return text, {}

    sorted_terms = sorted(_GLOSSARY_PATTERNS.keys(), key=len, reverse=True)
    for i, english_term in enumerate(sorted_terms):
        pattern = _GLOSSARY_PATTERNS[english_term]
        matches = list(pattern.finditer(modified_text))
        if not matches:
            continue

        marker = f"__GLOSS_ID_{i}__"
        mapping[marker] = _GLOSSARY_MAPPING[english_term]
        modified_text = pattern.sub(marker, modified_text)

    return modified_text, mapping


def apply_glossary_post(text: str, mapping: dict) -> str:
    """Restore markers with final format"""
    for marker, replacement in mapping.items():
        text = text.replace(marker, replacement)
    return text


def translate_text_ollama(text: str, target_lang: str, model_name: str) -> str:
    """Send text to Ollama API for high-quality translation"""
    import requests

    ollama_url = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/generate")
    lang_name = "Indonesian" if target_lang == "id" else "English"

    prompt = f"""
You are a professional translator. Translate the following text into natural and professional {lang_name}.
CRITICAL RULES:
1. ONLY output the {lang_name} translation. Do not add any explanations or notes.
2. DO NOT repeat the original text.
3. DO NOT output any characters from the original language.
4. Keep the original meaning but make it sound like a natural conversation, not a robot translation.
5. If the text contains markers like __GLOSS_ID_n__, keep them exactly as they are.

TEXT TO TRANSLATE:
{text}

ONLY {lang_name.upper()} TRANSLATION:
"""
    payload = {"model": model_name, "prompt": prompt, "stream": False}

    try:
        response = requests.post(ollama_url, json=payload, timeout=300)
        response.raise_for_status()
        return response.json().get("response", "").strip()
    except Exception as e:
        print(f"   ⚠️ Ollama translation error: {e}")
        return None


def translate_text(
    text: str, target_lang: str = "id", source_lang: str = None, verbose: bool = True, is_cancelled: Optional[Callable[[], bool]] = None
) -> str:
    """Translate text with smart chunking and API safety"""
    use_ollama = os.environ.get("USE_OLLAMA_TRANSLATION", "false").lower() == "true"
    ollama_model = os.environ.get("OLLAMA_TRANSLATION_MODEL", "qwen3:8b")

    s_lang = (source_lang or "auto").lower()

    is_asian = s_lang in ["ja", "zh", "ko"]
    if not source_lang:
        if any("\u3040" <= c <= "\u30ff" or "\u4e00" <= c <= "\u9fff" for c in text[:300]):
            is_asian = True
            s_lang = "ja"

    MAX_CHARS = 800 if is_asian else 1800

    lines = [line.strip() for line in text.split("\n") if line.strip()]
    if not lines:
        return ""

    if verbose:
        mode = "OLLAMA" if use_ollama else "GOOGLE"
        print(f"   🌐 Translating {s_lang.upper()} -> {target_lang.upper()} using {mode}...")

    import textwrap
    chunks = []
    current_chunk = []
    current_len = 0

    for line in lines:
        if len(line) > MAX_CHARS:
            sublines = textwrap.wrap(line, width=MAX_CHARS, break_long_words=False)
        else:
            sublines = [line]
            
        for sl in sublines:
            if current_len + len(sl) > MAX_CHARS and current_chunk:
                chunks.append(current_chunk)
                current_chunk = []
                current_len = 0

            current_chunk.append(sl)
            current_len += len(sl) + 1

    if current_chunk:
        chunks.append(current_chunk)

    translated_chunks = []
    translator = GoogleTranslator(source=s_lang, target=target_lang)

    for i, chunk_lines in enumerate(tqdm(chunks, desc="Translating", unit="chunk", leave=False, disable=not verbose)):
        if is_cancelled and is_cancelled():
            raise InterruptedError("Cancelled during translation")

        joined_text = "\n".join(chunk_lines)
        marked_text, mapping = apply_glossary_pre(joined_text)

        result = None
        max_retries = 3

        for attempt in range(max_retries):
            try:
                if use_ollama:
                    result = translate_text_ollama(marked_text, target_lang, ollama_model)
                else:
                    result = translator.translate(marked_text)
                    if result and result.strip() == marked_text.strip() and len(marked_text) > 20:
                        if s_lang != "auto":
                            alt_tr = GoogleTranslator(source="auto", target=target_lang)
                            result = alt_tr.translate(marked_text)

                if result and result.strip() != marked_text.strip():
                    break

                if attempt < max_retries - 1:
                    wait_time = (attempt + 1) * 5 + random.uniform(1, 3)
                    time.sleep(wait_time)

            except Exception as e:
                err_str = str(e)
                err_summary = err_str.split('-->')[-1].strip() if '-->' in err_str else (err_str[:120] + ('...' if len(err_str) > 120 else ''))
                tqdm.write(f"   ⚠️ Translation chunk {i+1} attempt {attempt+1}: {err_summary}")
                err_msg = err_str.lower()
                is_conn_error = any(kw in err_msg for kw in ["connection", "timeout", "network", "api connection"])
                if attempt < max_retries - 1:
                    wait_time = ((attempt + 1) * 3 if is_conn_error else (attempt + 1) * 2)
                    time.sleep(wait_time)

        if not result or result.strip() == marked_text.strip():
            tqdm.write(f"   ❌ Could not translate chunk {i+1}, returning original text.")
            result = marked_text

        final_text = apply_glossary_post(result, mapping)
        translated_chunks.append(final_text)

        if not use_ollama and i < len(chunks) - 1:
            time.sleep(random.uniform(1.2, 2.5))

    return "\n\n".join(translated_chunks)
