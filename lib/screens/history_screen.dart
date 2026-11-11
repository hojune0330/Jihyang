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

    return GlassSegments(
      padding: const EdgeInsets.fromLTRB(16, 13, 10, 14),
      children: [
        _stat('운동한 날', '$days', '일'),
        _stat('완료', '$done', '회'),
        _stat('운동 시간', fmtKoreanShort(activeSec), ''),
      ],
    );
  }

  Widget _stat(String label, String value, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: GlassTokens.label.copyWith(fontSize: 12)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: value, style: GlassTokens.number(22)),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: GlassTokens.label.copyWith(fontSize: 12.5),
                  ),
              ],
            ),
          ),
        ),
      ],
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
                  style: GlassTokens.title,
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
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
      return const SizedBox(height: 56);
    }
    final date = DateTime(_month.year, _month.month, dayNum);
    final items = byDay[date];
    final ring = _ringFor(items);
    final isToday = date == DateTime(now.year, now.month, now.day);
    final isFuture = date.isAfter(DateTime(now.year, now.month, now.day));
    final selected = _selected == date;
    final done = items?.any((r) => r.isCompleted) ?? false;

    return GestureDetector(
      onTap: isFuture ? null : () => setState(() => _selected = date),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 42,
            height: 42,
            child: CustomPaint(
              painter: _RingPainter(
                progress: ring,
                done: done,
                selected: selected,
                showTrack: !isFuture,
              ),
              child: Center(
                child: Text(
                  '$dayNum',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.0,
                    fontWeight: isToday || selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontFeatures: GlassTokens.tabular,
                    color: isFuture
                        ? GlassTokens.tert.withValues(alpha: 0.55)
                        : isToday
                        ? GlassTokens.workText
                        : GlassTokens.ink,
                  ),
                ),
              ),
            ),
          ),
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
            style: GlassTokens.headline,
          ),
        ),
        if (items.isEmpty)
          const GlassSurface(
            material: GlassMaterial.thin,
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                r.isCompleted ? '운동 완료' : '중도 종료',
                style: GlassTokens.headline.copyWith(color: accent),
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
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: GlassTokens.ink,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(k, style: GlassTokens.label),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
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

/// 애플워치 활동 링 — 지난 날만 옅은 트랙, 기록이 있으면 진행 호.
/// 완료한 날은 링을 꽉 채우고, 선택한 날은 안쪽을 옅은 잉크로 채운다.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.done,
    required this.selected,
    required this.showTrack,
  });

  final double? progress;
  final bool done;
  final bool selected;
  final bool showTrack;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const stroke = 3.5;
    final radius = size.width / 2 - stroke / 2;

    if (selected) {
      canvas.drawCircle(
        center,
        radius - stroke,
        Paint()..color = GlassTokens.ink.withValues(alpha: 0.07),
      );
    }
    if (showTrack) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = GlassTokens.ink.withValues(alpha: 0.05),
      );
    }
    final p = progress;
    if (p != null) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -1.5708,
        6.28318 * p,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke
          ..color = done
              ? AppColors.work
              : AppColors.work.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.done != done ||
      old.selected != selected ||
      old.showTrack != showTrack;
}
