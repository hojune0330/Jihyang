import 'package:flutter/material.dart';

import '../models/phase.dart';
import '../services/tabata_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/huge_time_display.dart';

/// 화면 2 — 운동 진행 화면
///
/// 구성 (시각적 우선순위 순)
///  ① 상단: 운동 중 / 휴식 중 / 준비 / 세트 휴식
///  ② 중앙: 남은 시간 (화면에서 가장 큰 요소, 잘리지 않음)
///  ③ 라운드 카드 / 세트 카드 (독립 카드, 큰 숫자)
///  ④ 진행률 바 + 퍼센트 + 전체 남은 시간
///  ⑤ 다음 구간 안내 (현재와 구분되도록 톤 다운)
///  ⑥ 일시정지 / 종료 / 건너뛰기
///
/// 화면 전체가 상태 색 단색으로 채워지고, 그라데이션·네온·발광·불필요한
/// 그림자·장식 애니메이션은 쓰지 않는다.
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
    final bg = AppColors.bgOf(type);
    final fg = AppColors.onBgOf(type);
    final paused = engine.isPaused;

    return Scaffold(
      backgroundColor: bg,
      body: Container(
        color: bg,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final timeSize = (box.maxHeight * 0.29).clamp(88.0, 244.0);

              return Column(
                children: [
                  _header(phase, fg, paused),
                  const SizedBox(height: 4),
                  // ② 남은 시간 — 화면에서 가장 큰 요소
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: HugeTimeDisplay(
                        totalSeconds: engine.remainingSeconds,
                        color: fg,
                        fontSize: timeSize,
                        showHours: engine.remainingSeconds >= 3600,
                        horizontalPadding: 22,
                      ),
                    ),
                  ),
                  // ③ 라운드 / 세트 카드
                  _progressCards(fg, bg),
                  const SizedBox(height: 14),
                  // ④ 진행률
                  _progressSection(fg, bg),
                  const SizedBox(height: 10),
                  _controls(bg, fg, paused),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- ① 상태

  Widget _header(Phase? phase, Color fg, bool paused) {
    final label = switch (phase?.type) {
      PhaseType.prepare => '준비',
      PhaseType.work => '운동 중',
      PhaseType.rest => '휴식 중',
      PhaseType.setRest => '세트 휴식',
      null => '준비',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              if (paused) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: fg, width: 2),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '일시정지',
                    style: TextStyle(
                      color: fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- ③ 라운드/세트

  Widget _progressCards(Color fg, Color bg) {
    final perSet = engine.totalRoundsPerSet;
    final sets = engine.totalSets;
    final round = engine.currentRound;
    final set = engine.currentSet;
    final showSet = sets > 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _PhaseCard(
              label: '라운드',
              current: round,
              total: perSet,
              fg: fg,
              bg: bg,
            ),
          ),
          // 세트가 1개면 카드를 아예 만들지 않아 레이아웃이 깨지지 않는다.
          if (showSet) ...[
            const SizedBox(width: 10),
            Expanded(
              child: _PhaseCard(
                label: '세트',
                current: set,
                total: sets,
                fg: fg,
                bg: bg,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ ④ 진행률

  Widget _progressSection(Color fg, Color bg) {
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
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        children: [
          // ⑤ 다음 구간은 테두리 없는 작은 알약으로 현재 상태와 구분
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                fg.withValues(alpha: 0.14),
                Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              nextText,
              style: TextStyle(
                color: fg.withValues(alpha: 0.92),
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  Container(color: AppColors.trackOn(bg)),
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(color: fg),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text(
                '전체 ${(progress * 100).round()}%',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.85),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(
                '남은 ${_mmss(engine.remainingTotalSeconds)}',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.85),
                  fontSize: 12.5,
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

  // ------------------------------------------------------------ ⑥ 조작

  Widget _controls(Color bg, Color fg, bool paused) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
      child: Row(
        children: [
          // 종료 — 실수 방지를 위해 작은 외곽선 버튼으로 분리
          _SideButton(
            icon: Icons.close_rounded,
            color: fg,
            onTap: onStop,
            tooltip: '운동 종료',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 68,
              child: FilledButton(
                onPressed: onPauseToggle,
                style: FilledButton.styleFrom(
                  backgroundColor: fg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 32,
                      color: bg,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      paused ? '재개' : '일시정지',
                      style: TextStyle(
                        fontSize: 20,
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
          const SizedBox(width: 12),
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

/// 라운드/세트 표시 카드.
/// 현재 값은 크게, 전체 값은 작게 — 둘의 차이가 즉시 읽히도록 했다.
class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    required this.label,
    required this.current,
    required this.total,
    required this.fg,
    required this.bg,
  });

  final String label;
  final int current;
  final int total;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 11),
      decoration: BoxDecoration(
        color: AppColors.cardOn(bg),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg.withValues(alpha: 0.75),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$current',
                style: TextStyle(
                  color: fg,
                  fontSize: 36,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                ' / $total',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.72),
                  fontSize: 17,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
        width: 58,
        height: 58,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: color.withValues(alpha: 0.85),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 26,
                color: color.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
