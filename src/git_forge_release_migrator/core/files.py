from __future__ import annotations

import re
import shutil
from pathlib import Path


def ensure_dir(path: str | Path) -> Path:
    p = Path(path)
    p.mkdir(parents=True, exist_ok=True)
    return p


def cleanup_dir(path: str | Path) -> None:
    p = Path(path)
    if p.exists() and p.is_dir():
        shutil.rmtree(p, ignore_errors=True)


def sanitize_filename(name: str) -> str:
    base = name.split("/")[-1].split("?", 1)[0]
    base = base.replace(" ", "_").replace(":", "_").replace("\t", "_")
    base = re.sub(r"[^A-Za-z0-9._-]", "", base)
    return base or "asset"


def unique_asset_filename(target_dir: str | Path, raw_name: str) -> str:
    target = Path(target_dir)
    clean = sanitize_filename(raw_name)

    stem = clean
    suffix = ""
    if "." in clean and not clean.startswith("."):
        stem, ext = clean.rsplit(".", 1)
        suffix = f".{ext}"

    candidate = f"{stem}{suffix}"
    i = 2
    while (target / candidate).exists():
        candidate = f"{stem}-{i}{suffix}"
        i += 1

    return candidate
