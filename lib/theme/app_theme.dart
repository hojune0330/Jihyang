import 'package:flutter/material.dart';

/// 타바타 앱 전역 디자인 토큰
class AppColors {
  AppColors._();

  // 배경 — 순수 블랙
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF121214);
  static const Color surfaceHigh = Color(0xFF1C1C20);
  static const Color stroke = Color(0xFF2C2C31);

  // 구간 색 — 진하게
  static const Color work = Color(0xFFFF1744); // 운동 : 비비드 레드
  static const Color rest = Color(0xFF2979FF); // 휴식 : 비비드 블루
  static const Color prepare = Color(0xFFFFB300); // 준비 : 앰버

  // 시간 단위 색 — 구간 색 계열 안에서 서로 뚜렷이 구분되는 진한 색
  static const Color hourColor = Color(0xFF00E5FF); // 시

  // 운동(빨강 계열) 안에서 '분'과 '초'를 확실히 다르게
  static const Color workMinute = Color(0xFFFF9100); // 운동 중 '분' : 비비드 오렌지
  static const Color workSecond = Color(0xFFFF0059); // 운동 중 '초' : 비비드 크림슨
  // 휴식(파랑 계열) 안에서 '분'과 '초'를 확실히 다르게
  static const Color restMinute = Color(0xFF00E5FF); // 휴식 중 '분' : 비비드 시안
  static const Color restSecond = Color(0xFF2B5BFF); // 휴식 중 '초' : 비비드 블루
  static const Color setRestMinutesColor = Color(0xFFB388FF); // 세트 휴식
  static const Color prepareMinute = Color(0xFFFFC400); // 준비 중 '분'
  static const Color prepareSecond = Color(0xFFFF8F00); // 준비 중 '초'

  static const Color textPrimary = Color(0xFFF7F7FA);
  static const Color textSecondary = Color(0xFF9A9AA6);

  static Color forPhase(String type) => switch (type) {
    'work' => work,
    'rest' => rest,
    'setRest' => rest,
    _ => prepare,
  };

  static Color minuteFor(String type) => switch (type) {
    'work' => workMinute,
    'rest' => restMinute,
    'setRest' => restMinute,
    _ => prepareMinute,
  };

  static Color secondFor(String type) => switch (type) {
    'work' => workSecond,
    'rest' => restSecond,
    'setRest' => restSecond,
    _ => prepareSecond,
  };
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.work,
        secondary: AppColors.rest,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
    );
  }
}
