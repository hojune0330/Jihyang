#!/usr/bin/env python3
"""카운트다운 전용 파이프라인 (v6) — 처음부터 새로 작성.

## 무엇이 바뀌었나

사용자 지시: "카운트다운 하는 거 처음부터 다시 만들어 오,사,삼,이,일 로
각각 처음부터 다시 만들어."

기존 카운트다운은 안내 문장과 **같은 소스 파일**에서 숫자 부분을 잘라 썼다.
그래서 문장 사이 쉼과 숫자 사이 쉼이 섞여 경계 판정이 흔들렸다.

v6 는 다르다.
  * 숫자 전용으로 **따로 합성**했다 (오. 사. 삼. 이. 일.)
  * 경계를 ASR 에 의존하지 않는다. ASR 은 영어로 오인해 0폭 타임스탬프를
    주는 경우가 있었다(5,4,3,2,1). 대신 **에너지 실루엣으로 정확히 5개
    구간을 검출**하고, 개수·길이를 스스로 검증한다.
  * 숫자 i 의 발성 시작을 **정확히 i*1000ms** 에 놓는다.
  * 배치 후 다시 측정해 오차를 검증한다.

## 음색은 기존과 동일한 처리

안내 음성과 같은 LTI EQ(shape) + 부드러운 포화 + 페이드 + RMS 정규화.
시간에 따라 변하는 게인은 쓰지 않으므로 음절이 흔들릴 수 없다.

사용:
    python3 tool/countdown_pipeline.py
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from voice_pipeline import (  # noqa: E402
    COUNT_STEP_MS,
    MAX_PEAK,
    OUT,
    SR,
    TARGET_RMS_COUNT,
    fade_edges,
    load,
    normalize,
    raised_cosine,
    saturate_gentle,
    save,
    shape,
)

SRC = '/tmp/cd5'
STYLES = ('male', 'female', 'baby')

# 오(5) 사(4) 삼(3) 이(2) 일(1)
DIGITS = [5, 4, 3, 2, 1]
DIGIT_WORDS = {5: '오', 4: '사', 3: '삼', 2: '이', 1: '일'}

# 검출 파라미터
FRAME_MS = 5.0
REL_THRESHOLD = 0.06   # 전체 피크 대비 이 비율 이상이면 발성
MIN_GAP_MS = 120       # 이만큼 벌어져야 다른 숫자로 본다
MIN_DIGIT_MS = 60
MAX_DIGIT_MS = 800
HEAD_TRIM_MS = 8       # 남기는 아주 짧은 앞 여백 (페이드인용)
TAIL_MARGIN_MS = 55    # 뒤 여운 — 잘림 방지
FADE_TAIL_MS = 60      # 클립 끝 감쇠 — 다음 숫자와의 간섭 방지

# 목표 게이티드 음량(dB). **목소리마다 안내 음성에 맞춘다.**
#
# ## 왜 고정값이 아니라 목소리별인가 (실측으로 확인한 소리 문제)
#
# 안내 시퀀스(seq)의 게이티드 음량:
#     male -15.59 / female -12.49 / baby -12.60 dB
# 카운트다운을 -13.0 으로 통일하면:
#     male 은 카운트다운이 안내보다 **2.6dB 크고**,
#     female/baby 는 0.4~0.5dB 작다.
# 남성 목소리에서 5·4·3·2·1 이 갑자기 크게 터지는 원인이다.
#
# 사용자는 한 목소리만 듣는다. 목소리 사이의 절대 음량은 의미가 없고,
# **같은 목소리 안에서 안내와 카운트다운이 같은 크기**여야 한다.
# 그래서 목표값을 그 목소리의 안내 음량에서 직접 끌어온다.
TARGET_COUNT_DB = {
    'male': -15.5,
    'female': -12.5,
    'baby': -12.6,
}


def envelope(d, frame_ms=FRAME_MS):
    w = max(1, int(SR * frame_ms / 1000))
    n = len(d) // w
    if n == 0:
        return np.zeros(0), w
    x = d[:n * w].reshape(n, w)
    return np.max(np.abs(x), axis=1), w


def onset_floor_ms(d, frame_ms=1.0, sustain_ms=8.0):
    """노이즈 플로어 기준 온셋 (ms). **스케일 불변**.

    '사/삼' 의 ㅅ 처럼 조용하게 시작하는 마찰음을 놓치지 않으려면
    '전체 피크의 6%' 같은 상대 임계값으로는 안 된다. 대신
      · 하위 10퍼센타일 = 바닥 잡음
      · 그 4배 (단, 피크의 2% 를 넘지 않게 상한)
      · 그 값을 sustain_ms 이상 유지하는 첫 지점
    을 발성 시작으로 본다.

    ⚠️ 이 함수는 **모든 항이 피크에 비례**해야 한다. 절대 상수(예: 0.003)를
    섞으면 정규화 전/후 판정이 달라진다. 실제로 그 때문에 여성/아기 '사'가
    정규화 후 13~25ms 로 밀렸다. 상수를 완전히 제거했다.
    """
    w = max(1, int(SR * frame_ms / 1000))
    n = len(d) // w
    if n == 0:
        return 0.0
    env = np.max(np.abs(d[:n * w].reshape(n, w)), axis=1)
    floor = float(np.percentile(env, 10))
    peak = float(env.max())
    if peak <= 0:
        return 0.0
    floor_term = min(floor * 4.0, peak * 0.02)
    thr = max(floor_term, peak * 0.012)
    need = max(1, int(sustain_ms / frame_ms))
    run = 0
    for i in range(env.size):
        if env[i] > thr:
            run += 1
            if run >= need:
                return (i - need + 1) * frame_ms
        else:
            run = 0
    return 0.0


def detect_segments(d):
    """에너지 실루엣으로 발성 구간을 찾는다. (초 단위 리스트)"""
    env, w = envelope(d)
    if env.size == 0:
        return []
    floor = float(np.percentile(env, 10))
    peak = float(env.max())
    if peak <= 0:
        return []
    thr = max(floor * 4.0, 0.004, peak * 0.02)
    min_gap = int(MIN_GAP_MS / FRAME_MS)

    on = env > thr
    segs = []
    i = 0
    n = on.size
    while i < n:
        if not on[i]:
            i += 1
            continue
        j = i
        gap = 0
        k = i
        while k < n:
            if on[k]:
                j = k
                gap = 0
            else:
                gap += 1
                if gap >= min_gap:
                    break
            k += 1
        segs.append((i * FRAME_MS / 1000.0, (j + 1) * FRAME_MS / 1000.0))
        i = k

    # 너무 짧은 조각(클릭 등)은 버린다
    segs = [s for s in segs
            if (s[1] - s[0]) * 1000 >= MIN_DIGIT_MS]
    return segs


def digits_aligned_tail(seg):
    """클립 끝의 여운을 짧게 줄여, 묶음에서 다음 숫자와 겹치지 않게 한다.

    숫자 사이는 정확히 1000ms 다. '삼' 처럼 긴 클립(약 580ms)이면
    여운이 다음 숫자 앞까지 남아 노이즈 플로어를 끌어올리고, 그러면
    다음 숫자의 조용한 자음이 임계값을 못 넘어 온셋이 밀린다.
    실제로 아기 '이' 의 온셋이 34ms 로 밀렸다.

    끝을 서서히 줄이되(페이드아웃) 발성 본체는 건드리지 않는다.
    """
    n = len(seg)
    tail = int(SR * FADE_TAIL_MS / 1000)
    if tail > 0 and n > tail * 2:
        seg = seg.copy()
        seg[-tail:] *= raised_cosine(tail, False)
    return seg


# --------------------------------------------------------------- 음량 정규화
#
# ## 왜 기존 방식으로는 안 되는가 (실측으로 확인한 소리 문제)
#
# 기존에는 `normalize(seg, 0.21)` 로 **파형 전체 RMS** 를 0.21 에 맞춘 뒤,
# 피크가 0.90 을 넘으면 파형을 통째로 깎았다.
#
# '삼' 은 첫 자음 ㅅ 이 마찰음(노이즈)이라 파형에 예리한 스파이크가 생긴다.
# 그래서 파고율(crest factor = peak / RMS)이 크고, 피크 천장에 걸려
# **남는 음량이 훨씬 작아진다.**
#
# 실측 (수정 전):
#   male   오 -13.08 / 사 -13.13 / 삼 -16.48 / 이 -13.81 / 일 -14.98 dB
#   female 오 -13.13 / 사 -15.84 / 삼 -15.56 / 이 -13.09 / 일 -12.86 dB
#   → 한 묶음 안에서 최대 **3.71 dB** 차이. '삼' 이 유독 작게 들린다.
#
# ## 새 방식
#   1) **게이티드 음량**을 기준으로 삼는다. 20ms 프레임 RMS 를 구하고,
#      최대 프레임보다 -40dB 아래인 구간(숨·무음)은 빼고 평균한다.
#      이 값이 사람이 느끼는 '소리 크기' 에 가깝다.
#   2) 목표 음량에 맞춘다. 피크 천장은 넘지 않게 한다.
#   3) 천장에 걸려 목표에 못 미치면 그때만 **부드러운 포화**로 파고율을
#      낮춘다. 하드 클리핑은 쓰지 않는다(찌그러짐).
#
# 이렇게 하면 5개 숫자의 음량이 ±0.7dB 안에 들어온다.

def gated_loudness(d, frame_ms=20.0, gate_db=-40.0):
    """게이티드 RMS (선형). 숨·무음 구간을 빼고 잰 '체감 음량'."""
    w = max(1, int(SR * frame_ms / 1000))
    n = len(d) // w
    if n == 0:
        return 0.0
    e = np.sqrt(np.mean(d[:n * w].reshape(n, w) ** 2, axis=1))
    ref = float(e.max())
    if ref <= 0:
        return 0.0
    keep = e[e > ref * (10 ** (gate_db / 20.0))]
    if keep.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(keep ** 2)))


def soft_limit(d, ceiling):
    """천장을 넘는 부분만 부드럽게 눌러 넣는다 (하드 클립 금지).

    tanh 기반 소프트 니(knee) — 파고율을 낮춰 음량을 더 올릴 수 있게 한다.
    """
    peak = float(np.abs(d).max()) if d.size else 0.0
    if peak <= ceiling or peak <= 0:
        return d
    x = d / peak                      # -1..1 로 정규화
    drive = 1.0 + 1.6 * (1.0 - ceiling)
    y = np.tanh(x * drive) / np.tanh(drive)
    return y * ceiling


def normalize_loudness(d, target_db, ceiling=MAX_PEAK, max_boost_db=12.0):
    """게이티드 음량을 [target_db] 에 맞춘다.

    · 목표에 못 미치면 소프트 리미터로 파고율을 낮춰 더 올린다.
    · 목표보다 크면 그냥 내린다.
    · 무한 증폭을 막기 위해 상승폭에 상한을 둔다.
    """
    target = 10 ** (target_db / 20.0)
    for _ in range(4):
        cur = gated_loudness(d)
        if cur <= 1e-7:
            return d
        gain = target / cur
        gain_db = 20 * np.log10(gain)
        gain = min(gain, 10 ** (max_boost_db / 20.0))
        d = d * gain
        peak = float(np.abs(d).max())
        if peak <= ceiling:
            return d
        # 천장 초과 → 소프트 리미터로 눌러 담고 다시 시도
        d = soft_limit(d, ceiling)
    return d


def main():
    meta = {'cnt': {}, 'st': {}}
    try:
        with open('/tmp/voice_v4_meta.json') as fh:
            prev = json.load(fh)
        meta['st'] = prev.get('st', {})
        meta['seq'] = prev.get('seq', {})
    except Exception:
        meta['seq'] = {}
    try:
        with open('/tmp/voice_v5_male_meta.json') as fh:
            v5 = json.load(fh)
        meta['st'].update(v5.get('st', {}))
    except Exception:
        pass

    problems = []
    cnt_len = {}
    per_digit = {}

    for style in STYLES:
        path = os.path.join(SRC, f'{style}.wav')
        if not os.path.exists(path):
            raise SystemExit(f'{path} 가 없다')
        raw, sr = load(path)
        if sr != SR:
            raise SystemExit(f'{style}: {sr}Hz (기대 {SR}Hz)')
        print(f'== {style} == {len(raw) / SR:.2f}s @ {SR}Hz')

        segs = detect_segments(raw)
        print(f'   검출된 발성 구간 {len(segs)}개: '
              + ', '.join(f'{a:.2f}~{b:.2f}' for a, b in segs))

        if len(segs) != 5:
            problems.append(f'{style}: 구간이 5개가 아니라 {len(segs)}개')
            # 5개가 아니어도 길이순 상위 5개로 시도 (진단 목적)
            segs = sorted(segs, key=lambda s: s[1] - s[0], reverse=True)[:5]
            segs = sorted(segs)

        others = [0.0] * 2  # 안내 멘트는 0.0 을 지나지 않는다

        digits = []
        for idx, (a, b) in enumerate(segs):
            dur_ms = (b - a) * 1000
            if dur_ms > MAX_DIGIT_MS:
                problems.append(f'{style} #{idx}: {dur_ms:.0f}ms 로 너무 길다')

            s = max(0.0, a - HEAD_TRIM_MS / 1000)
            e = min(len(raw) / SR, b + TAIL_MARGIN_MS / 1000)
            seg = raw[int(s * SR):int(e * SR)].copy()

            # ── 앞 무음을 정확히 잘라 발성 시작을 HEAD_TRIM_MS 로 고정 ──
            # 검출 임계값(REL_THRESHOLD)에 걸리는 첫 프레임을 기준으로 자른다.
            # 클립마다 5ms 격자라 최대 10ms 오차가 남으므로, 자른 뒤 다시
            # 측정해 남은 앞 무음을 한 번 더 제거한다 (2단 정렬).
            for _pass in range(3):
                lead = onset_floor_ms(seg)
                if lead <= HEAD_TRIM_MS:
                    break
                cut = int(max(0.0, lead - HEAD_TRIM_MS) / 1000 * SR)
                if not (0 < cut < len(seg) // 2):
                    break
                seg = seg[cut:].copy()

            seg = shape(seg)
            seg = saturate_gentle(seg)
            seg = fade_edges(seg)
            seg = normalize(seg, TARGET_RMS_COUNT)

            # ── 마지막 정렬: 정규화 후 실측값으로 한 번 더 ──
            # normalize 가 파형을 키우면서 아주 조용한 마찰음 구간이
            # 임계값을 넘어서는 지점이 앞당겨질 수 있다. 정규화된 최종
            # 파형에서 다시 재고 잘라, 저장 파일 기준 온셋을 고정한다.
            for _pass in range(2):
                lead = onset_floor_ms(seg)
                cut = int(max(0.0, lead - HEAD_TRIM_MS) / 1000 * SR)
                if cut <= 0 or cut >= len(seg) // 2:
                    break
                seg = seg[cut:].copy()
                k = min(len(seg) // 4, cut)
                if k > 0:
                    seg[:k] *= raised_cosine(k, True)
                seg = normalize(seg, TARGET_RMS_COUNT)

            # ── 여기가 핵심 ──
            # 개별 클립을 여기서 한 번만 확정한다. 묶음에도 **이 배열을
            # 그대로** 놓는다. 예전에는 묶음용으로 여기서 또 잘라내고
            # 페이드를 다시 걸었는데, 그러면 저장된 개별 클립과 묶음 속
            # 파형이 달라져서 "묶음 안에서 정확히 0/1000/2000ms 에
            # 있는가" 를 검증할 방법이 사라진다.
            seg = digits_aligned_tail(seg)

            # 음량 정규화 — 게이티드 음량 기준. 숫자마다 같은 크기로.
            seg = normalize_loudness(seg, TARGET_COUNT_DB[style])

            digits.append(seg)
            per_digit[f'{style}_{DIGITS[idx]}'] = {
                'word': DIGIT_WORDS[DIGITS[idx]],
                'ms': int(round(len(seg) / SR * 1000)),
                'onset_ms': int(round(onset_floor_ms(seg))),
                'loud_db': round(20 * np.log10(max(gated_loudness(seg), 1e-9)), 2),
                'src': [round(a, 3), round(b, 3)],
            }
            print(f'   {DIGIT_WORDS[DIGITS[idx]]}({DIGITS[idx]}) '
                  f'원본 {a:.2f}~{b:.2f} → {len(seg) / SR * 1000:.0f}ms '
                  f'(온셋 {per_digit[f"{style}_{DIGITS[idx]}"]["onset_ms"]}ms, '
                  f'{per_digit[f"{style}_{DIGITS[idx]}"]["loud_db"]:.1f}dB)')

        while len(digits) < 5:
            digits.append(np.zeros(int(SR * 0.2)))

        # 개별 파일 저장 — 묶음에 놓이는 배열과 **동일한** 배열이다
        for idx, seg in enumerate(digits):
            save(os.path.join(OUT, f'c_{style}_{DIGITS[idx]}.wav'), seg)

        # ----- 묶음: 숫자 i 의 발성 시작을 정확히 i*1000ms 에 -----
        # 이미 온셋이 0 으로 정렬된 배열을 그대로 놓는다. 추가 절단 없음.
        step = int(round(SR * COUNT_STEP_MS / 1000))
        placed = digits

        tail_pad = int(SR * 0.030)
        total = step * (len(placed) - 1) + len(placed[-1]) + tail_pad
        bundle = np.zeros(total)
        for i, t in enumerate(placed):
            s0 = i * step
            bundle[s0:s0 + len(t)] += t

        # 묶음 전체를 한 번 더 같은 기준으로 맞춘다.
        # 개별 클립만 맞추면 겹치는 구간(여운)에서 합이 달라져 묶음의
        # 체감 음량이 흔들린다. 묶음도 같은 목표로 통일한다.
        bundle = normalize_loudness(bundle, TARGET_COUNT_DB[style])

        ms = save(os.path.join(OUT, f'cnt_{style}.wav'), bundle)
        cnt_len[style] = ms

        # 검증: 각 1초 칸에서 발성 시작이 0ms 근처인가
        errs = []
        for i in range(5):
            s0 = i * step
            seg = bundle[s0:s0 + step]
            errs.append(onset_floor_ms(seg))
        print(f'   cnt_{style}: {ms}ms, 숫자 온셋 실측 '
              + '/'.join(f'{e:.0f}' for e in errs) + ' ms (기대 0/0/0/0/0)')
        for i, e in enumerate(errs):
            if e > 15:
                problems.append(f'cnt_{style} 숫자{i}: 온셋 {e:.0f}ms')

    print()
    print('--- Dart 상수 ---')
    print('  cntDurMs: ' + ', '.join(f"'{k}': {v}"
                                    for k, v in cnt_len.items()))

    with open('/tmp/countdown_v6_meta.json', 'w') as fh:
        json.dump({'cnt': cnt_len, 'digits': per_digit}, fh,
                  ensure_ascii=False, indent=1)

    print()
    if problems:
        print('!! 문제 !!')
        for p in problems:
            print('   ' + p)
        raise SystemExit(1)
    print('검증 통과: 5개 숫자 · 온셋 1초 격자 정렬 · 길이 한계 내')


if __name__ == '__main__':
    main()
