#!/usr/bin/env python3
"""Writes the Prova simulada start and end beeps (#425) as 48 kHz mono WAV files.

The tones are generated here, so they carry no third-party licence: the project
dedicates them to the public domain (CC0 1.0). Import them into
/Game/Station/Audio as S_ExamStart and S_ExamEnd (see docs/unreal-setup.md).

Usage: scripts/generate-exam-sounds.py <output directory>
"""

import math
import struct
import sys
import wave
from pathlib import Path

RATE = 48_000
LEVEL = 0.5  # about -6 dBFS
FADE = 0.01  # seconds of fade in and out, so a beep never clicks


def beep(frequency: float, seconds: float) -> list[float]:
    count = int(RATE * seconds)
    fade = int(RATE * FADE)
    samples = []
    for i in range(count):
        envelope = min(1.0, i / fade, (count - 1 - i) / fade)
        # A touch of the octave makes the beep carry like a room buzzer, not a pure sine.
        tone = math.sin(2 * math.pi * frequency * i / RATE) + 0.25 * math.sin(4 * math.pi * frequency * i / RATE)
        samples.append(LEVEL * envelope * tone / 1.25)
    return samples


def silence(seconds: float) -> list[float]:
    return [0.0] * int(RATE * seconds)


def write(path: Path, samples: list[float]) -> None:
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", round(s * 32767)) for s in samples))


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    target = Path(sys.argv[1])
    target.mkdir(parents=True, exist_ok=True)
    # Entry: two short high beeps. Finish: one long lower beep.
    write(target / "S_ExamStart.wav", beep(1000, 0.25) + silence(0.15) + beep(1000, 0.25))
    write(target / "S_ExamEnd.wav", beep(800, 1.2))


if __name__ == "__main__":
    main()
