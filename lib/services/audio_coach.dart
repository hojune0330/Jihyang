import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/phase.dart';
import '../models/tabata_config.dart';

// ===========================================================================
// 효과음
// ===========================================================================

/// 경고음 종류.
///
/// 음성 안내를 **켠** 경우: 구간 시작에 짧은 '삑' 하나만 울리고 곧바로 음성이
/// 이어진다 (대화하듯 자연스럽게).
/// 음성 안내를 **끈** 경우: '삐-삐-' 두 번(약 0.84초)으로 구간 전환을 알리고,
/// 마지막 5초는 매초 '틱'으로 정확히 시간을 알려 준다.
enum Sfx {
  /// 운동 구간 주의음 — 높은 음 '삐-삐-' (840ms)
  work('audio/sfx_work.wav', 840),

  /// 휴식 구간 주의음 — 낮은 음 '삐-삐-' (840ms)
  rest('audio/sfx_rest.wav', 840),

  /// 전체 종료 — 세 번 상승 (1220ms)
  finish('audio/sfx_finish.wav', 1220),

  /// 음성이 켜져 있을 때 쓰는 짧은 주의음 '삑' (130ms)
  beep('audio/beep.wav', 130),

  /// 음성이 꺼졌을 때 매초 시간을 알리는 또렷한 틱 (110ms)
  count('audio/sfx_count.wav', 110);

  const Sfx(this.asset, this.durationMs);

  final String asset;
  final int durationMs;
}

// ===========================================================================
// 상태 안내 음성
// ===========================================================================

enum StateVoice {
  /// "준비하세요."
  prepare('prepare'),

  /// "운동 시작!"
  startWork('startWork'),

  /// "휴식 시작!"
  startRest('startRest'),

  /// "세트 간 휴식입니다."
  setRest('setRest'),

  /// "마지막 라운드입니다."
  lastRound('lastRound'),

  /// "운동이 모두 종료되었습니다."
  finish('finish');

  const StateVoice(this.key);

  final String key;

  String assetFor(VoiceStyle style) => 'audio/st_${style.assetKey}_$key.wav';
}

/// 목소리별 상태 안내 길이(ms) — 실제 파일 측정값.
///
/// 테스트에서는 오디오를 끄므로, 순수 상수 표로 두어 오디오 없이도
/// 카운트다운 보호구간을 동일하게 계산할 수 있게 한다.
const Map<VoiceStyle, Map<StateVoice, int>> _stDurationMs = {
  VoiceStyle.male: {
    StateVoice.prepare: 740,
    StateVoice.startWork: 940,
    StateVoice.startRest: 960,
    StateVoice.setRest: 1340,
    StateVoice.lastRound: 1100,
    StateVoice.finish: 1580,
  },
  VoiceStyle.female: {
    StateVoice.prepare: 920,
    StateVoice.startWork: 875,
    StateVoice.startRest: 906,
    StateVoice.setRest: 1340,
    StateVoice.lastRound: 1400,
    StateVoice.finish: 1840,
  },
  VoiceStyle.baby: {
    StateVoice.prepare: 680,
    StateVoice.startWork: 940,
    StateVoice.startRest: 980,
    StateVoice.setRest: 1300,
    StateVoice.lastRound: 1220,
    StateVoice.finish: 2120,
  },
};

int stateVoiceDurationMs(VoiceStyle style, StateVoice v) =>
    _stDurationMs[style]?[v] ?? 900;

// ===========================================================================
// 구간 → 안내 계획
// ===========================================================================

/// 한 구간에 울릴 소리 묶음. 재생 순서는 항상 **주의음 → 음성 → (추가 음성)**.
class AnnouncePlan {
  const AnnouncePlan({this.sfx, this.voices = const <StateVoice>[]});

  final Sfx? sfx;
  final List<StateVoice> voices;

  bool get isEmpty => sfx == null && voices.isEmpty;

  @override
  String toString() =>
      'AnnouncePlan(sfx: ${sfx?.name}, voices: ${voices.map((v) => v.key).join(',')})';
}

