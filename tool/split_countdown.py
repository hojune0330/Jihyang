#!/usr/bin/env python3
"""카운트다운 음성(오 사 삼 이 일)을 단어별로 분리한다.

TTS 결과는 단어 사이 무음이 일정하지 않아 silencedetect 로는 정확히
5등분되지 않는 경우가 있다. 여기서는 프레임 에너지 기반으로
'말하는 구간'을 찾은 뒤, 에너지가 가장 낮은 지점에서 4번 끊는다.
"""
import struct
import subprocess
import sys
import wave

import numpy as np

SR = 44100
FRAME = 0.010  # 10ms


def load(path):
    with wave.open(path) as w:
        n = w.getnframes()
        raw = w.readframes(n)
    return np.array(struct.unpack("<%dh" % n, raw), dtype=np.float64) / 32768.0


def write(path, samples, peak_target=0.86):
    peak = float(np.max(np.abs(samples))) if len(samples) else 1.0
    g = 1.0
    if peak > peak_target:
        g = peak_target / peak
    data = np.clip(samples * g, -1.0, 1.0)
    ints = (data * 32767).astype(np.int16)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(ints.tobytes())
    return len(data) / SR


def segment(path):
    s = load(path)
    n = len(s)
    hop = int(SR * FRAME)
    frames = n // hop
    rms = np.array(
        [np.sqrt(np.mean(s[i * hop : (i + 1) * hop] ** 2)) for i in range(frames)]
    )
    thr = max(rms.max() * 0.10, 1e-4)
    voiced = rms > thr

    # 연속 구간 묶기
    spans = []
    start = None
    for i, v in enumerate(voiced):
        if v and start is None:
            start = i
        elif not v and start is not None:
            spans.append((start, i))
            start = None
    if start is not None:
        spans.append((start, frames))

    # 60ms 미만 잡음 병합
    min_frames = int(0.06 / FRAME)
    merged = []
    for sp in spans:
        if merged and sp[0] - merged[-1][1] < min_frames:
            merged[-1] = (merged[-1][0], sp[1])
        else:
            merged.append(list(sp))
    return s, rms, merged, thr


def split_words(path, expect=5):
    s, rms, spans, thr = segment(path)
    print(f"  detected {len(spans)} spans: {[(round(a*FRAME,2), round(b*FRAME,2)) for a,b in spans]}")

    while len(spans) > expect:
        # 가장 짧은 간격으로 붙어있는 두 스팬을 병합
        gaps = [spans[i + 1][0] - spans[i][1] for i in range(len(spans) - 1)]
        i = int(np.argmin(gaps))
        spans[i] = [spans[i][0], spans[i + 1][1]]
        del spans[i + 1]

    while len(spans) < expect:
        # 가장 긴 스팬을 에너지 최저점에서 분할
        lengths = [b - a for a, b in spans]
        i = int(np.argmax(lengths))
        a, b = spans[i]
        seg = rms[a:b]
        # 중앙 40~60% 구간에서 최소 에너지 지점
        lo = int(len(seg) * 0.35)
        hi = int(len(seg) * 0.65)
        if hi <= lo:
            break
        cut = a + lo + int(np.argmin(seg[lo:hi]))
        spans[i] = [a, cut]
        spans.insert(i + 1, [cut, b])

    hop = int(SR * FRAME)
    out = []
    for a, b in spans:
        # 앞뒤 여유 40ms, 페이드
        sa = max(0, a * hop - int(SR * 0.04))
        sb = min(len(s), b * hop + int(SR * 0.06))
        seg = s[sa:sb].copy()
        fa = int(SR * 0.008)
        fo = int(SR * 0.045)
        if len(seg) > fa + fo:
            seg[:fa] *= np.linspace(0, 1, fa)
            seg[-fo:] *= np.linspace(1, 0, fo)
        out.append(seg)
    return out


def main():
    src = sys.argv[1]
    prefix = sys.argv[2]
    outdir = sys.argv[3]
    words = split_words(src, 5)
    durations = []
    for i, seg in enumerate(words):
        n = 5 - i  # 5,4,3,2,1
        p = f"{outdir}/{prefix}{n}.wav"
        d = write(p, seg)
        durations.append((n, round(d, 3)))
    print(f"  wrote {prefix}5..{prefix}1 -> {durations}")


if __name__ == "__main__":
    main()
