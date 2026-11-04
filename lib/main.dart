import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'models/tabata_config.dart';
import 'screens/finished_screen.dart';
import 'screens/ready_screen.dart';
import 'screens/running_screen.dart';
import 'screens/settings_screen.dart';
import 'services/audio_coach.dart';
import 'services/config_store.dart';
import 'services/notification_service.dart';
import 'services/session_store.dart';
import 'services/tabata_engine.dart';
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
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  await AudioCoach.instance.init();
  await NotificationService.instance.init();
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

/// 스크린샷 검증용 래퍼 (--dart-define=SHOT=settings 일 때 설정 화면을 바로 렌더)
class _ShotWrapper extends StatelessWidget {
  const _ShotWrapper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 디버그 빌드에서만 동작하는 화면 검증용 바로가기
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

  DateTime _lastSnapshot = DateTime.fromMillisecondsSinceEpoch(0);
  bool _wakelockOn = false;

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
        voiceEnabled: true,
        sfxEnabled: false,
      );
    }
    final session = await SessionStore.load();
    if (!mounted) return;

    setState(() {
      _config = cfg;
      _loaded = true;
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
  }

  void _syncSideEffects(EngineStatus status) {
    // 운동 중에는 화면이 꺼지지 않도록 유지
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

  // ------------------------------------------------------------ 액션

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<TabataConfig>(
      MaterialPageRoute(builder: (_) => SettingsScreen(initial: _config)),
    );
    if (result == null || !mounted) return;
    setState(() => _config = result);
    _engine.updateConfig(result);
    await ConfigStore.save(result);
    NotificationService.instance.cancelAll();
    AudioCoach.instance.voiceEnabled = result.voiceEnabled;
    AudioCoach.instance.sfxEnabled = result.sfxEnabled;
  }

  void _start() {
    AudioCoach.instance.voiceEnabled = _config.voiceEnabled;
    AudioCoach.instance.sfxEnabled = _config.sfxEnabled;
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
          '지금 종료하면 진행 상황이 사라집니다.',
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
      _engine.reset();
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
        // 불필요한 애니메이션 없이 즉시 전환 (구간 색상이 곧바로 바뀌어야 함)
        body: KeyedSubtree(key: ValueKey(_screen), child: _buildScreen()),
      ),
    );
  }

  Widget _buildScreen() {
    switch (_screen) {
      case AppScreen.ready:
        return ReadyScreen(
          config: _config,
          onStart: _start,
          onOpenSettings: _openSettings,
          hasSavedSession: _hasSavedSession,
          onResumeSession: _resumeSaved,
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
          sets: _engine.isFinished ? _config.sets : _engine.completedSets,
          totalSets: _config.sets,
          rounds: _config.totalRounds,
          totalRounds: _config.totalRounds,
          elapsedMs: _engine.elapsedTotalMs,
          onRestart: _restart,
          onHome: _goHome,
        );
    }
  }
}
