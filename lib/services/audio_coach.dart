import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 구간 시작 계열 안내음 종류
enum CueKind { workStart, restStart, setRestStart, finish }

/// 재생 기록 (타이머-사운드 싱크 검증용)
class PlayLogEntry {
  PlayLogEntry({
    required this.asset,
    required this.requestedAt,
    required this.requestedWallMs,
  });

  final String asset;
  final Duration requestedAt;
  final int requestedWallMs;

  @override
  String toString() =>
      'PlayLog(asset=$asset, at=${requestedAt.inMilliseconds}ms)';
}

/// 사운드 출력 담당.
///
/// 설계 원칙
///  1. **효과음과 음성을 하나의 파일로 미리 합성**해 두었다(`cue_*.wav`).
///     → 두 플레이어가 동시에 울려 겹치는 상황 자체가 발생하지 않는다.
///  2. 숫자 카운트다운은 실시간 TTS가 아니라 **미리 녹음한 wav**를 쓴다.
///     → 합성 지연이 없고 재생 길이가 항상 일정하다.
///  3. 자산별로 전용 플레이어를 미리 준비(preload)해 두고 `seek(0)+resume()`만 한다.
///     → 재생 시작 지연이 수십 ms 수준으로 일정하다.
///  4. **시간을 계산하지 않는다.** 언제 울릴지는 [TabataEngine]이 단일 벽시계로
///     결정하고, 이 클래스는 "지금 이 소리를 내라"는 지시만 수행한다.
class AudioCoach {
  AudioCoach._();
  static final AudioCoach instance = AudioCoach._();

  // ------------------------------------------------------------- 설정

  /// 전체 사운드 (마스터)
  bool soundEnabled = true;

  /// 음성 카운트다운 + 구간 음성 안내
  bool voiceEnabled = true;

  /// 효과음 (알림음/비프)
  bool sfxEnabled = true;

  bool get _anySound => soundEnabled && (voiceEnabled || sfxEnabled);

  // ------------------------------------------------------------- 플레이어

  final Map<String, AudioPlayer> _players = <String, AudioPlayer>{};

  /// 현재 재생 중인 '구간 안내' 플레이어 (새 안내 시 정지)
  final Set<String> _cueAssets = <String>{};

  /// 카운트다운 전용 플레이어 (숫자별)
  final Set<String> _countAssets = <String>{};

  bool _ready = false;

  /// 웹은 자동재생 정책 때문에 첫 사용자 제스처 이후에만 소리가 난다.
  bool get isReady => _ready;

  /// 검증용 재생 로그 (최근 120개)
  final List<PlayLogEntry> playLog = <PlayLogEntry>[];

  // ------------------------------------------------------------- 초기화

  Future<void> init() async {
    // 플러그인 준비만 확인하고, 실제 자산 프리로드는 warmUp에서 한다.
    _ready = true;
  }

  /// 필요한 자산을 미리 메모리에 올려 둔다.
  /// 운동 시작 직전에 호출하면 첫 소리도 지연 없이 난다.
  Future<void> warmUp() async {
    final assets = <String>{};
    if (_anySound) {
      if (voiceEnabled && sfxEnabled) {
        assets.addAll(const [
          'audio/cue_work.wav',
          'audio/cue_rest.wav',
          'audio/cue_setrest.wav',
          'audio/cue_finish.wav',
        ]);
      } else if (sfxEnabled) {
        assets.addAll(const [
          'audio/start_work.wav',
          'audio/start_rest.wav',
          'audio/set_rest.wav',
          'audio/finish.wav',
        ]);
      } else if (voiceEnabled) {
        assets.addAll(const [
          'audio/voice_work.wav',
          'audio/voice_rest.wav',
          'audio/voice_setrest.wav',
          'audio/voice_finish.wav',
        ]);
      }

      if (voiceEnabled) {
        for (var n = 5; n >= 1; n--) {
          assets.add('audio/count_$n.wav');
        }
      } else if (sfxEnabled) {
        assets.add('audio/beep.wav');
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
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setVolume(1.0);
      await p.setSource(AssetSource(asset));
      _players[asset] = p;
      return p;
    } catch (e) {
      if (kDebugMode) debugPrint('audio load failed($asset): $e');
      return null;
    }
  }

  // ------------------------------------------------------------- 재생

  Future<void> _play(String asset) async {
    if (!_anySound) return;
    final p = await _load(asset);
    if (p == null) return;
    final sw = Stopwatch()..start();
    try {
      await p.seek(Duration.zero);
      await p.resume();
      _log(asset, sw.elapsed);
    } catch (e) {
      if (kDebugMode) debugPrint('audio play failed($asset): $e');
    }
  }

  void _log(String asset, Duration elapsed) {
    if (!kDebugMode) return;
    playLog.add(
      PlayLogEntry(
        asset: asset,
        requestedAt: elapsed,
        requestedWallMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (playLog.length > 120) playLog.removeAt(0);
  }

  /// 구간 시작 안내 — 효과음과 음성이 **한 파일**이므로 절대 겹치지 않는다.
  void playCue(CueKind kind) {
    if (!_anySound) return;
    final asset = _cueAsset(kind);
    if (asset == null) return;

    // 이전 구간 안내가 아직 울리고 있으면 먼저 끊는다 (중복/겹침 방지)
    for (final other in _cueAssets) {
      if (other == asset) continue;
      _players[other]?.stop().catchError((_) {});
    }
    _cueAssets
      ..clear()
      ..add(asset);
    unawaited(_play(asset));
  }

  String? _cueAsset(CueKind kind) {
    if (voiceEnabled && sfxEnabled) {
      return switch (kind) {
        CueKind.workStart => 'audio/cue_work.wav',
        CueKind.restStart => 'audio/cue_rest.wav',
        CueKind.setRestStart => 'audio/cue_setrest.wav',
        CueKind.finish => 'audio/cue_finish.wav',
      };
    }
    if (sfxEnabled) {
      return switch (kind) {
        CueKind.workStart => 'audio/start_work.wav',
        CueKind.restStart => 'audio/start_rest.wav',
        CueKind.setRestStart => 'audio/set_rest.wav',
        CueKind.finish => 'audio/finish.wav',
      };
    }
    if (voiceEnabled) {
      return switch (kind) {
        CueKind.workStart => 'audio/voice_work.wav',
        CueKind.restStart => 'audio/voice_rest.wav',
        CueKind.setRestStart => 'audio/voice_setrest.wav',
        CueKind.finish => 'audio/voice_finish.wav',
      };
    }
    return null;
  }

  /// 마지막 5초 카운트다운 — 5,4,3,2,1
  ///
  /// 음성이 꺼져 있고 효과음만 켜져 있으면 짧은 비프로 대체한다.
  void playCount(int n) {
    if (!_anySound) return;
    final asset = voiceEnabled ? 'audio/count_$n.wav' : 'audio/beep.wav';
    // 카운트다운은 숫자별 전용 플레이어 → 이전 숫자를 끊지 않는다.
    _countAssets.add(asset);
    unawaited(_play(asset));
  }

  /// 일시정지/종료 시 즉시 모든 소리를 끊는다.
  Future<void> stopAll() async {
    for (final p in _players.values) {
      try {
        await p.stop();
      } catch (_) {}
    }
    _cueAssets.clear();
    _countAssets.clear();
  }

  /// 카운트다운만 즉시 취소 (일시정지)
  Future<void> stopCountdown() async {
    for (final a in _countAssets) {
      try {
        await _players[a]?.stop();
      } catch (_) {}
    }
    _countAssets.clear();
  }

  void vibrate({bool heavy = false}) {
    if (!soundEnabled) return;
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
