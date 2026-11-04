import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/phase.dart';
import '../models/tabata_config.dart';

/// 효과음 종류
enum Sfx {
  /// 운동 시작 · 다음 라운드 시작
  startWork('audio/start_work.wav'),

  /// 휴식 시작
  startRest('audio/start_rest.wav'),

  /// 새 세트 시작
  setStart('audio/set_start.wav'),

  /// 세트 간 휴식 시작
  setRest('audio/set_rest.wav'),

  /// 전체 운동 종료
  finish('audio/finish.wav'),

  /// 짧은 비프 (음성 대체)
  beep('audio/beep.wav');

  const Sfx(this.asset);
  final String asset;
}

/// 구간 → 효과음 매핑 (순수 함수, 테스트로 검증 가능).
///
/// - 운동 구간: 세트의 첫 라운드(=새 세트 시작)면 `setStart`, 그 외 `startWork`
/// - 휴식 구간: `startRest`
/// - 세트 간 휴식: `setRest`
/// - 준비 구간: 조용히 (준비가 끝나며 운동 시작음이 울린다)
Sfx? sfxForPhase(Phase phase) {
  switch (phase.type) {
    case PhaseType.prepare:
      return null;
    case PhaseType.work:
      if (phase.roundIndex == 1 && phase.setIndex > 1) return Sfx.setStart;
      return Sfx.startWork;
    case PhaseType.rest:
      return Sfx.startRest;
    case PhaseType.setRest:
      return Sfx.setRest;
  }
}

/// 재생 기록 (타이머-사운드 싱크 검증용)
class PlayLogEntry {
  PlayLogEntry({required this.asset, required this.wallMs, required this.kind});

  final String asset;
  final int wallMs;
  final String kind; // 'sfx' | 'voice'

  @override
  String toString() => 'PlayLog($kind $asset @${wallMs % 100000})';
}

