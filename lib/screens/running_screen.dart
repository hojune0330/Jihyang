import 'package:flutter/material.dart';

import '../models/phase.dart';
import '../services/tabata_engine.dart';
import '../theme/app_theme.dart';
import '../theme/glass/glass.dart';
import '../widgets/huge_time_display.dart';
import '../widgets/progress_ring.dart';

/// 화면 2 — 운동 진행 화면
///
/// 구성 (시각적 우선순위 순)
///  ① 상단: 운동 중 / 휴식 중 / 준비 / 세트 휴식
///  ② 중앙: **원형 진행 링** + 남은 시간 (화면에서 가장 큰 요소)
///  ③ 라운드 카드 / 세트 카드 (독립 카드, 큰 숫자)
///  ④ 보조 선형 진행 바 + 퍼센트 + 전체 남은 시간
///  ⑤ 다음 구간 안내
///  ⑥ 일시정지 / 종료 / 건너뛰기
///
/// 시간의 흐름 표현
///  - 원형 링: 남은 시간 비율만큼 시계 방향으로 **줄어든다** (메인)
///  - 선형 바: 전체 세션 진행률을 채운다 (보조)
///  두 요소 모두 `engine` 의 벽시계 계산값만 읽는다 → 타이머와 항상 일치.
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

    // 배경(360ms)과 위 요소의 색이 같은 시간에 바뀌도록 묶는다.
    // 배경만 애니메이션하면 전환 순간 이전 색 배경 위에 다음 색 요소가
    // 먼저 그려져 '파란 화면에 코랄 진행선' 같은 프레임이 생긴다.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: bg),
      duration: GlassTokens.phase,
      curve: GlassTokens.phaseCurve,
      builder: (context, animBg, _) =>
          _scaffold(animBg ?? bg, fg, phase, paused),
    );
  }

  Widget _scaffold(Color bg, Color fg, Phase? phase, bool paused) {
    return Scaffold(
      backgroundColor: bg,
      body: GlassBackdrop.phase(
        color: bg,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              // 화면이 낮으면(가로/작은 기기) 하단 요소를 압축한다.
              final compact = box.maxHeight < 620;

              return Column(
                children: [
                  _header(phase, fg, paused, compact),
                  // ② 링 + 남은 시간 — 화면에서 가장 큰 요소.
                  //    Expanded 로 남는 공간을 모두 주고, 그 안에서 링이
                  //    정사각형으로 최대한 커진다.
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 12 : 18,
                          vertical: compact ? 4 : 8,
                        ),
                        child: _ringArea(fg, bg),
                      ),
                    ),
                  ),
                  if (!compact) const SizedBox(height: 6),
                  // ③ 라운드 / 세트 카드
                  _progressCards(fg, bg, compact),
                  SizedBox(height: compact ? 8 : 12),
                  // ④ 보조 진행 정보
                  _progressSection(fg, bg, compact),
                  SizedBox(height: compact ? 6 : 10),
                  _controls(bg, fg, paused, compact),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 밝은 배경(준비 옐로)이면 같은 색상의 진한 톤 유리, 아니면 흰 유리
  static Color? _deep(Color bg) =>
      GlassTokens.needsDarkGlass(bg) ? GlassTokens.deepOf(bg) : null;

  // ------------------------------------------------- 링 + 남은 시간

  Widget _ringArea(Color fg, Color bg) {
    final cur = engine.currentPhase;
    final durationMs = (cur?.duration ?? 0) * 1000;
    // 남은 시간 비율 (1 = 가득, 0 = 끝) — 엔진의 실측 ms 기준
    final remainRatio = durationMs <= 0
        ? 0.0
        : (engine.remainingMs / durationMs).clamp(0.0, 1.0);

    return ProgressRing(
      progress: remainRatio,
      color: fg,
      trackColor: AppColors.trackOn(bg),
      strokeWidth: 10,
      // 링과 숫자 사이를 넉넉히 — 숫자가 링에 닿아 답답해 보이지 않게.
      gap: 26,
      child: AspectRatio(
        aspectRatio: 2.15,
        child: HugeTimeDisplay(
          totalSeconds: engine.remainingSeconds,
          color: fg,
          fontSize: 260,
          showHours: engine.remainingSeconds >= 3600,
          horizontalPadding: 4,
          shadows: AppColors.shadowOn(engine.phaseType),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- ① 상태

  Widget _header(Phase? phase, Color fg, bool paused, bool compact) {
    final label = switch (phase?.type) {
      PhaseType.prepare => '준비',
      PhaseType.work => '운동 중',
      PhaseType.rest => '휴식 중',
      PhaseType.setRest => '세트 휴식',
      null => '준비',
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(20, compact ? 8 : 14, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: GlassTokens.phase,
            child: Text(
              label,
              key: ValueKey(label),
              style: TextStyle(
                color: fg,
                fontSize: compact ? 20 : 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                // 소프트 옐로 배경 위 흰 글자가 살짝 떠 보이지 않도록
                // 얇은 그림자로 경계를 잡아 준다 (장식 아님, 가독성 목적).
                shadows: AppColors.shadowOn(engine.phaseType),
              ),
            ),
          ),
          if (paused) ...[
            const SizedBox(width: 10),
            GlassChip(
              label: '일시정지',
              icon: Icons.pause_rounded,
              color: fg,
              onColor: true,
              deep: _deep(AppColors.bgOf(phase?.type.name ?? 'prepare')),
              fontSize: 12,
              dense: true,
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------- ③ 라운드/세트

  Widget _progressCards(Color fg, Color bg, bool compact) {
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
              compact: compact,
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
                compact: compact,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ ④ 진행률

  Widget _progressSection(Color fg, Color bg, bool compact) {
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
          GlassChip(
            label: nextText,
            color: fg,
            onColor: true,
            fontSize: 13.5,
            deep: _deep(bg),
          ),
          SizedBox(height: compact ? 8 : 12),
          // 보조 선형 진행 바 — 전체 세션 진행률
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: AppColors.trackOn(bg)),
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: fg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
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
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(
                '남은 ${_mmss(engine.remainingTotalSeconds)}',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
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

  Widget _controls(Color bg, Color fg, bool paused, bool compact) {
    final h = compact ? 58.0 : 68.0;
    final side = compact ? 50.0 : 58.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(22, 4, 22, compact ? 10 : 18),
      child: Row(
        children: [
          // 종료 — 실수 방지를 위해 작은 외곽선 버튼으로 분리
          _SideButton(
            icon: Icons.close_rounded,
            color: fg,
            onTap: onStop,
            tooltip: '운동 종료',
            size: side,
            dark: GlassTokens.needsDarkGlass(bg),
            bg: bg,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlassButton.filled(
              label: paused ? '재개' : '일시정지',
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: fg,
              // 흰 버튼 위 글자는 상태색의 '진한 글자색' (옐로 위 대비 문제 해결)
              foreground: GlassTokens.textOf(engine.phaseType),
              height: h,
              fontSize: compact ? 18 : 19,
              radius: GlassTokens.rPill,
              onPressed: onPauseToggle,
            ),
          ),
          const SizedBox(width: 12),
          _SideButton(
            icon: Icons.keyboard_double_arrow_right_rounded,
            color: fg,
            onTap: onSkip,
            tooltip: '다음 구간으로',
            size: side,
            dark: GlassTokens.needsDarkGlass(bg),
            bg: bg,
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
    this.compact = false,
  });

  final String label;
  final int current;
  final int total;
  final Color fg;
  final Color bg;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      material: GlassMaterial.thin,
      onColor: true,
      deep: RunningScreen._deep(bg),
      radius: GlassTokens.rMd,
      padding: EdgeInsets.fromLTRB(16, compact ? 8 : 10, 16, compact ? 10 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg.withValues(alpha: 0.8),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$current',
                    maxLines: 1,
                    style: TextStyle(
                      color: fg,
                      fontSize: compact ? 30 : 34,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              Text(
                ' / $total',
                maxLines: 1,
                style: TextStyle(
                  color: fg.withValues(alpha: 0.72),
                  fontSize: compact ? 15 : 16,
                  height: 1.05,
                  fontWeight: FontWeight.w600,
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

/// 보조 버튼 — 상태색 위 원형 유리 버튼 (종료 / 다음 구간).
class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
    this.size = 58,
    this.dark = false,
    required this.bg,
  });

  final bool dark;
  final Color bg;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onTap,
      size: size,
      iconColor: color,
      onColor: true,
      deep: dark ? GlassTokens.deepOf(bg) : null,
      material: GlassMaterial.regular,
    );
  }
}
