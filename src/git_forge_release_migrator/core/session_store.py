from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path


def load_session(path: str) -> dict:
    session_path = Path(path)
    if not session_path.exists():
        raise FileNotFoundError(f"Session file not found: {path}")
    with session_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError(f"Invalid session payload in {path}")
    return data


def save_session(path: str, payload: dict) -> None:
    session_path = Path(path)
    session_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(session_path.parent, 0o700)
    except FileNotFoundError:
        pass

    fd, tmp_path = tempfile.mkstemp(prefix="gfrm-session-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=True, indent=2)
        os.chmod(tmp_path, 0o600)
        os.replace(tmp_path, session_path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
