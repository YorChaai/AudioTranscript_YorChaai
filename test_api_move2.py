import urllib.request
import json
import os
from dotenv import load_dotenv
load_dotenv()
api_key = os.getenv("API_KEY", "your_secret_api_key_here")

data = {
    "files": ["audio/bkp/lalaland/asdasd/tidurcepat.mp3.MP3"],
    "targetPath": "bkp"
}
req = urllib.request.Request(
    "http://localhost:5000/api/file/move", 
    data=json.dumps(data).encode("utf-8"), 
    headers={
        "Content-Type": "application/json",
        "X-API-Key": api_key
    }
)

try:
    with urllib.request.urlopen(req) as response:
        print("Status:", response.status)
        print("Response:", response.read().decode())
except urllib.error.HTTPError as e:
    print("HTTP Error:", e.code, e.read().decode())
except Exception as e:
    print("Error:", e)
