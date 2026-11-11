import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/phase.dart';
import '../models/tabata_config.dart';
import 'web_audio.dart';

// ===========================================================================
// 효과음
// ===========================================================================

enum Sfx {
  /// 운동 구간 주의음 — 높은 음 '삐-삐-' (840ms)
  work('audio/sfx_work.wav', 840),

  /// 휴식 구간 주의음 — 낮은 음 '삐-삐-' (840ms)
  rest('audio/sfx_rest.wav', 840),

  /// 전체 종료 — 세 번 상승 (1220ms)
  finish('audio/sfx_finish.wav', 1220),

  /// 짧은 주의음 '삑' (130ms)
  beep('audio/beep.wav', 130),

  /// 매초 시간을 알리는 또렷한 틱 (110ms)
  count('audio/sfx_count.wav', 110);

  const Sfx(this.asset, this.durationMs);

  final String asset;
  final int durationMs;
}

// ===========================================================================
// 안내 음성
// ===========================================================================

enum StateVoice {
  prepare('prepare'),
  startWork('startWork'),
  startRest('startRest'),
  setRest('setRest'),
  lastRound('lastRound'),
  finish('finish');

  const StateVoice(this.key);
  final String key;

  String assetFor(VoiceStyle style) => 'audio/st_${style.assetKey}_$key.wav';
}

/// 삑 소리와 음성 사이 간격 (파일 생성 시 쓴 값과 동일해야 한다)
///
/// v3 에서 90ms → 180ms 로 늘렸다. 이전에는 삑이 끝나자마자 음성이
/// 붙어서 '툭' 하고 튀는 느낌이 있었다. 사람이 숨을 한 번 쉬는
/// 정도의 틈을 두면 훨씬 자연스럽게 이어진다.
const int attentionGapMs = 180;

/// 음성과 음성 사이 간격
///
/// v3 에서 110ms → 300ms. '운동 시작' 과 '마지막 라운드' 처럼 두 문장이
/// 연달아 나올 때, 이전에는 거의 붙어 있어서 두 번째 문장이 급하게
/// 들렸다.
const int voiceToVoiceGapMs = 300;

/// 주의음 없이 음성만 시작할 때의 지연
const int silenceStartMs = 40;

/// 시퀀스를 합칠 때 쓰는 크로스페이드 길이 (파일 생성용)
const int crossfadeMs = 6;

/// 안내가 끝난 뒤 카운트다운 숫자를 허용하기까지의 여유
const int guardPaddingMs = 240;

/// 시퀀스 파일 앞부분의 '삑' 길이 (ms)
const int beepLeadMs = 130;

/// 목소리별 상태 안내 **음성만의** 길이(ms)
///
/// v4 실측값 — tool/voice_pipeline.py 산출.
/// 잘림 0ms, 앞 무음 제거. 발성은 클립 시작 0~10ms 안에 시작한다.
const Map<VoiceStyle, Map<StateVoice, int>> _stDurationMs = {
  VoiceStyle.male: {
    // v18 스포츠 MC — 앞 무음 제거 실측 (tool/fix_v18_onset.py)
    StateVoice.prepare: 464,
    StateVoice.startWork: 974,
    StateVoice.startRest: 905,
    StateVoice.setRest: 961,
    StateVoice.lastRound: 1009,
    StateVoice.finish: 940,
  },
  VoiceStyle.female: {
    StateVoice.prepare: 520,
    StateVoice.startWork: 939,
    StateVoice.startRest: 947,
    StateVoice.setRest: 834,
    StateVoice.lastRound: 1012,
    StateVoice.finish: 1006,
  },
  VoiceStyle.baby: {
    StateVoice.prepare: 456,
    StateVoice.startWork: 958,
    StateVoice.startRest: 823,
    StateVoice.setRest: 1018,
    StateVoice.lastRound: 985,
    StateVoice.finish: 883,
  },
};

int stateVoiceDurationMs(VoiceStyle style, StateVoice v) =>
    _stDurationMs[style]?[v] ?? 900;

