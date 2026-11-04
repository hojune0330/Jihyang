import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/phase.dart';
import '../models/tabata_config.dart';
import 'sound_service.dart';

enum EngineStatus { idle, running, paused, finished }

/// 벽시계(DateTime) 기반 타바타 엔진.
///
/// 남은 시간을 "타이머 틱 누적"이 아니라 `현재시각 - 구간시작시각`으로 계산하기 때문에
/// 화면이 꺼지거나 다른 앱으로 이동해 프레임이 멈춰도 시간이 틀어지지 않는다.
/// 일시정지 시점의 경과 시간을 보존했다가 재개하면 이어서 계산한다.
class TabataEngine extends ChangeNotifier {
  TabataEngine({TabataConfig? config})
    : _config = config ?? const TabataConfig() {
    _rebuild();
  }

  TabataConfig _config;
  TabataConfig get config => _config;

  final List<Phase> _phases = <Phase>[];
  List<Phase> get phases => List.unmodifiable(_phases);

  int _index = 0;
  int get index => _index;

  EngineStatus _status = EngineStatus.idle;
  EngineStatus get status => _status;

  bool get isIdle => _status == EngineStatus.idle;
  bool get isRunning => _status == EngineStatus.running;
  bool get isPaused => _status == EngineStatus.paused;
  bool get isFinished => _status == EngineStatus.finished;

  Timer? _ticker;

  /// 현재 구간이 시작된 벽시계 시각 (일시정지 중에는 null)
  DateTime? _phaseStartWall;

  /// 현재 구간에서 이미 흘러간 시간(ms) — 일시정지 누적분 + 재개 오프셋
  int _elapsedBeforeStart = 0;

  /// 직전에 안내한 남은 초 (카운트다운 중복 재생 방지)
  int _lastAnnouncedSecond = -1;

  int _remainingMs = 0;

  Phase? get currentPhase =>
      (_index >= 0 && _index < _phases.length) ? _phases[_index] : null;

  Phase? get nextPhase =>
      (_index + 1 < _phases.length) ? _phases[_index + 1] : null;

  /// 현재 구간 경과 시간(ms)
  int get _elapsedInPhase {
    var base = _elapsedBeforeStart;
    final start = _phaseStartWall;
    if (_status == EngineStatus.running && start != null) {
      base += DateTime.now().difference(start).inMilliseconds;
    }
    return base;
  }

  /// 남은 시간(초) — 0.3초 남아도 1초로 표시
  int get remainingSeconds {
    final cur = currentPhase;
    if (cur == null) return 0;
    if (_status == EngineStatus.idle) return cur.duration;
    return (_remainingMs / 1000).ceil().clamp(0, cur.duration);
  }

  /// 현재 구간 남은 시간(ms) — 알림 예약 등 외부에서 사용
  int get remainingMs {
    final cur = currentPhase;
    if (cur == null) return 0;
    if (_status == EngineStatus.idle) return cur.duration * 1000;
    return _remainingMs.clamp(0, cur.duration * 1000);
  }

  int get remainingTotalSeconds {
    var remain = remainingSeconds;
    for (var i = _index + 1; i < _phases.length; i++) {
      remain += _phases[i].duration;
    }
    return remain;
  }

  int get totalSeconds => _phases.fold<int>(0, (a, p) => a + p.duration);

  int get elapsedTotalSeconds {
    if (_status == EngineStatus.idle) return 0;
    var elapsed = 0;
    for (var i = 0; i < _index && i < _phases.length; i++) {
      elapsed += _phases[i].duration;
    }
    final cur = currentPhase;
    if (cur != null) {
      elapsed += cur.duration - remainingSeconds;
    }
    return elapsed.clamp(0, totalSeconds);
  }

  /// 전체 진행률 0~1
  double get totalProgress {
    final total = totalSeconds;
    if (total == 0) return 0;
    if (_status == EngineStatus.finished) return 1;
    return (elapsedTotalSeconds / total).clamp(0.0, 1.0);
  }

  /// 현재 구간 진행률 0~1
  double get phaseProgress {
    final cur = currentPhase;
    if (cur == null || cur.duration == 0) return 0;
    return (1 - remainingSeconds / cur.duration).clamp(0.0, 1.0);
  }

