import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'glass_tokens.dart';

/// 눌림 반응: 누르면 0.97배로 줄고, 놓으면 탄력 있게 돌아온다 (ripple 대신).
class GlassPressable extends StatefulWidget {
  const GlassPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = GlassTokens.pressScale,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final String? semanticLabel;

  @override
  State<GlassPressable> createState() => _GlassPressableState();
}

class _GlassPressableState extends State<GlassPressable> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _set(bool v) {
    if (!_enabled || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1.0,
          duration: _down ? GlassTokens.pressIn : GlassTokens.pressOut,
          curve: _down ? Curves.easeOut : GlassTokens.pressOutCurve,
          child: AnimatedOpacity(
            opacity: _enabled ? 1.0 : 0.4,
            duration: GlassTokens.state,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 주 버튼.
///
/// - [GlassButton.filled]: 단색 면 + 위쪽 1px 하이라이트 + 중립 그림자.
///   v1 의 세로 그라데이션·같은 색 발광 그림자(글로시 버튼)는 제거 (R1-3).
/// - [GlassButton.glass]: 무채 유리 (보조 동작)
class GlassButton extends StatelessWidget {
  const GlassButton.filled({
    super.key,
    required this.label,
    required this.onPressed,
    required Color this.color,
    this.icon,
    this.height = 56,
    this.foreground = Colors.white,
    this.fontSize = 17,
    this.radius = GlassTokens.rMd,
  }) : filled = true,
       onColor = false;

  const GlassButton.glass({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 56,
    this.foreground = GlassTokens.ink,
    this.fontSize = 17,
    this.radius = GlassTokens.rMd,
    this.onColor = false,
  }) : color = null,
       filled = false;

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final IconData? icon;
  final double height;
  final Color foreground;
  final double fontSize;
  final double radius;
  final bool filled;
  final bool onColor;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: fontSize + 6, color: foreground),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );

    final c = color;
    final Widget face;
    if (filled && c != null) {
      final shape = GlassBorder(radius: radius);
      face = DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          color: c,
          shadows: [
            BoxShadow(
              color: GlassTokens.shadowInk.withValues(alpha: 0.12),
              blurRadius: 16,
              spreadRadius: -6,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: CustomPaint(painter: _TopHighlight(radius: radius)),
            ),
            Center(child: content),
          ],
        ),
      );
    } else {
      face = GlassSurface(
        material: onColor ? GlassMaterial.thin : GlassMaterial.regular,
        onColor: onColor,
        radius: radius,
        child: Center(child: content),
      );
    }

    return GlassPressable(
      onTap: onPressed,
      semanticLabel: label,
      child: SizedBox(height: height, width: double.infinity, child: face),
    );
  }
}

/// 단색 버튼 위쪽 1px 안쪽 하이라이트
class _TopHighlight extends CustomPainter {
  _TopHighlight({required this.radius});
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = GlassBorder(
      radius: radius,
    ).getOuterPath((Offset.zero & size).deflate(0.5));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.4],
          colors: [
            Colors.white.withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _TopHighlight old) => old.radius != radius;
}

/// 원형 유리 아이콘 버튼
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 44,
    this.iconColor = GlassTokens.ink,
    this.onColor = false,
    this.material = GlassMaterial.regular,
    this.shadow = true,
    this.deep,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final Color iconColor;
  final bool onColor;
  final GlassMaterial material;
  final bool shadow;
  final Color? deep;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GlassPressable(
        onTap: onPressed,
        semanticLabel: tooltip,
        scale: 0.92,
        child: SizedBox(
          width: size,
          height: size,
          child: GlassSurface(
            material: material,
            onColor: onColor,
            shadow: shadow,
            blur: shadow,
            deep: deep,
            radius: GlassTokens.rPill,
            child: Center(
              child: Icon(icon, size: size * 0.44, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// 알약 칩
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.color = GlassTokens.ink,
    this.onColor = false,
    this.fontSize = 13,
    this.dense = false,
    this.deep,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color color;
  final bool onColor;
  final double fontSize;
  final bool dense;
  final Color? deep;

  @override
  Widget build(BuildContext context) {
    final chip = GlassSurface(
      material: GlassMaterial.thin,
      onColor: onColor,
      deep: deep,
      radius: GlassTokens.rPill,
      shadow: false,
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 11 : 14,
        vertical: dense ? 6 : 8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                fontFeatures: GlassTokens.tabular,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GlassPressable(onTap: onTap, semanticLabel: label, child: chip);
  }
}

/// iOS 설정식 묶음 카드 — 행 사이 hairline.
class GlassGroup extends StatelessWidget {
  const GlassGroup({
    super.key,
    required this.children,
    this.inset = 16,
    this.radius = GlassTokens.rMd,
  });

  final List<Widget> children;
  final double inset;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: inset),
            child: Container(
              height: GlassTokens.hairline,
              color: GlassTokens.separator,
            ),
          ),
        );
      }
    }
    return GlassSurface(
      radius: radius,
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// 한 카드 안에 가로로 칸을 나눈다 (세로 hairline).
class GlassSegments extends StatelessWidget {
  const GlassSegments({
    super.key,
    required this.children,
    this.radius = GlassTokens.rMd,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  });

  final List<Widget> children;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      cells.add(
        Expanded(
          child: Padding(padding: padding, child: children[i]),
        ),
      );
      if (i != children.length - 1) {
        cells.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Container(
              width: GlassTokens.hairline,
              color: GlassTokens.separator,
            ),
          ),
        );
      }
    }
    return GlassSurface(
      radius: radius,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cells,
        ),
      ),
    );
  }
}

/// 섹션 라벨 — iOS 묶음 위 작은 제목
class GlassSectionLabel extends StatelessWidget {
  const GlassSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 2, bottom: 7),
      child: Text(text, style: GlassTokens.overline),
    );
  }
}
