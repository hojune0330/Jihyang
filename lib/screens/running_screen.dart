import 'package:flutter/material.dart';

import '../models/phase.dart';
import '../services/tabata_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/huge_time_display.dart';

/// 화면 2 — 운동 진행 화면 (가장 중요한 화면)
///
/// 운동/휴식/준비 상태에 따라 **화면 전체 배경색**이 바뀐다.
/// 남은 시간을 화면에서 가장 크게 보여주고, 나머지 정보는 하단에 작게 모은다.
/// 그라데이션·네온·발광·그림자·애니메이션은 사용하지 않는다.
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

    // 화면 전체를 채우는 단색 배경
    final bg = AppColors.bgOf(type);
    // 배경 위에 올릴 글자색 (노랑 위에서는 검정)
    final fg = AppColors.onBgOf(type);

    final paused = engine.isPaused;

    return Scaffold(
      backgroundColor: bg,
      body: Container(
        color: bg,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              // 남은 시간이 화면의 절반 이상을 차지하도록 크게 잡는다.
              // HugeTimeDisplay 내부에서 실제 폭/높이를 측정해 잘리지 않게 축소한다.
              final timeSize = (box.maxHeight * 0.42).clamp(120.0, 340.0);

              return Column(
                children: [
                  _header(phase, fg, paused),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HugeTimeDisplay(
                            totalSeconds: engine.remainingSeconds,
                            color: fg,
                            fontSize: timeSize,
                            showHours: engine.remainingSeconds >= 3600,
                            horizontalPadding: 12,
                          ),
                          const SizedBox(height: 10),
                          _roundLine(fg),
                        ],
                      ),
                    ),
                  ),
                  _bottomInfo(fg),
                  _controls(bg, fg, paused),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 상단

  Widget _header(Phase? phase, Color fg, bool paused) {
    final label = switch (phase?.type) {
      PhaseType.prepare => '준비',
      PhaseType.work => '운동 중',
      PhaseType.rest => '휴식 중',
      PhaseType.setRest => '세트 휴식',
      null => '준비',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          if (paused) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: fg, width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '일시정지',
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 라운드

  Widget _roundLine(Color fg) {
    final perSet = engine.totalRoundsPerSet;
    final sets = engine.totalSets;
    final roundNum = engine.currentRound;
    final setNum = engine.currentSet;

    final text = sets > 1
        ? '라운드 $roundNum / $perSet   ·   세트 $setNum / $sets'
        : '라운드 $roundNum / $perSet';

    return Text(
      text,
      style: TextStyle(
        color: fg,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  // ---------------------------------------------------------------- 하단 정보

  Widget _bottomInfo(Color fg) {
    final progress = engine.totalProgress;
    final next = engine.nextPhase;

    final String nextText;
    if (next == null) {
      nextText = '다음 · 마지막 구간';
    } else {
      final t = next.duration;
      final mm = t ~/ 60;
      final ss = t % 60;
      final time = mm > 0
          ? '$mm:${ss.toString().padLeft(2, '0')}'
          : '${ss.toString().padLeft(2, '0')}초';
      nextText = '다음 · ${next.title} $time';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
      child: Column(
        children: [
          Text(
            nextText,
            style: TextStyle(
              color: fg.withValues(alpha: 0.82),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          // 전체 진행률
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: fg.withValues(alpha: 0.28)),
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(color: fg),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '전체 ${(progress * 100).round()}%',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.82),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(
                '남은 ${_mmss(engine.remainingTotalSeconds)}',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.82),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 조작

  Widget _controls(Color bg, Color fg, bool paused) {
    // 배경과 반대되는 단색으로 버튼을 채워 명확하게 구분한다.
    final buttonFill = fg;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 22),
      child: Row(
        children: [
          // 종료 — 실수 방지를 위해 작은 외곽선 버튼으로 분리
          _SideButton(
            icon: Icons.close_rounded,
            color: fg,
            onTap: onStop,
            tooltip: '운동 종료',
          ),
          const SizedBox(width: 14),
          // 일시정지 / 재개 — 가장 큰 버튼
          Expanded(
            child: SizedBox(
              height: 76,
              child: FilledButton(
                onPressed: onPauseToggle,
                style: FilledButton.styleFrom(
                  backgroundColor: buttonFill,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 36,
                      // 배경색과 동일한 색으로 채워 확실히 반전시킨다
                      color: bg,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      paused ? '재개' : '일시정지',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: bg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // 건너뛰기
          _SideButton(
            icon: Icons.keyboard_double_arrow_right_rounded,
            color: fg,
            onTap: onSkip,
            tooltip: '다음 구간으로',
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

/// 보조 버튼 — 어떤 배경색 위에서도 깔끔하게 보이도록 외곽선만 사용한다.
class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 64,
        height: 64,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 28, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
