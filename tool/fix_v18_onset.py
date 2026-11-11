#!/usr/bin/env python3
"""v18 남/여 안내 음성 앞 무음 제거 + 여성 카운트다운 음량 맞춤.

- st_<male|female>_*.wav : 발성 시작 3ms 전부터 자르고 3ms 페이드인
- seq_<male|female>_*.wav: 삑(130)+간격(180)=310ms 는 그대로, 그 뒤 같은 양만 삭제
- cnt_v7_female / c_female_*: 안내(seq startWork)와 음량 일치하도록 감쇠
원본 백업: tool/voice_archive/v18g_trim_backup/
"""
import os, sys, wave
import numpy as np

A = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'audio')
KEYS = ['prepare', 'startWork', 'startRest', 'setRest', 'lastRound', 'finish']
OVER_MS = 310

def rd(p):
    with wave.open(p) as w:
        sr = w.getframerate()
        return np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64), sr

def wr(p, d, sr):
    with wave.open(p, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(np.clip(np.round(d), -32768, 32767).astype(np.int16).tobytes())

def onset_ms(d, sr, start=0, length=None):
    w1 = int(round(sr / 1000))
    s0 = int(start * sr / 1000)
    s1 = len(d) if length is None else min(len(d), int((start + length) * sr / 1000))
    seg = np.abs(d[s0:s1]); n = len(seg) // w1
    env = seg[:n * w1].reshape(n, w1).max(1)
    floor = np.sort(env)[int(round((n - 1) * 0.10))]; peak = env.max()
    thr = max(min(floor * 4, peak * 0.02), peak * 0.012)
    run = 0
    for i, v in enumerate(env):
        run = run + 1 if v > thr else 0
        if run >= 8: return i - 7
    return -1

def gated_db(d):
    x = d / 32768; sr = 44100; w = int(sr * 0.01)
    n = len(x) // w
    e = np.sqrt((x[:n*w].reshape(n, w) ** 2).mean(1))
    gate = e.max() * 0.1
    v = e[e > gate]
    return 20 * np.log10(np.sqrt((v ** 2).mean()))

durs = {}
for style in ['male', 'female']:
    for k in KEYS:
        st, sr = rd(f'{A}/st_{style}_{k}.wav')
        on = onset_ms(st, sr)
        cut = max(0, on - 3) * sr // 1000
        new = st[cut:].copy()
        fi = int(sr * 0.003); new[:fi] *= np.linspace(0, 1, fi)
        wr(f'{A}/st_{style}_{k}.wav', new, sr)
        durs[(style, k)] = round(len(new) / sr * 1000)
        for sk in [k] + (['workLast'] if k == 'startWork' else []):
            sq, _ = rd(f'{A}/seq_{style}_{sk}.wav')
            # 삑 끝(약 130ms) 이후 음성 발성 시작을 직접 잰다
            von = 140 + onset_ms(sq, sr, 140, 800)
            target = OVER_MS + 3
            c2 = max(0, von - target) * sr // 1000
            o = (von - 20 - c2 * 1000 // sr) * sr // 1000  # 음성 20ms 앞에서 무음 잘라냄
            o = max(OVER_MS * sr // 1000 - c2, 135 * sr // 1000)
            assert np.abs(sq[o:o + c2]).max() < 600, (style, sk, np.abs(sq[o:o+c2]).max())
            sq2 = np.concatenate([sq[:o], sq[o + c2:]])
            wr(f'{A}/seq_{style}_{sk}.wav', sq2, sr)
            durs[(style, 'seq_' + sk)] = round(len(sq2) / sr * 1000)
            print(f'  seq {sk}: voice {von}ms -> {von - c2*1000//sr}ms')
        print(f'{style}.{k}: onset {on}ms -> cut {cut*1000//sr}ms, st {durs[(style,k)]}ms')

for style in ['male', 'female']:
    c, _ = rd(f'{A}/cnt_v7_{style}.wav'); s, _ = rd(f'{A}/seq_{style}_startWork.wav')
    print(style, 'cnt', round(gated_db(c), 2), 'seq', round(gated_db(s), 2))

# 여성 카운트다운 감쇠
c, sr = rd(f'{A}/cnt_v7_female.wav'); s, _ = rd(f'{A}/seq_female_startWork.wav')
diff = gated_db(c) - gated_db(s)
g = 10 ** (-diff / 20)
wr(f'{A}/cnt_v7_female.wav', c * g, sr)
for n in range(1, 6):
    x, sr = rd(f'{A}/c_female_{n}.wav'); wr(f'{A}/c_female_{n}.wav', x * g, sr)
print(f'female count gain {-diff:.2f}dB')
for (st, k), v in sorted(durs.items()): print(st, k, v)
