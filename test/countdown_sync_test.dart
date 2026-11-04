import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/services/audio_coach.dart';
import 'package:tabata_timer/services/tabata_engine.dart';

/// 카운트다운 싱크·중복 버그 회귀 테스트.
///
/// 실기기 보고: "5·4·3·2·1 싱크가 전혀 안 맞고 중복돼서 말하거나
/// 안 들리다가 들려"
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TabataEngine build() => TabataEngine(
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
      )..audioOutputEnabled = true;

  List<String> countStarts() => AudioCoach.instance.playLog
      .where((l) => l.kind.startsWith('count@'))
      .map((l) => l.kind)
      .toList();

  test('catchUp 이 카운트다운 도중에 와도 묶음은 한 번만 재생된다', () async {
    final e = build();
    AudioCoach.instance.playLog.clear();
    e.start();
    e.skip();
    AudioCoach.instance.playLog.clear();

    // 운동 20초 중 T+16.5s → 4번 숫자 무렵. 그때 앱 복귀(catchUp)
    await Future<void>.delayed(const Duration(milliseconds: 16500));
    e.catchUp();
    await Future<void>.delayed(const Duration(milliseconds: 3500));

    final starts = countStarts();
    // ignore: avoid_print
    print('catchUp 후 묶음 시작: $starts');
    expect(starts.length, 1,
        reason: '묶음이 여러 번 시작되면 숫자가 중복 재생된다: $starts');

    e.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('일시정지 후 재개해도 이미 울린 숫자를 다시 읽지 않는다', () async {
    final e = build();
    e.start();
    e.skip();

    // T+15.2s (= 5·4 가 울린 뒤) 에 일시정지
    await Future<void>.delayed(const Duration(milliseconds: 15200));
    e.pause();
    final announcedBefore = e.announcedCount;
    AudioCoach.instance.playLog.clear();

    await Future<void>.delayed(const Duration(milliseconds: 600));
    e.resume();
    await Future<void>.delayed(const Duration(milliseconds: 4600));

    // 재개 후 재생된 묶음은 '남은 숫자 위치' 에서 시작해야 한다
    final starts = countStarts();
    // ignore: avoid_print
    print('재개 전 울린 숫자 수: $announcedBefore / 재개 후 묶음: $starts');

    // 재개 후에는 최대 한 번만 시작
    expect(starts.length, lessThanOrEqualTo(1),
        reason: '재개 때 묶음이 중복 시작됐다: $starts');

    // 시작 위치가 5(0ms) 가 아니어야 한다 = 지난 숫자를 다시 읽지 않았다
    if (starts.isNotEmpty) {
      final pos = int.parse(starts.first.replaceAll(RegExp(r'[^0-9]'), ''));
      expect(pos, greaterThan(0),
          reason: '재개 후 5번부터 다시 읽었다 (중복): $starts');
    }

    e.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('묶음 파일은 숫자 간격이 정확히 1초여야 한다', () async {
    // 파일 구조 자체를 검증 (assets/audio/cnt_*.wav)
    // 테스트 환경에서는 파일을 읽지 않고 상수 계약만 확인한다.
    expect(countStepMs, 1000);
    expect(countBundleLastMs, 4000);
    for (final style in ['male', 'female', 'baby']) {
      expect(cntDurMs[style], greaterThan(4200),
          reason: '$style 묶음이 5번째 숫자까지 담지 못한다');
    }
  });
}
