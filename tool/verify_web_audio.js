// Chrome DevTools Protocol 로 웹 오디오 브리지를 실제 브라우저에서 검증한다.
//  * AudioContext 잠금 해제 여부
//  * 62개 wav fetch + decode 성공 개수
//  * 카운트다운 묶음 특정 오프셋 재생
//  * role 중복 재생 방지
const http = require('http');
const { spawn } = require('child_process');

const BASE = 'http://localhost:8099';
const PORT = 9222;

function get(path) {
  return new Promise((res, rej) => {
    http.get({ host: '127.0.0.1', port: PORT, path }, (r) => {
      let d = '';
      r.on('data', (c) => (d += c));
      r.on('end', () => res(d));
    }).on('error', rej);
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const chrome = spawn('/usr/bin/google-chrome', [
    '--headless=new',
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--disable-dev-shm-usage',
    '--autoplay-policy=no-user-gesture-required',
    '--mute-audio',
    `--remote-debugging-port=${PORT}`,
    '--user-data-dir=/tmp/chrome-audio-verify',
    'about:blank',
  ], { stdio: 'ignore' });

  let target = null;
  for (let i = 0; i < 40; i++) {
    await sleep(250);
    try {
      const list = JSON.parse(await get('/json/list'));
      target = list.find((t) => t.type === 'page');
      if (target) break;
    } catch (_) {}
  }
  if (!target) {
    console.log('FAILED: chrome not reachable');
    chrome.kill();
    process.exit(1);
  }

  const WebSocket = require('ws');
  const ws = new WebSocket(target.webSocketDebuggerUrl, { perMessageDeflate: false });
  let id = 0;
  const pending = new Map();

  const send = (method, params = {}) =>
    new Promise((res) => {
      const mid = ++id;
      pending.set(mid, res);
      ws.send(JSON.stringify({ id: mid, method, params }));
    });

  ws.on('message', (raw) => {
    const msg = JSON.parse(raw);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg.result || msg);
      pending.delete(msg.id);
    })
  });

  await new Promise((r) => ws.on('open', r));
  await send('Page.enable');
  await send('Runtime.enable');

  // 오디오 브리지만 단독으로 검증 (Flutter 앱 로딩과 무관)
  const html = `<!DOCTYPE html><html><head>
    <script src="${BASE}/audio_bridge.js"></script>
  </head><body>probe</body></html>`;
  // 파일로 저장해 로컬에서 열면 fetch 가 file:// 이 되므로, HTTP 경유 페이지 사용
  await send('Page.navigate', { url: BASE + '/index.html' });
  await sleep(3500);

  const expr = `(async () => {
    const A = window.__tabataAudio;
    if (!A) return { fatal: 'bridge missing' };
    const out = { steps: [] };
    out.unlocked = await A.unlock();
    const st0 = A.status();
    out.state = st0.state; out.sampleRate = st0.sampleRate;
    out.steps.push('unlock=' + out.unlocked + ' state=' + st0.state);

    const list = ['beep.wav','sfx_work.wav','sfx_rest.wav','sfx_finish.wav','sfx_count.wav'];
    for (const s of ['male','female','baby']) {
      list.push('cnt_' + s + '.wav');
      for (let n=1;n<=5;n++) list.push('c_'+s+'_'+n+'.wav');
      for (const k of ['prepare','startWork','startRest','setRest','lastRound','finish','workLast'])
        list.push('seq_'+s+'_'+k+'.wav');
      for (const k of ['prepare','startWork','startRest','setRest','lastRound','finish'])
        list.push('st_'+s+'_'+k+'.wav');
    }
    const pre = await A.preload(list.map(f => 'audio/'+f));
    out.preload = pre;
    out.steps.push('preload=' + pre.ok + '/' + pre.total);
    out.failed = (A.status().failed || []).slice(0,5);

    out.playOffset1000 = A.play('audio/cnt_male.wav','count',1.0,1000,0,true);
    out.playing = A.status().playing;
    out.steps.push('play@1000ms=' + out.playOffset1000);

    // 같은 role 두 번 → 하나만 살아있어야 한다
    A.play('audio/cnt_male.wav','count',1.0,0,0,true);
    out.playingAfterSecond = A.status().playing;

    A.stopAll();
    out.playingAfterStop = A.status().playing;
    return out;
  })()`;

  const r = await send('Runtime.evaluate', {
    expression: expr,
    awaitPromise: true,
    returnByValue: true,
    userGesture: true,
  });

  console.log(JSON.stringify(r.result && r.result.value ? r.result.value : r, null, 2));

  ws.close();
  chrome.kill();
})().catch((e) => {
  console.error('FAILED', e);
  process.exit(1);
});
