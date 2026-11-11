// ============================================================================
//  Tabata 오디오 브리지 (웹 전용)
// ============================================================================
//
//  ## 왜 audioplayers 를 웹에서 쓰지 않는가
//
//  1. audioplayers_web 은 **플레이어마다 AudioContext 를 새로 만든다**
//     (`wrapped_player.dart:85  _audioContext ??= web.AudioContext();`)
//     우리는 채널이 4개(안내/카운트/효과음/미리듣기)라 컨텍스트가 4개 생긴다.
//     Safari 는 동시 AudioContext 수를 제한하므로 일부가 조용히 죽는다.
//
//  2. AudioContext 가 **사용자 제스처 없이** 만들어진다. 브라우저는 이 경우
//     컨텍스트를 'suspended' 로 잠근다. 잠긴 컨텍스트는 소리를 전혀 내지
//     않는다. (특히 iOS Safari / 모바일 Chrome)
//     → 이 앱을 받은 사람이 링크를 열면 **아예 무음**이던 원인.
//
//  3. `crossOrigin = 'anonymous'` + MediaElementSource 조합은 서버가
//     CORS 헤더를 주지 않으면 **에러 없이 무음**만 낸다.
//
//  4. HTMLAudioElement 는 재생 준비(lazy load)와 재생 시작 사이에 지연이
//     있어 1초 간격 카운트다운에 쓰기엔 부정확하다.
//
//  ## 해결 구조
//
//    * AudioContext **하나**만 쓴다 (Safari 제약 회피).
//    * 첫 사용자 제스처에서 `resume()` 으로 잠금을 해제한다.
//    * 모든 wav 를 **미리 fetch + decode** 해 AudioBuffer 로 들고 있는다.
//      디코딩이 끝나 있으면 재생 시작이 `source.start(when)` 한 줄이라
//      지연도 지터도 없다.
//    * 재생 시각을 `AudioContext.currentTime` 기준의 **절대 시각**으로 준다.
//      JS 타이머(setTimeout) 오차가 사운드 타이밍에 영향을 주지 않는다.
//    * 이미 재생 중인 소리는 '세대(gen)' 로 무효화하고, 같은 role 의 이전
//      소리는 반드시 정지시킨다 (중복 재생 원천 차단).
// ============================================================================

