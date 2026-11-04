import 'package:flutter/material.dart';

/// 무광 단색 디자인 토큰.
/// 그라데이션 / 네온 / 발광 / 과한 그림자를 사용하지 않는다.
///
/// 색 체계 원칙
///  1. 운동·휴식·준비 색은 **앱 전체에서 단 하나의 값**만 쓴다.
///     진행 화면의 전체 배경색과 메인/설정 화면의 강조색이 같은 값을 공유한다.
///  2. 진행 화면 배경은 그 색을 그대로 화면 전체에 채운다.
///  3. 배경 위 글자는 배경 밝기에 따라 화이트 또는 잉크(검정)로 자동 반전한다.
class AppColors {
  AppColors._();

  // ---------------------------------------------------------------
  // 기본 (짙은 차콜)
  // ---------------------------------------------------------------
  static const Color background = Color(0xFF0E0F12);
  static const Color surface = Color(0xFF1A1B1F);
  static const Color surfaceHigh = Color(0xFF24252A);
  static const Color divider = Color(0xFF31323A);

  // ---------------------------------------------------------------
  // 상태 색 — 앱 전체 공통 (부드러운 저채도)
  // ---------------------------------------------------------------
  /// 운동 : 소프트 코랄
  static const Color work = Color(0xFFE77D75);

  /// 휴식 : 소프트 블루
  static const Color rest = Color(0xFF648BD2);

  /// 준비 / 카운트다운 : 소프트 옐로
  static const Color prepare = Color(0xFFE8C96D);

  // 진행 화면 전체 배경도 동일한 값을 그대로 사용한다.
  static const Color workBg = work;
  static const Color restBg = rest;

  /// 준비 화면 배경.
  ///
  /// 요구사항: "준비 화면 글자색은 화이트".
  /// 소프트 옐로(#E8C96D) 위 흰 글자는 대비가 1.6:1 로 읽히지 않는다.
  /// 그래서 준비 배경만 **따뜻한 다크 차콜**로 두고, 옐로는 포인트 색으로만 쓴다.
  /// → 흰 글자 대비 15:1, 운동(코랄)·휴식(블루)과도 한눈에 구분된다.
  static const Color prepareBg = Color(0xFF1C1913);

  // ---------------------------------------------------------------
  // 글자
  // ---------------------------------------------------------------
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA8A9B2);
  static const Color textTertiary = Color(0xFF6E6F79);

  /// 옐로 배경 위 잉크색 (순수 검정보다 눈이 편한 웜 잉크)
  static const Color ink = Color(0xFF17130B);

  // ---------------------------------------------------------------
  // 상태별 헬퍼
  // ---------------------------------------------------------------

  /// 화면 전체를 채울 배경색
  static Color bgOf(String phaseType) => switch (phaseType) {
    'work' => workBg,
    'rest' => restBg,
    'setRest' => restBg,
    'prepare' => prepareBg,
    _ => prepareBg,
  };

  /// 배경 위에 올릴 기본 글자색
  ///
  /// 준비 화면도 **화이트**다 (요구사항). 준비 배경을 다크 차콜로 둔 이유가 이것이며,
  /// 옐로는 라벨·포인트에만 쓴다.
  static Color onBgOf(String phaseType) => const Color(0xFFFFFFFF);

  /// 다크 화면에서 쓰는 강조색
  static Color of(String phaseType) => switch (phaseType) {
    'work' => work,
    'rest' => rest,
    'setRest' => rest,
    'prepare' => prepare,
    _ => prepare,
  };

  /// 진행률 바 트랙 — 어떤 배경에서도 채움색과 구분되도록 배경을 살짝 어둡게 깐다.
  static Color trackOn(Color bg) =>
      Color.alphaBlend(Colors.black.withValues(alpha: 0.16), bg);

  /// 진행 화면의 카드(라운드/세트) 배경 — 배경을 살짝 어둡게 눌러 글자 대비를 올린다.
  static Color cardOn(Color bg) =>
      Color.alphaBlend(Colors.black.withValues(alpha: 0.14), bg);

  /// 다크 화면에서 상태색을 은은하게 깔아 쓰는 카드 배경
  static Color tinted(Color accent) =>
      Color.alphaBlend(accent.withValues(alpha: 0.14), surface);
}

class AppTheme {
  AppTheme._();

  /// 기본 서체 — Pretendard (라운드 고딕 계열).
  ///
  /// 한글과 숫자가 같은 서체로 그려져 스타일이 어긋나지 않는다.
  /// 숫자는 `tabularFigures` 를 함께 켜서 자리 폭이 변하지 않게 한다
  /// (타이머가 흔들리지 않는 이유).
  static const String fontFamily = 'Pretendard';

  static ThemeData get dark {
    // fontFamily 는 ThemeData 생성자 전용 인자라 copyWith 로는 못 넘긴다.
    // textTheme / primaryTextTheme 양쪽에 직접 적용해 모든 Text 에 반영한다.
    final base = ThemeData.dark(useMaterial3: true);
    final text = base.textTheme
        .apply(
          fontFamily: fontFamily,
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        )
        .copyWith(
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            fontFamily: fontFamily,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontFamily: fontFamily,
          ),
        );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.work,
        secondary: AppColors.rest,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      splashFactory: InkRipple.splashFactory,
      dividerColor: AppColors.divider,
      textTheme: text,
      primaryTextTheme: text,
      typography: Typography.material2021(
        platform: TargetPlatform.android,
        black: text,
        white: text,
      ),
    );
  }
}
