"""Extract a data-only GitHub tarball. Never preserve links, permissions or configuration."""
import pathlib
import sys
import tarfile

MAX_BYTES = 100 * 1024 * 1024
MAX_FILES = 20000


def extract(archive, destination):
    root = pathlib.Path(destination).resolve()
    root.mkdir(parents=True, exist_ok=True)
    total = 0
    count = 0
    with tarfile.open(archive, "r:*") as bundle:
        for member in bundle:
            parts = pathlib.PurePosixPath(member.name).parts
            if member.name.startswith("/") or ".." in parts or "\\" in member.name:
                raise ValueError("Unsafe archive path")
            if len(parts) < 2 or not member.isfile():
                continue
            relative = parts[1:]
            if any(p in {".git", ".claude", ".mcp.json", "CLAUDE.md", "CLAUDE.local.md"} for p in relative):
                continue
            total += member.size
            count += 1
            if total > MAX_BYTES or count > MAX_FILES:
                raise ValueError("Snapshot exceeds review budget")
            target = root.joinpath(*relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.extractfile(member) as source, target.open("xb") as output:
                output.write(source.read())
            target.chmod(0o444)


if __name__ == "__main__":
    extract(sys.argv[1], sys.argv[2])
