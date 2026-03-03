from __future__ import annotations

import json
import os
import subprocess


class CommandError(RuntimeError):
    pass


def run_cmd(
    cmd: list[str],
    env: dict[str, str] | None = None,
    cwd: str | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)

    proc = subprocess.run(
        cmd,
        cwd=cwd,
        env=merged_env,
        check=False,
        text=True,
        capture_output=True,
    )

    if check and proc.returncode != 0:
        stderr = (proc.stderr or proc.stdout or "").strip()
        raise CommandError(stderr or f"Command failed with exit code {proc.returncode}: {' '.join(cmd)}")

    return proc


def run_json(cmd: list[str], env: dict[str, str] | None = None, cwd: str | None = None) -> dict | list:
    proc = run_cmd(cmd, env=env, cwd=cwd)
    text = proc.stdout.strip()
    if not text:
        raise CommandError(f"Empty JSON output from command: {' '.join(cmd)}")
    return json.loads(text)


def run_lines(cmd: list[str], env: dict[str, str] | None = None, cwd: str | None = None) -> list[str]:
    proc = run_cmd(cmd, env=env, cwd=cwd)
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]
