import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabata_timer/screens/history_screen.dart';
import 'package:tabata_timer/services/workout_store.dart';
import 'package:tabata_timer/theme/app_theme.dart';

Future<void> _capture(WidgetTester tester, String path) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  final now = DateTime.now();

  setUpAll(() async {
    final loader = FontLoader('Pretendard');
    for (final f in const [
      'assets/fonts/Pretendard-Regular.otf',
      'assets/fonts/Pretendard-SemiBold.otf',
      'assets/fonts/Pretendard-Bold.otf',
      'assets/fonts/Pretendard-ExtraBold.otf',
    ]) {
      loader.addFont(
        File(f).readAsBytes().then(
          (b) => ByteData.view(Uint8List.fromList(b).buffer),
        ),
      );
    }
    await loader.load();
  });

  setUp(() async {
    final records = <Map<String, dynamic>>[];
    for (final entry in const [
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
      ).subtract(Duration(days: entry.$1));
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
        'completedRounds': entry.$2 ? 8 : 3,
        'completedSets': entry.$2 ? 1 : 0,
        'totalRounds': 8,
        'outcome': entry.$2 ? 'completed' : 'aborted',
        'progress': entry.$2 ? 1.0 : 0.35,
      });
    }
    SharedPreferences.setMockInitialValues({
      'tabata_workout_records_v1': jsonEncode(records),
    });
    await WorkoutStore.load(force: true);
  });

  testWidgets('캡처: 운동 기록 달력', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: RepaintBoundary(child: const HistoryScreen()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    await _capture(tester, '/tmp/shot_history.png');
    expect(find.text('${now.day}'), findsWidgets);
  });
}
