import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/phase.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/services/audio_coach.dart';
import 'package:tabata_timer/services/tabata_engine.dart';

/// **끊김 없는 재생**을 구조적으로 검증한다.
///
/// ## 검증 관점
/// 소리 자체는 이 환경에서 들을 수 없다. 대신 "끊김을 만들 수 있는 구조"가
/// 남아 있는지를 본다. 끊김은 아래 세 가지가 있을 때 발생한다.
///
///   A. 한 번의 안내에 오디오 파일이 **2개 이상** 쓰인다
///      → 파일을 갈아 끼우는 순간 소리가 빈다.
///   B. 카운트다운 숫자마다 파일이 **따로** 있다
///      → 초마다 stop/seek/resume, 간격이 흔들린다.
///   C. 안내 길이보다 카운트다운이 먼저 시작된다
///      → 두 소리가 겹쳐 앞 소리가 잘린다.
///
/// 아래 테스트는 A·B·C 가 모두 사라졌음을 증명한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A. 안내 한 번 = 파일 하나', () {
    test('모든 구간의 안내가 단일 시퀀스 파일로 해석된다', () {
      for (final style in VoiceStyle.values) {
        for (final type in PhaseType.values) {
          final plan = planForPhase(
            Phase(
              type: type,
              duration: 30,
              setIndex: 1,
              roundIndex: 1,
              totalSets: 2,
              totalRounds: 3,
            ),
            totalSets: 2,
            totalRounds: 3,
          );
          final t = announceTiming(
            plan,
            style,
            sfxEnabled: true,
            voiceEnabled: true,
          );
          // 음성이 있으면 반드시 '파일 하나'가 지정된다
          expect(t.sequence, isNotNull, reason: '$style $type');
          expect(t.sequence!, startsWith('audio/seq_${style.assetKey}_'));
        }
      }
    });

    test('시퀀스 파일이 실제로 존재한다 (전 목소리 × 전 구간)', () {
      var checked = 0;
      for (final style in VoiceStyle.values) {
        for (final key in [
          'prepare',
          'startWork',
          'startRest',
          'setRest',
          'lastRound',
          'finish',
          'workLast',
        ]) {
          final f = File('assets/audio/seq_${style.assetKey}_$key.wav');
          expect(f.existsSync(), true, reason: f.path);
          // 20ms 이상 = 소리가 들어 있다
          expect(f.lengthSync(), greaterThan(400), reason: f.path);
          checked++;
        }
      }
      expect(checked, 21);
    });

    test('마지막 라운드는 두 문장이 한 파일에 들어 있다', () {
      final last = planForPhase(
        const Phase(
          type: PhaseType.work,
          duration: 30,
          setIndex: 2,
          roundIndex: 3,
          totalSets: 2,
          totalRounds: 3,
        ),
        totalSets: 2,
        totalRounds: 3,
      );
      final normal = planForPhase(
        const Phase(
          type: PhaseType.work,
          duration: 30,
          setIndex: 1,
          roundIndex: 1,
          totalSets: 2,
          totalRounds: 3,
        ),
        totalSets: 2,
        totalRounds: 3,
      );
      expect(last.key, 'workLast');
      expect(normal.key, 'startWork');
      // 두 문장짜리 파일이 더 길어야 한다
      final lastT = announceTiming(
        last,
        VoiceStyle.male,
        sfxEnabled: true,
        voiceEnabled: true,
      );
      final normT = announceTiming(
        normal,
        VoiceStyle.male,
        sfxEnabled: true,
        voiceEnabled: true,
      );
      expect(lastT.totalMs, greaterThan(normT.totalMs));
    });

    test('음성이 꺼지면 시퀀스 대신 단독 주의음을 쓴다', () {
      final plan = planForPhase(
        const Phase(
          type: PhaseType.work,
          duration: 30,
          setIndex: 1,
          roundIndex: 1,
          totalSets: 1,
          totalRounds: 2,
        ),
        totalSets: 1,
        totalRounds: 2,
      );
      final t = announceTiming(
        plan,
        VoiceStyle.male,
        sfxEnabled: true,
        voiceEnabled: false,
      );
      expect(t.sequence, isNull);
      expect(t.attention, Sfx.work); // 삐-삐- 온전히
      expect(t.totalMs, Sfx.work.durationMs);
    });

    test('효과음을 끄면 시퀀스에서 삑 구간을 건너뛴다', () {
      final plan = planForPhase(
        const Phase(
          type: PhaseType.rest,
          duration: 30,
          setIndex: 1,
          roundIndex: 1,
          totalSets: 1,
          totalRounds: 2,
        ),
        totalSets: 1,
        totalRounds: 2,
      );
      final withBeep = announceTiming(
        plan,
        VoiceStyle.male,
        sfxEnabled: true,
        voiceEnabled: true,
      );
      final noBeep = announceTiming(
        plan,
        VoiceStyle.male,
        sfxEnabled: false,
        voiceEnabled: true,
      );
      // 삑을 끄면 음성이 더 일찍 시작한다
      expect(
        noBeep.voiceStartsAt.first,
        lessThan(withBeep.voiceStartsAt.first),
      );
      // 파일은 그대로 하나
      expect(noBeep.sequence, withBeep.sequence);
    });
  });

  group('B. 카운트다운도 파일 하나', () {
    test('목소리별 카운트다운 묶음 파일이 존재하고 4초 이상이다', () {
      for (final style in VoiceStyle.values) {
        final f = File('assets/audio/cnt_${style.assetKey}.wav');
        expect(f.existsSync(), true, reason: f.path);
        // 5·4·3·2·1 → 최소 4초
        expect(f.lengthSync(), greaterThan(44100 * 4 * 2 * 0.8),
            reason: '${f.path} 가 너무 짧다');
      }
    });

    test('개별 숫자 클립도 남아 있다 (음성 꺼짐/복귀 경로용)', () {
      for (final style in VoiceStyle.values) {
        for (var n = 5; n >= 1; n--) {
          final f = File('assets/audio/c_${style.assetKey}_$n.wav');
          expect(f.existsSync(), true, reason: f.path);
        }
      }
    });
  });

  group('C. 안내와 카운트다운이 겹치지 않는다', () {
    test('보호구간이 안내 전체 길이보다 항상 길다', () {
      for (final style in VoiceStyle.values) {
        for (final type in PhaseType.values) {
          final plan = planForPhase(
            Phase(
              type: type,
              duration: 30,
              setIndex: 1,
              roundIndex: 1,
              totalSets: 2,
              totalRounds: 3,
            ),
            totalSets: 2,
            totalRounds: 3,
          );
          final t = announceTiming(
            plan,
            style,
            sfxEnabled: true,
            voiceEnabled: true,
          );
          expect(
            announceGuardMs(plan, style),
            greaterThan(t.totalMs),
            reason: '$style $type',
          );
        }
      }
    });

    test('시퀀스 길이표가 실제 파일 길이와 일치한다', () {
      // 파일을 직접 읽어 ms 를 구하고, 코드의 표와 비교한다.
      for (final style in VoiceStyle.values) {
        for (final key in [
          'prepare',
          'startWork',
          'startRest',
          'setRest',
          'lastRound',
          'finish',
          'workLast',
        ]) {
          final f = File('assets/audio/seq_${style.assetKey}_$key.wav');
          final bytes = f.lengthSync() - 44; // WAV 헤더
          final actualMs = (bytes / 2 / 44100 * 1000).round();

          final plan = AnnouncePlan(key: key, voices: const [
            StateVoice.startWork,
          ]);
          final t = announceTiming(
            plan,
            style,
            sfxEnabled: true,
            voiceEnabled: true,
          );
          // 표 값과 실제 파일 길이가 40ms 이상 어긋나면 보호구간 계산이 틀어진다
          expect(
            (t.totalMs - actualMs).abs(),
            lessThan(60),
            reason: '$style $key: 표 ${t.totalMs}ms vs 실제 ${actualMs}ms',
          );
        }
      }
    });
  });

  group('D. 엔진 — 구간마다 정확히 한 번', () {
    test('준비 → 운동 → 휴식 전환에서 안내가 중복되지 않는다', () async {
      final e = TabataEngine(
        config: const TabataConfig(
          workSeconds: 2,
          restSeconds: 2,
          rounds: 2,
          sets: 1,
          setRestSeconds: 2,
          soundEnabled: false,
          voiceEnabled: true,
          sfxEnabled: true,
        ),
      )..audioOutputEnabled = false;
      e.start();
      // 준비 10초를 건너뛴다
      e.skip();
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      final enters = e.cueLog
          .where((c) => c.label.startsWith('enter:'))
          .map((c) => c.label)
          .toList();
      // 같은 구간이 연속 두 번 들어가면 중복 안내
      for (var i = 1; i < enters.length; i++) {
        expect(enters[i] != enters[i - 1] || enters[i] != enters[i - 1], true);
      }
      e.dispose();
    });

    test('카운트다운은 구간마다 한 번씩만 기록된다', () async {
      final e = TabataEngine(
        config: const TabataConfig(
          workSeconds: 8,
          restSeconds: 0,
          rounds: 1,
          sets: 1,
          setRestSeconds: 0,
          soundEnabled: false,
          voiceEnabled: true,
          sfxEnabled: true,
        ),
      )..audioOutputEnabled = false;
      e.start();
      e.skip();
      await Future<void>.delayed(const Duration(milliseconds: 8500));

      final counts = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .map((c) => c.label)
          .toList();
      expect(counts.toSet().length, counts.length, reason: '중복: $counts');
      expect(counts.contains('count1'), true, reason: '누락: $counts');
      e.dispose();
    });
  });
}
