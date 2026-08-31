"""
Database module - SQLite dengan connection pooling untuk performance
"""

import os
import sqlite3
import json
from pathlib import Path
from datetime import datetime
from queue import Queue, Empty
import threading
from config import BASE_DIR, DB_PATH

# Fix M5: Configurable connection pool size via environment variable
# Default to 10, but can be overridden with DB_POOL_SIZE env var
POOL_SIZE = int(os.environ.get("DB_POOL_SIZE", "10"))
_connection_pool = None
_pool_lock = threading.Lock()
_temp_connections = []  # Track temporary connections to prevent leaks
_temp_connections_lock = threading.Lock()
_max_temp_connections = 5  # Limit temporary connections to prevent exhaustion
_initialized = False


def _create_tables(conn):
    """buat tabel jika belum ada"""
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS jobs (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            audio_file TEXT,
            language TEXT,
            do_translate INTEGER DEFAULT 0,
            target_lang TEXT DEFAULT 'id',
            output_file TEXT,
            progress REAL DEFAULT 0,
            error TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            duration_seconds REAL
        );

        CREATE TABLE IF NOT EXISTS history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            job_id TEXT,
            type TEXT NOT NULL,
            source_file TEXT,
            output_file TEXT,
            language TEXT,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            metadata TEXT,
            FOREIGN KEY (job_id) REFERENCES jobs(id)
        );

        -- Fix H8: Add indexes for performance
        CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
        CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs(created_at);
        CREATE INDEX IF NOT EXISTS idx_jobs_type ON jobs(type);
        CREATE INDEX IF NOT EXISTS idx_history_job_id ON history(job_id);
        CREATE INDEX IF NOT EXISTS idx_history_created_at ON history(created_at);
        CREATE INDEX IF NOT EXISTS idx_history_type ON history(type);
    """)
    conn.commit()


def _create_connection():
    """buat koneksi database baru"""
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    _create_tables(conn)
    return conn


def _init_pool():
    """inisialisasi connection pool"""
    global _connection_pool, _initialized
    if _initialized:
        return

    with _pool_lock:
        if _initialized:
            return

        _connection_pool = Queue(maxsize=POOL_SIZE)

        # Pre-create connections
        for _ in range(POOL_SIZE):
            try:
                conn = _create_connection()
                _connection_pool.put(conn)
            except Exception as e:
                print(f"⚠️ Warning: Could not create all pool connections: {e}")
                break

        _initialized = True
        print(f"✅ Database connection pool initialized ({_connection_pool.qsize()}/{POOL_SIZE} connections)")


def get_db():
    """
    ambil koneksi dari pool (non-blocking dengan timeout)
    Return connection yang harus dikembalikan ke pool setelah selesai
    """
    if not _initialized:
        _init_pool()

    try:
        conn = _connection_pool.get(timeout=5.0)
        return conn
    except Empty:
        # Pool exhausted - create temporary connection with tracking
        with _temp_connections_lock:
            if len(_temp_connections) < _max_temp_connections:
                print("⚠️ Warning: Connection pool exhausted, creating temporary connection")
                temp_conn = _create_connection()
                _temp_connections.append(temp_conn)
                return temp_conn
            else:
                # Too many temp connections - wait for pool
                print("⚠️ Warning: Too many temporary connections, waiting for pool...")
                return _connection_pool.get(timeout=30.0)  # Wait longer


def return_db(conn):
    """
    kembalikan koneksi ke pool
    WAJIB dipanggil setelah selesai menggunakan koneksi
    """
    if not _initialized or _connection_pool is None:
        try:
            conn.close()
        except Exception:
            pass
        return

    # Check if this is a temporary connection
    is_temp = False
    with _temp_connections_lock:
        if conn in _temp_connections:
            is_temp = True
            _temp_connections.remove(conn)

    with _pool_lock:
        try:
            # Test if connection is still valid
            conn.execute("SELECT 1")

            if is_temp:
                # Don't return temp connections to pool - close them
                conn.close()
            else:
                _connection_pool.put_nowait(conn)
        except Exception:
            # Connection invalid, create new one
            try:
                new_conn = _create_connection()
                _connection_pool.put_nowait(new_conn)
            except Exception:
                pass
            finally:
                try:
                    conn.close()
                except Exception:
                    pass


def get_db_context():
    """
    Context manager untuk database connection
    Usage:
        with get_db_context() as conn:
            conn.execute(...)
    """
    return DatabaseContextManager()


class DatabaseContextManager:
    """Context manager untuk auto return connection ke pool"""

    def __init__(self):
        self.conn = None

    def __enter__(self):
        self.conn = get_db()
        return self.conn

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.conn:
            return_db(self.conn)
        return False


# Fix C4: Wrapper functions dengan auto connection management
def create_job(job_id, job_type, audio_file, language, do_translate=False, target_lang='id'):
    """buat job baru"""
    now = datetime.now().isoformat()
    conn = get_db()
    try:
        conn.execute(
            """INSERT INTO jobs (id, type, audio_file, language, do_translate, target_lang, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (job_id, job_type, audio_file, language, int(do_translate), target_lang, now, now)
        )
        conn.commit()
    finally:
        return_db(conn)


def update_job(job_id, **kwargs):
    """update field job"""
    clean_kwargs = {k: v for k, v in kwargs.items() if v is not None}
    clean_kwargs['updated_at'] = datetime.now().isoformat()
    conn = get_db()
    try:
        sets = ", ".join(f"{k} = ?" for k in clean_kwargs)
        vals = list(clean_kwargs.values()) + [job_id]
        conn.execute(f"UPDATE jobs SET {sets} WHERE id = ?", vals)
        conn.commit()
    finally:
        return_db(conn)


def get_job(job_id):
    """ambil satu job"""
    conn = get_db()
    try:
        row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
        return dict(row) if row else None
    finally:
        return_db(conn)


def add_history(job_id, hist_type, source_file, output_file, language, status, metadata=None):
    """tambah entry history"""
    now = datetime.now().isoformat()
    conn = get_db()
    try:
        conn.execute(
            """INSERT INTO history (job_id, type, source_file, output_file, language, status, created_at, metadata)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (job_id, hist_type, source_file, output_file, language, status, now,
             json.dumps(metadata) if metadata else None)
        )
        conn.commit()
    finally:
        return_db(conn)


def get_history(limit=50):
    """ambil history terbaru"""
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT * FROM history ORDER BY created_at DESC LIMIT ?", (limit,)
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        return_db(conn)


# Initialize pool on module import
try:
    _init_pool()
except Exception as e:
    print(f"⚠️ Warning: Database pool initialization failed: {e}")
    print("  Will fallback to direct connections")


# Fix H8: Cleanup handler on application exit
def _cleanup_pool():
    """Close all connections in pool on application exit"""
    global _connection_pool, _initialized

    if _connection_pool is None:
        return

    print("🧹 Cleaning up database connections...")

    while not _connection_pool.empty():
        try:
            conn = _connection_pool.get_nowait()
            conn.close()
        except Exception:
            pass

    _connection_pool = None
    _initialized = False
    print("✅ Database connections cleaned up")


# Register cleanup handler
import atexit
atexit.register(_cleanup_pool)
