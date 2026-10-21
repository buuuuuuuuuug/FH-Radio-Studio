import json
from pathlib import Path
from xml.etree import ElementTree as ET

import pytest

from backend.fh_radio_studio_cli.common import CliError
from backend.fh_radio_studio_cli.playlist_membership import playlist_membership
from backend.fh_radio_studio_cli.project_refs import project_ref_for_path, track_key_for_source_ref

from .conftest import assert_cli_ok, run_cli


def fixture(tmp_path, *, duplicate=False, count=1):
    (tmp_path / "sources").mkdir()
    (tmp_path / ".fh-radio-studio").mkdir()
    entries = []
    for i in range(count + int(duplicate)):
        file = tmp_path / f"sources/{i}.wav"
        file.write_bytes(b"audio")
        ref = project_ref_for_path(tmp_path, file)
        entries.append(
            {
                "track_key": track_key_for_source_ref(ref),
                "source_ref": ref,
                "title": "Song 0" if duplicate else f"Song {i}",
                "artist": "Artist",
            }
        )
    (tmp_path / ".fh-radio-studio/track_metadata.json").write_text(
        json.dumps({"schema_version": 2, "tracks": entries}), encoding="utf-8"
    )
    xml = ET.Element("Radio")
    station = ET.SubElement(
        ET.SubElement(xml, "RadioStations"), "RadioStation", Number="9", Name="Horizon Opus"
    )
    samples = ET.SubElement(station, "SampleList", Type="Track")
    for i in range(count):
        ET.SubElement(
            samples, "Sample", SoundName=f"S{i}", DisplayName=f"Song {i}", Artist="Artist"
        )
    for kind in ["FreeRoam", "Event"]:
        playlist = ET.SubElement(station, "PlayList", Type=kind)
        for i in range(count):
            ET.SubElement(playlist, "Entry", Name=f"S{i}")
    path = tmp_path / "RadioInfo_CN.xml"
    ET.ElementTree(xml).write(path, encoding="utf-8")
    return entries, path


def test_reads_all_39_tracks_without_baseline_or_custom_detection(tmp_path):
    entries, xml = fixture(tmp_path, count=39)
    result = playlist_membership(tmp_path, xml)
    for kind in ["FreeRoam", "Event"]:
        assignments = [a for a in result["assignments"] if a["playlist_type"] == kind]
        assert len(assignments) == 39
        assert [a["slot"] for a in assignments] == list(range(1, 40))
        assert assignments[-1]["track_key"] == entries[-1]["track_key"]
    assert result["uncertain_sources"] == []
    assert result["builtin_targets"] == []
    # Membership is read-only; it must not create or overwrite an editable plan.
    assert not (tmp_path / ".fh-radio-studio/playlist_plan.json").exists()


def test_ambiguous_local_copies_are_unknown_instead_of_not_included(tmp_path):
    entries, xml = fixture(tmp_path, duplicate=True)
    result = playlist_membership(tmp_path, xml)
    assert result["assignments"] == []
    assert len(result["uncertain_sources"]) == len(entries)


def test_missing_source_is_unknown_and_does_not_shift_other_slots(tmp_path):
    entries, xml = fixture(tmp_path, count=2)
    (tmp_path / "sources/0.wav").unlink()
    result = playlist_membership(tmp_path, xml)
    assert len(result["uncertain_sources"]) == 1
    assert all(
        a["slot"] == 2 and a["track_key"] == entries[1]["track_key"] for a in result["assignments"]
    )


def test_cli_and_missing_metadata(tmp_path):
    _, xml = fixture(tmp_path)
    result = run_cli(
        "playlist-membership", "--project-dir", str(tmp_path), "--radio-info", str(xml)
    )
    assert_cli_ok(result)
    assert len(json.loads(result.stdout)["assignments"]) == 2
    (tmp_path / ".fh-radio-studio/track_metadata.json").unlink()
    with pytest.raises(CliError):
        playlist_membership(tmp_path, xml)


def test_entity_declarations_are_rejected(tmp_path):
    _, xml = fixture(tmp_path)
    xml.write_text('<!DOCTYPE Radio [<!ENTITY x "test">]><Radio/>', encoding="utf-8")
    with pytest.raises(CliError):
        playlist_membership(tmp_path, xml)
