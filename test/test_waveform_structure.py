import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path
from unittest.mock import patch

import numpy as np
import soundfile as sf

from backend.fh_radio_studio_cli.waveform import cmd_waveform_audio, waveform_payload


def test_waveform_does_not_generate_unreliable_sections_or_timepoints(tmp_path):
    sr = 8000
    t = np.arange(sr * 52, dtype=np.float32) / sr
    amplitude = np.where(t < 15, 0.03, np.where(t < 36, 0.6, 0.12))
    audio = np.sin(2 * np.pi * 220 * t) * amplitude
    source = tmp_path / "structure.wav"
    sf.write(source, audio, sr)
    result = waveform_payload(source, bins=128)
    assert result["segments"] == []
    assert len(result["waveform"]["bins"]) == 128
    assert result["markers"] == {}
    assert result["point_candidates"] == {}
    assert result["loop_candidates"] == {}
    assert result["beats"] == []


def test_waveform_structure_survives_silence_and_short_audio(tmp_path):
    source = tmp_path / "short.wav"
    sf.write(source, np.zeros(800), 8000)
    result = waveform_payload(source, bins=32)
    assert result["segments"] == []
    assert all(b["peak"] == 0 for b in result["waveform"]["bins"])


def test_old_section_cache_is_replaced_and_waveform_result_is_cached(tmp_path):
    source = tmp_path / "source.wav"
    sf.write(source, np.zeros(8000), 8000)
    cache = tmp_path / "cache"
    cache.mkdir()
    stat = source.stat()
    legacy = hashlib.sha256(
        f"v2:{source.resolve()}:{stat.st_size}:{stat.st_mtime_ns}:64".encode()
    ).hexdigest()
    (cache / f"{legacy}.json").write_text(
        json.dumps(
            {"waveform": {"bins": []}, "segments": [{"start": 0, "end": 1, "label": "section_01"}]}
        ),
        encoding="utf-8",
    )
    args = argparse.Namespace(input=str(source), bins=64, cache_dir=str(cache), ffmpeg=None)
    with contextlib.redirect_stdout(io.StringIO()) as stream:
        assert cmd_waveform_audio(args) == 0
    assert json.loads(stream.getvalue())["segments"] == []
    with patch(
        "backend.fh_radio_studio_cli.waveform.read_audio_for_analysis",
        side_effect=AssertionError("unexpected decode"),
    ):
        with contextlib.redirect_stdout(io.StringIO()) as stream:
            assert cmd_waveform_audio(args) == 0
    assert json.loads(stream.getvalue())["segments"] == []
