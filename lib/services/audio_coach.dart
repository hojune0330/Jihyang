import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/phase.dart';
import '../models/tabata_config.dart';

// ===========================================================================
// 효과음 (경고음)
// ===========================================================================

/// 짧고 선명한 단일 전자음 (ATM 버튼음 계열).
///
/// - 운동/휴식은 **음높이**로 구분한다 (높음 = 운동, 낮음 = 휴식).
/// - 모두 170ms 이하의 짧은 단일음. 반복음·긴 여운 없음.
enum Sfx {
  /// 운동 시작 — 1180Hz, 95ms
  work('audio/sfx_work.wav', 95),

  /// 휴식 시작 — 660Hz, 110ms
  rest('audio/sfx_rest.wav', 110),

  /// 전체 종료 — 780→1170Hz 2음, 167ms
  finish('audio/sfx_finish.wav', 167),

  /// 음성 대체용 중립 비프 — 900Hz, 80ms
  beep('audio/beep.wav', 80);

  const Sfx(this.asset, this.durationMs);

  final String asset;

  /// 실제 파일 길이(ms). 음성과의 간격 계산에 쓴다.
  final int durationMs;
}

// ===========================================================================
// 상태 안내 음성
// ===========================================================================

/// 구간 상태를 알려 주는 사전 녹음 음성.
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

/// 목소리별 상태 안내 음성 길이(ms) — 실제 파일을 ffprobe 로 측정한 값.
///
/// 카운트다운 숫자가 시작 안내 음성과 겹치지 않도록 하는 '보호 구간'을
/// 계산하는 데 쓴다. 오디오를 끈 상태(테스트)에서도 동일하게 계산되도록
/// 순수 상수 표로 둔다.
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
    StateVoice.startWork: 900,
    StateVoice.startRest: 940,
    StateVoice.setRest: 1340,
    StateVoice.lastRound: 1400,
    StateVoice.finish: 1840,
  },
  VoiceStyle.cute: {
    StateVoice.prepare: 680,
    StateVoice.startWork: 840,
    StateVoice.startRest: 760,
    StateVoice.setRest: 1180,
    StateVoice.lastRound: 1140,
    StateVoice.finish: 1740,
  },
};

int stateVoiceDurationMs(VoiceStyle style, StateVoice v) =>
    _stDurationMs[style]?[v] ?? 900;

// ===========================================================================
// 구간 → 안내 계획
// ===========================================================================

/// 한 구간에 울릴 소리 묶음. **재생 순서는 항상 [효과음 → 음성 → (추가 음성)]**.
///
/// 순서를 고정했기 때문에 효과음과 음성이 뒤섞여 뭉개지지 않는다.
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
/// - 준비: **[준비하세요]** (효과음 없음 — 조용히 시작)
/// - 운동: 효과음(높은음) + [운동 시작], 세션 마지막 라운드면 +[마지막 라운드]
/// - 휴식: 효과음(낮은음) + [휴식 시작]
/// - 세트 간 휴식: 효과음(낮은음) + [세트 간 휴식입니다]
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

/// 효과음이 끝나고 음성이 시작되기까지의 간격(ms).
const int sfxToVoiceGapMs = 150;

/// 음성과 음성 사이 간격(ms).
const int voiceToVoiceGapMs = 100;

