"""Preview and apply explicit time data without interpreting document instructions."""

from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import io
import json
import math
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PureWindowsPath

from .common import CliError
from .metadata import _load_cache_entries, metadata_cache_path, read_track_metadata
from .project_json_guard import write_project_json
from .project_refs import project_path_or_absolute, resolve_project_ref
from .radio_timing_import import radio_assignment_layouts, radio_info_rows
from .timing_units import (
    SAMPLE_RATE,
    row_time_unit,
    samples_to_seconds,
    seconds_to_samples,
    validate_units,
)

GROUPS = {
    "td": ("TrackDrop",),
    "pd": ("PostDrop",),
    "tl": ("TrackLoopStart", "TrackLoopEnd"),
    "pl": ("PostRaceLoopStart", "PostRaceLoopEnd"),
}
ALIASES = {
    "trackkey": "track_key",
    "samplerate": "sample_rate",
    "采样率": "sample_rate",
    "timeunit": "time_unit",
    "时间单位": "time_unit",
    "radiostation": "radio_station",
    "文件": "file",
    "文件名": "file",
    "来源文件": "file",
    "source": "file",
    "filename": "file",
    "filepath": "file",
    "曲目": "title",
    "歌曲": "title",
    "歌曲名": "title",
    "歌名": "title",
    "song": "title",
    "track": "title",
    "歌手": "artist",
    "艺术家": "artist",
    "作家": "artist",
    "td": "TrackDrop",
    "trackdrop": "TrackDrop",
    "pd": "PostDrop",
    "postdrop": "PostDrop",
    "tla": "TrackLoopStart",
    "tlb": "TrackLoopEnd",
    "pla": "PostRaceLoopStart",
    "plb": "PostRaceLoopEnd",
    "tl1": "TrackLoopStart",
    "tl2": "TrackLoopEnd",
    "pl1": "PostRaceLoopStart",
    "pl2": "PostRaceLoopEnd",
    "tlstart": "TrackLoopStart",
    "trackloopstart": "TrackLoopStart",
    "tl起点": "TrackLoopStart",
    "tlend": "TrackLoopEnd",
    "trackloopend": "TrackLoopEnd",
    "tl终点": "TrackLoopEnd",
    "plstart": "PostRaceLoopStart",
    "postloopstart": "PostRaceLoopStart",
    "postraceloopstart": "PostRaceLoopStart",
    "pl起点": "PostRaceLoopStart",
    "plend": "PostRaceLoopEnd",
    "postloopend": "PostRaceLoopEnd",
    "postraceloopend": "PostRaceLoopEnd",
    "pl终点": "PostRaceLoopEnd",
    "tl": "tl_range",
    "trackloop": "tl_range",
    "tl起止": "tl_range",
    "pl": "pl_range",
    "postloop": "pl_range",
    "pl起止": "pl_range",
    "bpm": "bpm",
    "title": "title",
    "artist": "artist",
    "file": "file",
}


def key(value):
    return re.sub(r"[\s_.\-:：()（）/]+", "", unicodedata.normalize("NFKC", str(value)).casefold())


def time_value(value):
    if isinstance(value, bool):
        raise ValueError("时间不能是布尔值")
    if isinstance(value, (int, float)):
        result = float(value)
    else:
        text = (
            unicodedata.normalize("NFKC", str(value)).strip().replace("：", ":").replace(",", ".")
        )
        if re.fullmatch(r"\d+(?:\.\d+)?", text):
            result = float(text)
        elif ":" in text:
            parts = text.split(":")
            if len(parts) not in (2, 3) or any(
                not re.fullmatch(r"\d+(?:\.\d+)?", p.strip()) for p in parts
            ):
                raise ValueError("时间格式无效")
            nums = list(map(float, parts))
            if any(n >= 60 for n in nums[1:]):
                raise ValueError("秒数或小时后的分钟须小于 60")
            result = sum(n * 60**i for i, n in enumerate(reversed(nums)))
        else:
            unit = re.compile(
                r"(\d+(?:\.\d+)?)\s*(毫秒|milliseconds?|ms|小时|hours?|h|分钟|分|minutes?|min|m|秒|seconds?|sec|s)",
                re.I,
            )
            matches = list(unit.finditer(text))
            if not matches or unit.sub("", text).strip():
                raise ValueError("不能识别时间格式")
            result = 0.0
            for match in matches:
                number = float(match[1])
                u = match[2].casefold()
                result += number * (
                    0.001
                    if u in ("ms", "毫秒", "millisecond", "milliseconds")
                    else (
                        3600
                        if u in ("h", "小时", "hour", "hours")
                        else 60 if u in ("m", "min", "分", "分钟", "minute", "minutes") else 1
                    )
                )
    if not math.isfinite(result) or result < 0:
        raise ValueError("时间必须为非负有限数")
    return result


