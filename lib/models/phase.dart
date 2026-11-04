/// 타바타 구간(페이즈) 정의
enum PhaseType { prepare, work, rest, setRest }

class Phase {
  const Phase({
    required this.type,
    required this.duration,
    required this.setIndex,
    required this.roundIndex,
    required this.totalSets,
    required this.totalRounds,
  });

  /// 구간 종류
  final PhaseType type;

  /// 구간 길이(초)
  final int duration;

  /// 현재 세트 (1부터)
  final int setIndex;

  /// 세트 안의 현재 라운드 (1부터, 준비/세트휴식은 1)
  final int roundIndex;

  final int totalSets;

  /// 한 세트의 라운드 수
  final int totalRounds;

  bool get isWorkout => type == PhaseType.work;
  bool get isRest => type == PhaseType.rest || type == PhaseType.setRest;

  /// 마지막 5초 음성 카운트다운을 하는 구간.
  ///
  /// 준비·운동·휴식·세트 간 휴식 **모든 시간 구간**에서 동작한다.
  /// (5초보다 짧은 구간은 실제로 울릴 수 있는 숫자만 자동으로 남는다)
  bool get hasCountdown => duration > 0;

  String get title => switch (type) {
    PhaseType.prepare => '준비',
    PhaseType.work => '운동',
    PhaseType.rest => '휴식',
    PhaseType.setRest => '세트 휴식',
  };

  /// 화면에 크게 표시되는 이름
  String get bigTitle => switch (type) {
    PhaseType.prepare => '준비',
    PhaseType.work => '운동 중',
    PhaseType.rest => '휴식',
    PhaseType.setRest => '세트 휴식',
  };
}
