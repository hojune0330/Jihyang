import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/phase.dart';
import '../models/tabata_config.dart';
import 'audio_coach.dart';

enum EngineStatus { idle, running, paused, finished }

/// 벽시계(DateTime) 기반 타바타 엔진.
///
/// 남은 시간을 틱 누적이 아니라 `현재시각 - 구간시작시각`으로 계산하므로
/// 화면 갱신이 늦거나 프레임이 멈춰도 시간이 틀어지지 않는다.
/// 구간 전환 시 초과분(overshoot)을 다음 구간으로 이월해 시간 손실/중복을 없앤다.
class TabataEngine extends ChangeNotifier {
  TabataEngine({TabataConfig? config})
    : _config = config ?? const TabataConfig() {
    _rebuild();
  }

  TabataConfig _config;
  TabataConfig get config => _config;

  final List<Phase> _phases = <Phase>[];

  /// 완료 화면에서 사용할 스냅샷 (phases를 리셋해도 유지)
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

  /// 현재 구간 시작 시각 (일시정지 중에는 null)
  DateTime? _phaseStartWall;

  /// 현재 구간에서 이미 소비한 시간(ms) — 일시정지 누적분
  int _elapsedInPhaseMs = 0;

  int _remainingMs = 0;

  /// 이미 안내한 카운트다운 숫자 (중복 방지)
  final Set<int> _announcedCounts = <int>{};

  /// 완료 통계
  int _completedRounds = 0;
  int _completedSets = 0;
  int _elapsedTotalMs = 0;
  DateTime? _sessionStartWall;

  int get completedRounds => _completedRounds;
  int get completedSets => _completedSets;

  /// 실제로 흐른 총 시간(ms) — 완료 화면에서 사용
  int get elapsedTotalMs {
    if (_status == EngineStatus.finished) return _elapsedTotalMs;
    final start = _sessionStartWall;
    if (start == null) return 0;
    if (_status == EngineStatus.running) {
      return DateTime.now().difference(start).inMilliseconds;
    }
    return _elapsedTotalMs;
  }

  Phase? get currentPhase =>
      (_index >= 0 && _index < _phases.length) ? _phases[_index] : null;

  Phase? get nextPhase =>
      (_index + 1 < _phases.length) ? _phases[_index + 1] : null;

  // --------------------------------------------------------- 시간 계산

  int get _phaseElapsedMs {
    var base = _elapsedInPhaseMs;
    final start = _phaseStartWall;
    if (_status == EngineStatus.running && start != null) {
      base += DateTime.now().difference(start).inMilliseconds;
    }
    return base;
  }

  /// 현재 구간 남은 시간(ms)
  int get remainingMs {
    final cur = currentPhase;
    if (cur == null) return 0;
    if (_status == EngineStatus.idle) return cur.duration * 1000;
    return _remainingMs.clamp(0, cur.duration * 1000);
  }

  /// 남은 시간(초) — 0.05초 남아도 1초로 표시
  int get remainingSeconds {
    final cur = currentPhase;
    if (cur == null) return 0;
    if (_status == EngineStatus.idle) return cur.duration;
    return (_remainingMs / 1000).ceil().clamp(0, cur.duration);
  }

  int get totalSeconds => _phases.fold<int>(0, (a, p) => a + p.duration);

  int get remainingTotalSeconds {
    var remain = remainingSeconds;
    for (var i = _index + 1; i < _phases.length; i++) {
      remain += _phases[i].duration;
    }
    return remain;
  }

