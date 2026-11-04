import 'package:flutter/material.dart';

import '../models/tabata_config.dart';
import '../theme/app_theme.dart';
import '../utils/fmt.dart';

/// 화면 1 — 운동 시작 전 메인 화면
///
/// 정보 위계
///  ① 운동 시간 / 휴식 시간 — 가장 큰 카드 (핵심)
///  ② 라운드 / 세트 / 세트 간 휴식 — 각각 독립된 카드
///  ③ 총 소요 시간 — 준비시간 포함, 실제 타이머와 동일한 계산
///  ④ 운동 기록 진입 / 설정 진입
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
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight - 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (hasSavedSession) _resumeBanner(),
                          _timeCards(),
                          const SizedBox(height: 10),
                          _countCards(),
                          const SizedBox(height: 10),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 10, 2),
      child: Row(
        children: [
          const Flexible(
            child: Text(
              '타바타 타이머',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
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
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onResumeSession,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.play_circle_outline,
                size: 19,
                color: AppColors.prepare,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  '진행 중이던 운동 이어서 하기',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 19,
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
            flex: 58,
            child: _BigTimeCard(
              label: '운동 시간',
              value: _mmss(config.workSeconds),
              hint: '한 라운드',
              accent: AppColors.work,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            flex: 42,
            child: _BigTimeCard(
              label: '휴식 시간',
              value: hasRest ? _mmss(config.restSeconds) : '없음',
              hint: hasRest ? '라운드 사이' : '휴식 없이 진행',
              accent: AppColors.rest,
              muted: !hasRest,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------- ② 라운드 / 세트 / 세트 간 휴식

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
          const SizedBox(width: 9),
          Expanded(
            child: _StatCard(
              label: '세트',
              value: '${config.sets}',
              unit: '세트',
              accent: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 9),
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
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '총 소요 시간',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '준비 ${TabataConfig.prepareSeconds}초 포함 · '
                    '총 ${config.totalRounds}라운드',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11.5,
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
                      fontSize: 23,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          // 운동 / 휴식 비중을 한 줄로 보여 준다
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
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
          const SizedBox(height: 9),
          Row(
            children: [
              _legend(
                AppColors.work,
                '운동 ${fmtKorean(config.pureWorkSeconds)}',
              ),
              const SizedBox(width: 14),
              _legend(
                AppColors.rest,
                '휴식 ${fmtKorean(config.totalSeconds - config.pureWorkSeconds)}',
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
        Text(
          text,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------- 시작 버튼

  Widget _startArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        height: 66,
        width: double.infinity,
        child: FilledButton(
          onPressed: onStart,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.work,
            foregroundColor: AppColors.ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow_rounded, size: 29, color: AppColors.ink),
              SizedBox(width: 5),
              Text(
                '운동 시작',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
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

  String _mmss(int seconds) => fmtClock(seconds);

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
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 15),
      decoration: BoxDecoration(
        color: muted
            ? AppColors.surface
            : AppColors.tinted(accent).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: muted ? AppColors.divider : accent.withValues(alpha: 0.45),
          width: 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: effective,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: effective,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: muted ? AppColors.textSecondary : AppColors.textPrimary,
                fontSize: 42,
                height: 1.0,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.6,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
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
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
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
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 6),
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
                    fontSize: compact ? 22 : 28,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit.isNotEmpty)
                  Text(
                    ' $unit',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
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
