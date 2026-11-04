import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/services/tabata_engine.dart';

/// 카운트다운이 **실제로 1초 간격**으로 울리는지 실측한다.
///
/// 실기기 보고: "5·4·3·2·1 싱크가 전혀 안 맞고 중복돼서 말하거나
/// 안 들리다가 들려"
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('운동 20초 카운트다운이 1초 간격으로 5→1 정확히 울린다', () async {
    final e = TabataEngine(
      config: const TabataConfig(
        workSeconds: 20,
        restSeconds: 10,
        rounds: 1,
        sets: 1,
        setRestSeconds: 0,
        soundEnabled: true,
        voiceEnabled: true,
        sfxEnabled: true,
      ),
    )..audioOutputEnabled = false; // cueLog 로 발화 시각만 측정

    e.start();
    e.skip(); // 준비 10초 건너뛰기
    e.cueLog.clear();
    // 운동 20초: 5→1 은 T+15,16,17,18,19초
    await Future<void>.delayed(const Duration(milliseconds: 19600));

    final hits = <String, int>{};
    for (final c in e.cueLog) {
      if (c.label.startsWith('count')) hits[c.label] = c.actualWallMs;
    }

    // ignore: avoid_print
    print('=== 카운트다운 발화: ${hits.keys.toList()} ===');

    expect(hits.keys.toList(), ['count5', 'count4', 'count3', 'count2', 'count1'],
        reason: '5·4·3·2·1 이 순서대로 한 번씩 울려야 한다: ${hits.keys.toList()}');

    // 간격이 1초 ±120ms 인지 (타이머 지터 허용)
    final order = ['count5', 'count4', 'count3', 'count2', 'count1'];
    for (var i = 1; i < order.length; i++) {
      final gap = hits[order[i]]! - hits[order[i - 1]]!;
      // ignore: avoid_print
      print('${order[i - 1]} → ${order[i]}: ${gap}ms');
      expect((gap - 1000).abs(), lessThan(120),
          reason: '${order[i - 1]}→${order[i]} 간격이 1초가 아니다: ${gap}ms');
    }

    e.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