def _xlsx(raw):
    ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    with zipfile.ZipFile(io.BytesIO(raw)) as book:
        if len(book.infolist()) > 3000 or sum(i.file_size for i in book.infolist()) > 40_000_000:
            raise CliError("表格过大，请另存为 CSV 后导入")
        shared = []
        if "xl/sharedStrings.xml" in book.namelist():
            shared = [
                "".join(si.itertext())
                for si in ET.fromstring(book.read("xl/sharedStrings.xml")).findall("m:si", ns)
            ]
        time_styles = set()
        if "xl/styles.xml" in book.namelist():
            styles = ET.fromstring(book.read("xl/styles.xml"))
            custom = {
                int(f.get("numFmtId")): f.get("formatCode", "")
                for f in styles.findall("m:numFmts/m:numFmt", ns)
            }
            for i, style in enumerate(styles.findall("m:cellXfs/m:xf", ns)):
                num = int(style.get("numFmtId", "0"))
                fmt = custom.get(num, "").casefold()
                if num in set(range(14, 23)) | {45, 46, 47} or re.search(
                    r"(?:\[m+\]|m+:s|h+:m|s+\.0)", fmt
                ):
                    time_styles.add(i)
        result = []
        for name in sorted(
            n for n in book.namelist() if re.fullmatch(r"xl/worksheets/sheet\d+\.xml", n)
        ):
            grid = []
            for row in ET.fromstring(book.read(name)).findall("m:sheetData/m:row", ns):
                cells = {}
                for cell in row.findall("m:c", ns):
                    letters = re.match(r"[A-Z]+", cell.get("r", "A1")).group()
                    col = 0
                    for letter in letters:
                        col = col * 26 + ord(letter) - 64
                    if col > 256:
                        continue
                    text = cell.findtext("m:v", "", ns)
                    if cell.get("t") == "s":
                        text = shared[int(text)] if text else ""
                    elif cell.get("t") == "inlineStr":
                        inline = cell.find("m:is", ns)
                        text = "".join(inline.itertext()) if inline is not None else ""
                    elif text and int(cell.get("s", "0")) in time_styles:
                        text = float(text) * 86400
                    cells[col - 1] = text
                if cells:
                    grid.append([cells.get(i, "") for i in range(max(cells) + 1)])
            result.extend(_table(grid))
        return result


def _table(grid):
    if not grid:
        return []
    header = None
    output = []
    for row in grid:
        names = [ALIASES.get(key(c), str(c).strip()) for c in row]
        if any(n in names for n in ("track_key", "file", "title")) and any(
            n in names
            for n in (
                *sum((list(g) for g in GROUPS.values()), []),
                "tl_range",
                "pl_range",
                "radio_station",
            )
        ):
            supported = [n for n in names if n in set(ALIASES.values())]
            if len(supported) != len(set(supported)):
                raise CliError("表头存在重复列（包括同义列），请每个时间点只保留一列")
            header = names
            continue
        if header is None:
            continue
        if any(value is not None and str(value).strip() for value in row):
            output.append({name: row[i] if i < len(row) else "" for i, name in enumerate(header)})
    return output


