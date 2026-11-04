import 'package:flutter/material.dart';

/// 투명도 + 하이라이트 + 그림자로 입체감을 준 글래스 버튼
class DepthButton extends StatefulWidget {
  const DepthButton({
    super.key,
    required this.onTap,
    this.label,
    this.icon,
    this.accent = const Color(0xFFFFFFFF),
    this.height = 60,
    this.width,
    this.expand = false,
    this.filled = false,
    this.enabled = true,
    this.radius = 20,
    this.iconSize = 24,
    this.fontSize = 15,
  });

  final VoidCallback? onTap;
  final String? label;
  final IconData? icon;
  final Color accent;
  final double height;
  final double? width;
  final bool expand;

  /// true면 accent 색을 진하게(주요 CTA), false면 유리처럼 투명하게
  final bool filled;
  final bool enabled;
  final double radius;
  final double iconSize;
  final double fontSize;

  @override
  State<DepthButton> createState() => _DepthButtonState();
}

class _DepthButtonState extends State<DepthButton> {
  bool _pressed = false;

  bool get _active => widget.enabled && widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final pressed = _pressed && _active;

    // 투명 레이어 조합 — 위에서 아래로 빛이 떨어지는 느낌
    final topAlpha = widget.filled ? 0.92 : 0.16;
    final bottomAlpha = widget.filled ? 0.62 : 0.05;

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.alphaBlend(accent.withValues(alpha: topAlpha), Colors.black),
        Color.alphaBlend(accent.withValues(alpha: bottomAlpha), Colors.black),
      ],
    );

    final content = widget.label == null
        ? Icon(
            widget.icon,
            size: widget.iconSize,
            color: widget.filled
                ? Colors.black.withValues(alpha: 0.86)
                : accent,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: widget.filled
                      ? Colors.black.withValues(alpha: 0.86)
                      : accent,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  widget.label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.filled
                        ? Colors.black.withValues(alpha: 0.88)
                        : accent,
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          );

    Widget body = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      height: widget.height,
      width: widget.expand ? double.infinity : widget.width,
      transform: Matrix4.translationValues(0, pressed ? 2.5 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        gradient: gradient,
        border: Border.all(
          color: accent.withValues(alpha: pressed ? 0.20 : 0.34),
          width: 1.1,
        ),
        boxShadow: pressed
            ? [
                // 눌렸을 때: 그림자가 줄고 위쪽 하이라이트가 사라짐
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
                BoxShadow(
                  color: accent.withValues(alpha: widget.filled ? 0.18 : 0.10),
                  blurRadius: 12,
                  spreadRadius: -4,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                // 떠 있을 때: 아래로 떨어지는 그림자 + 은은한 발광
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.62),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: accent.withValues(alpha: widget.filled ? 0.34 : 0.14),
                  blurRadius: 22,
                  spreadRadius: -6,
                  offset: const Offset(0, 4),
                ),
                // 상단 유리 반사광
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.06),
                  blurRadius: 2,
                  spreadRadius: 0,
                  offset: const Offset(0, -1),
                ),
              ],
      ),
      child: Stack(
        children: [
          // 상단 하이라이트 광택
          Positioned(
            left: 8,
            right: 8,
            top: 1.2,
            child: IgnorePointer(
              child: Container(
                height: widget.height * 0.34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.radius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(
                        alpha: widget.filled ? 0.28 : 0.12,
                      ),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: content,
            ),
          ),
        ],
      ),
    );

    if (!_active) {
      body = Opacity(opacity: 0.38, child: body);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _active ? (_) => setState(() => _pressed = true) : null,
      onTapUp: _active ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: _active ? () => setState(() => _pressed = false) : null,
      onTap: _active ? widget.onTap : null,
      child: body,
    );
  }
}
