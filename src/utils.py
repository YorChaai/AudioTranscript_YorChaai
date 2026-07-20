"""
Shared utilities for audio/video conversion and common operations
Fix H7: Centralize duplicate code from transcribe.py and server.py
"""

import os
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from typing import List, Optional

# ============================================================================
# SHARED CONSTANTS - Centralized definitions (DRY principle)
# ============================================================================

# Media file extensions
AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".flac", ".ogg", ".wma", ".aac", ".mp4"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".mpeg", ".mpg", ".m4v"}
MEDIA_EXTENSIONS = AUDIO_EXTENSIONS | VIDEO_EXTENSIONS

# Language choices
LANGUAGE_CHOICES = {
    "id": "Indonesian",
    "en": "English",
    "ja": "Japanese",
    "auto": "Auto-detect (Mixed)",
}

# Model size recommendations
MODEL_RECOMMENDATIONS = {
    "tiny": {"vram_min_gb": 0.5, "speed": "fastest", "accuracy": "lowest"},
    "small": {"vram_min_gb": 1, "speed": "fast", "accuracy": "decent"},
    "medium": {"vram_min_gb": 2, "speed": "balanced", "accuracy": "good"},
    "large-v3": {"vram_min_gb": 4, "speed": "slow", "accuracy": "best"},
}


def get_media_extensions():
    """Get all supported media extensions (audio + video)"""
    return MEDIA_EXTENSIONS


def get_audio_extensions():
    """Get audio-only extensions"""
    return AUDIO_EXTENSIONS


def get_video_extensions():
    """Get video-only extensions"""
    return VIDEO_EXTENSIONS


def find_ffmpeg(base_dir: Path = None, verbose: bool = False) -> str:
    """
    Find ffmpeg executable in common locations

    Args:
        base_dir: Base directory to search (optional)
        verbose: Whether to print found message

    Returns:
        Path to ffmpeg executable

    Raises:
        FileNotFoundError: If ffmpeg not found anywhere
    """
    if base_dir is None:
        base_dir = Path(__file__).parent

    # Check environment variable first
    env_path = os.environ.get("FFMPEG_PATH")
    if env_path:
        env_path_obj = Path(env_path)
        # If it points to a directory, look for ffmpeg.exe inside
        if env_path_obj.is_dir():
            env_path_obj = env_path_obj / "ffmpeg.exe"
        if env_path_obj.exists():
            if verbose: print(f"   FFmpeg found via FFMPEG_PATH: {env_path_obj}")
            return str(env_path_obj)

    # Check if ffmpeg is in PATH (Windows specific)
    ffmpeg_in_path = shutil.which("ffmpeg.exe") or shutil.which("ffmpeg")
    if ffmpeg_in_path:
        if verbose: print(f"   FFmpeg found in PATH: {ffmpeg_in_path}")
        return ffmpeg_in_path

    # Local candidates
    local_candidates = [
        base_dir / "ffmpeg.exe",
        base_dir / "bin" / "ffmpeg.exe",
        base_dir / "tools" / "ffmpeg.exe",
        base_dir / "tools" / "ffmpeg" / "bin" / "ffmpeg.exe",
        Path(r"C:\ffmpeg\bin\ffmpeg.exe"),
        Path(r"C:\Program Files\ffmpeg\bin\ffmpeg.exe"),
        Path(r"C:\ffmpeg\ffmpeg.exe"),
    ]

    # Check for installed FFmpeg in C:\ffmpeg\ffmpeg-*\bin\
    try:
        ffmpeg_root = Path(r"C:\ffmpeg")
        if ffmpeg_root.exists():
            for folder in ffmpeg_root.iterdir():
                if folder.is_dir() and folder.name.startswith("ffmpeg-"):
                    bin_folder = folder / "bin"
                    if bin_folder.exists():
                        ffmpeg_exe = bin_folder / "ffmpeg.exe"
                        if ffmpeg_exe.exists():
                            if verbose: print(f"   FFmpeg found: {ffmpeg_exe}")
                            return str(ffmpeg_exe)
    except Exception as e:
        if verbose: print(f"   Error scanning C:\\ffmpeg: {e}")

    for candidate in local_candidates:
        if candidate.exists():
            if verbose: print(f"   FFmpeg found: {candidate}")
            return str(candidate)

    # FFmpeg not found - raise error with helpful message
    print("\n" + "=" * 70)
    print("   ❌ FFMPEG NOT FOUND!")
    print("=" * 70)
    print("\n   FFmpeg is required for video conversion.")
    print("\n   INSTALLATION OPTIONS:")
    print("   " + "-" * 60)
    print("   1. Download from: https://www.gyan.dev/ffmpeg/builds/")
    print("      → Download 'ffmpeg-release-essentials.zip'")
    print("      → Extract to C:\\ffmpeg")
    print("      → Add C:\\ffmpeg\\bin to PATH")
    print("\n   2. Or use winget (Windows Package Manager):")
    print("      winget install Gyan.FFmpeg")
    print("\n   3. Or use chocolatey:")
    print("      choco install ffmpeg")
    print("=" * 70 + "\n")

    raise FileNotFoundError(
        "FFmpeg not found! Please install FFmpeg or set FFMPEG_PATH environment variable."
    )


