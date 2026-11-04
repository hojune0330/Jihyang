import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 화면 중앙의 초대형 시간 표시.
///
/// 네온/발광/그라데이션 없이 단색 + 높은 대비만 사용한다.
/// 주어진 폭/높이를 실제로 측정해 글자 크기를 계산하므로
/// 어떤 화면 비율에서도 숫자가 잘리지 않는다.
class HugeTimeDisplay extends StatelessWidget {
  const HugeTimeDisplay({
    super.key,
    required this.totalSeconds,
    required this.color,
    required this.fontSize,
    this.showHours = false,
    this.horizontalPadding = 20,
  });

  final int totalSeconds;
  final Color color;

  /// 최대 폰트 크기(px). 화면이 좁으면 자동으로 줄어든다.
  final double fontSize;
  final bool showHours;
  final double horizontalPadding;

  /// 기준 측정 크기
  static const double _probe = 100;

  @override
  Widget build(BuildContext context) {
    final clamped = totalSeconds < 0 ? 0 : totalSeconds;
    final h = clamped ~/ 3600;
    final m = (clamped % 3600) ~/ 60;
    final s = clamped % 60;

    final useHours = showHours || h > 0;
    final text = useHours ? '$h:${_p(m)}:${_p(s)}' : '${_p(m)}:${_p(s)}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth.isFinite
            ? constraints.maxWidth - horizontalPadding * 2
            : 400.0;
        final availableH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fontSize * 1.1;

        // 기준 크기로 한 번 측정한 뒤 비율로 축소 → 결정적이고 빠르다.
        final probeStyle = _style(_probe);
        final tp = TextPainter(
          text: TextSpan(text: text, style: probeStyle),
          textDirection: ui.TextDirection.ltr,
          maxLines: 1,
        )..layout();

        final wRatio = availableW > 0 ? availableW / tp.width : 1.0;
        final hRatio = availableH > 0 ? availableH / tp.height : 1.0;
        final scale = [wRatio, hRatio, fontSize / _probe]
            .reduce((a, b) => a < b ? a : b)
            .clamp(0.1, 10.0);

        final size = _probe * scale;
        tp.dispose();

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: _style(size),
          ),
        );
      },
    );
  }

  TextStyle _style(double size) => TextStyle(
    fontSize: size,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -size * 0.03,
    color: color,
    fontFeatures: const [ui.FontFeature.tabularFigures()],
  );

  String _p(int v) => v.toString().padLeft(2, '0');
}
