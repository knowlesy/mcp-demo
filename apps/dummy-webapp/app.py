import os
import sqlite3
import threading
import time

from flask import Flask, jsonify, request
from prometheus_client import (
    Counter, Gauge, Histogram,
    generate_latest, CONTENT_TYPE_LATEST,
)

app = Flask(__name__)

DB_PATH = os.environ.get("DB_PATH", "/data/app.db")

REQUEST_COUNT = Counter(
    "webapp_requests_total", "Total HTTP requests", ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "webapp_request_latency_seconds", "Request latency in seconds", ["endpoint"]
)
DB_ERRORS = Counter("webapp_db_errors_total", "Total database errors")
MEMORY_ALLOCATED_MB = Gauge("webapp_memory_stress_mb", "MB currently allocated by stress endpoint")


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = get_db()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            name       TEXT    NOT NULL,
            email      TEXT    UNIQUE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS events (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id    INTEGER,
            action     TEXT,
            timestamp  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id)
        );
    """)
    try:
        conn.execute(
            "INSERT INTO users (name, email) VALUES (?, ?)",
            ("Admin", "admin@example.com"),
        )
        conn.execute(
            "INSERT INTO users (name, email) VALUES (?, ?)",
            ("Alice", "alice@example.com"),
        )
        conn.commit()
    except sqlite3.IntegrityError:
        pass  # seed data already present
    conn.close()


# ── Routes ────────────────────────────────────────────────────────────────────

@app.route("/health")
def health():
    start = time.time()
    try:
        conn = get_db()
        conn.execute("SELECT COUNT(*) FROM users").fetchone()
        conn.close()
        payload = {"status": "healthy", "db": "ok"}
        status = 200
    except Exception as exc:
        DB_ERRORS.inc()
        payload = {"status": "unhealthy", "db": str(exc)}
        status = 500
    REQUEST_COUNT.labels("GET", "/health", str(status)).inc()
    REQUEST_LATENCY.labels("/health").observe(time.time() - start)
    return jsonify(payload), status


@app.route("/users", methods=["GET"])
def list_users():
    start = time.time()
    try:
        conn = get_db()
        rows = conn.execute("SELECT id, name, email, created_at FROM users").fetchall()
        conn.close()
        result = [dict(r) for r in rows]
        status = 200
    except Exception as exc:
        DB_ERRORS.inc()
        result = {"error": str(exc)}
        status = 500
    REQUEST_COUNT.labels("GET", "/users", str(status)).inc()
    REQUEST_LATENCY.labels("/users").observe(time.time() - start)
    return jsonify(result), status


@app.route("/users", methods=["POST"])
def create_user():
    start = time.time()
    body = request.get_json(silent=True) or {}
    try:
        conn = get_db()
        conn.execute(
            "INSERT INTO users (name, email) VALUES (?, ?)",
            (body.get("name", "unknown"), body.get("email", "unknown@example.com")),
        )
        conn.commit()
        conn.close()
        status = 201
        result = {"status": "created"}
    except Exception as exc:
        DB_ERRORS.inc()
        result = {"error": str(exc)}
        status = 500
    REQUEST_COUNT.labels("POST", "/users", str(status)).inc()
    REQUEST_LATENCY.labels("/users").observe(time.time() - start)
    return jsonify(result), status


@app.route("/stress")
def stress():
    """Allocate RAM until OOMKilled. ?mb=N controls how many MB to grab."""
    mb = int(request.args.get("mb", 200))
    REQUEST_COUNT.labels("GET", "/stress", "200").inc()
    MEMORY_ALLOCATED_MB.set(mb)

    def _allocate():
        chunks = []
        for _ in range(mb):
            chunks.append(b"x" * 1_048_576)  # 1 MiB per chunk
        time.sleep(30)
        MEMORY_ALLOCATED_MB.set(0)

    t = threading.Thread(target=_allocate, daemon=True)
    t.start()
    return jsonify({"allocating_mb": mb, "note": "pod will OOMKill if limit exceeded"})


@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.route("/")
def index():
    REQUEST_COUNT.labels("GET", "/", "200").inc()
    return jsonify({"service": "dummy-webapp", "version": "1.0.0"})


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=8080, threaded=True)
