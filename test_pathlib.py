import pathlib

BASE_DIR = pathlib.Path(__file__).resolve().parent
AUDIO_FOLDER = BASE_DIR / "audio"

src = (BASE_DIR / "audio" / "test.mp3").resolve()

print("AUDIO_FOLDER.resolve():", AUDIO_FOLDER.resolve())
print("src.parents:", list(src.parents))

if AUDIO_FOLDER.resolve() in src.parents:
    print("It is IN parents!")
else:
    print("It is NOT IN parents!")
