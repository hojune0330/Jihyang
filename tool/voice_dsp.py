#!/usr/bin/env python3
"""음성 후처리 DSP — '날카로움' 을 수치로 깎고 이어짐을 부드럽게 만든다.

## 왜 필요한가

elevenlabs 원본 음성을 그대로 쓰면 특정 구간에서 4kHz 이상 성분이
20% 를 넘는다. 귀로 들으면 '쇳소리', '찢어지는 소리' 로 느껴지고,
작은 폰 스피커에서는 더 심하게 들린다.

측정으로 확인한 값 (v3 원본):
    st_female_startRest  >4kHz 16.0%
    st_baby_startWork    >4kHz 10.8%
    st_baby_startRest    >4kHz 24.2%

## 처리 순서 (각 단계는 독립적이고 측정 가능하다)

  1) 럼블 제거   100Hz 하이패스 — 폰 스피커가 재생 못 하는 저역을 걷어내
                 남은 에너지를 목소리에 쓸 수 있게 한다.
  2) 디에서      시간에 따라 변하는 4~10kHz 감쇠. 'ㅅ/ㅆ/ㅊ' 처럼
                 순간적으로 치솟는 구간만 골라 누른다 (전체를 먹먹하게
                 만들지 않기 위해 정적 필터가 아니라 동적 필터를 쓴다).
  3) 소프트 새추레이션  tanh 로 살짝 눌러 저차 배음을 채운다.
                 고역을 깎으면 소리가 얇아지는데, 배음을 채우면
                 '부드럽지만 존재감 있는' 소리가 된다.
  4) 정규화      RMS 를 전부 같게.

ffmpeg 필터는 이 환경에서 신뢰할 수 없으므로 전부 numpy 로 처리한다.
"""
import numpy as np

SR_DEFAULT = 44100


def highpass(d, sr, cutoff=100.0):
    """1차(6dB/oct) 하이패스 — 위상 왜곡이 적고 계산이 단순하다."""
    if d.size == 0:
        return d
    rc = 1.0 / (2 * np.pi * cutoff)
    alpha = rc / (rc + 1.0 / sr)
    out = np.empty_like(d)
    prev_x = 0.0
    prev_y = 0.0
    for i in range(d.size):
        x = d[i]
        y = alpha * (prev_y + x - prev_x)
        out[i] = y
        prev_x = x
        prev_y = y
    return out


def highpass_fast(d, sr, cutoff=100.0):
    """하이패스의 벡터화 버전 (긴 신호용). 1차 IIR 을 순환식으로 푼다."""
    if d.size == 0:
        return d
    rc = 1.0 / (2 * np.pi * cutoff)
    alpha = rc / (rc + 1.0 / sr)
    # y[n] = alpha*(y[n-1] + x[n] - x[n-1])
    #     = alpha*x[n] + (-alpha)*x[n-1] + alpha*y[n-1]
    b = np.array([alpha, -alpha])
    a = np.array([1.0, -alpha])
    try:
        from scipy.signal import lfilter
        return lfilter(b, a, d)
    except Exception:
        return highpass(d, sr, cutoff)


def _smooth(x, k):
    """이동평균 — 제어 신호를 부드럽게 만들어 필터가 덜덜 떨지 않게 한다."""
    if k <= 1 or x.size == 0:
        return x
    k = min(k, x.size)
    ker = np.ones(k) / k
    return np.convolve(x, ker, mode='same')


