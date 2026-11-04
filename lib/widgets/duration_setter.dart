import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// 분/초를 각각 조절·입력하는 시간 설정 타일.
///
/// - +/- 버튼으로 1단위 조절 (길게 누르면 연속 조절)
/// - 숫자를 직접 탭해서 키보드 입력
/// - 초는 0~59 범위로 자동 제한
class DurationSetter extends StatefulWidget {
  const DurationSetter({
    super.key,
    required this.label,
    required this.seconds,
    required this.onChanged,
    required this.accent,
    this.maxMinutes = 59,
    this.allowZero = false,
  });

  final String label;

  /// 총 초 단위 값
  final int seconds;
  final ValueChanged<int> onChanged;
  final Color accent;
  final int maxMinutes;
  final bool allowZero;

  @override
  State<DurationSetter> createState() => _DurationSetterState();
}

class _DurationSetterState extends State<DurationSetter> {
  bool get _canZero => widget.allowZero;

  int get _minutes => widget.seconds ~/ 60;
  int get _secs => widget.seconds % 60;

  void _set({int? minutes, int? secs}) {
    final m = (minutes ?? _minutes).clamp(0, widget.maxMinutes);
    final s = (secs ?? _secs).clamp(0, 59);
    var total = m * 60 + s;
    if (!_canZero && total < 1) total = 1;
    widget.onChanged(total);
  }

  Future<void> _editNumber({required bool isMinute}) async {
    final current = isMinute ? _minutes : _secs;
    final controller = TextEditingController(text: current.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceHigh,
          title: Text(
            isMinute ? '분 입력' : '초 입력',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (v) =>
                Navigator.of(ctx).pop(int.tryParse(v) ?? current),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                '취소',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(
                ctx,
              ).pop(int.tryParse(controller.text) ?? current),
              child: const Text(
                '확인',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    if (isMinute) {
      _set(minutes: result.clamp(0, widget.maxMinutes));
    } else {
      _set(secs: result.clamp(0, 59));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _UnitBox(
                value: _minutes,
                unit: '분',
                accent: widget.accent,
                onTap: () => _editNumber(isMinute: true),
                onMinus: _minutes > 0
                    ? () => _set(minutes: _minutes - 1)
                    : null,
                onPlus: _minutes < widget.maxMinutes
                    ? () => _set(minutes: _minutes + 1)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _UnitBox(
                value: _secs,
                unit: '초',
                accent: widget.accent,
                onTap: () => _editNumber(isMinute: false),
                onMinus: (_secs > 0 || _minutes > 0)
                    ? () => _set(
                        secs: _secs > 0 ? _secs - 1 : 59,
                        minutes: _secs > 0 ? null : _minutes - 1,
                      )
                    : null,
                onPlus: _secs < 59 ? () => _set(secs: _secs + 1) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _UnitBox extends StatelessWidget {
  const _UnitBox({
    required this.value,
    required this.unit,
    required this.accent,
    required this.onTap,
    this.onMinus,
    this.onPlus,
  });

  final int value;
  final String unit;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Row(
        children: [
          _StepBtn(icon: Icons.remove_rounded, onTap: onMinus, color: accent),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: accent,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    unit,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _StepBtn(icon: Icons.add_rounded, onTap: onPlus, color: accent),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 62,
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? color
              : AppColors.textTertiary.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