/// 시작 안내 총 길이(ms).
///
/// 이 시간보다 이른 카운트다운 숫자는 '시작 안내와 겹친다'고 보고 생략한다.
/// (예: 운동 5초 + 남성 목소리 → 보호구간 약 1.3초 → 5·4·3 생략, 2·1만 안내)
int announceGuardMs(
  AnnouncePlan plan,
  VoiceStyle style, {
  bool sfxEnabled = true,
  bool voiceEnabled = true,
}) {
  var t = 0;
  if (plan.sfx != null && sfxEnabled) t += sfxToVoiceGapMs;
  if (voiceEnabled) {
    for (final v in plan.voices) {
      t += stateVoiceDurationMs(style, v) + voiceToVoiceGapMs;
    }
  }
  return t + 120;
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

/// 재생 역할. **역할마다 '지금 재생 중인 자산'은 단 하나**만 존재할 수 있다.
///
/// 그래서 새 소리를 낼 때 같은 역할의 이전 소리는 **무조건 먼저 끊긴다.**
/// (중복 재생이 구조적으로 불가능해진다)
enum _Role { sfx, state, count, preview }

/// 사운드 출력 담당.
///
/// ## 이 클래스가 시간을 계산하지 않는 이유
/// 언제 울릴지는 [TabataEngine]이 단일 벽시계로 결정한다. 여기서는
/// "지금 이 소리를 내라"는 지시만 수행한다. → 음성 재생이 타이머를 지연시키지 않는다.
///
/// ## 중복 재생을 막는 3가지 장치
/// 1. **자산당 플레이어는 정확히 1개.** 생성 즉시(await 이전에) 맵에 등록하고,
///    준비 작업은 `Future`로 공유한다. 동시 호출이 와도 플레이어가 2개 생기지 않는다.
///    (이전 구현의 경쟁 조건 = 중복 재생의 직접 원인이었다)
/// 2. **역할별 단일 슬롯.** 같은 역할의 새 재생 요청은 이전 자산을 먼저 stop 한다.
/// 3. **세대 토큰(_epoch).** 구간이 바뀌면 토큰이 증가하고, 증가 이전에 시작된
///    비동기 재생 시퀀스는 도중에 전부 폐기된다. → 이전 구간 음성이 다음
///    구간까지 흘러가지 않는다.
class AudioCoach {
  AudioCoach._();

  static final AudioCoach instance = AudioCoach._();

  // ------------------------------------------------------------- 설정

  bool soundEnabled = true;
  bool voiceEnabled = true;
  bool sfxEnabled = true;
  VoiceStyle voiceStyle = VoiceStyle.male;
  double sfxVolume = 0.9;
  double voiceVolume = 0.9;

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

  /// 자산 → 플레이어 (자산당 정확히 1개)
  final Map<String, AudioPlayer> _players = <String, AudioPlayer>{};

  /// 자산 → 준비 Future (동시 호출 공유용)
  final Map<String, Future<AudioPlayer>> _pending = <String, Future<AudioPlayer>>{};

  /// 역할 → 현재 재생 중인 자산
  final Map<_Role, String> _current = <_Role, String>{};

  bool _ready = false;
  bool get isReady => _ready;

  /// 검증용 재생 로그
  final List<PlayLogEntry> playLog = <PlayLogEntry>[];

  Future<void> init() async {
    _ready = true;
    // 안드로이드 오디오 포커스 정책.
    // gain 을 쓰면 재생할 때마다 포커스 요청/해제가 반복되며 다른 앱 소리와
    // 부딪혀 끊김이 생긴다. sonification + focus none 으로 '짧은 알림음'에
    // 맞는 가장 안정적인 조합을 쓴다.
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            audioMode: AndroidAudioMode.normal,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.none,
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('setAudioContext failed: $e');
    }
  }

  // ------------------------------------------------------------- 로딩

  bool _isVoiceAsset(String asset) =>
      asset.contains('st_') || asset.contains('c_') || asset.contains('preview_');

  double _volumeFor(String asset) =>
      _isVoiceAsset(asset) ? voiceVolume : sfxVolume;

  /// 자산 플레이어를 **동기적으로** 확보한다. (경쟁 조건 제거의 핵심)
  ///
  /// 맵 등록이 첫 await 보다 먼저 일어나므로, 동시에 여러 곳에서 호출해도
  /// 같은 Future 하나를 공유한다 → 플레이어가 중복 생성되지 않는다.
  Future<AudioPlayer> _ensure(String asset) {
    final existing = _pending[asset];
    if (existing != null) return existing;

    final player = AudioPlayer();
    _players[asset] = player; // ← await 이전에 등록
    final future = _prepare(player, asset);
    _pending[asset] = future;
    return future;
  }

  Future<AudioPlayer> _prepare(AudioPlayer p, String asset) async {
    try {
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
      final v = _volumeFor(e.key);
      e.value.setVolume(v).catchError((_) {});
    }
  }

  /// 이번 세션에 쓸 자산을 미리 올린다. (운동 시작 직전 1회)
  Future<void> warmUp() async {
    cut();
    final assets = <String>{};
    if (!_anySound) return;

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

  /// 역할의 현재 자산을 **즉시** 끊는다. (await 하지 않는다 → 지연 없음)
  void _stopRole(_Role role) {
    final cur = _current.remove(role);
    if (cur == null) return;
    _players[cur]?.stop().catchError((_) {});
  }

  /// 실제 재생. 시작 전에 stop → seek(0) → resume 순서를 지킨다.
  Future<void> _start(
    _Role role,
    String asset,
    int epoch, {
    String? phaseType,
  }) async {
    if (epoch != _epoch) return;
    final p = await _ensure(asset);
    if (epoch != _epoch) return;
    try {
      await p.stop();
      if (epoch != _epoch) return;
      await p.setVolume(_volumeFor(asset));
      await p.seek(Duration.zero);
      if (epoch != _epoch) return;
      await p.resume();
      _current[role] = asset;
      _log(asset, role, phaseType: phaseType);
    } catch (e) {
      if (kDebugMode) debugPrint('audio play failed($asset): $e');
    }
  }

  // ------------------------------------------------------------- 공개 API

  /// 구간 전환. **이전 구간의 모든 예약/잔여음을 즉시 무효화**한 뒤 안내를 시작한다.
  ///
  /// [TabataEngine]이 구간에 들어갈 때 한 번만 호출한다.
  void announce(AnnouncePlan plan, {String? phaseType}) {
    _epoch++; // ← 동기. 이미 시작된 비동기 시퀀스가 전부 폐기된다.
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
    // ① 효과음 먼저 (항상 동일한 순서)
    if (plan.sfx != null && sfxEnabled) {
      _stopRole(_Role.sfx);
      unawaited(_start(_Role.sfx, plan.sfx!.asset, epoch, phaseType: phaseType));
    }

    if (!voiceEnabled || plan.voices.isEmpty) return;

    // ② 효과음이 끝난 뒤 음성
    if (plan.sfx != null && sfxEnabled) {
      await Future<void>.delayed(
        Duration(milliseconds: plan.sfx!.durationMs + sfxToVoiceGapMs),
      );
      if (epoch != _epoch) return;
    }

    // ③ 음성은 한 번에 하나. 길이만큼 기다린 뒤 다음 음성.
    for (final v in plan.voices) {
      final asset = v.assetFor(voiceStyle);
      _stopRole(_Role.state);
      unawaited(_start(_Role.state, asset, epoch, phaseType: phaseType));
      await Future<void>.delayed(
        Duration(
          milliseconds: stateVoiceDurationMs(voiceStyle, v) + voiceToVoiceGapMs,
        ),
      );
      if (epoch != _epoch) return;
    }
  }

  /// 마지막 5초 카운트다운 숫자.
  ///
  /// 음성이 꺼져 있으면 짧은 비프로 대체한다.
  void playCount(int n) {
    if (!_anySound) return;
    if (!voiceEnabled) {
      if (sfxEnabled) playSfx(Sfx.beep);
      return;
    }
    final epoch = _epoch;
    _stopRole(_Role.count);
    unawaited(
      _start(_Role.count, 'audio/c_${voiceStyle.assetKey}_$n.wav', epoch),
    );
  }

  /// 단발 효과음.
  void playSfx(Sfx sfx) {
    if (!_anySound || !sfxEnabled) return;
    final epoch = _epoch;
    _stopRole(_Role.sfx);
    unawaited(_start(_Role.sfx, sfx.asset, epoch));
  }

  /// 설정 화면 '미리 듣기'.
  ///
  /// 별도 샘플 파일 대신 **실제 재생에 쓰는 자산 그대로**를 이어 들려준다.
  /// → 미리 듣는 목소리와 실제 운동 중 목소리가 어긋날 수 없다.
  Future<void> previewVoice(VoiceStyle style) async {
    if (!_anySound) return;
    final epoch = _epoch;
    _stopRole(_Role.preview);
    _stopRole(_Role.state);
    _stopRole(_Role.count);

    // "운동 시작!" → 5·4·3·2·1
    await _start(
      _Role.preview,
      StateVoice.startWork.assetFor(style),
      epoch,
    );
    await Future<void>.delayed(
      Duration(
        milliseconds:
            stateVoiceDurationMs(style, StateVoice.startWork) + 220,
      ),
    );
    for (var n = 5; n >= 1; n--) {
      if (epoch != _epoch) return;
      _stopRole(_Role.preview);
      unawaited(
        _start(
          _Role.preview,
          'audio/c_${style.assetKey}_$n.wav',
          epoch,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 720));
    }
  }

  Future<void> previewSfx(Sfx sfx) async {
    if (!_anySound) return;
    final epoch = _epoch;
    _stopRole(_Role.preview);
    await _start(_Role.preview, sfx.asset, epoch);
  }

  // ------------------------------------------------------------- 정지

  /// 재생 중인 모든 소리를 즉시 무효화하고 멈춘다.
  ///
  /// 토큰 증가가 **동기**라, 늦게 도착하는 비동기 완료가 이전 소리를
  /// 되살리는 일이 없다. (일시정지/건너뛰기/종료에서 호출)
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
    _pending.clear();
  }
}
