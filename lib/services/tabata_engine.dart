import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/phase.dart';
import '../models/tabata_config.dart';
import 'sound_service.dart';

enum EngineStatus { idle, running, paused, finished }

/// 타바타 타이머 엔진
///
/// - 50ms 주기로 갱신하되 Stopwatch 실측 시간으로 누적 드리프트를 보정한다.
/// - 운동/휴식 구간의 마지막 5초에서 1초마다 카운트다운 비프를 울린다.
class TabataEngine extends ChangeNotifier {
  TabataEngine({TabataConfig? config})
    : _config = config ?? const TabataConfig();

  TabataConfig _config;
  TabataConfig get config => _config;

  final List<Phase> _phases = <Phase>[];
  List<Phase> get phases => List.unmodifiable(_phases);

  int _index = 0;
  int get index => _index;

  int _remainingMs = 0;
  int get remainingMs => _remainingMs;

  EngineStatus _status = EngineStatus.idle;
  EngineStatus get status => _status;

  Timer? _ticker;
  final Stopwatch _stopwatch = Stopwatch();
  int _lastWholeSecond = -1;

  /// 구간 전환 직전 신호를 중복 재생하지 않기 위한 플래그
  bool _transitionFired = false;

  bool get isRunning => _status == EngineStatus.running;
  bool get isFinished => _status == EngineStatus.finished;
  bool get isIdle => _status == EngineStatus.idle;

  Phase? get currentPhase =>
      (_index >= 0 && _index < _phases.length) ? _phases[_index] : null;

  /// 남은 시간(초) — 올림 처리하여 0.4초 남아도 1초로 표시
  int get remainingSeconds {
    if (currentPhase == null) return 0;
    return (_remainingMs / 1000).ceil().clamp(0, currentPhase!.duration);
  }

  /// 전체 진행률 0~1
  double get totalProgress {
    if (_phases.isEmpty) return 0;
    final total = _phases.fold<int>(0, (a, p) => a + p.duration);
    if (total == 0) return 0;
    var elapsed = 0;
    for (var i = 0; i < _index && i < _phases.length; i++) {
      elapsed += _phases[i].duration;
    }
    final cur = currentPhase;
    if (cur != null) elapsed += (cur.duration - remainingSeconds);
    return (elapsed / total).clamp(0.0, 1.0);
  }

  /// 현재 구간 진행률 0~1
  double get phaseProgress {
    final cur = currentPhase;
    if (cur == null || cur.duration == 0) return 0;
    return (1 - remainingSeconds / cur.duration).clamp(0.0, 1.0);
  }

  /// 남은 총 시간(초)
  int get remainingTotalSeconds {
    var remain = remainingSeconds;
    for (var i = _index + 1; i < _phases.length; i++) {
      remain += _phases[i].duration;
    }
    return remain;
  }

  /// 완료한 운동 개수
  int get completedWorkouts =>
      _phases.take(_index).where((p) => p.type == PhaseType.work).length;

  int get totalWorkouts =>
      _phases.where((p) => p.type == PhaseType.work).length;

  void updateConfig(TabataConfig config) {
    _config = config;
    if (_status != EngineStatus.running && _status != EngineStatus.paused) {
      _phases
        ..clear()
        ..addAll(config.buildPhases());
      _index = 0;
      _remainingMs = _phases.isEmpty ? 0 : _phases.first.duration * 1000;
      notifyListeners();
    }
  }

  void reset() {
    _ticker?.cancel();
    _stopwatch.stop();
    _stopwatch.reset();
    _status = EngineStatus.idle;
    _phases
      ..clear()
      ..addAll(_config.buildPhases());
    _index = 0;
    _lastWholeSecond = -1;
    _transitionFired = false;
    _remainingMs = _phases.isEmpty ? 0 : _phases.first.duration * 1000;
    notifyListeners();
  }

  void start() {
    if (_phases.isEmpty) reset();
    if (_phases.isEmpty) return;
    if (_status == EngineStatus.finished) reset();
    _status = EngineStatus.running;
    _lastWholeSecond = remainingSeconds;
    _stopwatch
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());

    // 시작 시점 안내음
    final cur = currentPhase;
    if (cur != null && cur.type != PhaseType.prepare) {
      if (cur.type == PhaseType.work) {
        SoundService.instance.workStart();
      } else {
        SoundService.instance.restStart();
      }
    }
    notifyListeners();
  }

  void pause() {
    if (_status != EngineStatus.running) return;
    _ticker?.cancel();
    _stopwatch.stop();
    _status = EngineStatus.paused;
    notifyListeners();
  }

  void resume() {
    if (_status != EngineStatus.paused) return;
    _status = EngineStatus.running;
    _stopwatch
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
    notifyListeners();
  }

  void toggle() {
    switch (_status) {
      case EngineStatus.running:
        pause();
      case EngineStatus.paused:
        resume();
      case EngineStatus.idle:
      case EngineStatus.finished:
        start();
    }
  }

  /// 다음 구간으로 건너뛰기
  void skip() {
    if (_status == EngineStatus.idle) return;
    _advance(playSound: false);
  }

  void _advance({bool playSound = true}) {
    _index++;
    _transitionFired = false;
    _stopwatch.reset();
    if (_index >= _phases.length) {
      _finish();
      return;
    }
    _remainingMs = _phases[_index].duration * 1000;
    _lastWholeSecond = remainingSeconds;

    if (playSound) {
      final cur = _phases[_index];
      if (cur.type == PhaseType.work) {
        SoundService.instance.workStart();
        if (_config.vibrationEnabled) SoundService.instance.vibrate();
      } else if (cur.type == PhaseType.rest || cur.type == PhaseType.setRest) {
        SoundService.instance.restStart();
        if (_config.vibrationEnabled) SoundService.instance.vibrate();
      }
    }
    notifyListeners();
  }

  void _finish() {
    _ticker?.cancel();
    _stopwatch.stop();
    _status = EngineStatus.finished;
    _index = _phases.length - 1;
    _remainingMs = 0;
    if (_config.soundEnabled) SoundService.instance.finish();
    if (_config.vibrationEnabled) SoundService.instance.vibrate(heavy: true);
    notifyListeners();
  }

  void _tick() {
    final cur = currentPhase;
    if (cur == null) return;

    _remainingMs = cur.duration * 1000 - _stopwatch.elapsedMilliseconds;

    if (_remainingMs <= 0) {
      if (!_transitionFired) {
        _transitionFired = true;
        if (_config.soundEnabled) SoundService.instance.phaseEnd();
        if (_config.vibrationEnabled) SoundService.instance.vibrate();
      }
      _advance();
      return;
    }

    final secs = remainingSeconds;

    // 마지막 5초 카운트다운 — 운동/휴식 구간에서만
    if (secs != _lastWholeSecond) {
      _lastWholeSecond = secs;
      if (cur.needsCountdown && secs <= 5 && secs >= 1) {
        if (_config.soundEnabled) {
          SoundService.instance.countdownBeep();
        }
        if (_config.vibrationEnabled && secs <= 3) {
          SoundService.instance.vibrate();
        }
      }
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    super.dispose();
  }
}
