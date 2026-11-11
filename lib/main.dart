import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'models/tabata_config.dart';
import 'models/workout_record.dart';
import 'screens/finished_screen.dart';
import 'screens/history_screen.dart';
import 'screens/ready_screen.dart';
import 'screens/running_screen.dart';
import 'screens/settings_screen.dart';
import 'services/audio_coach.dart';
import 'services/config_store.dart';
import 'services/notification_service.dart';
import 'services/session_store.dart';
import 'services/tabata_engine.dart';
import 'services/workout_store.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  await AudioCoach.instance.init();
  await NotificationService.instance.init();
  NotificationService.instance.cancelLegacyRoutineAlarms();
  runApp(const TabataApp());
}

class TabataApp extends StatelessWidget {
  const TabataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '타바타 타이머',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const _ShotWrapper(child: AppShell()),
    );
  }
}

/// 스크린샷 검증용 래퍼 (--dart-define=SHOT=settings|finished|history)
class _ShotWrapper extends StatelessWidget {
  const _ShotWrapper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      const shot = String.fromEnvironment('SHOT');
      if (shot == 'settings') {
        return const SettingsScreen(initial: TabataConfig());
      }
      if (shot == 'finished') {
        return FinishedScreen(
          sets: 2,
          totalSets: 2,
          rounds: 16,
          totalRounds: 16,
          elapsedMs: 1000 * 60 * 22 + 1000 * 43,
          onRestart: () {},
          onHome: () {},
        );
      }
      if (shot == 'history') {
        return const HistoryScreen();
      }
    }
    return child;
  }
}

