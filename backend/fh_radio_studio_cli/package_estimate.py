"""Read-only package size projection, using the same plan/bank selection as build-package.

Vorbis quality is VBR, not a promised bitrate. Nominal curve uses Xiph's 44/48 kHz
stereo setup, with FSBank's [-.1,1] quality mapping; show a conservative +45% budget
separately. This is a warning aid, never proof that a game bank will fit.
"""

from __future__ import annotations

import argparse
import json
import math
import mmap
from pathlib import Path

from .bank_expansion import BANK_SIZE_LIMIT
from .common import CliError
from .fsb5 import parse_fsb5_bytes
from .game import default_radio_info, find_station, parse_xml
from .metadata import _load_cache_entries, metadata_cache_path, read_track_metadata
from .package import (
    load_playlist_groups_from_package,
    load_playlist_plan_builtin_targets,
    load_playlist_plan_groups,
    resolve_target_bank_for_station,
)
from .project_refs import track_key_for_project_path
from .reconstruct_plan import is_ui_supported_radio


def nominal_stereo_bps(quality: int) -> float:
    if not 1 <= quality <= 100:
        raise CliError("Build quality must be between 1 and 100")
    # https://github.com/xiph/vorbis/blob/master/lib/modes/setup_44.h (per channel)
    rates = [
        45000,
        64000,
        80000,
        96000,
        112000,
        128000,
        160000,
        192000,
        224000,
        256000,
        320000,
        500002,
    ]
    index = (quality - 1) / 9
    lower = min(10, int(index))
    return rates[lower] + (rates[lower + 1] - rates[lower]) * (index - lower)


def size_curve(seconds: float, fixed_bytes: int, slots: int) -> list[int]:
    return [
        math.ceil(fixed_bytes + 65536 + slots * 4096 + seconds * nominal_stereo_bps(q) / 8)
        for q in range(1, 101)
    ]


def mapped_bank_info(path: Path):
    with path.open("rb") as stream:
        if path.stat().st_size == 0:
            raise CliError(f"Empty bank: {path.name}")
        with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
            return parse_fsb5_bytes(data)


def estimate_package(args: argparse.Namespace) -> dict:
    project = Path(args.project_dir)
    baseline = Path(args.baseline_manifest)
    audio = baseline.parent / "media" / "audio"
    root = parse_xml(default_radio_info(audio)).getroot()
    restore = load_playlist_plan_builtin_targets(args.playlist_plan, root)
    groups = load_playlist_plan_groups(
        args.playlist_plan,
        root,
        project_dir=project,
        skip_radios={int(t["radio"]) for t in restore},
    )
    if not groups and getattr(args, "playlist_from_package", None):
        groups = load_playlist_groups_from_package(args.playlist_from_package, root)
    entries = _load_cache_entries(metadata_cache_path(project))
    rows: dict[str, dict] = {}
    manifest = json.loads(baseline.read_text(encoding="utf-8-sig"))
    for item in manifest.get("files", []):
        name = str(item.get("install_relative_path") or "")
        if not name:
            continue
        size = int(item.get("size") or 0)
        rows[name] = {
            "name": name,
            "sizes": [size] * 100,
            "upper_sizes": [size] * 100,
            "rebuilt": False,
            "limit_bytes": BANK_SIZE_LIMIT if name.endswith(".bank") else None,
        }
    stations = root.find("RadioStations")
    if stations is not None:
        for station in stations.findall("RadioStation"):
            if not is_ui_supported_radio(station.get("Name", "")):
                continue
            radio = int(station.get("Number", "0"))
            try:
                bank = resolve_target_bank_for_station(audio, station, radio, None)
            except CliError:
                continue
            name = "media/audio/FMODBanks/" + bank.name
            if name in rows:
                rows[name].update(primary_radio_bank=True, radio=radio, station=station.get("Name"))
    for group in groups:
        radio = int(group["radio"])
        station = find_station(root, radio)
        bank = resolve_target_bank_for_station(audio, station, radio, None)
        info = mapped_bank_info(bank)
        sources = list(group["sources"])
        durations = []
        for source in sources:
            key = track_key_for_project_path(project, source)
            entry = entries.get(key, {})
            stat = source.stat()
            try:
                cached = (
                    entry.get("size") == stat.st_size
                    and abs(float(entry.get("mtime_ms", -1)) - stat.st_mtime * 1000) < 2
                )
            except (ValueError, TypeError):
                cached = False
            duration = entry.get("duration_sec") if cached else None
            if (
                isinstance(duration, bool)
                or not isinstance(duration, (int, float))
                or not math.isfinite(duration)
                or duration <= 0
            ):
                duration = read_track_metadata(source).duration_sec
            if duration is None or not math.isfinite(duration) or duration <= 0:
                raise CliError(f"无法读取 {source.name} 的时长，不能可靠预估大小")
            durations.append(float(duration))
        slots = max(info.num_samples, len(sources)) if args.expand_slots else info.num_samples
        # The builder repeats assigned tracks to fill unused physical bank slots.
        seconds = sum(durations[i % len(durations)] for i in range(slots))
        fixed = max(0, bank.stat().st_size - info.total_size)
        sizes = size_curve(seconds, fixed, slots)
        name = "media/audio/FMODBanks/" + bank.name
        rows[name] = {
            "name": name,
            "radio": radio,
            "station": station.get("Name"),
            "sizes": sizes,
            "upper_sizes": [math.ceil(v * 1.45) for v in sizes],
            "duration_seconds": seconds,
            "slots": slots,
            "rebuilt": True,
            "primary_radio_bank": True,
            "limit_bytes": BANK_SIZE_LIMIT,
        }
    ordered = sorted(rows.values(), key=lambda item: (not item["rebuilt"], item["name"]))
    return {
        "schema_version": 1,
        "default_quality": 50,
        "quality_min": 1,
        "quality_max": 100,
        "method": "nominal_vorbis_48khz_stereo_with_bank_overhead",
        "warning": "可变码率估算；建议余量按估算值上浮 45%，实际以构建结果为准。",
        "files": ordered,
        "total_sizes": [sum(row["sizes"][q] for row in ordered) for q in range(100)],
        "total_upper_sizes": [sum(row["upper_sizes"][q] for row in ordered) for q in range(100)],
    }


def cmd_estimate_package(args: argparse.Namespace) -> int:
    print(json.dumps(estimate_package(args), ensure_ascii=False))
    return 0