def deess(d, sr, thresh_ratio=0.25, max_reduce_db=-9.0, cut=4000.0):
    """동적 디에서.

    신호를 4kHz 이상만 남긴 '고역 성분' 과 전체로 나눠,
    고역 비율이 임계값을 넘는 순간에만 감쇠를 건다.

    Args:
        thresh_ratio: 고역/전체 에너지 비율이 이 값을 넘으면 감쇠 시작
        max_reduce_db: 최대 감쇠량 (dB, 음수)
    """
    if d.size < 1024:
        return d

    # 고역만 추출 (4kHz 위)
    n = 1 << int(np.ceil(np.log2(d.size)))
    spec = np.fft.rfft(d, n)
    f = np.fft.rfftfreq(n, 1 / sr)
    hi_spec = spec.copy()
    hi_spec[f < cut] = 0.0
    hi = np.fft.irfft(hi_spec, n)[:d.size]

    # 프레임별 고역 비율
    win = max(64, int(sr * 0.010))
    hop = max(32, win // 2)
    frames = 1 + max(0, (d.size - win) // hop)
    if frames < 2:
        return d
    ratio = np.zeros(frames)
    for i in range(frames):
        s = i * hop
        tot = np.sqrt(np.mean(d[s:s + win] ** 2)) + 1e-9
        h = np.sqrt(np.mean(hi[s:s + win] ** 2))
        ratio[i] = h / tot

    # 임계 초과분에 비례한 감쇠 (0 ~ max_reduce_db)
    over = np.clip((ratio - thresh_ratio) / max(1e-6, 1.0 - thresh_ratio), 0, 1)
    gain_db = over * max_reduce_db
    gain_db = _smooth(gain_db, 5)
    gain = 10 ** (gain_db / 20.0)

    # 프레임 → 샘플 보간
    centers = np.arange(frames) * hop + win / 2
    g = np.interp(np.arange(d.size), centers, gain)

    # 고역만 감쇠시킨다 (전체를 먹먹하게 만들지 않는다)
    return d - hi * (1.0 - g)


def tilt_high(d, sr, shelf_start=5000.0, shelf_gain_db=-4.0,
              lpf_hz=11000.0):
    """고역 셸프 + 완만한 로우패스.

    디에서로 못 잡는 지속적인 고역 '시원찮음' 을 정리한다.
    """
    if d.size < 1024:
        return d
    n = 1 << int(np.ceil(np.log2(d.size)))
    spec = np.fft.rfft(d, n)
    f = np.fft.rfftfreq(n, 1 / sr)

    gain = np.ones(f.size)
    # 셸프: shelf_start 부터 1옥타브에 걸쳐 shelf_gain_db 까지
    band = (f >= shelf_start) & (f < shelf_start * 2)
    if band.any():
        t = (f[band] - shelf_start) / (shelf_start * 2 - shelf_start)
        gain[band] = 10 ** (shelf_gain_db * t / 20.0)
    gain[f >= shelf_start * 2] = 10 ** (shelf_gain_db / 20.0)

    # 로우패스: lpf_hz 위는 부드럽게 굴린다
    hi = f > lpf_hz
    if hi.any():
        gain[hi] *= 1.0 / (1.0 + (f[hi] / lpf_hz - 1.0) * 2.0)

    return np.fft.irfft(spec * gain, n)[:d.size]


def saturate(d, drive=1.35, mix=0.55):
    """소프트 새추레이션 — 고역을 깎아 얇아진 소리에 배음을 채운다."""
    if d.size == 0:
        return d
    peak = float(np.max(np.abs(d)))
    if peak < 1e-6:
        return d
    x = d / peak
    sat = np.tanh(x * drive) / np.tanh(drive)
    return (x * (1.0 - mix) + sat * mix) * peak


def polish(d, sr=SR_DEFAULT):
    """음성 클립 표준 후처리 파이프라인."""
    y = highpass_fast(d, sr, 100.0)
    y = deess(y, sr, thresh_ratio=0.22, max_reduce_db=-10.0, cut=4000.0)
    y = tilt_high(y, sr, shelf_start=5000.0, shelf_gain_db=-4.5,
                  lpf_hz=11000.0)
    y = saturate(y, drive=1.35, mix=0.55)
    return y


def hf_ratio(d, sr, cut=4000.0):
    if d.size < 512:
        return 0.0
    spec = np.abs(np.fft.rfft(d * np.hanning(len(d)))) ** 2
    f = np.fft.rfftfreq(len(d), 1 / sr)
    tot = float(spec.sum())
    return float(spec[f > cut].sum() / tot) if tot > 1e-12 else 0.0
