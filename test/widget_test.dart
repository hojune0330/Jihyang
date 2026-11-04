import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/services/tabata_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TabataConfig', () {
    test('페이즈 구성: 운동/휴식/세트휴식 개수와 총 시간', () {
      const cfg = TabataConfig(
        workSeconds: 20,
        restSeconds: 10,
        exerciseCount: 8,
        setCount: 2,
        setRestMinutes: 1,
        prepareSeconds: 10,
      );
      final phases = cfg.buildPhases();
      // 준비1 + 운동8 + 휴식7  = 16 (1세트)  ×2 = 32  + 세트휴식1 = 34
      expect(phases.length, 1 + 15 * 2 + 1);
      expect(cfg.totalSeconds, 10 + 2 * 230 + 60);
      expect(cfg.pureWorkSeconds, 320);
    });

    test('json 왕복 변환이 값을 보존한다', () {
      const cfg = TabataConfig(
        workSeconds: 45,
        restSeconds: 15,
        exerciseCount: 6,
        setCount: 3,
        setRestMinutes: 2,
        prepareSeconds: 5,
      );
      final restored = TabataConfig.fromJson(cfg.toJson());
      expect(restored.workSeconds, 45);
      expect(restored.exerciseCount, 6);
      expect(restored.setCount, 3);
      expect(restored.setRestMinutes, 2);
      expect(restored.prepareSeconds, 5);
    });
  });

  group('TabataEngine (벽시계 기반)', () {
    test('초기 상태는 첫 구간(준비)이고 남은 시간이 설정값과 같다', () {
      final engine = TabataEngine(
        config: const TabataConfig(
          workSeconds: 20,
          restSeconds: 10,
          exerciseCount: 2,
          setCount: 1,
          prepareSeconds: 10,
          soundEnabled: false,
          vibrationEnabled: false,
        ),
      );
      expect(engine.status, EngineStatus.idle);
      expect(engine.remainingSeconds, 10);
      expect(engine.totalSeconds, 10 + 20 + 10 + 20);
      engine.dispose();
    });

    test('시작 후 실제 경과 시간만큼 남은 시간이 줄어든다', () async {
      final engine = TabataEngine(
        config: const TabataConfig(
          workSeconds: 6,
          restSeconds: 4,
          exerciseCount: 2,
          setCount: 1,
          prepareSeconds: 0,
          soundEnabled: false,
          vibrationEnabled: false,
        ),
      );
      engine.start();
      expect(engine.remainingSeconds, 6);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      // 약 1.3초 경과 → 5초 남음 (틱 누적이 아닌 실제 시간 기준)
      expect(engine.remainingSeconds, lessThanOrEqualTo(5));
      expect(engine.remainingSeconds, greaterThanOrEqualTo(4));
      engine.dispose();
    });

    test('일시정지 중에는 시간이 흐르지 않고, 재개하면 이어진다', () async {
      final engine = TabataEngine(
        config: const TabataConfig(
          workSeconds: 20,
          restSeconds: 5,
          exerciseCount: 2,
          setCount: 1,
          prepareSeconds: 0,
          soundEnabled: false,
          vibrationEnabled: false,
        ),
      );
      engine.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      engine.pause();
      final afterPause = engine.remainingSeconds;

      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(engine.remainingSeconds, afterPause); // 멈춰 있음

      engine.resume();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(engine.remainingSeconds, lessThan(afterPause));
      engine.dispose();
    });

    test('구간을 넘어가면 운동 → 휴식으로 자동 전환된다', () async {
      final engine = TabataEngine(
        config: const TabataConfig(
          workSeconds: 1,
          restSeconds: 1,
          exerciseCount: 2,
          setCount: 1,
          prepareSeconds: 0,
          soundEnabled: false,
          vibrationEnabled: false,
        ),
      );
      engine.start();
      expect(engine.currentPhase?.isWorkout, true);
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      expect(engine.currentPhase?.isRest, true);
      engine.dispose();
    });

    test('설정 변경 시 대기 상태로 재구성된다', () {
      final engine = TabataEngine(
        config: const TabataConfig(
          exerciseCount: 8,
          setCount: 1,
          soundEnabled: false,
          vibrationEnabled: false,
        ),
      );
      engine.start();
      engine.updateConfig(
        const TabataConfig(
          exerciseCount: 4,
          setCount: 2,
          setRestMinutes: 1,
          soundEnabled: false,
          vibrationEnabled: false,
        ),
      );
      expect(engine.status, EngineStatus.idle);
      expect(engine.index, 0);
      expect(
        engine.totalSeconds,
        engine.phases.fold<int>(0, (a, p) => a + p.duration),
      );
      engine.dispose();
    });
  });
}
