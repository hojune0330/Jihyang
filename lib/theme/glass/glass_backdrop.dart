import 'package:flutter/material.dart';

import 'glass_tokens.dart';

/// 배경 오브 배치 프리셋 (§2). 화면마다 고정해 화면 이동 시 오브가 튀지 않게 한다.
enum BackdropPreset { home, settings, history, finished }

/// 유리 뒤에 비칠 배경 (§2).
///
/// - [GlassBackdrop.ambient]: 밝은 그라데이션 + 상태색 오브 (메인/설정/기록/완료)
/// - [GlassBackdrop.phase]: 상태색 단색 채움 유지 + 위 빛 / 아래 그늘 (진행 화면)
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

  /// null 이 아니면 phase 배경
  final Color? phaseColor;

  @override
  Widget build(BuildContext context) {
    final pc = phaseColor;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (pc != null) ..._phaseLayers(pc) else ..._ambientLayers(),
        child,
      ],
    );
  }

  // ---------------------------------------------------------------- phase

  List<Widget> _phaseLayers(Color c) {
    return [
      // 상태색 단색 — 값은 그대로, 전환만 부드럽게 (§5 phase)
      AnimatedContainer(
        duration: GlassTokens.phase,
        curve: GlassTokens.phaseCurve,
        color: c,
      ),
      // 위쪽 빛: 평면감을 없애는 최소한의 깊이
      IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [
                Colors.white.withValues(alpha: 0.14),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
      // 아래쪽 그늘: 같은 색 계열로 살짝 눌러 조작부를 받친다
      IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: 0.10),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  // -------------------------------------------------------------- ambient

  List<Widget> _ambientLayers() {
    return [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [GlassTokens.ambientTop, GlassTokens.ambientBottom],
          ),
        ),
      ),
      LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth.isFinite ? box.maxWidth : 390.0;
          final h = box.maxHeight.isFinite ? box.maxHeight : 844.0;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (final o in _orbsFor(preset))
                Positioned(
                  left: o.x * w - o.size * w / 2,
                  top: o.y * h - o.size * w / 2,
                  child: _Orb(size: o.size * w, color: o.color, alpha: o.alpha),
                ),
            ],
          );
        },
      ),
    ];
  }

  static List<_OrbSpec> _orbsFor(BackdropPreset p) => switch (p) {
    BackdropPreset.home => const [
      _OrbSpec(0.08, 0.10, 0.95, GlassTokens.orbCoral, 0.50),
      _OrbSpec(0.98, 0.36, 1.00, GlassTokens.orbSky, 0.48),
      _OrbSpec(0.05, 0.66, 0.75, GlassTokens.orbAmber, 0.42),
      _OrbSpec(0.95, 0.90, 0.85, GlassTokens.orbMint, 0.38),
      _OrbSpec(0.45, 1.04, 0.70, GlassTokens.orbLilac, 0.32),
    ],
    BackdropPreset.settings => const [
      _OrbSpec(0.00, 0.04, 0.90, GlassTokens.orbCoral, 0.40),
      _OrbSpec(1.00, 0.30, 0.90, GlassTokens.orbSky, 0.40),
      _OrbSpec(0.10, 0.75, 0.80, GlassTokens.orbAmber, 0.36),
      _OrbSpec(0.95, 0.98, 0.80, GlassTokens.orbLilac, 0.32),
    ],
    BackdropPreset.history => const [
      _OrbSpec(0.95, 0.05, 0.90, GlassTokens.orbCoral, 0.42),
      _OrbSpec(0.00, 0.40, 0.90, GlassTokens.orbSky, 0.36),
      _OrbSpec(0.95, 0.80, 0.85, GlassTokens.orbMint, 0.36),
    ],
    BackdropPreset.finished => const [
      _OrbSpec(0.15, 0.18, 1.15, GlassTokens.orbCoral, 0.58),
      _OrbSpec(0.95, 0.30, 0.95, GlassTokens.orbAmber, 0.55),
      _OrbSpec(0.05, 0.75, 0.85, GlassTokens.orbSky, 0.40),
      _OrbSpec(0.90, 0.95, 0.85, GlassTokens.orbMint, 0.38),
    ],
  };
}

/// 오브 위치: 화면 비율 좌표(x, y), 지름(화면 폭 대비), 색, 중심 알파
class _OrbSpec {
  const _OrbSpec(this.x, this.y, this.size, this.color, this.alpha);
  final double x;
  final double y;
  final double size;
  final Color color;
  final double alpha;
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color, required this.alpha});

  final double size;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: alpha * 0.4),
                color.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
