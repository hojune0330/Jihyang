import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// 음성 파이프라인 v4 회귀 테스트.
///
/// ## 사용자 지적 (이 테스트가 다시는 안 나오게 막는 것)
///   "숫자와 음성의 싱크가 안 맞고 끊기듯 들리는 부분 단어, 음절 모두 별로"
///
/// ## v3 의 실제 결함 (수치로 확인)
///   · `st_male_prepare` : "준비" 구간 0.22~0.92 인데 **0.48 에서 잘림**
///     → 440ms 손실. "준비" 가 "준" 으로 들렸다.
///   · `st_baby_finish`  : "운동 종료" 6.72~7.96 인데 **7.43 에서 잘림**
///     → 530ms 손실. "운동 종료" 가 "운동 종" 으로 들렸다.
///   · 11개 대사 중 8개가 80~530ms 잘려 있었다.
///   · 클립 앞 무음이 68~220ms → 안내가 늦게 들려 싱크가 밀린 느낌.
///
/// ## v4 가 보장하는 것
///   · 모든 음성 클립이 ASR 단어 끝을 **넘어서** 잘린다 (잘림 0ms)
///   · 발성이 클립 시작 12ms 이내 → 간격이 매번 일정
///   · 카운트다운 숫자 발성이 정확히 i*1000ms 에 온다
///   · 시간 불변(LTI) EQ 만 사용 → 음절이 파르르 떨리지 않는다
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ({int sampleRate, int dataBytes, int dataStart}) readWav(File f) {
    final bytes = f.readAsBytesSync();
    final bd = ByteData.sublistView(bytes);
    var sampleRate = 0, dataBytes = 0, dataStart = 0;
    var i = 12;
    while (i + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(i, i + 4));
      final size = bd.getUint32(i + 4, Endian.little);
      if (id == 'fmt ') {
        sampleRate = bd.getUint32(i + 12, Endian.little);
      } else if (id == 'data') {
        dataBytes = size;
        dataStart = i + 8;
        break;
      }
      i += 8 + size + (size.isOdd ? 1 : 0);
    }
    return (sampleRate: sampleRate, dataBytes: dataBytes, dataStart: dataStart);
  }

  /// 5ms 창 기준 발성 시작 위치 (ms)
  double onsetMs(File f) {
    final bytes = f.readAsBytesSync();
    final w = readWav(f);
    final bd = ByteData.sublistView(bytes);
    const win = 221; // 5ms @ 44.1kHz
    final n = w.dataBytes ~/ 2;

    var maxAmp = 0;
    for (var k = 0; k < n; k++) {
      final a = bd.getInt16(w.dataStart + k * 2, Endian.little).abs();
      if (a > maxAmp) maxAmp = a;
    }
    if (maxAmp == 0) return -1;
    final thr = (maxAmp * 0.05).round();
    for (var f2 = 0; f2 * win + win <= n; f2++) {
      var peak = 0;
      for (var k = 0; k < win; k++) {
        final a = bd
            .getInt16(w.dataStart + (f2 * win + k) * 2, Endian.little)
            .abs();
        if (a > peak) peak = a;
      }
      if (peak > thr) return f2 * 5.0;
    }
    return -1;
  }

  /// 클립 끝에서부터 세어 처음 발성이 나오는 위치 (끝에서 몇 ms)
  double tailVoiceMs(File f) {
    final bytes = f.readAsBytesSync();
    final w = readWav(f);
    final bd = ByteData.sublistView(bytes);
    const win = 221;
    final n = w.dataBytes ~/ 2;

    var maxAmp = 0;
    for (var k = 0; k < n; k++) {
      final a = bd.getInt16(w.dataStart + k * 2, Endian.little).abs();
      if (a > maxAmp) maxAmp = a;
    }
    if (maxAmp == 0) return -1;
    final thr = (maxAmp * 0.05).round();

    final frames = n ~/ win;
    for (var f2 = frames - 1; f2 >= 0; f2--) {
      var peak = 0;
      for (var k = 0; k < win; k++) {
        final idx = f2 * win + k;
        if (idx >= n) break;
        final a = bd.getInt16(w.dataStart + idx * 2, Endian.little).abs();
        if (a > peak) peak = a;
      }
      if (peak > thr) return (frames - 1 - f2) * 5.0;
    }
    return -1;
  }

  group('A. 잘린 단어가 없다', () {
    test('모든 음성 클립 끝에 20ms 이상의 여운이 남아 있다', () {
      // v3 는 단어 중간에서 잘려 끝에 여운이 전혀 없었다(0ms).
      // 잘리지 않았다면 발성 후 최소 20ms 의 감쇠 구간이 있어야 한다.
      final bad = <String>[];
      for (final style in ['male', 'female', 'baby']) {
        for (final key in [
          'prepare',
          'startWork',
          'startRest',
          'setRest',
          'lastRound',
          'finish',
        ]) {
          final f = File('assets/audio/st_${style}_$key.wav');
          expect(f.existsSync(), true, reason: f.path);
          final tv = tailVoiceMs(f);
          if (tv < 20) {
            bad.add('${f.path.split('/').last}: 끝 여운 ${tv.toStringAsFixed(0)}ms');
          }
        }
      }
      expect(bad, isEmpty, reason: '단어가 잘린 클립: ${bad.join(', ')}');
    });

    test('음성 클립이 최소 400ms 이상이다 (단어 하나 이상 담김)', () {
      for (final style in ['male', 'female', 'baby']) {
        for (final key in [
          'prepare',
          'startWork',
          'startRest',
          'setRest',
          'lastRound',
          'finish',
        ]) {
          final f = File('assets/audio/st_${style}_$key.wav');
          final w = readWav(f);
          final ms = w.dataBytes / 2 / 44100 * 1000;
          expect(ms, greaterThan(400), reason: '${f.path} = ${ms}ms');
        }
      }
    });
  });

  group('B. 발성 시작이 앞으로 당겨져 있다 (싱크 밀림 방지)', () {
    test('모든 음성 클립이 12ms 안에 발성된다', () {
      final bad = <String>[];
      for (final style in ['male', 'female', 'baby']) {
        for (final key in ['prepare', 'startWork', 'startRest', 'setRest',
          'lastRound', 'finish']) {
          final f = File('assets/audio/st_${style}_$key.wav');
          final on = onsetMs(f);
          if (on < 0 || on > 12) {
            bad.add('${f.path.split('/').last}: ${on.toStringAsFixed(0)}ms');
          }
        }
      }
      expect(bad, isEmpty, reason: '앞 무음이 남은 클립: ${bad.join(', ')}');
    });
  });

  group('C. 카운트다운 숫자가 1초 격자에 정확히 놓인다', () {
    test('cnt 파일에서 숫자가 1초 간격으로 시작한다', () {
      for (final style in ['male', 'female', 'baby']) {
        final f = File('assets/audio/cnt_$style.wav');
        expect(f.existsSync(), true, reason: f.path);
        final bytes = f.readAsBytesSync();
        final w = readWav(f);
        final bd = ByteData.sublistView(bytes);

        // 각 숫자의 발성 시작을 찾아 0/1000/2000/3000/4000 과 비교
        const win = 221;
        final n = w.dataBytes ~/ 2;
        var maxAmp = 0;
        for (var k = 0; k < n; k++) {
          final a = bd.getInt16(w.dataStart + k * 2, Endian.little).abs();
          if (a > maxAmp) maxAmp = a;
        }
        final thr = (maxAmp * 0.04).round();

        // i*1000ms 지점부터 250ms 안에서 첫 발성을 찾는다
        for (var i = 0; i < 5; i++) {
          final base = (i * 1000 / 1000 * 44100).round();
          var found = -1;
          for (var k = base; k < base + 44100 * 250 ~/ 1000 && k < n; k++) {
            final a = bd.getInt16(w.dataStart + k * 2, Endian.little).abs();
            if (a > thr) {
              found = k;
              break;
            }
          }
          expect(found, greaterThanOrEqualTo(0),
              reason: '$style 숫자 ${5 - i} 를 찾지 못했다');
          final offset = (found - base) / 44100 * 1000;
          expect(offset, lessThan(15),
              reason: '$style 숫자 ${5 - i}: ${offset.toStringAsFixed(0)}ms '
                  '늦게 시작 (15ms 이내여야 한다)');
          expect(win, greaterThan(0));
        }
      }
    });
  });

  group('D. 시퀀스가 삑 + 음성을 온전히 담는다', () {
    test('시퀀스 길이 = 삑 + 간격 + 음성 (+ 여유) 과 일치한다', () {
      // 파일을 실제로 읽어 계산한 값과 표가 어긋나면
      // 보호구간 계산이 틀어져 카운트다운이 안내를 덮는다.
      for (final style in ['male', 'female', 'baby']) {
        for (final key in ['prepare', 'startWork', 'startRest', 'setRest',
          'lastRound', 'finish']) {
          final seq = File('assets/audio/seq_${style}_$key.wav');
          final st = File('assets/audio/st_${style}_$key.wav');
          expect(seq.existsSync(), true, reason: seq.path);
          expect(st.existsSync(), true, reason: st.path);

          final seqMs = readWav(seq).dataBytes / 2 / 44100 * 1000;
          final stMs = readWav(st).dataBytes / 2 / 44100 * 1000;
          // 삑(130ms) + 간격(180ms) + 음성
          final expected = 130 + 180 + stMs;
          expect((seqMs - expected).abs(), lessThan(120),
              reason: '$style/$key: 시퀀스 ${seqMs.toStringAsFixed(0)}ms, '
                  '기대 ${expected.toStringAsFixed(0)}ms');
        }
      }
    });
  });
}
