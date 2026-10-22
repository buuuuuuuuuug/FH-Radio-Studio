"""Replace package contents without renaming directories held open by Explorer.

The old files are moved to an owned sibling before new immutable files are
linked/copied in. A durable journal allows rollback after an interrupted publish.
The completed stage is never consumed until publication commits.
"""

from __future__ import annotations

import json
import os
import shutil
from pathlib import Path

from .common import CliError


def journal_path(target: Path) -> Path:
    return target.with_name(f".{target.name}-publishing.json")


def _linked(path: Path) -> bool:
    return path.is_symlink() or getattr(path, "is_junction", lambda: False)()


def _file(root: Path, relative: str) -> Path:
    part = Path(relative)
    if not relative or part.is_absolute() or part.drive or ".." in part.parts:
        raise CliError("准备包替换记录包含无效路径")
    result = root / part
    cursor = result
    while cursor != root:
        if _linked(cursor):
            raise CliError("准备包替换路径不能包含链接")
        cursor = cursor.parent
    if _linked(root):
        raise CliError("准备包目录不能是链接")
    return result


def _files(root: Path) -> list[str]:
    result = []

    def visit(directory: Path) -> None:
        for path in directory.iterdir():
            if _linked(path):
                raise CliError(f"准备包内容不能包含链接：{path}")
            if path.is_dir():
                visit(path)
            elif path.is_file():
                result.append(path.relative_to(root).as_posix())
            else:
                raise CliError(f"准备包中存在非常规文件：{path}")

    visit(root)
    return sorted(result)


def _install_file(source: Path, destination: Path) -> None:
    """Creating a link/file works even when renames into an open folder do not.

    The publication journal blocks consumers until all files have been installed.
    Keep the source intact so recovery can be safely repeated after interruption.
    """
    if destination.is_file() and os.path.samefile(source, destination):
        return
    if destination.is_dir():
        destination.rmdir()
    elif destination.exists():
        destination.unlink()
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)


def recover_inplace(target: Path) -> None:
    """Roll back only mutations for which the old file actually reached backup."""
    journal = journal_path(target)
    if not journal.exists():
        return
    if _linked(journal):
        raise CliError("准备包替换记录不能是链接")
    data = json.loads(journal.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("version") != 1 or data.get("target") != target.name:
        raise CliError("准备包替换记录无效，请保留目录并查看日志")
    name = data.get("backup")
    if (
        not isinstance(name, str)
        or Path(name).name != name
        or not name.startswith(f".{target.name}-previous-")
    ):
        raise CliError("准备包恢复目录无效")
    backup = target.parent / name
    if _linked(backup) or not backup.is_dir():
        raise CliError("准备包恢复文件缺失，请保留新旧包并查看日志")
    old = data.get("old")
    new = data.get("new")
    if (
        not isinstance(old, list)
        or not isinstance(new, list)
        or not all(isinstance(s, str) for s in old + new)
    ):
        raise CliError("准备包替换文件列表无效")
    # Validate everything before touching anything, including surviving parents.
    for relative in set(old + new):
        _file(target, relative)
        _file(backup, relative)
    for relative in set(new) - set(old):
        destination = _file(target, relative)
        if destination.is_file():
            destination.unlink()
    for relative in old:
        saved = _file(backup, relative)
        if saved.is_file():
            destination = _file(target, relative)
            _install_file(saved, destination)
    journal.unlink()
    try:
        shutil.rmtree(backup)
    except OSError:
        pass


def publish_inplace(target: Path, stage: Path, backup: Path) -> None:
    old_files = _files(target)
    new_files = [name for name in _files(stage) if name != ".publish-ready.json"]
    backup.mkdir()
    journal = journal_path(target)
    with journal.open("x", encoding="utf-8") as stream:
        json.dump(
            {
                "version": 1,
                "target": target.name,
                "backup": backup.name,
                "old": old_files,
                "new": new_files,
            },
            stream,
        )
        stream.flush()
        os.fsync(stream.fileno())
    try:
        for relative in old_files:
            saved = _file(backup, relative)
            saved.parent.mkdir(parents=True, exist_ok=True)
            _file(target, relative).replace(saved)
        # Manifest is installed last; consumers refuse the package while the
        # journal exists. New hardlinks are immutable and cost no extra bank copy.
        ordered = sorted(
            new_files,
            key=lambda name: (name.endswith("fh_radio_studio_package_manifest.json"), name),
        )
        for relative in ordered:
            source = _file(stage, relative)
            destination = _file(target, relative)
            _install_file(source, destination)
        journal.unlink()  # Commit. A missing journal always means a complete tree.
    except BaseException as error:
        try:
            recover_inplace(target)
        except (OSError, CliError) as rollback:
            raise CliError(
                f"准备包替换尚未完成；请保留旧包 {backup} 与新包 {stage}，重试时将先恢复旧包：{rollback}"
            ) from error
        raise
