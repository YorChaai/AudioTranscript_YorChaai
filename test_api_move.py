import urllib.request
import json

data = {
    "files": ["audio/bkp/lalaland/asdasd/tidurcepat.mp3.MP3"],
    "targetPath": "bkp"
}
req = urllib.request.Request(
    "http://localhost:5000/api/file/move", 
    data=json.dumps(data).encode("utf-8"), 
    headers={"Content-Type": "application/json"}
)

try:
    with urllib.request.urlopen(req) as response:
        print(response.read().decode())
except Exception as e:
    print("Error:", e)
