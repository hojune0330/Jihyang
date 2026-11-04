import '../models/tabata_config.dart';

/// 운동 세션 결과 구분
enum SessionOutcome {
  /// 끝까지 완료
  completed('완료'),

  /// 중도 종료
  aborted('중도 종료');

  const SessionOutcome(this.label);
  final String label;

  static SessionOutcome fromName(String? v) =>
      v == 'aborted' ? SessionOutcome.aborted : SessionOutcome.completed;
}

/// 운동 기록 1건.
///
/// 완료/중도 종료 모두 저장하며, 중도 종료는 진행률로 구분한다.
class WorkoutRecord {
  WorkoutRecord({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.workSeconds,
    required this.restSeconds,
    required this.rounds,
    required this.sets,
    required this.setRestSeconds,
    required this.plannedSeconds,
    required this.activeSeconds,
    required this.completedRounds,
    required this.completedSets,
    required this.totalRounds,
    required this.outcome,
    required this.progress,
  });

  /// 고유 id (시작 시각 ms 기반)
  final int id;

  /// 운동 시작 시각
  final DateTime startedAt;

  /// 운동 종료(또는 중단) 시각
  final DateTime endedAt;

  // ---- 당시 프로그램 설정 ----
  final int workSeconds;
  final int restSeconds;
  final int rounds;
  final int sets;
  final int setRestSeconds;

  /// 프로그램 총 예상 시간(초) — 준비 포함
  final int plannedSeconds;

  /// 실제로 타이머가 흐른 시간(초) — 일시정지 제외
  final int activeSeconds;

  /// 실제 완료한 라운드 수
  final int completedRounds;

  /// 실제 완료한 세트 수
  final int completedSets;

  /// 프로그램 전체 라운드 수
  final int totalRounds;

  final SessionOutcome outcome;

  /// 진행률 0.0 ~ 1.0
  final double progress;

  bool get isCompleted => outcome == SessionOutcome.completed;

  /// 기록에 남길 프로그램 설정
  TabataConfig get configSnapshot => TabataConfig(
    workSeconds: workSeconds,
    restSeconds: restSeconds,
    rounds: rounds,
    sets: sets,
    setRestSeconds: setRestSeconds,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'endedAt': endedAt.millisecondsSinceEpoch,
    'workSeconds': workSeconds,
    'restSeconds': restSeconds,
    'rounds': rounds,
    'sets': sets,
    'setRestSeconds': setRestSeconds,
    'plannedSeconds': plannedSeconds,
    'activeSeconds': activeSeconds,
    'completedRounds': completedRounds,
    'completedSets': completedSets,
    'totalRounds': totalRounds,
    'outcome': outcome.name,
    'progress': progress,
  };

  factory WorkoutRecord.fromJson(Map<String, dynamic> json) {
    int i(String k, int f) {
      final v = json[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return f;
    }

    double d(String k, double f) {
      final v = json[k];
      if (v is num) return v.toDouble();
      return f;
    }

    final startedMs = i('startedAt', DateTime.now().millisecondsSinceEpoch);
    final endedMs = i('endedAt', startedMs);

    return WorkoutRecord(
      id: i('id', startedMs),
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedMs),
      endedAt: DateTime.fromMillisecondsSinceEpoch(endedMs),
      workSeconds: i('workSeconds', 30),
      restSeconds: i('restSeconds', 15),
      rounds: i('rounds', 8),
      sets: i('sets', 1),
      setRestSeconds: i('setRestSeconds', 60),
      plannedSeconds: i('plannedSeconds', 0),
      activeSeconds: i('activeSeconds', 0),
      completedRounds: i('completedRounds', 0),
      completedSets: i('completedSets', 0),
      totalRounds: i('totalRounds', 0),
      outcome: SessionOutcome.fromName(json['outcome'] as String?),
      progress: d('progress', 0).clamp(0.0, 1.0),
    );
  }

  /// 오늘 기록인지
  bool get isToday {
    final now = DateTime.now();
    return startedAt.year == now.year &&
        startedAt.month == now.month &&
        startedAt.day == now.day;
  }

  /// 이번 주(월~일) 기록인지
  bool get isThisWeek {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    final start = startedAt;
    return !start.isBefore(monday) &&
        start.isBefore(monday.add(const Duration(days: 7)));
  }

  /// 날짜 키 (yyyy-MM-dd)
  String get dateKey =>
      '${startedAt.year.toString().padLeft(4, '0')}-'
      '${startedAt.month.toString().padLeft(2, '0')}-'
      '${startedAt.day.toString().padLeft(2, '0')}';
}
