import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabata_timer/screens/history_screen.dart';
import 'package:tabata_timer/services/workout_store.dart';

void main() {
  testWidgets('운동 기록 달력이 날짜와 기록 상세를 보여준다', (tester) async {
    final now = DateTime.now();
    final records = <Map<String, dynamic>>[];
    for (final entry in const [(0, true), (1, true), (3, false), (5, true)]) {
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
      'tabata_workout_records_v1': _encode(records),
    });

    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: HistoryScreen()));
    await tester.runAsync(() => WorkoutStore.load(force: true));
    await tester.pumpAndSettle();

    final monthTitle = '${now.year}년 ${now.month}월';
    expect(find.text(monthTitle), findsOneWidget);
    expect(find.text('${now.day}'), findsWidgets);
    expect(find.text('운동 기록'), findsOneWidget);

    // 오늘 기록 상세가 바로 보여야 한다
    expect(find.text('운동 완료'), findsWidgets);

    // 기록이 있는 날짜를 눌러 상세를 바꾼다
    final aborted = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 3));
    if (aborted.month == now.month) {
      await tester.tap(find.text('${aborted.day}').first);
      await tester.pumpAndSettle();
      expect(find.text('중도 종료'), findsWidgets);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

String _encode(List<Map<String, dynamic>> list) => jsonEncode(list);