  /// 현재 라운드 (1부터). 세트 휴식에서는 직전 라운드로 표시
  int get currentRound {
    final cur = currentPhase;
    if (cur == null) return 1;
    if (cur.type == PhaseType.setRest) return cur.totalExercises;
    if (cur.type == PhaseType.rest) return cur.exerciseIndex;
    return cur.exerciseIndex == 0 ? 1 : cur.exerciseIndex;
  }

  int get totalRounds {
    final cur = currentPhase;
    return cur?.totalExercises ?? _config.exerciseCount;
  }

  int get currentSet {
    final cur = currentPhase;
    if (cur == null) return 1;
    return cur.setIndex;
  }

  int get totalSets => currentPhase?.totalSets ?? _config.setCount;

  // ---------------------------------------------------------------- 제어

  void _rebuild() {
    _phases
      ..clear()
      ..addAll(_config.buildPhases());
    _index = 0;
    _elapsedBeforeStart = 0;
    _phaseStartWall = null;
    _lastAnnouncedSecond = -1;
    _remainingMs = _phases.isEmpty ? 0 : _phases.first.duration * 1000;
  }

  /// 설정 변경 — 진행 중이어도 새 설정으로 재구성해 즉시 반영
  void updateConfig(TabataConfig config) {
    _config = config;
    _ticker?.cancel();
    _ticker = null;
    _status = EngineStatus.idle;
    _rebuild();
    notifyListeners();
  }

  void reset() {
    _ticker?.cancel();
    _ticker = null;
    _status = EngineStatus.idle;
    _rebuild();
    notifyListeners();
  }

  void start() {
    if (_phases.isEmpty) _rebuild();
    if (_phases.isEmpty) return;
    if (_status == EngineStatus.finished) _rebuild();

    _status = EngineStatus.running;
    _phaseStartWall = DateTime.now();
    _elapsedBeforeStart = 0;
    _lastAnnouncedSecond = -1;
    _remainingMs = (currentPhase?.duration ?? 0) * 1000;

    _startTicker();
    _announceStart(currentPhase);
    notifyListeners();
  }

  void pause() {
    if (_status != EngineStatus.running) return;
    _elapsedBeforeStart = _elapsedInPhase;
    _phaseStartWall = null;
    _status = EngineStatus.paused;
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  void resume() {
    if (_status != EngineStatus.paused) return;
    _status = EngineStatus.running;
    _phaseStartWall = DateTime.now();
    _startTicker();
    // 재개 시점에 밀린 구간을 소리 없이 정리
    _sync(allowSound: false);
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
    _advanceTo(_index + 1, carryMs: 0, announce: false);
    if (_status == EngineStatus.running) {
      _phaseStartWall = DateTime.now();
      _startTicker();
    }
    notifyListeners();
  }

  /// 앱이 포그라운드로 돌아왔을 때 호출 — 밀린 구간을 즉시 반영
  void catchUp() {
    if (_status != EngineStatus.running) return;
    _sync(allowSound: false);
    notifyListeners();
  }

  // ---------------------------------------------------------------- 내부

  void _startTicker() {
    _ticker?.cancel();
    // 250ms: 화면 갱신 부드러움과 배터리 소모의 균형
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _sync());
  }

  void _sync({bool allowSound = true}) {
    if (_status != EngineStatus.running) return;
    if (_phases.isEmpty) return;

    var guard = 0;
    while (guard++ < 2000) {
      final cur = currentPhase;
      if (cur == null) return;

      final elapsed = _elapsedInPhase;
      final durationMs = cur.duration * 1000;
      final remain = durationMs - elapsed;

      if (remain > 0) {
        _remainingMs = remain;
        _handleCountdown(cur, remain, allowSound: allowSound);
        notifyListeners();
        return;
      }

      // 구간 종료 → 다음 구간으로 (초과분 이월)
      final carry = -remain;
      if (allowSound && _config.soundEnabled) {
        SoundService.instance.phaseEnd();
      }
      if (allowSound && _config.vibrationEnabled) {
        SoundService.instance.vibrate();
      }
      _advanceTo(_index + 1, carryMs: carry, announce: allowSound);
      if (_status != EngineStatus.running) return;
    }
  }

