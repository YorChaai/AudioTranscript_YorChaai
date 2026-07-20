import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
import os
from pathlib import Path
from dotenv import load_dotenv

# Base Directories
BASE_DIR = Path(__file__).parent.parent
SRC_DIR = BASE_DIR / "src"
AUDIO_FOLDER = BASE_DIR / "audio"
CONVERT_DIR = BASE_DIR / "output"
OUTPUT_SINGLE = BASE_DIR / "output" / "single"
OUTPUT_MULTIPLE = BASE_DIR / "output" / "multiple"
SUMMARY_DIR = BASE_DIR / "summary"
UPLOADS_DIR = BASE_DIR / "server" / "uploads"
VIDEO_UPLOAD_FOLDER = UPLOADS_DIR / "video"
DB_PATH = BASE_DIR / "server" / "app.db"

# Load environment variables
_env_path = BASE_DIR / ".env"
if _env_path.exists():
    load_dotenv(_env_path)
    print(f"✅ Loaded .env file from: {_env_path}")

# Supported Media Formats
AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".flac", ".ogg", ".wma", ".aac"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".mpeg", ".mpg", ".m4v"}
MEDIA_EXTENSIONS = AUDIO_EXTENSIONS | VIDEO_EXTENSIONS

# Server Configuration
API_KEY = os.environ.get("API_KEY", "YORCHAAI_SECRET_KEY")
MAX_CONTENT_LENGTH = 500 * 1024 * 1024  # max upload 500MB
RATE_LIMIT_REQUESTS = 100  # max requests per window
RATE_LIMIT_WINDOW = 60  # window in seconds

# Whisper ML Configuration
MODEL_SIZE = os.environ.get("WHISPER_MODEL_SIZE", "large-v3")
LOCAL_MODEL_PATH = os.environ.get("WHISPER_MODEL_PATH", "D:\\model\\large-v3")
DEVICE = "cuda"
COMPUTE_TYPE = "float16"
AUTO_TRANSLATE_TARGET = "id"

# Progress Constants
PROGRESS_MIN = 1
PROGRESS_MAX = 99
PROGRESS_LOADING = 1
PROGRESS_TRANSCRIBING_MIN = 1
PROGRESS_TRANSCRIBING_MAX = 99
PROGRESS_SAVING = 99
PROGRESS_COMPLETED = 100

# Supported Languages
SUPPORTED_LANGS = {
    "id": "Indonesian",
    "en": "English",
    "ja": "Japanese",
    "auto": "Auto-detect (Mixed)",
}

# Language Mapping for Menu (consistent across scripts)
LANGUAGE_MENU = {
    "1": {"code": "id", "name": "Indonesian"},
    "2": {"code": "en", "name": "English"},
    "3": {"code": "ja", "name": "Japanese"},
    "4": {"code": "auto", "name": "Auto-detect / Campuran"},
}

# Ensure required directories exist
def ensure_directories(verbose=False):
    dirs = [
        AUDIO_FOLDER, VIDEO_UPLOAD_FOLDER, CONVERT_DIR,
        SUMMARY_DIR, OUTPUT_SINGLE, OUTPUT_MULTIPLE,
        BASE_DIR / "server", BASE_DIR / "temp"
    ]
    for d in dirs:
        if not d.exists():
            d.mkdir(parents=True, exist_ok=True)
            if verbose:
                print(f"📁 Created directory: {d}")
