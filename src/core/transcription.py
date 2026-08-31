import os
from pathlib import Path
from datetime import datetime
from tqdm import tqdm

from typing import Callable, Optional
from config import SUPPORTED_LANGS, OUTPUT_MULTIPLE, OUTPUT_SINGLE
from core.translator import translate_text, load_glossary
from utils import get_audio_info_technical, repair_audio_ffmpeg, format_time_srt, find_ffmpeg
import subprocess

def transcribe_audio(model, audio_path: Path, language: str = None, verbose: bool = True, progress_callback: Optional[Callable[[float], None]] = None, beam_size: int = 5) -> dict:
    """transkripsi file audio ke teks menggunakan Whisper"""
    if verbose:
        print(f"🎤 Transcribing: {audio_path.name} (beam_size={beam_size})")

    if not audio_path.exists():
        raise FileNotFoundError(f"Audio file not found: {audio_path}")

    # Technical Pre-check
    tech_info = get_audio_info_technical(audio_path)
    if tech_info.get("success") and verbose:
        print(f"   📏 Technical Duration: {tech_info['duration']:.1f}s | Bitrate: {tech_info['bitrate'] // 1000}kbps | Freq: {tech_info['sample_rate']}Hz")

    lang_param = None if language == "auto" else language
    lang_display = SUPPORTED_LANGS.get(language, "Auto-detect")
    if verbose:
        print(f"   Language mode: {lang_display}")

    # Auto-Chunking for Large Files (> 1.5 hours)
    CHUNK_THRESHOLD_SEC = 5400
    CHUNK_LENGTH_SEC = 3600
    
    if tech_info.get("success") and tech_info["duration"] > CHUNK_THRESHOLD_SEC:
        if verbose:
            print(f"   ⚠️  DURASI SANGAT PANJANG ({tech_info['duration']/3600:.1f} Jam). AUTO-CHUNKING AKTIF.")
            print(f"      Memotong audio menjadi bagian {CHUNK_LENGTH_SEC//60} menit untuk mencegah crash (OOM)...")
        
        project_root = Path(__file__).parent.parent.parent
        chunk_dir = project_root / "temp" / "chunks" / audio_path.stem
        chunk_dir.mkdir(parents=True, exist_ok=True)
        
        # Cleanup existing chunks if any
        for f in chunk_dir.glob("chunk_*.wav"):
            try: f.unlink()
            except: pass
            
        try:
            ffmpeg_bin = find_ffmpeg()
            chunk_pattern = str(chunk_dir / "chunk_%03d.wav")
            
            cmd = [
                ffmpeg_bin, "-y", "-i", str(audio_path),
                "-f", "segment", "-segment_time", str(CHUNK_LENGTH_SEC),
                "-c:a", "pcm_s16le", "-ar", "16000", "-ac", "1",
                chunk_pattern
            ]
            
            subprocess.run(cmd, capture_output=True, check=False)
            chunks = sorted(chunk_dir.glob("chunk_*.wav"))
        except Exception as e:
            if verbose: print(f"   ❌ Error saat memotong: {e}")
            chunks = []
            
        if not chunks:
            if verbose: print("   ❌ Auto-chunking gagal. Melanjutkan file asli (rentan crash)...")
        else:
            if verbose: print(f"   ✅ Audio berhasil dipotong menjadi {len(chunks)} bagian.")
            
            full_text = ""
            all_segments = []
            detected = None
            prob = 0.0
            
            pbar = None
            if verbose:
                pbar = tqdm(total=tech_info["duration"], unit="s", unit_scale=True, bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}]")
            
            last_end_total = 0
            for i, chunk in enumerate(chunks):
                if verbose: print(f"\n   🔄 Memproses Part {i+1}/{len(chunks)}...")
                try:
                    c_segments, c_info = model.transcribe(
                        str(chunk),
                        language=lang_param,
                        beam_size=beam_size,
                        word_timestamps=True,
                        vad_filter=True,
                    )
                    
                    if i == 0:
                        detected = c_info.language
                        prob = c_info.language_probability
                        
                    offset = i * CHUNK_LENGTH_SEC
                    last_end_local = 0
                    
                    for segment in c_segments:
                        text = segment.text.strip()
                        full_text += text + "\n"
                        adj_start = segment.start + offset
                        adj_end = segment.end + offset
                        
                        all_segments.append({
                            "start": adj_start, 
                            "end": adj_end, 
                            "text": text
                        })
                        
                        if pbar:
                            increment = segment.end - last_end_local
                            if increment > 0:
                                pbar.update(increment)
                                last_end_total += increment
                        
                        if progress_callback and tech_info["duration"] > 0:
                            progress = (adj_end / tech_info["duration"]) * 100
                            progress_callback(min(progress, 100.0))
                            
                        last_end_local = segment.end
                        
                    # Fix progress bar for exact chunk duration if slightly off
                    chunk_duration = c_info.duration
                    if pbar and (chunk_duration - last_end_local) > 0:
                        pbar.update(chunk_duration - last_end_local)
                        last_end_total += (chunk_duration - last_end_local)
                except Exception as e:
                    if verbose: print(f"   ❌ Gagal memproses part {i+1}: {e}")
                    
            if pbar:
                if (tech_info["duration"] - last_end_total) > 0:
                    pbar.update(tech_info["duration"] - last_end_total)
                pbar.close()
                
            # Cleanup chunks
            try:
                for f in chunks: f.unlink()
                chunk_dir.rmdir()
            except:
                pass
                
            return {
                "text": full_text.strip(),
                "language": detected,
                "language_mode": language,
                "language_probability": prob,
                "segments": all_segments,
            }

    segments, info = model.transcribe(
        str(audio_path),
        language=lang_param,
        beam_size=beam_size,
        word_timestamps=True,
        vad_filter=True,
    )

    total_duration = info.duration
    detected = info.language
    prob = info.language_probability

    if verbose:
        print(f"   ⏱️  Detected duration: {total_duration:.1f} seconds ({total_duration / 60:.1f} min)")

    # Auto-Repair Logic
    actual_audio_path = audio_path
    is_temp = False

    if tech_info.get("success") and abs(total_duration - tech_info["duration"]) > 10:
        if verbose:
            print("   ⚠️  MISMATCH DETECTED! Duration differs from technical info.")
            print("      🚀 AUTO-REPAIR: Mencoba memperbaiki file audio...")

        repaired_path = repair_audio_ffmpeg(audio_path)
        if repaired_path:
            actual_audio_path = repaired_path
            is_temp = True
            if verbose:
                print("   🔄 Retrying transcription with repaired file...")
            segments, info = model.transcribe(
                str(actual_audio_path),
                language=lang_param,
                beam_size=beam_size,
                word_timestamps=True,
                vad_filter=False,
            )
            total_duration = info.duration
            detected = info.language
            prob = info.language_probability
        else:
            if verbose:
                print("   ❌ Auto-repair failed. Continuing with original file.")

    pbar = None
    if verbose:
        pbar = tqdm(total=total_duration, unit="s", unit_scale=True, bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}]")

    full_text = ""
    all_segments = []
    last_end = 0

    for segment in segments:
        text = segment.text.strip()
        full_text += text + "\n"
        all_segments.append({"start": segment.start, "end": segment.end, "text": text})
        
        if pbar:
            increment = segment.end - last_end
            if increment > 0:
                pbar.update(increment)
                
        if progress_callback and total_duration > 0:
            progress = (segment.end / total_duration) * 100
            progress_callback(min(progress, 100.0))
            
        last_end = segment.end

    if pbar:
        pbar.update(total_duration - last_end)
        pbar.close()

    if is_temp and actual_audio_path.exists():
        try:
            actual_audio_path.unlink()
        except Exception as e:
            if verbose: print(f"   ⚠️ Could not delete temp file: {e}")

    return {
        "text": full_text.strip(),
        "language": detected,
        "language_mode": language,
        "language_probability": prob,
        "segments": all_segments,
    }


