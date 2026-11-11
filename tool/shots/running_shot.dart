// 실기(웹 CanvasKit) 렌더 검증용 진입점 — 앱 번들에는 포함되지 않는다.
// flutter build web -t tool/shots/running_shot.dart --dart-define=PHASE=prepare
import 'package:flutter/material.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabata_timer/screens/finished_screen.dart';
import 'package:tabata_timer/screens/history_screen.dart';
import 'package:tabata_timer/screens/ready_screen.dart';
import 'package:tabata_timer/screens/settings_screen.dart';
import 'package:tabata_timer/services/workout_store.dart';
import 'package:tabata_timer/screens/running_screen.dart';
import 'package:tabata_timer/services/tabata_engine.dart';
import 'package:tabata_timer/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _seedRecords();
  const phase = String.fromEnvironment('PHASE', defaultValue: 'prepare');
  final engine = TabataEngine(
    config: const TabataConfig(
      workSeconds: 30,
      restSeconds: 15,
      rounds: 8,
      sets: 2,
      setRestSeconds: 60,
      soundEnabled: false,
    ),
  )..audioOutputEnabled = false;
  engine.start();
  if (phase != 'prepare') engine.skip();
  if (phase == 'rest') engine.skip();
  if (const bool.fromEnvironment('PAUSED', defaultValue: true)) engine.pause();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: phase == 'ready'
          ? ReadyScreen(
              config: engine.config,
              onStart: () {},
              onOpenSettings: () {},
              onOpenHistory: () {},
              hasSavedSession: false,
              onResumeSession: () {},
              todayCount: 1,
            )
          : phase == 'settings'
          ? SettingsScreen(initial: engine.config)
          : phase == 'history'
          ? const HistoryScreen()
          : phase == 'finished'
          ? FinishedScreen(
              sets: 2,
              totalSets: 2,
              rounds: 16,
              totalRounds: 16,
              elapsedMs: 820000,
              onRestart: () {},
              onHome: () {},
            )
          : ListenableBuilder(
              listenable: engine,
              builder: (_, _) => RunningScreen(
                engine: engine,
                onPauseToggle: engine.toggle,
                onStop: () {},
                onSkip: engine.skip,
              ),
            ),
    ),
  );
}

Future<void> _seedRecords() async {
  final now = DateTime.now();
  final list = <Map<String, dynamic>>[];
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
    list.add({
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
  final p = await SharedPreferences.getInstance();
  await p.setString('tabata_workout_records_v1', jsonEncode(list));
  await WorkoutStore.load(force: true);
}