def parse_rows(raw, format):
    if len(raw) > 8_000_000:
        raise CliError("导入数据过大，最多 8 MB")
    if format == "xlsx":
        return _xlsx(raw)
    if format == "xml" or raw.lstrip(b"\xef\xbb\xbf\x00 \t\r\n").startswith(b"<"):
        return radio_info_rows(raw)
    text = raw.decode("utf-8-sig")
    if not text.strip():
        raise CliError("导入内容为空")
    if format == "json" or text.lstrip().startswith(("[", "{")):
        data = json.loads(text)
        if isinstance(data, dict):
            rows = data.get("tracks", data.get("rows"))
            if rows is not None:
                if not isinstance(rows, list):
                    raise CliError("JSON 需要歌曲数组或包含 tracks 的对象")
                units = {
                    ALIASES.get(key(k), k): v
                    for k, v in data.items()
                    if ALIASES.get(key(k), k) in ("time_unit", "sample_rate")
                }
                data = [dict(units, **row) if isinstance(row, dict) else row for row in rows]
            else:
                data = [data]
        if not isinstance(data, list):
            raise CliError("JSON 需要歌曲数组或包含 tracks 的对象")
        return data
    delimiter = "\t" if "\t" in text.splitlines()[0] else ","
    if delimiter == "," and ";" in text.splitlines()[0] and "," not in text.splitlines()[0]:
        delimiter = ";"
    return _table(list(csv.reader(io.StringIO(text), delimiter=delimiter)))


def _normalized(row):
    if not isinstance(row, dict):
        raise ValueError("每首歌需要一个对象")
    out = {}
    marker_units = set()

    def add(column, value):
        name = ALIASES.get(key(column), column)
        if name in out:
            raise ValueError(f"同一行存在重复字段（包括同义字段）：{name}")
        out[name] = value

    for k, v in row.items():
        if k in ("markers_sec", "markers_samples") and isinstance(v, dict):
            unit = "samples" if k == "markers_samples" else "time"
            marker_units.add(unit)
            for marker, value in v.items():
                add(marker, value)
        else:
            add(k, v)
    if marker_units:
        if len(marker_units) > 1:
            raise ValueError("同一行不能混用秒和采样点时间组")
        inferred = next(iter(marker_units))
        if "time_unit" in out and row_time_unit(out) != inferred:
            raise ValueError("时间单位与 markers_sec / markers_samples 不一致")
        out["time_unit"] = inferred
    for group, columns in [("tl", GROUPS["tl"]), ("pl", GROUPS["pl"])]:
        raw = out.get(group + "_range")
        if raw is not None:
            parts = re.split(r"\s*(?:->|→|–|—|\s-\s)\s*", str(raw))
            if len(parts) != 2:
                raise ValueError(f"{group.upper()} 需要起止两个时间，用 → 或空格-空格分隔")
            if any(column in out for column in columns):
                raise ValueError(f"{group.upper()} 范围与单独起止字段重复，请只保留一种表示")
            out.update(zip(columns, parts))
    return out


def _sha(raw):
    return hashlib.sha256(raw).hexdigest()


MATCH_MODES = ("auto", "filename", "title", "title-artist", "artist-title")
CSV_COLUMNS = ("Filename", "TD", "PD", "TL-A", "TL-B", "PL-A", "PL-B")


def identity_key(value):
    return re.sub(r"[\W_]+", "", unicodedata.normalize("NFKC", str(value)).casefold())


