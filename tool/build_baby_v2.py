#!/usr/bin/env python3
"""아기 목소리 v2(어린 여자아이) 생성.

TTS 한 번으로 11개 발화를 받아 에너지 기반으로 분리한 뒤,
각각 페이드/RMS 정규화해서 자산 파일로 저장한다.

  [0] 준비          [1] 운동 시작     [2] 휴식 시작
  [3] 세트 휴식     [4] 마지막 라운드 [5] 운동 종료
  [6] 다섯  [7] 넷  [8] 셋  [9] 둘  [10] 하나

ffmpeg 의 afade 는 이 환경에서 무음만 만들어내므로
자르기 · 페이드 · 정규화는 전부 numpy 로 처리한다.
"""
import wave
import numpy as np
import os

SRC = '/tmp/babyv2/raw.wav'
OUT = 'assets/audio'
STYLE = 'baby'

# 에너지 기반으로 찾은 발화 구간 (ms)
SEGS = [
    (140, 640),    # 준비
    (980, 1800),   # 운동 시작
    (2160, 2880),  # 휴식 시작
    (3220, 3880),  # 세트 휴식
    (4140, 5180),  # 마지막 라운드
    (5540, 6440),  # 운동 종료
    (6760, 7120),  # 다섯
    (7420, 7720),  # 넷
    (8100, 8280),  # 셋
    (8600, 8880),  # 둘
    (9260, 9580),  # 하나
]

STATE_KEYS = ['prepare', 'startWork', 'startRest', 'setRest', 'lastRound', 'finish']
NUMBERS = [5, 4, 3, 2, 1]

TARGET_RMS_VOICE = 0.190
TARGET_RMS_COUNT = 0.200


def load(path):
    with wave.open(path, 'rb') as w:
        sr = w.getframerate()
        n = w.getnframes()
        ch = w.getnchannels()
        raw = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
    if ch > 1:
        raw = raw.reshape(-1, ch).mean(axis=1)
    return sr, raw


def fade(d, sr, fade_ms=8):
    k = int(sr * fade_ms / 1000)
    if k <= 0 or len(d) < 2 * k:
        return d
    d = d.copy()
    d[:k] *= np.linspace(0.0, 1.0, k)
    d[-k:] *= np.linspace(1.0, 0.0, k)
    return d


def normalize(d, target):
    rms = float(np.sqrt(np.mean(d ** 2)))
    if rms < 1e-6:
        return d
    d = d * (target / rms)
    peak = float(np.max(np.abs(d)))
    if peak > 0.99:
        d = d * (0.99 / peak)
    return d


def save(path, sr, d):
    pcm = np.clip(d, -1.0, 1.0)
    pcm = (pcm * 32767).astype(np.int16)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def main():
    sr, data = load(SRC)
    print(f'src: {len(data)/sr*1000:.0f}ms @ {sr}Hz')

    cut = []
    for (a, b) in SEGS:
        seg = data[int(a / 1000 * sr):int(b / 1000 * sr)].copy()
        seg = fade(seg, sr)
        cut.append((seg, b - a))

    # 1) 상태 안내 6종
    print('\n--- 상태 안내 ---')
    for i, key in enumerate(STATE_KEYS):
        seg, _ = cut[i]
        seg = normalize(seg, TARGET_RMS_VOICE)
        path = f'{OUT}/st_{STYLE}_{key}.wav'
        save(path, sr, seg)
        print(f'  {os.path.basename(path):28s} {len(seg)/sr*1000:6.0f}ms')

    # 2) 숫자 5개
    print('\n--- 숫자 ---')
    digits = []
    for i, num in enumerate(NUMBERS):
        seg, _ = cut[6 + i]
        # 숫자는 앞뒤 여백을 조금 붙여 또렷하게
        pad = int(sr * 0.02)
        seg = np.concatenate([np.zeros(pad, dtype=np.float32), seg, np.zeros(pad, dtype=np.float32)])
        seg = normalize(seg, TARGET_RMS_COUNT)
        path = f'{OUT}/c_{STYLE}_{num}.wav'
        save(path, sr, seg)
        digits.append(seg)
        print(f'  {os.path.basename(path):28s} {len(seg)/sr*1000:6.0f}ms')

    # 3) 카운트다운 묶음: 1초 간격으로 배치 (정확히 1000ms)
    print('\n--- 카운트다운 묶음 ---')
    step = int(sr * 1.0)
    last_len = len(digits[-1])
    total = step * 4 + last_len + int(sr * 0.10)
    bundle = np.zeros(total, dtype=np.float32)
    for i, seg in enumerate(digits):
        start = i * step
        bundle[start:start + len(seg)] += seg
    peak = float(np.max(np.abs(bundle)))
    if peak > 0.99:
        bundle = bundle * (0.99 / peak)
    cnt_path = f'{OUT}/cnt_{STYLE}.wav'
    save(cnt_path, sr, bundle)
    print(f'  {os.path.basename(cnt_path):28s} {len(bundle)/sr*1000:6.0f}ms')

    # 4) 길이 표 출력 (Dart 상수 갱신용)
    print('\n--- Dart 상수용 ---')
    print('state (ms):', {k: round(len(cut[i][0]) / sr * 1000) for i, k in enumerate(STATE_KEYS)})
    print('cntDurMs baby:', round(len(bundle) / sr * 1000))


if __name__ == '__main__':
    main()
