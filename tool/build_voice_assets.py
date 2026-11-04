#!/usr/bin/env python3
"""오디오 클립 분할 + 페이드 + RMS 정규화 (numpy 직접 처리).

ffmpeg 의 `afade` 필터가 이 환경에서 조용히 무음 파일을 만들어내는 문제가
있어서, 자르기/페이드/정규화를 모두 numpy 로 직접 한다.
(ffmpeg 는 mp3 → wav 디코딩에만 사용)

사용:
    python3 tool/build_voice_assets.py
"""
import os
import subprocess
import wave

import numpy as np

SR = 22050
AUDIO = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')

# 상태 안내 문장 경계 (ASR 세그먼트 기준, 초)
BABY_STATE = {
    'prepare': (0.18, 0.74),
    'startWork': (1.30, 2.12),
    'startRest': (2.72, 3.58),
    'setRest': (4.24, 5.42),
    'lastRound': (6.10, 7.20),
    'finish': (7.88, 9.88),
}
BABY_COUNT = {5: (0.08, 0.52), 4: (1.08, 1.38), 3: (2.10, 2.38),
              2: (3.00, 3.22), 1: (3.80, 4.06)}

# 목표 RMS — 파일마다 녹음 크기가 달라 '커졌다 작아졌다' 하는 것을 막는다.
TARGET_RMS_VOICE = 0.190
TARGET_RMS_COUNT = 0.200


def decode(src, dst):
    """mp3 → mono 22050 wav"""
    subprocess.run(
        ['ffmpeg', '-v', 'error', '-y', '-i', src, '-ac', '1', '-ar', str(SR),
         '-c:a', 'pcm_s16le', dst],
        check=True,
    )


def load(path):
    with wave.open(path, 'rb') as w:
        n, sr, ch = w.getnframes(), w.getframerate(), w.getnchannels()
        raw = w.readframes(n)
    d = np.frombuffer(raw, dtype='<i2').astype(np.float64) / 32768.0
    if ch > 1:
        d = d.reshape(-1, ch).mean(axis=1)
    return d, sr


def save(path, d, sr=SR):
    d = np.clip(d, -1.0, 1.0)
    pcm = (d * 32767.0).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def cut_fade(d, sr, a, b, pad=0.0, fade_in=0.006, fade_out=0.014):
    """[a-pad, b+pad] 구간을 잘라 앞뒤 페이드를 넣는다."""
    start = max(0, int((a - pad) * sr))
    end = min(len(d), int((b + pad) * sr))
    seg = d[start:end].copy()
    n = len(seg)
    if n == 0:
        return seg
    fi = min(n // 2, int(sr * fade_in))
    fo = min(n // 2, int(sr * fade_out))
    if fi > 0:
        seg[:fi] *= np.linspace(0.0, 1.0, fi)
    if fo > 0:
        seg[-fo:] *= np.linspace(1.0, 0.0, fo)
    return seg


def normalize(d, target_rms, max_peak=0.97):
    rms = float(np.sqrt(np.mean(d ** 2))) if d.size else 0.0
    if rms > 1e-7:
        d = d * (target_rms / rms)
    peak = float(np.max(np.abs(d))) if d.size else 0.0
    if peak > max_peak:
        d = d / peak * max_peak
    return d


def verify(path):
    d, _ = load(path)
    peak = float(np.max(np.abs(d))) if d.size else 0.0
    rms = float(np.sqrt(np.mean(d ** 2))) if d.size else 0.0
    return len(d) / SR, peak, rms


def main():
    baby_src = '/tmp/baby/mono.wav'
    baby_cnt = '/tmp/baby/count.wav'
    if not os.path.exists(baby_src):
        # mp3 원본에서 다시 디코딩
        for mp3, wav in (('/tmp/baby/src.mp3', baby_src),
                         ('/tmp/baby/count.mp3', baby_cnt)):
            if os.path.exists(mp3):
                decode(mp3, wav)

    written = []

    # 1) 아기 상태 안내
    d, sr = load(baby_src)
    for key, (a, b) in BABY_STATE.items():
        seg = cut_fade(d, sr, a, b, pad=0.06)
        seg = normalize(seg, TARGET_RMS_VOICE)
        out = os.path.join(AUDIO, f'st_cute_{key}.wav')
        save(out, seg, sr)
        written.append(out)

    # 2) 아기 카운트다운
    d, sr = load(baby_cnt)
    for n, (a, b) in BABY_COUNT.items():
        seg = cut_fade(d, sr, a, b, pad=0.05, fade_out=0.016)
        seg = normalize(seg, TARGET_RMS_COUNT)
        out = os.path.join(AUDIO, f'c_cute_{n}.wav')
        save(out, seg, sr)
        written.append(out)

    # 3) 남성/여성 음성도 같은 기준으로 RMS 정규화 (이미 잘려 있는 파일)
    for pat in ('c_male', 'c_female', 'st_male', 'st_female'):
        for n in ([5, 4, 3, 2, 1] if pat.startswith('c_') else
                  ['prepare', 'startWork', 'startRest', 'setRest',
                   'lastRound', 'finish']):
            p = os.path.join(AUDIO, f'{pat}_{n}.wav')
            if not os.path.exists(p):
                continue
            d2, sr2 = load(p)
            if not d2.size or float(np.max(np.abs(d2))) == 0.0:
                print(f'  !! SOURCE EMPTY: {os.path.basename(p)}')
                continue
            target = (TARGET_RMS_COUNT if pat.startswith('c_')
                      else TARGET_RMS_VOICE)
            save(p, normalize(d2, target), sr2)
            written.append(p)

    print(f'{"file":26s} {"dur":>7s} {"peak":>6s} {"rms":>6s}')
    bad = []
    for p in written:
        dur, peak, rms = verify(p)
        flag = '' if peak > 0.05 else '  <-- SILENT!'
        if peak <= 0.05:
            bad.append(os.path.basename(p))
        print(f'{os.path.basename(p):26s} {dur:7.3f} {peak:6.3f} {rms:6.3f}{flag}')
    print()
    print('SILENT FILES:', bad if bad else 'none')


if __name__ == '__main__':
    main()
