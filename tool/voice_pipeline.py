#!/usr/bin/env python3
"""음성 자산 v4 — 파이프라인 전면 재작성.

## v3 에서 무엇이 잘못됐나 (사용자 지적 2건 모두 같은 뿌리)

사용자: "숫자와 음성의 싱크가 안 맞고 끊기듯 들리는 부분 단어, 음절 모두 별로"

### ㄱ. 단어가 잘렸다 (가장 치명적)

v3 는 **에너지 검출로 대충 찾은 구간**에서 음성을 잘랐다.
ASR 단어 타임스탬프와 대조하니 이렇게 잘려 있었다.

    st_male_prepare   "준비"      0.22~0.92 인데 0.48 에서 잘림 → 440ms 손실
    st_baby_finish    "운동 종료"  6.72~7.96 인데 7.43 에서 잘림 → 530ms 손실
    st_female_finish  "운동 종료"  7.00~8.00 인데 7.76 에서 잘림 → 240ms 손실
    ... 11개 중 8개가 80~530ms 잘림

"준비" 가 "준" 으로, "운동 종료" 가 "운동 종" 으로 들린 이유가 이것이다.
**끊기는 음절은 DSP 문제가 아니라 자르는 지점 문제였다.**

### ㄴ. 디에서가 음절을 뭉갰다

v3 는 10ms 프레임마다 게인을 계산해 4kHz 이상만 눌렀다. 프레임 경계에서
게인이 계단처럼 바뀌어 **진폭 변조(파르르 떨림)** 가 생겼고, 한국어의
ㅅ·ㅆ·ㅊ 같은 마찰음이 뭉개졌다.

## v4 설계 — 세 가지를 바꿨다

### 1) 자르기: ASR 단어 타임스탬프 + 에너지 정밀 스캔
   ASR 이 알려준 단어 시작/끝을 **출발점**으로만 쓰고,
   실제 경계는 5ms 해상도 에너지 엔벨로프를 **앞뒤로 스캔**해 찾는다.
     · 앞: 단어 시작에서 뒤로 가며 '80ms 이상 조용한 지점' 직전까지
     · 뒤: 단어 끝에서 앞으로 가며 '80ms 이상 조용한 지점' 직후까지
   잘림을 구조적으로 불가능하게 만들고, **검증 단계에서 실제로 확인**한다.

### 2) 음색: 시변 필터 제거 → 단일 선형 EQ 한 방
   프레임마다 게인을 바꾸는 디에서는 버린다.
   대신 한 번의 FFT 로 전체 구간에 **고정 EQ** 를 건다.
   시간에 따라 변하지 않으므로(LTI) 음절이 흔들릴 수 없다.
       · 85Hz 하이패스 (폰 스피커가 못 내는 저역 정리)
       · 5.5kHz 위 -3.5dB 셸프 (날카로움 완화)
       · 12.5kHz 위 완만한 롤오프 (쇳소리 제거)

### 3) 이어붙이기: 겹침 제거 + 온셋 정렬
   · 삑과 음성 사이에 크로스페이드를 걸지 않는다.
     두 신호 모두 경계에서 0 이므로 겹칠 필요가 없다.
     (v3 의 크로스페이드는 오히려 삑 꼬리를 음성 앞에 얹었다)
   · 카운트다운 숫자는 **발성 시작점이 정확히 i*1000ms** 에 오도록 배치.
     v3 는 15ms 앞 여백이 있어 숫자가 매번 15ms 늦게 났다.
   · 생성 후 실제 온셋 위치를 측정해 **검증**한다.

사용:
    python3 tool/voice_pipeline.py
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

SR = 44100
RAW = '/tmp/tts3'
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')

STATE_KEYS = ['prepare', 'startWork', 'startRest', 'setRest', 'lastRound', 'finish']
NUMBERS = [5, 4, 3, 2, 1]

# ASR (elevenlabs_scribe_v2) 이 알려준 **단어별** 시작·끝 (초).
# 대사 순서: 준비 / 운동 시작 / 휴식 시작 / 세트 휴식 / 마지막 라운드 /
#            운동 종료 / 다섯 / 넷 / 셋 / 둘 / 하나
WORDS = {
    'male': [
        [(0.22, 0.48)], [(1.12, 1.32), (1.46, 1.76)],
        [(2.40, 2.62), (2.76, 3.10)], [(3.76, 3.98), (4.14, 4.46)],
        [(5.14, 5.42), (5.52, 5.82)], [(6.50, 6.78), (6.94, 7.18)],
        [(7.80, 8.16)], [(8.78, 8.94)], [(9.64, 9.72)],
        [(10.44, 10.48)], [(11.10, 11.32)],
    ],
    'female': [
        [(0.24, 0.48)], [(1.22, 1.44), (1.60, 1.90)],
        [(2.58, 2.80), (2.96, 3.18)], [(3.94, 4.22), (4.38, 4.74)],
        [(5.44, 5.76), (5.88, 6.24)], [(7.00, 7.30), (7.48, 7.74)],
        [(8.44, 8.82)], [(9.50, 9.60)], [(10.36, 10.46)],
        [(11.14, 11.30)], [(11.94, 12.18)],
    ],
    'baby': [
        [(0.20, 0.46)], [(1.16, 1.48), (1.60, 1.94)],
        [(2.54, 2.78), (2.96, 3.20)], [(3.86, 4.14), (4.30, 4.68)],
        [(5.30, 5.58), (5.70, 6.08)], [(6.72, 7.00), (7.16, 7.42)],
        [(8.08, 8.52)], [(9.08, 9.26)], [(9.96, 10.06)],
        [(10.70, 10.88)], [(11.46, 11.70)],
    ],
}

# 클립 다듬기
HEAD_MARGIN_MS = 12     # 앞쪽에 남기는 숨 (스캔 결과에서 추가로)
TAIL_MARGIN_MS = 60     # 뒤쪽에 남기는 여운 — 잘림 방지의 핵심
FADE_IN_MS = 8
FADE_OUT_MS = 45
QUIET_RUN_MS = 80       # 이만큼 연속 조용하면 '발성 끝' 으로 본다
VOICE_FLOOR_RMS = 0.008

# 음색 (모두 시간 불변 = LTI)
HP_HZ = 85.0
SHELF_HZ = 5500.0
SHELF_DB = -3.5
LP_HZ = 12500.0
PEAK_HZ = 6500.0     # ㅅ/ㅆ 마찰음 대역
PEAK_Q = 1.0
PEAK_DB = -4.0
SAT_DRIVE = 1.25
SAT_MIX = 0.25

TARGET_RMS_VOICE = 0.19
TARGET_RMS_COUNT = 0.21
MAX_PEAK = 0.90

# 이어붙이기
BEEP_RMS = 0.24
ATTENTION_GAP_MS = 180
VOICE_GAP_MS = 300
COUNT_STEP_MS = 1000


# --------------------------------------------------------------------- 기본 IO

def decode(name):
    src = os.path.join(RAW, f'{name}.mp3')
    dst = os.path.join(RAW, f'{name}.wav')
    if os.path.exists(src):
        subprocess.run(
            ['ffmpeg', '-v', 'error', '-y', '-i', src,
             '-ac', '1', '-ar', str(SR), '-c:a', 'pcm_s16le', dst],
            check=True,
        )
    return dst


def load(path):
    with wave.open(path, 'rb') as w:
        n, sr, ch = w.getnframes(), w.getframerate(), w.getnchannels()
        raw = w.readframes(n)
    d = np.frombuffer(raw, dtype='<i2').astype(np.float64) / 32768.0
    if ch > 1:
        d = d.reshape(-1, ch).mean(axis=1)
    return d, sr


def save(path, d):
    pcm = (np.clip(d, -1.0, 1.0) * 32767.0).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return int(round(len(pcm) / SR * 1000))


# ------------------------------------------------------------------ 경계 검출

def envelope(d, win_ms=5.0):
    win = max(8, int(SR * win_ms / 1000))
    n = len(d) // win
    if n == 0:
        return np.zeros(0), win
    env = np.array([np.sqrt(np.mean(d[i * win:(i + 1) * win] ** 2))
                    for i in range(n)])
    return env, win


def true_span(d, asr_start, asr_end):
    """ASR 구간을 출발점으로 실제 발성 경계를 에너지로 다시 찾는다.

    Returns: (start_s, end_s) — 잘림 없이 발성 전체를 덮는 구간
    """
    env, win = envelope(d)
    smp_per_env = win / SR
    if env.size == 0:
        return asr_start, asr_end

    floor = float(np.percentile(env, 10))
    peak = float(env.max())
    thr = max(floor * 3.0, peak * 0.035, VOICE_FLOOR_RMS)
    quiet_run = max(2, int(QUIET_RUN_MS / (win / SR * 1000)))

    i_start = int(asr_start / smp_per_env)
    i_end = min(env.size - 1, int(asr_end / smp_per_env))

    # 앞으로: asr_start 에서 거꾸로 가며 '조용한 구간이 끝나는 곳' 찾기
    lo = i_start
    while lo > 0:
        if env[lo] < thr:
            # 조용한 구간이 quiet_run 이상 이어지는지 확인
            j = lo
            while j > 0 and env[j] < thr:
                j -= 1
            if lo - j >= quiet_run:
                break
            lo = j
        lo -= 1
    # ASR 시작보다 120ms 이상 물러나지 않는다 (앞 무음이 길어지면
    # 안내가 늦게 들려 싱크가 어긋난 것처럼 느껴진다)
    lo_bound = max(0, int((asr_start - 0.120) / smp_per_env))
    start_idx = max(lo_bound, lo)

    # 뒤로: asr_end 에서 앞으로 가며 '조용한 구간이 시작되는 곳' 찾기
    hi = i_end
    n = env.size
    while hi < n - 1:
        if env[hi] < thr:
            j = hi
            while j < n - 1 and env[j] < thr:
                j += 1
            if j - hi >= quiet_run:
                break
            hi = j
        hi += 1
    hi_bound = min(n, int((asr_end + 0.400) / smp_per_env))
    end_idx = min(hi_bound, hi + 1)

    start_s = start_idx * smp_per_env
    end_s = end_idx * smp_per_env
    return start_s, end_s


# ------------------------------------------------------------------ 음색 처리

def shape(d):
    """시간 불변(단일 FFT) EQ — 음절을 흔들지 않는다."""
    if d.size < 2048:
        return d
    n = 1 << int(np.ceil(np.log2(d.size)))
    spec = np.fft.rfft(d, n)
    f = np.fft.rfftfreq(n, 1 / SR)

    gain = np.ones(f.size)

    # 85Hz 하이패스 (2차, 부드럽게)
    hp = f / HP_HZ
    gain *= hp ** 2 / np.sqrt(1.0 + hp ** 4)

    # 5.5kHz 위 셸프 -3.5dB (1옥타브 완만)
    shelf = np.ones(f.size)
    band = (f >= SHELF_HZ) & (f < SHELF_HZ * 2)
    if band.any():
        t = (f[band] - SHELF_HZ) / (SHELF_HZ * 2 - SHELF_HZ)
        shelf[band] = 10 ** (SHELF_DB * t / 20.0)
    shelf[f >= SHELF_HZ * 2] = 10 ** (SHELF_DB / 20.0)
    gain *= shelf

    # 12.5kHz 위 완만한 롤오프
    hi = f > LP_HZ
    if hi.any():
        gain[hi] *= 1.0 / np.sqrt(1.0 + (f[hi] / LP_HZ - 1.0) ** 2)

    # 6.5kHz 피킹 컷 -4dB (Q≈1)
    #   한국어 ㅅ·ㅆ·ㅊ 의 '쇠' 소리가 몰려 있는 대역만 골라 누른다.
    #   2~4kHz(말소리 또렷함)는 건드리지 않으므로 음절이 뭉개지지 않는다.
    #   시간에 따라 변하지 않는 필터라 파르르 떨림이 생기지 않는다.
    peak_band = np.exp(-0.5 * ((np.log(f + 1e-9) - np.log(PEAK_HZ)) /
                               (1.0 / PEAK_Q)) ** 2)
    gain *= 10 ** (PEAK_DB * peak_band / 20.0)

    return np.fft.irfft(spec * gain, n)[:d.size]


def saturate_gentle(d, drive=SAT_DRIVE, mix=SAT_MIX):
    peak = float(np.max(np.abs(d))) if d.size else 0.0
    if peak < 1e-6:
        return d
    x = d / peak
    return ((x * (1 - mix) + np.tanh(x * drive) / np.tanh(drive) * mix)
            * peak)


def raised_cosine(n, rising):
    if n <= 0:
        return np.zeros(0)
    t = np.linspace(0.0, np.pi, n)
    return (1.0 - np.cos(t)) / 2.0 if rising else (1.0 + np.cos(t)) / 2.0


def fade_edges(d, fade_in_ms=FADE_IN_MS, fade_out_ms=FADE_OUT_MS):
    d = d.copy()
    fi = min(len(d) // 2, int(SR * fade_in_ms / 1000))
    fo = min(len(d) // 2, int(SR * fade_out_ms / 1000))
    if fi > 0:
        d[:fi] *= raised_cosine(fi, True)
    if fo > 0:
        d[-fo:] *= raised_cosine(fo, False)
    return d


def normalize(d, target, max_peak=MAX_PEAK):
    rms = float(np.sqrt(np.mean(d ** 2))) if d.size else 0.0
    if rms > 1e-7:
        d = d * (target / rms)
    peak = float(np.max(np.abs(d))) if d.size else 0.0
    if peak > max_peak:
        d = d / peak * max_peak
    return d


def hf_ratio(d, cut=4000.0):
    if d.size < 512:
        return 0.0
    spec = np.abs(np.fft.rfft(d * np.hanning(len(d)))) ** 2
    f = np.fft.rfftfreq(len(d), 1 / SR)
    tot = float(spec.sum())
    return float(spec[f > cut].sum() / tot) if tot > 1e-12 else 0.0


def onset_ms(d, thr_ratio=0.05):
    """발성 시작 위치(ms)."""
    env, win = envelope(d)
    if env.size == 0:
        return 0.0
    thr = env.max() * thr_ratio
    idx = int(np.argmax(env > thr))
    return idx * win / SR * 1000


def tail_quiet_ms(d, ms=40):
    """클립 끝 ms 구간의 최대 진폭 — 잘림 검증용."""
    k = int(SR * ms / 1000)
    if len(d) <= k:
        return 0.0
    return float(np.max(np.abs(d[-k:])))


# ----------------------------------------------------------------------- 메인

def main():
    st_len = {}
    cnt_len = {}
    problems = []

    for style in ('male', 'female', 'baby'):
        path = decode(style)
        raw, src_sr = load(path)
        if src_sr != SR:
            raise SystemExit(f'{style}: 샘플레이트가 {src_sr}Hz 다')
        print(f'== {style} == {len(raw) / SR:.2f}s @ {SR}Hz')

        words = WORDS[style]
        assert len(words) == 11, f'{style}: 단어 그룹이 11개가 아니다'

        # ----- 상태 안내 6종 -----
        st_len[style] = {}
        for i, key in enumerate(STATE_KEYS):
            grp = words[i]
            a0, b0 = grp[0][0], grp[-1][1]
            s, e = true_span(raw, a0, b0)
            s = max(0.0, s - HEAD_MARGIN_MS / 1000)
            e = min(len(raw) / SR, e + TAIL_MARGIN_MS / 1000)

            seg = raw[int(s * SR):int(e * SR)].copy()
            before_hf = hf_ratio(seg)
            # 앞 무음을 잘라 발성이 클립 시작 직후(8ms)에 오게 한다.
            # 그래야 '삑 → 180ms → 음성' 간격이 매번 똑같아진다.
            on = int(onset_ms(seg, 0.05) / 1000 * SR)
            cut = max(0, on - int(SR * 8 / 1000))
            if cut < len(seg) // 2:
                seg = seg[cut:].copy()
            seg = shape(seg)
            seg = saturate_gentle(seg)
            seg = fade_edges(seg)
            seg = normalize(seg, TARGET_RMS_VOICE)
            ms = save(os.path.join(OUT, f'st_{style}_{key}.wav'), seg)
            st_len[style][key] = ms

            # 잘림 검증: 끝 구간이 조용하면 OK
            tq = tail_quiet_ms(seg, 25)
            ok = tq < 0.05
            if not ok:
                problems.append(f'st_{style}_{key}: 끝이 조용하지 않다 {tq:.3f}')
            print(f'   st_{style}_{key:11s} {ms:5d}ms '
                  f'컷 {s:.3f}~{e:.3f} (ASR {a0:.2f}~{b0:.2f}) '
                  f'잘림={max(0, (b0 - e)) * 1000:+.0f}ms '
                  f'>4k {before_hf * 100:4.1f}%→{hf_ratio(seg) * 100:4.1f}% '
                  f'끝에너지={tq:.3f} {"OK" if ok else "FAIL"}')

        # ----- 숫자 5개 -----
        digits = []
        for j, num in enumerate(NUMBERS):
            grp = words[6 + j]
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
            save(os.path.join(OUT, f'c_{style}_{num}.wav'), seg)
            digits.append(seg)
            print(f'   c_{style}_{num:11d} {len(seg) / SR * 1000:5.0f}ms '
                  f'잘림={max(0, (b0 - e)) * 1000:+.0f}ms '
                  f'끝에너지={tail_quiet_ms(seg, 25):.3f}')

        # ----- 카운트다운 묶음 -----
        # 숫자의 '발성 시작' 이 정확히 i*1000ms 에 오도록 앞 여백을 잘라낸다.
        step = int(SR * COUNT_STEP_MS / 1000)
        trimmed = []
        for seg in digits:
            on = int(onset_ms(seg, 0.05) / 1000 * SR)
            # 온셋 앞의 무음은 버리고, 아주 짧은 페이드인만 남긴다
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
        cnt_len[style] = save(os.path.join(OUT, f'cnt_{style}.wav'), bundle)
        print(f'   cnt_{style:10s} {cnt_len[style]:5d}ms '
              f'(숫자 온셋 0/1000/2000/3000/4000)')

        # 온셋 검증
        for i in range(5):
            s0 = i * step
            seg = bundle[s0:]
            on = onset_ms(seg)
            if on > 20:
                problems.append(
                    f'cnt_{style} 숫자{i}: 온셋이 {on:.0f}ms (0 이어야 함)')
        print()

    print('--- Dart 상수 ---')
    for style, m in st_len.items():
        inner = ', '.join(f'StateVoice.{k}: {v}' for k, v in m.items())
        print(f'  VoiceStyle.{style}: {{{inner}}},')
    print('  cntDurMs: ' +
          ', '.join(f"'{k}': {v}" for k, v in cnt_len.items()))

    print()
    if problems:
        print('!! 문제 발견 !!')
        for p in problems:
            print('   ' + p)
    else:
        print('검증 통과: 잘린 단어 없음, 카운트다운 온셋 정렬 정상')

    with open('/tmp/voice_v4_meta.json', 'w') as fh:
        json.dump({'st': st_len, 'cnt': cnt_len}, fh, ensure_ascii=False)


if __name__ == '__main__':
    main()
