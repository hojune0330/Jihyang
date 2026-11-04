import 'package:flutter/material.dart';

/// 현재 라운드 / 전체 라운드를 점으로 표시.
/// 진행할수록 채워지고, 현재 라운드는 테두리로 강조한다.
class RoundDots extends StatelessWidget {
  const RoundDots({
    super.key,
    required this.total,
    required this.current,
    required this.accent,
    this.dimmed = false,
  });

  final int total;
  final int current;
  final Color accent;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, box) {
        const gap = 5.0;
        final maxWidth = box.maxWidth;
        // 점 지름을 공간에 맞춰 자동 축소 (최대 14, 최소 4)
        final dot = ((maxWidth - gap * (total - 1)) / total).clamp(4.0, 14.0);
        final adjustedGap = total > 1
            ? ((maxWidth - dot * total) / (total - 1)).clamp(1.0, gap)
            : gap;

        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) SizedBox(width: adjustedGap),
                _Dot(
                  size: dot,
                  done: i < current - 1,
                  now: i == current - 1,
                  dimmed: dimmed,
                  accent: accent,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.size,
    required this.done,
    required this.now,
    required this.dimmed,
    required this.accent,
  });

  final double size;
  final bool done;
  final bool now;
  final bool dimmed;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final base = dimmed ? 0.35 : 1.0;
    if (now) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent.withValues(alpha: 0.95 * base),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.85 * base),
              blurRadius: size * 1.1,
              spreadRadius: size * 0.12,
            ),
          ],
        ),
      );
    }
    if (done) {
      return Container(
        width: size * 0.82,
        height: size * 0.82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent.withValues(alpha: 0.55 * base),
        ),
      );
    }
    return Container(
      width: size * 0.82,
      height: size * 0.82,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: accent.withValues(alpha: 0.30 * base),
          width: 1.2,
        ),
      ),
    );
  }
}
