#!/usr/bin/env python3
"""남성 목소리만 '아나운서' 톤으로 교체하는 파이프라인 (v5).

## 이 스크립트의 안전장치

여성·아기 음성은 **어떤 것도 바꾸지 않는다**는 요구가 있었다.
말로만 지키지 않고 구조로 막는다.

  * 쓰기 허용 파일 이름을 `st_male_* / c_male_* / cnt_male / seq_male_*` 로
    화이트리스트 검사한다. 그 외 이름이 나오면 **즉시 중단**한다.
  * 실행 전 여성·아기 자산의 md5 를 뜨고, 끝나면 다시 떠서 비교한다.
    하나라도 달라졌으면 비정상 종료한다.

## v4 파이프라인과 동일한 처리

`tool/voice_pipeline.py` 의 검증된 함수를 그대로 가져다 쓴다.
  · true_span()  — ASR 단어 구간에서 에너지 스캔으로 경계 확장 (잘림 방지)
  · shape()      — 시간불변 FFT EQ (음절 흔들림 구조적 불가능)
  · normalize()  — RMS 통일

## 아나운서 톤을 위해 추가로 하는 일

  * 속도: 합성 단계에서 speed 0.95 로 이미 조금 느리게 뽑았다.
  * 앞뒤 여백을 v4 보다 조금 넉넉히 주어 문장이 '뚝' 끊기지 않게 한다.
  * 숫자는 또박또박 들리도록 별도 정규화(RMS 0.21)를 유지한다.

사용:
    python3 tool/voice_male_anchor.py
"""
import hashlib
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from voice_pipeline import (  # noqa: E402
    COUNT_STEP_MS,
    HEAD_MARGIN_MS,
    MAX_PEAK,
    NUMBERS,
    OUT,
    SR,
    STATE_KEYS,
    TARGET_RMS_COUNT,
    TARGET_RMS_VOICE,
    TAIL_MARGIN_MS,
    fade_edges,
    load,
    normalize,
    onset_ms,
    raised_cosine,
    saturate_gentle,
    save,
    shape,
    tail_quiet_ms,
    true_span,
)

RAW = '/tmp/tts4/male_anchor.wav'
STYLE = 'male'

# 아나운서 톤: 문장이 '뚝' 끊기지 않도록 여운을 조금 더 준다.
TAIL_MARGIN_MS_ANCHOR = 110

# ==== elevenlabs_scribe_v2 가 알려준 **단어별** 시작·끝 (초) ====
# 순서: 준비 / 운동 시작 / 휴식 시작 / 세트 간 휴식 / 마지막 라운드 /
#       운동 종료 / 다섯 / 넷 / 셋 / 둘 / 하나
WORDS = [
    [(0.30, 0.50)],                                   # 준비
    [(0.88, 1.12), (1.22, 1.50)],                     # 운동 시작
    [(2.00, 2.22), (2.34, 2.56)],                     # 휴식 시작
    [(3.02, 3.20), (3.34, 3.36), (3.52, 3.82)],       # 세트 간 휴식
    [(4.18, 4.46), (4.58, 4.88)],                     # 마지막 라운드
    [(5.30, 5.54), (5.70, 5.94)],                     # 운동 종료
    [(6.30, 6.62)],                                   # 다섯
    [(7.12, 7.14)],                                   # 넷
    [(7.72, 7.80)],                                   # 셋
    [(8.20, 8.32)],                                   # 둘
    [(8.72, 8.90)],                                   # 하나
]

PROTECTED_GLOBS = [
    'st_female_*.wav', 'st_baby_*.wav',
    'c_female_*.wav', 'c_baby_*.wav',
    'cnt_female.wav', 'cnt_baby.wav',
    'seq_female_*.wav', 'seq_baby_*.wav',
]

ALLOWED_PREFIX = ('st_male_', 'c_male_', 'cnt_male', 'seq_male_')


def md5_of(path):
    h = hashlib.md5()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def protected_snapshot():
    import glob
    snap = {}
    for pat in PROTECTED_GLOBS:
        for p in sorted(glob.glob(os.path.join(OUT, pat))):
            snap[os.path.basename(p)] = md5_of(p)
    return snap


def assert_allowed(name):
    if not name.startswith(ALLOWED_PREFIX):
        raise SystemExit(
            f'!! 쓰기 금지 파일이다: {name}\n'
            f'   이 스크립트는 남성 자산만 만든다. 여성·아기 자산은 보존 대상.'
        )


def write_male(name, data):
    assert_allowed(name)
    return save(os.path.join(OUT, name), data)


