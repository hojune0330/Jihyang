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
  static const Color background = Color(0xFFF2F3F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceHigh = Color(0xFFE9EAF0);
  static const Color divider = Color(0xFFD9DBE3);

  // ---------------------------------------------------------------
  // 상태 색 — 앱 전체 공통 (부드러운 저채도)
  // ---------------------------------------------------------------
  /// 운동 : 소프트 코랄
  static const Color work = Color(0xFFE77D75);

  /// 휴식 : 소프트 블루
  static const Color rest = Color(0xFF648BD2);

  /// 준비 / 카운트다운 : 소프트 옐로
  static const Color prepare = Color(0xFFFFE27A);

  // 진행 화면 전체 배경도 동일한 값을 그대로 사용한다.
  static const Color workBg = work;
  static const Color restBg = rest;

  /// 준비 화면 배경 — 기존 소프트 옐로 그대로.
  static const Color prepareBg = prepare;

  // ---------------------------------------------------------------
  // 글자
  // ---------------------------------------------------------------
  static const Color textPrimary = Color(0xFF15161B);
  static const Color textSecondary = Color(0xFF5B5F6E);
  static const Color textTertiary = Color(0xFF8A8E9C);

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

  /// 배경 위에 올릴 기본 글자색 — 모든 구간 화이트.
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

  /// 입체 카드 데코레이션.
  ///
  /// - 위에서 아래로 살짝 어두워지는 그라데이션 (표면이 빛을 받는 느낌)
  /// - 위쪽 가장자리의 얇은 하이라이트 테두리
  /// - 아래로 떨어지는 부드러운 그림자 (띄워진 느낌)
  /// accent 가 있으면 테두리를 상태색으로 은은하게 물들인다.
  static BoxDecoration raised({
    required Color base,
    double radius = 18,
    Color? accent,
    bool muted = false,
  }) {
    // 반투명 유리 면: 배경색이 비치도록 알파를 낮추고, 위쪽에만 빛이 살짝 모인다.
    final glass = base.withValues(alpha: muted ? 0.55 : 0.42);
    final sheen = Colors.white.withValues(alpha: 0.10);
    final border = (accent != null && !muted)
        ? accent.withValues(alpha: 0.42)
        : Colors.white.withValues(alpha: 0.12);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.alphaBlend(sheen, glass), glass],
        stops: const [0.0, 0.6],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border, width: 1.0),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.30),
          blurRadius: 20,
          spreadRadius: -6,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  /// 시작 버튼 — 상태색 위에 위에서 아래로 빛이 떨어지는 그라데이션과 같은 색 계열 그림자.
  static BoxDecoration glossyButton(Color color, {double radius = 17}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.alphaBlend(
            Colors.white.withValues(alpha: 0.22),
            color.withValues(alpha: 0.88),
          ),
          color.withValues(alpha: 0.88),
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.35),
          blurRadius: 16,
          spreadRadius: -2,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }

  /// 옅은 배경(준비 옐로 등) 위 흰 글자가 떠 보이지 않도록 주는 최소한의 그림자.
  ///
  /// 장식이 아니라 가독성 보정이다 — 흰 글자가 배경과 경계를 잃는 것을 막는다.
  static List<Shadow>? shadowOn(String phaseType) {
    if (phaseType != 'prepare') return null;
    return const [
      Shadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 1.5)),
    ];
  }
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
    final base = ThemeData.light(useMaterial3: true);
    final text = base.textTheme
        .apply(
          fontFamily: fontFamily,
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        )
        .copyWith(
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontFamily: fontFamily),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontFamily: fontFamily,
          ),
        );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.work,
        secondary: AppColors.rest,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      // 글래스 시스템 §5: 물결(ripple) 대신 눌림 축소 + 스프링 복귀를 쓴다.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.work,
        selectionHandleColor: AppColors.work,
      ),
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
