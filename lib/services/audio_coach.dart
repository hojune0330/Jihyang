import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/phase.dart';
import '../models/tabata_config.dart';

// ===========================================================================
// 효과음 (음성 안내를 끈 상태에서 쓰는 단독 신호)
// ===========================================================================

/// 경고음 종류.
///
/// 안내 음성이 **켜져** 있으면 `seq_*.wav` 파일 하나에 [삑 + 음성]이 미리
/// 합쳐져 있어 재생 한 번으로 끝난다. 아래 단독 효과음은 **음성을 끈 상태**와
/// **초 알림(틱)** 에서만 쓴다.
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
// 안내 시퀀스 (삑 + 음성이 미리 합쳐진 단일 파일)
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

/// 삑 소리와 음성 사이 간격 (파일을 만들 때 쓴 값과 동일해야 한다)
const int attentionGapMs = 90;

/// 음성과 음성 사이 간격
const int voiceToVoiceGapMs = 110;

/// 주의음 없이 음성만 시작할 때의 지연
const int silenceStartMs = 40;

/// 안내가 끝난 뒤 카운트다운 숫자를 허용하기까지의 여유
const int guardPaddingMs = 140;

/// 시퀀스 파일 앞부분의 '삑' 길이 (ms) — 효과음을 끈 상태에서 건너뛸 때 쓴다.
const int beepLeadMs = 130;

/// 목소리별 상태 안내 **음성만의** 길이(ms) — 실제 파일 측정값.
/// (시퀀스 총 길이를 계산하는 기준)
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

/// 안내 시퀀스 파일의 **실제 길이**(ms) — tool/build_sequences.py 산출값.
const Map<String, Map<String, int>> _seqDurMs = {
  'male': {
    'prepare': 960,
    'startWork': 1160,
    'startRest': 1180,
    'setRest': 1560,
    'lastRound': 1320,
    'finish': 1800,
    'workLast': 2370,
  },
  'female': {
    'prepare': 1140,
    'startWork': 1095,
    'startRest': 1126,
    'setRest': 1560,
    'lastRound': 1620,
    'finish': 2060,
    'workLast': 2605,
  },
  'baby': {
    'prepare': 900,
    'startWork': 1160,
    'startRest': 1200,
    'setRest': 1520,
    'lastRound': 1440,
    'finish': 2340,
    'workLast': 2490,
  },
};

/// 5·4·3·2·1 이 1초 간격으로 들어 있는 묶음 파일의 길이(ms)
// ignore: unused_element
const Map<String, int> _cntDurMs = {
  'male': 4449,
  'female': 4424,
  'baby': 4360,
};

// ===========================================================================
// 구간 → 안내 계획
// ===========================================================================

/// 한 구간에 울릴 소리 묶음.
class AnnouncePlan {
  const AnnouncePlan({
    this.sfx,
    this.voices = const <StateVoice>[],
    this.key = 'prepare',
  });

  final Sfx? sfx;
  final List<StateVoice> voices;

  /// 시퀀스 파일 키 (`seq_<style>_<key>.wav`)
  final String key;

  bool get isEmpty => sfx == null && voices.isEmpty;

  /// 재생할 시퀀스 파일 (삑 + 음성이 미리 합쳐진 단일 파일)
  String seqAssetFor(VoiceStyle style) => 'audio/seq_${style.assetKey}_$key.wav';

  @override
  String toString() =>
      'AnnouncePlan(key: $key, sfx: ${sfx?.name}, '
      'voices: ${voices.map((v) => v.key).join(',')})';
}

/// 구간 → 안내 계획 (순수 함수).
///
/// [sfx] 는 '음성이 꺼졌을 때' 쓸 단독 주의음이다. 음성이 켜져 있으면
/// 시퀀스 파일 안에 이미 짧은 삑이 들어 있으므로 그대로 재생하면 된다.
AnnouncePlan planForPhase(
  Phase phase, {
  required int totalSets,
  required int totalRounds,
}) {
  final isFinalRoundOfSession =
      phase.setIndex >= totalSets && phase.roundIndex >= totalRounds;

  switch (phase.type) {
    case PhaseType.prepare:
      return const AnnouncePlan(voices: [StateVoice.prepare], key: 'prepare');
    case PhaseType.work:
      if (isFinalRoundOfSession) {
        // '운동 시작' + '마지막 라운드' 를 한 파일로 합쳐 둔 것
        return const AnnouncePlan(
          sfx: Sfx.work,
          voices: [StateVoice.startWork, StateVoice.lastRound],
          key: 'workLast',
        );
      }
      return const AnnouncePlan(
        sfx: Sfx.work,
        voices: [StateVoice.startWork],
        key: 'startWork',
      );
    case PhaseType.rest:
      return const AnnouncePlan(
        sfx: Sfx.rest,
        voices: [StateVoice.startRest],
        key: 'startRest',
      );
    case PhaseType.setRest:
      return const AnnouncePlan(
        sfx: Sfx.rest,
        voices: [StateVoice.setRest],
        key: 'setRest',
      );
  }
}

