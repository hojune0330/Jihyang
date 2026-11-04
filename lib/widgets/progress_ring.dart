import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 원형 진행 링 — 남은 시간을 시각적으로 표현하는 **메인** 요소.
///
/// 설계 원칙
///  - 얇고 균일한 선. 그라데이션·발광·그림자 없음.
///  - 12시 방향에서 시작해 **시계 방향으로 줄어든다** (남은 시간이 줄면 링도 줄어든다).
///  - 진행률은 엔진의 실제 경과 시간에서 계산된 값을 그대로 받는다
///    (여기서 시간을 따로 세지 않는다 → 타이머와 어긋날 수 없다).
///  - 트랙(배경 링)을 옅게 깔아 '남은 양'이 한눈에 비교된다.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.child,
    this.strokeWidth = 10,
    this.gap = 18,
  });

  /// 0.0 ~ 1.0 (1 = 가득 참)
  final double progress;
  final Color color;
  final Color trackColor;
  final Widget child;
  final double strokeWidth;

  /// 링과 안쪽 숫자 사이 여백
  final double gap;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, c) {
        // 정사각형 한 변 — 주어진 공간에 맞춰 결정
        final side = math.min(
          c.maxWidth.isFinite ? c.maxWidth : c.maxHeight,
          c.maxHeight.isFinite ? c.maxHeight : c.maxWidth,
        );
        return SizedBox(
          width: side.isFinite ? side : 300,
          height: side.isFinite ? side : 300,
          child: CustomPaint(
            painter: _RingPainter(
              progress: p,
              color: color,
              trackColor: trackColor,
              strokeWidth: strokeWidth,
            ),
            child: Padding(
              padding: EdgeInsets.all(strokeWidth + gap),
              child: Center(child: child),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);

    // 트랙 (남은 양을 비교할 기준)
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    // 진행 호 — 12시에서 시작, 시계 방향
    if (progress > 0) {
      final fill = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color;
      const start = -math.pi / 2;
      canvas.drawArc(rect, start, 2 * math.pi * progress, false, fill);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
