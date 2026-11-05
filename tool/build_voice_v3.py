#!/usr/bin/env python3
"""음성 자산 v3 — elevenlabs/v4-tts 3종 목소리 + DSP 후처리.

## 이번에 바꾼 것 (v2 대비)

1. **TTS 엔진 교체** — minimax speech-2.8-hd → elevenlabs/v4-tts
   톤은 유지: 남성 184Hz / 여성 219Hz / 아기 267Hz.
   (v2 는 남성 176Hz, 여성 176Hz 수준이었다)

2. **샘플레이트 44100Hz 통일**
   이전에는 남성/여성 22개 파일이 22050Hz, 나머지 40개가 44100Hz 로
   섞여 있었다. 기기는 샘플레이트가 바뀔 때마다 오디오 출력을 다시 열기
   때문에 파일을 갈아 끼우는 지점에서 미세한 끊김이 생긴다.
   → 전부 44100Hz.

3. **디에서 + 고역 정리 (날카로움 제거)**
   elevenlabs 원본은 특정 구간의 4kHz 이상 성분이 24% 까지 올라간다.
   귀로는 '쇳소리' 로 들린다. 동적 디에서 + 셸프 + 새추레이션으로
   실측 24.2% → 4.2% 까지 낮춘다.

4. **레이즈드코사인 페이드 (앞 12ms / 뒤 35ms) + 고정 여백**
   이전 v2 는 선형 8ms 하드컷. 끝이 각지게 잘려 다음 소리로 넘어갈 때
   '뚝' 하는 파형 불연속이 생겼다.

5. **RMS 통일 (0.19)**
   문장마다 녹음 크기가 달라 '커졌다 작아졌다' 하던 것을 하나로.

ffmpeg 의 afade 는 이 환경에서 무음만 만들어내므로
자르기 · 페이드 · 정규화 · 필터는 전부 numpy 로 처리한다.
(ffmpeg 는 mp3 → wav 디코딩에만 사용)

사용:
    python3 tool/build_voice_v3.py
"""
import os
import subprocess
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voice_dsp import polish, hf_ratio  # noqa: E402

SR = 44100
RAW = '/tmp/tts3'
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')

# ASR 단어 타임스탬프 + 에너지 검출로 확정한 발화 구간 (초)
# 순서: 준비, 운동 시작, 휴식 시작, 세트 휴식, 마지막 라운드, 운동 종료,
#       다섯, 넷, 셋, 둘, 하나
SPANS = {
    'male': [
        (0.030, 0.480), (0.990, 1.670), (2.270, 3.100),
        (3.600, 4.470), (5.020, 5.890), (6.370, 7.190),
        (7.770, 8.060), (8.580, 8.810), (9.380, 9.670),
        (10.240, 10.610), (11.030, 11.390),
    ],
    'female': [
        (0.030, 0.500), (1.090, 1.810), (2.450, 3.190),
        (3.800, 4.750), (5.330, 6.290), (6.870, 7.760),
        (8.390, 8.720), (9.280, 9.530), (10.100, 10.400),
        (11.000, 11.360), (11.850, 12.220),
    ],
    'baby': [
        (0.030, 0.480), (1.050, 1.810), (2.440, 3.200),
        (3.720, 4.530), (5.170, 6.100), (6.610, 7.430),
        (8.050, 8.400), (8.860, 9.120), (9.660, 9.980),
        (10.580, 10.920), (11.380, 11.730),
    ],
}

STATE_KEYS = ['prepare', 'startWork', 'startRest', 'setRest', 'lastRound', 'finish']
NUMBERS = [5, 4, 3, 2, 1]

PAD_HEAD_MS = 15
PAD_TAIL_MS = 45
FADE_IN_MS = 12
FADE_OUT_MS = 35

TARGET_RMS_VOICE = 0.190
TARGET_RMS_COUNT = 0.200
MAX_PEAK = 0.90


def decode(name):
    src = os.path.join(RAW, f'{name}.mp3')
    dst = os.path.join(RAW, f'{name}.wav')
    if os.path.exists(src):
        subprocess.run(
            ['ffmpeg', '-v', 'error', '-y', '-i', src,
             '-ac', '1', '-ar', str(SR), '-c:a', 'pcm_s16le', dst],
            check=True,
        )
    return dst


def load(path):
    with wave.open(path, 'rb') as w:
        n, sr, ch = w.getnframes(), w.getframerate(), w.getnchannels()
        raw = w.readframes(n)
    d = np.frombuffer(raw, dtype='<i2').astype(np.float64) / 32768.0
    if ch > 1:
        d = d.reshape(-1, ch).mean(axis=1)
    return d, sr


def resample(d, src_sr, dst_sr=SR):
    if src_sr == dst_sr or d.size == 0:
        return d
    n = int(round(d.size * dst_sr / src_sr))
    x_old = np.arange(d.size) / src_sr
    x_new = np.arange(n) / dst_sr
    return np.interp(x_new, x_old, d)


def raised_cosine(n, rising):
    if n <= 0:
        return np.zeros(0)
    t = np.linspace(0.0, np.pi, n)
    return (1.0 - np.cos(t)) / 2.0 if rising else (1.0 + np.cos(t)) / 2.0


