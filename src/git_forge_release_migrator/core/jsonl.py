from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


def append_log(
    path: str,
    *,
    status: str,
    tag: str,
    message: str,
    asset_count: int,
    duration_ms: int,
    dry_run: bool,
) -> None:
    record = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "status": status,
        "tag": tag,
        "message": message,
        "asset_count": asset_count,
        "duration_ms": duration_ms,
        "dry_run": dry_run,
    }
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=True) + "\n")