enum AppScreen { ready, running, finished }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late final TabataEngine _engine;
  TabataConfig _config = const TabataConfig();
  bool _loaded = false;
  AppScreen _screen = AppScreen.ready;
  bool _hasSavedSession = false;
  int _todayCount = 0;

  DateTime _lastSnapshot = DateTime.fromMillisecondsSinceEpoch(0);
  bool _wakelockOn = false;

  /// 이번 세션 기록이 이미 저장되었는지 (중복 저장 방지)
  bool _recordSaved = false;

  /// 이번 앱 실행에서 오디오 잠금 해제 + 사전 로딩을 마쳤는가.
  ///
  /// 웹은 첫 제스처 전까지 소리를 낼 수 없다. 준비 화면에서 미리 풀어 두면
  /// 운동 시작 직후 첫 음성도 지연 없이 나간다.
  bool _audioReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine = TabataEngine()..addListener(_onEngine);
    _boot();
  }

  Future<void> _boot() async {
    var cfg = await ConfigStore.load();
    // 검증용 빠른 설정 (빌드 시 --dart-define=FAST=true)
    if (const bool.fromEnvironment('FAST')) {
      cfg = const TabataConfig(
        workSeconds: 4,
        restSeconds: 3,
        rounds: 3,
        sets: 2,
        setRestSeconds: 4,
        soundEnabled: true,
        voiceEnabled: true,
        sfxEnabled: true,
      );
    }
    final session = await SessionStore.load();
    final records = await WorkoutStore.load(force: true);
    if (!mounted) return;

    setState(() {
      _config = cfg;
      _loaded = true;
      _todayCount = WorkoutStore.today(records).length;
    });
    _engine.updateConfig(cfg);

    if (session != null) {
      _engine.restoreFromSnapshot(session);
      final restoredConfig = _engine.config;
      final restored = _engine.isRunning || _engine.isPaused;
      if (!mounted) return;
      setState(() {
        _config = restoredConfig;
        _hasSavedSession = restored;
      });
      if (restored) _recordSaved = false;
    }

    // 화면 검증용 자동 시작 (빌드 시 --dart-define=AUTOSTART=true)
    if (const bool.fromEnvironment('AUTOSTART')) {
      _start();
    }
  }

  void _onEngine() {
    if (!mounted) return;
    final status = _engine.status;
    AppScreen target;
    if (status == EngineStatus.finished) {
      target = AppScreen.finished;
    } else if (status == EngineStatus.running ||
        status == EngineStatus.paused) {
      target = AppScreen.running;
    } else {
      target = AppScreen.ready;
    }
    if (target != _screen) {
      setState(() => _screen = target);
    } else {
      setState(() {});
    }
    _syncSideEffects(status);
    _persistSession();
    if (status == EngineStatus.finished) _saveRecordIfNeeded();
  }

  void _syncSideEffects(EngineStatus status) {
    final keepAwake =
        status == EngineStatus.running || status == EngineStatus.paused;
    if (keepAwake != _wakelockOn) {
      _wakelockOn = keepAwake;
      WakelockPlus.toggle(enable: keepAwake).catchError((_) {});
    }
  }

  void _persistSession() {
    if (_engine.isIdle || _engine.isFinished) {
      if (_lastSnapshot.millisecondsSinceEpoch != 0) {
        _lastSnapshot = DateTime.fromMillisecondsSinceEpoch(0);
        SessionStore.clear();
      }
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastSnapshot).inMilliseconds < 1000) return;
    _lastSnapshot = now;
    SessionStore.save(_engine.snapshot());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _engine.catchUp();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (!_engine.isIdle && !_engine.isFinished) {
        SessionStore.save(_engine.snapshot());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.removeListener(_onEngine);
    _engine.dispose();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  // ------------------------------------------------------------ 기록

  /// 완료 / 중도 종료 모두 기록으로 남긴다.
  Future<void> _saveRecordIfNeeded() async {
    if (_recordSaved) return;
    final started = _engine.sessionStartedAt;
    if (started == null) return;
    _recordSaved = true;

    final cfg = _engine.config;
    final activeSec = (_engine.elapsedTotalMs / 1000).round();
    final progress = _engine.totalProgress.clamp(0.0, 1.0);
    final completed = _engine.isFinished && progress >= 0.999;

    final rec = WorkoutRecord(
      id: started.millisecondsSinceEpoch,
      startedAt: started,
      endedAt: DateTime.now(),
      workSeconds: cfg.workSeconds,
      restSeconds: cfg.restSeconds,
      rounds: cfg.rounds,
      sets: cfg.sets,
      setRestSeconds: cfg.setRestSeconds,
      plannedSeconds: cfg.totalSeconds,
      activeSeconds: activeSec,
      completedRounds: _engine.completedRounds,
      completedSets: _engine.completedSets,
      totalRounds: cfg.totalRounds,
      outcome: completed ? SessionOutcome.completed : SessionOutcome.aborted,
      progress: progress,
    );

    final added = await WorkoutStore.add(rec);
    if (!mounted) return;
    final records = await WorkoutStore.load(force: true);
    if (!mounted) return;
    setState(() => _todayCount = WorkoutStore.today(records).length);
    if (kDebugMode) debugPrint('record saved: added=$added $rec');
  }

  // ------------------------------------------------------------ 액션

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<TabataConfig>(
      MaterialPageRoute(builder: (_) => SettingsScreen(initial: _config)),
    );
    await AudioCoach.instance.stopAll();
    if (result == null || !mounted) return;
    setState(() => _config = result);
    _engine.updateConfig(result);
    await ConfigStore.save(result);
    NotificationService.instance.cancelAll();
  }

  Future<void> _openHistory() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const HistoryScreen()));
    final records = await WorkoutStore.load(force: true);
    if (!mounted) return;
    setState(() => _todayCount = WorkoutStore.today(records).length);
  }

  Future<void> _start() async {
    _recordSaved = false;

    // ── 세션 시작 전 오디오 게이트 ────────────────────────────────────
    //
    // 브라우저는 사용자 제스처 없이는 소리를 재생하지 못한다. '운동 시작'
    // 버튼을 누른 지금이 **가장 확실한 제스처 시점**이므로, 여기서
    // 잠금을 풀고 이번 세션에 쓸 음성 파일을 미리 받아 둔 뒤 타이머를
    // 시작한다. 파일이 준비되기 전에 타이머가 먼저 흐르는 문제를 막는다.
    // 잠금은 제스처마다 다시 확인한다. iOS 는 전화·화면 잠금·앱 전환 뒤
    // 컨텍스트를 중단 상태로 두며, 그 상태는 **새 제스처**에서만 풀린다.
    // 한 번 풀었다고 건너뛰면 그 뒤 세션 전체가 무음이 된다.
    try {
      await AudioCoach.instance.unlock();
      if (!_audioReady) {
        await AudioCoach.instance
            .preloadForSession(style: _config.voiceStyle)
            .timeout(const Duration(seconds: 4), onTimeout: () {});
      }
    } catch (_) {
      // 오디오를 못 준비해도 타이머는 반드시 시작한다.
    }
    if (!mounted) return;
    if (!_audioReady) setState(() => _audioReady = true);

    _engine.start();
    NotificationService.instance.scheduleSession(_engine);
  }

  Future<void> _confirmStop() async {
    final pauseBefore = _engine.isRunning;
    if (pauseBefore) _engine.pause();

    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text(
          '운동을 종료할까요?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          '지금까지 진행한 내용은 운동 기록에 "중도 종료"로 저장됩니다.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              '계속하기',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '종료',
              style: TextStyle(
                color: AppColors.work,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (quit == true) {
      NotificationService.instance.cancelAll();
      await AudioCoach.instance.stopAll();
      // 기록 저장 (중도 종료)
      await _saveRecordIfNeeded();
      _engine.reset();
      if (!mounted) return;
      setState(() {
        _screen = AppScreen.ready;
        _hasSavedSession = false;
      });
    } else if (pauseBefore) {
      _engine.resume();
    }
  }

  void _restart() {
    NotificationService.instance.cancelAll();
    _recordSaved = false;
    _engine.reset();
    _engine.start();
    NotificationService.instance.scheduleSession(_engine);
  }

  void _goHome() {
    NotificationService.instance.cancelAll();
    _engine.reset();
    setState(() {
      _screen = AppScreen.ready;
      _hasSavedSession = false;
    });
  }

  void _resumeSaved() {
    setState(() {
      _screen = AppScreen.running;
      _hasSavedSession = false;
    });
    if (_engine.isPaused) _engine.resume();
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _screen == AppScreen.ready,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_screen == AppScreen.running) _confirmStop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Listener(
          // 웹 브라우저는 **사용자 제스처 안에서만** 오디오 잠금을 풀 수 있다.
          // 앱 어디를 처음 눌러도 그 순간 잠금을 풀고 음성 파일을 미리 받아
          // 두면, 운동 시작 버튼을 누르기도 전에 준비가 끝난다.
          // (공유 링크를 받은 사람의 기기에서 소리가 안 나던 문제의 대응)
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _warmAudioOnce(),
          child: KeyedSubtree(key: ValueKey(_screen), child: _buildScreen()),
        ),
      ),
    );
  }

  /// 첫 터치에서 한 번만 오디오를 준비한다.
  void _warmAudioOnce() {
    // 잠금 해제는 터치마다 시도한다 (이미 풀린 상태면 비용이 거의 없다).
    // 사전 로딩은 한 번만 한다.
    unawaited(AudioCoach.instance.unlock().catchError((_) => false));
    if (_audioReady) return;
    _audioReady = true;
    unawaited(() async {
      try {
        await AudioCoach.instance.preloadForSession(style: _config.voiceStyle);
        if (!mounted) return;
        setState(() {});
      } catch (_) {
        // 실패해도 앱은 정상 동작해야 한다.
      }
    }());
  }

  Widget _buildScreen() {
    switch (_screen) {
      case AppScreen.ready:
        return ReadyScreen(
          config: _config,
          onStart: _start,
          onOpenSettings: _openSettings,
          onOpenHistory: _openHistory,
          hasSavedSession: _hasSavedSession,
          onResumeSession: _resumeSaved,
          todayCount: _todayCount,
        );
      case AppScreen.running:
        return RunningScreen(
          engine: _engine,
          onPauseToggle: () {
            _engine.toggle();
            if (_engine.isRunning) {
              NotificationService.instance.scheduleSession(_engine);
            } else {
              NotificationService.instance.cancelAll();
            }
          },
          onStop: _confirmStop,
          onSkip: () => _engine.skip(),
        );
      case AppScreen.finished:
        return FinishedScreen(
          sets: _engine.completedSets,
          totalSets: _config.sets,
          rounds: _engine.completedRounds,
          totalRounds: _config.totalRounds,
          elapsedMs: _engine.elapsedTotalMs,
          onRestart: _restart,
          onHome: _goHome,
        );
    }
  }
}
