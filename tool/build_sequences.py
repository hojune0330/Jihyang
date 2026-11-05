#!/usr/bin/env python3
"""안내 시퀀스를 '파일 하나'로 미리 합친다.

## 왜 이렇게 하는가 (사운드 끊김의 근본 원인 제거)

이전 구조는 안내 한 번에 여러 파일을 이어 붙였다.

    삑(130ms) → 90ms 대기 → "운동 시작"(940ms)

이때 파일마다 `stop → seek(0) → resume` 을 호출한다. 그 사이에
오디오 장치가 비고, 사용자에게는 **뚝, 뚝 끊기는 소리**로 들린다.
게다가 앞 소리가 아직 재생 중일 때 다음 재생이 걸리면 앞 소리가
중간에 잘린다.

그래서 여기서 **간격까지 미리 계산해 하나의 WAV 로 합쳐 둔다.**
재생 측은 `resume()` 한 번만 호출하면 되므로
 - 이어 붙이기 실패가 원천적으로 불가능하고
 - 파일 사이 무음/끊김이 생길 수 없고
 - 타이밍이 ±1ms 수준으로 고정된다.

## v3 에서 추가로 고친 것 — '부드럽게 이어지지 않는다'

이전에는 삑 소리가 음성보다 훨씬 컸고(peak 0.99 vs 음성 RMS 0.19),
간격도 90ms 로 짧아서 **삑 → 음성 전환이 툭 튀었다.**
또 음성이 끝나자마자 다음 소리가 붙어 숨 쉴 틈이 없었다.

  · 삑 소리를 음성과 같은 크기(RMS 0.24)로 맞춘다
  · 삑 앞뒤에 12ms / 45ms 레이즈드코사인 페이드를 넣는다
  · 삑 → 음성 간격 90ms → 180ms
  · 음성 → 음성 간격 110ms → 300ms
  · 합치는 모든 지점에 짧은 크로스페이드를 건다 (파형 불연속 0)

사용:
    python3 tool/build_sequences.py
"""
import os
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voice_dsp import hf_ratio  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')

# 출력 샘플레이트 — 모든 자산을 44100 으로 통일한다.
OUTC = 44100

# AudioCoach 의 상수와 반드시 같아야 한다.
ATTENTION_GAP_MS = 180
VOICE_GAP_MS = 300
CROSSFADE_MS = 6

# 삑 소리 목표 RMS — 음성(0.19)보다 아주 살짝만 크게.
BEEP_RMS = 0.24


def load_mono(path):
    with wave.open(path, 'rb') as w:
        n, sr, ch = w.getnframes(), w.getframerate(), w.getnchannels()
        raw = w.readframes(n)
    d = np.frombuffer(raw, dtype='<i2').astype(np.float64) / 32768.0
    if ch > 1:
        d = d.reshape(-1, ch).mean(axis=1)
    return d, sr


def resample(d, src, dst):
    if src == dst or d.size == 0:
        return d
    n = int(round(d.size * dst / src))
    x_old = np.arange(d.size) / src
    x_new = np.arange(n) / dst
    return np.interp(x_new, x_old, d)


def silence(ms):
    return np.zeros(max(1, int(OUTC * ms / 1000)))


def place(buf, clip, at_ms):
    start = int(OUTC * at_ms / 1000)
    end = start + len(clip)
    if end > len(buf):
        buf = np.concatenate([buf, np.zeros(end - len(buf))])
    buf[start:end] += clip
    return buf