/// 안내 시퀀스 파일의 **실제 길이**(ms) — tool/build_sequences.py 산출값.
///
/// v4: 겹침 없는 이어붙이기, 간격 180/300ms, 삑 RMS 0.24.
const Map<String, Map<String, int>> seqDurMs = {
  'male': {
    // v18 스포츠 MC 픽스 (구절 단위 재생성, 음성 인식 기준 분할)
    'prepare': 775,
    'startWork': 1283,
    'startRest': 1215,
    'setRest': 1271,
    'lastRound': 1334,
    'finish': 1251,
    'workLast': 2663,
  },
  'female': {
    // v18c 부드러운 30대 여성 (구절 단위 재생성, 음성 인식 기준 분할)
    'prepare': 830,
    'startWork': 1249,
    'startRest': 1256,
    'setRest': 1146,
    'lastRound': 1322,
    'finish': 1316,
    'workLast': 2619,
  },
  'baby': {
    'prepare': 766,
    'startWork': 1268,
    'startRest': 1133,
    'setRest': 1328,
    'lastRound': 1295,
    'finish': 1193,
    'workLast': 2553,
  },
};

/// 5·4·3·2·1 이 1초 간격으로 들어 있는 묶음 파일의 길이(ms)
const Map<String, int> cntDurMs = {'male': 4386, 'female': 4453, 'baby': 4388};

/// 묶음 안에서 숫자 '5' 가 시작하는 위치 = 0ms.
/// 숫자 간격은 정확히 1초, 마지막 숫자 '1' 은 4000ms 에서 시작한다.
const int countStepMs = 1000;

/// 마지막 숫자 '1' 의 시작 위치(ms)
const int countBundleLastMs = 4 * countStepMs;

// ===========================================================================
// 구간 → 안내 계획
// ===========================================================================

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

  String seqAssetFor(VoiceStyle style) =>
      'audio/seq_${style.assetKey}_$key.wav';

  @override
  String toString() =>
      'AnnouncePlan(key: $key, sfx: ${sfx?.name}, '
      'voices: ${voices.map((v) => v.key).join(',')})';
}

/// 구간 → 안내 계획 (순수 함수).
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

class AnnounceTiming {
  const AnnounceTiming({
    this.attention,
    this.voiceStartsAt = const <int>[],
    this.totalMs = 0,
    this.sequence,
  });

  final Sfx? attention;
  final List<int> voiceStartsAt;
  final int totalMs;
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

  if (!hasVoice) {
    final attention = sfxEnabled ? plan.sfx : null;
    return AnnounceTiming(
      attention: attention,
      totalMs: attention?.durationMs ?? 0,
    );
  }

  final starts = <int>[];
  var at = sfxEnabled ? beepLeadMs + attentionGapMs : silenceStartMs;
  for (final v in plan.voices) {
    starts.add(at);
    at = at + stateVoiceDurationMs(style, v) + voiceToVoiceGapMs;
  }

  final total = seqDurMs[style.assetKey]?[plan.key] ?? (at - voiceToVoiceGapMs);

  return AnnounceTiming(
    attention: sfxEnabled ? Sfx.beep : null,
    voiceStartsAt: starts,
    totalMs: total,
    sequence: plan.seqAssetFor(style),
  );
}

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
  final String kind;
  final String? phaseType;

  @override
  String toString() => 'PlayLog($kind $asset @${wallMs % 100000})';
}

// ===========================================================================
// 채널 — 역할마다 **플레이어 정확히 1개**
// ===========================================================================

/// 한 역할(안내 / 카운트 / 효과음 / 미리듣기)을 담당하는 채널.
///
/// ## 왜 자산별이 아니라 역할별인가 (겹침의 근본 원인 제거)
///
/// 예전 구조는 오디오 파일마다 플레이어를 따로 만들었다. 그러면
/// "이전 파일을 멈춰라" 라는 요청이 **어느 플레이어를 멈춰야 하는지**
/// 놓칠 수 있고, 놓친 플레이어는 계속 재생되어 다음 소리와 겹친다.
///
/// 역할마다 플레이어가 하나뿐이면 `stop()` 한 번이 그 역할의 소리를
/// **무조건** 침묵시킨다. 겹칠 플레이어가 존재하지 않는다.
///
/// ## 중복 재생 방지
/// [_gen] 세대 번호를 첫 줄에서 **동기적으로** 올린다. 이미 진행 중이던
/// 재생 시퀀스는 다음 await 에서 자기 세대가 바뀐 것을 확인하고 스스로
/// 중단한다. (await 뒤에 점유하던 이전 구조의 경쟁 조건 제거)
class _Channel {
  _Channel(this.label);

