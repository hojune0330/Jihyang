import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 음성 안내 + 효과음 재생을 한 곳에서 조율한다.
///
/// - 음성과 효과음이 겹치지 않도록 단일 직렬 큐로 처리
/// - 같은 안내가 중복 재생되지 않도록 키 기반 디바운스
/// - 음성 안내는 짧은 문구만 사용 ("운동", "삼", "이", "일")
class AudioCoach {
  AudioCoach._();
  static final AudioCoach instance = AudioCoach._();

  // ---------------------------------------------------------------- 효과음

  final List<AudioPlayer> _sfxPool = <AudioPlayer>[];
  int _sfxCursor = 0;
  bool _sfxReady = false;

  // ---------------------------------------------------------------- 음성

  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;
  bool _ttsAvailable = true;

  /// 음성/효과음 켜기
  bool voiceEnabled = true;
  bool sfxEnabled = true;

  /// 안내 큐 — 순서대로 하나씩 처리
  final List<AudioCue> _queue = <AudioCue>[];
  bool _running = false;

  /// 최근 재생 키 / 시각 (중복 방지)
  final Map<String, DateTime> _recent = <String, DateTime>{};

  Future<void> init() async {
    await _initSfx();
    await _initTts();
  }

  Future<void> _initSfx() async {
    if (_sfxReady) return;
    try {
      for (var i = 0; i < 3; i++) {
        final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
        await p.setVolume(1.0);
        _sfxPool.add(p);
      }
      _sfxReady = true;
    } catch (e) {
      if (kDebugMode) debugPrint('sfx init failed: $e');
    }
  }

  Future<void> _initTts() async {
    if (_ttsReady || !_ttsAvailable) return;
    if (kIsWeb) {
      _ttsAvailable = false; // 웹은 음성 미지원으로 처리
      return;
    }
    try {
      await _tts.setLanguage('ko-KR');
      await _tts.setSpeechRate(0.52); // 짧고 또렷하게
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      _ttsReady = true;
    } catch (e) {
      if (kDebugMode) debugPrint('tts init failed: $e');
      _ttsAvailable = false;
    }
  }

  // ---------------------------------------------------------------- 퍼블릭 큐

  /// 카운트다운 숫자 안내 (5 → 1)
  void sayCount(int n) {
    if (!voiceEnabled) {
      playSfx(Sfx.beep);
      return;
    }
    enqueue(AudioCue.speech(_koreanNumber(n), key: 'count-$n'));
  }

  /// 운동 시작 안내
  void announceWorkStart({
    required int round,
    required int totalRounds,
    required int set,
    required int totalSets,
    bool withSfx = true,
  }) {
    if (withSfx) playSfx(Sfx.startWork);
    if (!voiceEnabled) return;
    final roundText = totalSets > 1 ? '$set세트 $round라운드 운동' : '$round라운드 운동';
    enqueue(AudioCue.speech(roundText, key: 'work-$set-$round'));
  }

  /// 휴식 시작 안내
  void announceRestStart({required int seconds, bool withSfx = true}) {
    if (withSfx) playSfx(Sfx.startRest);
    if (!voiceEnabled) return;
    enqueue(
      AudioCue.speech(
        '휴식 ${_spokenSeconds(seconds)}',
        key: 'rest-$seconds-${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      ),
    );
  }

  /// 세트 간 휴식 시작 안내
  void announceSetRestStart({required int seconds, required int nextSet}) {
    playSfx(Sfx.startRest);
    if (!voiceEnabled) return;
    enqueue(
      AudioCue.speech(
        '세트 휴식 ${_spokenSeconds(seconds)}. 다음 $nextSet세트',
        key: 'setrest-$nextSet',
      ),
    );
  }

  /// 세트 간 휴식 종료 안내
  void announceSetRestEnd({required int nextSet}) {
    playSfx(Sfx.transition);
    if (!voiceEnabled) return;
    enqueue(AudioCue.speech('$nextSet세트 시작', key: 'setrest-end-$nextSet'));
  }

  /// 전체 운동 완료
  void announceFinish({required int sets, required int rounds}) {
    playSfx(Sfx.finish);
    if (!voiceEnabled) return;
    final text = sets > 1 ? '운동 완료. $sets세트 $rounds라운드' : '운동 완료. $rounds라운드';
    enqueue(AudioCue.speech(text, key: 'finish'));
  }

  /// 전환 알림음
  void playSfx(Sfx sfx) {
    if (!sfxEnabled) return;
    unawaited(_playSfxFile(sfx.asset));
  }

  void vibrate({bool heavy = false}) {
    HapticFeedback.mediumImpact().catchError((_) {});
    if (heavy) HapticFeedback.heavyImpact().catchError((_) {});
  }

  // ---------------------------------------------------------------- 내부

  Future<void> _playSfxFile(String asset) async {
    if (!_sfxReady) await _initSfx();
    if (_sfxPool.isEmpty) return;
    try {
      final p = _sfxPool[_sfxCursor % _sfxPool.length];
      _sfxCursor++;
      await p.stop();
      await p.play(AssetSource(asset));
    } catch (e) {
      if (kDebugMode) debugPrint('sfx play failed($asset): $e');
    }
  }

  void enqueue(AudioCue cue) {
    final key = cue.key;
    if (key != null) {
      final last = _recent[key];
      final now = DateTime.now();
      // 같은 안내 1.2초 내 중복 차단
      if (last != null && now.difference(last).inMilliseconds < 1200) return;
      _recent[key] = now;
      if (_recent.length > 40) {
        _recent.removeWhere((_, v) => now.difference(v).inSeconds > 30);
      }
    }
    _queue.add(cue);
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final cue = _queue.removeAt(0);
        if (cue.speech != null) {
          await _speak(cue.speech!);
        } else if (cue.asset != null) {
          await _playSfxFile(cue.asset!);
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _speak(String text) async {
    if (!voiceEnabled) return;
    if (!_ttsAvailable) {
      // 음성 미지원 환경에서는 비프로 대체
      await _playSfxFile(Sfx.beep.asset);
      return;
    }
    await _initTts();
    if (!_ttsReady) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      if (kDebugMode) debugPrint('tts speak failed: $e');
    }
  }

  /// 정지 (종료/리셋 시 남은 안내 제거)
  Future<void> stopAll() async {
    _queue.clear();
    try {
      if (_ttsReady) await _tts.stop();
    } catch (_) {}
    for (final p in _sfxPool) {
      try {
        await p.stop();
      } catch (_) {}
    }
  }

  String _koreanNumber(int n) => switch (n) {
    5 => '오',
    4 => '사',
    3 => '삼',
    2 => '이',
    1 => '일',
    _ => '$n',
  };

  String _spokenSeconds(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0 && s > 0) return '$m분 $s초';
    if (m > 0) return '$m분';
    return '$s초';
  }

  Future<void> dispose() async {
    await stopAll();
    for (final p in _sfxPool) {
      await p.dispose();
    }
    _sfxPool.clear();
  }
}

enum Sfx {
  startWork('audio/start_work.wav'),
  startRest('audio/start_rest.wav'),
  transition('audio/transition.wav'),
  finish('audio/finish.wav'),
  beep('audio/beep.wav');

  const Sfx(this.asset);
  final String asset;
}

class AudioCue {
  /// 음성 안내 큐
  AudioCue.speech(this.speech, {this.key}) : asset = null;

  /// 효과음 큐
  AudioCue.sfx(this.asset, {this.key = 'sfx'}) : speech = null;

  final String? speech;
  final String? asset;
  final String? key;
}