def main():
    before = protected_snapshot()
    print(f'여성·아기 자산 {len(before)}개 md5 스냅샷 완료')

    if not os.path.exists(RAW):
        raise SystemExit(f'{RAW} 가 없다. 먼저 남성 TTS 를 받아 둘 것.')

    raw, src_sr = load(RAW)
    if src_sr != SR:
        raise SystemExit(f'샘플레이트가 {src_sr}Hz 다 ({SR}Hz 여야 함)')
    print(f'== {STYLE} (아나운서) == {len(raw) / SR:.2f}s @ {SR}Hz')

    assert len(WORDS) == 11, '단어 그룹이 11개가 아니다'

    problems = []
    st_len = {}
    cnt_len = None

    # ----- 상태 안내 6종 -----
    for i, key in enumerate(STATE_KEYS):
        grp = WORDS[i]
        a0, b0 = grp[0][0], grp[-1][1]
        s, e = true_span(raw, a0, b0)
        s = max(0.0, s - HEAD_MARGIN_MS / 1000)
        e = min(len(raw) / SR, e + TAIL_MARGIN_MS_ANCHOR / 1000)

        seg = raw[int(s * SR):int(e * SR)].copy()
        # 앞 무음 제거 → 발성이 클립 시작 직후(8ms)에 온다.
        on = int(onset_ms(seg, 0.05) / 1000 * SR)
        cut = max(0, on - int(SR * 8 / 1000))
        if cut < len(seg) // 2:
            seg = seg[cut:].copy()
        seg = shape(seg)
        seg = saturate_gentle(seg)
        seg = fade_edges(seg)
        seg = normalize(seg, TARGET_RMS_VOICE)
        ms = write_male(f'st_{STYLE}_{key}.wav', seg)
        st_len[key] = ms

        tq = tail_quiet_ms(seg, 25)
        cut_ms = max(0.0, (b0 - e)) * 1000
        if cut_ms > 15:
            problems.append(f'st_{STYLE}_{key}: {cut_ms:.0f}ms 잘림')
        if tq > 0.05:
            problems.append(f'st_{STYLE}_{key}: 끝이 조용하지 않다 {tq:.3f}')
        print(f'   st_{STYLE}_{key:11s} {ms:5d}ms '
              f'컷 {s:.3f}~{e:.3f} (ASR {a0:.2f}~{b0:.2f}) '
              f'잘림={cut_ms:+.0f}ms 끝에너지={tq:.3f}')

    # ----- 숫자 5개 -----
    digits = []
    for j, num in enumerate(NUMBERS):
        grp = WORDS[6 + j]
        a0, b0 = grp[0][0], grp[-1][1]
        s, e = true_span(raw, a0, b0)
        s = max(0.0, s - HEAD_MARGIN_MS / 1000)
        e = min(len(raw) / SR, e + TAIL_MARGIN_MS / 1000)

        seg = raw[int(s * SR):int(e * SR)].copy()
        on = int(onset_ms(seg, 0.05) / 1000 * SR)
        cut = max(0, on - int(SR * 8 / 1000))
        if cut < len(seg) // 2:
            seg = seg[cut:].copy()
        seg = shape(seg)
        seg = saturate_gentle(seg)
        seg = fade_edges(seg)
        seg = normalize(seg, TARGET_RMS_COUNT)
        write_male(f'c_{STYLE}_{num}.wav', seg)
        digits.append(seg)
        print(f'   c_{STYLE}_{num:11d} {len(seg) / SR * 1000:5.0f}ms '
              f'잘림={max(0, (b0 - e)) * 1000:+.0f}ms')

    # ----- 카운트다운 묶음: 숫자 발성이 정확히 i*1000ms 에 -----
    step = int(SR * COUNT_STEP_MS / 1000)
    trimmed = []
    for seg in digits:
        on = int(onset_ms(seg, 0.05) / 1000 * SR)
        keep = 8  # ms
        cut = max(0, on - int(SR * keep / 1000))
        t = seg[cut:].copy()
        k = min(len(t) // 2, int(SR * keep / 1000))
        if k > 0:
            t[:k] *= raised_cosine(k, True)
        trimmed.append(t)

    total = step * (len(trimmed) - 1) + len(trimmed[-1])
    bundle = np.zeros(total)
    for i, seg in enumerate(trimmed):
        s0 = i * step
        bundle[s0:s0 + len(seg)] += seg
    peak = float(np.max(np.abs(bundle)))
    if peak > MAX_PEAK:
        bundle = bundle * (MAX_PEAK / peak)
    cnt_len = write_male(f'cnt_{STYLE}.wav', bundle)
    print(f'   cnt_{STYLE:10s} {cnt_len:5d}ms')

    for i in range(5):
        on = onset_ms(bundle[i * step:])
        if on > 15:
            problems.append(f'cnt_{STYLE} 숫자{i}: 온셋 {on:.0f}ms')
        print(f'      숫자{i} 온셋 {on:.0f}ms')

    # ----- 여성·아기 자산이 그대로인지 확인 -----
    after = protected_snapshot()
    if before != after:
        diff = [k for k in before if before.get(k) != after.get(k)]
        raise SystemExit(f'!! 여성·아기 자산이 변경됐다: {diff}')
    print(f'\n여성·아기 자산 {len(before)}개 전부 그대로 (md5 일치)')

    meta = {'st': {STYLE: st_len}, 'cnt': {STYLE: cnt_len}}
    with open('/tmp/voice_v5_male_meta.json', 'w') as fh:
        json.dump(meta, fh, ensure_ascii=False)

    print('\n--- Dart 상수 (male 만 갱신) ---')
    inner = ', '.join(f'StateVoice.{k}: {v}' for k, v in st_len.items())
    print(f'  VoiceStyle.{STYLE}: {{{inner}}},')
    print(f"  cntDurMs: '{STYLE}': {cnt_len}")

    print()
    if problems:
        print('!! 문제 발견 !!')
        for p in problems:
            print('   ' + p)
        raise SystemExit(1)
    print('검증 통과: 잘린 단어 없음, 카운트다운 온셋 정렬 정상')


if __name__ == '__main__':
    main()
