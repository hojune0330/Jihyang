import 'dart:js_interop';

/// `window.__tabataAudio` (web/audio_bridge.js) 의 Dart 쪽 래퍼.
///
/// ## 설계 의도
///
/// 브라우저 오디오는 "재생 요청 → 준비 → 소리" 사이에 지연이 있고,
/// 사용자 제스처 없이는 아예 잠겨 있다. 그 문제를 JS 한 곳에서 모두
/// 처리하고, Dart 는 **결과(성공/실패)만** 받는다.
///
/// 여기서는 예외를 던지지 않는다. 브리지 스크립트가 로드되지 않은
/// 환경(구형 브라우저, 스크립트 차단)에서도 타이머 앱 자체는 정상
/// 동작해야 하기 때문이다.
@JS('__tabataAudio')
external _Bridge? get _bridge;

extension type _Bridge._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> unlock();
  external JSPromise<JSObject> preload(JSArray<JSString> assets);
  external JSBoolean isReady(String asset);
  external JSBoolean play(
    String asset,
    String role,
    double volume,
    int offsetMs,
    int whenMs,
    bool interrupt,
  );
  external void stopRole(String role);
  external void stopAll();
  external void setMasterVolume(double v);
  external JSObject status();
}

class WebAudio {
  const WebAudio();

  static bool _hasBridge() {
    try {
      return _bridge != null;
    } catch (_) {
      return false;
    }
  }

  /// 브리지 스크립트가 실제로 붙었는가
  bool get available => _hasBridge();

  /// 오디오 잠금이 해제됐는가
  bool get unlocked {
    if (!_hasBridge()) return false;
    try {
      final s = _bridge!.status().dartify();
      if (s is Map) return s['unlocked'] == true;
    } catch (_) {}
    return false;
  }

  /// 사용자 제스처 안에서 호출해야 잠금이 풀린다.
  Future<bool> unlock() async {
    if (!_hasBridge()) return false;
    try {
      final r = await _bridge!.unlock().toDart;
      return r.toDart;
    } catch (_) {
      return false;
    }
  }

  /// 자산을 미리 받아 디코딩한다. 성공 개수를 돌려준다.
  Future<int> preload(List<String> assets) async {
    if (!_hasBridge() || assets.isEmpty) return 0;
    try {
      final arr = assets.map((e) => e.toJS).toList().toJS;
      final res = await _bridge!.preload(arr).toDart;
      final m = res.dartify();
      if (m is Map) {
        final ok = m['ok'];
        if (ok is int) return ok;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// 디코딩이 끝나 즉시 재생 가능한 상태인가
  bool isReady(String asset) {
    if (!_hasBridge()) return false;
    try {
      return _bridge!.isReady(asset).toDart;
    } catch (_) {
      return false;
    }
  }

  /// 재생. 브라우저가 거부하면 false 를 돌려준다 (예외 없음).
  bool play(
    String asset, {
    required String role,
    double volume = 1.0,
    int offsetMs = 0,
    int whenMs = 0,
    bool interrupt = true,
  }) {
    if (!_hasBridge()) return false;
    try {
      return _bridge!
          .play(asset, role, volume, offsetMs, whenMs, interrupt)
          .toDart;
    } catch (_) {
      return false;
    }
  }

  void stopRole(String role) {
    if (!_hasBridge()) return;
    try {
      _bridge!.stopRole(role);
    } catch (_) {}
  }

  void stopAll() {
    if (!_hasBridge()) return;
    try {
      _bridge!.stopAll();
    } catch (_) {}
  }

  void setMasterVolume(double v) {
    if (!_hasBridge()) return;
    try {
      _bridge!.setMasterVolume(v);
    } catch (_) {}
  }

  /// 진단용 (테스트/로그)
  Map<String, Object?> status() {
    if (!_hasBridge()) return const {'supported': false};
    try {
      final s = _bridge!.status().dartify();
      if (s is Map) return s.map((k, v) => MapEntry('$k', v));
    } catch (_) {}
    return const {'supported': false};
  }
}
