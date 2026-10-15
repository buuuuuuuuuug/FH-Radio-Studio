"""Experimental SeamlessLoopMusic native adapter (C API, separate CLI process).

ABI: CPUrising/seamless-loop-music loopfinder/include/loopfinder/loopfinder_api.h.
The DLL returns PCM frame indices, not interleaved channel indices.
"""

from __future__ import annotations

import ctypes
import hashlib
import json
import math
import os
import tempfile
import time
from pathlib import Path

import soundfile as sf

from .audio import read_audio_for_analysis


class NativeLoopPoint(ctypes.Structure):
    _fields_ = [
        ("loopStart", ctypes.c_int64),
        ("loopEnd", ctypes.c_int64),
        ("noteDiff", ctypes.c_float),
        ("loudnessDiff", ctypes.c_float),
        ("score", ctypes.c_float),
    ]


def _native_path(path: Path) -> bytes:
    text = str(path)
    if os.name == "nt":
        # The upstream C decoder uses fopen. A neutral WAV name and Windows
        # short path avoid Japanese/Chinese source names crossing an ANSI ABI.
        buffer = ctypes.create_unicode_buffer(32768)
        fn = ctypes.windll.kernel32.GetShortPathNameW
        fn.argtypes = [ctypes.c_wchar_p, ctypes.c_wchar_p, ctypes.c_uint32]
        fn.restype = ctypes.c_uint32
        count = fn(text, buffer, len(buffer))
        if 0 < count < len(buffer):
            text = buffer.value
        return text.encode("mbcs", errors="strict")
    return os.fsencode(text)


def analyze_seamless(
    source: Path,
    dll: Path,
    *,
    cache_dir: Path | None = None,
    ffmpeg: str | None = None,
    top_n: int = 10,
    force: bool = False,
):
    source, dll = source.resolve(), dll.resolve()
    if not source.is_file():
        raise ValueError(f"Audio source missing: {source}")
    if not dll.is_file():
        raise ValueError(f"SeamlessLoopMusic native library missing: {dll}")
    top_n = max(1, min(10, top_n))
    stat = source.stat()
    dll_hash = hashlib.sha256(dll.read_bytes()).hexdigest()
    key = hashlib.sha256(
        f"slm-v1:{source}:{stat.st_size}:{stat.st_mtime_ns}:{dll_hash}:{top_n}".encode()
    ).hexdigest()
    cache = cache_dir / f"slm-{key}.json" if cache_dir else None
    if cache and cache.is_file() and not force:
        try:
            result = json.loads(cache.read_text(encoding="utf-8"))
            if result.get("loop_engine") == "seamless-loop-music" and result.get("candidates"):
                result["cached"] = True
                return result
        except (OSError, ValueError):
            pass
    started = time.perf_counter()
    audio, sr, decoder = read_audio_for_analysis(source, ffmpeg=ffmpeg)
    total = len(audio)
    if sr <= 0 or total == 0:
        raise ValueError("Empty or invalid PCM audio")
    lib = ctypes.CDLL(str(dll))
    lib.lf_analyze_file.argtypes = [
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.POINTER(NativeLoopPoint),
        ctypes.c_int,
    ]
    lib.lf_analyze_file.restype = ctypes.c_int
    lib.lf_get_last_error.argtypes = []
    lib.lf_get_last_error.restype = ctypes.c_char_p
    points = (NativeLoopPoint * 10)()
    # Decode once through Studio's existing decoder. Conversion is lossless
    # float PCM at the original rate and never changes the imported file.
    with tempfile.TemporaryDirectory(prefix="fh_slm_") as temp:
        wav = Path(temp) / "audio.wav"
        sf.write(wav, audio, sr, subtype="FLOAT")
        count = lib.lf_analyze_file(_native_path(wav), top_n, points, len(points))
    if count < 0:
        error = (lib.lf_get_last_error() or b"unknown error").decode("utf-8", errors="replace")
        raise ValueError(f"SeamlessLoopMusic analysis failed: {error}")
    if count > len(points):
        raise ValueError("Unexpected native result count")
    candidates, seen = [], set()
    for p in list(points)[:count]:
        a, b = int(p.loopStart), int(p.loopEnd)
        if not (0 <= a < b <= total) or (a, b) in seen:
            continue
        if not all(math.isfinite(float(v)) for v in (p.score, p.noteDiff, p.loudnessDiff)):
            continue
        seen.add((a, b))
        candidates.append(
            {
                "start": a / sr,
                "end": b / sr,
                "score": max(0.0, min(1.0, float(p.score))),
                "bars": 0,
                "why": "SeamlessLoopMusic · 音色与响度衔接匹配；请试听确认",
                "evidence": {
                    "provider": "seamless-loop-music",
                    "start_sample": a,
                    "end_sample": b,
                    "sample_rate": sr,
                    "native_score": float(p.score),
                    "note_difference": float(p.noteDiff),
                    "loudness_difference": float(p.loudnessDiff),
                },
            }
        )
    if not candidates:
        raise ValueError("SeamlessLoopMusic 未找到有效循环；可继续手动选点。")
    result = {
        "schema_version": 1,
        "source": str(source),
        "loop_engine": "seamless-loop-music",
        "duration_sec": total / sr,
        "sample_rate": sr,
        "samples": total,
        "decoder": decoder,
        "candidates": {"tl": candidates, "pl": candidates},
        "native_library_sha256": dll_hash,
        "cached": False,
        "runtime_ms": round((time.perf_counter() - started) * 1000),
    }
    if cache:
        cache.parent.mkdir(parents=True, exist_ok=True)
        # Parallel editor and batch requests must never share a temporary file.
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", suffix=".tmp", prefix="slm-", dir=cache.parent, delete=False
        ) as handle:
            json.dump(result, handle, ensure_ascii=False)
            temp = Path(handle.name)
        try:
            temp.replace(cache)
        finally:
            temp.unlink(missing_ok=True)
    return result


def cmd_seamless_loops(args):
    result = analyze_seamless(
        Path(args.input),
        Path(args.slm_dll),
        cache_dir=Path(args.cache_dir) if args.cache_dir else None,
        ffmpeg=args.ffmpeg,
        force=args.force,
    )
    print(json.dumps(result, ensure_ascii=False))
    return 0
