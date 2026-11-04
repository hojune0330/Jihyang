import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/phase.dart';
import '../models/tabata_config.dart';
import '../services/config_store.dart';
import '../services/sound_service.dart';
import '../services/tabata_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/depth_button.dart';
import '../widgets/timer_display.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final TabataEngine _engine;
  TabataConfig _config = const TabataConfig();
  Timer? _pulseTimer;
  bool _pulse = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine = TabataEngine();
    _engine.addListener(_onEngineChanged);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await SoundService.instance.init();
    final cfg = await ConfigStore.load();
    if (!mounted) return;
    setState(() => _config = cfg);
    _engine.updateConfig(cfg);
    _engine.reset();
  }

  void _onEngineChanged() {
    if (!mounted) return;
    final cur = _engine.currentPhase;
    final inCountdown =
        cur != null &&
        cur.needsCountdown &&
        _engine.status == EngineStatus.running &&
        _engine.remainingSeconds <= 5 &&
        _engine.remainingSeconds >= 1;

    if (inCountdown && _pulseTimer == null) {
      _pulseTimer = Timer.periodic(const Duration(milliseconds: 480), (_) {
        if (mounted) setState(() => _pulse = !_pulse);
      });
    } else if (!inCountdown && _pulseTimer != null) {
      _pulseTimer?.cancel();
      _pulseTimer = null;
      _pulse = false;
    }
    setState(() {});
    _syncWakelock();
  }

  bool? _wakelockOn;

  void _syncWakelock() {
    final keepAwake = _engine.status == EngineStatus.running;
    if (_wakelockOn == keepAwake) return;
    _wakelockOn = keepAwake;
    WakelockPlus.toggle(enable: keepAwake).catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드에서는 정확도가 떨어질 수 있어 자동 일시정지
    if (state == AppLifecycleState.paused && _engine.isRunning) {
      _engine.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseTimer?.cancel();
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<TabataConfig>(
      MaterialPageRoute(builder: (_) => SettingsScreen(initial: _config)),
    );
    if (result == null || !mounted) return;
    setState(() => _config = result);
    _engine.updateConfig(result);
    _engine.reset();
    await ConfigStore.save(result);
  }

  @override
  Widget build(BuildContext context) {
    final phase = _engine.currentPhase;
    final accent = phase == null
        ? AppColors.prepare
        : AppColors.forPhase(phase.type.name);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(accent),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildPhaseBadge(phase, accent),
                      const SizedBox(height: 22),
                      _buildRingTimer(phase, accent),
                      const SizedBox(height: 22),
                      _buildStats(accent),
                      const SizedBox(height: 26),
                      _buildNextUp(accent),
                    ],
                  ),
                ),
              ),
            ),
            _buildControls(accent),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 14, 4),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.8),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'TABATA',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _engine.status == EngineStatus.running
                    ? '진행 중'
                    : _engine.status == EngineStatus.paused
                    ? '일시정지'
                    : _engine.status == EngineStatus.finished
                    ? '완료'
                    : '대기',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          DepthButton(
            onTap: _openSettings,
            icon: Icons.tune_rounded,
            accent: AppColors.textPrimary,
            width: 46,
            height: 46,
            radius: 15,
            iconSize: 21,
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseBadge(Phase? phase, Color accent) {
    final title = phase?.title ?? '준비';
    final subtitle = phase?.subtitle ?? '설정을 확인하세요';
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: accent.withValues(alpha: 0.42), width: 1),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.20),
                blurRadius: 22,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                phase?.isWorkout == true
                    ? Icons.local_fire_department_rounded
                    : phase?.isRest == true
                    ? Icons.self_improvement_rounded
                    : Icons.hourglass_bottom_rounded,
                size: 15,
                color: accent,
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  color: accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 12,
                color: accent.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 8),
              Text(
                subtitle,
                style: TextStyle(
                  color: accent.withValues(alpha: 0.82),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRingTimer(Phase? phase, Color accent) {
    final seconds = _engine.remainingSeconds;
    final showRing = _engine.status != EngineStatus.idle && phase != null;

    return SizedBox(
      height: 292,
      width: 292,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 외곽 링 (구간 진행률)
          SizedBox(
            height: 292,
            width: 292,
            child: CustomPaint(
              painter: _RingPainter(
                phaseProgress: showRing ? _engine.phaseProgress : 0,
                totalProgress: showRing ? _engine.totalProgress : 0,
                accent: accent,
                pulse: _pulse,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: 1,
                child: TimerDisplay(
                  totalSeconds: _engine.isIdle && phase == null
                      ? _config.totalSeconds
                      : seconds,
                  dimZeroHours: true,
                  fontSize: _pulse ? 70 : 66,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _engine.isIdle
                    ? '총 ${_fmt(_config.totalSeconds)}'
                    : _engine.status == EngineStatus.finished
                    ? '수고하셨습니다'
                    : '${_engine.completedWorkouts} / ${_engine.totalWorkouts} 운동 완료',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats(Color accent) {
    final phase = _engine.currentPhase;
    final items = <Widget>[
      _buildStatTile(
        label: '세트',
        value: phase == null
            ? '${_config.setCount}'
            : '${phase.setIndex}/${phase.totalSets}',
        unit: '세트',
        color: AppColors.setRest,
        icon: Icons.layers_rounded,
      ),
      _buildStatTile(
        label: '운동',
        value: '${_config.exerciseCount}',
        unit: '개',
        color: AppColors.work,
        icon: Icons.fitness_center_rounded,
      ),
      _buildStatTile(
        label: '휴식',
        value: '${_config.setRestMinutes}',
        unit: '분',
        color: AppColors.minutes,
        icon: Icons.timer_outlined,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: items[i]),
        ],
      ],
    );
  }

  Widget _buildStatTile({
    required String label,
    required String value,
    required String unit,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 15, color: color.withValues(alpha: 0.9)),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: unit,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextUp(Color accent) {
    final phase = _engine.currentPhase;
    if (phase == null || _engine.isIdle) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: AppColors.textSecondary.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 6),
          const Text(
            '오른쪽 위 설정에서 n개 · n세트 · n분 휴식을 조절하세요',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    final next = _engine.index + 1 < _engine.phases.length
        ? _engine.phases[_engine.index + 1]
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.stroke, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '다음',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 10),
          if (next == null)
            Text(
              '마지막 구간',
              style: TextStyle(
                color: accent,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            )
          else ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.forPhase(next.type.name),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              next.title,
              style: TextStyle(
                color: AppColors.forPhase(next.type.name),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _fmt(next.duration),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (!_engine.isIdle) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 12, color: AppColors.stroke),
            const SizedBox(width: 12),
            Text(
              '남은 총 ${_fmt(_engine.remainingTotalSeconds)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControls(Color accent) {
    final running = _engine.isRunning;
    final paused = _engine.status == EngineStatus.paused;
    final finished = _engine.status == EngineStatus.finished;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      child: Column(
        children: [
          Row(
            children: [
              DepthButton(
                onTap: () => _engine.reset(),
                icon: Icons.refresh_rounded,
                accent: AppColors.textPrimary,
                width: 62,
                height: 62,
                iconSize: 23,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DepthButton(
                  onTap: () {
                    SoundService.instance.init();
                    _engine.toggle();
                  },
                  label: running
                      ? '일시정지'
                      : paused
                      ? '계속하기'
                      : finished
                      ? '다시 시작'
                      : '시작',
                  icon: running
                      ? Icons.pause_rounded
                      : finished
                      ? Icons.replay_rounded
                      : Icons.play_arrow_rounded,
                  accent: running ? AppColors.minutes : AppColors.work,
                  filled: true,
                  height: 62,
                  expand: true,
                  iconSize: 26,
                  fontSize: 17,
                ),
              ),
              const SizedBox(width: 12),
              DepthButton(
                onTap: _engine.isIdle ? null : () => _engine.skip(),
                icon: Icons.skip_next_rounded,
                accent: AppColors.rest,
                width: 62,
                height: 62,
                iconSize: 24,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 전체 진행 바
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(
                  height: 4,
                  color: AppColors.stroke.withValues(alpha: 0.55),
                ),
                FractionallySizedBox(
                  widthFactor: _engine.totalProgress.clamp(0.0, 1.0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent.withValues(alpha: 0.55), accent],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.6),
                          blurRadius: 8,
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

  String _fmt(int total) {
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// 구간 진행률 링
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.phaseProgress,
    required this.totalProgress,
    required this.accent,
    required this.pulse,
  });

  final double phaseProgress;
  final double totalProgress;
  final Color accent;
  final bool pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    // 바깥 옅은 링
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AppColors.stroke.withValues(alpha: 0.9);
    canvas.drawCircle(center, radius - 2, bgPaint);

    // 안쪽 얇은 링 (전체 진행률)
    final totalPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: 0.18);
    canvas.drawCircle(center, radius - 16, totalPaint);

    if (totalProgress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 16),
        -math.pi / 2,
        2 * math.pi * totalProgress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = accent.withValues(alpha: 0.45),
      );
    }

    // 현재 구간 진행 아크
    if (phaseProgress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius - 2);
      final glow = pulse ? 0.5 : 0.28;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * phaseProgress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = pulse ? 9 : 6
          ..strokeCap = StrokeCap.round
          ..color = accent.withValues(alpha: glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * phaseProgress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: -math.pi / 2,
            endAngle: 3 * math.pi / 2,
            colors: [accent.withValues(alpha: 0.25), accent],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.phaseProgress != phaseProgress ||
      old.totalProgress != totalProgress ||
      old.accent != accent ||
      old.pulse != pulse;
}
