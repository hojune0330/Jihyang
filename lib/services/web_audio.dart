/// 웹 오디오 브리지 — 조건부 임포트 진입점.
///
/// * 웹  → `dart:js_interop` 로 `window.__tabataAudio` 를 직접 호출
/// * 그 외 → 아무것도 하지 않는 스텁 (모바일은 audioplayers 사용)
library;

export 'web_audio_stub.dart' if (dart.library.js_interop) 'web_audio_impl.dart';
