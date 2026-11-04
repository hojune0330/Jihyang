import 'phase.dart';

/// 타바타 설정값.
///
/// 시간은 모두 '초' 단위로 보관하고, 화면에서는 분/초로 나누어 보여준다.
class TabataConfig {
  const TabataConfig({
    this.workSeconds = 30,
    this.restSeconds = 15,
    this.rounds = 8,
    this.sets = 1,
    this.setRestSeconds = 60,
    this.voiceEnabled = true,
    this.sfxEnabled = true,
  });

  /// 운동 시간(초)
  final int workSeconds;

  /// 운동 사이 휴식(초)
  final int restSeconds;

  /// 라운드 수 (한 세트 안의 운동 개수)
  final int rounds;

  /// 세트 수
  final int sets;

  /// 세트 간 휴식(초)
  final int setRestSeconds;

  /// 음성 안내 사용
  final bool voiceEnabled;

  /// 효과음 사용
  final bool sfxEnabled;

  /// 시작 전 카운트다운 — 설정 항목으로 노출하지 않고 고정
  static const int prepareSeconds = 3;

  int get workMinutes => workSeconds ~/ 60;
  int get workSecondsPart => workSeconds % 60;
  int get restMinutes => restSeconds ~/ 60;
  int get restSecondsPart => restSeconds % 60;
  int get setRestMinutes => setRestSeconds ~/ 60;
  int get setRestSecondsPart => setRestSeconds % 60;

  TabataConfig copyWith({
    int? workSeconds,
    int? restSeconds,
    int? rounds,
    int? sets,
    int? setRestSeconds,
    bool? voiceEnabled,
    bool? sfxEnabled,
  }) {
    return TabataConfig(
      workSeconds: workSeconds ?? this.workSeconds,
      restSeconds: restSeconds ?? this.restSeconds,
      rounds: rounds ?? this.rounds,
      sets: sets ?? this.sets,
      setRestSeconds: setRestSeconds ?? this.setRestSeconds,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      sfxEnabled: sfxEnabled ?? this.sfxEnabled,
    );
  }

  /// 1세트 시간(초)
  int get setSeconds => rounds * workSeconds + (rounds - 1) * restSeconds;

  /// 전체 예상 시간(초)
  int get totalSeconds =>
      prepareSeconds + sets * setSeconds + (sets - 1) * setRestSeconds;

  /// 순수 운동 시간(초)
  int get pureWorkSeconds => sets * rounds * workSeconds;

  /// 전체 라운드 수(세트 포함)
  int get totalRounds => sets * rounds;

  List<Phase> buildPhases() {
    final phases = <Phase>[];

    phases.add(
      Phase(
        type: PhaseType.prepare,
        duration: prepareSeconds,
        setIndex: 1,
        roundIndex: 0,
        totalSets: sets,
        totalRounds: rounds,
      ),
    );

    for (var s = 1; s <= sets; s++) {
      for (var r = 1; r <= rounds; r++) {
        phases.add(
          Phase(
            type: PhaseType.work,
            duration: workSeconds,
            setIndex: s,
            roundIndex: r,
            totalSets: sets,
            totalRounds: rounds,
          ),
        );
        final isLastRoundOfSet = r == rounds;
        if (!isLastRoundOfSet && restSeconds > 0) {
          phases.add(
            Phase(
              type: PhaseType.rest,
              duration: restSeconds,
              setIndex: s,
              roundIndex: r,
              totalSets: sets,
              totalRounds: rounds,
            ),
          );
        }
        if (isLastRoundOfSet && s < sets && setRestSeconds > 0) {
          phases.add(
            Phase(
              type: PhaseType.setRest,
              duration: setRestSeconds,
              setIndex: s,
              roundIndex: r,
              totalSets: sets,
              totalRounds: rounds,
            ),
          );
        }
      }
    }
    return phases;
  }

  Map<String, dynamic> toJson() => {
    'workSeconds': workSeconds,
    'restSeconds': restSeconds,
    'rounds': rounds,
    'sets': sets,
    'setRestSeconds': setRestSeconds,
    'voiceEnabled': voiceEnabled,
    'sfxEnabled': sfxEnabled,
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
      workSeconds: readInt('workSeconds', 30).clamp(5, 3600),
      restSeconds: readInt('restSeconds', 15).clamp(0, 3600),
      rounds: readInt('rounds', 8).clamp(1, 99),
      sets: readInt('sets', 1).clamp(1, 20),
      setRestSeconds: readInt('setRestSeconds', 60).clamp(0, 3600),
      voiceEnabled: readBool('voiceEnabled', true),
      sfxEnabled: readBool('sfxEnabled', true),
    );
  }
}
