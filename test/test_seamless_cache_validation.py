from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
from unittest.mock import patch

import pytest

from backend.fh_radio_studio_cli import seamless_loop


def valid_result(source, dll_hash):
    point = {
        "start": 1.0,
        "end": 5.0,
        "score": 0.9,
        "evidence": {
            "start_sample": 48000,
            "end_sample": 240000,
            "sample_rate": 48000,
            "native_score": 0.9,
            "note_difference": 0.1,
            "loudness_difference": 0.2,
        },
    }
    return {
        "schema_version": 1,
        "source": str(source),
        "loop_engine": "seamless-loop-music",
        "duration_sec": 10.0,
        "sample_rate": 48000,
        "samples": 480000,
        "native_library_sha256": dll_hash,
        "candidates": {"tl": [point], "pl": [copy.deepcopy(point)]},
    }


@pytest.mark.parametrize(
    "malformed",
    [
        [],
        None,
        {"candidates": [1]},
        "wrong-end",
        "nan-score",
        "missing-evidence",
        "wrong-frame",
        "oversized-int",
        "bad-duration",
    ],
)
def test_invalid_native_cache_is_ignored_and_analysis_restarts(tmp_path, malformed):
    source, dll = tmp_path / "song.wav", tmp_path / "loopfinder.dll"
    source.write_bytes(b"audio")
    dll.write_bytes(b"library")
    dll_hash = hashlib.sha256(dll.read_bytes()).hexdigest()
    stat = source.stat()
    key = hashlib.sha256(
        f"slm-v1:{source}:{stat.st_size}:{stat.st_mtime_ns}:{dll_hash}:10".encode()
    ).hexdigest()
    cache = tmp_path / f"slm-{key}.json"
    result = valid_result(source, dll_hash)
    if malformed == "wrong-end":
        result["candidates"]["tl"][0]["end"] = 11
    elif malformed == "nan-score":
        result["candidates"]["pl"][0]["score"] = float("nan")
    elif malformed == "missing-evidence":
        result["candidates"]["tl"][0].pop("evidence")
    elif malformed == "wrong-frame":
        result["candidates"]["tl"][0]["evidence"]["end_sample"] = 250000
    elif malformed == "oversized-int":
        result["candidates"]["tl"][0]["score"] = 10**1000
    elif malformed == "bad-duration":
        result["duration_sec"] = 100
    else:
        result = malformed
    cache.write_text(json.dumps(result), encoding="utf-8")
    with patch.object(
        seamless_loop, "read_audio_for_analysis", side_effect=RuntimeError("analysis restarted")
    ):
        with pytest.raises(RuntimeError, match="analysis restarted"):
            seamless_loop.analyze_seamless(source, dll, cache_dir=tmp_path)


def test_valid_native_cache_skips_decoder_and_library(tmp_path):
    source, dll = tmp_path / "song.wav", tmp_path / "loopfinder.dll"
    source.write_bytes(b"audio")
    dll.write_bytes(b"library")
    dll_hash = hashlib.sha256(dll.read_bytes()).hexdigest()
    stat = source.stat()
    key = hashlib.sha256(
        f"slm-v1:{source}:{stat.st_size}:{stat.st_mtime_ns}:{dll_hash}:10".encode()
    ).hexdigest()
    result = valid_result(source, dll_hash)
    (tmp_path / f"slm-{key}.json").write_text(json.dumps(result), encoding="utf-8")
    with patch.object(
        seamless_loop, "read_audio_for_analysis", side_effect=AssertionError("decoded")
    ):
        with patch.object(
            seamless_loop.ctypes, "CDLL", side_effect=AssertionError("library loaded")
        ):
            cached = seamless_loop.analyze_seamless(source, dll, cache_dir=tmp_path)
    assert cached["cached"] is True
    assert cached["candidates"] == result["candidates"]
