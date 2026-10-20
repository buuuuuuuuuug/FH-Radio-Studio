"""Cached waveform decoding, without beat detection or AI models."""

import math

from .audio import read_audio_for_analysis
from .common import *


def waveform_payload(source: Path, bins: int = 8192, ffmpeg: Optional[str] = None):
    data, sr, decoder = read_audio_for_analysis(source, ffmpeg=ffmpeg)
    total = len(data)
    mono = np.max(np.abs(data), axis=1) if data.ndim > 1 else np.abs(data)
    bins = max(16, min(16384, total, bins))
    peak = float(np.max(mono)) if total else 0.0
    values = []
    for i in range(bins):
        start, end = i * total // bins, (i + 1) * total // bins
        chunk = mono[start : max(start + 1, end)]
        p = float(np.max(chunk)) if len(chunk) else 0.0
        r = float(np.sqrt(np.mean(chunk**2))) if len(chunk) else 0.0
        values.append(
            {"peak": p, "rms": r, "norm_peak": p / max(peak, 1e-9), "norm_rms": r / max(peak, 1e-9)}
        )
    return {
        "schema_version": 1,
        "path": str(source),
        "title": source.stem,
        "duration_sec": total / sr,
        "sample_rate": sr,
        "channels": data.shape[1] if data.ndim > 1 else 1,
        "samples": total,
        "bpm": 0,
        "peak_dbfs": 20 * math.log10(max(peak, 1e-9)),
        "rms_dbfs": 0,
        "waveform": {"bins": values},
        "beats": [],
        "segments": [],
        "markers": {},
        "point_candidates": {},
        "loop_candidates": {},
        "warnings": [],
        "decoder": decoder,
        "ai_note": "仅波形；未运行 AI",
    }


def cmd_waveform_audio(args):
    source = Path(args.input).expanduser().resolve()
    stat = source.stat()
    cache = Path(args.cache_dir).expanduser() if args.cache_dir else None
    key = hashlib.sha256(
        f"v3:{source}:{stat.st_size}:{stat.st_mtime_ns}:{args.bins}".encode()
    ).hexdigest()
    file = cache / f"{key}.json" if cache else None
    if file and file.is_file():
        try:
            cached = file.read_text(encoding="utf-8")
            if isinstance(json.loads(cached).get("waveform"), dict):
                print(cached)
                return 0
        except (ValueError, OSError):
            pass
    result = waveform_payload(source, args.bins, args.ffmpeg)
    text = json.dumps(result, ensure_ascii=False, separators=(",", ":"))
    if file:
        file.parent.mkdir(parents=True, exist_ok=True)
        temp = file.with_suffix(".tmp")
        temp.write_text(text, encoding="utf-8")
        temp.replace(file)
    print(text)
    return 0
