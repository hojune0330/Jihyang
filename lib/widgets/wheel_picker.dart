import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass/glass.dart';

/// 아이폰 알람 스타일 휠 컬럼.
///
/// 실제 손가락 드래그(FixedExtentScrollPhysics)로 값이 바뀌고,
/// 한 칸씩 스냅되며, 중앙 값만 크고 진하게 표시된다.
/// (드래그하는 척하는 시각효과가 아니라 실제 스크롤이다)
class WheelColumn extends StatefulWidget {
  const WheelColumn({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.accent,
    required this.onChanged,
    this.suffix = '',
    this.width = 92,
    this.itemExtent = 44,
    this.visibleRows = 5,
    this.enabled = true,
  }) : assert(max >= min, 'max must be >= min');

  final int value;
  final int min;
  final int max;
  final Color accent;
  final ValueChanged<int> onChanged;
  final String suffix;
  final double width;
  final double itemExtent;

  /// 홀수 권장 (3, 5, 7) — 중앙 정렬이 깔끔해진다.
  final int visibleRows;
  final bool enabled;

  @override
  State<WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<WheelColumn> {
  late FixedExtentScrollController _ctrl;
  late int _current;

  int get _count => widget.max - widget.min + 1;

  @override
  void initState() {
    super.initState();
    _current = widget.value.clamp(widget.min, widget.max);
    _ctrl = FixedExtentScrollController(initialItem: _current - widget.min);
  }

  @override
  void didUpdateWidget(covariant WheelColumn old) {
    super.didUpdateWidget(old);
    if (old.min != widget.min || old.max != widget.max) {
      _ctrl.dispose();
      _current = widget.value.clamp(widget.min, widget.max);
      _ctrl = FixedExtentScrollController(initialItem: _current - widget.min);
      return;
    }
    // 외부에서 값이 바뀐 경우(프리셋 등) 휠도 따라 이동
    final target = widget.value.clamp(widget.min, widget.max);
    if (target != _current && !_isDragging) {
      _current = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_ctrl.hasClients) return;
        final idx = target - widget.min;
        if (_ctrl.selectedItem != idx) _ctrl.jumpToItem(idx);
      });
    }
  }

  bool _isDragging = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extent = widget.itemExtent;
    final height = extent * widget.visibleRows;

    return SizedBox(
      width: widget.width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 중앙 선택 영역 표시
          Positioned(
            left: 0,
            right: 0,
            top: (height - extent) / 2,
            height: extent,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: GlassTokens.shape(
                    GlassTokens.rXs,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: GlassTokens.rimWidth,
                    ),
                  ),
                  color: Color.alphaBlend(
                    widget.accent.withValues(alpha: 0.10),
                    GlassTokens.ink.withValues(alpha: 0.05),
                  ),
                ),
              ),
            ),
          ),
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification) _isDragging = true;
              if (n is ScrollEndNotification) _isDragging = false;
              return false;
            },
            child: ListWheelScrollView.useDelegate(
              controller: _ctrl,
              itemExtent: extent,
              physics: widget.enabled
                  ? const FixedExtentScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              diameterRatio: 1.55,
              perspective: 0.0035,
              squeeze: 1.0,
              useMagnifier: true,
              magnification: 1.32,
              overAndUnderCenterOpacity: 0.34,
              onSelectedItemChanged: (index) {
                final v = widget.min + index.clamp(0, _count - 1);
                if (v == _current) return;
                _current = v;
                widget.onChanged(v);
              },
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: _count,
                builder: (context, index) {
                  final v = widget.min + index;
                  final selected = v == _current;
                  return Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${v.toString().padLeft(2, '0')}${widget.suffix}',
                        maxLines: 1,
                        style: TextStyle(
                          color: selected
                              ? (widget.enabled
                                    ? AppColors.textPrimary
                                    : AppColors.textTertiary)
                              : AppColors.textSecondary,
                          fontSize: selected ? 27 : 20,
                          height: 1.0,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          letterSpacing: -0.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 분 : 초 휠 피커 (아이폰 알람 스타일)
class WheelDurationPicker extends StatelessWidget {
  const WheelDurationPicker({
    super.key,
    required this.seconds,
    required this.accent,
    required this.onChanged,
    this.unitLabel = '분',
    this.maxMinutes = 59,
  });

  final int seconds;
  final Color accent;
  final ValueChanged<int> onChanged;
  final String unitLabel;
  final int maxMinutes;

  @override
  Widget build(BuildContext context) {
    final m = (seconds ~/ 60).clamp(0, maxMinutes);
    final s = seconds % 60;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WheelColumn(
              value: m,
              min: 0,
              max: maxMinutes,
              accent: accent,
              onChanged: (v) => onChanged(v * 60 + s),
            ),
            const SizedBox(height: 5),
            Text(
              unitLabel,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 18),
          child: Text(
            ':',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WheelColumn(
              value: s,
              min: 0,
              max: 59,
              accent: accent,
              onChanged: (v) => onChanged(m * 60 + v),
            ),
            const SizedBox(height: 5),
            const Text(
              '초',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 설정 행을 눌렀을 때 휠 피커가 담긴 바텀시트를 띄우는 헬퍼.
///
/// 값이 바뀔 때마다 [onChanged] 가 즉시 호출되어 설정값에 바로 반영된다.
Future<void> showWheelSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required Widget picker,
  required Color accent,
  required VoidCallback onDone,
  Widget? extra,
}) {
  return showGlassSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: GlassTokens.title.copyWith(fontSize: 17.5)),
          const SizedBox(height: 4),
          Text(subtitle, style: GlassTokens.caption.copyWith(fontSize: 12)),
          const SizedBox(height: 14),
          picker,
          if (extra != null) extra,
          const SizedBox(height: 16),
          GlassButton.filled(
            label: '완료',
            color: accent,
            height: 54,
            fontSize: 16,
            radius: GlassTokens.rMd,
            foreground: accent == AppColors.textPrimary
                ? Colors.white
                : AppColors.ink,
            onPressed: () {
              onDone();
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    ),
  );
}
