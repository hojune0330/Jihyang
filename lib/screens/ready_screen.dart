import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/tabata_config.dart';
import '../theme/app_theme.dart';
import '../utils/fmt.dart';

/// 메인 화면 전용 밝은 유리(글래스) 팔레트.
/// 설정·진행·기록 화면은 기존 다크 팔레트(AppColors)를 그대로 쓴다.
class _Ui {
  _Ui._();

  static const bgBase = Color(0xFFF3F5FC);
  static const bgWarm = Color(0xFFFFF4EE);

  // 배경 오브 (카드 뒤에서 유리가 굴절시켜 보여 주는 색)
  static const orbCoral = Color(0xFFFF9B8A);
  static const orbSky = Color(0xFF8CC4FF);
  static const orbAmber = Color(0xFFFFD98A);
  static const orbMint = Color(0xFF9CE8CF);
  static const orbLilac = Color(0xFFC7B4FF);

  static const ink = Color(0xFF15161B);
  static const sub = Color(0xFF5B5F6E);
  static const tert = Color(0xFF8A8E9C);

  // 글자/라벨용 진한 상태색 (밝은 배경에서 대비 확보)
  static const work = Color(0xFFD65F57);
  static const rest = Color(0xFF3B6FC4);
  static const prep = Color(0xFFF2C94C);
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
      backgroundColor: _Ui.bgBase,
      body: Stack(
        children: [
          // 배경: 연한 그라데이션 + 색 오브 (유리 카드가 뒤를 흐리게 비추도록)
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_Ui.bgBase, _Ui.bgWarm],
                ),
              ),
            ),
          ),
          Positioned(
            left: -110,
            top: -60,
            child: _orb(330, _Ui.orbCoral, 0.70),
          ),
          Positioned(right: -150, top: 150, child: _orb(360, _Ui.orbSky, 0.65)),
          Positioned(left: -80, top: 430, child: _orb(260, _Ui.orbAmber, 0.60)),
          Positioned(
            right: -90,
            bottom: 40,
            child: _orb(300, _Ui.orbMint, 0.55),
          ),
          Positioned(
            left: 60,
            bottom: -120,
            child: _orb(260, _Ui.orbLilac, 0.50),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  _topBar(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (hasSavedSession) _resumeBanner(),
                          Expanded(flex: 5, child: _timeCards()),
                          const SizedBox(height: 12),
                          Expanded(flex: 3, child: _countCards()),
                          const SizedBox(height: 12),
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
        ],
      ),
    );
  }

  static Widget _orb(double size, Color color, double alpha) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * 0.45),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
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
                color: _Ui.ink,
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
                  Text(
                    todayCount > 0 ? '운동 기록 $todayCount' : '운동 기록',
                    style: const TextStyle(
                      color: _Ui.sub,
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
            icon: const Icon(Icons.settings_outlined, color: _Ui.ink),
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
        child: _Glass(
          radius: 14,
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

    return _Glass(
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
                        child: const ColoredBox(color: _Ui.work),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        flex: restFlex,
                        child: const ColoredBox(color: _Ui.rest),
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
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      child: SizedBox(
        height: 72,
        width: double.infinity,
        child: DecoratedBox(
          decoration: AppColors.glossyButton(AppColors.work),
          child: FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
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

/// 반투명 유리 카드.
/// 뒤 배경을 블러로 비추고, 위쪽 빛 + 얇은 흰 테두리 + 부드러운 그림자로 띄운다.
/// tint 가 있으면 상태색을 옅게 섞는다.
class _Glass extends StatelessWidget {
  const _Glass({
    required this.child,
    this.tint,
    this.radius = 18,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final Color? tint;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    final t = tint;
    // 면 색: 위쪽이 더 투명하고 아래로 갈수록 살짝 탁탁해진다
    final topFill = t == null
        ? Colors.white.withValues(alpha: 0.22)
        : Color.alphaBlend(
            t.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.22),
          );
    final bottomFill = t == null
        ? Colors.white.withValues(alpha: 0.46)
        : Color.alphaBlend(
            t.withValues(alpha: 0.26),
            Colors.white.withValues(alpha: 0.40),
          );
    final edge = t == null
        ? Colors.white.withValues(alpha: 0.85)
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.55),
            t.withValues(alpha: 0.70),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: [
          // 넓고 부드러운 바닥 그림자 (띄워 올린 느낌)
          BoxShadow(
            color: const Color(0xFF1A1D2E).withValues(alpha: 0.14),
            blurRadius: 28,
            spreadRadius: -6,
            offset: const Offset(0, 14),
          ),
          // 가까운 테두리 그림자 (경계 선을 또렴하게)
          BoxShadow(
            color: const Color(0xFF1A1D2E).withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.55, 1.0],
                colors: [topFill, topFill, bottomFill],
              ),
              borderRadius: br,
              border: Border.all(color: edge, width: 1.2),
            ),
            child: Stack(
              children: [
                // 상단 빛 반사(유리 하이라이트)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: br,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [
                            Colors.white.withValues(alpha: 0.55),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
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
    return _Glass(
      tint: muted ? null : tint,
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
    return _Glass(
      radius: 16,
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
                        color: accent == _Ui.prep ? _Ui.ink : accent,
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
