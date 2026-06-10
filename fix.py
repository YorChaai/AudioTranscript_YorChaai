import re
import os

file_path = r'd:\2. Organize\1. Projects\audio convert to txt\src\server.py'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

auth_logic = '''from functools import wraps
from flask import request, jsonify
import os

API_KEY = os.environ.get("API_KEY", "YORCHAAI_SECRET_KEY")

def require_api_key(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if request.endpoint == 'health_check':
            return f(*args, **kwargs)
        key = request.headers.get("X-Api-Key")
        if key == API_KEY:
            return f(*args, **kwargs)
        return jsonify({"error": "Unauthorized: Invalid API Key"}), 401
    return decorated_function
'''

if 'def require_api_key(' not in content:
    content = content.replace('app = Flask(__name__)\nCORS(app)', 'app = Flask(__name__)\nCORS(app)\n\n' + auth_logic)

content = re.sub(r'(@app\.route\([^\)]+\)\n)(?!@require_api_key|@_rate_limited_endpoint)', r'\1@require_api_key\n', content)
# Ensure rate limit endpoints also get auth
content = re.sub(r'(@_rate_limited_endpoint\n)(?!@require_api_key)', r'\1@require_api_key\n', content)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