/// 구간 → 안내 계획 (순수 함수 → 테스트로 검증 가능).
///
/// [sfx] 는 '음성이 꺼졌을 때' 쓸 주의음이다. 음성이 켜져 있으면 짧은 삑으로
/// 대체되고 곧바로 음성이 이어진다 ([announceTiming] 참고).
AnnouncePlan planForPhase(
  Phase phase, {
  required int totalSets,
  required int totalRounds,
}) {
  final isFinalRoundOfSession =
      phase.setIndex >= totalSets && phase.roundIndex >= totalRounds;

  switch (phase.type) {
    case PhaseType.prepare:
      return const AnnouncePlan(voices: [StateVoice.prepare]);
    case PhaseType.work:
      return AnnouncePlan(
        sfx: Sfx.work,
        voices: [
          StateVoice.startWork,
          if (isFinalRoundOfSession) StateVoice.lastRound,
        ],
      );
    case PhaseType.rest:
      return const AnnouncePlan(
        sfx: Sfx.rest,
        voices: [StateVoice.startRest],
      );
    case PhaseType.setRest:
      return const AnnouncePlan(
        sfx: Sfx.rest,
        voices: [StateVoice.setRest],
      );
  }
}

// --- 안내 시퀀스 타이밍 -----------------------------------------------------

/// 주의음이 끝나고 음성이 시작되기까지의 간격.
const int attentionGapMs = 90;

/// 음성과 음성 사이 간격 — 문장이 붙어 들리지 않을 만큼만 띄운다.
const int voiceToVoiceGapMs = 110;

/// 주의음 없이 음성만 시작할 때의 지연.
const int silenceStartMs = 40;

/// 안내가 끝난 뒤 카운트다운 숫자를 허용하기까지의 여유.
const int guardPaddingMs = 140;

/// 안내 시퀀스의 절대 시각표.
///
/// [TabataEngine] 과 [AudioCoach] 가 **같은 함수**로 시각을 계산하므로,
/// "카운트다운이 시작 안내와 겹친다" 같은 불일치가 구조적으로 생기지 않는다.
class AnnounceTiming {
  const AnnounceTiming({
    this.attention,
    this.voiceStartsAt = const <int>[],
    this.totalMs = 0,
  });

  /// 실제로 울릴 주의음 (음성 유무에 따라 달라진다)
  final Sfx? attention;

  /// 각 음성이 시작되어야 하는 시각(주의음 시작 = 0ms 기준)
  final List<int> voiceStartsAt;

  /// 마지막 음성이 끝나는 시각(ms)
  final int totalMs;

  bool get hasVoice => voiceStartsAt.isNotEmpty;
}

AnnounceTiming announceTiming(
  AnnouncePlan plan,
  VoiceStyle style, {
  required bool sfxEnabled,
  required bool voiceEnabled,
}) {
  final hasVoice = voiceEnabled && plan.voices.isNotEmpty;

  Sfx? attention;
  if (sfxEnabled) {
    // 음성이 함께 나오면 짧은 삑으로만 주의를 끌고 바로 음성으로 넘어간다.
    attention = hasVoice ? Sfx.beep : plan.sfx;
  }

  if (!hasVoice) {
    return AnnounceTiming(
      attention: attention,
      totalMs: attention?.durationMs ?? 0,
    );
  }

  var at = attention == null
      ? silenceStartMs
      : attention.durationMs + attentionGapMs;

  final starts = <int>[];
  var total = 0;
  for (final v in plan.voices) {
    starts.add(at);
    total = at + stateVoiceDurationMs(style, v);
    at = total + voiceToVoiceGapMs;
  }
  return AnnounceTiming(attention: attention, voiceStartsAt: starts, totalMs: total);
}

/// 이 시간보다 이른 카운트다운 숫자는 시작 안내와 겹친다고 보고 생략한다.
int announceGuardMs(
  AnnouncePlan plan,
  VoiceStyle style, {
  bool sfxEnabled = true,
  bool voiceEnabled = true,
}) {
  final t = announceTiming(
    plan,
    style,
    sfxEnabled: sfxEnabled,
    voiceEnabled: voiceEnabled,
  );
  return t.totalMs + guardPaddingMs;
}

