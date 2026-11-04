import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/main.dart';
import 'package:tabata_timer/models/tabata_config.dart';

void main() {
  testWidgets('홈 화면이 렌더링된다', (WidgetTester tester) async {
    await tester.pumpWidget(const TabataApp());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('TABATA'), findsOneWidget);
  });

  test('페이즈 구성이 올바르게 생성된다', () {
    const cfg = TabataConfig(
      workSeconds: 20,
      restSeconds: 10,
      exerciseCount: 8,
      setCount: 2,
      setRestMinutes: 2,
      prepareSeconds: 10,
    );
    final phases = cfg.buildPhases();
    // 준비1 + (운동8 + 휴식7)*2 + 세트휴식1
    expect(phases.length, 1 + 30 + 1);
    expect(cfg.totalSeconds, 10 + 2 * 230 + 120);
    expect(cfg.pureWorkSeconds, 2 * 8 * 20);
  });
}
