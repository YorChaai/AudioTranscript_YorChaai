import requests
import time
import os

BASE_URL = "http://localhost:5000/api"

def test_server():
    print(f"Testing server at {BASE_URL}...")
    
    # 1. Health Check
    try:
        resp = requests.get(f"{BASE_URL}/health")
        print(f"Health Check: {resp.status_code} - {resp.json()}")
    except Exception as e:
        print(f"Health Check Failed: {e}")
        return

    # 2. List Audio
    try:
        resp = requests.get(f"{BASE_URL}/audio/list")
        if resp.status_code == 200:
            print(f"List Audio: OK ({len(resp.json()['files'])} files)")
        else:
            print(f"List Audio Failed: {resp.status_code}")
    except Exception as e:
        print(f"List Audio Error: {e}")

    # 3. Upload Dummy File
    dummy_file = "test_audio.mp3"
    with open(dummy_file, "wb") as f:
        f.write(b"fake audio content")
    
    try:
        with open(dummy_file, "rb") as f:
            files = {"file": (dummy_file, f, "audio/mpeg")}
            resp = requests.post(f"{BASE_URL}/audio/upload", files=files)
            if resp.status_code == 200:
                print(f"Upload: OK - {resp.json()}")
            else:
                print(f"Upload Failed: {resp.status_code} - {resp.text}")
    except Exception as e:
        print(f"Upload Error: {e}")
    finally:
        if os.path.exists(dummy_file):
            os.remove(dummy_file)

if __name__ == "__main__":
    test_server()
