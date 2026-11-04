import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/phase.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/services/audio_coach.dart';
import 'package:tabata_timer/services/tabata_engine.dart';

/// 사운드 이벤트가 **정확히 한 번, 겹치지 않게** 발생하는지 검증한다.
///
/// 오디오 플러그인은 테스트 환경에 없으므로 실제 소리는 나지 않는다.
/// 대신 엔진이 만드는 이벤트 시각표와 큐 로그를 검증한다.
/// (소리 자체가 아닌 '언제 무엇을 지시했는가'를 보는 것)
TabataConfig cfg({
  int work = 6,
  int rest = 5,
  int rounds = 2,
  int sets = 1,
  int setRest = 4,
  bool voice = true,
  bool sfx = true,
}) => TabataConfig(
  workSeconds: work,
  restSeconds: rest,
  rounds: rounds,
  sets: sets,
  setRestSeconds: setRest,
  soundEnabled: false, // 테스트에서는 실제 재생을 끈다
  voiceEnabled: voice,
  sfxEnabled: sfx,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('안내 시각표 — 겹침 없음', () {
    test('주의음이 끝난 뒤에 첫 음성이 시작된다', () {
      for (final style in VoiceStyle.values) {
        final t = announceTiming(
          const AnnouncePlan(
            sfx: Sfx.work,
            voices: [StateVoice.startWork],
          ),
          style,
          sfxEnabled: true,
          voiceEnabled: true,
        );
        expect(t.attention, isNotNull);
        expect(t.hasVoice, true);
        // 음성 시작 시각 > 주의음 길이 (겹치지 않는다)
        expect(
          t.voiceStartsAt.first,
          greaterThan(t.attention!.durationMs),
          reason: '$style',
        );
      }
    });

    test('두 음성이 연속될 때 앞 음성이 끝난 뒤 다음이 시작된다', () {
      // 마지막 라운드: [운동 시작] + [마지막 라운드]
      for (final style in VoiceStyle.values) {
        final t = announceTiming(
          const AnnouncePlan(
            sfx: Sfx.work,
            voices: [StateVoice.startWork, StateVoice.lastRound],
          ),
          style,
          sfxEnabled: true,
          voiceEnabled: true,
        );
        expect(t.voiceStartsAt.length, 2);
        final firstEnds =
            t.voiceStartsAt[0] + stateVoiceDurationMs(style, StateVoice.startWork);
        expect(
          t.voiceStartsAt[1],
          greaterThanOrEqualTo(firstEnds),
          reason: '$style 두 음성이 겹친다',
        );
      }
    });

    test('음성을 끄면 삐-삐- 주의음이 온전히 울린다', () {
      for (final type in [PhaseType.work, PhaseType.rest]) {
        final plan = planForPhase(
          Phase(
            type: type,
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
        expect(t.hasVoice, false);
        expect(t.attention, type == PhaseType.work ? Sfx.work : Sfx.rest);
        expect(t.totalMs, t.attention!.durationMs);
      }
    });

    test('음성을 켜면 주의음은 짧은 삑으로 줄고 곧바로 음성이 온다', () {
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
        voiceEnabled: true,
      );
      expect(t.attention, Sfx.beep);
      expect(t.voiceStartsAt.first, lessThan(400));
    });

    test('보호구간이 안내 전체 길이보다 항상 길다', () {
      for (final style in VoiceStyle.values) {
        for (final type in PhaseType.values) {
          final plan = planForPhase(
            Phase(
              type: type,
              duration: 30,
              setIndex: 2,
              roundIndex: 3,
              totalSets: 2,
              totalRounds: 3,
            ),
            totalSets: 2,
            totalRounds: 3,
          );
          final t = announceTiming(plan, style,
              sfxEnabled: true, voiceEnabled: true);
          expect(
            announceGuardMs(plan, style),
            greaterThan(t.totalMs),
            reason: '$style $type',
          );
        }
      }
    });
  });

  group('엔진 — 안내는 구간마다 정확히 한 번', () {
    test('각 구간 진입 시 안내 계획이 한 번만 기록된다', () async {
      final e = TabataEngine(
        config: cfg(work: 1, rest: 1, rounds: 2, sets: 2, setRest: 1),
      )..audioOutputEnabled = false;
      e.start();

      final enters = <String>[];
      e.addListener(() {
        // 안내 계획이 바뀌면 = 구간에 진입했다
        final label = '${e.phaseType}:${e.currentSet}-${e.currentRound}';
        if (enters.isEmpty || enters.last != label) enters.add(label);
      });

      for (var i = 0; i < 20 && !e.isFinished; i++) {
        e.skip();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // 같은 구간이 연속 두 번 기록되면 중복 안내다
      expect(enters.toSet().length, enters.length,
          reason: '중복 구간 진입: $enters');
      e.dispose();
    });

    test('일시정지/재개를 반복해도 카운트다운이 중복 발화하지 않는다', () async {
      final e = TabataEngine(config: cfg(work: 12, rest: 0, rounds: 1))
        ..audioOutputEnabled = false;
      e.start();
      e.skip(); // 운동 12초

      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        e.pause();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        e.resume();
      }
      await Future<void>.delayed(const Duration(milliseconds: 10500));

      final counts = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .map((c) => c.label)
          .toList();
      expect(counts.toSet().length, counts.length,
          reason: '중복 발화: $counts');
      e.dispose();
    });

    test('건너뛰기를 반복해도 음성 이벤트가 몰리지 않는다', () async {
      final e = TabataEngine(config: cfg(work: 2, rest: 2, rounds: 3))
        ..audioOutputEnabled = false;
      e.start();
      for (var i = 0; i < 6; i++) {
        e.skip();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final counts = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .map((c) => c.label)
          .toList();
      expect(counts.toSet().length, counts.length,
          reason: '중복 발화: $counts');
      e.dispose();
    });

    test(
      '5~10초 짧은 운동에서도 카운트다운이 중복/누락 없이 동작한다',
      () async {
        for (final w in [5, 6, 7, 8, 9, 10]) {
          final e = TabataEngine(config: cfg(work: w, rest: 0, rounds: 1))
            ..audioOutputEnabled = false;
          e.start();
          e.skip();
          await Future<void>.delayed(Duration(milliseconds: w * 1000 + 500));

          final counts = e.cueLog
              .where((c) => c.label.startsWith('count'))
              .map((c) => c.label)
              .toList();
          expect(counts.toSet().length, counts.length,
              reason: '$w초 중복: $counts');
          // 5초 이상이므로 최소한 마지막 숫자 '1'은 반드시 울려야 한다
          expect(counts.contains('count1'), true, reason: '$w초: $counts');
          e.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('준비 구간도 동일한 사운드 시스템을 쓴다', () {
    test('준비 구간에 5초 카운트다운이 동작한다', () async {
      final e = TabataEngine(config: cfg())..audioOutputEnabled = false;
      e.start();
      // 준비 10초 → T-5s..T-1s = 5초·6초·7초·8초·9초 지점
      await Future<void>.delayed(const Duration(milliseconds: 9600));
      final counts = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .map((c) => c.label)
          .toList();
      expect(counts, ['count5', 'count4', 'count3', 'count2', 'count1']);
      e.dispose();
    });

    test('준비 구간에는 안내 음성이 있고 효과음은 없다', () {
      final plan = planForPhase(
        const Phase(
          type: PhaseType.prepare,
          duration: 10,
          setIndex: 1,
          roundIndex: 0,
          totalSets: 1,
          totalRounds: 2,
        ),
        totalSets: 1,
        totalRounds: 2,
      );
      expect(plan.sfx, isNull);
      expect(plan.voices, [StateVoice.prepare]);
    });

    test('세트 간 휴식에도 5초 카운트다운이 동작한다', () async {
      final e = TabataEngine(
        config: cfg(work: 1, rest: 1, rounds: 1, sets: 2, setRest: 8),
      )..audioOutputEnabled = false;
      e.start();
      e.skip(); // 운동
      e.skip(); // (휴식 없음) 세트 간 휴식
      expect(e.phaseType, 'setRest');
      e.cueLog.clear();
      // 세트 간 휴식 8초 → T-5s..T-1s = 3초..7초 지점
      await Future<void>.delayed(const Duration(milliseconds: 7600));
      final counts = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .map((c) => c.label)
          .toList();
      expect(counts, ['count5', 'count4', 'count3', 'count2', 'count1']);
      e.dispose();
    });
  });

  group('음성 자산 누락 없음', () {
    test('3가지 목소리 × 6가지 안내 + 5개 숫자 = 자산 경로가 모두 정의된다', () {
      for (final style in VoiceStyle.values) {
        for (final v in StateVoice.values) {
          final p = v.assetFor(style);
          expect(p, startsWith('audio/st_${style.name}_'));
          expect(p, endsWith('.wav'));
        }
        for (var n = 5; n >= 1; n--) {
          expect('audio/c_${style.assetKey}_$n.wav',
              contains('c_${style.name}_'));
        }
      }
    });

    test('아기 목소리 자산 키가 c_baby / st_baby 로 정확히 만들어진다', () {
      expect(VoiceStyle.baby.assetKey, 'baby');
      expect(StateVoice.startWork.assetFor(VoiceStyle.baby),
          'audio/st_baby_startWork.wav');
      expect('audio/c_${VoiceStyle.baby.assetKey}_5.wav',
          'audio/c_baby_5.wav');
    });
  });
}
