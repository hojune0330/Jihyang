import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'glass_tokens.dart';

/// 눌림 반응 (§5): 누르면 0.97배로 줄고, 놓으면 탄력 있게 돌아온다.
/// 물결(ripple) 대신 쓴다.
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
            opacity: _enabled ? 1.0 : 0.45,
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
/// - [GlassButton.filled]: 상태색이 진하게 물든 유리 (시작·다시 시작·저장)
/// - [GlassButton.glass]: 무채 유리 (보조 동작)
class GlassButton extends StatelessWidget {
  const GlassButton.filled({
    super.key,
    required this.label,
    required this.onPressed,
    required Color this.color,
    this.icon,
    this.height = 64,
    this.foreground = GlassTokens.ink,
    this.fontSize = 19,
    this.radius = GlassTokens.rLg,
  }) : filled = true,
       onColor = false;

  const GlassButton.glass({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 56,
    this.foreground = GlassTokens.ink,
    this.fontSize = 16,
    this.radius = GlassTokens.rLg,
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
          Icon(icon, size: fontSize + 11, color: foreground),
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
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
        ),
      ],
    );

    final c = color;
    final Widget face;
    if (filled && c != null) {
      face = _FilledGlass(color: c, radius: radius, child: content);
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

/// 상태색으로 꽉 찬 유리 — 색 면 + 위쪽 광택 + rim + 같은 색 그림자.
class _FilledGlass extends StatelessWidget {
  const _FilledGlass({
    required this.color,
    required this.radius,
    required this.child,
  });

  final Color color;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.38),
            blurRadius: 22,
            spreadRadius: -4,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: GlassTokens.shadowInk.withValues(alpha: 0.06),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      Colors.white.withValues(alpha: 0.18),
                      color,
                    ),
                    color,
                  ],
                ),
              ),
            ),
            // 위쪽 광택 (반사광)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.white.withValues(alpha: 0.32),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: ShapeDecoration(
                shape: GlassTokens.shape(
                  radius,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.45),
                    width: GlassTokens.rimWidth,
                  ),
                ),
              ),
            ),
            Center(child: child),
          ],
        ),
      ),
    );
  }
}

/// 원형 유리 아이콘 버튼 (진행 화면 종료/건너뛰기, 상단 설정·뒤로가기)
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
  });

  /// 카드 안처럼 이미 유리 위에 놓일 때는 그림자를 끈다.
  final bool shadow;

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final Color iconColor;
  final bool onColor;
  final GlassMaterial material;

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
            radius: GlassTokens.rPill,
            child: Center(
              child: Icon(icon, size: size * 0.46, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// 알약 칩 (진행 화면 '다음 · 휴식', 상단 '운동 기록')
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.color = GlassTokens.ink,
    this.onColor = false,
    this.fontSize = 12.5,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color color;
  final bool onColor;
  final double fontSize;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final chip = GlassSurface(
      material: GlassMaterial.thin,
      onColor: onColor,
      radius: GlassTokens.rPill,
      shadow: !onColor,
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 11 : 14,
        vertical: dense ? 6 : 8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 3, color: color),
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
                fontWeight: FontWeight.w800,
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

/// iOS 설정식 묶음 카드 — 행 사이에 얇은 구분선이 들어간 유리 그룹.
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
              height: 0.6,
              color: GlassTokens.ink.withValues(alpha: 0.10),
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

/// 섹션 라벨 (§4-3 overline)
class GlassSectionLabel extends StatelessWidget {
  const GlassSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 2, bottom: 8),
      child: Text(text, style: GlassTokens.overline),
    );
  }
}
