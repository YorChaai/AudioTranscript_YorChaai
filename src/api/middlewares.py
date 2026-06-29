import time
import threading
from functools import wraps
from flask import request, jsonify
from config import RATE_LIMIT_REQUESTS, RATE_LIMIT_WINDOW, API_KEY

_rate_limit_cache = {}  # ip -> list of request timestamps
_rate_limit_lock = threading.Lock()
_cleanup_counter = 0

def info(msg):
    print(f"ℹ️ {msg}")

def _get_client_ip() -> str:
    """Get client IP from request"""
    if request.headers.get("X-Forwarded-For"):
        return request.headers.get("X-Forwarded-For").split(",")[0].strip()
    return request.remote_addr or "unknown"

def _check_rate_limit(client_ip: str) -> bool:
    """
    Check if client IP has exceeded rate limit.
    Returns True if request is allowed, False if rate limited.
    """
    now = time.time()
    window_start = now - RATE_LIMIT_WINDOW

    with _rate_limit_lock:
        if client_ip not in _rate_limit_cache:
            _rate_limit_cache[client_ip] = []

        # Remove old timestamps outside window
        _rate_limit_cache[client_ip] = [
            ts for ts in _rate_limit_cache[client_ip] if ts > window_start
        ]

        if not _rate_limit_cache[client_ip]:
            del _rate_limit_cache[client_ip]
            _rate_limit_cache[client_ip] = []

        if len(_rate_limit_cache[client_ip]) >= RATE_LIMIT_REQUESTS:
            return False

        _rate_limit_cache[client_ip].append(now)
        return True

def _cleanup_rate_limit_cache():
    """Periodic cleanup of rate limit cache to prevent memory leak."""
    now = time.time()
    cleanup_threshold = 3600  # 1 hour

    with _rate_limit_lock:
        empty_ips = []
        for ip, timestamps in list(_rate_limit_cache.items()):
            recent_timestamps = [
                ts for ts in timestamps if ts > now - cleanup_threshold
            ]
            if recent_timestamps:
                _rate_limit_cache[ip] = recent_timestamps
            else:
                empty_ips.append(ip)

        for ip in empty_ips:
            _rate_limit_cache.pop(ip, None)

        if empty_ips:
            info(f"🧹 Cleaned up {len(empty_ips)} inactive IPs from rate limit cache")

def rate_limited_endpoint(f):
    """Decorator to add rate limiting to endpoints"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        global _cleanup_counter
        client_ip = _get_client_ip()
        
        if not _check_rate_limit(client_ip):
            info(f"⚠️ Rate limit exceeded for IP: {client_ip}")
            return jsonify(
                {
                    "error": "Rate limit exceeded. Please try again later.",
                    "limit": RATE_LIMIT_REQUESTS,
                    "window": f"{RATE_LIMIT_WINDOW}s",
                }
            ), 429

        _cleanup_counter += 1
        if _cleanup_counter >= 1000:
            _cleanup_rate_limit_cache()
            _cleanup_counter = 0

        return f(*args, **kwargs)

    return decorated_function

def require_api_key(f):
    """Decorator to enforce API key authentication"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if request.endpoint == "health_check":
            return f(*args, **kwargs)
        key = request.headers.get("X-Api-Key")
        if key == API_KEY:
            return f(*args, **kwargs)
        return jsonify({"error": "Unauthorized: Invalid API Key"}), 401

    return decorated_function
