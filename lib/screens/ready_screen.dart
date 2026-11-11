import 'package:flutter/material.dart';

import '../models/tabata_config.dart';
import '../theme/app_theme.dart';
import '../theme/glass/glass.dart';
import '../utils/fmt.dart';

/// 화면 1 — 운동 시작 전 메인 화면
///
/// 정보 위계 (유지)
///  ① 운동 시간 / 휴식 시간 — 가장 큰 카드 (핵심)
///  ② 라운드 / 세트 / 세트 간 휴식 — 한 장의 묶음 카드, 세 칸
///  ③ 총 소요 시간 — 실제 진행 순서를 그대로 그린 타임라인
///  ④ 시작 버튼
///
/// v1.1: 색은 운동·휴식 '라벨'에만 쓴다. 값은 모두 잉크 1색 (위계 정리).
class ReadyScreen extends StatelessWidget {
  const ReadyScreen({
    super.key,
    required this.config,
    required this.onStart,
    required this.onOpenSettings,
    required this.onOpenHistory,
    required this.hasSavedSession,
    required this.onResumeSession,
    this.todayCount = 0,
  });

  final TabataConfig config;
  final VoidCallback onStart;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenHistory;
  final bool hasSavedSession;
  final VoidCallback onResumeSession;
  final int todayCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GlassTokens.ambientTop,
      body: GlassBackdrop.ambient(
        preset: BackdropPreset.home,
        child: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GlassTokens.screenX,
                    4,
                    GlassTokens.screenX,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasSavedSession) _resumeBanner(),
                      Expanded(child: _timeCards()),
                      const SizedBox(height: GlassTokens.s3),
                      _countCard(),
                      const SizedBox(height: GlassTokens.s3),
                      _totalCard(),
                    ],
                  ),
                ),
              ),
              _startArea(),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 상단

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 16, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '타바타 타이머',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GlassTokens.largeTitle,
              // 앱 이름은 그대로, 크기만 iOS 큰 제목 위계로
            ),
          ),
          GlassChip(
            label: todayCount > 0 ? '운동 기록 · 오늘 $todayCount' : '운동 기록',
            color: GlassTokens.ink,
            onTap: onOpenHistory,
          ),
          const SizedBox(width: GlassTokens.s2),
          GlassIconButton(
            icon: Icons.tune_rounded,
            tooltip: '설정',
            size: 40,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }

  Widget _resumeBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.s3),
      child: GlassPressable(
        onTap: onResumeSession,
        semanticLabel: '진행 중이던 운동 이어서 하기',
        child: GlassSurface(
          radius: GlassTokens.rSm,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: const Row(
            children: [
              Expanded(
                child: Text('진행 중이던 운동 이어서 하기', style: GlassTokens.headline),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: GlassTokens.tert,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------- ① 운동 / 휴식 (핵심)

  Widget _timeCards() {
    final hasRest = config.restSeconds > 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _BigTimeCard(
            label: '운동 시간',
            value: fmtClock(config.workSeconds),
            hint: '한 라운드',
            labelColor: GlassTokens.workText,
            tint: AppColors.work,
          ),
        ),
        const SizedBox(width: GlassTokens.s3),
        Expanded(
          child: _BigTimeCard(
            label: '휴식 시간',
            value: hasRest ? fmtClock(config.restSeconds) : '없음',
            hint: hasRest ? '라운드 사이' : '휴식 없이 진행',
            labelColor: hasRest ? GlassTokens.restText : GlassTokens.tert,
            tint: hasRest ? AppColors.rest : null,
            muted: !hasRest,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------- ② 라운드 / 세트 / 세트 간 휴식

  Widget _countCard() {
    final showSetRest = config.sets > 1;
    return GlassSegments(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 15),
      children: [
        _Stat(label: '라운드', value: '${config.rounds}', unit: '회'),
        _Stat(label: '세트', value: '${config.sets}', unit: ''),
        _Stat(
          label: '세트 간 휴식',
          value: showSetRest ? _compact(config.setRestSeconds) : '—',
          unit: '',
          dim: !showSetRest,
        ),
      ],
    );
  }

  // -------------------------------------------------- ③ 총 소요 시간

  Widget _totalCard() {
    return GlassSurface(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(child: Text('총 소요 시간', style: GlassTokens.label)),
              Text(
                fmtKorean(config.totalSeconds),
                maxLines: 1,
                style: GlassTokens.number(24),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(height: 22, child: _Timeline(config: config)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '준비 ${TabataConfig.prepareSeconds}초 · '
                  '운동 ${fmtKoreanShort(config.pureWorkSeconds)} · '
                  '총 ${config.totalRounds}라운드',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GlassTokens.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------- 시작 버튼

  Widget _startArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GlassTokens.screenX,
        14,
        GlassTokens.screenX,
        16,
      ),
      child: GlassButton.filled(
        label: '운동 시작',
        color: AppColors.work,
        height: 60,
        fontSize: 18,
        radius: GlassTokens.rLg,
        onPressed: onStart,
      ),
    );
  }

  String _compact(int seconds) {
    if (seconds <= 0) return '없음';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0 && s > 0) return '$m분$s초';
    if (m > 0) return '$m분';
    return '$s초';
  }
}

/// 운동/휴식 시간 카드 — 화면에서 가장 큰 카드.
class _BigTimeCard extends StatelessWidget {
  const _BigTimeCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.labelColor,
    required this.tint,
    this.muted = false,
  });

  final String label;
  final String value;
  final String hint;
  final Color labelColor;
  final Color? tint;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tint: tint,
      radius: GlassTokens.rLg,
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GlassTokens.headline.copyWith(color: labelColor)),
          const SizedBox(height: 2),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GlassTokens.caption,
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: GlassTokens.number(
                52,
                color: muted ? GlassTokens.tert : GlassTokens.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 묶음 카드의 한 칸
class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.unit,
    this.dim = false,
  });

  final String label;
  final String value;
  final String unit;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GlassTokens.label.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                maxLines: 1,
                style: GlassTokens.number(
                  26,
                  color: dim ? GlassTokens.tert : GlassTokens.ink,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(unit, style: GlassTokens.label.copyWith(fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 진행 순서 타임라인 — 준비 → (운동·휴식 × 라운드) → 세트 휴식 → …
///
/// 길이는 실제 초에 비례한다. 라운드가 많아 칸이 좁아지면 운동/휴식 막대를
/// 블록으로 합쳐 그린다 (최소 폭 2px).
class _Timeline extends StatelessWidget {
  const _Timeline({required this.config});

  final TabataConfig config;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _TimelinePainter(config), size: Size.infinite);
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.c);

  final TabataConfig c;

  @override
  void paint(Canvas canvas, Size size) {
    final segs = <(int, Color)>[
      (TabataConfig.prepareSeconds, AppColors.prepare),
    ];
    for (var s = 0; s < c.sets; s++) {
      for (var r = 0; r < c.rounds; r++) {
        segs.add((c.workSeconds, AppColors.work));
        if (r < c.rounds - 1 && c.restSeconds > 0) {
          segs.add((c.restSeconds, AppColors.rest));
        }
      }
      if (s < c.sets - 1 && c.setRestSeconds > 0) {
        segs.add((c.setRestSeconds, GlassTokens.restText));
      }
    }
    final total = segs.fold<int>(0, (a, e) => a + e.$1);
    if (total == 0) return;

    const gap = 1.5;
    final usable = size.width - gap * (segs.length - 1);
    // 막대가 너무 많아 간격이 다 먹으면 간격 없이 그린다.
    final g = usable > size.width * 0.6 ? gap : 0.0;
    final w = size.width - g * (segs.length - 1);

    var x = 0.0;
    final h = size.height;
    for (final (sec, color) in segs) {
      final sw = (sec / total) * w;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 0, sw.clamp(1.0, double.infinity), h),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = color);
      x += sw + g;
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) => old.c != c;
}
