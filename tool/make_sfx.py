#!/usr/bin/env python3
"""경고음 생성기 — '삐-삐-' 두 번 울리는 약 0.9초 신호.

현장 요구사항
  - 너무 작아서 안 들린다 → **크게** (peak 0.99, RMS 도 높게)
  - (삐-삐-) 처럼 약 1초 유지
  - 운동 / 휴식은 음높이로 즉시 구분
  - 날카롭지 않게 (2kHz 이상 성분 배제, 5ms 어택)

음성 안내를 끈 상태에서는 각 초를 알려주는 짧은 '틱'음(sfx_count)을 쓴다.
"""
import wave
import numpy as np
import os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')


def beep(freq, dur, harm=((1, 1.0), (2, 0.30), (3, 0.12)), attack=0.005,
         release=0.030):
    """한 번 울리는 전자음. 끝을 부드럽게 닫아 '뚝' 끊기는 느낌을 없앤다."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    w = np.zeros(n)
    for h, a in harm:
        if freq * h > 2000:
            continue
        w += a * np.sin(2 * np.pi * freq * h * t)

    env = np.ones(n)
    a_n = max(1, int(SR * attack))
    env[:a_n] = np.linspace(0.0, 1.0, a_n)
    r_n = max(1, int(SR * release))
    env[-r_n:] = np.linspace(1.0, 0.0, r_n)
    # 아주 완만한 감쇠 — 끝까지 또렷하게 들리도록
    env *= np.linspace(1.0, 0.72, n)
    w *= env

    peak = np.max(np.abs(w))
    if peak > 0:
        w /= peak
    return w


def silence(dur):
    return np.zeros(max(1, int(SR * dur)))


def write_wav(name, data, peak=0.99):
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
    rms = np.sqrt(np.mean((pcm / 32768.0) ** 2))
    print(f'{name:16s} {len(pcm)/SR*1000:6.0f} ms  peak={peak:.2f} rms={rms:.3f}')


def double(freq, on=0.32, off=0.20):
    """삐-삐- : 같은 음높이 두 번."""
    return np.concatenate([beep(freq, on), silence(off), beep(freq, on)])


def main():
    # 운동 시작 — 높은 음(삐-삐-), 약 0.84초
    write_wav('sfx_work.wav', double(1175, 0.32, 0.20), peak=0.99)

    # 휴식 시작 — 낮은 음(삐-삐-), 약 0.84초
    write_wav('sfx_rest.wav', double(740, 0.32, 0.20), peak=0.99)

    # 전체 종료 — 세 번 상승(삐-삐-삐-), 약 1.3초
    write_wav(
        'sfx_finish.wav',
        np.concatenate([
            beep(880, 0.28), silence(0.13),
            beep(1046, 0.28), silence(0.13),
            beep(1318, 0.40),
        ]),
        peak=0.99,
    )

    # 음성 안내를 끈 상태의 초 알림 — 짧고 또렷한 단일 틱
    write_wav('sfx_count.wav', beep(1560, 0.11, release=0.020), peak=0.99)

    # 최후 대체용
    write_wav('beep.wav', beep(1000, 0.13), peak=0.95)


if __name__ == '__main__':
    main()
