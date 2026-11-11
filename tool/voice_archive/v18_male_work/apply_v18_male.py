#!/usr/bin/env python3
"""v18 남성 샘플(스포츠 MC 픽스)을 앱 자산(st_male_*, seq_male_*)으로 적용한다.

- 대상 파일: st_male_*.wav, seq_male_*.wav 만 쓴다.
- cnt_*, c_* (카운트다운) 와 여성·아기 파일은 건드리지 않는다.
- 원본: tool/voice_archive/raw_tts/v18_male/sample_v18_male.wav
"""
import os
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.abspath(os.path.join(HERE, '..', '..'))
ASSETS = os.path.abspath(os.path.join(TOOL, '..', 'assets', 'audio'))
SRC = os.path.join(TOOL, 'voice_archive', 'raw_tts', 'v18_male', 'sample_v18_male.wav')
BEEP = os.path.join(ASSETS, 'beep.wav')

SR = 44100
PAD_MS = 60           # 구간 앞뒤 여백
FADE_MS = 25          # 끝 페이드
GAP_ATTN_MS = 180     # 삑 -> 음성
GAP_VOICE_MS = 300    # 음성 -> 음성
TARGET_RMS_VOICE = 0.19
SEQ_TARGET_RMS = 0.20
BEEP_RMS = 0.24
MAX_PEAK = 0.90

KEYS = ['prepare', 'startWork', 'startRest', 'setRest', 'lastRound', 'finish']
# 원본 구간 순서 (v17 샘플): 준비, 운동시작, 휴식시작, 세트간휴식, 마지막라운드, 운동종료, 다섯, 넷, 셋, 둘, 하나
SEG_KEYS = KEYS + ['d5', 'd4', 'd3', 'd2', 'd1']
THRESH_RATIO = 0.04
QUIET_GAP_MS = 80     # 이 이상 조용하면 구절 경계


def read_mono(path):
    with wave.open(path, 'rb') as w:
        sr = w.getframerate()
        d = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768
    return d, sr


def write(path, d, sr=SR):
    d = np.clip(d, -1.0, 1.0)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((d * 32767).astype(np.int16).tobytes())


def rms(d):
    return float(np.sqrt(np.mean(d ** 2))) if d.size else 0.0


def normalize(d, target, max_peak=MAX_PEAK):
    r = rms(d)
    if r > 1e-7:
        d = d * (target / r)
    p = float(np.max(np.abs(d))) if d.size else 0.0
    if p > max_peak:
        d = d / p * max_peak
    return d


def fade(d, fi_ms=8, fo_ms=FADE_MS):
    d = d.copy()
    fi = min(len(d) // 2, int(SR * fi_ms / 1000))
    fo = min(len(d) // 2, int(SR * fo_ms / 1000))
    if fi:
        d[:fi] *= (1 - np.cos(np.linspace(0, np.pi, fi))) / 2
    if fo:
        d[-fo:] *= (1 + np.cos(np.linspace(0, np.pi, fo))) / 2
    return d


# 음성 인식(elevenlabs_scribe_v2) 으로 확인한 11개 구절 시각 (초, sample_v18_male.wav 기준)
ASR_PHRASES = [
    (0.18, 0.38), (0.88, 1.68), (2.22, 2.96), (3.48, 4.24), (4.78, 5.60),
    (6.18, 6.92), (7.46, 7.80), (8.42, 8.52), (9.12, 9.30), (9.90, 10.08),
    (10.62, 10.84),
]


def segments(d, sr):
    """구절 경계 = 인접 구절 사이 중간점. 각 창 안에서 소리가 있는 구간을 잡는다."""
    win = int(sr * 0.01)
    n = len(d) // win
    env = np.sqrt((d[:n * win].reshape(n, win) ** 2).mean(1))
    thr = max(env.max() * THRESH_RATIO, 0.008)
    on = env > thr
    cuts = [0]
    for (_, e), (s2, _) in zip(ASR_PHRASES, ASR_PHRASES[1:]):
        cuts.append(int(round((e + s2) / 2 * 100)))  # 10ms 단위 인덱스
    cuts.append(n)
    out = []
    for k in range(len(ASR_PHRASES)):
        lo, hi = cuts[k], min(cuts[k + 1], n)
        idx = np.where(on[lo:hi])[0]
        if idx.size == 0:
            raise RuntimeError(f'구절 {k} 소리 없음')
        out.append(((lo + idx[0]) * win, (lo + idx[-1] + 1) * win))
    return out


def main():
    src, sr = read_mono(SRC)
    assert sr == SR, f'샘플레이트 {sr} != {SR}'
    segs = segments(src, sr)
    assert len(segs) == len(SEG_KEYS), f'구절 {len(segs)}개 — 기대 {len(SEG_KEYS)}개'

    def clip_seg(i):
        a, b = segs[i]
        pad = int(SR * PAD_MS / 1000)
        a = max(0, a - pad)
        b = min(len(src), b + pad)
        return src[a:b].copy()

    st = {}
    for i, key in enumerate(SEG_KEYS[:len(KEYS)]):
        v = fade(clip_seg(i))
        v = normalize(v, TARGET_RMS_VOICE)
        out = os.path.join(ASSETS, f'st_male_{key}.wav')
        write(out, v)
        st[key] = len(v) / SR * 1000
        print(f'st_male_{key:11s} {st[key]:6.0f}ms rms {rms(v):.3f} peak {np.max(np.abs(v)):.3f}')

    # 삑
    beep, _ = read_mono(BEEP)
    beep = normalize(beep, BEEP_RMS)
    beep_ms = len(beep) / SR * 1000
    seq_ms = {}
    for key in KEYS:
        v, _ = read_mono(os.path.join(ASSETS, f'st_male_{key}.wav'))
        buf = np.concatenate([beep, np.zeros(int(SR * GAP_ATTN_MS / 1000)), v])
        buf = normalize(buf, SEQ_TARGET_RMS)
        write(os.path.join(ASSETS, f'seq_male_{key}.wav'), buf)
        seq_ms[key] = len(buf) / SR * 1000
        print(f'seq_male_{key:11s} {seq_ms[key]:6.0f}ms')

    # 운동 시작 + 마지막 라운드 (한 파일)
    a, _ = read_mono(os.path.join(ASSETS, 'st_male_startWork.wav'))
    b, _ = read_mono(os.path.join(ASSETS, 'st_male_lastRound.wav'))
    buf = np.concatenate([
        beep, np.zeros(int(SR * GAP_ATTN_MS / 1000)), a,
        np.zeros(int(SR * GAP_VOICE_MS / 1000)), b,
    ])
    buf = normalize(buf, SEQ_TARGET_RMS)
    write(os.path.join(ASSETS, 'seq_male_workLast.wav'), buf)
    seq_ms['workLast'] = len(buf) / SR * 1000
    print(f'seq_male_workLast {seq_ms["workLast"]:6.0f}ms')

    print()
    print('Dart seqDurMs male 항목:')
    print("  'male': {" + ', '.join(f"'{k}': {int(round(v))}" for k, v in seq_ms.items()) + '},')
    print('st (참고):', {k: int(round(v)) for k, v in st.items()})


if __name__ == '__main__':
    main()
