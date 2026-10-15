import argparse
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
import soundfile as sf

from backend.fh_radio_studio_cli.import_audio import cmd_import_audio
from backend.fh_radio_studio_cli.waveform import cmd_waveform_audio, waveform_payload


class WaveformAndDuplicatesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_waveform_is_real_and_cache_is_invalidated_when_source_changes(self):
        source = self.root / "audio.wav"
        samples = np.concatenate([np.zeros(24000), np.ones(24000) * 0.4])
        sf.write(source, np.column_stack([samples, -samples]), 48000)
        args = argparse.Namespace(
            input=str(source), bins=64, cache_dir=str(self.root / "cache"), ffmpeg=None
        )
        with contextlib.redirect_stdout(io.StringIO()) as out:
            cmd_waveform_audio(args)
        data = json.loads(out.getvalue())
        self.assertEqual(data["samples"], 48000)
        self.assertEqual(data["waveform"]["bins"][0]["peak"], 0)
        self.assertGreater(data["waveform"]["bins"][-1]["peak"], 0.3)
        self.assertEqual(data["point_candidates"], {})
        with patch(
            "backend.fh_radio_studio_cli.waveform.read_audio_for_analysis",
            side_effect=AssertionError("cache miss"),
        ):
            with contextlib.redirect_stdout(io.StringIO()):
                cmd_waveform_audio(args)
        sf.write(source, np.ones((96000, 2)) * 0.1, 48000)
        with contextlib.redirect_stdout(io.StringIO()) as out:
            cmd_waveform_audio(args)
        self.assertEqual(json.loads(out.getvalue())["samples"], 96000)

    def test_renamed_identical_import_is_skipped_and_does_not_create_extra_track(self):
        project = self.root / "project"
        sources = project / "sources"
        sources.mkdir(parents=True)
        existing = sources / "old.wav"
        sf.write(existing, np.zeros((4800, 2)), 48000)
        incoming = self.root / "renamed.wav"
        incoming.write_bytes(existing.read_bytes())
        args = argparse.Namespace(
            project_dir=str(project),
            target_folder="sources",
            inputs=[str(incoming)],
            ffmpeg=None,
            title=None,
            artist=None,
            album=None,
            cover_image=None,
            json=True,
        )
        with contextlib.redirect_stdout(io.StringIO()) as out:
            cmd_import_audio(args)
        data = json.loads(out.getvalue())
        self.assertEqual(data["imported"], [])
        self.assertEqual(len(data["duplicates_skipped"]), 1)
        self.assertEqual(len(list(sources.glob("*.wav"))), 1)

    def test_transcoded_duplicate_index_skips_reimport_but_not_replaced_destination(self):
        incoming = self.root / "input.wav"
        sf.write(incoming, np.zeros((4410, 2)), 44100)
        project = self.root / "transcoded_project"
        args = argparse.Namespace(
            project_dir=str(project),
            target_folder="sources",
            inputs=[str(incoming)],
            ffmpeg=None,
            title=None,
            artist=None,
            album=None,
            cover_image=None,
            json=True,
        )

        def run_import():
            with patch(
                "backend.fh_radio_studio_cli.import_audio._try_analyze_import_loudness",
                return_value={"status": "skipped"},
            ):
                with contextlib.redirect_stdout(io.StringIO()) as out:
                    cmd_import_audio(args)
            return json.loads(out.getvalue())

        first = run_import()
        self.assertEqual(len(first["imported"]), 1)
        destination = Path(first["imported"][0]["path"])
        self.assertEqual(sf.info(destination).samplerate, 48000)
        second = run_import()
        self.assertEqual(second["imported"], [])
        self.assertEqual(len(second["duplicates_skipped"]), 1)
        sf.write(destination, np.ones((4800, 2)) * 0.25, 48000)
        third = run_import()
        self.assertEqual(len(third["imported"]), 1)
        self.assertEqual(third["duplicates_skipped"], [])
        self.assertEqual(len(list((project / "sources").glob("*.wav"))), 2)


if __name__ == "__main__":
    unittest.main()
