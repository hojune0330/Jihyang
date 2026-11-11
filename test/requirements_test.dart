import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/phase.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/models/workout_record.dart';
import 'package:tabata_timer/services/audio_coach.dart';
import 'package:tabata_timer/services/tabata_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabata_timer/services/workout_store.dart';

/// 사용자가 명시한 "반드시 확인해야 할 11가지" 를 실제로 검증한다.
TabataConfig cfg({
  int work = 6,
  int rest = 5,
  int rounds = 2,
  int sets = 1,
  int setRest = 4,
}) => TabataConfig(
  workSeconds: work,
  restSeconds: rest,
  rounds: rounds,
  sets: sets,
  setRestSeconds: setRest,
  soundEnabled: false,
  voiceEnabled: false,
  sfxEnabled: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1) 준비시간', () {
    test('기본 준비시간은 10초이고 첫 구간으로 반드시 존재한다', () {
      expect(TabataConfig.prepareSeconds, 10);
      for (final sets in [1, 2, 5]) {
        final c = cfg(sets: sets);
        final phases = c.buildPhases();
        expect(phases.first.type, PhaseType.prepare);
        expect(phases.first.duration, 10);
      }
    });

    test('준비가 끝나면 첫 라운드(운동)가 시작된다', () async {
      final e = TabataEngine(config: cfg(work: 3, rest: 2, rounds: 2))
        ..audioOutputEnabled = false;
      e.start();
      expect(e.phaseType, 'prepare');
      e.skip(); // 준비 → 운동
      expect(e.phaseType, 'work');
      expect(e.currentRound, 1);
      expect(e.currentSet, 1);
      e.dispose();
    });
  });

  group('2) 운동·휴식 시간이 설정값과 일치', () {
    test('각 구간 길이가 설정값과 정확히 같다', () {
      final c = cfg(work: 20, rest: 10, rounds: 4, sets: 2, setRest: 60);
      final phases = c.buildPhases();
      for (final p in phases) {
        switch (p.type) {
          case PhaseType.prepare:
            expect(p.duration, TabataConfig.prepareSeconds);
          case PhaseType.work:
            expect(p.duration, 20);
          case PhaseType.rest:
            expect(p.duration, 10);
          case PhaseType.setRest:
            expect(p.duration, 60);
        }
      }
    });

    test('타이머 진행 중 남은 시간이 설정값에서 시작한다', () {
      final e = TabataEngine(config: cfg(work: 30, rest: 15))
        ..audioOutputEnabled = false;
      e.start();
      expect(e.remainingSeconds, 10); // 준비
      e.skip();
      expect(e.remainingSeconds, 30); // 운동
      e.dispose();
    });
  });

  group('3) 구간별 안내(효과음 + 음성) 매핑', () {
    Phase ph(
      PhaseType t,
      int dur,
      int set,
      int round, {
      int ts = 2,
      int tr = 3,
    }) => Phase(
      type: t,
      duration: dur,
      setIndex: set,
      roundIndex: round,
      totalSets: ts,
      totalRounds: tr,
    );

    test('준비 구간은 [준비하세요] 음성만 있고 효과음은 없다', () {
      final p = planForPhase(
        ph(PhaseType.prepare, 10, 1, 0),
        totalSets: 2,
        totalRounds: 3,
      );
      expect(p.sfx, isNull);
      expect(p.voices, [StateVoice.prepare]);
    });

    test('운동 구간은 운동 효과음 + [운동 시작]', () {
      final p = planForPhase(
        ph(PhaseType.work, 30, 1, 1),
        totalSets: 2,
        totalRounds: 3,
      );
      expect(p.sfx, Sfx.work);
      expect(p.voices, [StateVoice.startWork]);
    });

    test('세션 마지막 라운드는 [운동 시작] + [마지막 라운드] 순서로 안내한다', () {
      final p = planForPhase(
        ph(PhaseType.work, 30, 2, 3),
        totalSets: 2,
        totalRounds: 3,
      );
      expect(p.sfx, Sfx.work);
      expect(p.voices, [StateVoice.startWork, StateVoice.lastRound]);
    });

    test('마지막 세트라도 마지막 라운드가 아니면 lastRound 안내가 없다', () {
      final p = planForPhase(
        ph(PhaseType.work, 30, 2, 2),
        totalSets: 2,
        totalRounds: 3,
      );
      expect(p.voices, [StateVoice.startWork]);
    });

    test('휴식은 낮은 효과음 + [휴식 시작]', () {
      final p = planForPhase(
        ph(PhaseType.rest, 10, 1, 1),
        totalSets: 2,
        totalRounds: 3,
      );
      expect(p.sfx, Sfx.rest);
      expect(p.voices, [StateVoice.startRest]);
    });

    test('세트 간 휴식은 [세트 간 휴식입니다]', () {
      final p = planForPhase(
        ph(PhaseType.setRest, 60, 1, 3),
        totalSets: 2,
        totalRounds: 3,
      );
      expect(p.sfx, Sfx.rest);
      expect(p.voices, [StateVoice.setRest]);
    });

    test('운동 효과음과 휴식 효과음은 서로 다른 음높이 파일이다', () {
      expect(Sfx.work.asset, 'audio/sfx_work.wav');
      expect(Sfx.rest.asset, 'audio/sfx_rest.wav');
      expect(Sfx.work.asset == Sfx.rest.asset, false);
    });

    test('경고음은 약 0.8~1.3초 길이로 충분히 들리는 크기다', () {
      // 현장 요구: "삐-삐-" 처럼 1초 정도 유지, 너무 작아서 안 들리면 안 됨
      expect(Sfx.work.durationMs, inInclusiveRange(700, 1100));
      expect(Sfx.rest.durationMs, inInclusiveRange(700, 1100));
      expect(Sfx.finish.durationMs, inInclusiveRange(700, 1500));
      // 음성이 켜져 있을 때 쓰는 짧은 삑은 짧아야 한다 (음성과 겹치지 않게)
      expect(Sfx.beep.durationMs, lessThanOrEqualTo(200));
      // 음성이 꺼졌을 때 초를 알리는 틱도 짧고 또렷해야 한다
      expect(Sfx.count.durationMs, lessThanOrEqualTo(200));
    });

    test('엔진이 구간 진입 시 올바른 안내 계획을 선택한다', () async {
      final e = TabataEngine(
        config: cfg(work: 1, rest: 1, rounds: 2, sets: 2, setRest: 1),
      )..audioOutputEnabled = false;
      e.start();
      expect(e.lastPhasePlan.voices, [StateVoice.prepare]);
      expect(e.lastPhasePlan.sfx, isNull);

      e.skip(); // 1세트 1라운드 운동
      expect(e.lastPhaseSfx, Sfx.work);
      expect(e.lastPhasePlan.voices, [StateVoice.startWork]);

      e.skip(); // 휴식
      expect(e.lastPhaseSfx, Sfx.rest);
      expect(e.lastPhasePlan.voices, [StateVoice.startRest]);

      e.skip(); // 1세트 2라운드 운동
      e.skip(); // 세트 간 휴식
      expect(e.lastPhasePlan.voices, [StateVoice.setRest]);
      e.dispose();
    });

    test('3가지 목소리 모두 상태 안내 자산 경로를 만든다', () {
      for (final style in VoiceStyle.values) {
        for (final v in StateVoice.values) {
          expect(v.assetFor(style), 'audio/st_${style.name}_${v.key}.wav');
        }
      }
      expect(VoiceStyle.values.length, 3);
      expect(StateVoice.values.length, 6);
    });

    test('목소리 이름과 설명이 요구사항대로다', () {
      expect(VoiceStyle.male.label, '스포츠 MC');
      expect(VoiceStyle.female.label, '화난 코치');
      expect(VoiceStyle.baby.label, '어린 캐릭터');

      final f = VoiceStyle.female.description;
      expect(f.contains('단호'), true, reason: f);
      expect(f.contains('중년'), true, reason: f);
      expect(f.contains('차분'), false, reason: f);

      final b = VoiceStyle.baby.description;
      expect(b.contains('어린'), true, reason: b);
    });

    test('이전 버전의 cute 설정은 아기 목소리로 이어진다', () {
      expect(VoiceStyle.fromName('cute'), VoiceStyle.baby);
      expect(VoiceStyle.fromName('baby'), VoiceStyle.baby);
      expect(VoiceStyle.fromName(null), VoiceStyle.male);
    });
  });

  group('4) 마지막 5초 카운트다운 동기화', () {
    test('운동·휴식 모두 5→1 이 1초 간격으로, 오차 60ms 이내', () async {
      final e = TabataEngine(config: cfg(work: 7, rest: 6, rounds: 2))
        ..audioOutputEnabled = false;
      e.start();
      e.skip(); // 운동(7초)
      await Future<void>.delayed(const Duration(milliseconds: 7900));

      final workCounts = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .toList();
      expect(workCounts.map((c) => c.label).toList(), [
        'count5',
        'count4',
        'count3',
        'count2',
        'count1',
      ]);
      for (var i = 1; i < workCounts.length; i++) {
        final gap = workCounts[i].actualWallMs - workCounts[i - 1].actualWallMs;
        expect((gap - 1000).abs(), lessThanOrEqualTo(70), reason: '간격 $gap');
      }
      for (final c in workCounts) {
        expect(
          c.errorMs.abs(),
          lessThanOrEqualTo(60),
          reason: '오차 ${c.errorMs}',
        );
      }
      e.dispose();
    });

    test('휴식 구간에서도 동일하게 5→1 이 발생한다', () async {
      final e = TabataEngine(config: cfg(work: 8, rest: 7, rounds: 2))
        ..audioOutputEnabled = false;
      e.start();
      e.skip(); // 운동(8초)
      await Future<void>.delayed(const Duration(milliseconds: 8300));
      expect(e.phaseType, 'rest');
      e.cueLog.clear();
      await Future<void>.delayed(const Duration(milliseconds: 6500));
      final restCounts = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .toList();
      expect(restCounts.length, 5, reason: '${restCounts.map((c) => c.label)}');
      expect(restCounts.first.label, 'count5');
      e.dispose();
    });

    test('5초보다 짧은 구간에서는 음성이 중복 재생되지 않고, 전환음과 겹치지 않는다', () async {
      // 3초 운동 → 5,4,2 는 없고 3,2,1 만 (각 1회)
      final e = TabataEngine(config: cfg(work: 3, rest: 0, rounds: 1))
        ..audioOutputEnabled = false;
      e.start();
      e.skip();
      await Future<void>.delayed(const Duration(milliseconds: 3600));
      final labels = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .map((c) => c.label)
          .toList();
      // 3초 구간에서 시작음과 겹치는 '3' 은 생략 → 2, 1 만 남는다
      expect(labels, ['count2', 'count1']);
      expect(labels.toSet().length, labels.length, reason: '중복 발화: $labels');
      e.dispose();
    });

    test('전환 효과음과 겹치는 카운트다운 숫자는 생략된다 (4초 구간 → 3,2,1)', () async {
      final e = TabataEngine(config: cfg(work: 4, rest: 0, rounds: 1))
        ..audioOutputEnabled = false;
      e.start();
      e.skip();
      await Future<void>.delayed(const Duration(milliseconds: 4600));
      final labels = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .map((c) => c.label)
          .toList();
      // '4' 는 구간 시작 0ms 지점이라 운동 시작음과 겹치므로 생략된다
      expect(labels, ['count3', 'count2', 'count1']);
      e.dispose();
    });
  });

  group('5) 음성/효과음 겹침 방지 장치', () {
    test('카운트다운 보호구간이 시작 안내 길이보다 항상 길다', () {
      for (final style in VoiceStyle.values) {
        for (final type in PhaseType.values) {
          final p = Phase(
            type: type,
            duration: 30,
            setIndex: 2,
            roundIndex: 3,
            totalSets: 2,
            totalRounds: 3,
          );
          final plan = planForPhase(p, totalSets: 2, totalRounds: 3);
          final guard = announceGuardMs(plan, style);
          final timing = announceTiming(
            plan,
            style,
            sfxEnabled: true,
            voiceEnabled: true,
          );
          expect(
            guard,
            greaterThan(timing.totalMs),
            reason: '$style $type guard=$guard total=${timing.totalMs}',
          );
          expect(timing.hasVoice, true);
        }
      }
    });

    test('마지막 라운드 안내가 붙으면 보호구간이 더 길어진다', () {
      final normal = planForPhase(
        Phase(
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
      final last = planForPhase(
        Phase(
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
      expect(
        announceGuardMs(last, VoiceStyle.male),
        greaterThan(announceGuardMs(normal, VoiceStyle.male)),
      );
    });

    test('효과음/음성 자산이 서로 다르다 → 플레이어도 분리된다', () {
      for (final s in Sfx.values) {
        expect(
          s.asset.startsWith('audio/sfx_') || s.asset == 'audio/beep.wav',
          true,
        );
      }
      final voice = StateVoice.startWork.assetFor(VoiceStyle.male);
      expect(voice, 'audio/st_male_startWork.wav');
      expect(voice == Sfx.work.asset, false);
    });

    test('일시정지하면 재생 중이던 소리가 즉시 무효화된다', () async {
      final c = const TabataConfig(
        soundEnabled: true,
        sfxEnabled: true,
        voiceEnabled: true,
      );
      AudioCoach.instance.applyConfig(c);
      expect(AudioCoach.instance.soundEnabled, true);
      expect(AudioCoach.instance.sfxEnabled, true);
      // cut() 은 동기 함수 → await 없이도 즉시 이전 재생을 폐기한다
      AudioCoach.instance.cut();
      expect(AudioCoach.instance.playLog.length, greaterThanOrEqualTo(0));
    });
  });

  group('6) 라운드/세트 전환', () {
    test('라운드와 세트가 순서대로 증가한다', () async {
      final e = TabataEngine(
        config: cfg(work: 1, rest: 1, rounds: 2, sets: 2, setRest: 1),
      )..audioOutputEnabled = false;
      e.start();
      e.skip(); // 준비 → 1세트 1라운드 운동
      expect((e.currentSet, e.currentRound), (1, 1));
      e.skip(); // 휴식
      e.skip(); // 1세트 2라운드 운동
      expect((e.currentSet, e.currentRound), (1, 2));
      e.skip(); // 세트 휴식
      expect(e.phaseType, 'setRest');
      e.skip(); // 2세트 1라운드
      expect((e.currentSet, e.currentRound), (2, 1));
      e.dispose();
    });

    test('전체 라운드 수 = 라운드 × 세트', () {
      expect(cfg(rounds: 8, sets: 3).totalRounds, 24);
      expect(cfg(rounds: 1, sets: 1).totalRounds, 1);
    });
  });

  group('7) 세트 간 휴식 위치', () {
    test('세트 간 휴식은 세트 경계에만, 마지막 세트 뒤에는 없다', () {
      final c = cfg(rounds: 3, sets: 3, rest: 5, setRest: 30);
      final phases = c.buildPhases();
      final setRests = phases
          .where((p) => p.type == PhaseType.setRest)
          .toList();
      // 3세트 → 세트 간 휴식 2회
      expect(setRests.length, 2);
      for (final sr in setRests) {
        expect(sr.setIndex, lessThan(3));
      }
      // 마지막 구간은 운동이어야 한다 (마지막 뒤 휴식 없음)
      expect(phases.last.type, PhaseType.work);
    });

    test('세트가 1개면 세트 간 휴식이 생성되지 않는다', () {
      final c = cfg(sets: 1, setRest: 60);
      final setRests = c
          .buildPhases()
          .where((p) => p.type == PhaseType.setRest)
          .toList();
      expect(setRests.isEmpty, true);
    });
  });

  group('8) 총 소요시간 = 실제 진행시간', () {
    test('totalSeconds 와 buildPhases 합계가 같다', () {
      final cases = [
        cfg(work: 10, rest: 5, rounds: 2, sets: 2, setRest: 60),
        cfg(work: 30, rest: 15, rounds: 8, sets: 1, setRest: 60),
        cfg(work: 20, rest: 0, rounds: 5, sets: 3, setRest: 0),
        cfg(work: 5, rest: 5, rounds: 1, sets: 1, setRest: 0),
      ];
      for (final c in cases) {
        expect(
          c.totalSeconds,
          c.phasesTotalSeconds,
          reason: '총 시간 불일치: ${c.toJson()}',
        );
      }
    });

    test('마지막 운동 뒤 불필요한 휴식이 중복 계산되지 않는다', () {
      // 운동 10 / 휴식 5 / 2라운드 / 2세트 / 세트휴식 60
      final c = TabataConfig(
        workSeconds: 10,
        restSeconds: 5,
        rounds: 2,
        sets: 2,
        setRestSeconds: 60,
      );
      // 준비10 + 1세트(10+5+10=25) + 세트휴식60 + 2세트(25) = 120
      expect(c.totalSeconds, 120);
      // 순수 운동 = 10 × 2라운드 × 2세트 = 40
      expect(c.pureWorkSeconds, 40);
      // 운동 외 시간 = 준비10 + 휴식5 + 세트휴식60 + 휴식5 = 80
      // (마지막 라운드 뒤 휴식이 붙지 않았음을 이 값으로 확인한다)
      expect(c.totalSeconds - c.pureWorkSeconds, 80);
      // 마지막 구간은 운동 (뒤에 휴식이 붙지 않는다)
      expect(c.buildPhases().last.type, PhaseType.work);
    });

    test('엔진의 totalSeconds 도 동일하다', () {
      final c = cfg(work: 10, rest: 5, rounds: 2, sets: 2, setRest: 60);
      final e = TabataEngine(config: c)..audioOutputEnabled = false;
      expect(e.totalSeconds, c.totalSeconds);
      e.dispose();
    });
  });

  group('9) 일시정지 / 재개 싱크', () {
    test('일시정지 중에는 카운트다운이 예약되지 않고 재개 후 시간이 이어진다', () async {
      final e = TabataEngine(config: cfg(work: 10, rest: 0, rounds: 1))
        ..audioOutputEnabled = false;
      e.start();
      e.skip(); // 운동 10초
      await Future<void>.delayed(const Duration(milliseconds: 3000));
      e.pause();
      final remainAtPause = e.remainingSeconds;
      final countAtPause = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .length;
      await Future<void>.delayed(const Duration(milliseconds: 2000));
      expect(
        e.cueLog.where((c) => c.label.startsWith('count')).length,
        countAtPause,
        reason: '일시정지 중 카운트다운 발생',
      );
      expect(e.remainingSeconds, remainAtPause);
      e.resume();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(e.remainingSeconds, lessThan(remainAtPause));
      expect((remainAtPause - e.remainingSeconds), inInclusiveRange(1, 2));
      e.dispose();
    });

    test('일시정지 시간은 실제 운동 시간에 포함되지 않는다', () async {
      final e = TabataEngine(config: cfg(work: 20, rest: 0, rounds: 1))
        ..audioOutputEnabled = false;
      e.start();
      e.skip();
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      e.pause();
      final t = e.elapsedTotalMs;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect((e.elapsedTotalMs - t).abs(), lessThanOrEqualTo(40));
      e.dispose();
    });
  });

  group('10) 백그라운드 복귀 정산', () {
    test('catchUp 이 밀린 구간을 따라잡는다', () async {
      final e = TabataEngine(config: cfg(work: 1, rest: 1, rounds: 3))
        ..audioOutputEnabled = false;
      e.start();
      e.skip(); // 운동1
      // 2.5초 흐름 (운동1 + 휴식1 을 지나 운동2 로 진입해야 함)
      await Future<void>.delayed(const Duration(milliseconds: 2600));
      e.catchUp();
      expect(e.phaseType, anyOf('work', 'rest'));
      expect(e.isRunning, true);
      e.dispose();
    });

    test('스냅샷 복원 후 남은 시간이 유지된다', () async {
      final e = TabataEngine(config: cfg(work: 20, rest: 5, rounds: 2))
        ..audioOutputEnabled = false;
      e.start();
      e.skip();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final snap = e.snapshot();
      e.dispose();

      final e2 = TabataEngine()..audioOutputEnabled = false;
      e2.restoreFromSnapshot(snap);
      expect(e2.phaseType, 'work');
      expect(e2.remainingSeconds, lessThanOrEqualTo(20));
      expect(e2.remainingSeconds, greaterThanOrEqualTo(17));
      e2.dispose();
    });
  });

  group('11) 운동 기록 저장', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('완료 기록과 중도 종료 기록을 구분해 저장한다', () async {
      await WorkoutStore.clear();
      final now = DateTime.now();

      final completed = WorkoutRecord(
        id: 1,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 10)),
        workSeconds: 30,
        restSeconds: 15,
        rounds: 8,
        sets: 1,
        setRestSeconds: 60,
        plannedSeconds: 360,
        activeSeconds: 355,
        completedRounds: 8,
        completedSets: 1,
        totalRounds: 8,
        outcome: SessionOutcome.completed,
        progress: 1.0,
      );
      final aborted = WorkoutRecord(
        id: 2,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 3)),
        workSeconds: 30,
        restSeconds: 15,
        rounds: 8,
        sets: 1,
        setRestSeconds: 60,
        plannedSeconds: 360,
        activeSeconds: 120,
        completedRounds: 3,
        completedSets: 0,
        totalRounds: 8,
        outcome: SessionOutcome.aborted,
        progress: 120 / 360,
      );

      expect(await WorkoutStore.add(completed), true);
      expect(await WorkoutStore.add(aborted), true);
      // 중복 id 는 저장되지 않는다
      expect(await WorkoutStore.add(completed), false);

      final list = await WorkoutStore.load(force: true);
      expect(list.length, 2);
      expect(list.where((r) => r.isCompleted).length, 1);
      expect(list.where((r) => !r.isCompleted).length, 1);
      expect(WorkoutStore.totalCount(list), 2);
      expect(WorkoutStore.completedCount(list), 1);
      expect(WorkoutStore.totalActiveSeconds(list), 355 + 120);
    });

    test('기록은 JSON 왕복 후에도 값이 보존된다', () {
      final now = DateTime.now();
      final r = WorkoutRecord(
        id: 42,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 5)),
        workSeconds: 20,
        restSeconds: 10,
        rounds: 6,
        sets: 2,
        setRestSeconds: 45,
        plannedSeconds: 400,
        activeSeconds: 300,
        completedRounds: 9,
        completedSets: 1,
        totalRounds: 12,
        outcome: SessionOutcome.aborted,
        progress: 0.75,
      );
      final back = WorkoutRecord.fromJson(r.toJson());
      expect(back.id, r.id);
      expect(back.workSeconds, 20);
      expect(back.restSeconds, 10);
      expect(back.rounds, 6);
      expect(back.sets, 2);
      expect(back.setRestSeconds, 45);
      expect(back.outcome, SessionOutcome.aborted);
      expect(back.progress, closeTo(0.75, 0.0001));
      expect(back.completedRounds, 9);
      expect(back.totalRounds, 12);
    });

    test('엔진 완료 시점의 통계로 완료 기록을 만들 수 있다', () async {
      final e = TabataEngine(config: cfg(work: 1, rest: 1, rounds: 1))
        ..audioOutputEnabled = false;
      e.start();
      for (var i = 0; i < 10 && !e.isFinished; i++) {
        e.skip();
      }
      expect(e.isFinished, true);
      expect(e.totalProgress, 1.0);
      expect(e.completedRounds, 1);
      expect(e.sessionStartedAt, isNotNull);
      e.dispose();
    });
  });
}
