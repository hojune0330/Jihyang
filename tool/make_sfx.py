#!/usr/bin/env python3
"""짧고 선명한 단일 전자음(ATM 버튼음 계열) 효과음 생성기.

설계 원칙 (요구사항 ④)
  - 짧고 선명한 **단일** 신호음. 반복음·긴 감미료 금지.
  - 운동/휴식은 **음높이**로 명확히 구분 (높음=운동, 낮음=휴식).
  - 주변 소음 속에서도 인식 가능하도록 배음(2·3차)을 살짝 섞어
    '전자음' 특유의 또렷함을 준다.
  - 지나치게 날카롭지 않도록 2kHz 이상 성분은 최소화하고,
    4ms 어택 + 지수 감쇠로 귀를 찌르지 않게 만든다.

출력: assets/audio/sfx_work.wav, sfx_rest.wav, sfx_finish.wav, beep.wav
"""
import wave
import struct
import numpy as np
import os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')


def tone(freq, dur, harm=((1, 1.0), (2, 0.16), (3, 0.05)), attack=0.004,
         decay=40.0):
    """지수 감쇠하는 짧은 전자음 1개."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    w = np.zeros(n)
    for h, a in harm:
        if freq * h > 2000:      # 2kHz 이상은 넣지 않는다 (날카로움 방지)
            continue
        w += a * np.sin(2 * np.pi * freq * h * t)

    env = np.exp(-t * decay)
    a_n = max(1, int(SR * attack))
    env[:a_n] *= np.linspace(0.0, 1.0, a_n)
    tail = max(1, int(SR * 0.008))
    env[-tail:] *= np.linspace(1.0, 0.0, tail)
    w *= env

    peak = np.max(np.abs(w))
    if peak > 0:
        w /= peak
    return w


def silence(dur):
    return np.zeros(max(1, int(SR * dur)))


def write_wav(name, data, peak=0.90):
    data = np.asarray(data, dtype=np.float64)
    m = np.max(np.abs(data))
    if m > 0:
        data = data / m * peak
    pcm = np.clip(data * 32767.0, -32768, 32767).astype('<i2')
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())
    dur = len(pcm) / SR
    print(f'{name:18s} {dur*1000:6.1f} ms  peak={peak}')


def main():
    # 운동 시작 — 높고 또렷한 단일 전자음 (A5 880Hz 계열의 1180Hz)
    write_wav('sfx_work.wav', tone(1180, 0.095), peak=0.92)

    # 휴식 시작 — 낮고 부드러운 단일 전자음 (E4 660Hz)
    write_wav('sfx_rest.wav', tone(660, 0.110, decay=32.0), peak=0.92)

    # 전체 종료 — 짧은 2음 상승 (780 -> 1170Hz). 반복음 아님, 총 170ms
    write_wav(
        'sfx_finish.wav',
        np.concatenate([tone(780, 0.075), silence(0.012), tone(1170, 0.080)]),
        peak=0.92,
    )

    # 음성 대체용 중립 비프
    write_wav('beep.wav', tone(900, 0.080), peak=0.85)


if __name__ == '__main__':
    main()
