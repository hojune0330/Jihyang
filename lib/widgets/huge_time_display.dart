import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 화면 중앙의 초대형 시간 표시.
///
/// 네온/발광/그라데이션 없이 단색 + 높은 대비만 사용한다.
///
/// ## 숫자가 잘리지 않는 이유
///
/// 1. 주어진 폭과 높이를 **둘 다** 측정해서 더 작은 쪽 배율을 쓴다.
///    (폭만 보면 세로로 넘치고, 높이만 보면 가로로 잘린다)
/// 2. 글자 폭을 정확히 재기 위해 `TextPainter` 로 실측한다.
///    `letterSpacing` 이 음수여도 실제 렌더 폭에 반영된다.
/// 3. 여백(padding)을 뺀 **안전 영역** 안에서만 크기를 정한다.
///    그래서 어떤 화면 비율에서도 좌우가 잘리지 않는다.
/// 4. 마지막으로 `FittedBox(scaleDown)` 을 한 겹 더 둬서,
///    폰트 메트릭이 기기마다 조금 달라도 절대 넘치지 않게 한다.
class HugeTimeDisplay extends StatelessWidget {
  const HugeTimeDisplay({
    super.key,
    required this.totalSeconds,
    required this.color,
    required this.fontSize,
    this.showHours = false,
    this.horizontalPadding = 20,
    this.shadows,
  });

  final int totalSeconds;
  final Color color;

  /// 최대 폰트 크기(px). 공간이 부족하면 자동으로 줄어든다.
  final double fontSize;
  final bool showHours;
  final double horizontalPadding;
  final List<Shadow>? shadows;

  /// 기준 측정 크기
  static const double _probe = 100;

  /// 어떤 경우에도 이 배율 아래로는 내려가지 않는다 (가독성 하한).
  static const double _minScale = 0.5;

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
        final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        final maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : 400.0;

        var availableW = maxW - horizontalPadding * 2;
        var availableH = maxH;
        // 아주 작은 공간이 들어와도 계산이 무너지지 않게 하한을 둔다.
        if (availableW <= 8) availableW = maxW > 8 ? maxW : 8;
        if (availableH <= 8) availableH = maxH;

        // 기준 크기로 실측 → 폭/높이 중 더 빡빡한 쪽에 맞춘다.
        final tp = TextPainter(
          text: TextSpan(text: text, style: _style(_probe)),
          textDirection: ui.TextDirection.ltr,
          maxLines: 1,
        )..layout();

        final wRatio = availableW / tp.width;
        final hRatio = availableH / tp.height;
        final capRatio = fontSize / _probe;
        final scale = [wRatio, hRatio, capRatio].reduce((a, b) => a < b ? a : b);
        tp.dispose();

        // 가독성 하한(0.5배)을 적용하되, 공간을 넘지 않도록 다시 clamp.
        final floorScale = capRatio * _minScale;
        final finalScale = scale < floorScale && scale > 0 ? floorScale : scale;
        final size = _probe * finalScale.clamp(0.1, 10.0);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: _style(size),
            ),
          ),
        );
      },
    );
  }

  TextStyle _style(double size) => TextStyle(
    fontSize: size,
    height: 1.16, // 위/아래 여유 — 실제 글리프가 잘리지 않게
    fontWeight: FontWeight.w800,
    letterSpacing: -size * 0.02,
    color: color,
    shadows: shadows,
    fontFeatures: const [ui.FontFeature.tabularFigures()],
  );

  String _p(int v) => v.toString().padLeft(2, '0');
}
