import 'package:flutter/material.dart';

import '../models/tabata_config.dart';
import '../theme/app_theme.dart';
import '../utils/fmt.dart';

/// 화면 1 — 운동 시작 전 메인 화면
///
/// 정보 위계 (모두 '독립된 영역'으로 분리)
///  ① 운동 시간 / 휴식 시간 — 가장 큰 카드 (핵심)
///  ② 라운드 / 세트 — 큰 숫자 카드
///  ③ 세트 간 휴식 — 조건부 카드 (세트 1개면 안내 문구로 대체)
///  ④ 총 소요 시간 — 준비시간 포함, 실제 타이머와 동일한 계산
///  ⑤ 큰 시작 버튼
///
/// 각 영역은 카드로 분리되어 있고, 라벨 → 값 → 보조설명 순서로 크기가
/// 명확히 구분된다. 작은 글씨 나열은 하지 않는다.
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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight - 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (hasSavedSession) _resumeBanner(),
                          _timeCards(),
                          const SizedBox(height: 12),
                          _countCards(),
                          const SizedBox(height: 12),
                          _totalCard(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            _startArea(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 상단

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 6),
      child: Row(
        children: [
          const Flexible(
            child: Text(
              '타바타 타이머',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: onOpenHistory,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 17,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    todayCount > 0 ? '운동 기록 $todayCount' : '운동 기록',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onOpenSettings,
            iconSize: 24,
            tooltip: '설정',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumeBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onResumeSession,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.play_circle_outline,
                size: 20,
                color: AppColors.prepare,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '진행 중이던 운동 이어서 하기',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textTertiary,
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
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 55,
            child: _BigTimeCard(
              label: '운동 시간',
              value: fmtClock(config.workSeconds),
              hint: '한 라운드',
              accent: AppColors.work,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 45,
            child: _BigTimeCard(
              label: '휴식 시간',
              value: hasRest ? fmtClock(config.restSeconds) : '없음',
              hint: hasRest ? '라운드 사이' : '휴식 없이 진행',
              accent: AppColors.rest,
              muted: !hasRest,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------- ② 라운드 / 세트 / 세트 간 휴식

  Widget _countCards() {
    final showSetRest = config.sets > 1;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              label: '라운드',
              value: '${config.rounds}',
              unit: '회',
              accent: AppColors.prepare,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: '세트',
              value: '${config.sets}',
              unit: '세트',
              accent: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: '세트 간 휴식',
              value: showSetRest ? _compact(config.setRestSeconds) : '—',
              unit: '',
              accent: AppColors.rest,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------- ③ 총 소요 시간

  Widget _totalCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '총 소요 시간',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '준비 ${TabataConfig.prepareSeconds}초 포함',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    fmtKorean(config.totalSeconds),
                    maxLines: 1,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 운동 / 휴식 비중
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  Expanded(
                    flex:
                        (config.pureWorkSeconds *
                                1000 ~/
                                (config.totalSeconds == 0
                                    ? 1
                                    : config.totalSeconds))
                            .clamp(1, 1000),
                    child: const ColoredBox(color: AppColors.work),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex:
                        ((config.totalSeconds - config.pureWorkSeconds) *
                                1000 ~/
                                (config.totalSeconds == 0
                                    ? 1
                                    : config.totalSeconds))
                            .clamp(1, 1000),
                    child: const ColoredBox(color: AppColors.rest),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Flexible(
                child: _legend(
                  AppColors.work,
                  '운동 ${fmtKorean(config.pureWorkSeconds)} · '
                      '총 ${config.totalRounds}라운드',
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: _legend(
                  AppColors.rest,
                  '휴식 ${fmtKorean(config.totalSeconds - config.pureWorkSeconds)}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------- 시작 버튼

  Widget _startArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      child: SizedBox(
        height: 72,
        width: double.infinity,
        child: FilledButton(
          onPressed: onStart,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.work,
            foregroundColor: AppColors.ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
            elevation: 0,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow_rounded, size: 32, color: AppColors.ink),
              SizedBox(width: 6),
              Text(
                '운동 시작',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------- 포맷

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
    required this.accent,
    this.muted = false,
  });

  final String label;
  final String value;
  final String hint;
  final Color accent;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final effective = muted ? AppColors.textTertiary : accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: muted
            ? AppColors.surface
            : AppColors.tinted(accent).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: muted ? AppColors.divider : accent.withValues(alpha: 0.5),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: effective,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: effective,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: muted ? AppColors.textSecondary : AppColors.textPrimary,
                fontSize: 46,
                height: 1.0,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.8,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 라운드 / 세트 / 세트 간 휴식 — 각각 독립 카드.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.accent,
    this.compact = false,
  });

  final String label;
  final String value;
  final String unit;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 7),
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
                  style: TextStyle(
                    color: accent,
                    fontSize: compact ? 23 : 30,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit.isNotEmpty)
                  Text(
                    ' $unit',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
