#!/usr/bin/env python3
"""
Seed a user directly into the neon-users-service SQLite database.

Bypasses HANA's /auth/register because users-service has no admin-bootstrap
mechanism — registering through HANA only ever creates users with default
permissions, and there's no way for a non-admin to grant admin perms to
anyone (including themselves). The installer is a privileged context, so
we write the row ourselves.

Usage:
    seed-user.py <db_path> <username> <password> <perms_json>

Where:
    db_path     Absolute path to neon-users-db.sqlite
    username    User to create (idempotent: existing user is updated)
    password    Plain password — gets SHA-256 hashed before storage,
                matching what users-service does for /auth/login lookups
    perms_json  JSON object: {"klat": 30, "core": 30, ...}

Exits 0 on success.
"""
import hashlib
import json
import sqlite3
import sys
import time
import uuid
from pathlib import Path


def sha256_hex(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def build_user(username: str, password: str, perms: dict) -> dict:
    """Construct a User dict matching neon_data_models.user.database.User shape."""
    return {
        "user_id": str(uuid.uuid4()),
        "created_timestamp": int(time.time()),
        "username": username,
        "password_hash": sha256_hex(password),
        "permissions": perms,
        "tokens": [],
        # NeonUserConfig defaults are applied by users-service on read; an
        # empty dict here is sufficient to round-trip through pydantic.
        "neon": {},
    }


def upsert(db_path: Path, user: dict) -> None:
    conn = sqlite3.connect(str(db_path))
    try:
        # Match the schema users-service creates on its own startup.
        conn.execute(
            """CREATE TABLE IF NOT EXISTS users
            (user_id text,
             created_timestamp integer,
             username text,
             user_object text)"""
        )
        cursor = conn.execute(
            "SELECT user_id FROM users WHERE username = ?", (user["username"],)
        )
        existing = cursor.fetchone()
        cursor.close()

        if existing:
            # Preserve the existing user_id so any tokens / references survive.
            user["user_id"] = existing[0]
            conn.execute(
                "UPDATE users SET user_object = ? WHERE username = ?",
                (json.dumps(user), user["username"]),
            )
        else:
            conn.execute(
                "INSERT INTO users (user_id, created_timestamp, username, user_object) "
                "VALUES (?, ?, ?, ?)",
                (
                    user["user_id"],
                    user["created_timestamp"],
                    user["username"],
                    json.dumps(user),
                ),
            )
        conn.commit()
    finally:
        conn.close()


def main(argv: list) -> int:
    if len(argv) != 5:
        print(__doc__, file=sys.stderr)
        return 2
    _, db_path, username, password, perms_json = argv
    perms = json.loads(perms_json)
    user = build_user(username, password, perms)
    upsert(Path(db_path), user)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
