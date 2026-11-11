import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 글래스 디자인 시스템 토큰 — docs/glass/DESIGN_SYSTEM.md (v1.1)
///
/// 모든 화면은 이 파일의 값만 쓴다. 화면 안에서 임의의 알파·블러·그림자를
/// 새로 만들지 않는다.

/// 유리 재질 3단계
enum GlassMaterial { thin, regular, thick }

@immutable
class GlassSpec {
  const GlassSpec({
    required this.blur,
    required this.fillLight,
    required this.fillOnColor,
    required this.rim,
  });

  final double blur;

  /// 밝은 배경 위 흰 면 알파
  final double fillLight;

  /// 상태색 배경 위 흰 면 알파
  final double fillOnColor;

  /// 위쪽 1px 안쪽 하이라이트 알파
  final double rim;
}

class GlassTokens {
  GlassTokens._();

  // ------------------------------------------------------------ 재질
  static const Map<GlassMaterial, GlassSpec> specs = {
    GlassMaterial.thin: GlassSpec(
      blur: 16,
      fillLight: 0.55,
      fillOnColor: 0.18,
      rim: 0.55,
    ),
    GlassMaterial.regular: GlassSpec(
      blur: 24,
      fillLight: 0.72,
      fillOnColor: 0.22,
      rim: 0.85,
    ),
    GlassMaterial.thick: GlassSpec(
      blur: 30,
      fillLight: 0.86,
      fillOnColor: 0.30,
      rim: 0.95,
    ),
  };

  static GlassSpec spec(GlassMaterial m) => specs[m]!;

  static const double tintAlpha = 0.10;
  static const double hairline = 0.5;

  // ------------------------------------------------------------ 그림자 (1겹)
  static const Color shadowInk = Color(0xFF1C1C28);

  static List<BoxShadow> shadow({bool onColor = false}) => [
    BoxShadow(
      color: shadowInk.withValues(alpha: onColor ? 0.10 : 0.06),
      blurRadius: 24,
      spreadRadius: -6,
      offset: const Offset(0, 8),
    ),
  ];

  // ------------------------------------------------------------ 곡률
  static const double rXs = 10;
  static const double rSm = 14;
  static const double rMd = 20;
  static const double rLg = 26;
  static const double rXl = 32;

  /// 알약/원. 실제 반지름은 그릴 때 크기에 맞춰 [glassShape] 가 정한다.
  static const double rPill = 999;

  // ------------------------------------------------------------ 간격
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double screenX = 18;

  // ------------------------------------------------------------ 글자색
  static const Color ink = Color(0xFF111114);
  static const Color sub = Color(0xFF5E5E6A);
  static const Color tert = Color(0xFF747886);
  static const Color separator = Color(0x1F3C3C43);

  /// 흰 유리 위 글자 전용 진한 상태색 (대비 4.5:1, 테스트로 확정)
  static const Color workText = Color(0xFFAD3F38);
  static const Color restText = Color(0xFF2F5DAA);
  static const Color prepText = Color(0xFF7A5C00);

  /// 앱 틴트 — 스위치·슬라이더·텍스트 버튼 공통 1색
  static const Color tint = AppColors.work;
  static const Color tintText = workText;

  static Color textOf(String phaseType) => switch (phaseType) {
    'work' => workText,
    'rest' || 'setRest' => restText,
    _ => prepText,
  };

  /// 밝은 상태색(준비 옐로) 위 유리는 같은 색 계열로 진하게 누른다.
  static bool needsDarkGlass(Color bg) => bg.computeLuminance() > 0.5;

  /// 밝은 배경 위 '어두운 유리' 색 — 검정이 아니라 같은 색상의 진한 톤
  /// (노랑 위 검정 반투명은 탁한 올리브가 된다).
  static Color deepOf(Color bg) {
    final h = HSLColor.fromColor(bg);
    return h
        .withLightness((h.lightness * 0.36).clamp(0.0, 1.0))
        .withSaturation((h.saturation * 0.9).clamp(0.0, 1.0))
        .toColor();
  }

  // ------------------------------------------------------------ 배경
  static const Color ambientTop = Color(0xFFF2F2F7);
  static const Color ambientBottom = Color(0xFFF7F4F2);

  // ------------------------------------------------------------ 모션
  static const double pressScale = 0.97;
  static const Duration pressIn = Duration(milliseconds: 90);
  static const Duration pressOut = Duration(milliseconds: 260);
  static const Curve pressOutCurve = Curves.easeOutBack;
  static const Duration state = Duration(milliseconds: 220);
  static const Curve stateCurve = Curves.easeOutCubic;
  static const Duration phase = Duration(milliseconds: 360);
  static const Curve phaseCurve = Curves.easeInOut;

  // ------------------------------------------------------------ 타이포
  // 숫자만 굵게, 라벨은 가볍게 — 모든 글자가 소리치지 않게.
  static const TextStyle largeTitle = TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: ink,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
  );
  static const TextStyle title = TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: ink,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );
  static const TextStyle headline = TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: ink,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );
  static const TextStyle body = TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: ink,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
  );
  static const TextStyle label = TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: sub,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: sub,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );
  static const TextStyle overline = TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: tert,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  /// 큰 숫자
  static TextStyle number(double size, {Color color = ink}) => TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: color,
    fontSize: size,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -size * 0.035,
    fontFeatures: tabular,
  );

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  // ------------------------------------------------------------ 상태색 (유지)
  static const Color work = AppColors.work;
  static const Color rest = AppColors.rest;
  static const Color prepare = AppColors.prepare;
}

/// 모든 유리 부품이 쓰는 **단 하나의** 모양.
///
/// 곡률은 그릴 때마다 실제 크기를 보고 정한다.
///  - r 이 짧은 변의 절반 이상이면 stadium(알약/원) 경로
///  - 아니면 연속 곡률(superellipse)
/// superellipse 는 곡률이 변의 절반을 넘으면 경로가 깨져 화면 밖까지 곡선이
/// 튀어나간다 (v1 진행 화면 버튼 버그). 이 판단을 위젯마다 하지 않고 모양에
/// 넣어서 어떤 부품이 어떤 반지름을 넘겨도 깨지지 않게 한다.
class GlassBorder extends OutlinedBorder {
  const GlassBorder({this.radius = GlassTokens.rMd, super.side});

  final double radius;

  bool _isPill(Rect rect) => radius * 2 >= rect.shortestSide;

  Path _path(Rect rect) {
    if (_isPill(rect)) {
      return Path()..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
      );
    }
    return Path()..addRSuperellipse(
      RSuperellipse.fromRectAndRadius(rect, Radius.circular(radius)),
    );
  }

  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      GlassBorder(radius: radius, side: side ?? this.side);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    final inset = side.strokeInset - side.width / 2;
    canvas.drawPath(_path(rect.deflate(inset)), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) =>
      GlassBorder(radius: radius * t, side: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is GlassBorder && other.radius == radius && other.side == side;

  @override
  int get hashCode => Object.hash(radius, side);
}

/// 모양 클리퍼 — [GlassBorder] 경로로 자른다.
class GlassClip extends StatelessWidget {
  const GlassClip({super.key, required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: ShapeBorderClipper(shape: GlassBorder(radius: radius)),
      child: child,
    );
  }
}
