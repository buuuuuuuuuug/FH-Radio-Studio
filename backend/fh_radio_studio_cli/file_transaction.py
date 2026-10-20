"""Stage a bounded file set before installation and roll back failed writes."""

from __future__ import annotations

import os
import shutil
import stat
import tempfile
import warnings
from contextlib import contextmanager
from pathlib import Path
from typing import Iterable

from .common import CliError, md5_file
from .file_lock import FileLockTimeout, exclusive_file_lock


def _temporary_neighbor(destination: Path, suffix: str) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=destination.parent, prefix=f".{destination.name}.", suffix=suffix, delete=False
    ) as handle:
        return Path(handle.name)


def _remove_temporary(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except PermissionError:
        # copy2 preserves the Windows read-only attribute on staged files.
        path.chmod(path.stat().st_mode | stat.S_IWRITE)
        path.unlink()


def replace_files_atomically(
    replacements: Iterable[tuple[Path, Path, str | None]],
    *,
    removals: Iterable[Path] = (),
) -> None:
    """Install complete staged copies, preserving replaced originals for rollback.

    The optional digest belongs to the previously validated source. All copies
    and digest checks finish before any destination changes. Renaming originals
    preserves their bytes and metadata without a second large backup copy.
    Rollback is best effort if the OS also refuses the recovery operation; in
    that case the surviving backup paths are included in the error and retained.
    This handles ordinary errors and interrupts, not process kill or power loss.
    """
    staged: list[tuple[Path, Path]] = []
    backups: list[tuple[Path, Path]] = []
    installed: list[Path] = []
    destinations: set[Path] = set()
    try:
        for source, destination, expected_md5 in replacements:
            key = destination.resolve()
            if key in destinations:
                raise CliError(f"Duplicate file transaction destination: {destination}")
            destinations.add(key)
            temporary = _temporary_neighbor(destination, ".install-tmp")
            staged.append((temporary, destination))
            shutil.copy2(source, temporary)
            if expected_md5 and md5_file(temporary) != expected_md5:
                raise CliError(f"Source changed while staging: {source}")
        delete_paths = list(removals)
        for destination in delete_paths:
            key = destination.resolve()
            if key in destinations:
                raise CliError(f"Duplicate file transaction destination: {destination}")
            destinations.add(key)

        try:
            for temporary, destination in staged:
                if destination.exists():
                    backup = _temporary_neighbor(destination, ".install-backup")
                    try:
                        os.replace(destination, backup)
                    except BaseException:
                        _remove_temporary(backup)
                        raise
                    backups.append((backup, destination))
                os.replace(temporary, destination)
                installed.append(destination)
            for destination in delete_paths:
                if destination.exists():
                    backup = _temporary_neighbor(destination, ".install-backup")
                    try:
                        os.replace(destination, backup)
                    except BaseException:
                        _remove_temporary(backup)
                        raise
                    backups.append((backup, destination))
        except BaseException as error:
            recovery_errors = []
            for destination in reversed(installed):
                try:
                    _remove_temporary(destination)
                except OSError as recovery_error:
                    recovery_errors.append(str(recovery_error))
            for backup, destination in reversed(backups):
                try:
                    os.replace(backup, destination)
                except OSError as recovery_error:
                    recovery_errors.append(f"{backup} -> {destination}: {recovery_error}")
            if recovery_errors:
                raise CliError(
                    f"File installation failed ({error}); recovery needs attention: "
                    + "; ".join(recovery_errors)
                ) from error
            raise
        for backup, _ in backups:
            try:
                _remove_temporary(backup)
            except OSError as error:
                warnings.warn(f"Installed files; temporary backup retained at {backup}: {error}")
    finally:
        for temporary, _ in staged:
            try:
                _remove_temporary(temporary)
            except OSError as error:
                warnings.warn(f"Temporary install file retained at {temporary}: {error}")


@contextmanager
def game_file_write_lock(game_dir: Path, *, enabled: bool = True):
    if not enabled:
        yield
        return
    try:
        with exclusive_file_lock(game_dir.resolve() / ".fh-radio-studio-write.lock"):
            yield
    except FileLockTimeout as error:
        raise CliError(
            "Another operation is writing this game directory; wait for it to finish."
        ) from error


@contextmanager
def preserve_directory_on_failure(destination: Path):
    """Keep an existing directory until its replacement has completed."""
    backup = None
    if destination.exists():
        if not destination.is_dir() or destination.is_symlink():
            raise CliError(f"Expected an ordinary directory: {destination}")
        backup = Path(tempfile.mkdtemp(dir=destination.parent, prefix=f".{destination.name}.old-"))
        backup.rmdir()
        os.replace(destination, backup)
    try:
        yield
    except BaseException as error:
        try:
            if destination.exists():
                shutil.rmtree(destination)
            if backup is not None:
                os.replace(backup, destination)
        except OSError as recovery_error:
            raise CliError(
                f"Directory replacement failed ({error}); original retained at {backup}: "
                f"{recovery_error}"
            ) from error
        raise
    else:
        if backup is not None:
            try:
                shutil.rmtree(backup)
            except OSError as error:
                warnings.warn(
                    f"Replacement completed; previous directory retained at {backup}: {error}"
                )
