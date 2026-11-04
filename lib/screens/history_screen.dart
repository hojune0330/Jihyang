import 'package:flutter/material.dart';

import '../models/workout_record.dart';
import '../services/workout_store.dart';
import '../theme/app_theme.dart';
import '../utils/fmt.dart';

/// 운동 기록 화면
///
/// - 상단 요약: 주간 운동 횟수 / 누적 운동 횟수 / 누적 운동시간
/// - 오늘 기록 / 이전 날짜 기록을 날짜별로 묶어 표시
/// - 기록을 누르면 당시 프로그램 설정 + 실제 수행 결과를 상세 표시
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<WorkoutRecord> _records = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final today = WorkoutStore.today(_records);
    final week = WorkoutStore.thisWeek(_records);
    final groups = WorkoutStore.groupByDate(_records);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '운동 기록',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
                children: [
                  _summaryCard(today, week),
                  const SizedBox(height: 18),
                  if (_records.isEmpty)
                    _emptyState()
                  else
                    for (final g in groups) ...[
                      _dateHeader(g.key, g.value),
                      const SizedBox(height: 8),
                      for (final r in g.value) ...[
                        _recordTile(r),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 10),
                    ],
                ],
              ),
      ),
    );
  }

  // -------------------------------------------------------- 요약

  Widget _summaryCard(List<WorkoutRecord> today, List<WorkoutRecord> week) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '이번 주',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${week.length}',
                style: const TextStyle(
                  color: AppColors.work,
                  fontSize: 40,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.4,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 5, left: 3),
                child: Text(
                  '회 운동',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '오늘 ${today.length}회',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '주간 운동시간 ${fmtAccumulated(
                      WorkoutStore.totalActiveSeconds(week),
                    )}',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  '누적 운동 횟수',
                  '${WorkoutStore.totalCount(_records)}회',
                  '완료 ${WorkoutStore.completedCount(_records)}회',
                ),
              ),
              Container(width: 1, height: 34, color: AppColors.divider),
              const SizedBox(width: 14),
              Expanded(
                child: _miniStat(
                  '누적 운동시간',
                  fmtAccumulated(
                    WorkoutStore.totalActiveSeconds(_records),
                  ),
                  '실제 진행 시간',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            height: 1.0,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          sub,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------- 날짜 헤더

  Widget _dateHeader(String dateKey, List<WorkoutRecord> items) {
    final first = items.first.startedAt;
    final isToday = items.first.isToday;
    final weekday = const ['월', '화', '수', '목', '금', '토', '일'][
        first.weekday - 1];
    final title = isToday
        ? '오늘'
        : '${first.month}월 ${first.day}일 ($weekday)';
    final totalSec = WorkoutStore.totalActiveSeconds(items);

    return Padding(
      padding: const EdgeInsets.only(left: 3, bottom: 2),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: isToday ? AppColors.prepare : AppColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '${items.length}회',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            fmtAccumulated(totalSec),
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------- 기록 1건

  Widget _recordTile(WorkoutRecord r) {
    final done = r.isCompleted;
    final accent = done ? AppColors.work : AppColors.textSecondary;
    final t = r.startedAt;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');

    return InkWell(
      onTap: () => _openDetail(r),
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: done
                ? AppColors.work.withValues(alpha: 0.28)
                : AppColors.divider,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // 진행률 링
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      value: r.progress.clamp(0.0, 1.0),
                      strokeWidth: 3,
                      backgroundColor: AppColors.divider,
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                  Text(
                    '${(r.progress * 100).round()}',
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '$hh:$mm',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: done
                              ? AppColors.work.withValues(alpha: 0.16)
                              : AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          r.outcome.label,
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '운동 ${fmtKoreanShort(r.workSeconds)} · '
                    '휴식 ${fmtKoreanShort(r.restSeconds)} · '
                    '${r.rounds}회 × ${r.sets}세트',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  fmtClock(r.activeSeconds),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${r.completedRounds}/${r.totalRounds} 라운드',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.chevron_right_rounded,
              size: 17,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(WorkoutRecord r) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    r.isCompleted ? '운동 완료' : '중도 종료',
                    style: TextStyle(
                      color: r.isCompleted
                          ? AppColors.work
                          : AppColors.textSecondary,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '진행률 ${(r.progress * 100).round()}%',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _fullDate(r.startedAt),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 14),
              const _Label('당시 프로그램 설정'),
              const SizedBox(height: 7),
              _kv('운동 시간', fmtKoreanShort(r.workSeconds)),
              _kv('휴식 시간', fmtKoreanShort(r.restSeconds)),
              _kv('총 라운드', '${r.rounds}회 × ${r.sets}세트 '
                  '= ${r.totalRounds}라운드'),
              _kv(
                '세트 간 휴식',
                r.sets > 1 ? fmtKoreanShort(r.setRestSeconds) : '사용 안 함',
              ),
              _kv('예상 소요 시간', fmtKorean(r.plannedSeconds)),
              const SizedBox(height: 14),
              const _Label('실제 수행 결과'),
              const SizedBox(height: 7),
              _kv('완료 라운드', '${r.completedRounds} / ${r.totalRounds}'),
              _kv('완료 세트', '${r.completedSets} / ${r.sets}'),
              _kv('진행률', '${(r.progress * 100).round()}%'),
              _kv('실제 운동 시간', fmtClock(r.activeSeconds)),
              _kv('시작 시각', _time(r.startedAt)),
              _kv('종료 시각', _time(r.endedAt)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Text(
            k,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12.5,
            ),
          ),
          const Spacer(),
          Text(
            v,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(
            Icons.fitness_center_rounded,
            size: 44,
            color: AppColors.textTertiary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          const Text(
            '아직 운동 기록이 없습니다',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            '운동을 완료하거나 중간에 종료해도 기록이 저장됩니다.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  String _fullDate(DateTime d) {
    final wd = const ['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1];
    return '${d.year}년 ${d.month}월 ${d.day}일 ($wd) ${_time(d)}';
  }

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textTertiary,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
      ),
    );
  }
}
