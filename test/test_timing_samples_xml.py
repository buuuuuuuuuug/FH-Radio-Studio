import csv
import io
import json
import xml.etree.ElementTree as ET
from test.test_timing_import import TimingImportTests as _TimingFixture

import pytest

from backend.fh_radio_studio_cli.common import CliError
from backend.fh_radio_studio_cli.timing_import import export_timings, parse_rows, preview_import


@pytest.fixture
def project():
    fixture = _TimingFixture()
    fixture.setUp()
    try:
        yield fixture
    finally:
        fixture.doCleanups()


def radio_xml(*, rate="48000", marker="96001", second_radio=False, child_only=False):
    root = ET.Element("Radio")
    stations = ET.SubElement(root, "RadioStations")
    for number in ([1, 2] if second_radio else [1]):
        station = ET.SubElement(stations, "RadioStation", Number=str(number), Name="Radio")
        samples = ET.SubElement(station, "SampleList", Type="Track")
        sample = ET.SubElement(
            samples,
            "Sample",
            SoundName="event-song",
            DisplayName="Song",
            Artist="Artist",
            SampleRate=rate,
        )
        markers = {
            "TrackDrop": "1",
            "TrackLoopStart": marker,
            "TrackLoopEnd": "336002",
            "PostRaceLoopStart": "-1",
            "PostRaceLoopEnd": "-1",
        }
        for name, value in markers.items():
            if not child_only:
                sample.set(name, value)
            ET.SubElement(sample, "Marker", Name=name, Position=value)
        ET.SubElement(
            samples, "Sample", SoundName="roam-only", DisplayName="Wrong", SampleRate="44100"
        )
        ET.SubElement(ET.SubElement(station, "PlayList", Type="Event"), "Entry", Name="event-song")
        ET.SubElement(
            ET.SubElement(station, "PlayList", Type="FreeRoam"), "Entry", Name="roam-only"
        )
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def test_samples_roundtrip_preserves_single_sample_and_partial_configuration(project):
    raw = b"Filename,TD,PD,TL-A,TL-B,PL-A,PL-B\nArtist - Song.wav,1,,96001,336002,,\n"
    args = project.args(raw)
    args.overwrite = True
    args.confirm = True
    args.time_unit = "samples"
    preview = project.apply(
        args,
        preview_import(project.p, raw, "csv", overwrite=True, confirm=True, time_unit="samples"),
    )
    assert preview["applied_count"] == 1
    config = json.loads(project.path.read_text(encoding="utf-8"))["tracks"][0]
    assert config["markers_sec"]["TrackDrop"] == 1 / 48000
    assert config["confirmed"]["tl"] is True
    assert config["confirmed"]["pd"] is False
    exported = export_timings(project.p, time_unit="samples")
    row = next(csv.DictReader(io.StringIO(exported["csv"])))
    assert "SampleRate" not in row
    assert list(row) == ["Filename", "TD", "PD", "TL-A", "TL-B", "PL-A", "PL-B"]
    again = preview_import(
        project.p, exported["csv"].encode(), "csv", overwrite=True, time_unit="samples"
    )
    assert again["ready_count"] == 1
    assert again["rows"][0]["markers_sec"]["TrackDrop"] == 1 / 48000
    assert [row[k] for k in ("TD", "PD", "TL-A", "TL-B", "PL-A", "PL-B")] == [
        "1",
        "",
        "96001",
        "336002",
        "",
        "",
    ]


def test_explicit_sample_mode_without_rate_column(project):
    result = preview_import(
        project.p,
        b"Filename,TL-A,TL-B\nArtist - Song.wav,96001,336002\n",
        "csv",
        time_unit="samples",
    )
    assert result["ready_count"] == 1
    assert result["rows"][0]["markers_sec"]["TrackLoopStart"] == 96001 / 48000


@pytest.mark.parametrize("value", ["1.5", "-1", "NaN", "Infinity", "0:01.000", "9007199254740992"])
def test_invalid_sample_positions_are_not_applied(project, value):
    raw = f"Filename,TL-A,TL-B\nArtist - Song.wav,{value},336002\n".encode()
    result = preview_import(project.p, raw, "csv", time_unit="samples")
    assert result["ready_count"] == 0
    assert not result["_proposals"]


@pytest.mark.parametrize("rate", ["44100", "96000", "true", "NaN", ""])
def test_non_48khz_table_is_rejected_even_in_default_time_mode(project, rate):
    raw = f"Filename,SampleRate,TL-A,TL-B\nArtist - Song.wav,{rate},96000,336000\n".encode()
    result = preview_import(project.p, raw, "csv")
    assert result["ready_count"] == 0
    assert "48000" in result["rows"][0]["message"]


