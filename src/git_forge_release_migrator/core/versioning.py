def _normalize(tag: str) -> tuple[int, int, int]:
    value = tag.strip()
    if value.startswith("v"):
        value = value[1:]
    parts = value.split(".")
    if len(parts) != 3:
        raise ValueError(f"Invalid semantic tag: {tag}")
    return int(parts[0]), int(parts[1]), int(parts[2])


def version_le(left: str, right: str) -> bool:
    return _normalize(left) <= _normalize(right)
