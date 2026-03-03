from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

_TERMINAL_RELEASE_STATUSES = {"created", "updated", "skipped_existing"}
_TERMINAL_TAG_STATUSES = {"tag_created", "tag_skipped_existing"}


def load_checkpoint_state(path: str, signature: str) -> dict[str, str]:
    p = Path(path)
    if not p.exists():
        return {}

    state: dict[str, str] = {}
    with p.open("r", encoding="utf-8") as f:
        for line in f:
            text = line.strip()
            if not text:
                continue
            try:
                item = json.loads(text)
            except json.JSONDecodeError:
                continue
            if not isinstance(item, dict):
                continue
            if str(item.get("signature", "")) != signature:
                continue
            key = str(item.get("key", ""))
            status = str(item.get("status", ""))
            if key and status:
                state[key] = status
    return state


def append_checkpoint(
    path: str,
    *,
    signature: str,
    key: str,
    tag: str,
    status: str,
    message: str,
) -> None:
    record = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "signature": signature,
        "key": key,
        "tag": tag,
        "status": status,
        "message": message,
    }
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=True) + "\n")


def is_terminal_release_status(status: str) -> bool:
    return status in _TERMINAL_RELEASE_STATUSES


def is_terminal_tag_status(status: str) -> bool:
    return status in _TERMINAL_TAG_STATUSES
