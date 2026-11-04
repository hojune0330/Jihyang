#!/usr/bin/env python3
"""타바타 타이머용 효과음 생성.

부드러운 사인파 + 완만한 엔벨로프를 사용해 귀에 거슬리지 않게 만든다.
- start_work  : 상승 2음 (밝고 힘찬 시작)
- start_rest  : 하강 2음 (편안한 휴식)
- transition  : 중간 1음 (구간 전환)
- set_rest    : 하강 3음 (세트 간 휴식, 일반 휴식과 구분)
- finish      : 상승 4음 아르페지오 (완료)
- beep        : 짧은 중립음
"""
import struct
import wave

SR = 44100


def env(n, attack=0.008, release=0.10):
    """클릭 노이즈를 막는 완만한 엔벨로프."""
    a = int(SR * attack)
    r = int(SR * release)
    out = []
    for i in range(n):
        if i < a:
            v = i / max(a, 1)
        elif i > n - r:
            v = max(0.0, (n - i) / max(r, 1))
        else:
            v = 1.0
        # 부드러운 곡선
        out.append(v * v * (3 - 2 * v))
    return out


def tone(freq, dur, amp=0.42, harmonics=True):
    n = int(SR * dur)
    e = env(n)
    buf = []
    for i in range(n):
        t = i / SR
        v = 0.0
        # 기본음 + 약한 배음으로 따뜻한 소리
        v += 1.00 * __import__("math").sin(2 * 3.141592653589793 * freq * t)
        if harmonics:
            v += 0.16 * __import__("math").sin(2 * 3.141592653589793 * freq * 2 * t)
            v += 0.06 * __import__("math").sin(2 * 3.141592653589793 * freq * 3 * t)
        buf.append(amp * v * e[i] / 1.22)
    return buf


def silence(dur):
    return [0.0] * int(SR * dur)


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def write(path, samples):
    # 클리핑 방지
    peak = max((abs(s) for s in samples), default=1.0)
    g = 1.0 if peak <= 0.95 else 0.95 / peak
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(
            b"".join(
                struct.pack("<h", int(max(-1.0, min(1.0, s * g)) * 32767))
                for s in samples
            )
        )
    print(f"wrote {path}  ({len(samples)/SR:.2f}s)")


BASE = "/home/user/flutter_app/assets/audio"

# 운동 시작 : 밝게 상승 (G5 → C6)
write(
    f"{BASE}/start_work.wav",
    seq(tone(784, 0.10), silence(0.015), tone(1046, 0.17)),
)

# 휴식 시작 : 편안하게 하강 (E5 → B4)
write(
    f"{BASE}/start_rest.wav",
    seq(tone(659, 0.10), silence(0.015), tone(494, 0.19)),
)

# 구간 전환 : 중간 단음
write(f"{BASE}/transition.wav", seq(tone(880, 0.075, amp=0.34), silence(0.02)))

# 세트 간 휴식 : 하강 3음 (일반 휴식과 구분)
write(
    f"{BASE}/set_rest.wav",
    seq(
        tone(698, 0.10),
        silence(0.015),
        tone(587, 0.10),
        silence(0.015),
        tone(494, 0.16),
    ),
)

# 완료 : 상승 4음 아르페지오
write(
    f"{BASE}/finish.wav",
    seq(
        tone(523, 0.11),
        silence(0.01),
        tone(659, 0.11),
        silence(0.01),
        tone(784, 0.11),
        silence(0.01),
        tone(1046, 0.34),
    ),
)

# 중립 비프
write(f"{BASE}/beep.wav", seq(tone(880, 0.055, amp=0.30), silence(0.01)))
