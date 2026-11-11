import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/services/audio_coach.dart';

/// 새로 만든 카운트다운(오·사·삼·이·일) 검증.
///
/// 사용자 지시: "카운트다운 하는 거 처음부터 다시 만들어
///              오,사,삼,이,일 로 각각 처음부터 다시 만들어."
///
/// 숫자를 읽는 말이 '다섯·넷·셋·둘·하나' 에서 '오·사·삼·이·일' 로
/// 바뀌었으므로, 길이표·묶음·격자 정렬을 전부 새로 확인한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// WAV 를 (모노 float 리스트, 샘플레이트) 로 읽는다.
  /// 헤더 크기를 가정하지 않고 'data' 청크를 찾아 읽는다.
  (Float32List, int) readWav(File f) {
    final bytes = f.readAsBytesSync();
    final bd = ByteData.sublistView(bytes);
    var pos = 12;
    var sr = 44100;
    var bits = 16;
    var ch = 1;
    var dataOff = -1;
    var dataLen = 0;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = bd.getUint32(pos + 4, Endian.little);
      if (id == 'fmt ') {
        ch = bd.getUint16(pos + 10, Endian.little);
        sr = bd.getUint32(pos + 12, Endian.little);
        bits = bd.getUint16(pos + 22, Endian.little);
      } else if (id == 'data') {
        dataOff = pos + 8;
        dataLen = size;
        break;
      }
      pos += 8 + size + (size.isOdd ? 1 : 0);
    }
    if (dataOff < 0) {
      // 'data' 를 못 찾으면 스캔으로 재시도
      for (var i = 0; i + 8 <= bytes.length - 4; i++) {
        if (bytes[i] == 0x64 &&
            bytes[i + 1] == 0x61 &&
            bytes[i + 2] == 0x74 &&
            bytes[i + 3] == 0x61) {
          dataOff = i + 8;
          dataLen = bd.getUint32(i + 4, Endian.little);
          break;
        }
      }
    }
    expect(dataOff, greaterThan(0), reason: '${f.path}: data 청크 없음');
    expect(bits, 16, reason: '${f.path}: 16bit 가 아니다');

    final n = (dataLen ~/ 2) ~/ ch;
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(dataOff + i * 2 * ch, Endian.little) / 32768.0;
    }
    return (out, sr);
  }

  /// 발성 시작을 찾는다 (ms).
  ///
  /// ⚠️ 단순 `peak * 비율` 임계값을 쓰면 안 된다.
  /// 어미 여운이 크게 남은 클립은 대표 peak 가 커져서, 바로 뒤 숫자의
  /// 조용한 자음(ㅅ·ㅇ)이 임계값을 못 넘고 수십 ms 늦게 잡힌다.
  /// 실제로 아기 "사" 가 65ms 로 밀려 오탐이 났다.
  ///
  /// 그래서 tool/countdown_pipeline.py 의 `onset_floor_ms` 와 **같은 식**을 쓴다.
  ///  · 하위 10퍼센타일 = 바닥 잡음
  ///  · 그 4배 (단, 피크의 2% 상한)
  ///  · 피크의 1.2% 와 비교해 큰 쪽
  ///  · 그 값을 sustainMs 이상 연속으로 넘는 첫 지점
  int onsetMs(
    Float32List d,
    int sr, {
    double frameMs = 1.0,
    double sustainMs = 8.0,
  }) {
    final w = (sr * frameMs / 1000).round();
    final n = d.length ~/ w;
    if (n == 0) return -1;
    final env = Float64List(n);
    for (var i = 0; i < n; i++) {
      var m = 0.0;
      for (var k = 0; k < w; k++) {
        final a = d[i * w + k].abs();
        if (a > m) m = a;
      }
      env[i] = m;
    }
    final sorted = Float64List.fromList(env)..sort();
    final floor = sorted[((n - 1) * 0.10).round()];
    var peak = 0.0;
    for (final v in env) {
      if (v > peak) peak = v;
    }
    if (peak <= 0) return -1;
    final floorTerm = floor * 4.0 < peak * 0.02 ? floor * 4.0 : peak * 0.02;
    final thr = floorTerm > peak * 0.012 ? floorTerm : peak * 0.012;
    final need = (sustainMs / frameMs).round().clamp(1, n);
    var run = 0;
    for (var i = 0; i < n; i++) {
      if (env[i] > thr) {
        run++;
        if (run >= need) return ((i - need + 1) * frameMs).round();
      } else {
        run = 0;
      }
    }
    return -1;
  }

  group('A. 숫자 클립 15개(3목소리 x 오사삼이일)가 모두 있다', () {
    test('c_<style>_5/4/3/2/1 이 존재하고 100ms 이상이다', () {
      for (final style in VoiceStyle.values) {
        for (final n in [5, 4, 3, 2, 1]) {
          final f = File('assets/audio/c_${style.assetKey}_$n.wav');
          expect(
            f.existsSync(),
            isTrue,
            reason: '${f.path} 가 없다 (오·사·삼·이·일 재생성 필요)',
          );
          final (d, sr) = readWav(f);
          expect(sr, 44100, reason: '${f.path}: 44100Hz 여야 한다');
          final ms = d.length / sr * 1000;
          expect(ms, greaterThan(100), reason: '${f.path}: ${ms.round()}ms');
          expect(ms, lessThan(900), reason: '${f.path}: 너무 길다 ${ms.round()}ms');
        }
      }
    });
  });

  group('B. 카운트다운 묶음이 오·사·삼·이·일 5개를 1초 격자에 담는다', () {
    test('개별 클립이 묶음의 정확히 0/1000/2000/3000/4000ms 에 들어 있다', () {
      // 이게 이번 리빌드의 가장 강한 검증이다.
      // 파이프라인은 개별 클립을 한 번만 만들고, 그 **같은 배열**을
      // 묶음의 i*1000ms 지점에 놓는다. 그러므로 묶음의 그 구간을 잘라
      // 개별 파일과 비교하면 완전히 같아야 한다. 1샘플이라도 밀리면 실패.
      for (final style in VoiceStyle.values) {
        final key = style.assetKey;
        final (bundle, sr) = readWav(File('assets/audio/cnt_v7_$key.wav'));
        final step = (sr * countStepMs / 1000).round();

        for (var i = 0; i < 5; i++) {
          final n = 5 - i;
          final (clip, csr) = readWav(File('assets/audio/c_${key}_$n.wav'));
          expect(csr, sr, reason: '$key/$n: 샘플레이트가 다르다');

          final start = i * step;
          expect(
            start + clip.length,
            lessThanOrEqualTo(bundle.length),
            reason: '$key/$n: 묶음이 짧아 ${start + clip.length} 샘플을 담지 못한다',
          );

          var maxDiff = 0.0;
          var firstBad = -1;
          for (var k = 0; k < clip.length; k++) {
            final diff = (bundle[start + k] - clip[k]).abs();
            if (diff > maxDiff) maxDiff = diff;
            if (diff > 0.002 && firstBad < 0) firstBad = k;
          }
          expect(
            maxDiff,
            lessThan(0.002),
            reason:
                '$key/$n: 묶음 $start 샘플 지점이 개별 클립과 다르다 '
                '(최대차 $maxDiff, 첫 불일치 샘플 $firstBad = '
                '${(firstBad * 1000 / sr).toStringAsFixed(1)}ms)',
          );
        }
      }
    });

    test('묶음 안에서 숫자 발성도 0/1000/2000/3000/4000ms 에서 시작한다', () {
      for (final style in VoiceStyle.values) {
        final key = style.assetKey;
        final (d, sr) = readWav(File('assets/audio/cnt_v7_$key.wav'));
        final step = (sr * countStepMs / 1000).round();

        // 1초 칸마다 따로 재야 한다. 이웃 숫자의 여운이 섞이면
        // 노이즈 플로어가 올라가 온셋이 밀리기 때문이다.
        for (var i = 0; i < 5; i++) {
          final window = Float32List.sublistView(
            d,
            i * step,
            (i * step + step).clamp(0, d.length),
          );
          final on = onsetMs(window, sr);
          expect(
            on,
            inInclusiveRange(0, 12),
            reason: '$key 숫자${5 - i}: 1초 칸 안 온셋 ${on}ms',
          );
        }
      }
    });
  });

  group('C. 길이표가 실제 파일과 일치한다', () {
    test('cntDurMs 가 실제 묶음 길이와 25ms 이내로 맞는다', () {
      for (final style in VoiceStyle.values) {
        final table = cntDurMs[style.assetKey]!;
        final (d, sr) = readWav(
          File('assets/audio/cnt_v7_${style.assetKey}.wav'),
        );
        final actual = (d.length / sr * 1000).round();
        expect(
          (actual - table).abs(),
          lessThan(25),
          reason: '${style.assetKey}: 표=$table, 실제=$actual',
        );
      }
    });

    test('묶음이 5번째 숫자(4000ms)를 담을 만큼 길다', () {
      for (final style in VoiceStyle.values) {
        final (d, sr) = readWav(
          File('assets/audio/cnt_v7_${style.assetKey}.wav'),
        );
        final ms = d.length / sr * 1000;
        expect(
          ms,
          greaterThan(countBundleLastMs + 200),
          reason:
              '${style.assetKey}: ${ms.round()}ms 는 짧다 '
              '(4000ms 지점 숫자 + 여운 필요)',
        );
      }
      expect(countBundleLastMs, 4000);
      expect(countStepMs, 1000);
    });
  });

  group('D. 개별 숫자 클립이 앞 무음 없이 바로 발성된다', () {
    test('15개 클립 전부 onset <= 12ms', () {
      for (final style in VoiceStyle.values) {
        for (final n in [5, 4, 3, 2, 1]) {
          final (d, sr) = readWav(
            File('assets/audio/c_${style.assetKey}_$n.wav'),
          );
          final on = onsetMs(d, sr);
          expect(
            on,
            inInclusiveRange(0, 12),
            reason: '${style.assetKey}/$n: onset=${on}ms (앞 무음이 남아 있다)',
          );
        }
      }
    });
  });

  // ==========================================================================
  // E. 소리 크기가 고르다
  //
  // ## 이 그룹이 막는 실제 결함 (실측으로 확인)
  //
  // 기존 파이프라인은 파형 전체 RMS 를 목표에 맞춘 뒤 피크가 0.90 을 넘으면
  // 파형을 통째로 깎았다. '삼' 은 첫 자음 ㅅ 이 마찰음이라 파고율이 커서
  // 많이 깎였고, 그 결과 한 묶음 안에서 음량이 최대 **3.71dB** 벌어졌다.
  //   male   오 -13.08 / 사 -13.13 / 삼 -16.48 / 이 -13.81 / 일 -14.98 dB
  //   female 오 -13.13 / 사 -15.84 / 삼 -15.56 / 이 -13.09 / 일 -12.86 dB
  // '삼' 만 유독 작게 들리는 원인이었다.
  //
  // 또 카운트다운을 -13.0dB 로 통일하니 남성은 안내(-15.59dB)보다
  // 2.6dB 크게 터졌다. 사용자는 한 목소리만 들으므로 **같은 목소리 안에서**
  // 안내와 카운트다운이 같아야 한다.
  // ==========================================================================

  /// 게이티드 음량(dB). 20ms 프레임 RMS 에서 최대보다 -40dB 아래(숨·무음)를
  /// 빼고 평균한다. 사람이 느끼는 '소리 크기' 에 가깝다.
  double gatedDb(Float32List d, int sr) {
    final w = (sr * 0.020).round();
    final n = d.length ~/ w;
    if (n == 0) return -99;
    final e = Float64List(n);
    for (var i = 0; i < n; i++) {
      var acc = 0.0;
      for (var k = 0; k < w; k++) {
        final v = d[i * w + k];
        acc += v * v;
      }
      e[i] = sqrt(acc / w);
    }
    var ref = 0.0;
    for (final v in e) {
      if (v > ref) ref = v;
    }
    if (ref <= 0) return -99;
    final gate = ref * pow(10, -40.0 / 20.0);
    var acc = 0.0;
    var cnt = 0;
    for (final v in e) {
      if (v > gate) {
        acc += v * v;
        cnt++;
      }
    }
    if (cnt == 0) return -99;
    final r = sqrt(acc / cnt);
    return r <= 0 ? -99 : 20 * log(r) / ln10;
  }

  group('E. 소리 크기가 고르다', () {
    test('한 목소리 안에서 5개 숫자 음량 편차가 1.0dB 이내다', () {
      for (final style in VoiceStyle.values) {
        final vals = <int, double>{};
        for (final n in [5, 4, 3, 2, 1]) {
          final (d, sr) = readWav(
            File('assets/audio/c_${style.assetKey}_$n.wav'),
          );
          vals[n] = gatedDb(d, sr);
        }
        final keys = vals.keys.toList();
        final lo = keys.map((k) => vals[k]!).reduce(min);
        final hi = keys.map((k) => vals[k]!).reduce(max);
        final spread = hi - lo;
        expect(
          spread,
          lessThanOrEqualTo(1.0),
          reason:
              '${style.assetKey}: 숫자 음량 편차 ${spread.toStringAsFixed(2)}dB'
              ' (${keys.map((k) => '$k:${vals[k]!.toStringAsFixed(2)}').join(', ')})'
              ' — 예전엔 3.71dB 였다',
        );
      }
    });

    test('카운트다운이 같은 목소리의 안내 음량과 1.5dB 이내로 맞는다', () {
      for (final style in VoiceStyle.values) {
        final key = style.assetKey;
        final (cnt, csr) = readWav(File('assets/audio/cnt_v7_$key.wav'));
        final cntDb = gatedDb(cnt, csr);
        // 안내는 '운동 시작' 시퀀스를 기준으로 한다.
        final (seq, ssr) = readWav(
          File('assets/audio/seq_${key}_startWork.wav'),
        );
        final seqDb = gatedDb(seq, ssr);
        final diff = (cntDb - seqDb).abs();
        expect(
          diff,
          lessThanOrEqualTo(1.5),
          reason:
              '$key: 카운트 ${cntDb.toStringAsFixed(2)}dB vs '
              '안내 ${seqDb.toStringAsFixed(2)}dB → 차이 '
              '${diff.toStringAsFixed(2)}dB — 남성은 예전에 2.6dB 컸다',
        );
      }
    });

    test('왜곡(클리핑)이 없다', () {
      final bad = <String>[];
      for (final style in VoiceStyle.values) {
        for (final n in [5, 4, 3, 2, 1]) {
          final (d, _) = readWav(
            File('assets/audio/c_${style.assetKey}_$n.wav'),
          );
          var clipped = 0;
          for (final v in d) {
            if (v.abs() > 0.999) clipped++;
          }
          final pct = clipped / d.length * 100;
          if (pct > 0.01) {
            bad.add('${style.assetKey}/$n: ${pct.toStringAsFixed(3)}%');
          }
        }
      }
      for (final style in VoiceStyle.values) {
        final (d, _) = readWav(
          File('assets/audio/cnt_v7_${style.assetKey}.wav'),
        );
        var clipped = 0;
        for (final v in d) {
          if (v.abs() > 0.999) clipped++;
        }
        final pct = clipped / d.length * 100;
        if (pct > 0.01) {
          bad.add('cnt_${style.assetKey}: ${pct.toStringAsFixed(3)}%');
        }
      }
      expect(bad, isEmpty, reason: '찌그러진 클립: ${bad.join(', ')}');
    });

    test('모든 클립이 조용히 끝나고 0 근처에서 마무리된다 (팝 없음)', () {
      for (final style in VoiceStyle.values) {
        for (final n in [5, 4, 3, 2, 1]) {
          final (d, _) = readWav(
            File('assets/audio/c_${style.assetKey}_$n.wav'),
          );
          expect(
            d.last.abs(),
            lessThan(0.01),
            reason: '${style.assetKey}/$n: 마지막 샘플 ${d.last} — 팝 위험',
          );
        }
      }
    });
  });
}
