"""Publish completed packages while retaining recoverable output on Windows locks."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import time
import uuid
from pathlib import Path

from .common import CliError
from .file_lock import FileLockTimeout, exclusive_file_lock
from .package_transaction import publish_inplace, recover_inplace

READY_MARKER = ".publish-ready.json"
MANIFEST = "package/fh_radio_studio_package_manifest.json"


def owned_sibling(target: Path, candidate: Path) -> Path:
    if candidate.is_symlink() or candidate.resolve().parent != target.parent.resolve():
        raise CliError("准备包临时目录超出预期位置")
    return candidate


def check_target(target: Path) -> None:
    recover_inplace(target)
    if target.is_symlink() or (target.exists() and not target.is_dir()):
        raise CliError("准备包输出位置必须是普通目录，不能是链接")
    if target.exists() and any(target.iterdir()) and not (target / MANIFEST).is_file():
        raise CliError(f"输出目录不是完整准备包，请选择新的输出目录：{target}")


def _manifest_digest(stage: Path) -> str:
    data = (stage / MANIFEST).read_bytes()
    if not isinstance(json.loads(data), dict):
        raise CliError("准备包清单格式无效")
    return hashlib.sha256(data).hexdigest()


def mark_complete(target: Path, stage: Path) -> None:
    owned_sibling(target, stage)
    temporary = stage / f".publish-ready-{uuid.uuid4().hex}.tmp"
    temporary.write_text(
        json.dumps(
            {
                "version": 1,
                "target": target.name,
                "manifest_sha256": _manifest_digest(stage),
                "created_ns": time.time_ns(),
            }
        ),
        encoding="utf-8",
    )
    with temporary.open("r+b") as stream:
        os.fsync(stream.fileno())
    temporary.replace(stage / READY_MARKER)


def ready_metadata(target: Path, stage: Path) -> dict:
    owned_sibling(target, stage)
    if not stage.name.startswith(f".{target.name}-building-"):
        raise CliError("不是此准备包的待替换目录")
    if (
        (stage / READY_MARKER).is_symlink()
        or (stage / "package").is_symlink()
        or (stage / MANIFEST).is_symlink()
    ):
        raise CliError("待替换准备包不能包含清单链接")
    data = json.loads((stage / READY_MARKER).read_text(encoding="utf-8"))
    if (
        not isinstance(data, dict)
        or data.get("version") != 1
        or data.get("target") != target.name
        or data.get("manifest_sha256") != _manifest_digest(stage)
    ):
        raise CliError("待替换准备包清单已变化，请重新构建")
    return data


def completed_packages(target: Path) -> list[Path]:
    found = []
    for stage in target.parent.glob(f".{target.name}-building-*"):
        try:
            meta = ready_metadata(target, stage)
            found.append((int(meta["created_ns"]), stage))
        except (CliError, OSError, ValueError, KeyError, TypeError):
            continue
    return [stage for _, stage in sorted(found, reverse=True)]


def _rename_with_retry(source: Path, destination: Path) -> None:
    for attempt, delay in enumerate((0.15, 0.35, 0.7, 0)):
        try:
            source.rename(destination)
            return
        except OSError as error:
            transient = isinstance(error, PermissionError) or getattr(error, "winerror", None) in (
                5,
                32,
                33,
            )
            if not transient or attempt == 3:
                raise
            time.sleep(delay)


def publish_completed(target: Path, stage: Path) -> None:
    ready_metadata(target, stage)
    check_target(target)
    backup = owned_sibling(target, target.with_name(f".{target.name}-previous-{uuid.uuid4().hex}"))
    moved_old = False
    in_place = False
    try:
        if target.exists():
            try:
                _rename_with_retry(owned_sibling(target, target), backup)
                moved_old = True
            except PermissionError:
                publish_inplace(target, stage, backup)
                in_place = True
        try:
            if not in_place:
                _rename_with_retry(stage, target)
        except BaseException:
            if moved_old:
                try:
                    _rename_with_retry(backup, target)
                except OSError as rollback_error:
                    raise CliError(
                        f"准备包替换与恢复均被阻止。旧包保留于 {backup}，新包保留于 {stage}：{rollback_error}"
                    ) from rollback_error
            raise
    except OSError as error:
        raise CliError(
            f"准备包已构建完成，但替换目录被拒绝或占用：{target}。"
            f"请关闭该目录及其文件的占用程序后，点击“重试替换”；无需重新编码。"
            f"新准备包已保留于 {stage}。系统错误：{error}"
        ) from error
    # The rename is the commit point. Cleanup errors must not report a failed build.
    try:
        (target / READY_MARKER).unlink(missing_ok=True)
    except OSError as error:
        print(f"准备包已完成，临时标记清理未完成：{error}")
    obsolete = completed_packages(target)
    if moved_old or in_place:
        obsolete.append(backup)
    if in_place:
        obsolete.append(stage)
    for old in dict.fromkeys(obsolete):
        try:
            # Disable recovery before deleting a superseded completed package.
            (old / READY_MARKER).unlink(missing_ok=True)
            shutil.rmtree(owned_sibling(target, old))
        except OSError as error:
            print(f"准备包已完成，旧产物清理未完成，保留于 {old}：{error}")
    print(f"准备包已完成：{target}")


def cmd_publish_package(args: argparse.Namespace) -> int:
    target = Path(args.out_dir).expanduser().absolute()
    try:
        with exclusive_file_lock(target.with_name(f".{target.name}.build.lock")):
            stage = Path(args.ready_dir).expanduser().absolute()
            publish_completed(target, stage)
    except FileLockTimeout as error:
        raise CliError("此准备包正在构建或替换，请稍后重试") from error
    return 0


def cmd_discard_package_build(args: argparse.Namespace) -> int:
    target = Path(args.out_dir).expanduser().absolute()
    try:
        with exclusive_file_lock(target.with_name(f".{target.name}.build.lock")):
            stage = owned_sibling(target, Path(args.build_dir).expanduser().absolute())
            if not stage.name.startswith(f".{target.name}-building-"):
                raise CliError("不是此准备包的构建目录")
            if stage.exists() and not (stage / READY_MARKER).exists():
                shutil.rmtree(stage)
    except FileLockTimeout as error:
        raise CliError("构建进程尚未退出，未清理临时文件") from error
    return 0
