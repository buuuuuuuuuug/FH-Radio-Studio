import ctypes
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np

from backend.fh_radio_studio_cli.ai_timepoints import cli
from backend.fh_radio_studio_cli.ai_timepoints.providers import baseline_mir
from backend.fh_radio_studio_cli.ai_timepoints.schema import ProviderStatus
from backend.fh_radio_studio_cli.seamless_loop import NativeLoopPoint


class SeamlessIntegrationTests(unittest.TestCase):
    def test_native_abi_matches_upstream_int64_struct(self):
        self.assertEqual(ctypes.sizeof(NativeLoopPoint), 32)
        self.assertEqual(NativeLoopPoint.loopEnd.offset, 8)
        self.assertEqual(NativeLoopPoint.score.offset, 24)

    def test_baseline_uses_native_loops_and_never_runs_legacy_search(self):
        loops = {
            k: [{"start": 12.125, "end": 90.875, "score": 0.9, "bars": 0, "why": "SLM"}]
            for k in ("tl", "pl")
        }
        data = np.sin(np.arange(120000, dtype=np.float32) * 0.2).reshape(-1, 1)
        with patch.object(
            baseline_mir, "read_audio_for_analysis", return_value=(data, 1000, "mock")
        ):
            with patch.object(
                baseline_mir,
                "_best_track_loop_time",
                side_effect=AssertionError("legacy TL called"),
            ):
                with patch.object(
                    baseline_mir,
                    "_best_post_loop_time",
                    side_effect=AssertionError("legacy PL called"),
                ):
                    with patch.object(
                        baseline_mir,
                        "_track_loop_candidates",
                        side_effect=AssertionError("legacy candidates called"),
                    ):
                        result = baseline_mir.analyze(
                            Path("audio.wav"),
                            bins=32,
                            bpm=120,
                            max_beats=800,
                            ffmpeg=None,
                            loop_override=loops,
                        )
        self.assertEqual(result["candidates"]["tl"], loops["tl"])
        self.assertEqual(result["markers"]["TrackLoopStart"], 12.125)
        self.assertTrue(result["candidates"]["td"])
        self.assertTrue(result["candidates"]["pd"])

    def test_heavy_pipeline_keeps_native_loops_exact_after_ai_constraints(self):
        source = Path(__file__)
        native = {
            k: [{"start": 0.123456, "end": 100.123456, "score": 0.98, "bars": 0, "why": "native"}]
            for k in ("tl", "pl")
        }
        baseline = {
            "status": ProviderStatus("baseline_mir", "ok"),
            "candidates": {
                **native,
                "td": [{"t": 10, "score": 0.9, "why": "point"}],
                "pd": [{"t": 90, "score": 0.9, "why": "point"}],
            },
            "grid": {"beats": [0, 0.5, 1], "downbeats": [0], "bars": [0]},
            "segments": [],
            "duration_sec": 120,
            "sample_rate": 48000,
            "channels": 2,
            "samples": 5760000,
            "decoder": "mock",
            "peak_dbfs": -1,
            "rms_dbfs": -12,
            "bpm": 120,
            "bpm_confidence": 0.9,
            "markers": {},
            "waveform": {},
            "warnings": [],
        }
        args = SimpleNamespace(
            input=str(source),
            profile="local-heavy",
            ffmpeg=None,
            model_dir=None,
            max_beats=800,
            bins=32,
            bpm=120,
            loop_engine="seamless",
            slm_dll="loopfinder.dll",
            loop_cache_dir=None,
        )

        def constraints(c, *unused, **kwargs):
            # These are the old AI rules: they must never receive native loops.
            self.assertEqual(c["tl"], [])
            self.assertEqual(c["pl"], [])
            return c

        with patch.object(
            cli, "_check_provider", side_effect=lambda name, md: ProviderStatus(name, "missing")
        ):
            with patch.object(cli, "analyze_seamless", return_value={"candidates": native}):
                with patch.object(cli.baseline_mir, "analyze", return_value=baseline) as analyze:
                    with patch.object(cli, "_apply_timing_constraints", side_effect=constraints):
                        result = cli.build_analysis_payload(args)
        self.assertEqual(result["loop_engine"], "seamless-loop-music")
        self.assertEqual(result["candidates"]["tl"], native["tl"])
        self.assertEqual(analyze.call_args.kwargs["loop_override"], native)


if __name__ == "__main__":
    unittest.main()
