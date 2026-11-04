import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'depth_button.dart';

/// "n개 / n세트 / n분 휴식" 형태의 설정 행
class SettingStepper extends StatelessWidget {
  const SettingStepper({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.onChanged,
    this.min = 1,
    this.max = 20,
    this.step = 1,
    this.accent = AppColors.minutes,
    this.subtitle,
    this.suffix,
  });

  final String title;
  final String? subtitle;

  /// 표시에 사용할 접미어 (예: '분 휴식' → "2분 휴식")
  final String? suffix;

  final int value;

  /// 값이 1일 때 표시 단위 (예: '개')
  final String unit;

  final int min;
  final int max;
  final int step;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = suffix != null ? '$value$suffix' : '$value$unit';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.stroke, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          DepthButton(
            onTap: value - step >= min ? () => onChanged(value - step) : null,
            icon: Icons.remove_rounded,
            accent: accent,
            width: 42,
            height: 42,
            radius: 14,
            iconSize: 20,
          ),
          SizedBox(
            width: 86,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    shadows: [
                      Shadow(
                        color: accent.withValues(alpha: 0.45),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          DepthButton(
            onTap: value + step <= max ? () => onChanged(value + step) : null,
            icon: Icons.add_rounded,
            accent: accent,
            width: 42,
            height: 42,
            radius: 14,
            iconSize: 20,
          ),
        ],
      ),
    );
  }
}
