import xml.etree.ElementTree as ET
from test.test_timing_samples_xml import project, radio_xml

import pytest

from backend.fh_radio_studio_cli.common import CliError
from backend.fh_radio_studio_cli.radio_timing_import import radio_assignment_layouts
from backend.fh_radio_studio_cli.timing_import import preview_import


def original_22():
    root = ET.fromstring(radio_xml())
    station = root.find("RadioStations/RadioStation")
    station.set("Number", "9")
    samples = station.find("SampleList")
    template = samples.find("Sample")
    for sample in list(samples):
        samples.remove(sample)
    event = station.find("PlayList[@Type='Event']")
    event.clear()
    event.set("Type", "Event")
    for i in range(22):
        sample = ET.fromstring(ET.tostring(template))
        sample.set("SoundName", f"original-{i}")
        sample.set("DisplayName", f"Original {i}")
        samples.append(sample)
        ET.SubElement(event, "Entry", Name=f"original-{i}")
    return ET.tostring(root)


def baseline(project, raw):
    path = project.p / "backups/baseline-current/media/audio/RadioInfo_CN.xml"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)
    return path


def test_baseline_without_local_songs_can_restore_22_without_changing_timepoints(project):
    raw = original_22()
    baseline(project, raw)
    result = preview_import(project.p, raw, "xml", assign_radio=True)
    assert result["radio_layouts"] == [
        {
            "radio_code": "R9",
            "playlist_type": "Event",
            "count": 22,
            "mode": "builtin",
            "message": "恢复原版 22 首（缺少完整本地源文件）",
            "sources": [],
        }
    ]
    assert result["ready_count"] == 0
    assert all(row["status"] == "builtin" for row in result["rows"])
    before = project.path.read_bytes()
    args = project.args(raw, assign_radio=True)
    args.format = "xml"
    applied = project.apply(args, result)
    assert applied["applied_count"] == 0
    assert project.path.read_bytes() == before


def test_changed_titles_with_same_bank_slot_names_are_not_misidentified_as_original(project):
    raw = original_22()
    baseline(project, raw)
    changed = raw.replace(b'DisplayName="Original 0"', b'DisplayName="Custom replacement"')
    result = preview_import(project.p, changed, "xml", assign_radio=True)
    assert result["radio_layouts"][0]["mode"] == "blocked"
    assert result["radio_layouts"][0]["count"] == 22


def test_baseline_change_after_preview_rejects_apply(project):
    raw = original_22()
    path = baseline(project, raw)
    result = preview_import(project.p, raw, "xml", assign_radio=True)
    path.write_bytes(raw.replace(b'DisplayName="Original 0"', b'DisplayName="Changed"'))
    args = project.args(raw, assign_radio=True)
    args.format = "xml"
    with pytest.raises(CliError, match="重新预览"):
        project.apply(args, result)


def test_custom_layout_follows_event_order_and_blocks_partial_matching(project):
    root = ET.fromstring(radio_xml())
    station = root.find("RadioStations/RadioStation")
    samples = station.find("SampleList")
    sample = ET.fromstring(ET.tostring(samples.find("Sample")))
    sample.set("SoundName", "second")
    sample.set("DisplayName", "Second")
    samples.append(sample)
    playlist = station.find("PlayList[@Type='Event']")
    playlist.insert(0, ET.Element("Entry", Name="second"))
    raw = ET.tostring(root)
    matched = [
        {
            "radio_code": "R1",
            "sound_name": "event-song",
            "source": "C:/first.wav",
            "status": "ready",
        },
        {
            "radio_code": "R1",
            "sound_name": "second",
            "source": "C:/second.wav",
            "status": "skipped",
        },
    ]
    layouts = radio_assignment_layouts(project.p, raw, matched)
    assert layouts[0]["sources"] == ["C:/second.wav", "C:/first.wav"]
    assert radio_assignment_layouts(project.p, raw, matched[:1])[0]["mode"] == "blocked"


def test_matching_local_sources_stay_editable_even_when_xml_matches_baseline(project):
    raw = radio_xml()
    baseline(project, raw)
    result = preview_import(project.p, raw, "xml", assign_radio=True)
    layout = result["radio_layouts"][0]
    assert layout["mode"] == "custom"
    assert len(layout["sources"]) == 1
    assert result["rows"][0]["source_matched"] is True


def test_invalid_timing_does_not_turn_a_reliably_matched_song_into_builtin(project):
    raw = radio_xml(marker="99999999")
    baseline(project, raw)
    result = preview_import(project.p, raw, "xml", assign_radio=True, overwrite=True)
    assert result["rows"][0]["status"] == "error"
    assert result["rows"][0]["source_matched"] is True
    assert result["radio_layouts"][0]["mode"] == "custom"
    assert result["_proposals"] == {}
