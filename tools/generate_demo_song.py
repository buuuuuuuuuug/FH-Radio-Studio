"""Generate the original, synthetic tutorial melody; no external audio is used."""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path


def generate(path: Path) -> None:
    sample_rate = 24000
    melody = [60, 64, 67, 72, 71, 67, 64, 62, 57, 60, 64, 69, 67, 64, 62, 60]
    frames = bytearray()
    for index in range(sample_rate * 16):
        seconds = index / sample_rate
        note_index = int(seconds * 2)
        phase = seconds % 0.5
        frequency = 440 * 2 ** ((melody[note_index % len(melody)] - 69) / 12)
        envelope = min(1, phase / 0.015) * math.exp(-phase * 6)
        lead = (
            sum(
                math.sin(2 * math.pi * frequency * harmonic * seconds) / harmonic**2
                for harmonic in (1, 2, 3)
            )
            * envelope
            * 0.35
        )
        bass = math.sin(2 * math.pi * 130.8128 * seconds) * 0.09
        fade = min(1, seconds / 0.05, (16 - seconds) / 0.2)
        frames.extend(struct.pack("<h", round((lead + bass) * fade * 32767)))
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(sample_rate)
        audio.writeframes(frames)


if __name__ == "__main__":
    generate(Path(__file__).resolve().parents[1] / "app/assets/audio/looplab_demo.wav")
