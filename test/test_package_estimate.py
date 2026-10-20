import argparse
import json
import math
import tempfile
import unittest
import wave
from pathlib import Path
from test.test_bank_expansion import bank
from types import SimpleNamespace
from unittest.mock import patch

from backend.fh_radio_studio_cli.cli import build_parser
from backend.fh_radio_studio_cli.common import CliError
from backend.fh_radio_studio_cli.fsb5 import splice_fsb5_into_bank
from backend.fh_radio_studio_cli.package_estimate import (
    estimate_package,
    nominal_stereo_bps,
    size_curve,
)
from backend.fh_radio_studio_cli.project_refs import project_ref_for_path, track_key_for_source_ref


class PackageEstimateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name)
        self.baseline = self.project / "backups/baseline-current"
        audio = self.baseline / "media/audio"
        (audio / "FMODBanks").mkdir(parents=True)
        (audio / "RadioInfo_EN.xml").write_text(
            '<Radio><RadioStations><RadioStation Number="1" Name="Horizon Pulse"><Banks><Bank Name="R1_Tracks_CU1"/></Banks></RadioStation></RadioStations></Radio>',
            encoding="utf-8",
        )
        (audio / "FMODBanks/R1_Tracks_CU1.assets.bank").write_bytes(bank(["A", "B", "C", "D"]))
        self.manifest = self.baseline / "baseline_manifest.json"
        self.manifest.write_text(
            json.dumps(
                {
                    "files": [
                        {
                            "install_relative_path": "media/Stripped/StringTables/CHS.zip",
                            "size": 1234,
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        (self.project / "sources").mkdir()
        self.source = self.project / "sources/a.wav"
        with wave.open(str(self.source), "wb") as f:
            f.setnchannels(2)
            f.setsampwidth(2)
            f.setframerate(48000)
            f.writeframes(b"\0" * (4 * 48000))
        self.plan = self.project / "plan.json"
        self.write_plan([self.source])
        self.args = argparse.Namespace(
            project_dir=str(self.project),
            baseline_manifest=str(self.manifest),
            playlist_plan=str(self.plan),
            playlist_from_package=None,
            expand_slots=False,
        )

    def write_plan(self, sources):
        entries = [
            {
                "source_ref": project_ref_for_path(self.project, source),
                "track_key": track_key_for_source_ref(project_ref_for_path(self.project, source)),
            }
            for source in sources
        ]
        (self.project / ".fh-radio-studio").mkdir(exist_ok=True)
        (self.project / ".fh-radio-studio/track_metadata.json").write_text(
            json.dumps({"schema_version": 2, "tracks": entries}), encoding="utf-8"
        )
        self.plan.write_text(
            json.dumps(
                {
                    "assignments": [
                        {
                            "track_key": entries[i]["track_key"],
                            "radio_code": "R1",
                            "playlist_type": scene,
                            "slot": i + 1,
                        }
                        for scene in ["FreeRoam", "Event"]
                        for i, source in enumerate(sources)
                    ]
                }
            ),
            encoding="utf-8",
        )

    def test_scene_dedup_fills_physical_slots_and_includes_fixed_files_without_writes(self):
        before = {str(p): p.read_bytes() for p in self.project.rglob("*") if p.is_file()}
        result = estimate_package(self.args)
        rebuilt = next(row for row in result["files"] if row["rebuilt"])
        self.assertEqual(rebuilt["slots"], 4)
        self.assertAlmostEqual(rebuilt["duration_seconds"], 4)
        self.assertEqual(len(result["files"]), 2)
        self.assertEqual(result["total_sizes"][49], rebuilt["sizes"][49] + 1234)
        self.assertEqual(
            before, {str(p): p.read_bytes() for p in self.project.rglob("*") if p.is_file()}
        )

    def test_invalid_cached_duration_or_timestamp_falls_back_to_source_metadata(self):
        key = track_key_for_source_ref(project_ref_for_path(self.project, self.source))
        for duration, mtime in [
            (float("nan"), self.source.stat().st_mtime * 1000),
            (float("inf"), self.source.stat().st_mtime * 1000),
            (True, self.source.stat().st_mtime * 1000),
            (30, "invalid timestamp"),
            (30, None),
        ]:
            with self.subTest(duration=duration, mtime=mtime):
                entry = {
                    "size": self.source.stat().st_size,
                    "mtime_ms": mtime,
                    "duration_sec": duration,
                }
                with patch(
                    "backend.fh_radio_studio_cli.package_estimate._load_cache_entries",
                    return_value={key: entry},
                ):
                    result = estimate_package(self.args)
                rebuilt = next(row for row in result["files"] if row["rebuilt"])
                self.assertEqual(rebuilt["duration_seconds"], 4.0)

    def test_expansion_adds_slots_and_quality_curve_is_monotonic(self):
        sources = [self.source]
        for i in range(5):
            other = self.project / "sources" / f"{i}.wav"
            other.write_bytes(self.source.read_bytes())
            sources.append(other)
        self.write_plan(sources)
        self.args.expand_slots = True
        row = next(row for row in estimate_package(self.args)["files"] if row["rebuilt"])
        self.assertEqual(row["slots"], 6)
        self.assertAlmostEqual(row["duration_seconds"], 6)
        self.assertTrue(all(a < b for a, b in zip(row["sizes"], row["sizes"][1:])))

    def test_long_bank_exceeds_limit_at_high_quality(self):
        sizes = size_curve(40000, 1000, 200)
        self.assertLess(sizes[0], 2**31)
        self.assertGreater(sizes[-1], 2**31)

    def test_unreadable_duration_is_not_presented_as_zero(self):
        self.source.write_bytes(b"bad")
        with self.assertRaises(CliError):
            estimate_package(self.args)

    def test_quality_default_and_bounds(self):
        args = build_parser().parse_args(["build-package", "--out-dir", "out", "--radio", "1"])
        self.assertEqual(args.quality, 50)
        for q in [0, 101]:
            with self.assertRaises(CliError):
                nominal_stereo_bps(q)

    def test_actual_oversized_bank_is_rejected_before_write(self):
        class Huge(bytes):
            def __len__(self):
                return 2**31

        out = self.project / "should-not-exist.bank"
        with (
            patch.object(Path, "read_bytes", return_value=Huge(b"")),
            patch(
                "backend.fh_radio_studio_cli.fsb5.parse_fsb5_bytes",
                return_value=SimpleNamespace(bank_offset=0, total_size=0),
            ),
        ):
            with self.assertRaises(CliError):
                splice_fsb5_into_bank(self.source, b"x", out)
        self.assertFalse(out.exists())


if __name__ == "__main__":
    unittest.main()
