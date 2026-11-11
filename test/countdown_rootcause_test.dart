import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/services/audio_coach.dart';
import 'package:tabata_timer/services/tabata_engine.dart';

/// 카운트다운 "밀림 / 두 번 반복 / 버벅임 / 끊김" 의 **구조적 원인**을 계측한다.
///
/// 실기기 보고:
///   "5초 카운트다운에서 숫자와 음성 싱크가 안 맞고 음성이 밀리거나
///    두 번 반복, 버벅거림, 끊김의 문제가 계속 발생"
///
/// 가설
/// ----
/// H1. 생명주기 출렁임(resumed)마다 catchUp() 이 불리면 카운트다운 묶음이
///     **다시 시작**된다 → 두 번 반복 / 겹침.
/// H2. 늦게 도착한 예약이 '이미 지난 숫자'를 delay 0 으로 즉시 발화하면
///     숫자가 밀려서 들린다.
/// H3. 묶음 시작 여부를 bool 하나(_countStarted)로만 판단해서, 구간이
///     바뀌어도·재예약돼도 '새로 시작해야 하는지'를 정확히 구분하지 못한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int bundleStarts() => AudioCoach.instance.playLog
      .where((e) => e.kind.startsWith('count@pos'))
      .length;

  /// 짧은 운동(12초)에서 카운트다운은 T+7,8,9,10,11초에 울린다.
  /// 그 사이에 생명주기 출렁임을 여러 번 넣는다 (화면 꺼짐/알림창/전환).
  test('H1: 생명주기 출렁임으로 묶음이 중복 시작되는가', () async {
    AudioCoach.instance.playLog.clear();
    final e = TabataEngine(
      config: const TabataConfig(
        workSeconds: 12,
        restSeconds: 10,
        rounds: 1,
        sets: 1,
        setRestSeconds: 0,
        soundEnabled: true,
        voiceEnabled: true,
        sfxEnabled: true,
      ),
    )..audioOutputEnabled = true;

    e.start();
    e.skip();
    e.cueLog.clear();
    AudioCoach.instance.playLog.clear();

    // 운동 12초. 카운트다운은 7초부터.
    // Android 에서는 화면 꺼짐/알림창/전환이면 resumed 가 자주 온다.
    for (var i = 0; i < 7; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      e.catchUp(); // 앱 복귀
    }
    await Future<void>.delayed(const Duration(milliseconds: 4500));

    final starts = bundleStarts();
    final counts = e.cueLog.where((c) => c.label.startsWith('count')).length;

    // ignore: avoid_print
    print('H1 → 묶음 시작 횟수=$starts, 숫자 발화=$counts');
    // ignore: avoid_print
    print(
      'H1 → playLog: '
      '${AudioCoach.instance.playLog.where((e) => e.kind.startsWith('count')).map((e) => e.kind).toList()}',
    );

    expect(
      starts,
      lessThanOrEqualTo(1),
      reason: '카운트다운 묶음은 구간당 1회만 시작돼야 한다 (실제 $starts회)',
    );
    e.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// pause → resume 을 반복하면 묶음이 몇 번 시작되는가.
  test('H1b: 일시정지/재개 반복으로 묶음이 중복 시작되는가', () async {
    AudioCoach.instance.playLog.clear();
    final e = TabataEngine(
      config: const TabataConfig(
        workSeconds: 12,
        restSeconds: 10,
        rounds: 1,
        sets: 1,
        setRestSeconds: 0,
        soundEnabled: true,
        voiceEnabled: true,
        sfxEnabled: true,
      ),
    )..audioOutputEnabled = true;

    e.start();
    e.skip();
    e.cueLog.clear();
    AudioCoach.instance.playLog.clear();

    // 카운트다운 시작 직전까지
    await Future<void>.delayed(const Duration(milliseconds: 6800));
    // 1초 안에 3번 재개 (사용자가 화면을 여러 번 껐다 켠 상황)
    for (var i = 0; i < 3; i++) {
      e.catchUp();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await Future<void>.delayed(const Duration(milliseconds: 4500));

    final starts = bundleStarts();
    // ignore: avoid_print
    print('H1b → 묶음 시작 횟수=$starts');
    // ignore: avoid_print
    print(
      'H1b → ${AudioCoach.instance.playLog.where((e) => e.kind.startsWith('count')).map((e) => e.kind).toList()}',
    );

    expect(
      starts,
      lessThanOrEqualTo(1),
      reason: '재개를 반복해도 묶음은 1회여야 한다 (실제 $starts회)',
    );
    e.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// H2: 숫자가 벽시계 격자에서 얼마나 밀리는가.
  test('H2: 숫자 발화가 벽시계 1초 격자에서 밀리는가', () async {
    final e = TabataEngine(
      config: const TabataConfig(
        workSeconds: 12,
        restSeconds: 10,
        rounds: 1,
        sets: 1,
        setRestSeconds: 0,
        soundEnabled: true,
        voiceEnabled: false, // 음성 없이 '틱' 경로만 측정
        sfxEnabled: true,
      ),
    )..audioOutputEnabled = false;

    e.start();
    e.skip();
    e.cueLog.clear();
    final phaseStart = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 12100));

    for (final c in e.cueLog) {
      if (!c.label.startsWith('count')) continue;
      final n = int.parse(c.label.substring(5));
      final expectAt = 12000 - n * 1000; // T+7s(n=5) … T+11s(n=1)
      final drift =
          (c.actualWallMs - phaseStart.millisecondsSinceEpoch) - expectAt;
      // ignore: avoid_print
      print('H2 → ${c.label}: 기대 $expectAt ms, 실제 $drift ms 편차');
      expect(
        drift.abs(),
        lessThan(80),
        reason: '${c.label} 이 격자에서 ${drift}ms 밀렸다',
      );
    }
    e.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
