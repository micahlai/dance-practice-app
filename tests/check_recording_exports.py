"""Verify actual AVFoundation-rendered layout pixels and soundtrack pitch.

Run after RecordingChecks with generated red-camera/blue-reference fixtures.
Requires ffmpeg on PATH; does not modify the generated videos.
"""
import math
import pathlib
import struct
import subprocess
import sys

root = pathlib.Path(sys.argv[1])


def pixel(path, seconds, x, y):
    data = subprocess.check_output([
        "ffmpeg", "-v", "error", "-ss", str(seconds), "-i", str(path),
        "-vf", f"crop=2:2:{x}:{y},format=rgb24", "-frames:v", "1",
        "-f", "rawvideo", "pipe:1",
    ])
    return tuple(data[:3])


def close_color(actual, expected):
    # Allow the color-matrix conversion of the untagged synthetic inputs.
    assert len(actual) == 3 and all(abs(a - e) < 40 for a, e in zip(actual, expected)), (actual, expected)


for mode in ("normal", "slow"):
    camera = root / f"camera-{mode}.mp4"
    side = root / f"sideBySide-{mode}.mp4"
    pip = root / f"pictureInPicture-{mode}.mp4"
    close_color(pixel(camera, 1, 960, 540), (255, 0, 0))
    close_color(pixel(side, 1, 480, 540), (255, 0, 0))
    close_color(pixel(side, 1, 1440, 540), (0, 0, 255))
    close_color(pixel(pip, 1, 960, 540), (255, 0, 0))
    close_color(pixel(pip, 1, 1700, 180), (0, 0, 255))
    close_color(pixel(side, 0.1, 1440, 540), (0, 0, 0))
    close_color(pixel(pip, 0.1, 1700, 180), (255, 0, 0))
    audio = subprocess.check_output([
        "ffmpeg", "-v", "error", "-ss", "0.75", "-i", str(camera),
        "-t", "1", "-vn", "-ac", "1", "-ar", "44100", "-f", "f32le", "pipe:1",
    ])
    samples = struct.unpack(f"<{len(audio) // 4}f", audio)
    assert samples and max(abs(value) for value in samples) > 0.01
    # A time-pitch algorithm can add small zero-crossing artifacts. Find
    # the strongest spectral frequency instead of counting crossings.
    downsampled = samples[::4]
    windowed = [sample * (0.5 - 0.5 * math.cos(2 * math.pi * i / (len(downsampled) - 1)))
                for i, sample in enumerate(downsampled)]

    def power(hz):
        coefficient = 2 * math.cos(2 * math.pi * hz / 11025)
        previous = before = 0.0
        for sample in windowed:
            current = sample + coefficient * previous - before
            before, previous = previous, current
        return previous * previous + before * before - coefficient * previous * before

    frequency = max(range(400, 481), key=power)
    assert math.isclose(frequency, 440, abs_tol=5), frequency
    print(f"PASS: {mode} layout pixels, reference delay, and pitch ({frequency:.1f} Hz)")
