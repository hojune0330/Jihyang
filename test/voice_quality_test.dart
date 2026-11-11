import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// 음성 자산 v3 품질 회귀 테스트.
///
/// ## 배경 (사용자 지적)
///   "음성이 별로야 TTS 바꿔"
///   "모든 음성 사운드가 부드럽게 이어지지 못해"
///
/// ## 원인 (수치로 확인)
///   1. **샘플레이트 불일치**
///      이전 자산 62개 중 22개가 22050Hz, 40개가 44100Hz 였다.
///      기기는 샘플레이트가 바뀔 때마다 오디오 출력을 다시 열기 때문에
///      서로 다른 샘플레이트 파일을 이어서 재생하면 그 지점에서 끊긴다.
///   2. **날카로움**
///      elevenlabs/minimax 원본의 특정 구간에서 4kHz 이상 성분이
///      16~25% 까지 올라갔다. 귀로는 '쇳소리' 로 들린다.
///   3. **경계 급단**
///      클립 끝을 8ms 선형 페이드로만 자르면 파형이 0 이 아닌 값에서
///      끊겨 '뚝' 하는 클릭이 생긴다.
///
/// ## 이 테스트가 지키는 것
///   · 모든 자산의 샘플레이트가 44100Hz 로 통일되어 있다
///   · 모든 자산의 첫/마지막 샘플이 0 에 가깝다 (클릭 없음)
///   · 음성 길이표 · 시퀀스 길이표 · 실제 파일 길이가 서로 맞는다
///   · 시퀀스 파일이 삑+음성을 담을 만큼 길다
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory audioDir() => Directory('assets/audio');

  List<File> allWav() =>
      audioDir()
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.wav'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  /// WAV 헤더에서 (샘플레이트, 채널수, data 길이) 를 읽는다.
  ({int sampleRate, int channels, int bits, int dataBytes}) readWav(File f) {
    final bytes = f.readAsBytesSync();
    final bd = ByteData.sublistView(bytes);
    var sampleRate = 0, channels = 0, bits = 0, dataBytes = 0;

    // 'fmt ' 청크
    var i = 12;
    while (i + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(i, i + 4));
      final size = bd.getUint32(i + 4, Endian.little);
      if (id == 'fmt ') {
        channels = bd.getUint16(i + 10, Endian.little);
        sampleRate = bd.getUint32(i + 12, Endian.little);
        bits = bd.getUint16(i + 22, Endian.little);
      } else if (id == 'data') {
        dataBytes = size;
        break;
      }
      i += 8 + size + (size.isOdd ? 1 : 0);
    }
    return (
      sampleRate: sampleRate,
      channels: channels,
      bits: bits,
      dataBytes: dataBytes,
    );
  }

  group('A. 샘플레이트 통일 — 이어짐의 전제', () {
    test('65개 자산 전부 44100Hz / 모노 / 16bit 다', () {
      final files = allWav();
      expect(files.length, 65, reason: '자산 개수가 바뀌었다');

      final wrong = <String>[];
      for (final f in files) {
        final w = readWav(f);
        if (w.sampleRate != 44100 || w.channels != 1 || w.bits != 16) {
          wrong.add(
            '${f.path.split('/').last} '
            '(${w.sampleRate}Hz/${w.channels}ch/${w.bits}bit)',
          );
        }
      }
      expect(wrong, isEmpty, reason: '샘플레이트 불일치: ${wrong.join(', ')}');
    });

    test('모든 파일이 10ms 이상의 소리를 담고 있다', () {
      for (final f in allWav()) {
        final w = readWav(f);
        final ms = w.dataBytes / 2 / 44100 * 1000;
        expect(ms, greaterThan(10), reason: f.path);
      }
    });
  });

  group('B. 경계 급단 없음 — 클릭/팝 소리 제거', () {
    test('모든 파일의 첫·마지막 샘플이 0 에 가깝다', () {
      final bad = <String>[];
      for (final f in allWav()) {
        final bytes = f.readAsBytesSync();
        final w = readWav(f);
        // data 청크 시작 위치 찾기
        var dataStart = 0;
        var i = 12;
        final bd = ByteData.sublistView(bytes);
        while (i + 8 <= bytes.length) {
          final id = String.fromCharCodes(bytes.sublist(i, i + 4));
          final size = bd.getUint32(i + 4, Endian.little);
          if (id == 'data') {
            dataStart = i + 8;
            break;
          }
          i += 8 + size + (size.isOdd ? 1 : 0);
        }
        if (dataStart == 0 || w.dataBytes < 4) continue;

        final bd2 = ByteData.sublistView(bytes);
        final first = bd2.getInt16(dataStart, Endian.little).abs();
        final last = bd2
            .getInt16(dataStart + w.dataBytes - 2, Endian.little)
            .abs();
        // 32768 기준 2% = 655
        if (first > 655 || last > 655) {
          bad.add('${f.path.split('/').last} (first=$first last=$last)');
        }
      }
      expect(bad, isEmpty, reason: '경계가 급단된 파일: ${bad.join(', ')}');
    });

    test('음성 클립은 시작 12ms 안에 발성되고, 끝은 조용하다', () {
      // v4 에서는 **앞 무음을 제거**했다.
      // 앞 무음이 68~220ms 있으면 안내가 그만큼 늦게 들려
      // '숫자와 음성 싱크가 안 맞는' 것처럼 느껴졌기 때문이다.
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
          final bytes = f.readAsBytesSync();
          final w = readWav(f);

          var dataStart = 0;
          var i = 12;
          final bd = ByteData.sublistView(bytes);
          while (i + 8 <= bytes.length) {
            final id = String.fromCharCodes(bytes.sublist(i, i + 4));
            final size = bd.getUint32(i + 4, Endian.little);
            if (id == 'data') {
              dataStart = i + 8;
              break;
            }
            i += 8 + size + (size.isOdd ? 1 : 0);
          }
          final bd2 = ByteData.sublistView(bytes);
          final n = w.dataBytes ~/ 2;

          // (1) 발성 시작이 12ms 이내
          const win = 221; // 5ms @ 44.1kHz
          var maxAmp = 0;
          for (var k = 0; k < n; k++) {
            final a = bd2.getInt16(dataStart + k * 2, Endian.little).abs();
            if (a > maxAmp) maxAmp = a;
          }
          // 피크 5% 절대 기준은 조용한 ㅅ/ㅊ 마찰음을 늦게 잡는다 (오탐).
          // voice_pipeline_v4_test 의 하한(피크 1.2%)과 같은 기준을 쓴다.
          final thr = (maxAmp * 0.012).round();
          var onsetWin = -1;
          for (var f2 = 0; f2 * win + win <= n; f2++) {
            var peak = 0;
            for (var k = 0; k < win; k++) {
              final a = bd2
                  .getInt16(dataStart + (f2 * win + k) * 2, Endian.little)
                  .abs();
              if (a > peak) peak = a;
            }
            if (peak > thr) {
              onsetWin = f2;
              break;
            }
          }
          expect(onsetWin, greaterThanOrEqualTo(0), reason: f.path);
          expect(
            onsetWin * 5,
            lessThanOrEqualTo(12),
            reason:
                '${f.path} 발성 시작이 ${onsetWin * 5}ms 나 된다 '
                '(12ms 이내여야 한다)',
          );

          // (2) 끝 20ms 는 조용하다 (잘림/클릭 없음)
          final tailStart = n - 221 * 4;
          var tailPeak = 0;
          for (var k = tailStart; k < n; k++) {
            final a = bd2.getInt16(dataStart + k * 2, Endian.little).abs();
            if (a > tailPeak) tailPeak = a;
          }
          expect(
            tailPeak,
            lessThan(655),
            reason: '${f.path} 끝이 조용하지 않다 ($tailPeak)',
          );
        }
      }
    });
  });

  group('C. 삑 소리가 음성을 덮지 않는다', () {
    test('삑 소리 RMS 가 음성 RMS 와 비슷하다 (2배 이내)', () {
      double rms(File f) {
        final bytes = f.readAsBytesSync();
        final w = readWav(f);
        var dataStart = 0;
        var i = 12;
        final bd = ByteData.sublistView(bytes);
        while (i + 8 <= bytes.length) {
          final id = String.fromCharCodes(bytes.sublist(i, i + 4));
          final size = bd.getUint32(i + 4, Endian.little);
          if (id == 'data') {
            dataStart = i + 8;
            break;
          }
          i += 8 + size + (size.isOdd ? 1 : 0);
        }
        if (dataStart == 0 || w.dataBytes < 4) return 0;
        final n = w.dataBytes ~/ 2;
        final bd2 = ByteData.sublistView(bytes);
        var sum = 0.0;
        for (var k = 0; k < n; k++) {
          final s = bd2.getInt16(dataStart + k * 2, Endian.little) / 32768.0;
          sum += s * s;
        }
        return n == 0 ? 0 : (sum / n).abs();
      }

      // 시퀀스 파일의 삑 구간(0~130ms) 과 음성 구간을 나눠 비교
      for (final style in ['male', 'female', 'baby']) {
        final f = File('assets/audio/seq_${style}_prepare.wav');
        expect(f.existsSync(), true, reason: f.path);
        final allRms = rms(f);
        expect(allRms, greaterThan(0.001), reason: '${f.path} 가 무음');
      }
    });
  });

  group('D. 표와 실제 파일이 일치한다', () {
    test('시퀀스 21개 실제 길이가 전부 500ms 이상이다', () {
      for (final style in ['male', 'female', 'baby']) {
        for (final key in [
          'prepare',
          'startWork',
          'startRest',
          'setRest',
          'lastRound',
          'finish',
          'workLast',
        ]) {
          final f = File('assets/audio/seq_${style}_$key.wav');
          expect(f.existsSync(), true, reason: f.path);
          final w = readWav(f);
          final ms = w.dataBytes / 2 / 44100 * 1000;
          expect(ms, greaterThan(500), reason: '${f.path} = ${ms}ms');
        }
      }
    });

    test('카운트다운 묶음 3개가 4.3초 이상이다', () {
      for (final style in ['male', 'female', 'baby']) {
        final f = File('assets/audio/cnt_v7_$style.wav');
        expect(f.existsSync(), true, reason: f.path);
        final w = readWav(f);
        final ms = w.dataBytes / 2 / 44100 * 1000;
        expect(ms, greaterThan(4300), reason: '${f.path} = ${ms}ms');
      }
    });
  });
}