  final String label;

  /// 플레이어는 **실제로 소리를 낼 때** 만든다.
  ///
  /// 싱글턴 생성 시점에 만들면, 오디오 플러그인이 없는 환경(단위 테스트)에서
  /// `MissingPluginException` 으로 앱 전체가 죽는다. 소리를 끈 상태의
  /// 테스트·미리보기에서도 안전해야 하므로 지연 생성한다.
  AudioPlayer? _player;
  bool _failed = false;

  AudioPlayer? _ensurePlayer() {
    if (_player != null || _failed) return _player;
    try {
      // `AudioPlayer()` 는 생성자 안에서 `_create()` 를 **비동기로** 던진다.
      // 플러그인이 없는 환경(단위 테스트)에서는 그 Future 가
      // `MissingPluginException` 으로 완료되는데, 이를 그대로 두면
      // **잡히지 않은 비동기 예외**가 되어 테스트·앱이 죽는다.
      // 존 가드로 감싸 실패를 값으로 바꾼다.
      runZonedGuarded(
        () {
          _player = AudioPlayer();
        },
        (e, s) {
          _failed = true;
          _player = null;
          if (kDebugMode) debugPrint('[$label] player creation failed: $e');
        },
      );
    } catch (e) {
      _failed = true;
      _player = null;
      if (kDebugMode) debugPrint('[$label] player creation failed: $e');
    }
    return _player;
  }

  static const Duration _t = Duration(milliseconds: 2500);

  int _gen = 0;
  bool _configured = false;

  /// 이 채널이 실제로 어떤 자산을 재생 중인가 (null = 없음).
  String? _playingAsset;

  /// 마지막으로 설정한 볼륨 — 매 재생마다 platform call 하지 않기 위해 캐시.
  double? _volume;

  /// 소스가 이미 준비되어 있고 **이어붙이기(seek)만** 하면 되는 상태.
  ///
  /// 카운트다운 묶음은 구간 1회 시작 후 최대 4초간 재생된다. 그 사이에
  /// 새 재생이 걸리면(= 같은 파일을 타임라인 위치에서 다시 걸 때) 소스를
  /// 교체하지 않고 `seek` 만 하면 이어지므로 끊김이 없다.
  bool _sourceLoaded = false;

  /// 리소스 준비(모바일). 캐시 목적으로 미리 불러 둔다.
  Future<void> preload(String asset) async {
    if (AudioCoach._web.available) return;
    if (_sourceLoaded && _playingAsset == asset) return;
    final player = _ensurePlayer();
    if (player == null) return;
    try {
      await player.setSource(AssetSource(asset)).timeout(_t);
      if (player.state != PlayerState.playing) {
        // 준비만 하고 재생하지 않는다.
        await player.stop().timeout(_t);
      }
      _playingAsset = asset;
      _sourceLoaded = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[$label] preload failed($asset): $e');
    }
  }