/// 종료 안내 계획
const AnnouncePlan finishPlan = AnnouncePlan(
  sfx: Sfx.finish,
  voices: [StateVoice.finish],
  key: 'finish',
);

// --- 안내 시각표 -----------------------------------------------------------

/// 안내 시퀀스의 절대 시각표.
///
/// 실제 재생은 **파일 하나**지만, 카운트다운 보호구간을 계산하려면 각 음성이
/// 파일 안에서 몇 ms 에 시작하는지 알아야 한다. 파일을 만들 때 쓴 간격과
/// 아래 계산이 같으므로 어긋날 수 없다.
class AnnounceTiming {
  const AnnounceTiming({
    this.attention,
    this.voiceStartsAt = const <int>[],
    this.totalMs = 0,
    this.sequence,
  });

  /// 실제로 울릴 주의음 (음성 유무에 따라 달라진다)
  final Sfx? attention;

  /// 각 음성이 시작되는 시각(시퀀스 시작 = 0ms 기준)
  final List<int> voiceStartsAt;

  /// 시퀀스 전체 길이(ms)
  final int totalMs;

  /// 재생할 시퀀스 자산 (음성이 켜져 있을 때)
  final String? sequence;

  bool get hasVoice => voiceStartsAt.isNotEmpty;
}

AnnounceTiming announceTiming(
  AnnouncePlan plan,
  VoiceStyle style, {
  required bool sfxEnabled,
  required bool voiceEnabled,
}) {
  final hasVoice = voiceEnabled && plan.voices.isNotEmpty;

  // 음성이 없으면 단독 주의음을 그대로 낸다 (삐-삐- 온전히).
  if (!hasVoice) {
    final attention = sfxEnabled ? plan.sfx : null;
    return AnnounceTiming(
      attention: attention,
      totalMs: attention?.durationMs ?? 0,
    );
  }

  // 음성이 있으면 파일 하나에 삑 + 음성이 들어 있다.
  final starts = <int>[];
  var at = sfxEnabled
      ? beepLeadMs + attentionGapMs
      : silenceStartMs;
  for (final v in plan.voices) {
    starts.add(at);
    at = at + stateVoiceDurationMs(style, v) + voiceToVoiceGapMs;
  }

  final total = _seqDurMs[style.assetKey]?[plan.key] ??
      (at - voiceToVoiceGapMs);

  return AnnounceTiming(
    attention: sfxEnabled ? Sfx.beep : null,
    voiceStartsAt: starts,
    totalMs: total,
    sequence: plan.seqAssetFor(style),
  );
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
  final String kind; // 'seq' | 'sfx' | 'count' | 'preview'
  final String? phaseType;

  @override
  String toString() => 'PlayLog($kind $asset @${wallMs % 100000})';
}

// ===========================================================================
// AudioCoach
// ===========================================================================

enum _Role { seq, sfx, count, preview }