  void _advanceTo(int nextIndex, {required int carryMs, bool announce = true}) {
    _index = nextIndex;
    _elapsedBeforeStart = carryMs < 0 ? 0 : carryMs;
    _lastAnnouncedSecond = -1;
    _phaseStartWall = _status == EngineStatus.running ? DateTime.now() : null;

    if (_index >= _phases.length) {
      _finish();
      return;
    }
    _remainingMs = (_phases[_index].duration * 1000 - _elapsedBeforeStart)
        .clamp(0, 1 << 31);
    if (announce) _announceStart(_phases[_index]);
  }

  void _announceStart(Phase? phase) {
    if (phase == null || !_config.soundEnabled) return;
    switch (phase.type) {
      case PhaseType.work:
        SoundService.instance.workStart();
      case PhaseType.rest:
      case PhaseType.setRest:
        SoundService.instance.restStart();
      case PhaseType.prepare:
        break;
    }
    if (_config.vibrationEnabled) SoundService.instance.vibrate();
  }

  void _handleCountdown(Phase phase, int remainMs, {required bool allowSound}) {
    if (!phase.needsCountdown) return;
    final secs = (remainMs / 1000).ceil();
    if (secs > 5 || secs < 1) return;
    if (secs == _lastAnnouncedSecond) return;
    _lastAnnouncedSecond = secs;
    if (allowSound && _config.soundEnabled) {
      SoundService.instance.countdownBeep();
    }
    if (allowSound && _config.vibrationEnabled && secs <= 3) {
      SoundService.instance.vibrate();
    }
  }

  void _finish() {
    _ticker?.cancel();
    _ticker = null;
    _phaseStartWall = null;
    _status = EngineStatus.finished;
    _remainingMs = 0;
    _elapsedBeforeStart = 0;
    if (_config.soundEnabled) SoundService.instance.finish();
    if (_config.vibrationEnabled) SoundService.instance.vibrate(heavy: true);
    notifyListeners();
  }

  // ------------------------------------------------- 스냅샷(백그라운드 복원)

  /// 현재 진행 상황을 저장용 맵으로 직렬화
  Map<String, dynamic> snapshot() {
    return {
      'status': _status.name,
      'index': _index,
      'elapsedBeforeStart': _status == EngineStatus.running
          ? _elapsedInPhase
          : _elapsedBeforeStart,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'config': _config.toJson(),
    };
  }

  /// 저장된 스냅샷으로 복원. 앱이 종료되어도 남은 시간이 이어진다.
  void restoreFromSnapshot(Map<String, dynamic> snap) {
    try {
      final configJson = snap['config'];
      if (configJson is Map) {
        _config = TabataConfig.fromJson(Map<String, dynamic>.from(configJson));
      }
      _rebuild();

      final savedIndex = snap['index'];
      final savedElapsed = snap['elapsedBeforeStart'];
      final savedAt = snap['savedAt'];
      final savedStatus = snap['status'];

      if (savedIndex is! int ||
          savedIndex < 0 ||
          savedIndex >= _phases.length) {
        return;
      }
      if (savedStatus != 'running' && savedStatus != 'paused') return;

      _index = savedIndex;
      var elapsed = savedElapsed is int ? savedElapsed : 0;

      // 종료돼 있던 시간만큼 진행시킨다 (벽시계 기준)
      if (savedStatus == 'running' && savedAt is int) {
        final gap = DateTime.now().millisecondsSinceEpoch - savedAt;
        if (gap > 0) elapsed += gap;
      }

      // 밀린 구간을 소리 없이 정산
      var guard = 0;
      while (guard++ < 2000 && _index < _phases.length) {
        final durationMs = _phases[_index].duration * 1000;
        if (elapsed < durationMs) break;
        elapsed -= durationMs;
        _index++;
      }
      if (_index >= _phases.length) {
        _index = _phases.length - 1;
        _elapsedBeforeStart = _phases[_index].duration * 1000;
        _remainingMs = 0;
        _status = EngineStatus.idle;
        return;
      }

      _elapsedBeforeStart = elapsed < 0 ? 0 : elapsed;
      _remainingMs = (_phases[_index].duration * 1000 - _elapsedBeforeStart)
          .clamp(0, 1 << 31);
      _lastAnnouncedSecond = -1;
      _phaseStartWall = null;

      if (savedStatus == 'running') {
        _status = EngineStatus.running;
        _phaseStartWall = DateTime.now();
        _startTicker();
      } else {
        _status = EngineStatus.paused;
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('snapshot restore failed: $e');
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
