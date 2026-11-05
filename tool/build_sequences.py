#!/usr/bin/env python3
"""안내 시퀀스 · 카운트다운 묶음 생성기 v4.

## v3 에서 무엇이 잘못됐나

사용자: "숫자와 음성의 싱크가 안 맞고 끊기듯 들리는 부분 단어, 음절 모두 별로"

### ㄱ. 크로스페이드가 오히려 소리를 겹쳤다
   v3 는 삑 끝 6ms 와 음성 앞 6ms 를 **서로 겹쳐** 이어 붙였다.
   두 신호 모두 경계에서 0 인데도 겹치면 오히려
   '삑 꼬리' 와 '음성 첫 자음' 이 동시에 울려 **음절이 뭉개진다.**
   → v4 는 겹치지 않는다. 각 클립이 이미 0 으로 시작·종료하므로
     단순히 이어 붙이면 파형 불연속이 0 이다.

### ㄴ. 삑이 음성보다 훨씬 컸다
   v3 이전 peak 0.99 → 음성 RMS 0.19. 삑이 귀를 때리고 나서 음성이
   작게 들리니 '끊긴 것처럼' 느껴졌다.
   → 삑을 RMS 0.24 로 맞춘다 (음성 0.19 보다 아주 살짝만 크게).

### ㄷ. 카운트다운 숫자가 매번 조금씩 늦었다
   v3 는 숫자 클립마다 15ms 앞 여백이 있어 숫자가 15ms 늦게 났다.
   1초 간격은 유지되지만 '박자' 가 밀린 느낌을 준다.
   → v4 클립은 발성이 0~10ms 안에 시작한다.
     묶음 배치 후 **실측으로 온셋을 확인**한다.

## 이 파일이 만드는 것

    seq_<style>_<key>.wav   × 21   (삑 + 음성, 미리 합친 파일 하나)
    cnt_<style>.wav         × 3    (5·4·3·2·1, 정확히 1초 간격)

사용:
    python3 tool/build_sequences.py
"""
import json
import os
import sys
import wave

import numpy as np

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')

OUTC = 44100

# AudioCoach 상수와 반드시 같아야 한다.
ATTENTION_GAP_MS = 180   # 삑 → 음성 시작
VOICE_GAP_MS = 300       # 음성 → 음성
COUNT_STEP_MS = 1000

BEEP_RMS = 0.24
SEQ_TARGET_RMS = 0.20
MAX_PEAK = 0.90

# 클립의 발성이 시작하는 위치(ms). voice_pipeline.py 가 0~10ms 로 맞춰 둔다.
ONSET_TOLERANCE_MS = 12


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
    return np.interp(np.arange(n) / dst, np.arange(d.size) / src, d)


def raised_cosine(n, rising):
    if n <= 0:
        return np.zeros(0)
    t = np.linspace(0.0, np.pi, n)
    return (1.0 - np.cos(t)) / 2.0 if rising else (1.0 + np.cos(t)) / 2.0


def onset_ms(d):
    win = int(OUTC * 0.005)
    n = len(d) // win
    if n == 0:
        return 0.0
    env = np.array([np.sqrt(np.mean(d[i * win:(i + 1) * win] ** 2))
                    for i in range(n)])
    if env.max() <= 0:
        return 0.0
    idx = int(np.argmax(env > env.max() * 0.05))
    return idx * 5.0


def norm(d, target, max_peak=MAX_PEAK):
    rms = float(np.sqrt(np.mean(d ** 2))) if d.size else 0.0
    if rms > 1e-7:
        d = d * (target / rms)
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


def silence(ms):
    return np.zeros(max(1, int(OUTC * ms / 1000)))


