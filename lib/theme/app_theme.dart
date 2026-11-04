import 'package:flutter/material.dart';

/// 타바타 앱 전역 디자인 토큰
class AppColors {
  AppColors._();

  // 배경 — 철저히 블랙
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF0E0E11);
  static const Color surfaceHigh = Color(0xFF16161B);
  static const Color stroke = Color(0xFF26262E);

  // 시 / 분 / 초 — 각각 다른 색으로 강조
  static const Color hours = Color(0xFF4FC3F7); // 시 : 시안 블루
  static const Color minutes = Color(0xFFFFB547); // 분 : 앰버
  static const Color seconds = Color(0xFFFF4D7D); // 초 : 핑크 레드

  // 구간 색
  static const Color work = Color(0xFF2EE6A8); // 운동 — 민트 그린
  static const Color rest = Color(0xFF4FC3F7); // 휴식 — 블루
  static const Color setRest = Color(0xFFB388FF); // 세트 휴식 — 퍼플
  static const Color prepare = Color(0xFFFFB547); // 준비 — 앰버

  static const Color textPrimary = Color(0xFFF7F7FA);
  static const Color textSecondary = Color(0xFF8E8E9A);

  static Color forPhase(String type) => switch (type) {
    'work' => work,
    'rest' => rest,
    'setRest' => setRest,
    _ => prepare,
  };
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.seconds,
        secondary: AppColors.work,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
    );
  }
}