  double get totalProgress {
    final total = totalSeconds;
    if (total == 0) return 0;
    if (_status == EngineStatus.finished) return 1;
    var elapsed = 0;
    for (var i = 0; i < _index && i < _phases.length; i++) {
      elapsed += _phases[i].duration;
    }
    final cur = currentPhase;
    if (cur != null) elapsed += cur.duration - remainingSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  /// 현재 라운드(세트 내)와 전체 라운드 번호
  int get currentRound {
    final cur = currentPhase;
    if (cur == null) return 1;
    return cur.roundIndex == 0 ? 1 : cur.roundIndex;
  }

  int get totalRoundsPerSet {
    final cur = currentPhase;
    return cur?.totalRounds ?? _config.rounds;
  }

  int get currentSet {
    final cur = currentPhase;
    return cur?.setIndex ?? 1;
  }

  int get totalSets => currentPhase?.totalSets ?? _config.sets;

  /// 세트를 합친 전체 라운드 번호
  int get globalRound {
    final cur = currentPhase;
    if (cur == null) return 1;
    final perSet = cur.totalRounds;
    if (cur.type == PhaseType.prepare) return 1;
    return (cur.setIndex - 1) * perSet + cur.roundIndex;
  }

  int get globalTotalRounds => _config.totalRounds;

  String get phaseType => currentPhase?.type.name ?? 'prepare';

  // --------------------------------------------------------- 제어

  void _rebuild() {
    _phases
      ..clear()
      ..addAll(_config.buildPhases());
    _index = 0;
    _elapsedInPhaseMs = 0;
    _phaseStartWall = null;
    _remainingMs = _phases.isEmpty ? 0 : _phases.first.duration * 1000;
    _announcedCounts.clear();
    _completedRounds = 0;
    _completedSets = 0;
    _elapsedTotalMs = 0;
    _sessionStartWall = null;
  }

  void updateConfig(TabataConfig config) {
    _config = config;
    _stopTicker();
    _status = EngineStatus.idle;
    _rebuild();
    notifyListeners();
  }

  void reset() {
    _stopTicker();
    _status = EngineStatus.idle;
    _rebuild();
    AudioCoach.instance.stopAll();
    notifyListeners();
  }

  void start() {
    // 완료 직후이거나 인덱스가 끝을 가리키면 구간을 처음부터 다시 만든다.
    // (이 처리가 없으면 종료 후 재시작 시 곧바로 _finish()로 튕겨나간다)
    if (_phases.isEmpty ||
        _status == EngineStatus.finished ||
        _index >= _phases.length) {
      _rebuild();
    }
    if (_phases.isEmpty) return;

    _status = EngineStatus.running;
    _phaseStartWall = DateTime.now();
    _sessionStartWall = DateTime.now();
    _elapsedInPhaseMs = 0;
    _elapsedTotalMs = 0;
    _remainingMs = (currentPhase?.duration ?? 0) * 1000;
    _announcedCounts.clear();
    _completedRounds = 0;
    _completedSets = 0;

    AudioCoach.instance.voiceEnabled = _config.voiceEnabled;
    AudioCoach.instance.sfxEnabled = _config.sfxEnabled;

    _startTicker();
    _onPhaseEntered(currentPhase, isStart: true);
    notifyListeners();
  }

  void pause() {
    if (_status != EngineStatus.running) return;
    _elapsedInPhaseMs = _phaseElapsedMs;
    _elapsedTotalMs = elapsedTotalMs;
    _phaseStartWall = null;
    _status = EngineStatus.paused;
    _stopTicker();
    AudioCoach.instance.stopAll();
    notifyListeners();
  }

  void resume() {
    if (_status != EngineStatus.paused) return;
    _status = EngineStatus.running;
    _phaseStartWall = DateTime.now();
    // 세션 시작 시각 보정 (일시정지 동안의 시간 제외)
    if (_sessionStartWall != null) {
      _sessionStartWall = DateTime.now().subtract(
        Duration(milliseconds: _elapsedTotalMs),
      );
    }
    _startTicker();
    _sync(allowAudio: false);
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
    if (_status != EngineStatus.running && _status != EngineStatus.paused) {
      return;
    }
    AudioCoach.instance.stopAll();
    _advanceTo(_index + 1, carryMs: 0, announce: false);
    if (_status == EngineStatus.running) {
      _phaseStartWall = DateTime.now();
      _startTicker();
    }
    notifyListeners();
  }

  /// 앱 복귀 시 밀린 구간 정산
  void catchUp() {
    if (_status != EngineStatus.running) return;
    _sync(allowAudio: true, isCatchUp: true);
    notifyListeners();
  }

  // --------------------------------------------------------- 내부

  void _startTicker() {
    _stopTicker();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _sync());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _sync({bool allowAudio = true, bool isCatchUp = false}) {
    if (_status != EngineStatus.running || _phases.isEmpty) return;

    var guard = 0;
    while (guard++ < 5000) {
      final cur = currentPhase;
      if (cur == null) return;

      final remain = cur.duration * 1000 - _phaseElapsedMs;

      if (remain > 0) {
        _remainingMs = remain;
        if (allowAudio) _handleCountdown(cur, remain);
        notifyListeners();
        return;
      }

      // 구간 초과분을 다음 구간으로 이월 (시간 손실/중복 방지)
      final carry = -remain;
      if (carry >= cur.duration * 1000) {
        // 구간을 통째로 건너뛰는 경우 carry는 잘라서 무한 루프 방지
      }
      _advanceTo(
        _index + 1,
        carryMs: carry,
        announce: !isCatchUp || carry < 1000,
      );
      if (_status != EngineStatus.running) return;
    }
  }

  void _advanceTo(int nextIndex, {required int carryMs, bool announce = true}) {
    final prev = currentPhase;

    // 통계 반영
    if (prev != null && prev.type == PhaseType.work) {
      _completedRounds += 1;
    }
    if (prev != null && prev.type == PhaseType.setRest) {
      _completedSets = prev.setIndex;
    }

    _index = nextIndex;
    _announcedCounts.clear();

    if (_index >= _phases.length) {
      _finish();
      return;
    }

    final next = _phases[_index];
    _elapsedInPhaseMs = carryMs < 0 ? 0 : carryMs;
    _phaseStartWall = _status == EngineStatus.running ? DateTime.now() : null;
    _remainingMs = (next.duration * 1000 - _elapsedInPhaseMs).clamp(0, 1 << 31);

    if (announce) _onPhaseEntered(next, isStart: false);
  }

  void _onPhaseEntered(Phase? phase, {required bool isStart}) {
    if (phase == null) return;
    final coach = AudioCoach.instance;
    coach.voiceEnabled = _config.voiceEnabled;
    coach.sfxEnabled = _config.sfxEnabled;

    switch (phase.type) {
      case PhaseType.prepare:
        break;
      case PhaseType.work:
        coach.announceWorkStart(
          round: phase.roundIndex,
          totalRounds: phase.totalRounds,
          set: phase.setIndex,
          totalSets: phase.totalSets,
        );
        if (_config.voiceEnabled) coach.vibrate();
      case PhaseType.rest:
        coach.announceRestStart(seconds: phase.duration);
      case PhaseType.setRest:
        coach.announceSetRestStart(
          seconds: phase.duration,
          nextSet: phase.setIndex + 1,
        );
    }
  }

  void _handleCountdown(Phase phase, int remainMs) {
    if (!phase.hasCountdown) return;
    final secs = (remainMs / 1000).ceil();
    if (secs > 5 || secs < 1) return;
    if (_announcedCounts.contains(secs)) return;
    _announcedCounts.add(secs);
    AudioCoach.instance.sayCount(secs);
    if (AudioCoach.instance.voiceEnabled && secs <= 2) {
      AudioCoach.instance.vibrate();
    }
  }

  void _finish() {
    _stopTicker();
    _elapsedTotalMs = elapsedTotalMs;
    _status = EngineStatus.finished;
    _remainingMs = 0;
    _elapsedInPhaseMs = 0;
    _phaseStartWall = null;
    if (_completedSets == 0) {
      _completedSets = _config.sets;
    }
    _completedRounds = _config.sets * _config.rounds;
    AudioCoach.instance.announceFinish(
      sets: _config.sets,
      rounds: _config.rounds,
    );
    notifyListeners();
  }

  // --------------------------------------------------------- 스냅샷

  Map<String, dynamic> snapshot() => {
    'status': _status.name,
    'index': _index,
    'elapsedInPhaseMs': _status == EngineStatus.running
        ? _phaseElapsedMs
        : _elapsedInPhaseMs,
    'elapsedTotalMs': elapsedTotalMs,
    'completedRounds': _completedRounds,
    'completedSets': _completedSets,
    'savedAt': DateTime.now().millisecondsSinceEpoch,
    'config': _config.toJson(),
  };

  void restoreFromSnapshot(Map<String, dynamic> snap) {
    try {
      final configJson = snap['config'];
      if (configJson is Map) {
        _config = TabataConfig.fromJson(Map<String, dynamic>.from(configJson));
      }
      _rebuild();

      final savedStatus = snap['status'];
      final savedIndex = snap['index'];
      final savedElapsed = snap['elapsedInPhaseMs'];
      final savedAt = snap['savedAt'];
      final savedTotal = snap['elapsedTotalMs'];

      if (savedStatus != 'running' && savedStatus != 'paused') return;
      if (savedIndex is! int ||
          savedIndex < 0 ||
          savedIndex >= _phases.length) {
        return;
      }

      _index = savedIndex;
      var elapsed = savedElapsed is int ? savedElapsed : 0;
      final gap = savedStatus == 'running' && savedAt is int
          ? DateTime.now().millisecondsSinceEpoch - savedAt
          : 0;
      if (gap > 0) elapsed += gap;

      // 밀린 구간 정산
      var guard = 0;
      while (guard++ < 5000 && _index < _phases.length) {
        final durationMs = _phases[_index].duration * 1000;
        if (elapsed < durationMs) break;
        elapsed -= durationMs;
        if (_phases[_index].type == PhaseType.work) _completedRounds++;
        _index++;
      }

      if (_index >= _phases.length) {
        _index = _phases.length - 1;
        _status = EngineStatus.idle;
        return;
      }

      _elapsedInPhaseMs = elapsed.clamp(0, _phases[_index].duration * 1000);
      _remainingMs = _phases[_index].duration * 1000 - _elapsedInPhaseMs;
      final completed = snap['completedRounds'];
      if (completed is int) _completedRounds = completed;
      final setsDone = snap['completedSets'];
      if (setsDone is int) _completedSets = setsDone;
      _elapsedTotalMs = savedTotal is int ? savedTotal + gap : 0;

      if (savedStatus == 'running') {
        _status = EngineStatus.running;
        _phaseStartWall = DateTime.now();
        _sessionStartWall = DateTime.now().subtract(
          Duration(milliseconds: _elapsedTotalMs),
        );
        _startTicker();
      } else {
        _status = EngineStatus.paused;
        _phaseStartWall = null;
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('restore failed: $e');
    }
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