  /// 같은 채널에 새 재생이 걸리면 이전 재생은 폐기된다.
  ///
  /// ## 왜 async 체인을 없앴는가 (v5 핵심 수정)
  ///
  /// 예전 구현은 `stop → setVolume → setSource → seek → resume` 을 **모두
  /// await** 했다. 모바일에서는 각 호출이 platform channel 왕복이고,
  /// `setSource` 는 자산 디코딩까지 기다린다. 그 사이 마이크로태스크가
  /// 끼어들어 카운트다운 묶음이 실제로 재생을 시작하는 시점이
  /// **벽시계 기준보다 늦어진다** → 숫자가 밀려서 들린다.
  ///
  /// 지금은:
  ///   * 같은 파일이 이어지는 중이면 `seek` 만 한다 (소스 교체 없음 → 무끊김)
  ///   * 볼륨은 값이 바뀔 때만 보낸다 (platform 왕복 절반)
  ///   * `resume()` 만 await 한다 (실제 시작 시각을 보장해야 하는 유일한 호출)
  Future<void> play(
    String asset, {
    int startAtMs = 0,
    required double volume,
  }) async {
    final gen = ++_gen; // ← 동기 구간: 즉시 이전 재생 무효화

    // ── 웹: 사전 디코딩된 AudioBuffer 로 정확히 재생한다 ──────────────
    //
    // audioplayers_web 은 플레이어마다 AudioContext 를 만들고, 그 컨텍스트가
    // 사용자 제스처 없이 생성되면 잠겨서 **소리가 아예 나지 않는다.**
    // (공유 링크를 받은 사람의 기기에서 무음이던 원인)
    if (AudioCoach._web.available) {
      final ok = AudioCoach._web.play(
        asset,
        role: label,
        volume: volume,
        offsetMs: startAtMs,
        interrupt: true,
      );
      if (!ok && kDebugMode) {
        debugPrint('[$label] web play skipped($asset): not ready/locked');
      }
      return;
    }

    final player = _ensurePlayer();
    if (player == null) return;

    final sameSource = _sourceLoaded && _playingAsset == asset;
    final needsVolume = _volume != volume;

    try {
      if (sameSource) {
        // ── 이어붙이기 경로: 소스를 건드리지 않는다 ───────────────────
        // 카운트다운 묶음을 타임라인 위치로 다시 거는 경우가 여기 해당.
        // setSource 를 하지 않으므로 디코딩 대기·끊김이 없다.
        if (needsVolume) {
          _volume = volume;
          await player.setVolume(volume).timeout(_t);
          if (gen != _gen) return;
        }
        await player.seek(Duration(milliseconds: startAtMs)).timeout(_t);
        if (gen != _gen) return;
        await player.resume().timeout(_t);
        return;
      }

      // ── 새 소스 경로 ────────────────────────────────────────────────
      _playingAsset = asset;
      _sourceLoaded = false;

      if (needsVolume) {
        _volume = volume;
        await player.setVolume(volume).timeout(_t);
        if (gen != _gen) return;
      }

      await player.setSource(AssetSource(asset)).timeout(_t);
      if (gen != _gen) return;
      _sourceLoaded = true;

      if (startAtMs > 0) {
        await player.seek(Duration(milliseconds: startAtMs)).timeout(_t);
        if (gen != _gen) return;
      }

      await player.resume().timeout(_t);
    } catch (e) {
      _sourceLoaded = false;
      if (kDebugMode) debugPrint('[$label] play failed($asset): $e');
    }
  }

  /// 웹 전용: 동기적으로 재생을 시도하고 성공 여부를 돌려준다.
  /// 같은 역할의 이전 재생은 브리지가 먼저 정지시킨다 (interrupt).
  bool webPlayNow(
    String asset, {
    required int startAtMs,
    required double volume,
  }) {
    _gen++;
    return AudioCoach._web.play(
      asset,
      role: label,
      volume: volume,
      offsetMs: startAtMs,
      interrupt: true,
    );
  }

  /// 즉시 침묵. 세대를 올려 진행 중이던 재생도 함께 폐기한다.
  void stop() {
    _gen++;
    // 소스는 그대로 두어, 같은 파일을 다시 걸 때 seek 만으로 이어지게 한다.
    if (AudioCoach._web.available) {
      AudioCoach._web.stopRole(label);
      return;
    }
    final player = _player;
    if (player == null) return;
    unawaited(player.stop().timeout(_t).catchError((_) {}));
  }

  /// 소스 캐시까지 버린다 (목소리가 바뀌었을 때).
  void resetSource() {
    stop();
    _playingAsset = null;
    _sourceLoaded = false;
  }

  Future<void> configure(AudioContextAndroid? ctx) async {
    final player = _ensurePlayer();
    if (player == null) return;
    if (_configured) return;
    _configured = true;
    try {
      if (ctx != null) {
        await player.setAudioContext(AudioContext(android: ctx)).timeout(_t);
      }
      await player.setReleaseMode(ReleaseMode.stop).timeout(_t);
    } catch (e) {
      if (kDebugMode) debugPrint('[$label] configure failed: $e');
    }
  }

  Future<void> dispose() async {
    _gen++;
    final player = _player;
    if (player == null) return;
    try {
      await player.dispose();
    } catch (_) {}
  }
}

// ===========================================================================
// AudioCoach
// ===========================================================================

