import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass/glass.dart';

/// 화면 3 — 운동 완료 화면
///
/// 주인공은 기록 화면과 같은 '활동 링'이다. 완료 라운드 비율만큼 채워지고
/// 가운데에 완료 라운드 수를 둔다. (v1 의 체크 아이콘 배지는 범용 성공
/// 일러스트라 제거 — v1.1 R1-12)
class FinishedScreen extends StatefulWidget {
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
  State<FinishedScreen> createState() => _FinishedScreenState();
}

class _FinishedScreenState extends State<FinishedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  double get _ratio => widget.totalRounds <= 0
      ? 1
      : (widget.rounds / widget.totalRounds).clamp(0.0, 1.0);

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
                const Spacer(flex: 3),
                const Text('운동 완료', style: GlassTokens.largeTitle),
                const SizedBox(height: 6),
                Text(
                  _ratio >= 1 ? '모든 라운드를 마쳤어요' : '수고했어요',
                  style: GlassTokens.label.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 200,
                  height: 200,
                  child: AnimatedBuilder(
                    animation: _ring,
                    builder: (_, _) => CustomPaint(
                      painter: _ActivityRing(
                        Curves.easeOutCubic.transform(_ring.value) * _ratio,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${widget.rounds}',
                              style: GlassTokens.number(56),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '/ ${widget.totalRounds} 라운드',
                              style: GlassTokens.label,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                GlassSegments(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 15),
                  children: [
                    _stat('총 운동 시간', elapsedTime),
                    if (widget.totalSets > 1)
                      _stat('완료 세트', '${widget.sets} / ${widget.totalSets}'),
                  ],
                ),
                const Spacer(flex: 4),
                GlassButton.filled(
                  label: '다시 시작',
                  color: AppColors.work,
                  height: 58,
                  fontSize: 17,
                  radius: GlassTokens.rLg,
                  onPressed: widget.onRestart,
                ),
                const SizedBox(height: 10),
                GlassButton.glass(
                  label: '메인 화면으로',
                  height: 54,
                  fontSize: 16,
                  radius: GlassTokens.rLg,
                  onPressed: widget.onHome,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get elapsedTime {
    final total = (widget.elapsedMs / 1000).round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: GlassTokens.label.copyWith(fontSize: 12)),
        const SizedBox(height: 6),
        Text(value, style: GlassTokens.number(24)),
      ],
    );
  }
}

/// 활동 링 — 옅은 트랙 위에 코랄 호. 끝은 둥글게.
class _ActivityRing extends CustomPainter {
  _ActivityRing(this.p);

  final double p;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - stroke / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.work.withValues(alpha: 0.14),
    );
    if (p <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * p,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = AppColors.work,
    );
  }

  @override
  bool shouldRepaint(covariant _ActivityRing old) => old.p != p;
}
