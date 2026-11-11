import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 글래스 디자인 시스템 토큰 — docs/glass/DESIGN_SYSTEM.md §3~§5.
///
/// 모든 화면은 이 파일의 값만 쓴다. 화면 안에서 임의의 알파·블러·그림자를
/// 새로 만들지 않는다 (재질이 화면마다 달라지는 문제의 재발 방지).

/// 유리 재질 3단계 (§3)
enum GlassMaterial { thin, regular, thick }

/// 재질 한 단계의 물리값
@immutable
class GlassSpec {
  const GlassSpec({
    required this.blur,
    required this.fillLight,
    required this.fillOnColor,
    required this.rimTop,
    required this.rimBottom,
  });

  /// 배경 블러 σ
  final double blur;

  /// 밝은(ambient) 배경 위 흰 면 알파
  final double fillLight;

  /// 상태색(phase) 배경 위 흰 면 알파
  final double fillOnColor;

  /// 테두리 rim — 위쪽 / 아래쪽 흰색 알파
  final double rimTop;
  final double rimBottom;
}

class GlassTokens {
  GlassTokens._();

  // ------------------------------------------------------------ 재질 §3
  static const Map<GlassMaterial, GlassSpec> specs = {
    GlassMaterial.thin: GlassSpec(
      blur: 18,
      fillLight: 0.38,
      fillOnColor: 0.16,
      rimTop: 0.55,
      rimBottom: 0.15,
    ),
    GlassMaterial.regular: GlassSpec(
      blur: 24,
      fillLight: 0.58,
      fillOnColor: 0.20,
      rimTop: 0.85,
      rimBottom: 0.25,
    ),
    GlassMaterial.thick: GlassSpec(
      blur: 32,
      fillLight: 0.78,
      fillOnColor: 0.28,
      rimTop: 0.90,
      rimBottom: 0.30,
    ),
  };

  static GlassSpec spec(GlassMaterial m) => specs[m]!;

  /// 위쪽 하이라이트 (위 0~45% 구간, 흰색 알파 → 0)
  static const double highlightAlpha = 0.35;
  static const double highlightAlphaOnColor = 0.18;
  static const double highlightStop = 0.45;

  /// 상태색 틴트 알파 범위
  static const double tintAlpha = 0.12;

  /// rim 두께
  static const double rimWidth = 1.0;

  // ------------------------------------------------------------ 그림자 §3
  static const Color shadowInk = Color(0xFF1A1D2E);

  static List<BoxShadow> shadow({bool onColor = false, double lift = 1.0}) => [
    BoxShadow(
      color: shadowInk.withValues(alpha: (onColor ? 0.16 : 0.10) * lift),
      blurRadius: 30,
      spreadRadius: -8,
      offset: Offset(0, 14 * lift),
    ),
    BoxShadow(
      color: shadowInk.withValues(alpha: onColor ? 0.08 : 0.05),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];

  // ------------------------------------------------------------ 곡률 §4-1
  static const double rXs = 10;
  static const double rSm = 14;
  static const double rMd = 20;
  static const double rLg = 26;
  static const double rXl = 32;
  static const double rPill = 999;

  static ShapeBorder shape(double r, {BorderSide side = BorderSide.none}) =>
      RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(r),
        side: side,
      );

  // ------------------------------------------------------------ 간격 §4-2
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double screenX = 18;

  // ------------------------------------------------------------ 글자색 §4-4
  static const Color ink = Color(0xFF15161B);
  static const Color sub = Color(0xFF5B5F6E);
  static const Color tert = Color(0xFF8A8E9C);

  /// 흰 유리 위 글자 전용 진한 상태색 (대비 4.5:1 확보)
  static const Color workText = Color(0xFFC24A42);
  static const Color restText = Color(0xFF3466BA);
  static const Color prepText = Color(0xFF8A6800);

  /// 상태 이름 → 글자용 진한 색
  static Color textOf(String phaseType) => switch (phaseType) {
    'work' => workText,
    'rest' || 'setRest' => restText,
    _ => prepText,
  };

  // ------------------------------------------------------------ 배경 §2
  static const Color ambientTop = Color(0xFFF3F5FC);
  static const Color ambientBottom = Color(0xFFFFF4EE);

  static const Color orbCoral = Color(0xFFFF9B8A);
  static const Color orbSky = Color(0xFF8CC4FF);
  static const Color orbAmber = Color(0xFFFFD98A);
  static const Color orbMint = Color(0xFF9CE8CF);
  static const Color orbLilac = Color(0xFFC7B4FF);

  // ------------------------------------------------------------ 모션 §5
  static const double pressScale = 0.97;
  static const Duration pressIn = Duration(milliseconds: 90);
  static const Duration pressOut = Duration(milliseconds: 260);
  static const Curve pressOutCurve = Curves.easeOutBack;
  static const Duration state = Duration(milliseconds: 220);
  static const Curve stateCurve = Curves.easeOutCubic;
  static const Duration phase = Duration(milliseconds: 360);
  static const Curve phaseCurve = Curves.easeInOut;

  // ------------------------------------------------------------ 타이포 §4-3
  static const TextStyle title = TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: ink,
    fontSize: 17,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
  );
  static const TextStyle headline = TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: ink,
    fontSize: 15,
    fontWeight: FontWeight.w800,
  );
  static const TextStyle body = TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: ink,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: sub,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  static const TextStyle overline = TextStyle(
    fontFamily: AppTheme.fontFamily,
    color: sub,
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
  );
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  // ------------------------------------------------------------ 상태색 (유지)
  /// 상태색 값 자체는 AppColors 를 그대로 쓴다 (정체성 유지 §0-1).
  static const Color work = AppColors.work;
  static const Color rest = AppColors.rest;
  static const Color prepare = AppColors.prepare;
}
