import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 시 / 분 / 초 를 각각 다른 색으로 강조한 대형 타이머
class TimerDisplay extends StatelessWidget {
  const TimerDisplay({
    super.key,
    required this.totalSeconds,
    this.dimZeroHours = true,
    this.fontSize = 66,
  });

  final int totalSeconds;
  final bool dimZeroHours;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final clamped = totalSeconds < 0 ? 0 : totalSeconds;
    final h = (clamped ~/ 3600).clamp(0, 99);
    final m = ((clamped % 3600) ~/ 60).clamp(0, 59);
    final s = (clamped % 60).clamp(0, 59);

    final hoursOpacity = (dimZeroHours && h == 0) ? 0.34 : 1.0;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Unit(
            value: h.toString().padLeft(2, '0'),
            label: '시',
            color: AppColors.hours,
            fontSize: fontSize,
            opacity: hoursOpacity,
          ),
          _Colon(
            color: AppColors.hours,
            fontSize: fontSize,
            opacity: hoursOpacity,
          ),
          _Unit(
            value: m.toString().padLeft(2, '0'),
            label: '분',
            color: AppColors.minutes,
            fontSize: fontSize,
          ),
          _Colon(color: AppColors.minutes, fontSize: fontSize),
          _Unit(
            value: s.toString().padLeft(2, '0'),
            label: '초',
            color: AppColors.seconds,
            fontSize: fontSize,
          ),
        ],
      ),
    );
  }
}

class _Colon extends StatelessWidget {
  const _Colon({
    required this.color,
    required this.fontSize,
    this.opacity = 1.0,
  });

  final Color color;
  final double fontSize;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: fontSize * 0.30),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: fontSize * 0.72,
          height: 1,
          fontWeight: FontWeight.w300,
          color: color.withValues(alpha: 0.42 * opacity),
        ),
      ),
    );
  }
}

class _Unit extends StatelessWidget {
  const _Unit({
    required this.value,
    required this.label,
    required this.color,
    required this.fontSize,
    this.opacity = 1.0,
  });

  final String value;
  final String label;
  final Color color;
  final double fontSize;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // 숫자 뒤 은은한 발광
            Text(
              value,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.0,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
                color: color.withValues(alpha: 0.28 * opacity),
                shadows: [
                  Shadow(
                    color: color.withValues(alpha: 0.55 * opacity),
                    blurRadius: fontSize * 0.42,
                  ),
                ],
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.0,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
                color: color.withValues(alpha: opacity),
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SizedBox(height: fontSize * 0.13),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10 * opacity),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: color.withValues(alpha: 0.26 * opacity),
              width: 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: (fontSize * 0.17).clamp(9.0, 14.0),
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: color.withValues(alpha: 0.92 * opacity),
            ),
          ),
        ),
      ],
    );
  }
}
