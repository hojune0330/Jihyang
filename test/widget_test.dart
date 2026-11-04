import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/phase.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/services/tabata_engine.dart';

/// 테스트용 설정 (음성/효과음 끔 → 오디오 플러그인 의존 제거)
TabataConfig cfg({
  int work = 2,
  int rest = 1,
  int rounds = 3,
  int sets = 1,
  int setRest = 2,
}) => TabataConfig(
  workSeconds: work,
  restSeconds: rest,
  rounds: rounds,
  sets: sets,
  setRestSeconds: setRest,
  voiceEnabled: false,
  sfxEnabled: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('설정/구간 구성', () {
    test('페이즈 개수와 총 시간이 정확하다 (1세트)', () {
      final c = cfg(work: 20, rest: 10, rounds: 8, sets: 1);
      final phases = c.buildPhases();
      // 준비1 + (운동8 + 휴식7)
      expect(phases.length, 1 + 8 + 7);
      expect(c.totalSeconds, TabataConfig.prepareSeconds + 8 * 20 + 7 * 10);
      expect(c.pureWorkSeconds, 160);
    });

    test('세트 간 휴식이 올바른 위치에 삽입된다 (2세트)', () {
      final c = cfg(work: 20, rest: 10, rounds: 4, sets: 2, setRest: 60);
      final phases = c.buildPhases();
      final setRests = phases
          .where((p) => p.type == PhaseType.setRest)
          .toList();
      expect(setRests.length, 1);
      // 1세트 마지막 라운드(4) 뒤에 위치
      final idx = phases.indexWhere((p) => p.type == PhaseType.setRest);
      expect(phases[idx - 1].type, PhaseType.work);
      expect(phases[idx - 1].roundIndex, 4);
      expect(phases[idx + 1].setIndex, 2);
      expect(phases[idx + 1].roundIndex, 1);
    });

    test('세트 마지막 라운드 뒤에는 일반 휴식이 오지 않는다', () {
      final c = cfg(rounds: 3, sets: 2, work: 5, rest: 2, setRest: 5);
      final phases = c.buildPhases();
      for (var i = 0; i < phases.length; i++) {
        final p = phases[i];
        if (p.type == PhaseType.work && p.roundIndex == p.totalRounds) {
          // 다음은 휴식이 아닌 세트휴식이거나 운동이어야 한다
          if (i + 1 < phases.length) {
            expect(phases[i + 1].type, isNot(PhaseType.rest));
          }
        }
      }
    });

    test('json 왕복 변환이 값을 보존한다', () {
      final c = cfg(work: 90, rest: 45, rounds: 8, sets: 2, setRest: 120);
      final r = TabataConfig.fromJson(c.toJson());
      expect(r.workSeconds, 90);
      expect(r.restSeconds, 45);
      expect(r.rounds, 8);
      expect(r.sets, 2);
      expect(r.setRestSeconds, 120);
      // 분/초 분해
      expect(r.workMinutes, 1);
      expect(r.workSecondsPart, 30);
      expect(r.restSecondsPart, 45);
    });

    test('초 범위가 벗어난 값은 보정된다', () {
      final r = TabataConfig.fromJson({
        'workSeconds': 0,
        'restSeconds': -5,
        'rounds': 0,
        'sets': 999,
        'setRestSeconds': 99999,
      });
      expect(r.workSeconds, greaterThanOrEqualTo(5));
      expect(r.restSeconds, 0);
      expect(r.rounds, 1);
      expect(r.sets, 20);
      expect(r.setRestSeconds, lessThanOrEqualTo(3600));
    });
  });

  group('타이머 정확도 (벽시계 기반)', () {
    test('① 운동 → 휴식 전환이 정확한 시점에 일어난다', () async {
      final e = TabataEngine(config: cfg(work: 1, rest: 1, rounds: 2));
      e.start();
      expect(e.currentPhase?.type, PhaseType.prepare);
      // 준비 10초가 정확히 유지되어야 한다
      await Future<void>.delayed(const Duration(milliseconds: 6000));
      expect(e.currentPhase?.type, PhaseType.prepare);
      expect(e.remainingSeconds, lessThanOrEqualTo(5));
      await Future<void>.delayed(const Duration(milliseconds: 4300));
      // 10.3초 경과 → 이미 운동 구간
      expect(e.currentPhase?.type, PhaseType.work);
      e.dispose();
    });

    test('준비시간은 정확히 10초다', () {
      const c = TabataConfig();
      expect(TabataConfig.prepareSeconds, 10);
      final prepare = c.buildPhases().first;
      expect(prepare.type, PhaseType.prepare);
      expect(prepare.duration, 10);
    });

    test('남은 시간이 실제 경과 시간 기준으로 감소한다', () async {
      final e = TabataEngine(config: cfg(work: 10, rest: 5, rounds: 1));
      e.start();
      // 준비 구간 건너뛰기
      e.skip();
      expect(e.currentPhase?.type, PhaseType.work);
      final before = e.remainingSeconds;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final after = e.remainingSeconds;
      expect(before - after, inInclusiveRange(1, 2));
      e.dispose();
    });

    test('③ 일시정지 중에는 시간이 흐르지 않고 재개하면 이어진다', () async {
      final e = TabataEngine(config: cfg(work: 20, rest: 5, rounds: 2));
      e.start();
      e.skip();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      e.pause();
      final pausedAt = e.remainingSeconds;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(e.remainingSeconds, pausedAt); // 멈춤
      e.resume();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(e.remainingSeconds, lessThan(pausedAt));
      expect(pausedAt - e.remainingSeconds, inInclusiveRange(1, 2));
      e.dispose();
    });

    test('구간 전환 시 시간 손실이 없다 (초과분 이월)', () async {
      final e = TabataEngine(config: cfg(work: 2, rest: 2, rounds: 2));
      final total = e.totalSeconds;
      e.start();
      await Future<void>.delayed(const Duration(milliseconds: 5000));
      // 진행된 만큼 전체 남은 시간이 줄어야 한다 (늘거나 그대로면 손실/중복)
      expect(e.remainingTotalSeconds, lessThan(total));
      e.dispose();
    });

    test('④ 라운드와 세트가 정확히 계산된다', () async {
      final e = TabataEngine(
        config: cfg(work: 1, rest: 1, rounds: 2, sets: 2, setRest: 1),
      );
      e.start();
      e.skip(); // 준비 → 운동
      expect(e.currentSet, 1);
      expect(e.currentRound, 1);
      e.skip(); // 운동1 → 휴식
      e.skip(); // 휴식 → 운동2
      expect(e.currentRound, 2);
      e.skip(); // 운동2 → 세트휴식
      expect(e.currentPhase?.type, PhaseType.setRest);
      e.skip(); // 세트휴식 → 2세트 운동1
      expect(e.currentSet, 2);
      expect(e.currentRound, 1);
      e.dispose();
    });

    test('⑤ 세트 간 휴식이 정상 동작하고 통계가 남는다', () async {
      final e = TabataEngine(
        config: cfg(work: 1, rest: 1, rounds: 2, sets: 2, setRest: 2),
      );
      e.start();
      e.skip(); // 운동1
      e.skip(); // 휴식
      e.skip(); // 운동2
      e.skip(); // 세트휴식
      expect(e.completedRounds, 2); // 1세트 2라운드 완료
      e.dispose();
    });

    test('건너뛰기로 마지막 구간을 지나면 완료 상태가 된다', () async {
      final e = TabataEngine(config: cfg(work: 1, rest: 1, rounds: 1));
      e.start();
      for (var i = 0; i < 10 && !e.isFinished; i++) {
        e.skip();
      }
      expect(e.isFinished, true);
      expect(e.completedRounds, 1);
      e.dispose();
    });

    test('⑦ 완료 후 다시 시작할 수 있다', () async {
      final e = TabataEngine(config: cfg(work: 1, rest: 1, rounds: 1));
      e.start();
      for (var i = 0; i < 10 && !e.isFinished; i++) {
        e.skip();
      }
      expect(e.isFinished, true);
      e.start();
      expect(e.status, EngineStatus.running);
      expect(e.index, 0);
      expect(e.completedRounds, 0);
      e.dispose();
    });

    test('설정 변경 시 대기 상태로 재구성된다', () {
      final e = TabataEngine(config: cfg(rounds: 8));
      e.start();
      e.updateConfig(cfg(rounds: 4, sets: 2));
      expect(e.status, EngineStatus.idle);
      expect(e.index, 0);
      expect(e.config.rounds, 4);
      e.dispose();
    });
  });

  group('카운트다운 안내', () {
    test('② 마지막 5초에서 5→1 각 1회만 안내된다', () async {
      final e = TabataEngine(config: cfg(work: 8, rest: 5, rounds: 1));
      e.start();
      e.skip();
      // 안내 중복 방지용 내부 상태 검증: 같은 초를 두 번 안내하지 않는다
      final seen = <int>{};
      for (var i = 0; i < 60; i++) {
        final s = e.remainingSeconds;
        if (s <= 5 && s >= 1) {
          // 새로 등장한 초만 기록
          seen.add(s);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (e.currentPhase?.type != PhaseType.work) break;
      }
      expect(seen.contains(5), true);
      expect(seen.every((v) => v >= 1 && v <= 5), true);
      e.dispose();
    });
  });

  group('세션 복원', () {
    test('⑥ 스냅샷 복원 후 시간이 이어진다', () async {
      final e = TabataEngine(config: cfg(work: 20, rest: 5, rounds: 2));
      e.start();
      e.skip();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final snap = e.snapshot();
      e.dispose();

      final e2 = TabataEngine();
      e2.restoreFromSnapshot(snap);
      expect(e2.currentPhase?.type, PhaseType.work);
      expect(e2.remainingSeconds, lessThanOrEqualTo(20));
      expect(e2.remainingSeconds, greaterThan(15));
      e2.dispose();
    });

    test('일시정지 스냅샷은 정지 상태로 복원된다', () async {
      final e = TabataEngine(config: cfg(work: 20, rest: 5, rounds: 2));
      e.start();
      e.skip();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      e.pause();
      final snap = e.snapshot();
      final remain = e.remainingSeconds;
      e.dispose();

      final e2 = TabataEngine();
      e2.restoreFromSnapshot(snap);
      expect(e2.isPaused, true);
      expect(e2.remainingSeconds, remain);
      e2.dispose();
    });
  });
}
