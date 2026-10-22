import hashlib
import json
import math
import shutil
import struct
import wave

import pytest

from backend.fh_radio_studio_cli.cli import main
from backend.fh_radio_studio_cli.metadata import (
    display_metadata_for_path,
    metadata_cache_path,
    read_track_metadata,
)


def audio(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(48000)
        stream.writeframes(
            b"".join(
                struct.pack("<h", round(8000 * math.sin(2 * math.pi * 440 * i / 48000)))
                for i in range(96000)
            )
        )
    return path


def test_edit_survives_scan_and_project_move_without_changing_audio(tmp_path):
    project = tmp_path / "project"
    source = audio(project / "sources" / "Song - Artist.wav")
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    assert (
        main(
            [
                "set-track-metadata",
                str(source),
                "--project-dir",
                str(project),
                "--title",
                "正しい曲名",
                "--artist",
                "Correct Artist",
            ]
        )
        == 0
    )
    assert main(["scan-metadata", "--project-dir", str(project), "--all-sources", "--json"]) == 0
    entry = json.loads(metadata_cache_path(project).read_text(encoding="utf-8"))["tracks"][0]
    assert entry["title"] == "正しい曲名"
    assert entry["artist"] == "Correct Artist"
    assert entry["track_key"].startswith("trkref_")
    assert hashlib.sha256(source.read_bytes()).hexdigest() == before
    relocated = tmp_path / "relocated"
    shutil.move(project, relocated)
    moved_source = relocated / "sources" / source.name
    assert display_metadata_for_path(
        moved_source, metadata_cache_path(relocated), ("wrong", "wrong")
    ) == ("Correct Artist", "正しい曲名")
    assert hashlib.sha256(moved_source.read_bytes()).hexdigest() == before


def test_edit_rejects_external_audio_and_control_characters(tmp_path):
    external = audio(tmp_path / "external.wav")
    for source, title in [
        (external, "Title"),
        (audio(tmp_path / "project/sources/track.wav"), "bad\nname"),
    ]:
        assert (
            main(
                [
                    "set-track-metadata",
                    str(source),
                    "--project-dir",
                    str(tmp_path / "project"),
                    "--title",
                    title,
                    "--artist",
                    "Artist",
                ]
            )
            == 2
        )
    assert not metadata_cache_path(tmp_path / "project").exists()


def test_filename_fallback_rule_is_unchanged(tmp_path):
    source = audio(tmp_path / "again - YUI.wav")
    info = read_track_metadata(source)
    assert (info.artist, info.title, info.from_tags) == ("again", "YUI", False)


@pytest.mark.parametrize("deferred", [False, True])
def test_edited_metadata_is_used_in_built_radio_xml(tmp_path, mock_game, deferred):
    from xml.etree import ElementTree as ET

    project = tmp_path / "project"
    source = audio(project / "sources" / "Old Artist - Old Title.wav")
    assert (
        main(
            [
                "set-track-metadata",
                str(source),
                "--project-dir",
                str(project),
                "--title",
                "New Title",
                "--artist",
                "New Artist",
            ]
        )
        == 0
    )
    output = project / "packages" / "edited"
    baseline = project / "backups" / "baseline-current"
    assert (
        main(
            [
                "baseline",
                "create",
                "--game-dir",
                str(mock_game.game_dir),
                "--out-dir",
                str(baseline),
                "--state",
                "current",
                "--yes",
            ]
        )
        == 0
    )
    assert (
        main(
            [
                "build-package",
                str(source),
                "--game-dir",
                str(mock_game.game_dir),
                "--radio",
                "4",
                "--source",
                "CHS",
                "--target",
                "EN",
                "--skip-bank",
                "--metadata-cache",
                str(metadata_cache_path(project)),
                "--baseline-manifest",
                str(baseline / "baseline_manifest.json"),
                "--playlist-mode",
                "only",
                "--out-dir",
                str(output),
                *(["--defer-publish"] if deferred else []),
            ]
        )
        == 0
    )
    if deferred:
        from backend.fh_radio_studio_cli.package_publication import completed_packages

        assert not output.exists()
        stage = completed_packages(output)[0]
        assert main(["publish-package", "--out-dir", str(output), "--ready-dir", str(stage)]) == 0
    root = ET.parse(output / "package/media/audio/RadioInfo_CN.xml").getroot()
    samples = root.findall(".//RadioStation[@Number='4']/SampleList[@Type='Track']/Sample")
    assert samples
    assert {sample.get("DisplayName") for sample in samples} == {"New Title"}
    assert {sample.get("Artist") for sample in samples} == {"New Artist"}
