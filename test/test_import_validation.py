import contextlib
import io
import unittest
from test import test_timing_import as fixture
from unittest.mock import patch

from backend.fh_radio_studio_cli.common import CliError
from backend.fh_radio_studio_cli.timing_import import cmd_import_timings, import_timings, parse_rows


class ImportValidationTests(unittest.TestCase):
    setUp = fixture.TimingImportTests.setUp
    args = fixture.TimingImportTests.args

    def test_duplicate_alias_headers_cannot_silently_overwrite_markers(self):
        for headers in [
            "Filename,TD,TrackDrop",
            "Filename,TL-A,TL1",
            "Filename,Radio_station,RadioStation",
        ]:
            with self.subTest(headers=headers), self.assertRaises(CliError):
                parse_rows((headers + "\nArtist - Song.wav,1,2").encode(), "csv")

    def test_oversized_input_is_rejected_before_parsing_or_writing(self):
        args = self.args(b"x" * 8_000_001)
        before = self.path.read_bytes()
        with self.assertRaises(CliError):
            import_timings(args)
        self.assertEqual(self.path.read_bytes(), before)

    def test_malformed_workbook_indices_report_a_cli_error(self):
        args = self.args(b"unused")
        with patch(
            "backend.fh_radio_studio_cli.timing_import.import_timings",
            side_effect=IndexError("bad shared string"),
        ):
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(CliError):
                cmd_import_timings(args)
