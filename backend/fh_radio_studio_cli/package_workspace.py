"""Transient radio audio: write once, link repeated slots, release after verification."""

from __future__ import annotations

import mmap
import os
import shutil
from pathlib import Path

from .common import CliError
from .fsb5 import parse_fsb5_bytes


def stage_wav(source: Path | str, destination: Path) -> None:
    """The first slot is already prepared; repeated slots are read-only aliases."""
    source = Path(source)
    if source.resolve() == destination.resolve():
        return
    if destination.exists() or destination.is_symlink():
        raise CliError(f"构建槽位文件已存在：{destination}")
    try:
        os.link(source, destination)
    except OSError:
        # FAT/exFAT, different volumes and restricted filesystems may reject links.
        # Never overwrite a file that appeared while attempting the link.
        with destination.open("xb") as output, source.open("rb") as input_stream:
            shutil.copyfileobj(input_stream, output)


def cleanup_audio_workspace(out_dir: Path | str, *paths: Path) -> None:
    """Only remove generated descendants of this build's work directory."""
    work = (Path(out_dir).expanduser() / "work").resolve()
    for path in paths:
        resolved = path.resolve()
        if path.is_symlink() or resolved == work or not resolved.is_relative_to(work):
            raise CliError(f"临时音频目录超出构建工作区：{path}")
        if path.is_dir():
            try:
                shutil.rmtree(path)
            except OSError as error:
                print(f"临时音频清理未完成：{path}: {error}")


def finish_radio_audio(args, stage_dir: Path, encoded_dir: Path, bank: Path, slots: int) -> None:
    """Verify the final bank before releasing that radio's WAV and encoded FSB."""
    if args.skip_bank:
        return
    with bank.open("rb") as stream:
        if os.fstat(stream.fileno()).st_size == 0:
            raise CliError(f"生成的电台 bank 为空：{bank.name}")
        with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
            info = parse_fsb5_bytes(data)
            if info.num_samples != slots or info.bank_offset + info.total_size > len(data):
                raise CliError(f"生成的电台 bank 校验失败：{bank.name}")
    cleanup_audio_workspace(args.out_dir, stage_dir, encoded_dir)