def match_tracks(project, data, entries, mode):
    if mode not in MATCH_MODES:
        raise ValueError("未知匹配方式")
    if data.get("track_key"):
        return [str(data["track_key"])] if str(data["track_key"]) in entries else []
    value = str(data.get("file") or data.get("title") or "").strip()
    if not value:
        raise ValueError("缺少文件名或歌曲名")
    if mode in ("auto", "filename") and data.get("file"):
        name = PureWindowsPath(value).name.casefold()
        exact = [
            k
            for k, c in entries.items()
            if resolve_project_ref(project, c["source_ref"]).name.casefold() == name
            or c["source_ref"] == value
        ]
        if exact:
            return exact
    title = str(data.get("title") or value)
    artist = str(data.get("artist") or "")
    if mode in ("auto", "title") and data.get("title"):
        exact = [
            k
            for k, c in entries.items()
            if identity_key(c.get("title", "")) == identity_key(title)
            and (not artist or identity_key(c.get("artist", "")) == identity_key(artist))
        ]
        if exact or mode == "title" or artist:
            return exact
    target = identity_key(
        PureWindowsPath(value).stem
        if PureWindowsPath(value).suffix.lower()
        in (".wav", ".flac", ".mp3", ".ogg", ".m4a", ".aac")
        else value
    )
    matches = []
    for k, c in entries.items():
        file = resolve_project_ref(project, c["source_ref"])
        song, who = str(c.get("title", "")), str(c.get("artist", ""))
        keys = {
            "filename": [file.name, file.stem],
            "title": [song],
            "title-artist": [song + "_" + who],
            "artist-title": [who + "_" + song],
        }
        modes = keys if mode == "auto" else [mode]
        candidate_keys = [identity_key(v) for m in modes for v in keys[m]]
        if target in candidate_keys and target:
            matches.append(k)
    return matches


def radio_values(value):
    if value is None or str(value).strip() == "":
        return []
    parts = re.split(r"[;；|、,，\s]+", unicodedata.normalize("NFKC", str(value)).strip())
    radios = []
    for part in parts:
        if not re.fullmatch(r"[Rr]?[1-9]", part):
            raise ValueError("Radio_station 只能填写 R1–R9 或 1–9；多个电台用分号分隔")
        radio = "R" + part[-1]
        if radio not in radios:
            radios.append(radio)
    return radios


def _saved_radios(project):
    path = project / ".fh-radio-studio/playlist_plan.json"
    if not path.exists():
        return {}
    document = json.loads(path.read_text(encoding="utf-8-sig"))
    result = {}
    for assignment in document.get("assignments", []):
        if not isinstance(assignment, dict) or not assignment.get("track_key"):
            continue
        radio = str(assignment.get("radio_code", ""))
        if re.fullmatch(r"R[1-9]", radio) and assignment.get("slot", 0) > 0:
            result.setdefault(assignment["track_key"], set()).add(radio)
    return result


def export_timings(
    project, identity="filename", *, include_radio=False, time_unit="time", sample_rate=SAMPLE_RATE
):
    validate_units(time_unit, sample_rate)
    if identity not in MATCH_MODES[1:]:
        raise CliError("未知导出标识方式")
    timing = project / "analysis/track_timing.json"
    doc = json.loads(timing.read_text(encoding="utf-8-sig")) if timing.exists() else {"tracks": []}
    configs = {
        c.get("track_key"): c
        for c in doc.get("tracks", [])
        if isinstance(c, dict) and c.get("track_key")
    }
    entries = [
        c
        for c in _load_cache_entries(metadata_cache_path(project)).values()
        if c.get("track_key") and c.get("source_ref")
    ]
    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer)
    writer.writerow(
        [CSV_COLUMNS[0]] + (["Radio_station"] if include_radio else []) + list(CSV_COLUMNS[1:])
    )
    stations = _saved_radios(project) if include_radio else {}
    count, names = 0, []
    for entry in sorted(
        entries,
        key=lambda c: (
            str(c.get("artist", "")).casefold(),
            str(c.get("title", "")).casefold(),
            c["source_ref"],
        ),
    ):
        config = configs.get(entry["track_key"], {})
        name = resolve_project_ref(project, entry["source_ref"]).name
        title, artist = str(entry.get("title", "")), str(entry.get("artist", ""))
        name = {
            "filename": name,
            "title": title,
            "title-artist": title + "_" + artist,
            "artist-title": artist + "_" + title,
        }[identity]
        values = []
        for marker in (
            "TrackDrop",
            "PostDrop",
            "TrackLoopStart",
            "TrackLoopEnd",
            "PostRaceLoopStart",
            "PostRaceLoopEnd",
        ):
            value = config.get("markers_sec", {}).get(marker)
            if value is None:
                values.append("")
            elif (
                isinstance(value, (int, float))
                and not isinstance(value, bool)
                and math.isfinite(value)
                and value >= 0
            ):
                if time_unit == "samples":
                    values.append(seconds_to_samples(value))
                else:
                    millis = round(value * 1000)
                    values.append(
                        f"{millis // 60000}:{(millis // 1000) % 60:02d}.{millis % 1000:03d}"
                    )
            else:
                raise CliError(f"歌曲 {name} 包含无效时间点，导出已停止")
        radio = ";".join(sorted(stations.get(entry["track_key"], [])))
        writer.writerow([name] + ([radio] if include_radio else []) + values)
        names.append(identity_key(name))
        count += 1
    duplicates = len(names) - len(set(names))
    return {
        "schema_version": 1,
        "csv": buffer.getvalue(),
        "count": count,
        "identity": identity,
        "time_unit": time_unit,
        "sample_rate": SAMPLE_RATE if time_unit == "samples" else None,
        "warning": "标识存在重名，建议使用文件名导出并核对预览。" if duplicates else "",
    }


