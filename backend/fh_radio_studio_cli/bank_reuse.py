"""Content-checked reuse of completed radio banks and atomic package publication."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
import uuid
from contextlib import ExitStack
from copy import deepcopy
from dataclasses import dataclass
from functools import wraps
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path

from .common import CliError
from .file_lock import FileLockTimeout, exclusive_file_lock

VERSION = 1


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _digest(value) -> str:
    return hashlib.sha256(
        json.dumps(
            value, sort_keys=True, ensure_ascii=False, separators=(",", ":"), allow_nan=False
        ).encode("utf-8")
    ).hexdigest()


def _public_unit(value):
    if isinstance(value, dict):
        return {
            key: _public_unit(item)
            for key, item in value.items()
            if not key.startswith("_runtime_")
            and key not in {"bank_build", "bank_reused", "reused_from"}
        }
    if isinstance(value, list):
        return [_public_unit(item) for item in value]
    return value


def engine_signature(ffmpeg, fsbankcl):
    root = Path(__file__).parent
    # Any backend code affecting decoding, normalization, markers or bank layout
    # invalidates old results; do not rely on a manually maintained module list.
    code = {
        str(path.relative_to(root).as_posix()): file_sha256(path)
        for path in sorted(root.rglob("*.py"))
    }
    dependencies = {}
    for name in ("numpy", "soundfile", "scipy", "librosa", "pyloudnorm", "soxr"):
        try:
            dependencies[name] = version(name)
        except PackageNotFoundError:
            dependencies[name] = None
    tools = {}
    for name, value in [("ffmpeg", ffmpeg), ("fsbankcl", fsbankcl)]:
        if value:
            path = Path(value).resolve()
            tools[name] = file_sha256(path)
            if name == "fsbankcl":
                tools["fsbank_dlls"] = {
                    p.name: file_sha256(p) for p in sorted(path.parent.glob("*.dll"))
                }
        else:
            tools[name] = None
    return _digest({"code": code, "dependencies": dependencies, "tools": tools})


def radio_fingerprint(*, radio, source_bank, target_names, tracks, settings, engine):
    return _digest(
        {
            "version": VERSION,
            "radio": radio,
            "source_bank": file_sha256(source_bank),
            "target_names": target_names,
            "tracks": tracks,
            "settings": settings,
            "engine": engine,
        }
    )


def load_previous_units(package):
    if not package:
        return []
    path = Path(package).expanduser()
    if not path.is_file():
        candidates = [
            path / "fh_radio_studio_package_manifest.json",
            path / "package/fh_radio_studio_package_manifest.json",
        ]
        path = next((item for item in candidates if item.is_file()), candidates[-1])
    try:
        manifest = json.loads(path.read_text(encoding="utf-8-sig"))
        if manifest.get("skip_bank"):
            return []
        radios = manifest.get("radios")
        if not isinstance(radios, list):
            return []
        return [(path.parent, unit) for unit in radios if isinstance(unit, dict)]
    except (OSError, ValueError, AttributeError):
        return []


@dataclass(frozen=True)
class ReusableBank:
    source: Path
    unit: dict

    def copy_to(self, directory: Path):
        target = directory / self.source.name
        directory.mkdir(parents=True, exist_ok=True)
        if self.source.resolve() != target.resolve():
            shutil.copy2(self.source, target)
        if file_sha256(target) != self.unit["bank_build"]["bank_sha256"]:
            raise CliError("复用的 bank 在复制期间发生变化，已保留上次准备包，请重试")
        unit = deepcopy(self.unit)
        unit["bank_reused"] = True
        return unit


def reusable_bank(previous, *, radio, bank_name, fingerprint):
    for root, unit in previous:
        record = unit.get("bank_build")
        if (
            unit.get("radio") != radio
            or unit.get("target_bank_name") != bank_name
            or not isinstance(record, dict)
            or record.get("version") != VERSION
            or record.get("fingerprint") != fingerprint
        ):
            continue
        try:
            if record.get("unit_sha256") != _digest(_public_unit(unit)):
                continue
        except (ValueError, TypeError):
            # Invalid optional reuse metadata must not prevent a fresh build.
            continue
        bank = root / "media/audio/FMODBanks" / bank_name
        try:
            if file_sha256(bank) == record.get("bank_sha256"):
                return ReusableBank(bank, unit)
        except OSError:
            continue
    return None


def stamp_unit(unit, fingerprint, bank):
    unit["bank_reused"] = False
    unit["bank_build"] = {
        "version": VERSION,
        "fingerprint": fingerprint,
        "bank_sha256": file_sha256(bank),
        "unit_sha256": _digest(_public_unit(unit)),
    }


def atomic_package_build(function):
    """Keep the last completed package available until a new one is complete."""

    @wraps(function)
    def publish(args):
        target = Path(args.out_dir).expanduser().absolute()
        if target.exists() and not target.is_dir():
            raise CliError("准备包输出位置必须是目录")
        if target.is_symlink():
            raise CliError("准备包输出目录不能是链接目录")
        manifest = target / "package/fh_radio_studio_package_manifest.json"
        if target.exists() and any(target.iterdir()) and not manifest.is_file():
            raise CliError(f"输出目录不是完整准备包，请选择新的输出目录：{target}")
        target.parent.mkdir(parents=True, exist_ok=True)
        stage = Path(tempfile.mkdtemp(prefix=f".{target.name}-building-", dir=target.parent))
        backup = target.with_name(f".{target.name}-previous-{uuid.uuid4().hex}")

        # Validate exact owned paths before any recursive cleanup or rename.
        def owned(path):
            if path.is_symlink() or path.resolve().parent != target.parent.resolve():
                raise CliError("准备包临时目录超出预期位置")
            return path

        clone = argparse.Namespace(**vars(args))
        clone.out_dir = str(stage)
        clone._publish_out_dir = str(target)
        clone.reuse_package = getattr(args, "reuse_package", None) or (
            str(target) if manifest.is_file() else None
        )
        published = False
        try:
            result = function(clone)
            if result != 0:
                return result
            if not (stage / "package/fh_radio_studio_package_manifest.json").is_file():
                raise CliError("构建未生成完整准备包清单，已保留旧准备包")
            if target.exists():
                owned(target).rename(owned(backup))
            try:
                owned(stage).rename(target)
            except BaseException:
                if backup.exists():
                    owned(backup).rename(target)
                raise
            published = True
            print(f"准备包已完成：{target}")
            return result
        finally:
            if stage.exists():
                shutil.rmtree(owned(stage))
            if published and backup.exists():
                try:
                    shutil.rmtree(owned(backup))
                except OSError as error:
                    print(f"旧准备包清理未完成，保留于 {backup}: {error}")

    @wraps(function)
    def build(args):
        target = Path(args.out_dir).expanduser().absolute()
        with ExitStack() as stack:
            try:
                stack.enter_context(
                    exclusive_file_lock(target.with_name(f".{target.name}.build.lock"))
                )
            except FileLockTimeout as error:
                raise CliError("此准备包正在构建，请等待当前构建完成后重试。") from error
            return publish(args)

    return build


def published_path(args, path):
    final = getattr(args, "_publish_out_dir", None)
    if not final:
        return path
    try:
        relative = Path(path).absolute().relative_to(Path(args.out_dir).absolute())
    except ValueError:
        return path
    return Path(final) / relative