/// 사운드 출력 담당.
///
/// 설계 원칙
/// ---------
/// 1. **시간을 계산하지 않는다.** 언제 울릴지는 [TabataEngine]이 단일 벽시계로
///    결정하고, 이 클래스는 "지금 이 소리를 내라"는 지시만 수행한다.
/// 2. **효과음과 음성은 서로 다른 플레이어**를 쓴다. 같은 순간에 겹치지 않도록
///    엔진이 시점을 분리해 지시하고, 여기서는 최소 간격만 보장한다.
/// 3. 숫자 카운트다운은 미리 녹음된 wav → 재생 길이가 항상 일정하다.
/// 4. 모든 자산은 미리 preload 후 `seek(0)+resume()` 만 한다 → 시작 지연 최소화.
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

  /// 설정 반영
  void applyConfig(TabataConfig c) {
    soundEnabled = c.soundEnabled;
    voiceEnabled = c.voiceEnabled;
    sfxEnabled = c.sfxEnabled;
    voiceStyle = c.voiceStyle;
    sfxVolume = c.sfxVolume;
    voiceVolume = c.voiceVolume;
    _applyVolumes();
  }

  // ------------------------------------------------------------- 플레이어

  final Map<String, AudioPlayer> _players = <String, AudioPlayer>{};
  bool _ready = false;
  bool get isReady => _ready;

  /// 현재 재생 중인 효과음 자산
  final Set<String> _activeSfx = <String>{};

  /// 현재 재생 중인 음성 자산
  final Set<String> _activeVoice = <String>{};

  /// 마지막 효과음 재생 시각 (겹침 방지 간격 판단)
  int _lastSfxAtMs = 0;

  /// 검증용 재생 로그
  final List<PlayLogEntry> playLog = <PlayLogEntry>[];

  Future<void> init() async {
    _ready = true;
  }

  void _applyVolumes() {
    // 효과음 / 음성 플레이어에 각각 볼륨 적용
    for (final e in _players.entries) {
      final isVoice = e.key.contains('c_') || e.key.contains('preview_');
      e.value
          .setVolume(isVoice ? voiceVolume : sfxVolume)
          .catchError((_) => null);
    }
  }

  /// 필요한 자산을 미리 올려 둔다. 운동 시작 직전 호출 → 첫 소리 지연 없음.
  Future<void> warmUp() async {
    final assets = <String>{};

    if (sfxEnabled && _anySound) {
      assets.addAll(const [
        'audio/start_work.wav',
        'audio/start_rest.wav',
        'audio/set_start.wav',
        'audio/set_rest.wav',
        'audio/finish.wav',
        'audio/beep.wav',
      ]);
    }
    if (voiceEnabled && _anySound) {
      for (var n = 5; n >= 1; n--) {
        assets.add('audio/c_${voiceStyle.assetKey}_$n.wav');
      }
    }
    for (final a in assets) {
      unawaited(_load(a));
    }
  }

  Future<AudioPlayer?> _load(String asset) async {
    final existing = _players[asset];
    if (existing != null) return existing;
    try {
      final isVoice = asset.contains('c_') || asset.contains('preview_');
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setVolume(isVoice ? voiceVolume : sfxVolume);
      await p.setSource(AssetSource(asset));
      _players[asset] = p;
      return p;
    } catch (e) {
      if (kDebugMode) debugPrint('audio load failed($asset): $e');
      return null;
    }
  }

  Future<void> _play(String asset, {required bool isVoice}) async {
    final p = await _load(asset);
    if (p == null) return;
    try {
      await p.seek(Duration.zero);
      await p.resume();
      _log(asset, isVoice);
    } catch (e) {
      if (kDebugMode) debugPrint('audio play failed($asset): $e');
    }
  }

  void _log(String asset, bool isVoice) {
    if (!kDebugMode) return;
    playLog.add(
      PlayLogEntry(
        asset: asset,
        wallMs: DateTime.now().millisecondsSinceEpoch,
        kind: isVoice ? 'voice' : 'sfx',
      ),
    );
    if (playLog.length > 300) playLog.removeAt(0);
  }

  // ------------------------------------------------------------- 효과음

  /// 효과음 재생. 이전 효과음이 끝나지 않았으면 끊고 새로 재생한다.
  void playSfx(Sfx sfx) {
    if (!_anySound || !sfxEnabled) return;
    // 음성 카운트다운이 울리는 중이면 효과음을 살짝 늦춰 겹침을 피한다.
    final now = DateTime.now().millisecondsSinceEpoch;
    final gap = now - _lastSfxAtMs;
    _lastSfxAtMs = now;
    if (gap < 90) return; // 같은 순간 중복 요청 차단

    for (final other in _activeSfx) {
      if (other == sfx.asset) continue;
      _players[other]?.stop().catchError((_) {});
    }
    _activeSfx
      ..clear()
      ..add(sfx.asset);
    unawaited(_play(sfx.asset, isVoice: false));
  }

  /// 음성 카운트다운 숫자 재생 (5→1).
  /// 음성이 꺼져 있으면 비프로 대체.
  void playCount(int n) {
    if (!_anySound) return;
    if (!voiceEnabled) {
      if (sfxEnabled) playSfx(Sfx.beep);
      return;
    }
    final asset = 'audio/c_${voiceStyle.assetKey}_$n.wav';
    _activeVoice.add(asset);
    unawaited(_play(asset, isVoice: true));
  }

  /// 미리 듣기 — "오 사 삼 이 일" 연속 샘플
  Future<void> previewVoice(VoiceStyle style) async {
    if (!_anySound) return;
    await stopVoice();
    await _play('audio/preview_${style.name}.wav', isVoice: true);
  }

  /// 효과음 미리 듣기
  Future<void> previewSfx(Sfx sfx) async {
    if (!_anySound) return;
    await stopSfx();
    await _play(sfx.asset, isVoice: false);
  }

  /// 효과음만 정지
  Future<void> stopSfx() async {
    for (final a in _activeSfx) {
      try {
        await _players[a]?.stop();
      } catch (_) {}
    }
    _activeSfx.clear();
  }

  /// 음성만 정지
  Future<void> stopVoice() async {
    for (final a in _activeVoice) {
      try {
        await _players[a]?.stop();
      } catch (_) {}
    }
    _activeVoice.clear();
  }

  /// 전체 정지 (일시정지/종료)
  Future<void> stopAll() async {
    await stopSfx();
    await stopVoice();
    // 미리듣기 등 남은 플레이어도 정지
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
    await stopAll();
    for (final p in _players.values) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _players.clear();
  }
}
