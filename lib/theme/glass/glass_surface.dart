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
    // 알약/원(rPill)은 superellipse 대신 stadium 으로 그린다. 곡률이 변 길이의
    // 절반을 넘는 superellipse 는 가장자리에 가시 잔상이 생긴다 (D3 실기 캡처).
    final pill = radius >= 100;
    ShapeBorder shapeOf() =>
        pill ? const StadiumBorder() : GlassTokens.shape(radius);
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
        shape: shapeOf(),
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
                  shape: shapeOf(),
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
                  pill: pill,
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

    body = pill
        ? ClipRRect(borderRadius: br, child: body)
        : ClipRSuperellipse(borderRadius: br, child: body);

    if (!shadow) return body;
    // 그림자는 둥근 사각형으로 그린다 (흐린 그림자라 모양 차이는 안 보인다).
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: GlassTokens.shadow(onColor: onColor),
      ),
      child: body,
    );
  }
}

/// 위가 밝고 아래로 옅어지는 1px rim — 애플 유리 가장자리 반짝임
class _RimPainter extends CustomPainter {
  _RimPainter({
    required this.radius,
    required this.pill,
    required this.top,
    required this.bottom,
  });

  final double radius;
  final bool pill;
  final Color top;
  final Color bottom;

  @override
  void paint(Canvas canvas, Size size) {
    const w = GlassTokens.rimWidth;
    final rect = (Offset.zero & size).deflate(w / 2);
    final path = Path();
    if (pill) {
      path.addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
      );
    } else {
      final r = Radius.circular((radius - w / 2).clamp(0, double.infinity));
      path.addRSuperellipse(RSuperellipse.fromRectAndRadius(rect, r));
    }
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
      old.radius != radius ||
      old.pill != pill ||
      old.top != top ||
      old.bottom != bottom;
}
