import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 카운트다운 / 구간 전환 사운드 및 진동 담당
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final List<AudioPlayer> _pool = <AudioPlayer>[];
  int _cursor = 0;
  bool _ready = false;

  /// 짧은 비프음 연타를 위해 플레이어 여러 개를 미리 준비
  Future<void> init() async {
    if (_ready) return;
    for (var i = 0; i < 4; i++) {
      final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      await p.setVolume(1.0);
      _pool.add(p);
    }
    _ready = true;
  }

  AudioPlayer _next() {
    if (_pool.isEmpty) {
      final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      _pool.add(p);
    }
    final p = _pool[_cursor % _pool.length];
    _cursor++;
    return p;
  }

  Future<void> _play(String asset) async {
    try {
      await init();
      final p = _next();
      await p.stop();
      await p.play(AssetSource(asset));
    } catch (e) {
      if (kDebugMode) debugPrint('sound error($asset): $e');
    }
  }

  /// 5,4,3,2,1 카운트다운 비프
  Future<void> countdownBeep() => _play('audio/beep.wav');

  /// 구간 종료 신호
  Future<void> phaseEnd() => _play('audio/beep_end.wav');

  /// 운동 시작 신호
  Future<void> workStart() => _play('audio/beep_go.wav');

  /// 휴식 시작 신호
  Future<void> restStart() => _play('audio/beep_rest.wav');

  /// 전체 종료 신호 (3연타)
  Future<void> finish() async {
    await _play('audio/beep_end.wav');
    await Future<void>.delayed(const Duration(milliseconds: 420));
    await _play('audio/beep_end.wav');
    await Future<void>.delayed(const Duration(milliseconds: 420));
    await _play('audio/beep_go.wav');
  }

  void vibrate({bool heavy = false}) {
    // 웹/테스트 등 미지원 플랫폼에서는 조용히 무시
    HapticFeedback.mediumImpact().catchError((_) {});
    if (heavy) HapticFeedback.heavyImpact().catchError((_) {});
  }

  Future<void> dispose() async {
    for (final p in _pool) {
      await p.dispose();
    }
    _pool.clear();
    _ready = false;
  }
}
