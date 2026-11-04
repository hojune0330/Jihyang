import 'phase.dart';

/// 타바타 설정값
class TabataConfig {
  const TabataConfig({
    this.workSeconds = 20,
    this.restSeconds = 10,
    this.exerciseCount = 8,
    this.setCount = 1,
    this.setRestMinutes = 2,
    this.prepareSeconds = 10,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
  });

  /// 운동 시간 (초)
  final int workSeconds;

  /// 운동 사이 휴식 (초)
  final int restSeconds;

  /// 운동 개수 (n개)
  final int exerciseCount;

  /// 세트 수 (n세트)
  final int setCount;

  /// 세트 간 휴식 (n분)
  final int setRestMinutes;

  /// 시작 전 준비 시간 (초)
  final int prepareSeconds;

  final bool soundEnabled;
  final bool vibrationEnabled;

  TabataConfig copyWith({
    int? workSeconds,
    int? restSeconds,
    int? exerciseCount,
    int? setCount,
    int? setRestMinutes,
    int? prepareSeconds,
    bool? soundEnabled,
    bool? vibrationEnabled,
  }) {
    return TabataConfig(
      workSeconds: workSeconds ?? this.workSeconds,
      restSeconds: restSeconds ?? this.restSeconds,
      exerciseCount: exerciseCount ?? this.exerciseCount,
      setCount: setCount ?? this.setCount,
      setRestMinutes: setRestMinutes ?? this.setRestMinutes,
      prepareSeconds: prepareSeconds ?? this.prepareSeconds,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    );
  }

  /// 세트 사이 휴식(초)
  int get setRestSeconds => setRestMinutes * 60;

  /// 1세트 총 시간
  int get setSeconds =>
      exerciseCount * workSeconds + (exerciseCount - 1) * restSeconds;

  /// 전체 예상 소요 시간(초)
  int get totalSeconds =>
      prepareSeconds + setCount * setSeconds + (setCount - 1) * setRestSeconds;

  /// 총 운동 시간(초) — 순수하게 운동하는 시간만
  int get pureWorkSeconds => setCount * exerciseCount * workSeconds;

  List<Phase> buildPhases() {
    final phases = <Phase>[];

    if (prepareSeconds > 0) {
      phases.add(
        Phase(
          type: PhaseType.prepare,
          duration: prepareSeconds,
          setIndex: 1,
          exerciseIndex: 0,
          totalSets: setCount,
          totalExercises: exerciseCount,
        ),
      );
    }

    for (var s = 1; s <= setCount; s++) {
      for (var e = 1; e <= exerciseCount; e++) {
        phases.add(
          Phase(
            type: PhaseType.work,
            duration: workSeconds,
            setIndex: s,
            exerciseIndex: e,
            totalSets: setCount,
            totalExercises: exerciseCount,
          ),
        );
        if (e < exerciseCount && restSeconds > 0) {
          phases.add(
            Phase(
              type: PhaseType.rest,
              duration: restSeconds,
              setIndex: s,
              exerciseIndex: e,
              totalSets: setCount,
              totalExercises: exerciseCount,
            ),
          );
        }
      }
      if (s < setCount && setRestSeconds > 0) {
        phases.add(
          Phase(
            type: PhaseType.setRest,
            duration: setRestSeconds,
            setIndex: s,
            exerciseIndex: 0,
            totalSets: setCount,
            totalExercises: exerciseCount,
          ),
        );
      }
    }
    return phases;
  }

  Map<String, dynamic> toJson() => {
    'workSeconds': workSeconds,
    'restSeconds': restSeconds,
    'exerciseCount': exerciseCount,
    'setCount': setCount,
    'setRestMinutes': setRestMinutes,
    'prepareSeconds': prepareSeconds,
    'soundEnabled': soundEnabled,
    'vibrationEnabled': vibrationEnabled,
  };

  factory TabataConfig.fromJson(Map<String, dynamic> json) {
    int readInt(String key, int fallback) {
      final v = json[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return fallback;
    }

    bool readBool(String key, bool fallback) {
      final v = json[key];
      return v is bool ? v : fallback;
    }

    return TabataConfig(
      workSeconds: readInt('workSeconds', 20),
      restSeconds: readInt('restSeconds', 10),
      exerciseCount: readInt('exerciseCount', 8),
      setCount: readInt('setCount', 1),
      setRestMinutes: readInt('setRestMinutes', 2),
      prepareSeconds: readInt('prepareSeconds', 10),
      soundEnabled: readBool('soundEnabled', true),
      vibrationEnabled: readBool('vibrationEnabled', true),
    );
  }
}