def cmd_export_timings(args):
    try:
        result = export_timings(
            Path(args.project_dir),
            args.identity,
            include_radio=getattr(args, "include_radio", False),
            time_unit=getattr(args, "time_unit", "time"),
            sample_rate=getattr(args, "sample_rate", SAMPLE_RATE),
        )
    except (ValueError, OSError) as error:
        raise CliError(str(error)) from error
    print(json.dumps(result, ensure_ascii=False))
    return 0


def preview_import(
    project,
    raw,
    format,
    *,
    overwrite=False,
    confirm=False,
    match_mode="auto",
    assign_radio=False,
    time_unit="time",
    sample_rate=SAMPLE_RATE,
):
    validate_units(time_unit, sample_rate)
    timing = project / "analysis/track_timing.json"
    timing_raw = timing.read_bytes() if timing.exists() else b""
    metadata_raw = metadata_cache_path(project).read_bytes()
    doc = (
        json.loads(timing_raw.decode("utf-8-sig"))
        if timing_raw
        else {"schema_version": 2, "tracks": []}
    )
    if any(not isinstance(c, dict) or not c.get("track_key") for c in doc.get("tracks", [])):
        raise CliError("项目点位需要先完成迁移，暂不能批量导入")
    configs = {
        c["track_key"]: c
        for c in doc.get("tracks", [])
        if isinstance(c, dict) and c.get("track_key")
    }
    entries = {
        c["track_key"]: c
        for c in _load_cache_entries(metadata_cache_path(project)).values()
        if c.get("track_key") and c.get("source_ref")
    }
    rows = parse_rows(raw, format)
    is_radio_info = format == "xml" or raw.lstrip(b"\xef\xbb\xbf\x00 \t\r\n").startswith(b"<")
    if not rows:
        raise CliError("没有找到时间点数据；请使用带“文件名/歌曲名”和 TD/PD/TL/PL 的表头")
    if len(rows) > 10000:
        raise CliError("一次最多导入 10000 行")
    output = []
    proposals = {}
    seen = {}
    seen_radios = {}
    conflicts = set()
    for number, row in enumerate(rows, 1):
        result = {"row": number, "status": "error", "title": "", "message": ""}
        output.append(result)
        if is_radio_info:
            result.update(radio_code=row.get("_radio_code"), sound_name=row.get("_sound_name"))
        try:
            data = _normalized(row)
            if is_radio_info:
                result["title"] = f'{data.get("artist", "")} - {data.get("title", "")}'
                if data.get("_input_error"):
                    raise ValueError(data["_input_error"])
            parser = (
                samples_to_seconds if row_time_unit(data, time_unit) == "samples" else time_value
            )
            matches = match_tracks(project, data, entries, "auto" if is_radio_info else match_mode)
            if len(matches) != 1:
                raise ValueError(
                    "未找到对应歌曲" if not matches else "匹配到多首歌曲，请提供文件名或 track_key"
                )
            track_key = matches[0]
            if track_key in conflicts:
                raise ValueError("同一歌曲存在冲突数据，未导入该歌曲")
            entry = entries[track_key]
            result.update(
                track_key=track_key, title=f'{entry.get("artist","")} - {entry.get("title","")}'
            )
            stations = radio_values(data.get("radio_station")) if assign_radio else []
            result["radio_stations"] = stations
            source = resolve_project_ref(project, entry["source_ref"])
            result["source"] = str(source)
            if not source.is_file():
                raise ValueError("对应歌曲文件不存在")
            result["source_matched"] = True
            duration = entry.get("duration_sec")
            stat = source.stat()
            if (
                not duration
                or entry.get("size") != stat.st_size
                or entry.get("mtime_ms") != int(stat.st_mtime * 1000)
            ):
                duration = read_track_metadata(source).duration_sec
            if (
                not isinstance(duration, (int, float))
                or not math.isfinite(duration)
                or duration <= 0
            ):
                raise ValueError("歌曲缺少有效时长，先重新扫描元数据")
            before = copy.deepcopy(
                configs.get(
                    track_key,
                    {"track_key": track_key, "bpm": 0, "markers_sec": {}, "confirmed": {}},
                )
            )
            next = copy.deepcopy(before)
            markers = next.setdefault("markers_sec", {})
            confirmed = next.setdefault("confirmed", {})
            changed = []
            skipped = []
            for group, columns in GROUPS.items():
                present = [c for c in columns if c in data]
                if not present:
                    continue
                supplied = {
                    c: parser(data[c])
                    for c in present
                    if data[c] is not None and str(data[c]).strip()
                }
                if not overwrite and any(c in markers for c in columns):
                    if supplied:
                        skipped.append(group.upper())
                    continue
                # Explicit blank cells clear only when overwrite is enabled.
                if overwrite:
                    for c in present:
                        markers.pop(c, None)
                markers.update(supplied)
                values = {c: markers[c] for c in columns if c in markers}
                if any(
                    not isinstance(v, (int, float))
                    or not math.isfinite(v)
                    or v < 0
                    or v > duration + 1e-6
                    for v in values.values()
                ):
                    raise ValueError(f"{group.upper()} 超出歌曲时长 {duration:.3f} 秒")
                complete = len(values) == len(columns)
                if complete and len(columns) == 2 and values[columns[1]] <= values[columns[0]]:
                    raise ValueError(f"{group.upper()} 结束必须晚于开始")
                confirmed[group] = bool(confirm and complete)
                if supplied or overwrite:
                    changed.append(group.upper())
            new_empty = track_key not in configs and any(
                c in data for columns in GROUPS.values() for c in columns
            )
            if not changed and not stations and not new_empty:
                result.update(
                    status="skipped",
                    message=(
                        "已有时间组已跳过，请勾选允许覆盖" if skipped else "没有提供支持的时间点"
                    ),
                )
                continue
            if data.get("bpm") is not None:
                bpm = float(data["bpm"])
                if not math.isfinite(bpm) or not 0 < bpm <= 500:
                    raise ValueError("BPM 必须为 0–500 之间的正数")
                next["bpm"] = bpm
            if track_key in seen:
                previous = seen[track_key]
                if is_radio_info and proposals.get(track_key) == next:
                    stations = sorted(set(seen_radios[track_key]) | set(stations))
                    seen_radios[track_key] = stations
                    previous["radio_stations"] = stations
                    if stations:
                        previous["message"] = "导入 XML 时间点；分配至 " + ", ".join(stations)
                    result.update(status="skipped", message="相同歌曲时间点已合并")
                    continue
                if proposals.get(track_key) == next and seen_radios.get(track_key) == stations:
                    result.update(status="skipped", message="与前一行相同，已合并")
                    continue
                previous.update(status="error", message="同一歌曲出现冲突数据，未导入该歌曲")
                proposals.pop(track_key, None)
                conflicts.add(track_key)
                raise ValueError("同一歌曲出现多行冲突数据")
            seen[track_key] = result
            seen_radios[track_key] = stations
            proposals[track_key] = next
            result.update(
                status="ready",
                message=("导入 " + ", ".join(changed) if changed else "保留空白时间点")
                + ("；分配至 " + ", ".join(stations) if stations else "")
                + ("；跳过已有 " + ", ".join(skipped) if skipped else ""),
                markers_sec={c: markers.get(c) for columns in GROUPS.values() for c in columns},
                complete=all(
                    confirmed.get(g, False) and all(c in markers for c in cols)
                    for g, cols in GROUPS.items()
                ),
            )
        except (ValueError, TypeError, KeyError, OSError) as error:
            result["message"] = str(error)
    layouts = (
        radio_assignment_layouts(project, raw, output) if is_radio_info and assign_radio else []
    )
    restored = {layout["radio_code"] for layout in layouts if layout["mode"] == "builtin"}
    for row in output:
        if row.get("radio_code") in restored and row["status"] == "error":
            row.update(status="builtin", message="原版曲目随电台恢复，无需匹配本地文件")
    return {
        "schema_version": 1,
        "radio_layouts": layouts,
        "snapshot_hash": _sha(timing_raw + metadata_raw),
        "input_hash": _sha(
            raw
            + json.dumps(
                [
                    overwrite,
                    confirm,
                    match_mode,
                    assign_radio,
                    format,
                    time_unit,
                    sample_rate,
                    layouts,
                ]
            ).encode("utf-8")
        ),
        "time_unit": "samples" if is_radio_info else time_unit,
        "source_format": "radio-info" if is_radio_info else format,
        "sample_rate": SAMPLE_RATE,
        "rows": output,
        "ready_count": sum(c["status"] == "ready" for c in output),
        "_proposals": proposals,
        "_document": doc,
    }


