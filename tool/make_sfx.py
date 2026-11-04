#!/usr/bin/env python3
"""타바타 타이머 효과음 생성 (v3 — 명확한 경고음, 피로감 없는 톤).

설계
- 사인파 기반 + 완만한 어택/릴리즈 → 날카로운 클릭음 없음
- 배음은 2차만 약하게 → 금속성/삐- 소리 대신 부드러운 종소리 느낌
- 길이 0.35~0.75초 → 운동 중에도 확실히 인지, 그러나 길지 않게
- 각 상태는 '음정 진행 방향'으로 구분
    start_work  : 상승 3음 (올라감 = 시작/힘)
    start_rest  : 하강 3음 (내려감 = 이완)
    set_start   : 이중 펄스 상승 (반복 리듬 = 새 세트)
    finish      : 4음 아르페지오 + 긴 마지막 (완료)
"""
import math
import struct
import wave

SR = 44100
BASE = "/home/user/flutter_app/assets/audio"


def env(n, attack=0.014, release=0.16, hold=0.70):
    """부드러운 엔벨로프. attack/release 는 초 단위."""
    a = max(1, int(SR * attack))
    r = max(1, int(SR * release))
    out = [0.0] * n
    for i in range(n):
        if i < a:
            v = i / a
        elif i > n - r:
            v = max(0.0, (n - i) / r)
        else:
            v = 1.0
        # smoothstep
        out[i] = v * v * (3 - 2 * v) * hold
    return out


def tone(freq, dur, amp=0.5, attack=0.014, release=0.16):
    n = int(SR * dur)
    e = env(n, attack=attack, release=release)
    buf = [0.0] * n
    w = 2 * math.pi * freq
    for i in range(n):
        t = i / SR
        v = math.sin(w * t) + 0.22 * math.sin(2 * w * t) + 0.05 * math.sin(3 * w * t)
        buf[i] = amp * v * e[i] / 1.27
    return buf


def silence(dur):
    return [0.0] * int(SR * dur)


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def write(name, samples, target=0.97):
    peak = max((abs(s) for s in samples), default=1.0)
    # 항상 목표 피크까지 정규화 → 기기에서 충분히 크게 들린다
    g = target / peak if peak > 1e-6 else 1.0
    with wave.open(f"{BASE}/{name}", "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(
            b"".join(
                struct.pack("<h", int(max(-1.0, min(1.0, s * g)) * 32767))
                for s in samples
            )
        )
    print(f"  {name:20} {len(samples)/SR:.2f}s")


print("효과음 생성:")

# 운동 시작 / 다음 라운드 시작 : 상승 3음 (A5 → D6 → G6)
write(
    "start_work.wav",
    seq(
        tone(880, 0.085, 0.46, release=0.06),
        silence(0.018),
        tone(1175, 0.085, 0.50, release=0.06),
        silence(0.018),
        tone(1568, 0.24, 0.54, attack=0.010, release=0.20),
    ),
)

# 휴식 시작 : 하강 3음 (G5 → D5 → A4) — 운동 시작과 방향이 반대
write(
    "start_rest.wav",
    seq(
        tone(784, 0.095, 0.44, release=0.07),
        silence(0.020),
        tone(587, 0.095, 0.46, release=0.07),
        silence(0.020),
        tone(440, 0.30, 0.50, attack=0.016, release=0.24),
    ),
)

# 세트 시작 : 이중 펄스 + 상승 (반복 리듬으로 '새 세트' 느낌)
write(
    "set_start.wav",
    seq(
        tone(988, 0.070, 0.44, release=0.05),
        silence(0.045),
        tone(988, 0.070, 0.44, release=0.05),
        silence(0.045),
        tone(1319, 0.115, 0.48, release=0.08),
        silence(0.015),
        tone(1760, 0.26, 0.52, attack=0.010, release=0.21),
    ),
)

# 세트 간 휴식 시작 : 하강 3음 + 낮고 긴 마무리 (일반 휴식과 구분)
write(
    "set_rest.wav",
    seq(
        tone(698, 0.090, 0.42, release=0.06),
        silence(0.020),
        tone(587, 0.090, 0.44, release=0.06),
        silence(0.020),
        tone(466, 0.090, 0.44, release=0.06),
        silence(0.020),
        tone(349, 0.34, 0.48, attack=0.018, release=0.26),
    ),
)

# 운동 종료 : 4음 상승 아르페지오 + 긴 마지막 (완료감)
write(
    "finish.wav",
    seq(
        tone(523, 0.10, 0.42, release=0.07),
        silence(0.014),
        tone(659, 0.10, 0.45, release=0.07),
        silence(0.014),
        tone(784, 0.10, 0.48, release=0.07),
        silence(0.014),
        tone(1046, 0.46, 0.54, attack=0.012, release=0.36),
    ),
)

# 짧은 중립 비프 (효과음만 켜고 음성을 껐을 때 카운트 대체)
write("beep.wav", seq(tone(1046, 0.055, 0.38, release=0.045), silence(0.008)))

print("완료")
