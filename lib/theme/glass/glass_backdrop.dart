import 'package:flutter/material.dart';

import 'glass_tokens.dart';

/// 화면별 배경 프리셋 — 브랜드 2색(운동 코랄·휴식 블루) 빛의 위치만 다르다.
enum BackdropPreset { home, settings, history, finished }

/// 유리 뒤 배경.
///
/// - [GlassBackdrop.ambient]: iOS grouped 회색 바탕 + 브랜드 2색 빛 2개 (아주 옅게)
///   v1 의 5색 무지개 오브는 장식용 그라데이션이라 제거했다 (v1.1 R1-1).
/// - [GlassBackdrop.phase]: 상태색 단색 채움 유지 (진행 화면)
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop.ambient({
    super.key,
    required this.child,
    this.preset = BackdropPreset.home,
  }) : phaseColor = null;

  const GlassBackdrop.phase({
    super.key,
    required this.child,
    required Color color,
  }) : phaseColor = color,
       preset = BackdropPreset.home;

  final Widget child;
  final BackdropPreset preset;
  final Color? phaseColor;

  @override
  Widget build(BuildContext context) {
    final pc = phaseColor;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (pc != null)
          ColoredBox(color: pc)
        else ...[
          const ColoredBox(color: GlassTokens.ambientTop),
          for (final g in _glowsFor(preset))
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: g.center,
                  radius: g.radius,
                  colors: [
                    g.color.withValues(alpha: g.alpha),
                    g.color.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
        ],
        child,
      ],
    );
  }

  static List<_Glow> _glowsFor(BackdropPreset p) => switch (p) {
    BackdropPreset.home => const [
      _Glow(Alignment(-1.1, -0.9), 1.0, GlassTokens.work, 0.16),
      _Glow(Alignment(1.2, 0.1), 0.9, GlassTokens.rest, 0.12),
    ],
    BackdropPreset.settings => const [
      _Glow(Alignment(-1.2, -1.1), 0.9, GlassTokens.work, 0.10),
      _Glow(Alignment(1.2, 0.6), 0.9, GlassTokens.rest, 0.08),
    ],
    BackdropPreset.history => const [
      _Glow(Alignment(1.2, -1.0), 0.9, GlassTokens.work, 0.12),
      _Glow(Alignment(-1.2, 0.4), 0.9, GlassTokens.rest, 0.08),
    ],
    BackdropPreset.finished => const [
      _Glow(Alignment(0, -0.55), 0.85, GlassTokens.work, 0.20),
      _Glow(Alignment(0.9, 1.1), 0.8, GlassTokens.rest, 0.08),
    ],
  };
}

class _Glow {
  const _Glow(this.center, this.radius, this.color, this.alpha);
  final Alignment center;
  final double radius;
  final Color color;
  final double alpha;
}
