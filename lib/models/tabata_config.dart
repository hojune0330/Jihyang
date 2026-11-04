import 'phase.dart';

/// 카운트다운 음성 종류
enum VoiceStyle {
  male('남성', '또렷하고 안정적인 코치 목소리'),
  female('여성', '밝고 경쾌한 에너지 넘치는 목소리'),
  cute('캐릭터', '명랑하고 귀여운 캐릭터 목소리');

  const VoiceStyle(this.label, this.description);

  final String label;
  final String description;

  String get assetKey => name; // c_male_5.wav / c_female_5.wav / c_cute_5.wav

  static VoiceStyle fromName(String? v) {
    for (final s in VoiceStyle.values) {
      if (s.name == v) return s;
    }
    return VoiceStyle.male;
  }
}

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
    this.soundEnabled = true,
    this.voiceEnabled = true,
    this.sfxEnabled = true,
    this.voiceStyle = VoiceStyle.male,
    this.sfxVolume = 0.9,
    this.voiceVolume = 0.9,
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

  /// 전체 사운드 마스터 스위치
  final bool soundEnabled;

  /// 음성 카운트다운 사용
  final bool voiceEnabled;

  /// 효과음 사용
  final bool sfxEnabled;

  /// 카운트다운 목소리 종류
  final VoiceStyle voiceStyle;

  /// 효과음 볼륨 0.0 ~ 1.0
  final double sfxVolume;

  /// 음성 볼륨 0.0 ~ 1.0
  final double voiceVolume;

  /// 운동 시작 전 준비 시간 — 고정 10초
  static const int prepareSeconds = 10;

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
    bool? soundEnabled,
    bool? voiceEnabled,
    bool? sfxEnabled,
    VoiceStyle? voiceStyle,
    double? sfxVolume,
    double? voiceVolume,
  }) {
    return TabataConfig(
      workSeconds: workSeconds ?? this.workSeconds,
      restSeconds: restSeconds ?? this.restSeconds,
      rounds: rounds ?? this.rounds,
      sets: sets ?? this.sets,
      setRestSeconds: setRestSeconds ?? this.setRestSeconds,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      sfxEnabled: sfxEnabled ?? this.sfxEnabled,
      voiceStyle: voiceStyle ?? this.voiceStyle,
      sfxVolume: sfxVolume ?? this.sfxVolume,
      voiceVolume: voiceVolume ?? this.voiceVolume,
    );
  }

  /// 1세트 시간(초) — 마지막 라운드 뒤에는 휴식이 없다.
  int get setSeconds => rounds * workSeconds + (rounds - 1) * restSeconds;

  /// 전체 예상 시간(초)
  ///
  /// 준비 + 세트별 (운동·휴식) + 세트 사이 휴식.
  /// 마지막 라운드 뒤 휴식과 마지막 세트 뒤 세트휴식은 포함하지 않는다.
  int get totalSeconds =>
      prepareSeconds + sets * setSeconds + (sets - 1) * setRestSeconds;

  /// 순수 운동 시간(초)
  int get pureWorkSeconds => sets * rounds * workSeconds;

  /// 전체 라운드 수(세트 포함)
  int get totalRounds => sets * rounds;

  /// buildPhases() 가 만드는 실제 구간 길이의 합.
  /// totalSeconds 와 반드시 같아야 한다 (테스트로 검증).
  int get phasesTotalSeconds =>
      buildPhases().fold<int>(0, (a, p) => a + p.duration);

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
    'soundEnabled': soundEnabled,
    'voiceEnabled': voiceEnabled,
    'sfxEnabled': sfxEnabled,
    'voiceStyle': voiceStyle.name,
    'sfxVolume': sfxVolume,
    'voiceVolume': voiceVolume,
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

    double readDouble(String key, double fallback) {
      final v = json[key];
      if (v is num) return v.toDouble().clamp(0.0, 1.0);
      return fallback;
    }

    return TabataConfig(
      workSeconds: readInt('workSeconds', 30).clamp(5, 3600),
      restSeconds: readInt('restSeconds', 15).clamp(0, 3600),
      rounds: readInt('rounds', 8).clamp(1, 99),
      sets: readInt('sets', 1).clamp(1, 20),
      setRestSeconds: readInt('setRestSeconds', 60).clamp(0, 3600),
      soundEnabled: readBool('soundEnabled', true),
      voiceEnabled: readBool('voiceEnabled', true),
      sfxEnabled: readBool('sfxEnabled', true),
      voiceStyle: VoiceStyle.fromName(json['voiceStyle'] as String?),
      sfxVolume: readDouble('sfxVolume', 0.9),
      voiceVolume: readDouble('voiceVolume', 0.9),
    );
  }
}