// ===========================================================================
// 재생 기록
// ===========================================================================

class PlayLogEntry {
  PlayLogEntry({
    required this.asset,
    required this.wallMs,
    required this.kind,
    this.phaseType,
  });

  final String asset;
  final int wallMs;
  final String kind; // 'sfx' | 'state' | 'count' | 'preview'
  final String? phaseType;

  @override
  String toString() => 'PlayLog($kind $asset @${wallMs % 100000})';
}

// ===========================================================================
// AudioCoach
// ===========================================================================

enum _Role { sfx, state, count, preview }

/// 사운드 출력 담당.
///
/// ## 시간은 계산하지 않는다
/// 언제 울릴지는 [TabataEngine] 이 단일 벽시계로 결정한다. 여기서는 "지금 이
/// 소리를 내라"는 지시만 수행한다. → 음성 길이가 타이머를 지연시키지 않는다.
///
/// ## 중복 재생을 막는 4중 장치
/// 1. **자산당 플레이어 정확히 1개.** 생성 즉시(첫 await 이전에) 맵에 등록하고
///    준비 작업은 Future 하나를 공유한다. 동시 호출이 와도 2개가 생기지 않는다.
/// 2. **역할별 단일 슬롯 + 동기 점유.** [_playRole] 은 첫 await 이전에
///    `_current[role]` 을 새 자산으로 바꾼다. 그래야 다음 정지 요청이
///    "아직 재생 시작 전이라 슬롯이 비어 있는" 플레이어를 놓치지 않는다.
///    (이전 구현은 await 뒤에 점유해서, 정지 요청이 허공을 치고 그 플레이어가
///     계속 재생되는 경로가 있었다 → 중복·누락의 원인)
/// 3. **역할별 세대 번호(_roleSeq).** 같은 역할에 새 재생이 걸리면 진행 중이던
///    이전 재생 시퀀스는 다음 await 에서 스스로 폐기된다.
/// 4. **자산별 직렬화 큐(_opChain).** 같은 플레이어에 stop/seek/resume 이
///    동시에 들어가면 안드로이드에서 소리가 튀거나 멈춘다. 자산마다 작업을
///    한 줄로 세워 순서대로만 실행한다 → '뚝뚝 끊기는' 현상 제거.
class AudioCoach {
  AudioCoach._();

  static final AudioCoach instance = AudioCoach._();

  // ------------------------------------------------------------- 설정

  bool soundEnabled = true;
  bool voiceEnabled = true;
  bool sfxEnabled = true;
  VoiceStyle voiceStyle = VoiceStyle.male;
  double sfxVolume = 0.95;
  double voiceVolume = 1.0;

  bool get _anySound => soundEnabled;

  void applyConfig(TabataConfig c) {
    final styleChanged = voiceStyle != c.voiceStyle;
    soundEnabled = c.soundEnabled;
    voiceEnabled = c.voiceEnabled;
    sfxEnabled = c.sfxEnabled;
    sfxVolume = c.sfxVolume;
    voiceVolume = c.voiceVolume;
    if (styleChanged) {
      cut();
      voiceStyle = c.voiceStyle;
      unawaited(warmUp());
    } else {
      voiceStyle = c.voiceStyle;
    }
    _applyVolumes();
  }

  // ------------------------------------------------------------- 상태

  /// 세대 토큰. 구간 전환/일시정지/종료 시 증가한다.
  int _epoch = 0;

  /// 역할별 세대 번호 — 같은 역할의 이전 재생 시퀀스를 폐기하는 데 쓴다.
  final Map<_Role, int> _roleSeq = <_Role, int>{};

  /// 역할 → 현재(또는 재생 예정) 자산
  final Map<_Role, String> _current = <_Role, String>{};

  /// 자산 → 플레이어
  final Map<String, AudioPlayer> _players = <String, AudioPlayer>{};

