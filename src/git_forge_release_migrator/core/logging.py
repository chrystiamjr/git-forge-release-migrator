from __future__ import annotations

import json
import sys
import threading
import time
from datetime import datetime, timezone
from typing import TextIO


class ConsoleLogger:
    def __init__(self, *, quiet: bool = False, json_output: bool = False) -> None:
        self._quiet = quiet
        self._json_output = json_output
        self._tty = sys.stdout.isatty() and not json_output and not quiet
        self._lock = threading.RLock()
        self._spinner_stop = threading.Event()
        self._spinner_thread: threading.Thread | None = None
        self._spinner_message = ""
        self._spinner_prefix = "INFO"
        self._spinner_last_width = 0
        self._spinner_frames = ["|", "/", "-", "\\"]

    def _clear_spinner_line_locked(self) -> None:
        if not self._tty or self._spinner_last_width <= 0:
            return
        sys.stdout.write("\r" + (" " * self._spinner_last_width) + "\r")
        sys.stdout.flush()
        self._spinner_last_width = 0

    def _emit_json(self, prefix: str, message: str, stream: TextIO) -> None:
        record = {
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "level": prefix.lower(),
            "message": message,
        }
        stream.write(json.dumps(record, ensure_ascii=True) + "\n")
        stream.flush()

    def _print_line(self, prefix: str, message: str, stream: TextIO) -> None:
        with self._lock:
            if self._spinner_thread is not None and self._spinner_thread.is_alive():
                self._clear_spinner_line_locked()
            if self._json_output:
                self._emit_json(prefix, message, stream)
                return
            line = f"[{prefix}] {message}"
            stream.write(f"{line}\n")
            stream.flush()

    def _spinner_loop(self) -> None:
        idx = 0
        while not self._spinner_stop.is_set():
            frame = self._spinner_frames[idx % len(self._spinner_frames)]
            idx += 1
            line = f"[{self._spinner_prefix}] {self._spinner_message} {frame}"
            with self._lock:
                sys.stdout.write("\r" + line)
                if self._spinner_last_width > len(line):
                    sys.stdout.write(" " * (self._spinner_last_width - len(line)))
                sys.stdout.flush()
                self._spinner_last_width = len(line)
            time.sleep(0.12)

    def start_spinner(self, message: str, *, prefix: str = "INFO") -> bool:
        if not self._tty:
            self.info(message)
            return False

        self.stop_spinner()
        with self._lock:
            self._spinner_message = message
            self._spinner_prefix = prefix
            self._spinner_stop.clear()
            self._spinner_thread = threading.Thread(target=self._spinner_loop, daemon=True)
            self._spinner_thread.start()
        return True

    def update_spinner(self, message: str) -> None:
        with self._lock:
            self._spinner_message = message

    def stop_spinner(self, final_message: str | None = None, *, prefix: str = "INFO") -> None:
        thread = self._spinner_thread
        if thread is not None:
            self._spinner_stop.set()
            thread.join(timeout=1.0)
            with self._lock:
                self._clear_spinner_line_locked()
                self._spinner_thread = None
                self._spinner_stop.clear()
        if final_message:
            self._print_line(prefix, final_message, sys.stdout)

    def info(self, message: str) -> None:
        if self._quiet and not self._json_output:
            return
        self._print_line("INFO", message, sys.stdout)

    def warn(self, message: str) -> None:
        self._print_line("WARN", message, sys.stderr)

    def error(self, message: str) -> None:
        self._print_line("ERROR", message, sys.stderr)
