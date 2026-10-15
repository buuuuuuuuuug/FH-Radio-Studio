import csv
import io
import json
import shutil
import unittest
from test import test_timing_import as fixture

from backend.fh_radio_studio_cli.common import CliError
from backend.fh_radio_studio_cli.project_refs import project_ref_for_path, track_key_for_source_ref
from backend.fh_radio_studio_cli.timing_import import export_timings, import_timings, preview_import


class TimingTransferTests(unittest.TestCase):
    setUp = fixture.TimingImportTests.setUp
    args = fixture.TimingImportTests.args
    apply = fixture.TimingImportTests.apply

    def test_split_columns_and_identity_modes(self):
        for mode, identity in [
            ("filename", "Artist - Song.wav"),
            ("title", "Song"),
            ("title-artist", "Song_Artist"),
            ("artist-title", "Artist_Song"),
            ("auto", "Song - Artist"),
        ]:
            data = (
                f"Filename,TD,PD,TL1,TL2,PL1,PL2\n{identity},1,8,2.125,7.750,2.125,7.750\n".encode()
            )
            result = preview_import(self.p, data, "csv", overwrite=True, match_mode=mode)
            self.assertEqual(result["ready_count"], 1, (mode, result["rows"]))
            self.assertEqual(result["rows"][0]["markers_sec"]["TrackLoopStart"], 2.125)
        wrong = preview_import(self.p, b"title,artist,TL1,TL2\nSong,Wrong,2,7", "csv")
        self.assertEqual(wrong["ready_count"], 0)

    def test_export_roundtrip_is_read_only_and_separates_points(self):
        doc = json.loads(self.path.read_text())
        doc["tracks"][0]["markers_sec"].update(TrackLoopStart=2.125, TrackLoopEnd=7.750)
        self.path.write_text(json.dumps(doc), encoding="utf-8")
        before = self.path.read_bytes()
        result = export_timings(self.p)
        rows = list(csv.reader(io.StringIO(result["csv"])))
        self.assertEqual(rows[0], ["Filename", "TD", "PD", "TL-A", "TL-B", "PL-A", "PL-B"])
        self.assertEqual(rows[1][-2:], ["", ""])
        self.assertEqual(self.path.read_bytes(), before)
        raw = ("\ufeff" + result["csv"]).encode("utf-8")
        parsed = preview_import(self.p, raw, "csv", overwrite=True)
        self.assertEqual(parsed["ready_count"], 1)
        self.assertEqual(parsed["rows"][0]["markers_sec"]["TrackLoopEnd"], 7.75)
        result = export_timings(self.p, "title-artist")
        self.assertEqual(list(csv.reader(io.StringIO(result["csv"])))[1][0], "Song_Artist")

    def test_ambiguous_normalized_identity_is_rejected(self):
        target = self.p / "sources/other.wav"
        shutil.copyfile(self.p / "sources/Artist - Song.wav", target)
        doc = json.loads(self.meta.read_text())
        other = dict(doc["tracks"][0])
        other["source_ref"] = project_ref_for_path(self.p, target)
        other["track_key"] = track_key_for_source_ref(other["source_ref"])
        doc["tracks"].append(other)
        self.meta.write_text(json.dumps(doc), encoding="utf-8")
        r = preview_import(self.p, b"Filename,TL1,TL2\nSong_Artist,2,7", "csv")
        self.assertEqual(r["ready_count"], 0)
        self.assertIn("多首", r["rows"][0]["message"])
        r = preview_import(self.p, b"Filename,TL1,TL2\nArtist - Song.wav,2,7", "csv")
        self.assertEqual(r["ready_count"], 1)

    def test_changed_match_mode_requires_new_preview(self):
        a = self.args(b"Filename,TL1,TL2\nArtist - Song.wav,2,7")
        p = import_timings(a)
        a.apply = True
        a.expected_snapshot = p["snapshot_hash"]
        a.expected_input = p["input_hash"]
        a.match_mode = "title"
        before = self.path.read_bytes()
        with self.assertRaises(CliError):
            import_timings(a)
        self.assertEqual(self.path.read_bytes(), before)
