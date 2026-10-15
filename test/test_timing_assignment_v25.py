import csv
import io
import json
import unittest
from test import test_timing_import as fixture

from backend.fh_radio_studio_cli.common import CliError
from backend.fh_radio_studio_cli.timing_import import export_timings, import_timings, preview_import


class TimingAssignmentTests(unittest.TestCase):
    setUp = fixture.TimingImportTests.setUp
    args = fixture.TimingImportTests.args
    apply = fixture.TimingImportTests.apply

    def test_partial_loop_is_allowed_but_never_confirmed(self):
        a = self.args(b"Filename,TL1,TL2,PL1,PL2\nArtist - Song.wav,2,,,7")
        a.confirm = True
        preview = import_timings(a)
        self.assertEqual(preview["ready_count"], 1)
        self.assertIsNone(preview["rows"][0]["markers_sec"]["TrackLoopEnd"])
        self.apply(a, preview)
        saved = json.loads(self.path.read_text())["tracks"][0]
        self.assertEqual(saved["markers_sec"]["TrackLoopStart"], 2)
        self.assertNotIn("TrackLoopEnd", saved["markers_sec"])
        self.assertFalse(saved["confirmed"]["tl"])
        self.assertFalse(saved["confirmed"]["pl"])
        self.assertTrue(saved["confirmed"]["td"])

    def test_explicit_blanks_clear_only_with_overwrite(self):
        raw = b"Filename,TD,PD,TL1,TL2,PL1,PL2\nArtist - Song.wav,,,,,,"
        self.assertEqual(preview_import(self.p, raw, "csv")["ready_count"], 0)
        a = self.args(raw)
        a.overwrite = True
        a.confirm = True
        preview = import_timings(a)
        self.apply(a, preview)
        saved = json.loads(self.path.read_text())["tracks"][0]
        self.assertFalse(saved["markers_sec"])
        self.assertFalse(any(saved["confirmed"].values()))

    def test_optional_radio_validates_only_when_enabled(self):
        raw = b"Filename,Radio_station,TL1\nArtist - Song.wav,R1;3;R1,2"
        result = preview_import(self.p, raw, "csv", assign_radio=True)
        self.assertEqual(result["rows"][0]["radio_stations"], ["R1", "R3"])
        self.assertTrue(result["rows"][0]["source"].endswith("Artist - Song.wav"))
        bad = raw.replace(b"R1;3;R1", b"R10")
        self.assertEqual(preview_import(self.p, bad, "csv", assign_radio=True)["ready_count"], 0)
        self.assertEqual(preview_import(self.p, bad, "csv")["ready_count"], 1)

    def test_radio_flag_change_requires_preview_and_station_only_rows_work(self):
        a = self.args(b"Filename,Radio_station\nArtist - Song.wav,2")
        a.assign_radio = True
        preview = import_timings(a)
        self.assertEqual(preview["ready_count"], 1)
        a.assign_radio = False
        with self.assertRaises(CliError):
            self.apply(a, preview)

    def test_conflicting_radio_duplicate_rejects_song(self):
        raw = b"Filename,Radio_station,TL1\nArtist - Song.wav,R1,2\nArtist - Song.wav,R2,2"
        result = preview_import(self.p, raw, "csv", assign_radio=True)
        self.assertFalse(result["_proposals"])
        self.assertEqual(result["ready_count"], 0)

    def test_export_includes_empty_songs_and_optional_saved_radio(self):
        self.path.write_text('{"schema_version":2,"tracks":[]}', encoding="utf-8")
        path = self.p / ".fh-radio-studio/playlist_plan.json"
        path.write_text(
            json.dumps(
                {
                    "schema_version": 2,
                    "assignments": [
                        {
                            "track_key": self.id,
                            "radio_code": "R2",
                            "playlist_type": "Event",
                            "slot": 1,
                        },
                        {
                            "track_key": self.id,
                            "radio_code": "R2",
                            "playlist_type": "FreeRoam",
                            "slot": 1,
                        },
                        {"track_key": self.id, "radio_code": "R1", "slot": 1},
                    ],
                }
            ),
            encoding="utf-8",
        )
        original = self.path.read_bytes()
        result = export_timings(self.p, include_radio=True)
        rows = list(csv.reader(io.StringIO(result["csv"])))
        self.assertEqual(
            rows[0], ["Filename", "Radio_station", "TD", "PD", "TL-A", "TL-B", "PL-A", "PL-B"]
        )
        self.assertEqual(rows[1][1:], ["R1;R2", "", "", "", "", "", ""])
        preview = preview_import(
            self.p, result["csv"].encode(), "csv", confirm=True, assign_radio=True
        )
        self.assertEqual(preview["ready_count"], 1)
        self.assertFalse(preview["rows"][0]["complete"])
        self.assertEqual(self.path.read_bytes(), original)

    def test_letter_columns_and_legacy_numeric_columns_both_import(self):
        numeric = b"Filename,TD,PD,TL1,TL2,PL1,PL2\nArtist - Song.wav,1,8,2,7,2,7"
        letter = numeric.replace(b"TL1,TL2,PL1,PL2", b"TL-A,TL-B,PL-A,PL-B")
        a = preview_import(self.p, numeric, "csv", overwrite=True, confirm=True)
        b = preview_import(self.p, letter, "csv", overwrite=True, confirm=True)
        self.assertEqual(a["rows"][0]["markers_sec"], b["rows"][0]["markers_sec"])
        self.assertEqual(b["ready_count"], 1)
        self.assertTrue(b["rows"][0]["complete"])
