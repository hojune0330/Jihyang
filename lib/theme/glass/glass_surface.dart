import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'glass_tokens.dart';

/// 유리 면 — 앱의 모든 카드/시트/버튼 바탕.
///
/// 쌓는 순서 (아래 → 위)
///  1. 그림자 1겹    2. 배경 블러    3. 면 채움(단색)    4. 상태색 틴트(선택)
///  5. 위쪽 1px 안쪽 하이라이트 + 가장자리 hairline    6. 콘텐츠
///
/// 모양은 [GlassBorder] 하나만 쓴다 (알약/원도 깨지지 않음).
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
    this.deep,
  });

  final Widget child;
  final GlassMaterial material;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final double tintStrength;

  /// 상태색(진행 화면) 배경 위에 놓인 유리
  final bool onColor;
  final bool shadow;
  final bool blur;

  /// null 이 아니면 흰 유리 대신 이 색(밝은 배경의 진한 톤)으로 채운다.
  final Color? deep;

  @override
  Widget build(BuildContext context) {
    final spec = GlassTokens.spec(material);
    final shape = GlassBorder(radius: radius);
    final d = deep;
    final t = tint;

    Color face;
    if (d != null) {
      face = d.withValues(alpha: 0.45 + spec.fillOnColor * 0.5);
    } else {
      face = Colors.white.withValues(
        alpha: onColor ? spec.fillOnColor : spec.fillLight,
      );
      if (t != null) {
        face = Color.alphaBlend(
          t.withValues(alpha: GlassTokens.tintAlpha * tintStrength),
          face,
        );
      }
    }

    Widget body = DecoratedBox(
      decoration: ShapeDecoration(shape: shape, color: face),
      child: Stack(
        children: [
          Padding(padding: padding, child: child),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _EdgePainter(
                  radius: radius,
                  highlight: Colors.white.withValues(
                    alpha: d != null ? 0.22 : spec.rim,
                  ),
                  hairline: (onColor || d != null)
                      ? Colors.white.withValues(alpha: 0.16)
                      : GlassTokens.shadowInk.withValues(alpha: 0.05),
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
    body = GlassClip(radius: radius, child: body);

    if (!shadow) return body;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: GlassTokens.shadow(onColor: onColor),
      ),
      child: body,
    );
  }
}

/// 가장자리: 전체 hairline + 위쪽만 밝은 1px 하이라이트(빛은 위에서).
class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.radius,
    required this.highlight,
    required this.hairline,
  });

  final double radius;
  final Color highlight;
  final Color hairline;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final path = GlassBorder(radius: radius).getOuterPath(rect);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = hairline,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.35],
          colors: [highlight, highlight.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) =>
      old.radius != radius ||
      old.highlight != highlight ||
      old.hairline != hairline;
}
