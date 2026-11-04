import 'package:flutter/material.dart';

/// 무광 단색 디자인 토큰.
/// 그라데이션 / 네온 / 발광 / 과한 그림자를 사용하지 않는다.
class AppColors {
  AppColors._();

  /// 짙은 차콜 배경
  static const Color background = Color(0xFF0B0B0D);
  static const Color surface = Color(0xFF17171A);
  static const Color surfaceHigh = Color(0xFF222227);
  static const Color divider = Color(0xFF2E2E34);

  /// 운동 : 진하고 선명한 빨강
  static const Color work = Color(0xFFFF2D2D);

  /// 휴식 : 진하고 선명한 파랑
  static const Color rest = Color(0xFF1F6FFF);

  /// 준비 / 카운트다운 : 선명한 노랑
  static const Color prepare = Color(0xFFFFD60A);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9A9AA2);
  static const Color textTertiary = Color(0xFF5E5E66);

  static Color of(String phaseType) => switch (phaseType) {
    'work' => work,
    'rest' => rest,
    'setRest' => rest,
    'prepare' => prepare,
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
        primary: AppColors.work,
        secondary: AppColors.rest,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      splashFactory: InkRipple.splashFactory,
      dividerColor: AppColors.divider,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
    );
  }
}
