import 'package:flutter/material.dart';

import '../models/workout_record.dart';
import '../services/workout_store.dart';
import '../theme/app_theme.dart';
import '../theme/glass/glass.dart';
import '../utils/fmt.dart';

/// 운동 기록 화면 — 애플워치 활동 기록처럼 월별 달력으로 보여준다.
///
/// - 날짜 칸마다 그날의 운동을 링(원)으로 표시한다.
///   · 완료한 날: 꽉 찬 링 (색 강조)
///   · 중도 종료만 있는 날: 진행률만큼 채워진 링
/// - 월은 좌우 화살표로 넘긴다.
/// - 날짜를 누르면 아래에 그날 운동을 어떻게 했는지 보여준다.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<WorkoutRecord> _records = const [];
  bool _loading = true;

  late DateTime _month; // 보고 있는 달 (1일)
  DateTime? _selected; // 선택한 날짜 (자정)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _selected = DateTime(now.year, now.month, now.day);
    _load();
  }

  Future<void> _load() async {
    final list = await WorkoutStore.load(force: true);
    if (!mounted) return;
    setState(() {
      _records = list;
      _loading = false;
    });
  }

  // ------------------------------------------------------------ 집계

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 날짜(자정) → 그날 기록들
  Map<DateTime, List<WorkoutRecord>> get _byDay {
    final map = <DateTime, List<WorkoutRecord>>{};
    for (final r in _records) {
      map.putIfAbsent(_dayOf(r.startedAt), () => <WorkoutRecord>[]).add(r);
    }
    return map;
  }

  /// 달 안에서 그날의 링 진행률 (0~1). 기록이 없으면 null.
  double? _ringFor(List<WorkoutRecord>? items) {
    if (items == null || items.isEmpty) return null;
    if (items.any((r) => r.isCompleted)) return 1.0;
    final best = items.map((r) => r.progress).reduce((a, b) => a > b ? a : b);
    return best.clamp(0.08, 0.95);
  }

  // ------------------------------------------------------------ 빌드

  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: GlassTokens.ambientTop,
      extendBodyBehindAppBar: true,
      appBar: GlassNavBar(title: '운동 기록', scrolled: _scrolled),
      body: GlassBackdrop.ambient(
        preset: BackdropPreset.history,
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2.2))
            : NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  final v = n.metrics.pixels > 4;
                  if (v != _scrolled) setState(() => _scrolled = v);
                  return false;
                },
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    top + 72,
                    16,
                    32 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    _monthSummary(),
                    const SizedBox(height: 12),
                    _calendarCard(),
                    const SizedBox(height: 18),
                    _dayDetail(),
                  ],
                ),
              ),
      ),
    );
  }

  // ------------------------------------------------------------ 월 요약

  Widget _monthSummary() {
    final monthRecords = _records
        .where(
          (r) =>
              r.startedAt.year == _month.year &&
              r.startedAt.month == _month.month,
        )
        .toList();
    final done = monthRecords.where((r) => r.isCompleted).length;
    final activeSec = monthRecords.fold<int>(0, (a, r) => a + r.activeSeconds);
    final days = _byDay.keys
        .where((d) => d.year == _month.year && d.month == _month.month)
        .length;

    return Row(
      children: [
        _stat('운동한 날', '$days', '일'),
        const SizedBox(width: 10),
        _stat('완료', '$done', '회'),
        const SizedBox(width: 10),
        _stat('운동 시간', fmtKoreanShort(activeSec), ''),
      ],
    );
  }

  Widget _stat(String label, String value, String unit) {
    return Expanded(
      child: GlassSurface(
        radius: GlassTokens.rMd,
        padding: const EdgeInsets.fromLTRB(13, 12, 12, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: GlassTokens.tert,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: GlassTokens.ink,
                      ),
                    ),
                    if (unit.isNotEmpty)
                      TextSpan(
                        text: ' $unit',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: GlassTokens.sub,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 달력

  Widget _calendarCard() {
    final now = DateTime.now();
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;

    return GlassSurface(
      radius: GlassTokens.rLg,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        children: [
          Row(
            children: [
              GlassIconButton(
                tooltip: '이전 달',
                icon: Icons.chevron_left_rounded,
                size: 40,
                material: GlassMaterial.thick,
                shadow: false,
                onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month - 1, 1);
                }),
              ),
              Expanded(
                child: Text(
                  '${_month.year}년 ${_month.month}월',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: GlassTokens.ink,
                  ),
                ),
              ),
              GlassIconButton(
                tooltip: '다음 달',
                icon: Icons.chevron_right_rounded,
                size: 40,
                material: GlassMaterial.thick,
                shadow: false,
                onPressed: isCurrentMonth
                    ? null
                    : () => setState(() {
                        _month = DateTime(_month.year, _month.month + 1, 1);
                      }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final w in const ['일', '월', '화', '수', '목', '금', '토'])
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: w == '일'
                            ? GlassTokens.workText
                            : w == '토'
                            ? GlassTokens.restText
                            : GlassTokens.tert,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _grid(now),
        ],
      ),
    );
  }

  Widget _grid(DateTime now) {
    final first = DateTime(_month.year, _month.month, 1);
    final leading = first.weekday % 7; // 일요일 = 0
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final rows = ((leading + daysInMonth) / 7).ceil();
    final byDay = _byDay;

    return Column(
      children: [
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _cell(
                    row * 7 + col - leading + 1,
                    daysInMonth,
                    now,
                    byDay,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _cell(
    int dayNum,
    int daysInMonth,
    DateTime now,
    Map<DateTime, List<WorkoutRecord>> byDay,
  ) {
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 62);
    }
    final date = DateTime(_month.year, _month.month, dayNum);
    final items = byDay[date];
    final ring = _ringFor(items);
    final isToday = date == DateTime(now.year, now.month, now.day);
    final isFuture = date.isAfter(DateTime(now.year, now.month, now.day));
    final selected = _selected == date;
    final done = items?.any((r) => r.isCompleted) ?? false;

    return GestureDetector(
      onTap: () => setState(() => _selected = date),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: CustomPaint(
                painter: _RingPainter(
                  progress: ring,
                  done: done,
                  selected: selected,
                ),
                child: Center(
                  child: Text(
                    '$dayNum',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.0,
                      fontWeight: isToday || selected
                          ? FontWeight.w900
                          : FontWeight.w700,
                      color: isFuture
                          ? GlassTokens.tert.withValues(alpha: 0.5)
                          : (selected && ring != null && done)
                          ? Colors.white
                          : GlassTokens.ink,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 선택한 날 상세

  Widget _dayDetail() {
    final day = _selected;
    if (day == null) return const SizedBox.shrink();
    final items = (_byDay[day] ?? <WorkoutRecord>[])
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final wd = const ['월', '화', '수', '목', '금', '토', '일'][day.weekday - 1];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            '${day.month}월 ${day.day}일 ($wd)',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: GlassTokens.ink,
            ),
          ),
        ),
        if (items.isEmpty)
          const GlassSurface(
            material: GlassMaterial.thin,
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                Icon(
                  Icons.self_improvement_rounded,
                  size: 30,
                  color: GlassTokens.tert,
                ),
                SizedBox(height: 8, width: double.infinity),
                Text(
                  '이 날은 운동 기록이 없습니다',
                  style: TextStyle(
                    fontSize: 13,
                    color: GlassTokens.sub,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          )
        else
          for (final r in items) ...[
            _recordCard(r),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _recordCard(WorkoutRecord r) {
    final accent = r.isCompleted ? GlassTokens.workText : GlassTokens.sub;
    return GlassSurface(
      tint: r.isCompleted ? AppColors.work : null,
      tintStrength: 0.5,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                r.isCompleted ? '운동 완료' : '중도 종료',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
              const Spacer(),
              Text(
                '${_time(r.startedAt)} – ${_time(r.endedAt)}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: GlassTokens.tert,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _progressBar(r.progress),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _miniKv('운동', fmtClock(r.workSeconds))),
              Expanded(
                child: _miniKv(
                  '휴식',
                  r.restSeconds == 0 ? '없음' : fmtClock(r.restSeconds),
                ),
              ),
              Expanded(
                child: _miniKv('라운드', '${r.completedRounds}/${r.totalRounds}'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: GlassTokens.ink.withValues(alpha: 0.10)),
          const SizedBox(height: 10),
          _kv(
            '구성',
            '${r.rounds}회 × ${r.sets}세트'
                '${r.sets > 1 ? ' · 세트 간 휴식 ${r.setRestSeconds == 0 ? '없음' : fmtKoreanShort(r.setRestSeconds)}' : ''}',
          ),
          _kv('완료 세트', '${r.completedSets} / ${r.sets}'),
          _kv('실제 운동 시간', fmtClock(r.activeSeconds)),
          _kv('진행률', '${(r.progress * 100).round()}%'),
        ],
      ),
    );
  }

  Widget _progressBar(double progress) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        minHeight: 6,
        backgroundColor: GlassTokens.ink.withValues(alpha: 0.08),
        color: AppColors.work,
      ),
    );
  }

  Widget _miniKv(String k, String v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          k,
          style: const TextStyle(
            fontSize: 11,
            color: GlassTokens.tert,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          v,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: GlassTokens.ink,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            k,
            style: const TextStyle(fontSize: 12.5, color: GlassTokens.tert),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: GlassTokens.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 애플워치 활동 링 — 배경 트랙 + 진행 호. 완료한 날은 꽉 찬 링.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.done,
    required this.selected,
  });

  /// null 이면 기록 없음(트랙만), 0~1 이면 진행 호
  final double? progress;
  final bool done;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;
    const stroke = 4.0;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = GlassTokens.ink.withValues(alpha: 0.08);
    canvas.drawCircle(center, radius, track);

    final p = progress;
    if (p != null) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = AppColors.work;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -1.5708, // 12시 방향에서 시작
        6.28318 * p,
        false,
        arc,
      );
      if (done) {
        // 완료한 날은 안쪽을 옅게 채워 강조
        canvas.drawCircle(
          center,
          radius - stroke / 2 - 1,
          Paint()
            ..color = AppColors.work.withValues(alpha: selected ? 1.0 : 0.14),
        );
      }
    }

    if (selected) {
      canvas.drawCircle(
        center,
        radius + 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = GlassTokens.ink.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.done != done || old.selected != selected;
}
