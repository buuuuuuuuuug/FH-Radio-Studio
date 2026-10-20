"""OS-owned advisory locks released automatically when the process exits."""

from __future__ import annotations

import errno
import os
import time
from contextlib import contextmanager
from pathlib import Path


class FileLockTimeout(TimeoutError):
    """The requested lock remained owned by another operation."""


@contextmanager
def exclusive_file_lock(path: Path, *, timeout_sec: float = 0.0):
    path.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + timeout_sec
    with path.open("a+b") as handle:
        handle.seek(0, os.SEEK_END)
        if handle.tell() == 0:
            handle.write(b"\0")
            handle.flush()
        if os.name == "nt":
            import msvcrt

            def acquire():
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)

            def release():
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)

        else:
            import fcntl

            def acquire():
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

            def release():
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)

        while True:
            try:
                acquire()
                break
            except OSError as error:
                if error.errno not in {errno.EACCES, errno.EAGAIN, errno.EDEADLK}:
                    raise
                if time.monotonic() >= deadline:
                    raise FileLockTimeout(
                        f"Another operation holds the file lock: {path}"
                    ) from error
                time.sleep(min(0.02, max(0.0, deadline - time.monotonic())))
        try:
            yield
        finally:
            release()