  /// 자산 → 준비 Future (동시 호출 공유)
  final Map<String, Future<AudioPlayer>> _prepare_ = <String, Future<AudioPlayer>>{};

  /// 자산별 작업 직렬화 큐
  final Map<String, Future<void>> _opChain = <String, Future<void>>{};

  bool _ready = false;
  bool get isReady => _ready;

  final List<PlayLogEntry> playLog = <PlayLogEntry>[];

  Future<void> init() async {
    _ready = true;
    // ── 안드로이드 오디오 정책 (중복/끊김의 근본 원인 수정) ──────────────
    //
    // audioplayers 의 FocusManager 는 **포커스를 새로 얻은 플레이어가 생기면
    // 이전 플레이어를 pause()** 시킨다 (WrappedPlayer.kt 의 onLoss(true)).
    // 우리는 자산마다 플레이어를 따로 쓰기 때문에, gainTransientMayDuck 로
    // 두면 카운트 숫자가 울리는 순간 코치 음성이, 삑 소리가 울리는 순간 앞
    // 음성이 **중간에 잘린다.** → 사용자가 겪은 '뚝뚝 끊김 / 누락'.
    //
    // 그래서 포커스 요청을 아예 하지 않는다(AUDIOFOCUS_NONE). 그러면 각
    // 플레이어가 서로를 멈추지 않고 자연스럽게 겹쳐/이어서 재생된다.
    // (짧은 안내음에는 포커스를 뺏을 이유가 없다 — 음악 앱 소리도 안 죽인다)
    const android = AudioContextAndroid(
      isSpeakerphoneOn: false,
      audioMode: AndroidAudioMode.normal,
      stayAwake: false,
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.none,
    );
    _androidContext = android;
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(android: android));
    } catch (e) {
      if (kDebugMode) debugPrint('setAudioContext(global) failed: $e');
    }
  }

  /// 플레이어별로도 같은 컨텍스트를 못박아 둔다.
  /// (전역 설정이 늦게 적용되는 기기에서 포커스 경합이 다시 생기는 것을 막는다)
  AudioContextAndroid? _androidContext;

  // ------------------------------------------------------------- 로딩

  bool _isVoiceAsset(String asset) =>
      asset.contains('st_') || asset.contains('c_') || asset.contains('preview_');

  double _volumeFor(String asset) =>
      _isVoiceAsset(asset) ? voiceVolume : sfxVolume;

  /// 자산 플레이어를 **동기적으로** 확보한다 (중복 생성 원천 차단).
  Future<AudioPlayer> _ensure(String asset) {
    final existing = _prepare_[asset];
    if (existing != null) return existing;

    final player = AudioPlayer();
    _players[asset] = player; // ← 첫 await 이전에 등록
    final future = _preparePlayer(player, asset);
    _prepare_[asset] = future;
    return future;
  }

  Future<AudioPlayer> _preparePlayer(AudioPlayer p, String asset) async {
    try {
      // 플레이어 단위로 포커스 없음(none)을 못박는다.
      // 이걸 빠뜨리면 전역 설정이 늦게 적용되는 기기에서 자산끼리
      // 서로를 pause() 시켜 소리가 중간에 끊긴다.
      final ctx = _androidContext;
      if (ctx != null) {
        try {
          await p.setAudioContext(AudioContext(android: ctx));
        } catch (_) {}
      }
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setVolume(_volumeFor(asset));
      await p.setSource(AssetSource(asset));
    } catch (e) {
      if (kDebugMode) debugPrint('audio prepare failed($asset): $e');
    }
    return p;
  }

  void _applyVolumes() {
    for (final e in _players.entries) {
      e.value.setVolume(_volumeFor(e.key)).catchError((_) {});
    }
  }

  /// 자산별로 작업을 한 줄로 세운다.
  ///
  /// 같은 플레이어에 stop/seek/resume 이 겹쳐 들어가면 소리가 튀거나 멈춘다.
  /// 이 큐가 그것을 막는다.
  Future<void> _serial(String asset, Future<void> Function(AudioPlayer) op) {
    final prev = _opChain[asset];
    final completer = Completer<void>();
    final mine = completer.future;
    _opChain[asset] = mine;

    Future<void> run() async {
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      try {
        final p = await _ensure(asset);
        await op(p);
      } catch (e) {
        if (kDebugMode) debugPrint('audio op failed($asset): $e');
      } finally {
        if (!completer.isCompleted) completer.complete();
        if (identical(_opChain[asset], mine)) _opChain.remove(asset);
      }
    }

    unawaited(run());
    return mine;
  }

  Future<void> warmUp() async {
    if (!_anySound) return;
    final assets = <String>{};
    assets.addAll(Sfx.values.map((s) => s.asset));
    for (final v in StateVoice.values) {
      assets.add(v.assetFor(voiceStyle));
    }
    for (var n = 5; n >= 1; n--) {
      assets.add('audio/c_${voiceStyle.assetKey}_$n.wav');
    }
    await Future.wait(assets.map(_ensure));
  }

  // ------------------------------------------------------------- 재생

  void _log(String asset, _Role role, {String? phaseType}) {
    if (!kDebugMode) return;
    playLog.add(
      PlayLogEntry(
        asset: asset,
        wallMs: DateTime.now().millisecondsSinceEpoch,
        kind: role.name,
        phaseType: phaseType,
      ),
    );
    if (playLog.length > 400) playLog.removeAt(0);
  }

  /// 역할 재생. **첫 await 이전에 슬롯을 점유**하는 것이 핵심이다.
  Future<void> _playRole(_Role role, String asset, int epoch,
      {String? phaseType}) async {
    // --- 동기 구간: 슬롯 점유 + 이전 자산 정지 ---------------------------
    final seq = (_roleSeq[role] ?? 0) + 1;
    _roleSeq[role] = seq;
    final prevAsset = _current[role];
    _current[role] = asset;
    if (prevAsset != null && prevAsset != asset) {
      unawaited(_serial(prevAsset, (p) => p.stop()));
    }

    // --- 비동기 구간: 언제든 폐기될 수 있다 ------------------------------
    bool stale() => epoch != _epoch || _roleSeq[role] != seq;

    await _serial(asset, (p) async {
      if (stale()) return;
      await p.stop();
      if (stale()) return;
      await p.setVolume(_volumeFor(asset));
      await p.seek(Duration.zero);
      if (stale()) return;
      await p.resume();
      _log(asset, role, phaseType: phaseType);
    });
  }

  /// 역할을 즉시 무효화하고 재생 중인 자산을 멈춘다 (동기).
  void _stopRole(_Role role) {
    _roleSeq[role] = (_roleSeq[role] ?? 0) + 1;
    final cur = _current.remove(role);
    if (cur == null) return;
    unawaited(_serial(cur, (p) => p.stop()));
  }

  // ------------------------------------------------------------- 공개 API

  /// 구간 전환 안내.
  ///
  /// 이전 구간의 잔여음은 **동기적으로** 전부 무효화한 뒤, 절대 시각표대로
  /// 주의음 → 음성을 이어 붙인다.
  void announce(AnnouncePlan plan, {String? phaseType}) {
    _epoch++;
    for (final r in _Role.values) {
      _stopRole(r);
    }
    if (!_anySound) return;
    final epoch = _epoch;
    unawaited(_runAnnounce(plan, epoch, phaseType));
  }

  Future<void> _runAnnounce(
    AnnouncePlan plan,
    int epoch,
    String? phaseType,
  ) async {
    final timing = announceTiming(
      plan,
      voiceStyle,
      sfxEnabled: sfxEnabled,
      voiceEnabled: voiceEnabled,
    );

    // ① 주의음 (음성이 있으면 짧은 삑, 없으면 삐-삐-)
    if (timing.attention != null) {
      unawaited(
        _playRole(_Role.sfx, timing.attention!.asset, epoch,
            phaseType: phaseType),
      );
    }

    if (!timing.hasVoice) return;

    // ② 음성 — Stopwatch 기준 '절대 시각'으로 시작해 누적 오차를 없앤다.
    final sw = Stopwatch()..start();
    for (var i = 0; i < timing.voiceStartsAt.length; i++) {
      final at = timing.voiceStartsAt[i];
      final left = at - sw.elapsedMilliseconds;
      if (left > 0) {
        await Future<void>.delayed(Duration(milliseconds: left));
      }
      if (epoch != _epoch) return;
      unawaited(
        _playRole(
          _Role.state,
          plan.voices[i].assetFor(voiceStyle),
          epoch,
          phaseType: phaseType,
        ),
      );
    }
  }

  /// 마지막 5초 카운트다운.
  ///
  /// 음성이 꺼져 있으면 또렷한 '틱'으로 대체해 초를 정확히 알 수 있게 한다.
  void playCount(int n) {
    if (!_anySound) return;
    if (!voiceEnabled) {
      if (sfxEnabled) playSfx(Sfx.count);
      return;
    }
    final epoch = _epoch;
    unawaited(
      _playRole(_Role.count, 'audio/c_${voiceStyle.assetKey}_$n.wav', epoch),
    );
  }

  /// 단발 효과음.
  void playSfx(Sfx sfx) {
    if (!_anySound || !sfxEnabled) return;
    final epoch = _epoch;
    unawaited(_playRole(_Role.sfx, sfx.asset, epoch));
  }

  /// 설정 화면 '목소리 미리 듣기'.
  ///
  /// 실제 재생에 쓰는 **자산 그대로** 짧은 주의음 + "운동 시작!" + 5·4·3·2·1 을
  /// 이어 들려준다. → 미리 듣는 소리와 실제 운동 중 소리가 어긋날 수 없다.
  Future<void> previewVoice(VoiceStyle style) async {
    if (!_anySound) return;
    _epoch++;
    for (final r in _Role.values) {
      _stopRole(r);
    }
    final epoch = _epoch;

    final sw = Stopwatch()..start();
    var at = 0;

    void schedule(String asset, int ms) {
      final left = ms - sw.elapsedMilliseconds;
      if (left <= 0) {
        unawaited(_playRole(_Role.preview, asset, epoch));
      } else {
        Future<void>.delayed(Duration(milliseconds: left), () {
          if (epoch != _epoch) return;
          unawaited(_playRole(_Role.preview, asset, epoch));
        });
      }
    }

    if (sfxEnabled) {
      schedule(Sfx.beep.asset, at);
      at += Sfx.beep.durationMs + attentionGapMs;
    } else {
      at = silenceStartMs;
    }

    schedule(StateVoice.startWork.assetFor(style), at);
    at += stateVoiceDurationMs(style, StateVoice.startWork) + 260;

    for (var n = 5; n >= 1; n--) {
      schedule('audio/c_${style.assetKey}_$n.wav', at);
      at += 620;
    }
  }

  /// 설정 화면 '효과음 미리 듣기' — 실제 구간 시작에 울릴 소리를 그대로 낸다.
  Future<void> previewSfx(Sfx sfx) async {
    if (!_anySound) return;
    final epoch = _epoch;
    final timing = announceTiming(
      AnnouncePlan(sfx: sfx),
      voiceStyle,
      sfxEnabled: true,
      voiceEnabled: voiceEnabled,
    );
    final target = timing.attention ?? sfx;
    await _playRole(_Role.preview, target.asset, epoch);
  }

  /// 재생 중인 모든 소리를 즉시 무효화하고 멈춘다 (일시정지/건너뛰기/종료).
  void cut() {
    _epoch++;
    for (final r in _Role.values) {
      _stopRole(r);
    }
  }

  Future<void> stopAll() async {
    cut();
    for (final p in _players.values) {
      try {
        await p.stop();
      } catch (_) {}
    }
  }

  void vibrate({bool heavy = false}) {
    if (!_anySound) return;
    HapticFeedback.mediumImpact().catchError((_) {});
    if (heavy) HapticFeedback.heavyImpact().catchError((_) {});
  }

  Future<void> dispose() async {
    cut();
    for (final p in _players.values) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _players.clear();
    _prepare_.clear();
    _opChain.clear();
  }
}