(function () {
  'use strict';

  if (window.__tabataAudio) return;

  var ctx = null;          // 단일 AudioContext
  var masterGain = null;   // 마스터 게인
  var buffers = new Map(); // url -> AudioBuffer (디코딩 완료본)
  var loading = new Map(); // url -> Promise (중복 fetch 방지)
  var playing = new Map(); // role -> {src, gain, gen}
  var unlocked = false;
  var failedUrls = [];

  var BASE = null; // 오디오 자산 기본 경로 (Dart 가 설정)

  // iOS 는 Web Audio 도 무음 스위치(벨소리 스위치)의 영향을 받는다.
  // Safari 16.4+ 의 audioSession 을 'playback' 으로 두면 무음 스위치와
  // 무관하게 재생된다. 지원하지 않는 브라우저에서는 아무 일도 하지 않는다.
  function requestPlaybackSession() {
    try {
      if (navigator.audioSession && navigator.audioSession.type !== 'playback') {
        navigator.audioSession.type = 'playback';
      }
    } catch (e) { /* 미지원 브라우저 무시 */ }
  }

  function ensureContext() {
    if (ctx) return ctx;
    var AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    requestPlaybackSession();
    ctx = new AC({ latencyHint: 'interactive' });
    masterGain = ctx.createGain();
    masterGain.gain.value = 1.0;
    masterGain.connect(ctx.destination);

    // iOS 는 전화·화면 잠금·앱 전환 때 컨텍스트를 'interrupted' 로 바꾼다.
    // 상태가 바뀔 때마다 기록해 두면 다음 재생 전에 정확히 판단할 수 있다.
    ctx.onstatechange = function () {
      unlocked = ctx.state === 'running';
    };
    // 화면이 다시 보일 때 잠겨 있으면 resume 을 시도한다.
    // (제스처 밖이라 iOS 에서는 실패할 수 있으나, 실패해도 해가 없다.)
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'visible' && ctx && ctx.state !== 'running') {
        try { ctx.resume(); } catch (e) {}
      }
    });
    return ctx;
  }

  // ---------------------------------------------------------------- 잠금 해제
  // 사용자 제스처 안에서 호출돼야 한다. 여러 번 호출해도 안전하다.
  // **이미 풀려 있어도 매번 호출하라.** iOS 는 중단 후 제스처로만 복구된다.
  function unlock() {
    ensureContext();
    if (!ctx) return Promise.resolve(false);
    requestPlaybackSession();
    var jobs = [];
    if (ctx.state !== 'running' && ctx.resume) {
      jobs.push(ctx.resume().catch(function () {}));
    }
    // iOS Safari: 무음 버퍼를 한 번 재생해야 잠금이 풀리는 사례가 있다.
    try {
      var b = ctx.createBuffer(1, 1, ctx.sampleRate);
      var s = ctx.createBufferSource();
      s.buffer = b;
      s.connect(masterGain);
      s.start(0);
    } catch (e) { /* 무시 */ }
    return Promise.all(jobs).then(function () {
      unlocked = ctx.state === 'running';
      return unlocked;
    }).catch(function () { return false; });
  }

  // ---------------------------------------------------------------- 사전 로딩
  function urlFor(asset) {
    // Flutter 웹은 assets/ 아래에 원본 경로를 그대로 둔다.
    //  asset: 'audio/seq_male_prepare.wav'
    //  실제 URL: assets/assets/audio/seq_male_prepare.wav
    if (BASE === null) BASE = 'assets/assets/';
    return BASE + asset;
  }

  function load(asset) {
    var url = urlFor(asset);
    if (buffers.has(url)) return Promise.resolve(true);
    if (loading.has(url)) return loading.get(url);

    ensureContext();
    if (!ctx) return Promise.resolve(false);

    var p = fetch(url, { cache: 'no-cache' })
      .then(function (res) {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return res.arrayBuffer();
      })
      .then(function (ab) {
        // decodeAudioData 콜백형/프로미스형 모두 대응
        return new Promise(function (resolve, reject) {
          var r = ctx.decodeAudioData(ab, resolve, reject);
          if (r && typeof r.then === 'function') r.then(resolve, reject);
        });
      })
      .then(function (buf) {
        buffers.set(url, buf);
        loading.delete(url);
        return true;
      })
      .catch(function (e) {
        loading.delete(url);
        failedUrls.push(url + ' :: ' + e);
        return false;
      });

    loading.set(url, p);
    return p;
  }

  // 여러 개를 한 번에. 실패해도 나머지는 계속 진행한다.
  function preload(list) {
    if (!list || !list.length) return Promise.resolve({ ok: 0, total: 0 });
    return Promise.all(list.map(load)).then(function (results) {
      var ok = results.filter(Boolean).length;
      return { ok: ok, total: list.length, failed: failedUrls.slice() };
    });
  }

  function isReady(asset) {
    return buffers.has(urlFor(asset));
  }

  /// 디코딩된 버퍼의 길이(ms). 없으면 0.
  /// (검증용 — 숫자 간격이 정확한지 Dart/테스트에서 확인할 수 있게 한다)
  function bufferDurationMs(asset) {
    var b = buffers.get(urlFor(asset));
    return b ? Math.round(b.duration * 1000) : 0;
  }

  // ------------------------------------------------------------------ 재생
  // role 별로 하나만 살아 있게 한다. 같은 role 에 새 재생이 걸리면
  // 이전 소스를 즉시 멈춘다 → 중복 재생이 물리적으로 불가능.
  function stopRole(role) {
    var cur = playing.get(role);
    if (!cur) return;
    try { cur.gen.cancelled = true; } catch (e) {}
    try { cur.src.stop(); } catch (e) {}
    try { cur.src.disconnect(); } catch (e) {}
    playing.delete(role);
  }

  /**
   * @param asset      'audio/x.wav'
   * @param role       'seq' | 'count' | 'sfx' | 'preview'
   * @param volume     0..1
   * @param offsetMs   파일 안에서 시작할 위치
   * @param whenMs     지금으로부터 몇 ms 뒤에 시작할지 (정확 스케줄)
   * @param interrupt  같은 role 의 이전 소리를 끊을지
   */
  function play(asset, role, volume, offsetMs, whenMs, interrupt) {
    ensureContext();
    if (!ctx) return false;

    // 잠겨 있으면 소리는 나지 않는다. 조용히 실패하고 false 를 준다.
    if (ctx.state !== 'running') {
      // 다음 기회에 풀리도록 resume 시도 (제스처 안이면 성공)
      if (ctx.resume) { try { ctx.resume(); } catch (e) {} }
      if (ctx.state !== 'running') return false;
    }

    var url = urlFor(asset);
    var buf = buffers.get(url);
    if (!buf) {
      // 아직 안 받았으면 받아서 다음 호출에 대비한다.
      load(asset);
      return false;
    }

    if (interrupt !== false) stopRole(role);

    var src = ctx.createBufferSource();
    src.buffer = buf;

    var gain = ctx.createGain();
    gain.gain.value = Math.max(0, Math.min(1, volume == null ? 1 : volume));

    src.connect(gain);
    gain.connect(masterGain);

    var gen = { cancelled: false };
    playing.set(role, { src: src, gain: gain, gen: gen });

    var offset = Math.max(0, (offsetMs || 0) / 1000);
    var when = ctx.currentTime + Math.max(0, (whenMs || 0) / 1000);

    // 버퍼 길이를 넘는 오프셋이면 재생하지 않는다.
    if (offset >= buf.duration) {
      playing.delete(role);
      return false;
    }

    src.onended = function () {
      if (playing.get(role) && playing.get(role).gen === gen) {
        playing.delete(role);
      }
      try { gain.disconnect(); } catch (e) {}
    };

    try {
      src.start(when, offset);
    } catch (e) {
      playing.delete(role);
      return false;
    }
    return true;
  }

  function stopAll() {
    Array.from(playing.keys()).forEach(stopRole);
  }

  function setMasterVolume(v) {
    if (!masterGain) return;
    masterGain.gain.value = Math.max(0, Math.min(1, v == null ? 1 : v));
  }

  function status() {
    return {
      supported: !!ctx,
      state: ctx ? ctx.state : 'none',
      unlocked: unlocked,
      loaded: buffers.size,
      loading: loading.size,
      failed: failedUrls.slice(0, 20),
      playing: Array.from(playing.keys()),
      sampleRate: ctx ? ctx.sampleRate : 0,
    };
  }

  window.__tabataAudio = {
    unlock: unlock,
    preload: preload,
    load: load,
    isReady: isReady,
    bufferDurationMs: bufferDurationMs,
    play: play,
    stopRole: stopRole,
    stopAll: stopAll,
    setMasterVolume: setMasterVolume,
    status: status,
    _buffers: buffers,
  };

  // 첫 제스처들에서 자동으로 잠금 해제를 시도한다.
  ['pointerdown', 'touchstart', 'mousedown', 'keydown'].forEach(function (ev) {
    window.addEventListener(ev, function once() {
      unlock();
      // unlock 성공 후에는 리스너를 떼지 않는다 (iOS 재잠금 대비, 비용 없음)
    }, { passive: true });
  });
})();
