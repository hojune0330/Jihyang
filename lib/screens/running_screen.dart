import 'package:flutter/material.dart';

import '../models/phase.dart';
import '../services/tabata_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/huge_time_display.dart';

/// 화면 2 — 운동 진행 화면 (가장 중요한 화면)
///
/// 시간 외 정보는 최소화하고, 모든 요소는 단색·고대비로만 구성한다.
class RunningScreen extends StatelessWidget {
  const RunningScreen({
    super.key,
    required this.engine,
    required this.onPauseToggle,
    required this.onStop,
    required this.onSkip,
  });

  final TabataEngine engine;
  final VoidCallback onPauseToggle;
  final VoidCallback onStop;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final phase = engine.currentPhase;
    final type = phase?.type.name ?? 'prepare';
    final accent = AppColors.of(type);
    final isWork = phase?.type == PhaseType.work;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            // 남은 시간이 화면에서 가장 큰 비중을 차지하도록 계산
            final timeSize = (box.maxHeight * 0.30).clamp(96.0, 220.0);

            return Column(
              children: [
                _statusBar(phase, accent, isWork),
                const SizedBox(height: 4),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HugeTimeDisplay(
                        totalSeconds: engine.remainingSeconds,
                        color: accent,
                        fontSize: timeSize,
                        showHours: engine.remainingSeconds >= 3600,
                      ),
                      const SizedBox(height: 18),
                      _roundLine(phase, accent),
                    ],
                  ),
                ),
                _nextUp(accent),
                _progress(accent),
                _controls(accent),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statusBar(Phase? phase, Color accent, bool isWork) {
    final paused = engine.isPaused;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Text(
            phase?.bigTitle ?? '준비',
            style: TextStyle(
              color: accent,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          if (paused)
            const Text(
              '일시정지',
              style: TextStyle(
                color: AppColors.prepare,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
        ],
      ),
    );
  }

  Widget _roundLine(Phase? phase, Color accent) {
    final perSet = engine.totalRoundsPerSet;
    final sets = engine.totalSets;
    final roundNum = engine.currentRound;
    final setNum = engine.currentSet;

    final label = sets > 1
        ? '라운드 $roundNum / $perSet   ·   세트 $setNum / $sets'
        : '라운드 $roundNum / $perSet';

    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _nextUp(Color accent) {
    final next = engine.nextPhase;
    final String text;
    if (next == null) {
      text = '마지막 구간';
    } else {
      final secs = next.duration;
      final mm = secs ~/ 60;
      final ss = secs % 60;
      final time = mm > 0
          ? '$mm:${ss.toString().padLeft(2, '0')}'
          : '${ss.toString().padLeft(2, '0')}초';
      text = '다음 · ${next.title} $time';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  Widget _progress(Color accent) {
    final progress = engine.totalProgress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Container(color: AppColors.surfaceHigh),
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(color: accent),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '남은 ${_mmss(engine.remainingTotalSeconds)}',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controls(Color accent) {
    final paused = engine.isPaused;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      child: Row(
        children: [
          _BigButton(
            icon: Icons.stop_rounded,
            label: '종료',
            color: AppColors.surfaceHigh,
            textColor: AppColors.textSecondary,
            size: 66,
            onTap: onStop,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 76,
              child: FilledButton(
                onPressed: onPauseToggle,
                style: FilledButton.styleFrom(
                  backgroundColor: paused
                      ? AppColors.work
                      : AppColors.surfaceHigh,
                  foregroundColor: paused
                      ? Colors.black
                      : AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 34,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      paused ? '재개' : '일시정지',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _BigButton(
            icon: Icons.keyboard_double_arrow_right_rounded,
            label: '건너뛰기',
            color: AppColors.surfaceHigh,
            textColor: AppColors.textSecondary,
            size: 66,
            onTap: onSkip,
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

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Material(
            color: color,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Icon(icon, size: 30, color: textColor),
            ),
          ),
        ),
      ],
    );
  }
}
