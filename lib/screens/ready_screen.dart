import 'package:flutter/material.dart';

import '../models/tabata_config.dart';
import '../theme/app_theme.dart';
import '../theme/glass/glass.dart';
import '../utils/fmt.dart';

/// 메인 화면 글자색 — 글래스 토큰(§4-4) 별칭.
class _Ui {
  _Ui._();

  static const ink = GlassTokens.ink;
  static const sub = GlassTokens.sub;
  static const tert = GlassTokens.tert;

  // 흰 유리 위 글자/점용 진한 상태색 (대비 4.5:1)
  static const work = GlassTokens.workText;
  static const rest = GlassTokens.restText;
  static const prep = GlassTokens.prepText;
}

/// 화면 1 — 운동 시작 전 메인 화면
///
/// 정보 위계 (모두 '독립된 영역'으로 분리)
///  ① 운동 시간 / 휴식 시간 — 가장 큰 카드 (핵심)
///  ② 라운드 / 세트 / 세트 간 휴식
///  ③ 총 소요 시간 — 준비시간 포함, 실제 타이머와 동일한 계산
///  ④ 큰 시작 버튼
///
/// 카드들은 남는 세로 공간을 비율로 나눠 가져 화면을 빈틈없이 채운다.
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
                    6,
                    GlassTokens.screenX,
                    6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasSavedSession) _resumeBanner(),
                      Expanded(flex: 5, child: _timeCards()),
                      const SizedBox(height: GlassTokens.s3),
                      Expanded(flex: 3, child: _countCards()),
                      const SizedBox(height: GlassTokens.s3),
                      Expanded(flex: 3, child: _totalCard()),
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
      padding: const EdgeInsets.fromLTRB(22, 10, 16, 6),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '타바타 타이머',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _Ui.ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
          ),
          GlassChip(
            label: todayCount > 0 ? '운동 기록 $todayCount' : '운동 기록',
            icon: Icons.calendar_month_rounded,
            color: _Ui.sub,
            dense: true,
            onTap: onOpenHistory,
          ),
          const SizedBox(width: GlassTokens.s2),
          GlassIconButton(
            icon: Icons.settings_rounded,
            tooltip: '설정',
            size: 42,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }

  Widget _resumeBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPressable(
        onTap: onResumeSession,
        semanticLabel: '진행 중이던 운동 이어서 하기',
        child: GlassSurface(
          radius: GlassTokens.rSm,
          tint: AppColors.prepare,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: const Row(
            children: [
              Icon(Icons.play_circle_outline, size: 20, color: _Ui.prep),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '진행 중이던 운동 이어서 하기',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _Ui.ink,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: _Ui.tert),
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
          flex: 55,
          child: _BigTimeCard(
            label: '운동 시간',
            value: fmtClock(config.workSeconds),
            hint: '한 라운드',
            accent: _Ui.work,
            tint: AppColors.work,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 45,
          child: _BigTimeCard(
            label: '휴식 시간',
            value: hasRest ? fmtClock(config.restSeconds) : '없음',
            hint: hasRest ? '라운드 사이' : '휴식 없이 진행',
            accent: _Ui.rest,
            tint: AppColors.rest,
            muted: !hasRest,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------- ② 라운드 / 세트 / 세트 간 휴식

  Widget _countCards() {
    final showSetRest = config.sets > 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _StatCard(
            label: '라운드',
            value: '${config.rounds}',
            unit: '회',
            accent: _Ui.prep,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: '세트',
            value: '${config.sets}',
            unit: '세트',
            accent: _Ui.ink,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: '세트 간 휴식',
            value: showSetRest ? _compact(config.setRestSeconds) : '—',
            unit: '',
            accent: _Ui.rest,
            compact: true,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------- ③ 총 소요 시간

  Widget _totalCard() {
    final total = config.totalSeconds == 0 ? 1 : config.totalSeconds;
    final workFlex = (config.pureWorkSeconds * 1000 ~/ total).clamp(1, 1000);
    final restFlex =
        ((config.totalSeconds - config.pureWorkSeconds) * 1000 ~/ total).clamp(
          1,
          1000,
        );

    return GlassSurface(
      radius: GlassTokens.rLg,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '총 소요 시간',
                    style: TextStyle(
                      color: _Ui.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '준비 ${TabataConfig.prepareSeconds}초 포함',
                    style: TextStyle(
                      color: _Ui.tert,
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
                      color: _Ui.ink,
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
          Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      Expanded(
                        flex: workFlex,
                        child: const ColoredBox(color: AppColors.work),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        flex: restFlex,
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
                      _Ui.work,
                      '운동 ${fmtKorean(config.pureWorkSeconds)} · '
                      '총 ${config.totalRounds}라운드',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: _legend(
                      _Ui.rest,
                      '휴식 ${fmtKorean(config.totalSeconds - config.pureWorkSeconds)}',
                    ),
                  ),
                ],
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
              color: _Ui.sub,
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
      padding: const EdgeInsets.fromLTRB(
        GlassTokens.screenX,
        10,
        GlassTokens.screenX,
        18,
      ),
      child: GlassButton.filled(
        label: '운동 시작',
        icon: Icons.play_arrow_rounded,
        color: AppColors.work,
        height: 72,
        fontSize: 21,
        onPressed: onStart,
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

/// 운동/휴식 시간 카드 — 화면에서 가장 큰 카드. 남는 높이를 값이 채운다.
class _BigTimeCard extends StatelessWidget {
  const _BigTimeCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.accent,
    required this.tint,
    this.muted = false,
  });

  final String label;
  final String value;
  final String hint;
  final Color accent;
  final Color tint;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final effective = muted ? _Ui.tert : accent;
    return GlassSurface(
      tint: muted ? null : tint,
      radius: GlassTokens.rLg,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
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
          Expanded(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: muted ? _Ui.sub : _Ui.ink,
                    fontSize: 46,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.8,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _Ui.sub,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 라운드 / 세트 / 세트 간 휴식 — 각각 독립 유리 카드.
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
    return GlassSurface(
      radius: GlassTokens.rMd,
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _Ui.sub,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: FittedBox(
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
                          color: _Ui.sub,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
