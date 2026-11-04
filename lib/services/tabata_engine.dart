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

  /// 이 구간에서 카운트다운 묶음 재생을 이미 시작했는지.
  ///
  /// [catchUp]·[resume] 으로 [_scheduleEvents] 가 다시 돌 때 묶음을 **또**
  /// 재생하면 이미 울린 숫자와 겹친다. (실기기 버그: "중복돼서 말하거나
  /// 안 들리다가 들린다") 그래서 구간당 정확히 한 번만 시작한다.
  bool _countStarted = false;

  /// 묶음을 시작한 시점의 벽시계 — 재생이 끝났는지 판단하는 기준.
  DateTime? _countStartedWall;

  /// 묶음에서 재생을 시작한 타임라인 위치(ms). 5→0, 4→1000, 3→2000 …
  int _countStartPosMs = 0;

  /// 현재 구간에 울릴 안내 계획 (효과음 + 상태 음성).

  /// 구간 시작 안내(효과음+음성)가 끝날 때까지의 시간(ms).
  ///
  /// 이 시간보다 이른 카운트다운 숫자는 **시작 안내와 겹친다**고 보고 생략한다.
  /// "마지막 1초와 다음 구간 시작 음성이 겹치지 않게" 하는 장치의 앞쪽 절반이다.
  /// (뒤쪽 절반: 카운트다운 '1'은 구간 종료 1초 전에 울리고, 다음 구간 안내는
  /// 종료 시각에 울리므로 최소 350ms 간격이 확보된다)
  int _announceGuardMs = 0;

  // 스케줄러
  final List<Timer> _eventTimers = <Timer>[];
  Timer? _uiTicker;

  bool _disposed = false;

  /// 검증용 이벤트 로그 (최근 200개)
  final List<CueEvent> cueLog = <CueEvent>[];

  /// (검증용) 사운드를 실제로 켤지 여부. 테스트에서는 끈다.
  bool audioOutputEnabled = true;

  /// 운동 세션 시작 시각 (기록 저장용)
  DateTime? _sessionStartedAt;
  DateTime? get sessionStartedAt => _sessionStartedAt;

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
    _countStarted = false;
    _countStartedWall = null;
    _countStartPosMs = 0;
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
    AudioCoach.instance.cut();
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
    _countStarted = false;
    _countStartedWall = null;
    _countStartPosMs = 0;
    _completedRounds = 0;
    _completedSets = 0;
    _sessionStartedAt = DateTime.now();
    _phaseStartWall = _sessionStartedAt;

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
    // 재생 중이던 카운트다운/안내 음성을 **동기적으로** 무효화한다.
    AudioCoach.instance.cut();
    // 묶음도 끊겼으므로 '재생 중' 표시를 내린다. [_announced] 는 그대로 두어
    // 재개했을 때 이미 울린 숫자를 다시 읽지 않게 한다.
    // → 재개 시에는 **남은 다음 숫자 위치**부터 깔끔하게 이어진다.
    _countStarted = false;
    _countStartedWall = null;

    notifyListeners();
  }

  void resume() {
    if (_status != EngineStatus.paused) return;
    _status = EngineStatus.running;
    // 일시정지 동안 흐른 시간을 제외하고 같은 지점에서 이어진다.
    _phaseStartWall = DateTime.now().subtract(
      Duration(milliseconds: _pausedElapsedMs),
    );
    // 재개 시점부터 카운트다운 예약을 새로 건다 (지난 숫자는 재생하지 않는다).
    AudioCoach.instance.cut();
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
    AudioCoach.instance.cut();
    // 건너뛰기로 들어간 구간도 '전환 순간'이므로 시작 안내는 울린다.
    // (일시정지 상태에서 건너뛰면 소리는 내지 않는다)
    _advanceFrom(
      elapsedMs: elapsedInPhaseMs,
      announce: _status == EngineStatus.running,
    );
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
    AudioCoach.instance.applyConfig(_config);
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
    // 이미 발화 대기 중이던 예약을 무효화한다.
    _scheduleEpoch++;
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
  ///
  /// 이벤트 순서 규칙 (겹침 방지의 핵심)
  /// ------------------------------------
  ///   ① 구간 시작 T+0        : 효과음 → 상태 안내 음성 ([_enterPhase])
  ///   ② 마지막 5초 T-5s..T-1s: 카운트다운 숫자 (시작 안내와 겹치면 생략)
  ///   ③ 구간 종료 T+0        : [_reconcile] → [_advanceFrom] → 다음 구간 ①
  ///
  /// '1'은 T-1s 에 0.65초 이하로 끝나고, 다음 구간 안내는 T+0 에 시작하므로
  /// **최소 350ms 간격**이 항상 확보된다.
  void _scheduleEvents() {
    _cancelEventTimers();
    if (_status != EngineStatus.running) return;
    final cur = currentPhase;
    final start = _phaseStartWall;
    if (cur == null || start == null) return;

    final durationMs = cur.duration * 1000;
    final elapsed = elapsedInPhaseMs;

    // --- 마지막 5초 카운트다운 (모든 시간 구간) -----------------
    //
    // [중요] 초마다 다른 파일을 재생하면 파일 교체마다 stop/seek/resume 이
    // 일어나 '뚝뚝' 끊긴다. 그래서 5·4·3·2·1 이 1초 간격으로 미리 녹음된
    // **묶음 파일 하나**를 '가장 먼저 울릴 숫자' 지점부터 한 번만 재생한다.
    // 숫자 사이 간격은 파일에 새겨져 있으므로 흔들릴 수 없다.
    //
    // 음성 안내를 껐을 때는 묶음 대신 매초 '틱'(sfx_count)을 그대로 쓴다.
    if (cur.hasCountdown) {
      // 숫자 n 은 "구간 종료 n초 전" = `durationMs - n*1000` 지점에 울린다.
      // (n=5 → 0ms 위치 / n=1 → 4000ms 위치)
      //
      // ## 왜 '번호' 가 아니라 '벽시계 위치' 로 재생하는가
      //
      // 묶음 파일은 5·4·3·2·1 이 1초 간격으로 이어진 **하나의 타임라인**이다.
      // 예전에는 "가장 먼저 울릴 숫자" 를 골라 그 번호 지점부터 재생했다.
      // 그러면 [catchUp]·[resume] 으로 스케줄이 다시 걸릴 때마다 그 순간의
      // '남은 숫자' 를 새 시작점으로 잡아 **이미 울린 숫자와 겹쳤다.**
      // (실기기 보고: "5·4·3·2·1 이 싱크가 안 맞고 중복돼서 말하거나
      //  안 들리다가 들린다")
      //
      // 지금은 묶음을 구간당 **한 번만** 시작하고, 재생 위치는 항상
      // '구간 시작으로부터 흐른 시간' 에서 계산한다. 몇 번을 다시 걸어도
      // 타임라인 위의 같은 지점을 가리키므로 겹침도 어긋남도 생기지 않는다.
      for (var n = 5; n >= 1; n--) {
        // 이미 울린 숫자는 다시 예약하지 않는다.
        // (없으면 재개 때 같은 숫자에 타이머가 또 걸려 로그·발화가 중복된다)
        if (_announced.contains(n)) continue;
        final atMs = durationMs - n * countStepMs;
        final delayMs = atMs - elapsed;
        if (atMs < _announceGuardMs) {
          _announced.add(n); // 시작 안내와 겹치는 앞쪽 숫자는 생략
          continue;
        }
        if (delayMs < -countStepMs) {
          _announced.add(n); // 이미 한참 지난 숫자
          continue;
        }

        _scheduleAt(
          start.add(Duration(milliseconds: atMs)),
          delayMs < 0 ? 0 : delayMs,
          label: 'count$n',
          onFire: () {
            if (_disposed) return;
            if (_status != EngineStatus.running) return;
            if (currentPhase != cur) return;
            if (_announced.contains(n)) return;
            _announced.add(n);
            if (!audioOutputEnabled) return;

            if (!AudioCoach.instance.voiceEnabled) {
              // 음성 꺼짐 → 매초 또렷한 틱
              AudioCoach.instance.playSfx(Sfx.count);
              return;
            }

            // 묶음 타임라인 위에서 이 숫자의 위치.
            //   5 → 0ms, 4 → 1000ms, 3 → 2000ms, 2 → 3000ms, 1 → 4000ms
            final targetPos = (5 - n) * countStepMs;
            final now = DateTime.now();

            // ① 아직 시작 전 → 이 위치에서 시작
            if (!_countStarted) {
              _countStarted = true;
              _countStartedWall = now;
              _countStartPosMs = targetPos;
              AudioCoach.instance.playCountBundleAt(targetPos);
              return;
            }

            // ② 이미 재생 중 → **절대 다시 걸지 않는다.**
            //
            // 다시 걸면 이미 울린 숫자와 겹쳐 "중복돼서 말하는" 현상이 된다.
            // (실기기 보고의 직접 원인)
            //
            // 다만 백그라운드에서 재생이 이미 끝나 버렸다면(플레이어 타임아웃
            // 등) 그대로 두면 숫자가 통째로 사라지므로, 그 경우에만 이
            // 숫자부터 새로 시작한다.
            final startedAt = _countStartedWall;
            if (startedAt == null) return;
            final played = now.difference(startedAt).inMilliseconds;
            final remainOfBundle =
                (cntDurMs[_config.voiceStyle.assetKey] ?? 4400) - _countStartPosMs;
            if (played > remainOfBundle + 200) {
              _countStartedWall = now;
              _countStartPosMs = targetPos;
              AudioCoach.instance.playCountBundleAt(targetPos);
            }
            // 그 외에는 아무것도 하지 않는다 (재생 중인 묶음이 계속 이어진다)
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
        if (_disposed) return;
        if (_status != EngineStatus.running) return;
        _reconcile();
      },
    );
  }

  /// 벽시계 검증이 포함된 정확 예약.
  ///
  /// [_scheduleEpoch] 를 함께 기억해 두었다가, 발화 시점에 값이 달라졌으면
  /// (구간 전환 / 일시정지 / 재개) 그 예약은 **폐기**한다.
  /// 타이머 취소가 늦게 반영되거나 재예약과 겹쳐도 이벤트가 중복 발화하지 않는다.
  int _scheduleEpoch = 0;

  void _scheduleAt(
    DateTime target,
    int delayMs, {
    required String label,
    required VoidCallback onFire,
  }) {
    final epoch = _scheduleEpoch;
    final t = Timer(Duration(milliseconds: delayMs < 0 ? 0 : delayMs), () {
      if (_disposed) return;
      if (epoch != _scheduleEpoch) return; // 폐기된 예약
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
      // 백그라운드에서 여러 구간이 밀렸다면 **마지막 구간에서만** 안내한다.
      // (밀린 구간의 음성을 몰아서 재생하는 것을 막는다)
      final carry = elapsed - durationMs;
      final nextIdx = _index + 1;
      final isLastAdvance =
          nextIdx >= _phases.length ||
          carry < _phases[nextIdx].duration * 1000;
      _advanceFrom(elapsedMs: elapsed, announce: isLastAdvance);
      if (_status != EngineStatus.running) return;
    }
  }

  /// 현재 구간에서 경과한 시간을 반영해 다음 구간으로 넘어간다.
  ///
  /// [announce] 는 기본적으로 '실제 시간이 흘러' 넘어갈 때만 true 다.
  /// 백그라운드에서 여러 구간을 한꺼번에 따라잡을 때는 마지막 구간만 안내해
  /// 음성이 몰아서 재생되는 일을 막는다.
  void _advanceFrom({
    required int elapsedMs,
    bool announce = true,
  }) {
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
    _countStarted = false;
    _countStartedWall = null;
    _countStartPosMs = 0;
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

    // 구간 → 안내 계획은 순수 함수 한 곳에서만 결정한다.
    // (재생 여부와 무관하게 '어떤 소리가 선택됐는지'는 항상 기록 → 검증 가능)
    final plan = planForPhase(
      phase,
      totalSets: _config.sets,
      totalRounds: _config.rounds,
    );
    _lastPhasePlan = plan;
    _lastPhaseSfx = plan.sfx;
    _announceGuardMs = announceGuardMs(
      plan,
      _config.voiceStyle,
      sfxEnabled: _config.sfxEnabled,
      voiceEnabled: _config.voiceEnabled,
    );

    if (!audioOutputEnabled) return;

    AudioCoach.instance.announce(plan, phaseType: phase.type.name);
    if (phase.type == PhaseType.work) AudioCoach.instance.vibrate();
  }

  /// (검증용) 마지막으로 예약한 구간 전환 효과음
  Sfx? get lastPhaseSfx => _lastPhaseSfx;
  Sfx? _lastPhaseSfx;

  /// (검증용) 마지막으로 예약한 구간 안내 계획
  AnnouncePlan get lastPhasePlan => _lastPhasePlan;
  AnnouncePlan _lastPhasePlan = const AnnouncePlan();

  /// (검증용) 현재 구간의 카운트다운 보호 구간(ms)
  int get announceGuard => _announceGuardMs;

  /// (검증용) 이 구간에서 이미 울린 카운트다운 숫자 개수
  int get announcedCount => _announced.length;

  /// (검증용) 현재 구간의 안내 시각표
  AnnounceTiming get lastAnnounceTiming => announceTiming(
    _lastPhasePlan,
    _config.voiceStyle,
    sfxEnabled: _config.sfxEnabled,
    voiceEnabled: _config.voiceEnabled,
  );

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
      // 종료도 '구간 전환'과 동일한 순서로 안내한다.
      AudioCoach.instance.announce(finishPlan, phaseType: 'finished');
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