def prepare_smart_text(segments: list, lang: str) -> str:
    """Gabungkan segmen dengan cerdas berdasarkan jeda dan konteks bahasa"""
    if not segments:
        return ""

    is_ja = lang in ["ja", "auto"]
    ja_enders = ["か", "?", "ね", "よ", "です", "ます", "。", "！"]
    ja_conjunctions = ["てか", "でも", "それで", "あ", "あ!", "じゃあ", "けど", "あの", "えっと"]

    smart_text = ""
    for i, curr in enumerate(segments):
        text = curr["text"].strip()
        if not text:
            continue

        if i > 0:
            prev = segments[i - 1]
            gap = curr["start"] - prev["end"]

            if gap > 20:
                smart_text += "\n\n"
            elif gap > 3:
                smart_text += "\n"
            elif is_ja and any(prev["text"].strip().endswith(e) for e in ja_enders):
                smart_text += "\n"
            elif is_ja and any(text.startswith(c) for c in ja_conjunctions):
                smart_text += "\n"
            else:
                smart_text += "" if is_ja else " "

        smart_text += text
    return smart_text


def save_transcript(result: dict, output_path: Path, source_file: str, translated_text: str = None, target_lang: str = None):
    """Simpan hasil transkripsi ke file txt dan srt"""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    lang_mode = SUPPORTED_LANGS.get(result["language_mode"], "Auto")

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(f"Source: {source_file}\n")
        f.write(f"Language Mode: {lang_mode}\n")
        f.write(f"Detected: {result['language']} ({result['language_probability']:.1%})\n")
        f.write(f"Transcribed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write("=" * 50 + "\n\n")

        semicolon_text = " ; ".join([s["text"].strip() for s in result["segments"]])
        f.write(semicolon_text)

        f.write("\n\n" + "=" * 50 + "\n")
        f.write("TIMESTAMPS (SRT Format):\n\n")
        for i, seg in enumerate(result["segments"], 1):
            start = format_time_srt(seg["start"])
            end = format_time_srt(seg["end"])
            f.write(f"{i}\n{start} --> {end}\n{seg['text'].strip()}\n\n")

        if translated_text:
            f.write("=" * 50 + "\n\n")
            f.write(f"TRANSLATION ({target_lang.upper()}):\n\n")
            f.write(translated_text)
            f.write("\n\n")

    srt_path = output_path.with_suffix(".srt")
    with open(srt_path, "w", encoding="utf-8") as f:
        for i, seg in enumerate(result["segments"], 1):
            start = format_time_srt(seg["start"])
            end = format_time_srt(seg["end"])
            f.write(f"{i}\n{start} --> {end}\n{seg['text'].strip()}\n\n")

    print(f"💾 Saved TXT: {output_path.name}")
    print(f"🎬 Saved SRT: {srt_path.name}\n")


def get_relative_path_from_audio(file_or_folder: Path, audio_folder: Path) -> str:
    try:
        return str(file_or_folder.relative_to(audio_folder))
    except ValueError:
        return file_or_folder.name

def get_mirror_output_path(audio_file: Path, selected_folder: Path, timestamp: str, audio_folder: Path) -> Path:
    rel_path = audio_file.relative_to(selected_folder)
    output_base = OUTPUT_MULTIPLE / get_relative_path_from_audio(selected_folder, audio_folder)
    output_folder = output_base / rel_path.parent
    output_folder.mkdir(parents=True, exist_ok=True)
    output_name = f"{audio_file.stem}.txt"
    return output_folder / output_name

def process_file(model, audio_file: Path, output_folder: Path, language: str, do_translate: bool = False, target_lang: str = "id", preserve_structure: bool = False, selected_folder: Path = None, timestamp: str = None, verbose: bool = True, audio_base_folder: Path = None, progress_callback: Optional[Callable[[float], None]] = None, beam_size: int = 5, is_cancelled: Optional[Callable[[], bool]] = None):
    """Proses file audio tunggal dari transkripsi hingga translasi"""
    if timestamp is None:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    if preserve_structure and selected_folder and audio_base_folder:
        output_path = get_mirror_output_path(audio_file, selected_folder, timestamp, audio_base_folder)
    else:
        output_name = f"{audio_file.stem}.txt"
        output_path = output_folder / output_name
        
    srt_path = output_path.with_suffix(".srt")
    
    # Mencegah proses double jika TXT dan SRT sudah ada di output path
    if output_path.exists() and srt_path.exists():
        if verbose:
            print(f"   ⏩ SKIPPED: TXT dan SRT sudah ada di {output_path.parent.name}")
        dummy_result = {
            "text": "",
            "language": language if language != "auto" else "id",
            "language_mode": language,
            "language_probability": 1.0,
            "segments": [],
            "skipped": True,
        }
        return dummy_result, output_path

    result = transcribe_audio(model, audio_file, language, verbose=verbose, progress_callback=progress_callback, beam_size=beam_size)
    
    if not result:
        return None, output_path

    translated_text = None
    detected = (result["language"] or "").lower().strip()
    requested_target = (target_lang or "id").lower().strip()
    
    should_translate = do_translate and (detected != requested_target)

    if should_translate:
        if is_cancelled and is_cancelled():
            raise InterruptedError("Cancelled before translation")
        load_glossary()
        if verbose:
            print(f"   🌐 Translating transcript to '{requested_target}'...")
        smart_text = prepare_smart_text(result["segments"], result["language"])
        translated_text = translate_text(smart_text, requested_target, source_lang=result["language"], verbose=verbose, is_cancelled=is_cancelled)

    save_transcript(result, output_path, audio_file.name, translated_text, requested_target)
    return result, output_path