def import_timings(args):
    project = Path(args.project_dir)
    if args.input == "-":
        raw = sys.stdin.buffer.read(8_000_001)
    else:
        with Path(args.input).open("rb") as stream:
            raw = stream.read(8_000_001)
    format = args.format
    if format == "auto":
        format = Path(args.input).suffix.lower().lstrip(".") if args.input != "-" else "text"
    result = preview_import(
        project,
        raw,
        format,
        overwrite=args.overwrite,
        confirm=args.confirm,
        match_mode=getattr(args, "match_mode", "auto"),
        assign_radio=getattr(args, "assign_radio", False),
        time_unit=getattr(args, "time_unit", "time"),
        sample_rate=getattr(args, "sample_rate", SAMPLE_RATE),
    )
    proposals = result.pop("_proposals")
    doc = result.pop("_document")
    if args.apply:
        if (
            args.expected_snapshot != result["snapshot_hash"]
            or args.expected_input != result["input_hash"]
        ):
            raise CliError("文件或项目点位已变化，请重新预览后再导入")
        if not proposals:
            if any(layout["mode"] in ("builtin", "custom") for layout in result["radio_layouts"]):
                result.update(applied_count=0)
                return result
            raise CliError("没有可以导入的数据")
        path = project / "analysis/track_timing.json"
        cache = metadata_cache_path(project).read_bytes()
        current = path.read_bytes() if path.exists() else b""
        if _sha(current + cache) != args.expected_snapshot:
            raise CliError("项目点位刚刚改变，请重新预览")
        backup_dir = project / "analysis/timing-import-backups"
        backup_dir.mkdir(parents=True, exist_ok=True)
        backup = backup_dir / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f") + ".json")
        backup.write_bytes(
            current or json.dumps({"schema_version": 2, "tracks": []}).encode("utf-8")
        )
        now = datetime.now(timezone.utc).isoformat()
        old = {
            c["track_key"]: c
            for c in doc.get("tracks", [])
            if isinstance(c, dict) and c.get("track_key")
        }
        for track_key, config in proposals.items():
            config["updated_at"] = now
            old[track_key] = config
        doc.update(schema_version=2, updated_at=now, tracks=list(old.values()))
        write_project_json(path, doc, project_dir=project)
        result.update(
            applied_count=len(proposals), backup=project_path_or_absolute(project, backup)
        )
    return result


def cmd_import_timings(args):
    try:
        payload = import_timings(args)
    except (
        ValueError,
        OSError,
        IndexError,
        TypeError,
        csv.Error,
        zipfile.BadZipFile,
        ET.ParseError,
    ) as error:
        raise CliError(str(error)) from error
    print(json.dumps(payload, ensure_ascii=False))
    return 0