/// 사운드 출력 담당.
///
/// ## 끊김·겹침·누락을 막는 구조
///
/// 1. **역할 = 플레이어 1개.** 안내/카운트/효과음/미리듣기가 각각 플레이어
///    하나만 쓴다. 멈추라는 요청이 대상을 놓칠 수 없다. (겹침 제거)
/// 2. **안내 한 번 = 파일 하나 = `resume()` 한 번.** 삑과 음성 사이 간격까지
///    미리 합쳐 둔 `seq_*.wav` 를 쓴다. 파일 교체가 없으니 끊길 구간이 없다.
/// 3. **카운트다운도 파일 하나.** 5·4·3·2·1 이 1초 간격으로 녹음된
///    `cnt_*.wav` 를 '가장 먼저 울릴 숫자' 지점부터 한 번만 재생한다.
/// 4. **오디오 포커스를 요청하지 않는다.** 요청하면 앞 소리가 pause 된다.
/// 5. **모든 작업에 타임아웃.** 멈춘 플레이어가 영구 무음이 되지 않는다.
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
    voiceStyle = c.voiceStyle;
    if (styleChanged) {
      _seq.resetSource();
      _count.resetSource();
      _preview.resetSource();
    }
  }

  // ------------------------------------------------------------- 채널

  final _Channel _seq = _Channel('seq');
  final _Channel _count = _Channel('count');
  final _Channel _sfx = _Channel('sfx');
  final _Channel _preview = _Channel('preview');

  /// 웹 전용 오디오 브리지 (모바일에서는 스텁).
  ///
  /// 웹은 audioplayers 를 쓰지 않는다. 이유는 `web/audio_bridge.js` 참고:
  ///   * 플레이어마다 AudioContext 가 생겨 Safari 동시 개수 제한에 걸리고
  ///   * 사용자 제스처 없이 만든 컨텍스트가 'suspended' 로 잠겨 **완전 무음**
  ///   * HTMLAudioElement 지연 때문에 1초 카운트다운이 부정확
  static const _web = WebAudio();

  bool _ready = false;
  bool get isReady => _ready;

  /// 오디오가 지금 소리를 낼 수 있는 상태인가.
  ///
  /// * 웹: 브라우저 AudioContext 잠금이 풀렸는지 확인
  /// * 모바일/테스트: 잠금 개념이 없으므로 항상 true
  bool get isUnlocked => _web.available ? _web.unlocked : true;

  /// 웹 브리지를 실제로 쓰고 있는가 (진단용)
  bool get isWebBridge => _web.available;

  /// 사전 로딩이 끝나 즉시 재생 가능한가
  bool get isPreloaded => _preloaded;

  bool _preloaded = false;

  final List<PlayLogEntry> playLog = <PlayLogEntry>[];

  Future<void> init() async {
    _ready = true;
    // 오디오 포커스를 요청하지 않는다.
    // 요청하면 audioplayers 가 "새 플레이어가 포커스를 얻었다" 고 판단해
    // 이전 플레이어를 pause() 시킨다 → 소리가 중간에 잘린다.
    const android = AudioContextAndroid(
      isSpeakerphoneOn: false,
      audioMode: AndroidAudioMode.normal,
      stayAwake: false,
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.none,
    );
    try {
      await AudioPlayer.global
          .setAudioContext(AudioContext(android: android))
          .timeout(const Duration(milliseconds: 2500));
    } catch (e) {
      if (kDebugMode) debugPrint('setAudioContext failed: $e');
    }
    await Future.wait([
      _seq.configure(android),
      _count.configure(android),
      _sfx.configure(android),
      _preview.configure(android),
    ]);
  }

  /// 첫 사용자 제스처에서 호출 — 웹 오디오 잠금을 푼다.
  ///
  /// 브라우저는 제스처 없이 만든 AudioContext 를 잠근다. 이 호출 없이는
  /// **링크를 받은 사람의 기기에서 소리가 전혀 나지 않는다.**
  Future<bool> unlock() async {
    if (!_web.available) return true;
    return _web.unlock();
  }

  /// 세션 시작 전에 이번 목소리로 쓸 모든 파일을 미리 받아 둔다.
  ///
  /// 재생 요청 시점에 파일을 받으면 첫 음이 늦게 나오고, 준비 안 된
  /// 상태에서 타이머가 먼저 흘러가 카운트다운이 어긋난다.
  Future<void> preloadForSession({VoiceStyle? style}) async {
    if (!_web.available) {
      // 모바일은 warmUp() 이 실제 소스 준비까지 담당한다.
      _preloaded = true;
      return;
    }
    final s = style ?? voiceStyle;
    final assets = <String>{};
    assets.addAll(Sfx.values.map((e) => e.asset));
    for (final key in seqDurMs[s.assetKey]!.keys) {
      assets.add('audio/seq_${s.assetKey}_$key.wav');
    }
    assets.add('audio/cnt_v7_${s.assetKey}.wav');
    for (var n = 1; n <= 5; n++) {
      assets.add('audio/c_${s.assetKey}_$n.wav');
      assets.add('audio/st_${s.assetKey}_${_stateKeys[n - 1]}.wav');
    }
    final ok = await _web.preload(assets.toList());
    _preloaded = ok > 0 || assets.isEmpty;
    if (kDebugMode) {
      debugPrint('preload: $ok/${assets.length} ready');
    }
  }

  static const List<String> _stateKeys = [
    'prepare',
    'startWork',
    'startRest',
    'setRest',
    'lastRound',
    'finish',
  ];

  /// 첫 소리 지연을 줄이기 위한 준비. 채널은 이미 만들어져 있으므로
  /// 여기서는 존재하는 파일만 확인한다.
  Future<void> warmUp() async {
    if (!_anySound) return;
    // 웹은 실제로 파일을 받아 디코딩해 둔다 (재생 지연·누락 방지).
    // 모바일은 플레이어가 이미 준비되어 있으므로 계정만 확인한다.
    if (_web.available) {
      await preloadForSession();
      return;
    }
    // 모바일: 실제로 소스를 미리 열어 둔다.
    //
    // 예전에는 로그만 찍고 아무것도 하지 않았다. 그래서 첫 안내에서
    // `setSource` 가 자산 디코딩까지 기다리며 **첫 음이 늦게** 났고,
    // 구간이 바뀔 때마다 그 지연이 반복됐다.
    final assets = <String>{};
    assets.addAll(Sfx.values.map((s) => s.asset));
    final map = seqDurMs[voiceStyle.assetKey];
    if (map != null) {
      for (final key in map.keys) {
        assets.add('audio/seq_${voiceStyle.assetKey}_$key.wav');
      }
    }
    assets.add('audio/cnt_v7_${voiceStyle.assetKey}.wav');
    // 가장 먼저 울릴 '준비' 안내와 카운트다운 묶음은 반드시 준비해 둔다.
    await _seq.preload('audio/seq_${voiceStyle.assetKey}_prepare.wav');
    await _count.preload('audio/cnt_v7_${voiceStyle.assetKey}.wav');
    await _sfx.preload(Sfx.work.asset);
    if (kDebugMode) debugPrint('warmUp: ${assets.length} assets ready');
  }

  void _log(String asset, String kind, {String? phaseType}) {
    if (!kDebugMode) return;
    playLog.add(
      PlayLogEntry(
        asset: asset,
        wallMs: DateTime.now().millisecondsSinceEpoch,
        kind: kind,
        phaseType: phaseType,
      ),
    );
    if (playLog.length > 400) playLog.removeAt(0);
  }

  // ------------------------------------------------------------- 공개 API

  /// 구간 전환 안내.
  ///
  /// 먼저 **진행 중인 모든 소리를 즉시 멈춘다** → 다음 구간으로 넘어갈 때
  /// 이전 구간의 음성이 남아 겹치는 일이 없다.
  void announce(AnnouncePlan plan, {String? phaseType}) {
    _seq.stop();
    _count.stop();
    if (!_anySound) return;

    final hasVoice = voiceEnabled && plan.voices.isNotEmpty;

    if (!hasVoice) {
      final attention = sfxEnabled ? plan.sfx : null;
      if (attention == null) return;
      _sfx.play(attention.asset, volume: sfxVolume);
      _log(attention.asset, 'sfx', phaseType: phaseType);
      return;
    }

    // 파일 하나만 재생한다. 효과음을 껐으면 앞의 '삑' 구간을 건너뛴다.
    final asset = plan.seqAssetFor(voiceStyle);
    final startAt = sfxEnabled ? 0 : beepLeadMs + attentionGapMs;
    _seq.play(asset, startAtMs: startAt, volume: voiceVolume);
    _log(asset, 'seq', phaseType: phaseType);
  }

  /// 마지막 5초 카운트다운 — 묶음 파일을 [fromNumber] 지점부터 한 번 재생.
  ///
  /// 파일 안에서 숫자 사이 간격이 정확히 1초이므로 흔들리지 않는다.
  /// **안내 채널은 건드리지 않는다** (진행 중인 안내를 끊지 않기 위해).
  void playCountBundle({required int fromNumber}) {
    final n = fromNumber.clamp(1, 5);
    playCountBundleAt((5 - n) * 1000);
  }

  /// 묶음 파일을 **타임라인 위치(ms)** 에서 재생한다.
  ///
  /// 묶음 타임라인: 숫자 5 = 0ms, 4 = 1000ms, 3 = 2000ms, 2 = 3000ms,
  /// 1 = 4000ms. 파일 전체는 4400~4449ms.
  ///
  /// 왜 '번호' 가 아니라 '위치' 인가
  /// -----------------------------
  /// 앱 복귀(catchUp)나 일시정지 재개에서 카운트다운 도중에 다시 재생을
  /// 걸어야 할 때, 번호 단위로 시작하면 **이미 울린 숫자와 새로 시작한
  /// 숫자가 겹친다.** (실기기 버그: "5·4·3·2·1 이 중복돼서 말하거나
  /// 안 들리다가 들린다")
  ///
  /// 위치(ms)를 직접 주면 묶음 타임라인 위의 정확한 지점으로 이동하므로
  /// 몇 번을 다시 걸어도 겹치지 않고 벽시계와 어긋나지 않는다.
  ///
  /// 반환값: 실제로 재생이 시작되었는가.
  /// 웹에서는 디코딩 전이거나 오디오가 잠겨 있으면 false 가 돌아온다.
  /// 호출자는 false 일 때 "재생 중" 표시를 하면 안 된다 (다음 숫자에서 재시도).
  bool playCountBundleAt(int positionMs) {
    if (!_anySound || !voiceEnabled) return false;
    final pos = positionMs.clamp(0, countBundleLastMs);
    final asset = 'audio/cnt_v7_${voiceStyle.assetKey}.wav';
    if (_web.available) {
      final ok = _count.webPlayNow(asset, startAtMs: pos, volume: voiceVolume);
      if (ok) _log(asset, 'count@pos$pos');
      return ok;
    }
    _count.play(asset, startAtMs: pos, volume: voiceVolume);
    _log(asset, 'count@pos$pos');
    return true;
  }

  /// 단일 숫자 재생 (음성 꺼짐 → 틱 / 복귀 경로).
  void playCount(int n) {
    if (!_anySound) return;
    if (!voiceEnabled) {
      if (sfxEnabled) playSfx(Sfx.count);
      return;
    }
    final asset = 'audio/c_${voiceStyle.assetKey}_$n.wav';
    _count.play(asset, volume: voiceVolume);
    _log(asset, 'count');
  }

  /// 단발 효과음.
  void playSfx(Sfx sfx) {
    if (!_anySound || !sfxEnabled) return;
    _sfx.play(sfx.asset, volume: sfxVolume);
    _log(sfx.asset, 'sfx');
  }

  /// 설정 화면 '목소리 미리 듣기' — 실제 재생에 쓰는 시퀀스 파일 그대로.
  Future<void> previewVoice(VoiceStyle style) async {
    _seq.stop();
    _count.stop();
    _preview.stop();
    if (!_anySound) return;

    final asset = 'audio/seq_${style.assetKey}_startWork.wav';
    final startAt = sfxEnabled ? 0 : beepLeadMs + attentionGapMs;
    _preview.play(asset, startAtMs: startAt, volume: voiceVolume);
    _log(asset, 'preview');
  }

  /// 설정 화면 '효과음 미리 듣기'.
  Future<void> previewSfx(Sfx sfx) async {
    if (!_anySound) return;
    _preview.play(sfx.asset, volume: sfxVolume);
    _log(sfx.asset, 'preview');
  }

  /// 재생 중인 모든 소리를 즉시 멈춘다 (일시정지/건너뛰기/종료).
  void cut() {
    _seq.stop();
    _count.stop();
    _sfx.stop();
    _preview.stop();
  }

  Future<void> stopAll() async {
    cut();
  }

  void vibrate({bool heavy = false}) {
    if (!_anySound) return;
    HapticFeedback.mediumImpact().catchError((_) {});
    if (heavy) HapticFeedback.heavyImpact().catchError((_) {});
  }

  Future<void> dispose() async {
    await Future.wait([
      _seq.dispose(),
      _count.dispose(),
      _sfx.dispose(),
      _preview.dispose(),
    ]);
  }
}
