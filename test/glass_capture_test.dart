import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/screens/finished_screen.dart';
import 'package:tabata_timer/screens/history_screen.dart';
import 'package:tabata_timer/screens/ready_screen.dart';
import 'package:tabata_timer/screens/running_screen.dart';
import 'package:tabata_timer/screens/settings_screen.dart';
import 'package:tabata_timer/services/tabata_engine.dart';
import 'package:tabata_timer/services/workout_store.dart';
import 'package:tabata_timer/theme/app_theme.dart';

/// 글래스 디자인 개선 전/후 비교용 화면 캡처.
///
/// 실행: flutter test test/glass_capture_test.dart --dart-define=GLASS_STAGE=before
/// 결과: docs/glass/(stage)/*.png (390x844 @2x)
const _stage = String.fromEnvironment('GLASS_STAGE', defaultValue: 'tmp');

Future<void> _loadFonts() async {
  final loader = FontLoader('Pretendard');
  for (final f in const [
    'assets/fonts/Pretendard-Regular.otf',
    'assets/fonts/Pretendard-SemiBold.otf',
    'assets/fonts/Pretendard-Bold.otf',
    'assets/fonts/Pretendard-ExtraBold.otf',
  ]) {
    loader.addFont(
      File(
        f,
      ).readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)),
    );
  }
  await loader.load();
  final icons = FontLoader('MaterialIcons');
  final iconFile = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}'
    '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (iconFile.existsSync()) {
    icons.addFont(
      iconFile.readAsBytes().then(
        (b) => ByteData.view(Uint8List.fromList(b).buffer),
      ),
    );
    await icons.load();
  }
}

Future<void> _shot(WidgetTester tester, Key key, String name) async {
  final dir = Directory('docs/glass/$_stage')..createSync(recursive: true);
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _pump(WidgetTester tester, Key key, Widget home) async {
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: RepaintBoundary(key: key, child: home),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(_loadFonts);

  setUp(() async {
    final now = DateTime.now();
    final records = <Map<String, dynamic>>[];
    for (final e in const [
      (0, true),
      (1, true),
      (3, false),
      (5, true),
      (8, true),
    ]) {
      final st = DateTime(
        now.year,
        now.month,
        now.day,
        7,
        30,
      ).subtract(Duration(days: e.$1));
      records.add({
        'id': st.millisecondsSinceEpoch,
        'startedAt': st.millisecondsSinceEpoch,
        'endedAt': st.add(const Duration(minutes: 6)).millisecondsSinceEpoch,
        'workSeconds': 30,
        'restSeconds': 15,
        'rounds': 8,
        'sets': 1,
        'setRestSeconds': 0,
        'plannedSeconds': 355,
        'activeSeconds': 300,
        'completedRounds': e.$2 ? 8 : 3,
        'completedSets': e.$2 ? 1 : 0,
        'totalRounds': 8,
        'outcome': e.$2 ? 'completed' : 'aborted',
        'progress': e.$2 ? 1.0 : 0.35,
      });
    }
    SharedPreferences.setMockInitialValues({
      'tabata_workout_records_v1': jsonEncode(records),
    });
    await WorkoutStore.load(force: true);
  });

  const cfg = TabataConfig(
    workSeconds: 30,
    restSeconds: 15,
    rounds: 8,
    sets: 2,
    setRestSeconds: 60,
  );

  testWidgets('캡처: 메인', (tester) async {
    const key = ValueKey('shot');
    await _pump(
      tester,
      key,
      ReadyScreen(
        config: cfg,
        onStart: () {},
        onOpenSettings: () {},
        onOpenHistory: () {},
        hasSavedSession: false,
        onResumeSession: () {},
        todayCount: 2,
      ),
    );
    await _shot(tester, key, '1_ready');
  });

  testWidgets('캡처: 설정', (tester) async {
    const key = ValueKey('shot');
    await _pump(tester, key, const SettingsScreen(initial: cfg));
    await _shot(tester, key, '2_settings');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, key, '2_settings_sound');
  });

  testWidgets('캡처: 휠 시트', (tester) async {
    const key = ValueKey('shot');
    await _pump(tester, key, const SettingsScreen(initial: cfg));
    await tester.tap(find.text('운동 시간'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    // 시트는 오버레이라 앱 전체를 찍는다
    final dir = Directory('docs/glass/$_stage')..createSync(recursive: true);
    await tester.runAsync(() async {
      final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      final image = await layer.toImage(
        Offset.zero & tester.view.physicalSize,
        pixelRatio: 1,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${dir.path}/2_settings_sheet.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });

  testWidgets('캡처: 운동 기록', (tester) async {
    const key = ValueKey('shot');
    await _pump(tester, key, const HistoryScreen());
    await _shot(tester, key, '3_history');
  });

  for (final phase in ['prepare', 'work', 'rest']) {
    testWidgets('캡처: 진행 $phase', (tester) async {
      const key = ValueKey('shot');
      final engine = TabataEngine(config: cfg)..audioOutputEnabled = false;
      engine.start();
      if (phase != 'prepare') engine.skip(); // 준비 → 운동
      if (phase == 'rest') engine.skip(); // 운동 → 휴식
      engine.pause();
      await _pump(
        tester,
        key,
        RunningScreen(
          engine: engine,
          onPauseToggle: () {},
          onStop: () {},
          onSkip: () {},
        ),
      );
      await _shot(tester, key, '4_running_$phase');
      engine.reset();
      engine.dispose();
      // 오디오 채널 타임아웃 타이머(2.5s) 소진
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
    });
  }

  testWidgets('캡처: 완료', (tester) async {
    const key = ValueKey('shot');
    await _pump(
      tester,
      key,
      FinishedScreen(
        sets: 2,
        totalSets: 2,
        rounds: 16,
        totalRounds: 16,
        elapsedMs: 1000 * (60 * 13 + 40),
        onRestart: () {},
        onHome: () {},
      ),
    );
    await _shot(tester, key, '5_finished');
  });
}
