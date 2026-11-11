// 실기(웹 CanvasKit) 렌더 검증용 진입점 — 앱 번들에는 포함되지 않는다.
// flutter build web -t tool/shots/running_shot.dart --dart-define=PHASE=prepare
import 'package:flutter/material.dart';
import 'package:tabata_timer/models/tabata_config.dart';
import 'package:tabata_timer/screens/finished_screen.dart';
import 'package:tabata_timer/screens/running_screen.dart';
import 'package:tabata_timer/services/tabata_engine.dart';
import 'package:tabata_timer/theme/app_theme.dart';

void main() {
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
      home: phase == 'finished'
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
