import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 화면 중앙 대형 시간 표시.
///
/// 남은 시간(분:초)을 가장 크게 보여주고, 시가 있을 때만 앞에 붙인다.
/// 각 단위는 구간 색 계열 안에서 서로 다른 진한 색으로 강조한다.
class BigTimeDisplay extends StatelessWidget {
  const BigTimeDisplay({
    super.key,
    required this.totalSeconds,
    required this.phaseType,
    required this.fontSize,
    this.dimWhenZero = false,
  });

  final int totalSeconds;
  final String phaseType;
  final double fontSize;
  final bool dimWhenZero;

  @override
  Widget build(BuildContext context) {
    final clamped = totalSeconds < 0 ? 0 : totalSeconds;
    final h = clamped ~/ 3600;
    final m = (clamped % 3600) ~/ 60;
    final s = clamped % 60;

    final minuteColor = AppColors.minuteFor(phaseType);
    final secondColor = AppColors.secondFor(phaseType);
    final dim = dimWhenZero ? 0.55 : 1.0;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (h > 0) ...[
            _Num(
              text: h.toString(),
              color: AppColors.hourColor,
              fontSize: fontSize * 0.62,
            ),
            _Sep(color: AppColors.hourColor, fontSize: fontSize * 0.62),
          ],
          _Num(
            text: m.toString().padLeft(2, '0'),
            color: minuteColor.withValues(alpha: dim),
            fontSize: fontSize,
          ),
          _Sep(
            color: minuteColor.withValues(alpha: dim),
            fontSize: fontSize,
          ),
          _Num(
            text: s.toString().padLeft(2, '0'),
            color: secondColor.withValues(alpha: dim),
            fontSize: fontSize,
          ),
        ],
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep({required this.color, required this.fontSize});

  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.04),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: fontSize * 0.78,
          height: 1,
          fontWeight: FontWeight.w800,
          color: color.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num({required this.text, required this.color, required this.fontSize});

  final String text;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      height: 1,
      fontWeight: FontWeight.w900,
      letterSpacing: -3,
      color: color,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        // 진한 네온 글로우
        Text(
          text,
          style: style.copyWith(
            color: color.withValues(alpha: 0.55),
            shadows: [
              Shadow(
                color: color.withValues(alpha: 0.9),
                blurRadius: fontSize * 0.30,
              ),
              Shadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: fontSize * 0.70,
              ),
            ],
          ),
        ),
        Text(text, style: style),
      ],
    );
  }
}
