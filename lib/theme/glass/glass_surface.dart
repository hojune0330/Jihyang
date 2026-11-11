import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'glass_tokens.dart';

/// 유리 면 (§3) — 앱의 모든 카드/시트/버튼 바탕은 이 위젯 하나로 만든다.
///
/// 쌓는 순서 (아래 → 위)
///  1. 그림자 2겹      2. 배경 블러      3. 면 채움(세로 그라데이션)
///  4. 상태색 틴트     5. 위쪽 하이라이트  6. 그라데이션 rim 테두리   7. 콘텐츠
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.material = GlassMaterial.regular,
    this.radius = GlassTokens.rMd,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.tintStrength = 1.0,
    this.onColor = false,
    this.shadow = true,
    this.blur = true,
  });

  final Widget child;
  final GlassMaterial material;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// 상태색 틴트 (선택)
  final Color? tint;

  /// 틴트 세기 배율 (1.0 = 토큰 기본)
  final double tintStrength;

  /// true 면 상태색(진행 화면) 배경 위에 놓인 유리
  final bool onColor;

  final bool shadow;

  /// 배경 블러 사용 여부. 같은 화면에 겹겹이 놓인 작은 요소는 끄면 성능이 좋다.
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final spec = GlassTokens.spec(material);
    final br = BorderRadius.circular(radius);
    final fill = onColor ? spec.fillOnColor : spec.fillLight;
    final t = tint;

    Color face(double a) {
      final base = Colors.white.withValues(alpha: a);
      if (t == null) return base;
      return Color.alphaBlend(
        t.withValues(alpha: GlassTokens.tintAlpha * tintStrength),
        base,
      );
    }

    final hl = onColor
        ? GlassTokens.highlightAlphaOnColor
        : GlassTokens.highlightAlpha;

    Widget body = DecoratedBox(
      decoration: ShapeDecoration(
        shape: GlassTokens.shape(radius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [face(fill + 0.06), face(fill)],
        ),
      ),
      child: Stack(
        children: [
          // 위쪽 하이라이트
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: GlassTokens.shape(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, GlassTokens.highlightStop],
                    colors: [
                      Colors.white.withValues(alpha: hl),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
          // rim 테두리 (위 밝음 → 아래 옅음)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RimPainter(
                  radius: radius,
                  top: Colors.white.withValues(alpha: spec.rimTop),
                  bottom: Colors.white.withValues(alpha: spec.rimBottom),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (blur) {
      body = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: spec.blur, sigmaY: spec.blur),
        child: body,
      );
    }

    body = ClipRSuperellipse(borderRadius: br, child: body);

    if (!shadow) return body;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: GlassTokens.shape(radius),
        shadows: GlassTokens.shadow(onColor: onColor),
      ),
      child: body,
    );
  }
}

/// 위가 밝고 아래로 옅어지는 1px rim — 애플 유리 가장자리 반짝임
class _RimPainter extends CustomPainter {
  _RimPainter({required this.radius, required this.top, required this.bottom});

  final double radius;
  final Color top;
  final Color bottom;

  @override
  void paint(Canvas canvas, Size size) {
    const w = GlassTokens.rimWidth;
    final rect = (Offset.zero & size).deflate(w / 2);
    final r = Radius.circular((radius - w / 2).clamp(0, double.infinity));
    final path = Path()
      ..addRSuperellipse(RSuperellipse.fromRectAndRadius(rect, r));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          top,
          bottom,
          bottom.withValues(alpha: bottom.a * 1.6),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RimPainter old) =>
      old.radius != radius || old.top != top || old.bottom != bottom;
}