/// 사운드 출력 담당.
///
/// ## 끊김을 없애는 핵심 원칙
///
/// 1. **안내 한 번 = 파일 하나 = `resume()` 한 번.**
///    예전에는 `삑 → 90ms 대기 → 음성` 을 파일 2개로 이어 붙였다. 파일을
///    바꿀 때마다 `stop → seek → resume` 이 필요하고, 그 사이에 오디오
///    장치가 비면서 '뚝, 뚝' 끊겼다. 이제 그 간격까지 미리 합쳐 둔
///    `seq_*.wav` 하나만 재생하므로 **끊길 구간 자체가 없다.**
///
/// 2. **카운트다운 5·4·3·2·1 도 파일 하나.**
///    초마다 다른 파일을 재생하던 것을 1초 간격이 새겨진 `cnt_*.wav`
///    하나로 바꿨다. 숫자 사이 간격이 ±1ms 로 고정된다.
///
/// 3. **오디오 포커스를 요청하지 않는다.**
///    audioplayers 의 FocusManager 는 포커스를 새로 얻은 플레이어가 생기면
///    **이전 플레이어를 pause()** 시킨다. 자산마다 플레이어를 쓰는 구조에서
///    이 동작은 다른 소리를 중간에 잘라먹는다. `audioFocus: none` 으로
///    요청 자체를 하지 않는다.
///
/// 4. **모든 오디오 작업에 타임아웃.**
///    한 번 멈춘 플레이어가 영구히 무음이 되어 '누락'이 되던 문제를 막는다.
///
/// 5. **역할별 단일 슬롯 + 세대 번호.**
///    일시정지/건너뛰기/구간 전환 시 이전 재생을 확실히 끊고, 뒤늦게
///    도착한 재생 요청은 스스로 폐기된다.
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

  int _epoch = 0;
  final Map<_Role, int> _roleSeq = <_Role, int>{};
  final Map<_Role, String> _current = <_Role, String>{};
  final Map<String, AudioPlayer> _players = <String, AudioPlayer>{};
  final Map<String, Future<AudioPlayer>> _preparing =
      <String, Future<AudioPlayer>>{};
  final Map<String, Future<void>> _opChain = <String, Future<void>>{};

  bool _ready = false;
  bool get isReady => _ready;

  final List<PlayLogEntry> playLog = <PlayLogEntry>[];

  AudioContextAndroid? _androidContext;

  /// 모든 오디오 작업의 상한. 넘으면 포기하고 다음 요청을 받는다.
  static const Duration _opTimeout = Duration(milliseconds: 2500);

  Future<void> init() async {
    _ready = true;
    // 오디오 포커스를 요청하지 않는다 (위 설명 3번).
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
      await AudioPlayer.global
          .setAudioContext(AudioContext(android: android))
          .timeout(_opTimeout);
    } catch (e) {
      if (kDebugMode) debugPrint('setAudioContext failed: $e');
    }
  }

  // ------------------------------------------------------------- 로딩

  bool _isVoiceAsset(String asset) =>
      asset.contains('st_') ||
      asset.contains('seq_') ||
      asset.contains('vox_') ||
      asset.contains('cnt_') ||
      asset.contains('c_') ||
      asset.contains('preview_');

  double _volumeFor(String asset) =>
      _isVoiceAsset(asset) ? voiceVolume : sfxVolume;

  Future<AudioPlayer> _ensure(String asset) {
    final existing = _preparing[asset];
    if (existing != null) return existing;

    final player = AudioPlayer();
    _players[asset] = player; // ← 첫 await 이전에 등록
    final future = _preparePlayer(player, asset);
    _preparing[asset] = future;
    return future;
  }

  Future<AudioPlayer> _preparePlayer(AudioPlayer p, String asset) async {
    try {
      final ctx = _androidContext;
      if (ctx != null) {
        try {
          await p
              .setAudioContext(AudioContext(android: ctx))
              .timeout(_opTimeout);
        } catch (_) {}
      }
      await p.setReleaseMode(ReleaseMode.stop).timeout(_opTimeout);
      await p.setVolume(_volumeFor(asset)).timeout(_opTimeout);
      await p.setSource(AssetSource(asset)).timeout(_opTimeout);
    } catch (e) {
      if (kDebugMode) debugPrint('audio prepare failed($asset): $e');
    }
    return p;
  }

  void _applyVolumes() {
    for (final e in _players.entries) {
      e.value
          .setVolume(_volumeFor(e.key))
          .timeout(_opTimeout)
          .catchError((_) {});
    }
  }

  /// 자산별로 작업을 한 줄로 세운다 (같은 플레이어에 동시 명령 금지).
  Future<void> _serial(String asset, Future<void> Function(AudioPlayer) op) {
    final prev = _opChain[asset];
    final completer = Completer<void>();
    final mine = completer.future;
    _opChain[asset] = mine;

    Future<void> run() async {
      if (prev != null) {
        try {
          await prev.timeout(_opTimeout);
        } catch (_) {}
      }
      try {
        final p = await _ensure(asset);
        await op(p).timeout(_opTimeout);
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

  /// 재생에 쓸 자산을 미리 준비한다 (첫 소리 지연 제거).
  Future<void> warmUp() async {
    if (!_anySound) return;
    final assets = <String>{};
    assets.addAll(Sfx.values.map((s) => s.asset));
    for (final key in _seqDurMs[voiceStyle.assetKey]!.keys) {
      assets.add('audio/seq_${voiceStyle.assetKey}_$key.wav');
    }
    assets.add('audio/cnt_${voiceStyle.assetKey}.wav');
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

  /// 역할 재생 — 첫 await 이전에 슬롯을 점유한다.
  ///
  /// [startAtMs] 를 주면 파일의 그 지점부터 재생한다 (카운트다운 묶음에서
  /// 앞 숫자를 건너뛸 때 사용).
  Future<void> _playRole(
    _Role role,
    String asset,
    int epoch, {
    String? phaseType,
    int startAtMs = 0,
  }) async {
    final seq = (_roleSeq[role] ?? 0) + 1;
    _roleSeq[role] = seq;
    final prevAsset = _current[role];
    _current[role] = asset;
    if (prevAsset != null && prevAsset != asset) {
      unawaited(_serial(prevAsset, (p) => p.stop()));
    }

    bool stale() => epoch != _epoch || _roleSeq[role] != seq;

    await _serial(asset, (p) async {
      if (stale()) return;
      await p.stop();
      if (stale()) return;
      await p.setVolume(_volumeFor(asset));
      if (startAtMs > 0) {
        await p.seek(Duration(milliseconds: startAtMs));
      } else {
        await p.seek(Duration.zero);
      }
      if (stale()) return;
      await p.resume();
      if (!stale()) _log(asset, role, phaseType: phaseType);
    });
  }

  void _stopRole(_Role role) {
    _roleSeq[role] = (_roleSeq[role] ?? 0) + 1;
    final cur = _current.remove(role);
    if (cur == null) return;
    unawaited(_serial(cur, (p) => p.stop()));
  }

  // ------------------------------------------------------------- 공개 API

  /// 구간 전환 안내.
  ///
  /// 음성이 켜져 있으면 `seq_*.wav` 하나를 재생한다 (삑 + 음성이 이미 합쳐짐).
  /// 음성이 꺼져 있으면 단독 주의음(삐-삐-)만 낸다.
  void announce(AnnouncePlan plan, {String? phaseType}) {
    _epoch++;
    for (final r in _Role.values) {
      _stopRole(r);
    }
    if (!_anySound) return;
    final epoch = _epoch;

    final hasVoice = voiceEnabled && plan.voices.isNotEmpty;

    if (!hasVoice) {
      final attention = sfxEnabled ? plan.sfx : null;
      if (attention == null) return;
      unawaited(
        _playRole(_Role.sfx, attention.asset, epoch, phaseType: phaseType),
      );
      return;
    }

    // 파일 하나만 재생한다. 효과음을 껐으면 앞의 '삑' 구간을 건너뛴다.
    final asset = plan.seqAssetFor(voiceStyle);
    final startAt = sfxEnabled ? 0 : beepLeadMs + attentionGapMs;
    unawaited(
      _playRole(
        _Role.seq,
        asset,
        epoch,
        phaseType: phaseType,
        startAtMs: startAt,
      ),
    );
  }

  /// 마지막 5초 카운트다운 — 묶음 파일 하나를 [fromNumber] 초 지점부터 재생.
  ///
  /// 묶음 파일 안에서 숫자 사이 간격이 정확히 1초이므로, 초마다 파일을
  /// 갈아 끼우던 예전 방식과 달리 간격이 흔들리지 않는다.
  void playCountBundle({required int fromNumber}) {
    if (!_anySound) return;
    final n = fromNumber.clamp(1, 5);
    _epoch++; // 진행 중인 안내/카운트는 정리
    for (final r in _Role.values) {
      _stopRole(r);
    }
    final epoch = _epoch;

    if (!voiceEnabled) {
      // 음성이 꺼져 있으면 묶음 대신 매초 틱을 쓰므로 여기선 아무것도 안 함.
      return;
    }

    final offset = (5 - n) * 1000;
    unawaited(
      _playRole(
        _Role.count,
        'audio/cnt_${voiceStyle.assetKey}.wav',
        epoch,
        startAtMs: offset,
      ),
    );
  }

  /// 음성이 꺼진 상태의 1초 틱.
  void playCount(int n) {
    if (!_anySound) return;
    if (!voiceEnabled) {
      if (sfxEnabled) playSfx(Sfx.count);
      return;
    }
    // 묶음 재생을 쓰지 않는 경로(백그라운드 복귀 등)를 위한 단일 숫자.
    final epoch = _epoch;
    unawaited(
      _playRole(
        _Role.count,
        'audio/c_${voiceStyle.assetKey}_$n.wav',
        epoch,
      ),
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
  /// 실제 재생에 쓰는 **시퀀스 파일 그대로** 들려준다 → 미리 듣는 소리와
  /// 실제 운동 중 소리가 어긋날 수 없다.
  Future<void> previewVoice(VoiceStyle style) async {
    if (!_anySound) return;
    _epoch++;
    for (final r in _Role.values) {
      _stopRole(r);
    }
    final epoch = _epoch;

    final asset = 'audio/seq_${style.assetKey}_startWork.wav';
    final startAt = sfxEnabled ? 0 : beepLeadMs + attentionGapMs;
    unawaited(
      _playRole(_Role.preview, asset, epoch, startAtMs: startAt),
    );
  }

  /// 설정 화면 '효과음 미리 듣기'.
  Future<void> previewSfx(Sfx sfx) async {
    if (!_anySound) return;
    final epoch = _epoch;
    await _playRole(_Role.preview, sfx.asset, epoch);
  }

  /// 재생 중인 모든 소리를 즉시 무효화하고 멈춘다.
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
        await p.stop().timeout(_opTimeout);
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
    _preparing.clear();
    _opChain.clear();
  }
}
