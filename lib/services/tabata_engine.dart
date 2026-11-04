import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/phase.dart';
import '../models/tabata_config.dart';
import 'audio_coach.dart';

enum EngineStatus { idle, running, paused, finished }

/// 사운드 이벤트 기록 (타이머-사운드 싱크 검증용)
class CueEvent {
  CueEvent({
    required this.label,
    required this.phaseType,
    required this.roundIndex,
    required this.setIndex,
    required this.scheduledWallMs,
    required this.actualWallMs,
  });

  final String label;
  final String phaseType;
  final int roundIndex;
  final int setIndex;
  final int scheduledWallMs;
  final int actualWallMs;

  /// 예약 시각 대비 실제 발생 오차(ms). 음수면 빠름.
  int get errorMs => actualWallMs - scheduledWallMs;

  @override
  String toString() =>
      'CueEvent($label, ${phaseType}L$roundIndex/S$setIndex, err=${errorMs}ms)';
}

/// 벽시계(DateTime) 단일 기준 타바타 엔진.
///
/// 핵심 설계
/// ---------
/// 1. **시간은 오직 한 곳에서 계산한다.**
///    각 구간은 `구간시작벽시계(_phaseStartWall)` 하나만 들고 있고,
///    경과 시간 = `now - _phaseStartWall` 로 항상 다시 계산한다.
///    화면·사운드 모두 이 값을 읽기만 하므로 서로 어긋날 수 없다.
///
/// 2. **남은 시간을 1씩 감소시키지 않는다.**
///    UI 갱신 주기(50ms)와 실제 시간 진행이 분리되어 있어
///    프레임이 밀려도 남은 시간이 틀어지지 않는다.
///
/// 3. **사운드 이벤트는 벽시계에 맞춰 예약한다.**
///    "N초 남았을 때" 울릴 절대 시각을 계산해 Timer로 예약하고,
///    발화 시점에 현재 시각과 다시 비교해 오차를 보정한다.
///    → 화면 갱신 지연이 소리 시점을 밀지 않는다.
///
/// 4. **구간 전환은 초과분(overshoot)을 이월**해 시간 손실·중복이 없다.
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

  /// 현재 구간의 '가상 시작 시각'. (이미 소비한 시간만큼 과거로 밀어 둔다)
  /// 일시정지 중에는 null.
  DateTime? _phaseStartWall;

  /// 일시정지 시점의 구간 경과 시간
  int _pausedElapsedMs = 0;

  /// 완료된 구간들의 경과 시간 누적 (완료 화면 총 시간)
  int _accumulatedMs = 0;

  /// 이 구간에서 이미 안내한 카운트다운 숫자
  final Set<int> _announced = <int>{};

  // 스케줄러
  final List<Timer> _eventTimers = <Timer>[];
  Timer? _uiTicker;

  bool _disposed = false;

  /// 검증용 이벤트 로그 (최근 200개)
  final List<CueEvent> cueLog = <CueEvent>[];

  /// (검증용) 사운드를 실제로 켤지 여부. 테스트에서는 끈다.
  bool audioOutputEnabled = true;

  // -------------------------------------------------------- 시간 계산

  Phase? get currentPhase =>
      (_index >= 0 && _index < _phases.length) ? _phases[_index] : null;

  Phase? get nextPhase =>
      (_index + 1 < _phases.length) ? _phases[_index + 1] : null;

  int get _phaseDurationMs => (currentPhase?.duration ?? 0) * 1000;

  /// 현재 구간에서 흐른 시간 (ms)
  int get elapsedInPhaseMs {
    if (_status == EngineStatus.finished) return _phaseDurationMs;
    if (_status == EngineStatus.idle) return 0;
    final start = _phaseStartWall;
    if (_status == EngineStatus.running && start != null) {
      final v = DateTime.now().difference(start).inMilliseconds;
      return v < 0 ? 0 : v;
    }
    return _pausedElapsedMs;
  }

  /// 현재 구간 남은 시간 (ms) — 항상 지금 시각 기준으로 재계산
  int get remainingMs {
    final cur = currentPhase;
    if (cur == null) return 0;
    if (_status == EngineStatus.idle) return cur.duration * 1000;
    if (_status == EngineStatus.finished) return 0;
    final r = _phaseDurationMs - elapsedInPhaseMs;
    return r < 0 ? 0 : r;
  }

  /// 남은 시간(초) — 0.05초 남아도 1초로 표시해 0이 먼저 보이지 않게 한다.
  int get remainingSeconds {
    final cur = currentPhase;
    if (cur == null) return 0;
    if (_status == EngineStatus.idle) return cur.duration;
    if (_status == EngineStatus.finished) return 0;
    return (remainingMs / 1000).ceil().clamp(0, cur.duration);
  }

  int get totalSeconds => _phases.fold<int>(0, (a, p) => a + p.duration);

  /// 전체 남은 시간(초)
  int get remainingTotalSeconds {
    if (_status == EngineStatus.finished) return 0;
    var remain = remainingSeconds;
    for (var i = _index + 1; i < _phases.length; i++) {
      remain += _phases[i].duration;
    }
    return remain;
  }

  /// 전체 진행률 0.0 ~ 1.0
  double get totalProgress {
    final total = totalSeconds;
    if (total == 0) return 0;
    if (_status == EngineStatus.finished) return 1;
    var done = 0.0;
    for (var i = 0; i < _index && i < _phases.length; i++) {
      done += _phases[i].duration;
    }
    final cur = currentPhase;
    if (cur != null) {
      done += (elapsedInPhaseMs / 1000).clamp(0.0, cur.duration.toDouble());
    }
    return (done / total).clamp(0.0, 1.0);
  }

  /// 실제로 흐른 총 시간 (완료 화면)
  int get elapsedTotalMs {
    if (_status == EngineStatus.finished) return _accumulatedMs;
    if (_status == EngineStatus.idle) return 0;
    return _accumulatedMs + elapsedInPhaseMs;
  }

  // -------------------------------------------------------- 라운드/세트

  int get currentRound {
    final cur = currentPhase;
    if (cur == null) return 1;
    return cur.roundIndex == 0 ? 1 : cur.roundIndex;
  }

  int get totalRoundsPerSet => currentPhase?.totalRounds ?? _config.rounds;

  int get currentSet => currentPhase?.setIndex ?? 1;

  int get totalSets => currentPhase?.totalSets ?? _config.sets;

  int get globalRound {
    final cur = currentPhase;
    if (cur == null) return 1;
    if (cur.type == PhaseType.prepare) return 1;
    return (cur.setIndex - 1) * cur.totalRounds + cur.roundIndex;
  }

  int get globalTotalRounds => _config.totalRounds;

  String get phaseType => currentPhase?.type.name ?? 'prepare';

  /// 대기 화면 복귀 등에서 쓰는 완료 통계
  int get completedRounds => _completedRounds;
  int _completedRounds = 0;

  int get completedSets => _completedSets;
  int _completedSets = 0;

  // -------------------------------------------------------- 제어

  void _rebuild() {
    _cancelTimers();
    _phases
      ..clear()
      ..addAll(_config.buildPhases());
    _index = 0;
    _phaseStartWall = null;
    _pausedElapsedMs = 0;
    _accumulatedMs = 0;
    _announced.clear();
    _completedRounds = 0;
    _completedSets = 0;
  }

  void updateConfig(TabataConfig config) {
    _config = config;
    _stopUiTicker();
    _status = EngineStatus.idle;
    _rebuild();
    _applyAudioSettings();
    notifyListeners();
  }

  void reset() {
    _cancelTimers();
    _stopUiTicker();
    _status = EngineStatus.idle;
    _rebuild();
    _applyAudioSettings();
    AudioCoach.instance.stopAll();
    notifyListeners();
  }

  void start() {
    // 완료 직후이거나 인덱스가 끝을 가리키면 구간을 처음부터 다시 만든다.
    if (_phases.isEmpty ||
        _status == EngineStatus.finished ||
        _index >= _phases.length) {
      _rebuild();
    }
    if (_phases.isEmpty) return;

    _applyAudioSettings();
    unawaited(AudioCoach.instance.warmUp());

    _status = EngineStatus.running;
    _index = 0;
    _accumulatedMs = 0;
    _pausedElapsedMs = 0;
    _announced.clear();
    _completedRounds = 0;
    _completedSets = 0;
    _phaseStartWall = DateTime.now();

    _startUiTicker();
    _enterPhase(currentPhase, isStart: true);
    _scheduleEvents();
    notifyListeners();
  }

  void pause() {
    if (_status != EngineStatus.running) return;
    _pausedElapsedMs = elapsedInPhaseMs;
    _phaseStartWall = null;
    _status = EngineStatus.paused;

    _stopUiTicker();
    _cancelEventTimers();
    // 카운트다운 음성이 즉시 끊겨야 한다.
    unawaited(AudioCoach.instance.stopAll());

    notifyListeners();
  }

  void resume() {
    if (_status != EngineStatus.paused) return;
    _status = EngineStatus.running;
    // 일시정지 동안 흐른 시간을 제외하고 같은 지점에서 이어진다.
    _phaseStartWall = DateTime.now().subtract(
      Duration(milliseconds: _pausedElapsedMs),
    );
    _startUiTicker();
    _scheduleEvents();
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
    unawaited(AudioCoach.instance.stopAll());
    _advanceFrom(elapsedMs: elapsedInPhaseMs, announce: false);
    if (_status == EngineStatus.running) {
      _startUiTicker();
      _scheduleEvents();
    }
    notifyListeners();
  }

  /// 앱 복귀 시 밀린 구간 정산 (백그라운드에서 시간이 흘렀을 수 있다)
  void catchUp() {
    if (_status != EngineStatus.running) return;
    // 백그라운드 동안 타이머가 멈췄을 수 있으므로 예약을 다시 건다.
    _scheduleEvents();
    _reconcile();
    notifyListeners();
  }

  // -------------------------------------------------------- 내부

  void _applyAudioSettings() {
    final c = AudioCoach.instance;
    c.soundEnabled = _config.soundEnabled;
    c.voiceEnabled = _config.voiceEnabled;
    c.sfxEnabled = _config.sfxEnabled;
  }

  void _startUiTicker() {
    _stopUiTicker();
    // 화면 갱신 전용. 시간 계산에는 관여하지 않는다.
    _uiTicker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_status != EngineStatus.running) return;
      // 안전망: 예약 타이머가 어떤 이유로든 늦으면 여기서 따라잡는다.
      if (remainingMs <= 0) _reconcile();
      notifyListeners();
    });
  }

  void _stopUiTicker() {
    _uiTicker?.cancel();
    _uiTicker = null;
  }

  void _cancelEventTimers() {
    for (final t in _eventTimers) {
      t.cancel();
    }
    _eventTimers.clear();
  }

  void _cancelTimers() {
    _cancelEventTimers();
    _stopUiTicker();
  }

  void _record(String label, DateTime scheduled, {int? round, int? set}) {
    if (!kDebugMode) return;
    final cur = currentPhase;
    cueLog.add(
      CueEvent(
        label: label,
        phaseType: cur?.type.name ?? '-',
        roundIndex: round ?? cur?.roundIndex ?? 0,
        setIndex: set ?? cur?.setIndex ?? 0,
        scheduledWallMs: scheduled.millisecondsSinceEpoch,
        actualWallMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (cueLog.length > 200) cueLog.removeAt(0);
  }

  /// 현재 구간에 필요한 사운드 이벤트를 절대 시각 기준으로 예약한다.
  void _scheduleEvents() {
    _cancelEventTimers();
    if (_status != EngineStatus.running) return;
    final cur = currentPhase;
    final start = _phaseStartWall;
    if (cur == null || start == null) return;

    final durationMs = cur.duration * 1000;
    final elapsed = elapsedInPhaseMs;

    // --- 마지막 5초 카운트다운 ---------------------------------
    if (cur.hasCountdown) {
      for (var n = 5; n >= 1; n--) {
        if (_announced.contains(n)) continue;
        final atMs = durationMs - n * 1000;
        final delayMs = atMs - elapsed;
        if (delayMs < -250) {
          // 이미 지난 숫자(복귀 직후 등)는 건너뛴다 — 몰아서 재생하지 않는다.
          _announced.add(n);
          continue;
        }
        _scheduleAt(
          start.add(Duration(milliseconds: atMs)),
          delayMs < 0 ? 0 : delayMs,
          label: 'count$n',
          onFire: () {
            if (_status != EngineStatus.running || _disposed) return;
            if (currentPhase != cur) return;
            if (_announced.contains(n)) return;
            _announced.add(n);
            if (audioOutputEnabled) AudioCoach.instance.playCount(n);
          },
        );
      }
    }

    // --- 구간 종료(다음 구간 시작 = 전환음) ---------------------
    final endDelay = durationMs - elapsed;
    _scheduleAt(
      start.add(Duration(milliseconds: durationMs)),
      endDelay < 0 ? 0 : endDelay,
      label: 'end',
      onFire: () {
        if (_status != EngineStatus.running || _disposed) return;
        _reconcile();
      },
    );
  }

  /// 벽시계 검증이 포함된 정확 예약.
  void _scheduleAt(
    DateTime target,
    int delayMs, {
    required String label,
    required VoidCallback onFire,
  }) {
    final t = Timer(Duration(milliseconds: delayMs < 0 ? 0 : delayMs), () {
      if (_disposed) return;
      final now = DateTime.now();
      // 너무 일찍 깨어났으면 남은 시간만큼 다시 예약 (드리프트 보정)
      final delta = target.difference(now).inMilliseconds;
      if (delta > 12) {
        _scheduleAt(
          target,
          delta - 4,
          label: label,
          onFire: onFire,
        );
        return;
      }
      _record(label, target);
      onFire();
    });
    _eventTimers.add(t);
  }

  /// 실제 경과 시간과 구간 경계를 대조해 필요한 만큼 전진시킨다.
  void _reconcile() {
    if (_status != EngineStatus.running) return;
    var guard = 0;
    while (guard++ < 4000) {
      final cur = currentPhase;
      final start = _phaseStartWall;
      if (cur == null || start == null) return;
      final durationMs = cur.duration * 1000;
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      if (elapsed < durationMs) {
        return;
      }
      _advanceFrom(elapsedMs: elapsed);
      if (_status != EngineStatus.running) return;
    }
  }

  /// 현재 구간에서 경과한 시간을 반영해 다음 구간으로 넘어간다.
  void _advanceFrom({required int elapsedMs, bool announce = true}) {
    final prev = currentPhase;
    if (prev == null) return;

    final durationMs = prev.duration * 1000;
    final consumed = elapsedMs.clamp(0, durationMs);
    _accumulatedMs += consumed;
    if (prev.type == PhaseType.work) _completedRounds += 1;
    if (prev.type == PhaseType.setRest) _completedSets = prev.setIndex;

    // 초과분을 다음 구간으로 이월 → 시간 손실/중복 없음
    final carry = elapsedMs - durationMs;

    _index = _index + 1;
    _announced.clear();
    _cancelEventTimers();

    if (_index >= _phases.length) {
      _finish();
      return;
    }

    _phaseStartWall = DateTime.now().subtract(
      Duration(milliseconds: carry < 0 ? 0 : carry),
    );
    _pausedElapsedMs = carry < 0 ? 0 : carry;

    if (announce && _status == EngineStatus.running) {
      _enterPhase(currentPhase, isStart: false);
    }
    if (_status == EngineStatus.running) _scheduleEvents();
  }

  void _enterPhase(Phase? phase, {required bool isStart}) {
    if (phase == null) return;
    _recordOnEnter(phase);
    _applyAudioSettings();
    if (!audioOutputEnabled) return;

    final coach = AudioCoach.instance;
    switch (phase.type) {
      case PhaseType.prepare:
        break; // 준비 구간은 조용히 (카운트다운 후 시작음)
      case PhaseType.work:
        coach.playCue(CueKind.workStart);
        coach.vibrate();
      case PhaseType.rest:
        coach.playCue(CueKind.restStart);
      case PhaseType.setRest:
        coach.playCue(CueKind.setRestStart);
    }
  }

  void _recordOnEnter(Phase phase) {
    if (!kDebugMode) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    cueLog.add(
      CueEvent(
        label: 'enter:${phase.type.name}',
        phaseType: phase.type.name,
        roundIndex: phase.roundIndex,
        setIndex: phase.setIndex,
        scheduledWallMs: now,
        actualWallMs: now,
      ),
    );
    if (cueLog.length > 200) cueLog.removeAt(0);
  }

  void _finish() {
    _cancelTimers();
    _status = EngineStatus.finished;
    _phaseStartWall = null;
    _completedSets = _config.sets;
    _completedRounds = _config.sets * _config.rounds;
    if (audioOutputEnabled) {
      AudioCoach.instance.playCue(CueKind.finish);
    }
    notifyListeners();
  }

  // -------------------------------------------------------- 스냅샷

  Map<String, dynamic> snapshot() => {
    'status': _status.name,
    'index': _index,
    'elapsedInPhaseMs': elapsedInPhaseMs,
    'accumulatedMs': _accumulatedMs,
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
      if (savedStatus != 'running' && savedStatus != 'paused') return;

      final savedIndex = snap['index'];
      if (savedIndex is! int ||
          savedIndex < 0 ||
          savedIndex >= _phases.length) {
        return;
      }

      _index = savedIndex;
      var elapsed = snap['elapsedInPhaseMs'] is int
          ? snap['elapsedInPhaseMs'] as int
          : 0;

      // 앱이 죽어 있던 동안 흐른 시간 반영
      final savedAt = snap['savedAt'];
      final gap = savedStatus == 'running' && savedAt is int
          ? DateTime.now().millisecondsSinceEpoch - savedAt
          : 0;
      if (gap > 0) elapsed += gap;

      // 밀린 구간 정산
      var guard = 0;
      while (guard++ < 4000 && _index < _phases.length) {
        final durationMs = _phases[_index].duration * 1000;
        if (elapsed < durationMs) break;
        elapsed -= durationMs;
        if (_phases[_index].type == PhaseType.work) _completedRounds++;
        _index++;
      }

      if (_index >= _phases.length) {
        _index = _phases.length - 1;
        _status = EngineStatus.idle;
        notifyListeners();
        return;
      }

      final acc = snap['accumulatedMs'];
      _accumulatedMs = acc is int ? acc : 0;
      final completed = snap['completedRounds'];
      if (completed is int) _completedRounds = completed;
      final setsDone = snap['completedSets'];
      if (setsDone is int) _completedSets = setsDone;

      _applyAudioSettings();

      if (savedStatus == 'running') {
        _status = EngineStatus.running;
        _pausedElapsedMs = elapsed;
        _phaseStartWall = DateTime.now().subtract(
          Duration(milliseconds: elapsed),
        );
        _startUiTicker();
        _scheduleEvents();
      } else {
        _status = EngineStatus.paused;
        _pausedElapsedMs = elapsed;
        _phaseStartWall = null;
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('restore failed: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }
}
