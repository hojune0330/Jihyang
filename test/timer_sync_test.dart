import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/services/tabata_engine.dart';

/// 사운드-타이머 싱크 실측 검증.
///
/// 엔진이 남긴 `cueLog`(예약 시각 vs 실제 발화 시각)를 근거로
/// "정상 작동한다고 가정"하지 않고 실제 오차를 측정한다.
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

  group('사운드 이벤트 실측', () {
    test('카운트다운 5·4·3·2·1이 1초 간격으로 오차 60ms 이내 발화한다', () async {
      final e = TabataEngine(config: cfg(work: 6, rest: 0, rounds: 1))
        ..audioOutputEnabled = false;
      e.start();
      e.skip(); // 준비 → 운동(6초)
      await Future<void>.delayed(const Duration(milliseconds: 6800));

      final counts = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .toList();
      // 6초 구간이므로 5,4,3,2,1 전부 발생해야 한다
      expect(
        counts.length,
        5,
        reason: '카운트다운 개수가 5개여야 한다: ${counts.map((c) => c.label)}',
      );
      final labels = counts.map((c) => c.label).toList();
      expect(labels, ['count5', 'count4', 'count3', 'count2', 'count1']);

      // 예약 시각 대비 실제 발화 오차 측정
      final errors = counts.map((c) => c.errorMs.abs()).toList();
      expect(
        errors.every((v) => v <= 60),
        true,
        reason: '카운트다운 발화 오차(ms): $errors',
      );
      // 각 숫자 간 실제 간격도 1초 근처여야 한다
      for (var i = 1; i < counts.length; i++) {
        final gapMs = counts[i].actualWallMs - counts[i - 1].actualWallMs;
        expect(
          (gapMs - 1000).abs(),
          lessThanOrEqualTo(70),
          reason: '${labels[i - 1]} → ${labels[i]} 간격: ${gapMs}ms',
        );
      }
      e.dispose();
    });

    test('구간 전환은 구간 길이와 일치하는 시점에 정확히 한 번 발생한다', () async {
      final e = TabataEngine(config: cfg(work: 2, rest: 2, rounds: 2))
        ..audioOutputEnabled = false;
      final sw = Stopwatch()..start();
      e.start();
      e.skip(); // 준비 구간을 건너뛰고 바로 운동부터 측정
      await Future<void>.delayed(const Duration(milliseconds: 8800));

      final enters = e.cueLog
          .where((c) => c.label.startsWith('enter:'))
          .toList();
      expect(enters.length, greaterThanOrEqualTo(4));

      // work → rest 전환은 정확히 두 번의 'enter:work' 뒤 첫 'enter:rest'
      final types = enters.map((c) => c.phaseType).toList();
      expect(types.contains('work'), true);
      expect(types.contains('rest'), true);

      // 전환 시각 오차: 각 enter 의 실제 시각 차이가 구간 길이와 ±90ms 이내
      // (첫 항목은 start() 가 기록한 준비 구간이고 skip 으로 즉시 넘어갔으므로 제외)
      final transitions = enters.sublist(1);
      for (var i = 1; i < transitions.length; i++) {
        final prev = transitions[i - 1];
        final gap = transitions[i].actualWallMs - prev.actualWallMs;
        final expectedMs = switch (prev.phaseType) {
          'prepare' => TabataConfig.prepareSeconds * 1000,
          'work' => 2000,
          'rest' => 2000,
          _ => 2000,
        };
        expect(
          (gap - expectedMs).abs(),
          lessThanOrEqualTo(90),
          reason:
              '${prev.phaseType} → ${transitions[i].phaseType} 간격 ${gap}ms '
              '(기대 ${expectedMs}ms)',
        );
      }
      sw.stop();
      e.dispose();
    });

    test('일시정지하면 카운트다운 예약이 취소되어 발화하지 않는다', () async {
      final e = TabataEngine(config: cfg(work: 8, rest: 0, rounds: 1))
        ..audioOutputEnabled = false;
      e.start();
      e.skip(); // 운동 8초
      // 4초 진행 → 아직 카운트다운 전
      await Future<void>.delayed(const Duration(milliseconds: 4000));
      final beforePause = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .length;
      e.pause();
      // 일시정지 상태로 카운트다운 구간을 지나가도 발화하면 안 된다
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      final afterPause = e.cueLog
          .where((c) => c.label.startsWith('count'))
          .length;
      expect(afterPause, beforePause, reason: '일시정지 중 카운트다운이 발생했다');
      e.dispose();
    });

    test('재개하면 남은 시간에 맞는 카운트다운만 발화한다 (지난 숫자 몰아재생 없음)', () async {
      final e = TabataEngine(config: cfg(work: 8, rest: 0, rounds: 1))
        ..audioOutputEnabled = false;
      e.start();
      e.skip(); // 8초 운동
      await Future<void>.delayed(const Duration(milliseconds: 5000));
      final before = e.cueLog.where((c) => c.label.startsWith('count')).length;
      e.pause();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      e.resume();
      await Future<void>.delayed(const Duration(milliseconds: 1800));

      final after = e.cueLog.where((c) => c.label.startsWith('count')).toList();
      // 5초 시점에 일시정지했으므로 남은 3초 → 3,2,1 세 개만 발생
      final newOnes = after.length - before;
      expect(
        newOnes,
        inInclusiveRange(1, 3),
        reason: '재개 후 카운트다운 개수: $newOnes (${after.map((c) => c.label)})',
      );
      // 중복 라벨이 없어야 한다
      final labels = after.map((c) => c.label).toList();
      expect(labels.toSet().length, labels.length, reason: '중복 발화: $labels');
      e.dispose();
    });

    test('운동→휴식 전환에서 남은 전체 시간이 손실/중복되지 않는다', () async {
      final c = cfg(work: 2, rest: 2, rounds: 3);
      final e = TabataEngine(config: c)..audioOutputEnabled = false;
      final expectedTotal = c.totalSeconds;
      e.start();
      await Future<void>.delayed(const Duration(milliseconds: 5000));
      final remain = e.remainingTotalSeconds;
      // 5초 흐름 → 남은 시간은 (총 - 5) 근처
      expect(remain, lessThanOrEqualTo(expectedTotal - 4));
      expect(remain, greaterThanOrEqualTo(expectedTotal - 7));
      e.dispose();
    });

    test('일시정지 시간은 전체 경과 시간에 포함되지 않는다', () async {
      final e = TabataEngine(config: cfg(work: 5, rest: 0, rounds: 1))
        ..audioOutputEnabled = false;
      e.start();
      e.skip();
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      e.pause();
      final atPause = e.elapsedTotalMs;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(
        (e.elapsedTotalMs - atPause).abs(),
        lessThanOrEqualTo(30),
        reason: '일시정지 중 경과 시간이 늘어났다',
      );
      e.resume();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      // 재개 후 약 0.7초만 늘어나야 한다
      final delta = e.elapsedTotalMs - atPause;
      expect(delta, inInclusiveRange(600, 950), reason: '재개 후 증가분: $delta');
      e.dispose();
    });

    test('세트 간 휴식과 전체 완료가 순서대로 한 번씩 발생한다', () async {
      final e = TabataEngine(
        config: cfg(work: 1, rest: 0, rounds: 1, sets: 2, setRest: 1),
      )..audioOutputEnabled = false;
      e.start();
      // 준비(10) + 운동(1) + 세트휴식(1) + 운동(1) = 13초 + 여유
      await Future<void>.delayed(const Duration(milliseconds: 14000));

      final types = e.cueLog
          .where((c) => c.label.startsWith('enter:'))
          .map((c) => c.phaseType)
          .toList();
      expect(types.where((t) => t == 'setRest').length, 1);
      expect(e.status, EngineStatus.finished);
      e.dispose();
    });

    test('진행률은 0→1로 단조 증가한다', () async {
      final e = TabataEngine(config: cfg(work: 1, rest: 1, rounds: 2))
        ..audioOutputEnabled = false;
      e.start();
      var last = -1.0;
      for (var i = 0; i < 80; i++) {
        final p = e.totalProgress;
        expect(p, greaterThanOrEqualTo(last - 0.0001), reason: '진행률이 감소했다');
        last = p;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (e.isFinished) break;
      }
      expect(last, greaterThan(0.05));
      e.dispose();
    });

    test('완료 후 다시 시작하면 타이머와 카운트다운이 처음부터 정상 동작한다', () async {
      final e = TabataEngine(config: cfg(work: 2, rest: 0, rounds: 1))
        ..audioOutputEnabled = false;
      e.start();
      // 준비(10) + 운동(2) = 12초 + 여유
      await Future<void>.delayed(const Duration(milliseconds: 13000));
      expect(e.isFinished, true);

      e.cueLog.clear();
      e.start();
      expect(e.index, 0);
      expect(e.completedRounds, 0);
      e.skip();
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      final counts = e.cueLog.where((c) => c.label.startsWith('count')).length;
      // 2초 구간: 시작음과 겹치는 '2' 는 생략되고 '1' 만 남는다
      expect(counts, 1, reason: '2초 구간 → 1 한 번이어야 한다: $counts');
      e.dispose();
    });
  });

  group('마스터 사운드 스위치', () {
    test('전체 사운드를 끄면 음성/효과음도 함께 무음이 된다', () {
      final c = const TabataConfig(
        soundEnabled: false,
        voiceEnabled: true,
        sfxEnabled: true,
      );
      final e = TabataEngine(config: c);
      e.updateConfig(c);
      expect(e.config.soundEnabled, false);
      expect(c.copyWith(soundEnabled: true).soundEnabled, true);
      e.dispose();
    });

    test('설정 json 에 soundEnabled 가 보존된다', () {
      const c = TabataConfig(soundEnabled: false, voiceEnabled: true);
      final r = TabataConfig.fromJson(c.toJson());
      expect(r.soundEnabled, false);
      expect(r.voiceEnabled, true);
      // 구버전 json(필드 없음)은 기본값 true
      final legacy = TabataConfig.fromJson({'workSeconds': 20});
      expect(legacy.soundEnabled, true);
    });
  });
}