def soft_beep(d):
    """삑을 부드럽게 감싸고 음성과 비슷한 크기로 맞춘다."""
    d = d.copy()
    fi = min(len(d) // 2, int(OUTC * 0.010))
    fo = min(len(d) // 2, int(OUTC * 0.040))
    if fi > 0:
        d[:fi] *= raised_cosine(fi, True)
    if fo > 0:
        d[-fo:] *= raised_cosine(fo, False)
    rms = float(np.sqrt(np.mean(d ** 2))) if d.size else 0.0
    if rms > 1e-7:
        d = d * (BEEP_RMS / rms)
    peak = float(np.max(np.abs(d)))
    if peak > MAX_PEAK:
        d = d / peak * MAX_PEAK
    return d


def join(parts):
    """겹치지 않고 이어 붙인다. 각 조각은 이미 0 으로 시작·종료한다."""
    return np.concatenate(parts)


def main():
    # 남성만 다시 만드는 모드 (v5) — 여성·아기 시퀀스는 건드리지 않는다.
    only = os.environ.get('SEQ_ONLY_STYLE')
    styles = (only,) if only else ('male', 'female', 'baby')

    meta = {'seq': {}, 'cnt': {}}
    try:
        with open('/tmp/voice_v4_meta.json') as fh:
            prev = json.load(fh)
        meta['st'] = prev.get('st', {})
        meta['seq'] = prev.get('seq', {})
        meta['cnt'] = prev.get('cnt', {})
    except Exception:
        pass
    # v5 남성 메타가 있으면 st 길이를 그것으로 덮는다.
    try:
        with open('/tmp/voice_v5_male_meta.json') as fh:
            v5 = json.load(fh)
        meta.setdefault('st', {}).update(v5.get('st', {}))
    except Exception:
        pass

    beep = soft_beep(clip('beep.wav'))
    print(f'삑: {len(beep) / OUTC * 1000:.0f}ms  온셋 {onset_ms(beep):.0f}ms  '
          f'rms {np.sqrt(np.mean(beep ** 2)):.3f}')
    print(f'대상 목소리: {", ".join(styles)}')
    print()

    print('== 안내 시퀀스 (삑 + 음성) ==')
    seq_len = meta.get('seq', {})
    for style in styles:
        seq_len[style] = {}
        for key in ('prepare', 'startWork', 'startRest', 'setRest',
                    'lastRound', 'finish'):
            v = clip(f'st_{style}_{key}.wav')
            v_on = onset_ms(v)
            buf = join([beep, silence(ATTENTION_GAP_MS), v])
            d = norm(buf, SEQ_TARGET_RMS)
            seq_len[style][key] = save(f'seq_{style}_{key}.wav', d)
            # 삑 온셋(≈0) → 음성 온셋 기대값 = 삑길이 + 180 + v_on
            expect = len(beep) / OUTC * 1000 + ATTENTION_GAP_MS + v_on
            if abs(v_on - ONSET_TOLERANCE_MS) > ONSET_TOLERANCE_MS:
                print(f'   !! {style}/{key} 음성 온셋 {v_on:.0f}ms')
            print(f'      {style}/{key:10s} 음성 온셋 {v_on:.0f}ms '
                  f'→ 시퀀스 내 {expect:.0f}ms')

        # 운동 시작 + 마지막 라운드 (한 파일)
        a = clip(f'st_{style}_startWork.wav')
        b = clip(f'st_{style}_lastRound.wav')
        buf = join([beep, silence(ATTENTION_GAP_MS), a,
                    silence(VOICE_GAP_MS), b])
        seq_len[style]['workLast'] = save(
            f'seq_{style}_workLast.wav', norm(buf, SEQ_TARGET_RMS))

    print()
    print('== 카운트다운 묶음 (5·4·3·2·1) ==')
    cnt_len = meta.get('cnt', {})
    for style in styles:
        digits = [clip(f'c_{style}_{n}.wav') for n in (5, 4, 3, 2, 1)]
        # 각 숫자의 온셋을 보고 i*1000 위치에 정확히 오도록 앞을 당긴다
        step = int(OUTC * COUNT_STEP_MS / 1000)
        placed = []
        for d in digits:
            on = int(onset_ms(d) / 1000 * OUTC)
            cut = max(0, on)  # 온셋 앞 무음 제거 → 온셋 = 0
            t = d[cut:].copy()
            k = min(len(t) // 2, int(OUTC * 0.004))
            if k > 0:
                t[:k] *= raised_cosine(k, True)
            placed.append(t)

        total = step * 4 + len(placed[-1]) + int(OUTC * 0.020)
        buf = np.zeros(total)
        for i, t in enumerate(placed):
            s0 = i * step
            buf[s0:s0 + len(t)] += t
        peak = float(np.max(np.abs(buf)))
        if peak > MAX_PEAK:
            buf = buf * (MAX_PEAK / peak)
        cnt_len[style] = save(f'cnt_{style}.wav', buf)

        # 실측 온셋 검증
        errs = []
        for i in range(5):
            seg = buf[i * step:]
            got = onset_ms(seg)
            errs.append(got)
        print(f'      숫자 온셋 실측: '
              + ' '.join(f'{e:.0f}' for e in errs)
              + f'  (기대 0/1000/2000/3000/4000)')
        # seg 는 i*1000 지점부터 잘라냈으므로 온셋은 0 에 가까워야 한다
        bad = [f'{i}:{e:.0f}' for i, e in enumerate(errs)
               if e > ONSET_TOLERANCE_MS]
        if bad:
            print(f'   !! 온셋 어긋남: {", ".join(bad)}')

    print()
    print('--- Dart 길이표 ---')
    print('const Map<String, Map<String, int>> seqDurMs = {')
    for style, m in seq_len.items():
        inner = ', '.join(f"'{k}': {v}" for k, v in m.items())
        print(f"  '{style}': {{{inner}}},")
    print('};')
    print('const Map<String, int> cntDurMs = {')
    print('  ' + ', '.join(f"'{k}': {v}" for k, v in cnt_len.items()))
    print('};')

    meta['seq'] = seq_len
    meta['cnt'] = cnt_len
    with open('/tmp/voice_v4_meta.json', 'w') as fh:
        json.dump(meta, fh, ensure_ascii=False)


if __name__ == '__main__':
    main()
