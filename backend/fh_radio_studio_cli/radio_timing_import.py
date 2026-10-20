"""Read timing interchange rows from RadioInfo's Event track playlists."""

from __future__ import annotations

import xml.etree.ElementTree as ET

from .common import CliError
from .reconstruct_plan import is_ui_supported_radio

MARKERS = (
    "TrackDrop",
    "PostDrop",
    "TrackLoopStart",
    "TrackLoopEnd",
    "PostRaceLoopStart",
    "PostRaceLoopEnd",
)


def _radio_root(raw):
    # DTD/entity expansion has no role in the game's plain attribute XML.
    declarations = raw.replace(b"\x00", b"").upper()
    if b"<!DOCTYPE" in declarations or b"<!ENTITY" in declarations:
        raise CliError("RadioInfo XML 不支持 DTD 或实体声明")
    root = ET.fromstring(raw)
    stations = root.find("RadioStations") if root.tag == "Radio" else None
    if stations is None:
        raise CliError("不是有效的 RadioInfo XML：缺少 RadioStations")
    return stations


def radio_info_rows(raw):
    stations = _radio_root(raw)
    rows = []
    for station in stations.findall("RadioStation"):
        number = station.get("Number", "").strip()
        if number not in tuple(str(n) for n in range(1, 10)) or not is_ui_supported_radio(
            station.get("Name", "")
        ):
            continue
        lists = station.findall("PlayList")
        event_names = [
            entry.get("Name", "")
            for playlist in lists
            if playlist.get("Type", "").strip().casefold() == "event"
            for entry in playlist.findall("Entry")
        ]
        samples = [
            sample
            for group in station.findall("SampleList")
            if group.get("Type", "").strip().casefold() == "track"
            for sample in group.findall("Sample")
            if sample.get("SoundName", "") in event_names
        ]
        by_name = {sample.get("SoundName", ""): sample for sample in samples}
        for sound_name in event_names:
            sample = by_name.get(sound_name)
            if sample is None:
                raise CliError(f"R{number} 赛事列表引用了缺失的歌曲 {sound_name}")
            row = {
                "_radio_code": "R" + number,
                "_sound_name": sound_name,
                "title": sample.get("DisplayName", ""),
                "artist": sample.get("Artist", ""),
                "radio_station": "R" + number,
                "time_unit": "samples",
                "sample_rate": sample.get("SampleRate", ""),
            }
            if row["sample_rate"] != "48000":
                row["_input_error"] = "XML 中该歌曲的 SampleRate 必须为 48000 Hz"
            if not row["title"]:
                row["_input_error"] = "XML 中该歌曲缺少 DisplayName，无法可靠匹配本地歌曲"
            children = {}
            for marker in sample.findall("Marker"):
                name = marker.get("Name", "")
                if name in MARKERS:
                    value = marker.get("Position", "")
                    if name in children and children[name] != value:
                        row["_input_error"] = f"XML 中 {name} 存在冲突的 Marker"
                    children[name] = value
            for name in MARKERS:
                attribute, child = sample.get(name), children.get(name)
                if attribute is not None and child is not None and attribute != child:
                    row["_input_error"] = f"XML 中 {name} 属性与 Marker 的采样点不一致"
                value = attribute if attribute is not None else child
                if value is not None:
                    # -1 is the game's explicit 'not configured' sentinel.
                    row[name] = None if value.strip() == "-1" else value
            rows.append(row)
    if not rows:
        raise CliError("XML 中没有可导入的 R1–R9 赛事歌曲；FreeRoam（漫游）列表会被忽略")
    return rows


def _event_signatures(raw):
    """Compare complete ordered event contents, not merely slot names or counts."""
    root = _radio_root(raw)
    result = {}
    for station in root.findall("RadioStation"):
        number = station.get("Number", "").strip()
        if number not in tuple(str(n) for n in range(1, 10)) or not is_ui_supported_radio(
            station.get("Name", "")
        ):
            continue
        samples = {
            s.get("SoundName", ""): s
            for group in station.findall("SampleList")
            if group.get("Type", "").casefold() == "track"
            for s in group.findall("Sample")
        }
        entries = [
            e.get("Name", "")
            for group in station.findall("PlayList")
            if group.get("Type", "").casefold() == "event"
            for e in group.findall("Entry")
        ]
        if not entries:
            continue
        signature = []
        for name in entries:
            sample = samples.get(name)
            if sample is None:
                raise CliError(f"R{number} 赛事列表引用了缺失的歌曲 {name}")
            children = {m.get("Name"): m.get("Position") for m in sample.findall("Marker")}
            if any(
                sample.get(marker) is not None
                and marker in children
                and sample.get(marker) != children[marker]
                for marker in MARKERS
            ):
                raise CliError("XML 时间点属性与 Marker 不一致")
            signature.append(
                [
                    name,
                    sample.get("DisplayName", ""),
                    sample.get("Artist", ""),
                    sample.get("SampleRate", ""),
                    sample.get("SampleLength", ""),
                    *[sample.get(marker, children.get(marker, "")) for marker in MARKERS],
                ]
            )
        if "R" + number in result:
            raise CliError(f"XML 中存在重复的 R{number} 电台")
        result["R" + number] = signature
    return result


def radio_assignment_layouts(project, raw, matched_rows):
    imported = _event_signatures(raw)
    baseline = {}
    folder = project / "backups/baseline-current/media/audio"
    if folder.is_dir():
        for file in sorted(
            folder.glob("RadioInfo_*.xml"), key=lambda p: (p.name != "RadioInfo_CN.xml", p.name)
        ):
            try:
                for radio, signature in _event_signatures(file.read_bytes()).items():
                    baseline.setdefault(radio, []).append(signature)
            except (ET.ParseError, CliError, OSError):
                continue
            if all(signature in baseline.get(radio, []) for radio, signature in imported.items()):
                break
    matched = {(r.get("radio_code"), r.get("sound_name")): r for r in matched_rows}
    layouts = []
    for radio, signature in imported.items():
        item = {"radio_code": radio, "playlist_type": "Event", "count": len(signature)}
        sources = []
        for sample in signature:
            row = matched.get((radio, sample[0]), {})
            if not row.get("source") or not row.get("source_matched", row.get("status") != "error"):
                break
            sources.append(row["source"])
        if len(sources) == len(signature):
            if len(set(sources)) != len(sources):
                item.update(mode="blocked", message="同一电台含重复歌曲，保留当前列表")
            else:
                item.update(
                    mode="custom", sources=sources, message=f"替换为 {len(sources)} 首可编辑歌曲"
                )
        elif signature in baseline.get(radio, []):
            item.update(
                mode="builtin",
                message=f"恢复原版 {len(signature)} 首（缺少完整本地源文件）",
                sources=[],
            )
        else:
            item.update(mode="blocked", message="部分歌曲未能可靠匹配，保留当前电台列表")
        layouts.append(item)
    return layouts
