/// 타바타 구간(페이즈) 정의
enum PhaseType { prepare, work, rest, setRest }

class Phase {
  const Phase({
    required this.type,
    required this.duration,
    required this.setIndex,
    required this.exerciseIndex,
    required this.totalSets,
    required this.totalExercises,
  });

  /// 구간 종류
  final PhaseType type;

  /// 구간 길이(초)
  final int duration;

  /// 현재 세트 번호 (1부터)
  final int setIndex;

  /// 현재 운동 번호 (1부터, 세트 휴식에서는 0)
  final int exerciseIndex;

  final int totalSets;
  final int totalExercises;

  bool get isWorkout => type == PhaseType.work;

  bool get isRest => type == PhaseType.rest || type == PhaseType.setRest;

  /// 카운트다운 사운드를 울리는 구간 (운동 / 휴식)
  bool get needsCountdown => type != PhaseType.prepare;

  String get title => switch (type) {
    PhaseType.prepare => '준비',
    PhaseType.work => '운동 중',
    PhaseType.rest => '휴식',
    PhaseType.setRest => '세트 휴식',
  };

  String get subtitle => switch (type) {
    PhaseType.prepare => '곧 시작합니다',
    PhaseType.work => '$setIndex세트 · $exerciseIndex / $totalExercises개',
    PhaseType.rest => '다음 운동 준비',
    PhaseType.setRest => '다음은 ${setIndex + 1}세트',
  };
}
