"""Read-only membership of every RadioInfo list, independent of custom/builtin mode."""

from __future__ import annotations

import json
from pathlib import Path

from .common import CliError
from .metadata import _load_cache_entries, metadata_cache_path
from .project_refs import resolve_project_ref
from .reconstruct_plan import _read_radio_info_playlists
from .timing_import import match_tracks


def playlist_membership(project: Path, radio_info: Path) -> dict:
    # Reuse the import XML guard and authoritative parser; presence does not depend
    # on timing validity, station mode, prepared-package history or the baseline.
    raw = radio_info.read_bytes().replace(b"\x00", b"").upper()
    if b"<!DOCTYPE" in raw or b"<!ENTITY" in raw:
        raise CliError("RadioInfo XML 不支持 DTD 或实体声明")
    cache = metadata_cache_path(project)
    if not cache.is_file():
        raise CliError("歌曲资料尚未读取，无法可靠判断游戏归属")
    entries = {
        item["track_key"]: item
        for item in _load_cache_entries(cache).values()
        if item.get("track_key") and item.get("source_ref")
    }
    assignments, uncertain = [], set()
    resolved = {}
    for radio, lists in _read_radio_info_playlists(radio_info).items():
        for kind, tracks in lists.items():
            for slot, track in enumerate(tracks, 1):
                identity = (track.title, track.artist)
                if identity not in resolved:
                    matches = (
                        match_tracks(
                            project,
                            {"title": track.title, "artist": track.artist},
                            entries,
                            "title",
                        )
                        if track.title.strip()
                        else []
                    )
                    sources = [
                        str(resolve_project_ref(project, entries[key]["source_ref"]))
                        for key in matches
                    ]
                    if len(matches) != 1 or not Path(sources[0]).is_file():
                        uncertain.update(sources)
                        resolved[identity] = None
                    else:
                        resolved[identity] = matches[0]
                key = resolved[identity]
                if key is not None:
                    assignments.append(
                        {
                            "track_key": key,
                            "radio_code": radio,
                            "playlist_type": kind,
                            "slot": slot,
                        }
                    )
    return {
        "schema_version": 2,
        "assignments": assignments,
        "builtin_targets": [],
        "uncertain_sources": sorted(uncertain),
    }


def cmd_playlist_membership(args):
    try:
        result = playlist_membership(Path(args.project_dir), Path(args.radio_info))
    except (OSError, ValueError) as error:
        raise CliError(str(error)) from error
    print(json.dumps(result, ensure_ascii=False))
    return 0