def get_audio_info_technical(audio_path: Path) -> dict:
    """
    Mendapatkan durasi dan bitrate asli menggunakan ffprobe.
    Membantu mendeteksi jika file corrupt atau terpotong.
    """
    import json

    try:
        # We need ffprobe, which usually comes with ffmpeg
        ffmpeg_bin = find_ffmpeg(audio_path.parent)
        ffprobe_bin = str(Path(ffmpeg_bin).parent / "ffprobe.exe")
        if not Path(ffprobe_bin).exists():
            ffprobe_bin = "ffprobe"  # Fallback to PATH

        cmd = [
            ffprobe_bin,
            "-v",
            "quiet",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
            str(audio_path),
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            creationflags=subprocess.CREATE_NO_WINDOW
            if hasattr(subprocess, "CREATE_NO_WINDOW")
            else 0,
        )
        data = json.loads(result.stdout)

        # Ambil durasi dari format atau stream
        duration = float(data.get("format", {}).get("duration", 0))
        bitrate = int(data.get("format", {}).get("bit_rate", 0))

        # Ambil sample rate dari stream audio pertama
        sample_rate = 0
        for stream in data.get("streams", []):
            if stream.get("codec_type") == "audio":
                sample_rate = int(stream.get("sample_rate", 0))
                break

        return {
            "success": True,
            "duration": duration,
            "bitrate": bitrate,
            "sample_rate": sample_rate,
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


def repair_audio_ffmpeg(audio_path: Path, base_dir: Path = None) -> Path:
    """
    Repair/Normalize audio file to standard WAV (16kHz, mono)
    This is very effective for files with broken headers (VBR) or corruption.
    """
    if base_dir is None:
        base_dir = audio_path.parent

    # Create a 'temp' folder in the project root if it doesn't exist
    project_root = Path(__file__).parent.parent
    temp_dir = project_root / "temp" / "repaired"
    temp_dir.mkdir(parents=True, exist_ok=True)

    temp_path = (
        temp_dir / f"repaired_{audio_path.stem}_{datetime.now().strftime('%H%M%S')}.wav"
    )

    ffmpeg_bin = find_ffmpeg(base_dir)

    # Build command: Convert to 16kHz mono WAV
    command = [
        ffmpeg_bin,
        "-y",
        "-i",
        str(audio_path),
        "-ar",
        "16000",
        "-ac",
        "1",
        str(temp_path),
    ]

    print(f"   🔧 Repairing audio: {audio_path.name}")
    print("      (Converting to standard WAV 16kHz mono...)")

    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            creationflags=subprocess.CREATE_NO_WINDOW
            if hasattr(subprocess, "CREATE_NO_WINDOW")
            else 0,
        )

        if result.returncode != 0:
            print(f"   ❌ Repair failed: {result.stderr[:300]}")
            return None

        if not temp_path.exists() or temp_path.stat().st_size == 0:
            print("   ❌ Repaired file not created")
            return None

        print("   ✅ Repair successful! Using temporary file for transcription.")
        return temp_path
    except Exception as e:
        print(f"   ❌ Error during repair: {e}")
        return None


