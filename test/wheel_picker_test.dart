import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/screens/ready_screen.dart';
import 'package:tabata_timer/screens/settings_screen.dart';
import 'package:tabata_timer/theme/app_theme.dart';
import 'package:tabata_timer/widgets/wheel_picker.dart';

/// 휠 피커가 "드래그하는 것처럼 보이는 효과"가 아니라
/// 실제 손가락 드래그로 값이 바뀌는지 위젯 테스트로 검증한다.
void main() {
  group('휠 피커 — 실제 드래그', () {
    testWidgets('위로 드래그하면 값이 증가한다', (tester) async {
      var value = 30;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: StatefulBuilder(
                builder: (ctx, setState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WheelColumn(
                      value: value,
                      min: 0,
                      max: 59,
                      accent: AppColors.rest,
                      onChanged: (v) => setState(() => value = v),
                    ),
                    Text('VALUE:$value'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('VALUE:30'), findsOneWidget);

      // 실제 손가락 드래그 (위로 = 값 증가)
      await tester.drag(
        find.byType(ListWheelScrollView),
        const Offset(0, -132), // 44px * 3칸
      );
      await tester.pumpAndSettle();

      expect(
        value,
        greaterThan(30),
        reason: '위로 드래그했는데 값이 증가하지 않았다 (value=$value)',
      );
    });

    testWidgets('아래로 드래그하면 값이 감소한다', (tester) async {
      var value = 30;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (ctx, setState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WheelColumn(
                      value: value,
                      min: 0,
                      max: 59,
                      accent: AppColors.rest,
                      onChanged: (v) => setState(() => value = v),
                    ),
                    Text('VALUE:$value'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListWheelScrollView), const Offset(0, 132));
      await tester.pumpAndSettle();

      expect(
        value,
        lessThan(30),
        reason: '아래로 드래그했는데 값이 감소하지 않았다 (value=$value)',
      );
    });

    testWidgets('분/초가 서로 독립적으로 바뀐다', (tester) async {
      var seconds = 90; // 1분 30초
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (ctx, setState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WheelDurationPicker(
                      seconds: seconds,
                      accent: AppColors.work,
                      onChanged: (v) => setState(() => seconds = v),
                    ),
                    Text('SEC:$seconds'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 초 컬럼(오른쪽)만 위로 드래그 → 초만 증가, 분은 유지
      final wheels = find.byType(ListWheelScrollView);
      expect(wheels, findsNWidgets(2));
      await tester.drag(wheels.at(1), const Offset(0, -88));
      await tester.pumpAndSettle();

      final m = seconds ~/ 60;
      final s = seconds % 60;
      expect(m, 1, reason: '분이 함께 바뀌면 안 된다 (seconds=$seconds)');
      expect(s, greaterThan(30), reason: '초가 증가하지 않았다 (seconds=$seconds)');
    });

    testWidgets('경계값을 넘어가지 않는다 (0 ~ 59)', (tester) async {
      var value = 2;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (ctx, setState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WheelColumn(
                      value: value,
                      min: 0,
                      max: 59,
                      accent: AppColors.rest,
                      onChanged: (v) => setState(() => value = v),
                    ),
                    Text('VALUE:$value'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 크게 아래로 드래그 (0 아래로는 안 내려감)
      await tester.drag(find.byType(ListWheelScrollView), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(value, 0);

      // 크게 위로 여러 번 드래그 (59 위로는 안 올라감)
      for (var i = 0; i < 6; i++) {
        await tester.drag(
          find.byType(ListWheelScrollView),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
      }
      expect(value, 59);
    });
  });

  group('설정 화면 — 휠 시트', () {
    testWidgets('운동 시간 행을 누르면 휠 피커 시트가 열리고 드래그로 값이 바뀐다', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      TabataConfig? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(ctx).push<TabataConfig>(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(
                          initial: TabataConfig(workSeconds: 30),
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('운동 시간'), findsOneWidget);
      await tester.tap(find.text('운동 시간'));
      await tester.pumpAndSettle();

      // 시트가 열리면 휠이 2개(분/초) 보인다
      expect(find.byType(ListWheelScrollView), findsNWidgets(2));

      // 초 컬럼을 위로 드래그
      await tester.drag(
        find.byType(ListWheelScrollView).at(1),
        const Offset(0, -88),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(
        result!.workSeconds,
        greaterThan(30),
        reason: '드래그한 값이 설정에 반영되지 않았다 (${result!.workSeconds})',
      );
    });
  });

  group('메인 화면', () {
    testWidgets('운동/휴식/라운드/세트/세트간휴식/총 소요시간이 모두 보인다', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const cfg = TabataConfig(
        workSeconds: 10,
        restSeconds: 5,
        rounds: 2,
        sets: 2,
        setRestSeconds: 60,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ReadyScreen(
            config: cfg,
            onStart: () {},
            onOpenSettings: () {},
            onOpenHistory: () {},
            hasSavedSession: false,
            onResumeSession: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('운동 시간'), findsOneWidget);
      expect(find.text('휴식 시간'), findsOneWidget);
      expect(find.text('00:10'), findsOneWidget);
      expect(find.text('00:05'), findsOneWidget);
      expect(find.text('라운드'), findsOneWidget);
      expect(find.text('세트'), findsOneWidget);
      expect(find.text('세트 간 휴식'), findsOneWidget);
      expect(find.text('총 소요 시간'), findsOneWidget);
      // 준비10 + 25 + 60 + 25 = 120초 → 2분 00초
      expect(find.text('2분 00초'), findsOneWidget);
      expect(find.text('운동 기록'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('세트가 1개여도 레이아웃이 깨지지 않는다', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ReadyScreen(
            config: const TabataConfig(rounds: 8, sets: 1),
            onStart: () {},
            onOpenSettings: () {},
            onOpenHistory: () {},
            hasSavedSession: false,
            onResumeSession: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('총 소요 시간'), findsOneWidget);
    });
  });
}
