import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass/glass.dart';

/// 화면 3 — 운동 완료 화면
///
/// 글래스 시스템 §2 'finished' 배경(코랄·옐로 오브를 크게) 위에
/// 완료 배지 → 총 운동 시간(가장 큰 유리 카드) → 세트/라운드 → 버튼 순.
class FinishedScreen extends StatelessWidget {
  const FinishedScreen({
    super.key,
    required this.sets,
    required this.totalSets,
    required this.rounds,
    required this.totalRounds,
    required this.elapsedMs,
    required this.onRestart,
    required this.onHome,
  });

  final int sets;
  final int totalSets;
  final int rounds;
  final int totalRounds;
  final int elapsedMs;
  final VoidCallback onRestart;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GlassTokens.ambientTop,
      body: GlassBackdrop.ambient(
        preset: BackdropPreset.finished,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              children: [
                const Spacer(flex: 2),
                // 완료 배지 — 코랄 유리 원 + 체크
                SizedBox(
                  width: 92,
                  height: 92,
                  child: GlassSurface(
                    radius: GlassTokens.rPill,
                    tint: AppColors.work,
                    tintStrength: 2.2,
                    child: const Center(
                      child: Icon(
                        Icons.check_rounded,
                        size: 52,
                        color: GlassTokens.workText,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '운동 완료',
                  style: TextStyle(
                    color: GlassTokens.ink,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 22),
                // 총 운동 시간 — 가장 큰 카드
                GlassSurface(
                  material: GlassMaterial.regular,
                  radius: GlassTokens.rLg,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        Text(
                          elapsedTime,
                          style: const TextStyle(
                            color: GlassTokens.ink,
                            fontSize: 52,
                            height: 1.0,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.6,
                            fontFeatures: GlassTokens.tabular,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '총 운동 시간',
                          style: TextStyle(
                            color: GlassTokens.sub,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: GlassTokens.s3),
                Row(
                  children: [
                    if (totalSets > 1)
                      Expanded(
                        child: _stat(
                          '완료 세트',
                          '$sets / $totalSets',
                          GlassTokens.restText,
                        ),
                      ),
                    if (totalSets > 1) const SizedBox(width: GlassTokens.s3),
                    Expanded(
                      child: _stat('완료 라운드', '$rounds', GlassTokens.prepText),
                    ),
                  ],
                ),
                const Spacer(flex: 3),
                GlassButton.filled(
                  label: '다시 시작',
                  icon: Icons.replay_rounded,
                  color: AppColors.work,
                  height: 70,
                  fontSize: 20,
                  onPressed: onRestart,
                ),
                const SizedBox(height: 12),
                GlassButton.glass(
                  label: '메인 화면으로',
                  height: 60,
                  fontSize: 17,
                  onPressed: onHome,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get elapsedTime {
    final total = (elapsedMs / 1000).round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _stat(String label, String value, Color color) {
    return GlassSurface(
      radius: GlassTokens.rMd,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                fontFeatures: GlassTokens.tabular,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: GlassTokens.sub,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
