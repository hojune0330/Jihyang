import 'package:flutter/material.dart';

import '../models/tabata_config.dart';
import '../theme/app_theme.dart';

/// 화면 1 — 운동 시작 전 메인 화면
///
/// 한눈에: 운동 시간 / 휴식 시간 / 라운드 / 세트 / 세트 간 휴식 / 총 소요 시간
/// 진행 화면과 **같은 색 체계**를 쓴다 (운동=코랄, 휴식=블루, 준비=옐로).
class ReadyScreen extends StatelessWidget {
  const ReadyScreen({
    super.key,
    required this.config,
    required this.onStart,
    required this.onOpenSettings,
    required this.hasSavedSession,
    required this.onResumeSession,
  });

  final TabataConfig config;
  final VoidCallback onStart;
  final VoidCallback onOpenSettings;
  final bool hasSavedSession;
  final VoidCallback onResumeSession;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasSavedSession) _resumeBanner(),
                    _timeCards(),
                    const SizedBox(height: 12),
                    _progressCards(),
                    const SizedBox(height: 12),
                    _totalCard(),
                  ],
                ),
              ),
            ),
            _startArea(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
      child: Row(
        children: [
          const Text(
            '타바타 타이머',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onOpenSettings,
            iconSize: 25,
            tooltip: '설정',
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
      padding: const EdgeInsets.only(top: 8, bottom: 12),
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

  /// 운동 / 휴식 — 진행 화면과 동일한 색을 그대로 쓰는 독립 카드
  Widget _timeCards() {
    return Row(
      children: [
        Expanded(
          child: _TimeCard(
            label: '운동 시간',
            accent: AppColors.work,
            value: _hms(config.workSeconds),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: _TimeCard(
            label: '휴식 시간',
            accent: AppColors.rest,
            value: config.restSeconds == 0 ? '없음' : _hms(config.restSeconds),
          ),
        ),
      ],
    );
  }

  /// 라운드 / 세트 — 단순 텍스트가 아니라 구분된 영역
  Widget _progressCards() {
    final showSetRest = config.sets > 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _CountCard(
            label: '라운드',
            value: '${config.rounds}',
            unit: '회',
            accent: AppColors.prepare,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: _CountCard(
            label: '세트',
            value: '${config.sets}',
            unit: '세트',
            accent: AppColors.textPrimary,
          ),
        ),
        if (showSetRest) ...[
          const SizedBox(width: 11),
          Expanded(
            child: _CountCard(
              label: '세트 간 휴식',
              value: _compact(config.setRestSeconds),
              unit: '',
              accent: AppColors.rest,
              dense: true,
            ),
          ),
        ],
      ],
    );
  }

  Widget _totalCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text(
            '총 소요 시간',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            _longDuration(config.totalSeconds),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _startArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: SizedBox(
        height: 68,
        width: double.infinity,
        child: FilledButton(
          onPressed: onStart,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.work,
            foregroundColor: AppColors.ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow_rounded, size: 30, color: AppColors.ink),
              SizedBox(width: 5),
              Text(
                '운동 시작',
                style: TextStyle(
                  fontSize: 20,
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

  String _hms(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _compact(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0 && s > 0) return '$m분$s초';
    if (m > 0) return '$m분';
    return '$s초';
  }

  String _longDuration(int total) {
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h시간 ${m.toString().padLeft(2, '0')}분';
    }
    return '$m분 ${s.toString().padLeft(2, '0')}초';
  }
}

/// 운동/휴식 시간 카드 — 왼쪽에 상태 색 띠를 두어 진행 화면과 연결감을 준다.
class _TimeCard extends StatelessWidget {
  const _TimeCard({
    required this.label,
    required this.accent,
    required this.value,
  });

  final String label;
  final Color accent;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.tinted(accent),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.2),
      ),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 30,
                height: 1.0,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 라운드 / 세트 수 카드
class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.accent,
    this.dense = false,
  });

  final String label;
  final String value;
  final String unit;
  final Color accent;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
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
                    fontSize: dense ? 22 : 30,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit.isNotEmpty)
                  Text(
                    ' $unit',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
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
