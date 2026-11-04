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

사용:
    python3 tool/build_sequences.py
"""
import os
import wave

import numpy as np

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')

# 출력 샘플레이트 — 효과음(44100)에 맞춘다. (음성은 보간 업샘플)
OUTC = 44100

# AudioCoach 의 상수와 반드시 같아야 한다.
ATTENTION_GAP_MS = 90
VOICE_GAP_MS = 110


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
    """buf 의 at_ms 위치에 clip 을 더한다 (필요하면 버퍼를 늘린다)."""
    start = int(OUTC * at_ms / 1000)
    end = start + len(clip)
    if end > len(buf):
        buf = np.concatenate([buf, np.zeros(end - len(buf))])
    buf[start:end] += clip
    return buf


def norm(d, target_rms=0.20, max_peak=0.97):
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
    beep = clip('beep.wav')  # 130ms 주의음 (음성 앞에 짧게)

    # 음성 길이표 (ms) — AudioCoach._stDurationMs 와 일치해야 한다.
    voice_len = {
        'male': dict(prepare=740, startWork=940, startRest=960,
                     setRest=1340, lastRound=1100, finish=1580),
        'female': dict(prepare=920, startWork=875, startRest=906,
                       setRest=1340, lastRound=1400, finish=1840),
        'baby': dict(prepare=680, startWork=940, startRest=980,
                     setRest=1300, lastRound=1220, finish=2120),
    }

    print('== 안내 시퀀스 (삑 + 음성, 미리 합침) ==')
    seq_len = {}
    for style in ('male', 'female', 'baby'):
        seq_len[style] = {}
        for key in ('prepare', 'startWork', 'startRest', 'setRest',
                    'lastRound', 'finish'):
            v = clip(f'st_{style}_{key}.wav')
            buf = np.zeros(len(beep) + int(OUTC * ATTENTION_GAP_MS / 1000)
                           + len(v))
            buf[:len(beep)] = beep
            at = len(beep) + int(OUTC * ATTENTION_GAP_MS / 1000)
            buf[at:at + len(v)] += v
            d = norm(buf)
            seq_len[style][key] = save(f'seq_{style}_{key}.wav', d)

        # 운동 시작 + 마지막 라운드 (한 파일)
        a = clip(f'st_{style}_startWork.wav')
        b = clip(f'st_{style}_lastRound.wav')
        total = (len(beep) + int(OUTC * ATTENTION_GAP_MS / 1000) + len(a)
                 + int(OUTC * VOICE_GAP_MS / 1000) + len(b))
        buf = np.zeros(total)
        buf[:len(beep)] = beep
        at = len(beep) + int(OUTC * ATTENTION_GAP_MS / 1000)
        buf[at:at + len(a)] += a
        at += len(a) + int(OUTC * VOICE_GAP_MS / 1000)
        buf[at:at + len(b)] += b
        seq_len[style]['workLast'] = save(
            f'seq_{style}_workLast.wav', norm(buf))

    print()
    print('== 카운트다운 묶음 (5·4·3·2·1, 정확히 1초 간격) ==')
    cnt_len = {}
    for style in ('male', 'female', 'baby'):
        total = 4000  # 마지막 '1' 은 4000ms 위치
        buf = np.zeros(int(OUTC * total / 1000))
        for i, n in enumerate((5, 4, 3, 2, 1)):
            c = clip(f'c_{style}_{n}.wav')
            buf = place(buf, c, i * 1000)
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


if __name__ == '__main__':
    main()
