import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 한 번의 탭으로 값을 바꾸는 컴팩트 조절기 (설정 화면 이동 없이 인라인 편집)
class QuickStepper extends StatelessWidget {
  const QuickStepper({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.onChanged,
    required this.min,
    required this.max,
    this.step = 1,
    this.accent = AppColors.textPrimary,
    this.enabled = true,
  });

  final String label;
  final int value;
  final String unit;
  final int min;
  final int max;
  final int step;
  final Color accent;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final canDec = enabled && value - step >= min;
    final canInc = enabled && value + step <= max;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22), width: 1),
      ),
      child: Row(
        children: [
          _Btn(
            icon: Icons.remove_rounded,
            active: canDec,
            accent: accent,
            onTap: canDec ? () => onChanged(value - step) : null,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$value$unit',
                    style: TextStyle(
                      color: accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _Btn(
            icon: Icons.add_rounded,
            active: canInc,
            accent: accent,
            onTap: canInc ? () => onChanged(value + step) : null,
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.active,
    required this.accent,
    this.onTap,
  });

  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      containedInkWell: true,
      highlightShape: BoxShape.circle,
      child: SizedBox(
        width: 38,
        height: 48,
        child: Icon(
          icon,
          size: 20,
          color: accent.withValues(alpha: active ? 0.95 : 0.2),
        ),
      ),
    );
  }
}