def crossfade_join(a, b, ms=CROSSFADE_MS):
    """a 의 끝과 b 의 앞을 겹쳐 이어 붙인다 (파형 불연속 제거)."""
    k = min(int(OUTC * ms / 1000), len(a) // 2, len(b) // 2)
    if k <= 0:
        return np.concatenate([a, b])
    t = np.linspace(0.0, np.pi, k)
    ramp_up = (1.0 - np.cos(t)) / 2.0
    ramp_dn = (1.0 + np.cos(t)) / 2.0
    head = a[:-k].copy()
    mid = a[-k:] * ramp_dn + b[:k] * ramp_up
    return np.concatenate([head, mid, b[k:]])


def soft_beep(d, sr):
    """삑 소리를 부드럽게 다듬고 음성과 같은 크기로 맞춘다."""
    d = d.copy()
    fi = min(len(d) // 2, int(sr * 0.012))
    fo = min(len(d) // 2, int(sr * 0.045))
    if fi > 0:
        d[:fi] *= (1.0 - np.cos(np.linspace(0, np.pi, fi))) / 2.0
    if fo > 0:
        d[-fo:] *= (1.0 + np.cos(np.linspace(0, np.pi, fo))) / 2.0
    rms = float(np.sqrt(np.mean(d ** 2))) if d.size else 0.0
    if rms > 1e-7:
        d = d * (BEEP_RMS / rms)
    peak = float(np.max(np.abs(d)))
    if peak > 0.90:
        d = d / peak * 0.90
    return d


def norm(d, target_rms=0.20, max_peak=0.92):
    rms = float(np.sqrt(np.mean(d ** 2))) if d.size else 0.0
    if rms > 1e-7:
        d = d * (target_rms / rms)
    peak = float(np.max(np.abs(d))) if d.size else 0.0
    if peak > max_peak:
        d = d / peak * max_peak
    return d


def save(name, d):
    d = np.clip(d, -1.0, 1.0)
    pcm = (d * 32767.0).astype('<i2')
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(OUTC)
        w.writeframes(pcm.tobytes())
    ms = len(pcm) / OUTC * 1000
    rms = float(np.sqrt(np.mean(d ** 2))) if d.size else 0.0
    peak = float(np.max(np.abs(d))) if d.size else 0.0
    print(f'{name:30s} {ms:7.0f} ms  peak={peak:.2f} rms={rms:.3f}')
    return int(round(ms))


def clip(name):
    d, sr = load_mono(os.path.join(OUT, name))
    return resample(d, sr, OUTC)


def main():
    beep = soft_beep(clip('beep.wav'), OUTC)

    # 음성 길이표 (ms) — AudioCoach._stDurationMs 와 일치해야 한다.
    voice_len = {
        'male': dict(prepare=510, startWork=740, startRest=890,
                     setRest=930, lastRound=930, finish=880),
        'female': dict(prepare=530, startWork=780, startRest=800,
                       setRest=1010, lastRound=1020, finish=950),
        'baby': dict(prepare=510, startWork=820, startRest=820,
                     setRest=870, lastRound=990, finish=880),
    }

    print('== 안내 시퀀스 (삑 + 음성, 미리 합침 · 크로스페이드) ==')
    seq_len = {}
    for style in ('male', 'female', 'baby'):
        seq_len[style] = {}
        for key in ('prepare', 'startWork', 'startRest', 'setRest',
                    'lastRound', 'finish'):
            v = clip(f'st_{style}_{key}.wav')
            buf = crossfade_join(beep, silence(ATTENTION_GAP_MS))
            buf = crossfade_join(buf, v)
            d = norm(buf)
            seq_len[style][key] = save(f'seq_{style}_{key}.wav', d)

        # 운동 시작 + 마지막 라운드 (한 파일)
        a = clip(f'st_{style}_startWork.wav')
        b = clip(f'st_{style}_lastRound.wav')
        buf = crossfade_join(beep, silence(ATTENTION_GAP_MS))
        buf = crossfade_join(buf, a)
        buf = crossfade_join(buf, silence(VOICE_GAP_MS))
        buf = crossfade_join(buf, b)
        seq_len[style]['workLast'] = save(
            f'seq_{style}_workLast.wav', norm(buf))

    print()
    print('== 카운트다운 묶음 (5·4·3·2·1, 정확히 1초 간격) ==')
    cnt_len = {}
    for style in ('male', 'female', 'baby'):
        buf = np.zeros(int(OUTC * 4000 / 1000))
        digits = []
        for i, n in enumerate((5, 4, 3, 2, 1)):
            c = clip(f'c_{style}_{n}.wav')
            digits.append(c)
            buf = place(buf, c, i * 1000)
        # 마지막 숫자 뒤에 여유를 조금 둬서 잘리지 않게
        buf = np.concatenate([buf, np.zeros(int(OUTC * 0.05))])
        d = norm(buf, target_rms=0.20)
        cnt_len[style] = save(f'cnt_{style}.wav', d)

    print()
    print('--- Dart 길이표 (붙여넣기용) ---')
    print('const Map<String, Map<String, int>> seqDurMs = {')
    for style, m in seq_len.items():
        inner = ', '.join(f"'{k}': {v}" for k, v in m.items())
        print(f"  '{style}': {{{inner}}},")
    print('};')
    print('const Map<String, int> cntDurMs = {')
    print('  ' + ', '.join(f"'{k}': {v}" for k, v in cnt_len.items()))
    print('};')

    print()
    print('--- 이어짐 검증 ---')
    for style in ('male', 'female', 'baby'):
        p = os.path.join(OUT, f'seq_{style}_prepare.wav')
        d, _ = load_mono(p)
        # 파일 시작과 끝의 진폭 (급단 여부)
        print(f'  seq_{style}_prepare  head={abs(d[0]):.5f} '
              f'tail={abs(d[-1]):.5f}  >4k={hf_ratio(d, OUTC) * 100:.1f}%')


if __name__ == '__main__':
    main()