def smooth_edges(d, sr):
    d = d.copy()
    fi = min(len(d) // 2, int(sr * FADE_IN_MS / 1000))
    fo = min(len(d) // 2, int(sr * FADE_OUT_MS / 1000))
    if fi > 0:
        d[:fi] *= raised_cosine(fi, True)
    if fo > 0:
        d[-fo:] *= raised_cosine(fo, False)
    return d


def normalize(d, target, max_peak=MAX_PEAK):
    rms = float(np.sqrt(np.mean(d ** 2))) if d.size else 0.0
    if rms > 1e-7:
        d = d * (target / rms)
    peak = float(np.max(np.abs(d))) if d.size else 0.0
    if peak > max_peak:
        d = d / peak * max_peak
    return d


def pad(d, sr):
    return np.concatenate([
        np.zeros(int(sr * PAD_HEAD_MS / 1000)),
        d,
        np.zeros(int(sr * PAD_TAIL_MS / 1000)),
    ])


def save(path, d):
    pcm = (np.clip(d, -1.0, 1.0) * 32767.0).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return int(round(len(pcm) / SR * 1000))


def median_f0(d, sr):
    hop, win = int(sr * 0.02), int(sr * 0.04)
    vals = []
    for i in range(0, max(0, len(d) - win), hop):
        s = d[i:i + win]
        if np.sqrt(np.mean(s ** 2)) < 0.01:
            continue
        s = (s - s.mean()) * np.hanning(len(s))
        ac = np.correlate(s, s, 'full')[len(s) - 1:]
        lo, hi = int(sr / 600), int(sr / 70)
        if hi >= len(ac):
            continue
        seg = ac[lo:hi]
        if seg.size == 0 or seg.max() <= 0:
            continue
        k = int(np.argmax(seg)) + lo
        if ac[k] / ac[0] < 0.25:
            continue
        vals.append(sr / k)
    return float(np.median(vals)) if vals else 0.0


def main():
    st_len = {}
    cnt_meta = {}

    for style in ('male', 'female', 'baby'):
        path = decode(style)
        raw, src_sr = load(path)
        raw = resample(raw, src_sr, SR)
        print(f'== {style} == {len(raw) / SR:.2f}s @ {src_sr}Hz → {SR}Hz')

        spans = SPANS[style]
        assert len(spans) == 11, f'{style}: 구간이 11개가 아니다'

        st_len[style] = {}
        for i, key in enumerate(STATE_KEYS):
            a, b = spans[i]
            seg = raw[int(a * SR):int(b * SR)]
            before = hf_ratio(seg, SR)
            seg = polish(seg, SR)          # 디에서 + 고역 정리 + 새추레이션
            seg = smooth_edges(seg, SR)    # 레이즈드코사인 페이드
            seg = normalize(seg, TARGET_RMS_VOICE)
            seg = pad(seg, SR)
            ms = save(os.path.join(OUT, f'st_{style}_{key}.wav'), seg)
            st_len[style][key] = ms
            print(f'   st_{style}_{key:11s} {ms:5d}ms '
                  f'f0={median_f0(seg, SR):4.0f}Hz '
                  f'>4k {before * 100:4.1f}%→{hf_ratio(seg, SR) * 100:4.1f}% '
                  f'peak={np.max(np.abs(seg)):.2f}')

        digits = []
        for j, num in enumerate(NUMBERS):
            a, b = spans[6 + j]
            seg = raw[int(a * SR):int(b * SR)]
            before = hf_ratio(seg, SR)
            seg = polish(seg, SR)
            seg = smooth_edges(seg, SR)
            seg = normalize(seg, TARGET_RMS_COUNT)
            seg = pad(seg, SR)
            save(os.path.join(OUT, f'c_{style}_{num}.wav'), seg)
            digits.append(seg)
            print(f'   c_{style}_{num:11d} {len(seg) / SR * 1000:5.0f}ms '
                  f'>4k {before * 100:4.1f}%→{hf_ratio(seg, SR) * 100:4.1f}%')

        step = SR
        total = step * 4 + len(digits[-1])
        bundle = np.zeros(total)
        for i, seg in enumerate(digits):
            s = i * step
            bundle[s:s + len(seg)] += seg
        peak = float(np.max(np.abs(bundle)))
        if peak > MAX_PEAK:
            bundle = bundle * (MAX_PEAK / peak)
        ms = save(os.path.join(OUT, f'cnt_{style}.wav'), bundle)
        cnt_meta[style] = ms
        print(f'   cnt_{style:10s} {ms:5d}ms\n')

    print('--- Dart 상수용 (audio_coach.dart) ---')
    for style, m in st_len.items():
        inner = ', '.join(f'StateVoice.{k}: {v}' for k, v in m.items())
        print(f'  VoiceStyle.{style}: {{{inner}}},')
    print('  cntDurMs: ' + ', '.join(f"'{k}': {v}" for k, v in cnt_meta.items()))


if __name__ == '__main__':
    main()