def test_json_global_sample_units_and_native_sample_map(project):
    for data in [
        {
            "sample_rate": 48000,
            "tracks": [{"track_key": project.id, "TL-A": 96001, "TL-B": 336002}],
        },
        [
            {
                "track_key": project.id,
                "markers_samples": {"TrackLoopStart": 96001, "TrackLoopEnd": 336002},
            }
        ],
    ]:
        result = preview_import(project.p, json.dumps(data).encode(), "json")
        assert result["ready_count"] == 1
        assert result["rows"][0]["markers_sec"]["TrackLoopStart"] == 96001 / 48000


def test_units_are_part_of_apply_snapshot(project):
    args = project.args(b"Filename,TD\nArtist - Song.wav,1\n")
    args.overwrite = True
    from backend.fh_radio_studio_cli.timing_import import import_timings

    preview = import_timings(args)
    args.time_unit = "samples"
    before = project.path.read_bytes()
    with pytest.raises(CliError, match="重新预览"):
        project.apply(args, preview)
    assert project.path.read_bytes() == before


def test_xml_event_only_matching_sentinel_and_optional_assignment(project):
    raw = radio_xml()
    result = preview_import(project.p, raw, "xml", overwrite=True, confirm=True)
    assert result["ready_count"] == 1
    assert len(result["rows"]) == 1
    row = result["rows"][0]
    assert row["radio_stations"] == []
    assert row["markers_sec"]["TrackDrop"] == 1 / 48000
    assert row["markers_sec"]["PostRaceLoopStart"] is None
    assert result["_proposals"][project.id]["confirmed"]["pl"] is False
    result = preview_import(project.p, raw, "text", assign_radio=True)
    assert result["rows"][0]["radio_stations"] == ["R1"]
    assert result["source_format"] == "radio-info"


def test_xml_repeated_song_merges_radio_memberships(project):
    result = preview_import(project.p, radio_xml(second_radio=True), "xml", assign_radio=True)
    assert result["ready_count"] == 1
    assert result["rows"][0]["radio_stations"] == ["R1", "R2"]
    assert result["rows"][1]["status"] == "skipped"


def test_xml_without_event_playlist_does_not_fall_back_to_other_samples(project):
    root = ET.fromstring(radio_xml())
    station = root.find("RadioStations/RadioStation")
    station.remove(station.find("PlayList[@Type='Event']"))
    with pytest.raises(CliError, match="赛事"):
        preview_import(project.p, ET.tostring(root), "xml")


@pytest.mark.parametrize("rate", ["44100", "", "96000"])
def test_xml_rejects_missing_or_wrong_sample_rate(project, rate):
    result = preview_import(project.p, radio_xml(rate=rate), "xml")
    assert result["ready_count"] == 0
    assert "48000" in result["rows"][0]["message"]


def test_xml_marker_children_and_conflict_detection(project):
    result = preview_import(project.p, radio_xml(child_only=True), "xml")
    assert result["ready_count"] == 1
    raw = radio_xml().replace(
        b'Name="TrackLoopStart" Position="96001"', b'Name="TrackLoopStart" Position="96002"'
    )
    result = preview_import(project.p, raw, "xml")
    assert result["ready_count"] == 0
    assert "不一致" in result["rows"][0]["message"]


def test_xml_same_song_conflicting_timing_is_not_silently_chosen(project):
    root = ET.fromstring(radio_xml(second_radio=True))
    sample = root.findall("RadioStations/RadioStation")[1].find("SampleList/Sample")
    sample.set("TrackLoopStart", "100000")
    sample.find("Marker[@Name='TrackLoopStart']").set("Position", "100000")
    result = preview_import(project.p, ET.tostring(root), "xml", assign_radio=True)
    assert result["ready_count"] == 0
    assert not result["_proposals"]


def test_xml_unmatched_songs_remain_visible_and_no_generic_xml_is_accepted(project):
    result = preview_import(
        project.p, radio_xml().replace(b'DisplayName="Song"', b'DisplayName="Missing"'), "xml"
    )
    assert result["ready_count"] == 0
    assert "Missing" in result["rows"][0]["title"]
    with pytest.raises(CliError, match="RadioInfo"):
        parse_rows(b"<document />", "xml")
    with pytest.raises(CliError, match="DTD"):
        parse_rows(b'<!DOCTYPE Radio [<!ENTITY x "x">]><Radio/>', "xml")


def test_three_conflicting_rows_cannot_revive_rejected_proposal(project):
    raw = (
        b"Filename,TL-A,TL-B\nArtist - Song.wav,2,7\nArtist - Song.wav,3,8\nArtist - Song.wav,2,7\n"
    )
    result = preview_import(project.p, raw, "csv")
    assert result["ready_count"] == 0
    assert not result["_proposals"]


def test_export_cannot_select_another_sample_rate(project):
    with pytest.raises(ValueError, match="48000"):
        export_timings(project.p, time_unit="samples", sample_rate=44100)