def convert_video_to_mp3(
    video_path: Path,
    output_folder: Path = None,
    base_dir: Path = None,
    verbose: bool = True,
) -> Path:
    """
    Convert video file to MP3 using ffmpeg

    Args:
        video_path: Path to video file
        output_folder: Folder to save MP3 (default: same as video)
        base_dir: Base directory for ffmpeg search (default: video parent)
        verbose: If False, suppress most print statements

    Returns:
        Path to converted MP3 file or None if failed
    """
    if base_dir is None:
        base_dir = video_path.parent

    if output_folder is None:
        output_folder = video_path.parent

    output_folder.mkdir(parents=True, exist_ok=True)

    if verbose:
        print(f"   🎬 Converting: {video_path.name}")

    # Output path
    audio_path = output_folder / f"{video_path.stem}.mp3"

    # Handle existing file
    counter = 1
    original_audio_path = audio_path
    while audio_path.exists():
        audio_path = output_folder / f"{original_audio_path.stem}_{counter}.mp3"
        counter += 1

    ffmpeg_bin = find_ffmpeg(base_dir)

    # Build command - use list format for subprocess (handles spaces automatically)
    command = [
        ffmpeg_bin,
        "-y",  # Overwrite output
        "-i",
        str(video_path),
        "-vn",  # No video
        "-acodec",
        "libmp3lame",
        "-q:a",
        "2",  # High quality
        str(audio_path),
    ]

    if verbose:
        print(f"   🔄 Command: {' '.join(command)}")

    try:
        # Use shell=False (safer, handles paths with spaces correctly via list args)
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            timeout=600,  # 10 minutes timeout
            creationflags=subprocess.CREATE_NO_WINDOW
            if hasattr(subprocess, "CREATE_NO_WINDOW")
            else 0,  # Hide console window on Windows
        )

        if result.returncode != 0:
            print(f"   ❌ Conversion failed ({video_path.name}): {result.stderr[:300]}")
            return None

        if not audio_path.exists() or audio_path.stat().st_size == 0:
            print(f"   ❌ Output file not created: {video_path.name}")
            return None

        if verbose:
            print(f"   ✅ Converted: {audio_path.name}")
        return audio_path

    except subprocess.TimeoutExpired:
        print(f"   ❌ Conversion timeout (>10 min): {video_path.name}")
        return None
    except Exception as e:
        print(f"   ❌ Error converting {video_path.name}: {e}")
        return None


def convert_video_to_mp3_parallel(
    video_files: List[Path],
    output_folder: Path = None,
    max_workers: int = 4,
    base_dir: Path = None,
) -> List[Optional[Path]]:
    """
    Convert multiple video files to MP3 in parallel (4 threads)
    Fix: Parallel processing for faster batch conversion

    Args:
        video_files: List of video paths to convert
        output_folder: Output folder (default: same as each video)
        max_workers: Number of parallel threads (default: 4)
        base_dir: Base directory for ffmpeg

    Returns:
        List of converted MP3 paths (None if failed)
    """
    from tqdm import tqdm

    results = []
    total = len(video_files)

    print(f"\n⚡ Starting parallel conversion ({max_workers} threads)...")
    print(f"   📊 Total files: {total}")
    print(f"   🔄 Processing: {', '.join([f.name for f in video_files[:3]])}")
    if total > 3:
        print(f"   ... and {total - 3} more")

    # Convert in parallel
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all conversion tasks
        future_to_video = {
            executor.submit(
                convert_video_to_mp3,
                video,
                output_folder if output_folder else video.parent,
                base_dir,
                False,  # verbose=False for parallel
            ): video
            for video in video_files
        }

        # Collect results as they complete
        for future in tqdm(
            as_completed(future_to_video),
            total=total,
            desc="Converting",
            unit="video",
            leave=False,
        ):
            video = future_to_video[future]
            try:
                result = future.result()
                results.append(result)
                if result:
                    # In parallel mode, we just let tqdm handle the progress
                    pass
                else:
                    print(f"   ❌ Failed: {video.name}")
            except Exception as e:
                print(f"   ❌ Error converting {video.name}: {e}")
                results.append(None)

    # Summary
    success_count = sum(1 for r in results if r is not None)
    print(f"\n✅ Conversion complete: {success_count}/{total} succeeded")

    return results


def format_time(seconds: float) -> str:
    """Convert seconds to MM:SS format"""
    minutes = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{minutes:02d}:{secs:02d}"


def format_time_srt(seconds: float) -> str:
    """Convert seconds to HH:MM:SS,mmm format for SRT"""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    millis = int((seconds - int(seconds)) * 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"


def ensure_dirs(*paths):
    """Create directories if they don't exist"""
    for path in paths:
        Path(path).mkdir(parents=True, exist_ok=True)


def get_file_size_mb(path: Path) -> float:
    """Get file size in MB"""
    return path.stat().st_size / (1024 * 1024)


def handle_pdf_conversion_prompt(generated_files: List[Path]):
    """
    Prompt user to convert generated text files to PDF.
    Commonly used at the end of transcription scripts.
    """
    if not generated_files:
        return

    print("\n" + "-" * 50)
    print("📄 PDF Conversion")
    choice = input("Convert to PDF? (1 = Yes, 0 = No): ").strip()

    if choice == "1":
        print("\n🔄 Generating PDFs...")
        try:
            import convert_pdf
            from pdf_utils import txt_to_pdf

            success = 0
            for txt_path in generated_files:
                if txt_to_pdf(str(txt_path)):
                    success += 1

            print(f"\n✨ PDF conversion completed ({success}/{len(generated_files)} successful).")
        except ImportError:
            print("❌ Error: convert_pdf module not found.")
        except Exception as e:
            print(f"❌ Error during PDF conversion: {e}")
    else:
        print("👌 Skipped PDF conversion.")
