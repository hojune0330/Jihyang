import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/config_store.dart';
import 'services/notification_service.dart';
import 'services/session_store.dart';
import 'services/sound_service.dart';
import 'services/tabata_engine.dart';
import 'models/phase.dart';
import 'models/tabata_config.dart';
import 'theme/app_theme.dart';
import 'widgets/quick_stepper.dart';
import 'widgets/round_dots.dart';
import 'widgets/timer_display.dart';

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
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  await SoundService.instance.init();
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
      home: const TimerScreen(),
    );
  }
}

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> with WidgetsBindingObserver {
  late final TabataEngine _engine;
  TabataConfig _config = const TabataConfig();
  bool _loaded = false;
  DateTime _lastSnapshot = DateTime.fromMillisecondsSinceEpoch(0);

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
        workSeconds: 5,
        restSeconds: 5,
        exerciseCount: 4,
        setCount: 1,
        setRestMinutes: 0,
        prepareSeconds: 0,
        soundEnabled: false,
      );
    }
    final session = await SessionStore.load();
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _loaded = true;
    });
    if (session != null) {
      // 화면이 꺼졌거나 앱이 종료됐던 세션 복원
      _engine.restoreFromSnapshot(session);
      final restored = _engine.config;
      if (mounted) setState(() => _config = restored);
    } else {
      _engine.updateConfig(cfg);
    }
    // 검증용 자동 시작 (빌드 시 --dart-define=AUTOSTART=true)
    if (const bool.fromEnvironment('AUTOSTART') && _engine.isIdle) {
      _engine.start();
    }
  }

  void _onEngine() {
    if (!mounted) return;
    setState(() {});
    _persistSession();
  }

  /// 진행 상태를 주기적으로 저장 (과도한 IO 방지: 최대 1초에 1회)
  void _persistSession() {
    if (_engine.isIdle) {
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
    // 복귀 시 밀린 구간을 즉시 반영 (엔진은 벽시계 기반이라 시간이 틀어지지 않음)
    if (state == AppLifecycleState.resumed) {
      _engine.catchUp();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // 백그라운드로 밀리기 직전 상태 저장 (프로세스 종료 대비)
      if (!_engine.isIdle) SessionStore.save(_engine.snapshot());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.removeListener(_onEngine);
    _engine.dispose();
    super.dispose();
  }

  void _onStart() {
    SoundService.instance.init();
    _engine.toggle();
    if (_engine.isRunning) {
      // 화면이 꺼져도 구간 전환을 알 수 있도록 시스템에 예약
      NotificationService.instance.scheduleSession(_engine);
    } else {
      NotificationService.instance.cancelAll();
    }
  }

  void _change(TabataConfig next) {
    setState(() => _config = next);
    _engine.updateConfig(next);
    NotificationService.instance.cancelAll();
    ConfigStore.save(next);
    SoundService.instance.vibrate();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.work,
            ),
          ),
        ),
      );
    }

    final phase = _engine.currentPhase;
    final type = phase?.type.name ?? 'work';
    final accent = _engine.isIdle ? AppColors.work : AppColors.forPhase(type);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.15),
            radius: 1.0,
            colors: [
              accent.withValues(alpha: _engine.isIdle ? 0.05 : 0.15),
              AppColors.background,
            ],
            stops: const [0.0, 0.75],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              return Column(
                children: [
                  _header(accent),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _phaseLabel(phase, accent),
                            const SizedBox(height: 12),
                            _time(phase, type, box),
                            const SizedBox(height: 14),
                            _roundDots(accent),
                            const SizedBox(height: 10),
                            _roundLine(accent),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _progressZone(accent),
                  _settingsZone(accent),
                  _controls(accent),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 상단

  Widget _header(Color accent) {
    final status = _engine.isRunning
        ? '진행 중'
        : _engine.isPaused
        ? '일시정지'
        : _engine.isFinished
        ? '완료'
        : '준비';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent,
              boxShadow: [
                BoxShadow(color: accent.withValues(alpha: 0.9), blurRadius: 10),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '타바타 타이머',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          Text(
            status,
            style: TextStyle(
              color: _engine.isIdle ? AppColors.textSecondary : accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _phaseLabel(Phase? phase, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _engine.isIdle || phase?.isWorkout == true
                ? Icons.local_fire_department_rounded
                : phase?.isRest == true
                ? Icons.self_improvement_rounded
                : Icons.hourglass_bottom_rounded,
            size: 14,
            color: accent,
          ),
          const SizedBox(width: 6),
          Text(
            _engine.isIdle ? '운동 시간' : (phase?.title ?? '준비'),
            style: TextStyle(
              color: accent,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _time(Phase? phase, String type, BoxConstraints box) {
    // 화면 중앙에 가장 크게 — 세로 공간의 약 26%
    final size = (box.maxHeight * 0.30).clamp(84.0, 190.0);
    final seconds = _engine.isIdle
        ? (phase?.duration ?? _config.workSeconds)
        : _engine.remainingSeconds;

    // 구간이 바뀌면 색이 즉시 전환되어야 혼동이 없다 (크로스페이드 금지)
    return BigTimeDisplay(
      totalSeconds: seconds,
      phaseType: type,
      fontSize: size,
    );
  }

  Widget _roundDots(Color accent) {
    if (_engine.isIdle) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: RoundDots(
        total: _engine.totalRounds,
        current: _engine.currentRound,
        accent: accent,
      ),
    );
  }

  Widget _roundLine(Color accent) {
    if (_engine.isIdle) {
      final total = _config.totalSeconds;
      final label =
          '${_config.exerciseCount}개 · ${_config.setCount}세트 · ${_config.setRestMinutes}분 휴식   |   총 ${_mmss(total)}';
      return Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      );
    }

    final round = '라운드 ${_engine.currentRound} / ${_engine.totalRounds}';
    final set = _engine.totalSets > 1
        ? '   ·   세트 ${_engine.currentSet} / ${_engine.totalSets}'
        : '';
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: round,
            style: TextStyle(
              color: accent,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          TextSpan(
            text: set,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 진행률

  Widget _progressZone(Color accent) {
    final progress = _engine.isIdle ? 0.0 : _engine.totalProgress;
    final remainTotal = _engine.isIdle
        ? _config.totalSeconds
        : _engine.remainingTotalSeconds;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                _engine.isFinished ? '완료' : '전체 진행률',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  color: accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _mmss(remainTotal),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                Container(
                  height: 5,
                  color: AppColors.stroke.withValues(alpha: 0.6),
                ),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent.withValues(alpha: 0.7), accent],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.8),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 설정 (인라인)

  Widget _settingsZone(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: QuickStepper(
                  label: '운동',
                  value: _config.workSeconds,
                  unit: '초',
                  min: 5,
                  max: 120,
                  step: 5,
                  accent: AppColors.work,
                  onChanged: (v) => _change(_config.copyWith(workSeconds: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: QuickStepper(
                  label: '휴식',
                  value: _config.restSeconds,
                  unit: '초',
                  min: 0,
                  max: 60,
                  step: 5,
                  accent: AppColors.rest,
                  onChanged: (v) => _change(_config.copyWith(restSeconds: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: QuickStepper(
                  label: '운동 개수',
                  value: _config.exerciseCount,
                  unit: '개',
                  min: 1,
                  max: 30,
                  accent: AppColors.prepare,
                  onChanged: (v) => _change(_config.copyWith(exerciseCount: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: QuickStepper(
                  label: '세트 수',
                  value: _config.setCount,
                  unit: '세트',
                  min: 1,
                  max: 20,
                  accent: AppColors.hourColor,
                  onChanged: (v) => _change(_config.copyWith(setCount: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: QuickStepper(
                  label: '세트 간 휴식',
                  value: _config.setRestMinutes,
                  unit: '분',
                  min: 0,
                  max: 10,
                  accent: AppColors.setRestMinutesColor,
                  onChanged: (v) =>
                      _change(_config.copyWith(setRestMinutes: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SoundCell(
                  enabled: _config.soundEnabled,
                  onTap: () => _change(
                    _config.copyWith(soundEnabled: !_config.soundEnabled),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 컨트롤

  Widget _controls(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Row(
        children: [
          _CircleButton(
            icon: Icons.refresh_rounded,
            accent: AppColors.textPrimary,
            size: 58,
            onTap: () {
              NotificationService.instance.cancelAll();
              _engine.reset();
            },
          ),
          _CircleButton(
            icon: Icons.skip_next_rounded,
            accent: AppColors.textSecondary,
            size: 52,
            onTap: _engine.isIdle ? null : () => _engine.skip(),
          ),
          const SizedBox(width: 0),
          const Spacer(),
          _MainButton(
            running: _engine.isRunning,
            finished: _engine.isFinished,
            paused: _engine.isPaused,
            accent: accent,
            onTap: _onStart,
          ),
          const Spacer(),
          _CircleButton(
            icon: Icons.vibration_rounded,
            accent: _config.vibrationEnabled
                ? AppColors.rest
                : AppColors.textSecondary,
            size: 52,
            onTap: () {
              _change(
                _config.copyWith(vibrationEnabled: !_config.vibrationEnabled),
              );
            },
          ),
        ],
      ),
    );
  }

  String _mmss(int total) {
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.accent,
    required this.size,
    this.onTap,
  });

  final IconData icon;
  final Color accent;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return Opacity(
      opacity: active ? 1 : 0.3,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface,
              border: Border.all(
                color: accent.withValues(alpha: 0.22),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: size * 0.42, color: accent),
          ),
        ),
      ),
    );
  }
}

/// 화면에서 가장 눈에 띄는 주 버튼
class _MainButton extends StatelessWidget {
  const _MainButton({
    required this.running,
    required this.paused,
    required this.finished,
    required this.accent,
    required this.onTap,
  });

  final bool running;
  final bool paused;
  final bool finished;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = running ? AppColors.prepare : accent;
    final icon = running
        ? Icons.pause_rounded
        : finished
        ? Icons.replay_rounded
        : Icons.play_arrow_rounded;
    final label = running
        ? '일시정지'
        : paused
        ? '계속'
        : finished
        ? '다시'
        : '시작';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(color, Colors.white, 0.18)!,
                    color,
                    Color.lerp(color, Colors.black, 0.30)!,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 28,
                    spreadRadius: -2,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.7),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, size: 44, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

/// 소리 켜기/끄기 셀 (설정 그리드 6번째 칸)
class _SoundCell extends StatelessWidget {
  const _SoundCell({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = enabled ? AppColors.work : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.22), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              size: 17,
              color: accent.withValues(alpha: enabled ? 1 : 0.5),
            ),
            const SizedBox(height: 1),
            Text(
              enabled ? '소리 켬' : '소리 끔',
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
