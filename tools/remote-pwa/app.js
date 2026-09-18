/* Miku Remote — Web Bluetooth client for the M500's "Miku Remote" GATT service.
 * Mirrors app/src/main/java/com/miku/player/remote/MikuRemoteProtocol.kt — keep both in sync. */
(() => {
  'use strict';

  // ---------------------------------------------------------------- protocol
  const SUFFIX = '-4d49-4b55-9d31-3f8a6e7c2a01';
  const SERVICE = '39c5bb00' + SUFFIX;
  const CH = {
    now: '39c5bb01' + SUFFIX,
    cmd: '39c5bb02' + SUFFIX,
    vol: '39c5bb03' + SUFFIX,
    pair: '39c5bb04' + SUFFIX,
    status: '39c5bb05' + SUFFIX,
  };
  const READ_MARKER = '{"r":1}';
  const LS_TOKEN = 'miku_remote_token';
  const LS_DEVICE = 'miku_remote_device_id';
  const LS_LABEL = 'miku_remote_label';
  const LS_MS = 'miku_remote_mediasession';
  const LS_WAKE = 'miku_remote_wakelock';

  const enc = new TextEncoder();
  const dec = new TextDecoder();

  // ---------------------------------------------------------------- DOM
  const $ = (id) => document.getElementById(id);
  const ui = {
    dot: $('dot'), pill: $('pill'),
    connectView: $('connectView'), playerView: $('playerView'),
    btnConnect: $('btnConnect'), btnReconnect: $('btnReconnect'), connectHint: $('connectHint'),
    art: $('art'), quality: $('quality'), title: $('title'), artist: $('artist'), album: $('album'),
    seek: $('seek'), tPos: $('tPos'), tDur: $('tDur'),
    btnPrev: $('btnPrev'), btnPlay: $('btnPlay'), btnNext: $('btnNext'), icoPlay: $('icoPlay'),
    btnShuffle: $('btnShuffle'), btnLike: $('btnLike'), btnRepeat: $('btnRepeat'), repeatBadge: $('repeatBadge'),
    vol: $('vol'), volVal: $('volVal'), btnVolDown: $('btnVolDown'),
    deviceLine: $('deviceLine'), btnDisconnect: $('btnDisconnect'), btnOptions: $('btnOptions'),
    pairModal: $('pairModal'), codeInput: $('codeInput'), labelInput: $('labelInput'), pairErr: $('pairErr'),
    btnPairCancel: $('btnPairCancel'), btnPairGo: $('btnPairGo'),
    optionsModal: $('optionsModal'), btnOptionsClose: $('btnOptionsClose'), btnForget: $('btnForget'),
    swMediaSession: $('swMediaSession'), swWakeLock: $('swWakeLock'),
    toast: $('toast'),
  };

  const PLAY_PATH = 'M8 5v14l11-7z';
  const PAUSE_PATH = 'M6 5h4v14H6zm8 0h4v14h-4z';

  // ---------------------------------------------------------------- state
  let device = null, server = null, chars = null;
  let authorized = false;
  let userDisconnected = false;
  let reconnectTimer = null, reconnectAttempts = 0;
  let np = null;                 // last now-playing JSON
  let npAt = 0;                  // performance.now() when np arrived
  let seeking = false;
  let volTimer = null;
  let pairWaiter = null;         // {resolve, reject, timer}
  let wakeLock = null;
  let silentAudio = null;

  // Web Bluetooth serialises GATT operations per device; overlapping calls reject with
  // "GATT operation already in progress", so funnel everything through one promise chain.
  let gattChain = Promise.resolve();
  const gatt = (fn) => {
    const p = gattChain.then(fn, fn);
    gattChain = p.catch(() => {});
    return p;
  };

  // ---------------------------------------------------------------- helpers
  const toast = (msg, ms = 2200) => {
    ui.toast.textContent = msg;
    ui.toast.classList.add('show');
    clearTimeout(toast._t);
    toast._t = setTimeout(() => ui.toast.classList.remove('show'), ms);
  };
  const fmt = (ms) => {
    ms = Math.max(0, ms | 0);
    const s = Math.floor(ms / 1000), m = Math.floor(s / 60), h = Math.floor(m / 60);
    const ss = String(s % 60).padStart(2, '0');
    return h ? `${h}:${String(m % 60).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
  };
  const setPill = (text, pink = false) => {
    ui.pill.textContent = text;
    ui.pill.classList.toggle('pink', pink);
  };
  const setDot = (state) => { ui.dot.className = 'dot' + (state ? ' ' + state : ''); };
  const hashParam = (k) => {
    const m = new RegExp('[#&]' + k + '=([^&]*)').exec(location.hash);
    return m ? decodeURIComponent(m[1]) : '';
  };
  const phoneLabel = () => {
    const ua = navigator.userAgent;
    const os = /Android/i.test(ua) ? 'Android' : /Windows/i.test(ua) ? 'Windows' : /Mac/i.test(ua) ? 'Mac' : /CrOS/i.test(ua) ? 'ChromeOS' : /Linux/i.test(ua) ? 'Linux' : 'Device';
    const br = /Edg\//i.test(ua) ? 'Edge' : /OPR\//i.test(ua) ? 'Opera' : /Chrome\//i.test(ua) ? 'Chrome' : 'Browser';
    return `${br} on ${os}`;
  };
  const showView = (player) => {
    ui.connectView.classList.toggle('hidden', player);
    ui.playerView.classList.toggle('hidden', !player);
    ui.btnDisconnect.classList.toggle('hidden', !player);
  };

  // ---------------------------------------------------------------- connect / auth
  async function connect(existing) {
    ui.connectHint.textContent = '';
    try {
      if (!existing) {
        device = await navigator.bluetooth.requestDevice({
          filters: [{ services: [SERVICE] }],
          optionalServices: [SERVICE],
        });
      } else {
        device = existing;
      }
      device.removeEventListener('gattserverdisconnected', onDisconnected);
      device.addEventListener('gattserverdisconnected', onDisconnected);
      userDisconnected = false;
      setPill('connecting…');
      server = await device.gatt.connect();
      const svc = await server.getPrimaryService(SERVICE);
      chars = {
        now: await svc.getCharacteristic(CH.now),
        cmd: await svc.getCharacteristic(CH.cmd),
        vol: await svc.getCharacteristic(CH.vol),
        pair: await svc.getCharacteristic(CH.pair),
        status: await svc.getCharacteristic(CH.status),
      };
      chars.pair.addEventListener('characteristicvaluechanged', onPairNotify);
      chars.now.addEventListener('characteristicvaluechanged', onNowNotify);
      chars.vol.addEventListener('characteristicvaluechanged', onVolNotify);
      await gatt(() => chars.pair.startNotifications());
      await gatt(() => chars.now.startNotifications());
      await gatt(() => chars.vol.startNotifications());
      try { localStorage.setItem(LS_DEVICE, device.id); } catch (_) {}
      reconnectAttempts = 0;
      setDot('adv');
      setPill('connected · not paired');
      ui.deviceLine.textContent = device.name || 'Miku M500';
      await refreshStatus();
      await authenticate();
    } catch (e) {
      if (e && e.name === 'NotFoundError') { setPill('not connected'); return; } // chooser cancelled
      console.error(e);
      ui.connectHint.textContent = friendlyError(e);
      setPill('failed', true);
      setDot('');
    }
  }

  function friendlyError(e) {
    const m = (e && e.message) || String(e);
    if (/GATT Server is disconnected|Connection failed|NetworkError/i.test(m)) return 'Could not reach the M500. Is Phone Remote turned on and in range?';
    if (/User cancelled|NotFoundError/i.test(m)) return '';
    if (/Bluetooth adapter not available|not available/i.test(m)) return 'Bluetooth is off on this phone.';
    return m;
  }

  async function authenticate() {
    let token = null;
    try { token = localStorage.getItem(LS_TOKEN); } catch (_) {}
    if (token) {
      const r = await pairWrite('auth:' + token);
      if (r === 'ok:auth') { onAuthorized(); return; }
      if (r && r.startsWith('err:')) {
        try { localStorage.removeItem(LS_TOKEN); } catch (_) {}
        toast('This M500 no longer recognises this phone — pair again.', 3000);
      }
    }
    openPairSheet();
  }

  function onAuthorized() {
    authorized = true;
    setDot('on');
    setPill('connected');
    showView(true);
    gatt(() => chars.now.readValue()).then((v) => applyNow(dec.decode(v))).catch(() => {});
    gatt(() => chars.vol.readValue()).then((v) => applyVol(dec.decode(v))).catch(() => {});
    if (getBool(LS_MS)) enableMediaSession(true);
    if (getBool(LS_WAKE)) requestWakeLock();
  }

  /** Writes to the pair characteristic and resolves with the server's notify reply. */
  function pairWrite(text) {
    return new Promise((resolve) => {
      if (pairWaiter) { clearTimeout(pairWaiter.timer); pairWaiter.resolve(null); }
      const timer = setTimeout(() => { pairWaiter = null; resolve(null); }, 6000);
      pairWaiter = { resolve, timer };
      gatt(() => writeChar(chars.pair, text, true)).catch((e) => {
        clearTimeout(timer); pairWaiter = null; resolve('err:' + friendlyError(e));
      });
    });
  }

  function onPairNotify(ev) {
    const text = dec.decode(ev.target.value).trim();
    if (pairWaiter) { clearTimeout(pairWaiter.timer); const w = pairWaiter; pairWaiter = null; w.resolve(text); return; }
    if (text === 'err:unauthorized') { authorized = false; openPairSheet(); }
  }

  async function writeChar(ch, text, withResponse) {
    const bytes = enc.encode(text);
    if (withResponse && ch.writeValueWithResponse) return ch.writeValueWithResponse(bytes);
    if (!withResponse && ch.writeValueWithoutResponse && ch.properties.writeWithoutResponse) return ch.writeValueWithoutResponse(bytes);
    return ch.writeValue(bytes);
  }

  // ---------------------------------------------------------------- pairing sheet
  function openPairSheet() {
    showView(false);
    setPill('enter code');
    const pre = hashParam('code');
    ui.codeInput.value = /^\d{6}$/.test(pre) ? pre : '';
    try { ui.labelInput.value = localStorage.getItem(LS_LABEL) || phoneLabel(); } catch (_) { ui.labelInput.value = phoneLabel(); }
    ui.pairErr.textContent = '';
    ui.pairModal.classList.remove('hidden');
    setTimeout(() => (ui.codeInput.value ? ui.btnPairGo : ui.codeInput).focus(), 50);
  }

  async function doPair() {
    const code = ui.codeInput.value.replace(/\D/g, '');
    if (code.length !== 6) { ui.pairErr.textContent = 'The code is 6 digits.'; return; }
    const label = (ui.labelInput.value || phoneLabel()).trim().slice(0, 40).replace(/:/g, ' ');
    try { localStorage.setItem(LS_LABEL, label); } catch (_) {}
    ui.btnPairGo.disabled = true;
    ui.pairErr.textContent = '';
    const r = await pairWrite(`pair:${code}:${label}`);
    ui.btnPairGo.disabled = false;
    if (r && r.startsWith('ok:')) {
      const token = r.slice(3);
      try { localStorage.setItem(LS_TOKEN, token); } catch (_) {}
      ui.pairModal.classList.add('hidden');
      history.replaceState(null, '', location.pathname + location.search); // drop the used code from the URL
      toast('Paired with ' + (device.name || 'Miku M500'));
      onAuthorized();
      return;
    }
    ui.pairErr.textContent = {
      'err:bad-code': 'Wrong code. Check the M500 screen — it changes after each pairing.',
      'err:locked': 'Too many attempts. The M500 paused pairing for a minute and made a new code.',
      'err:no-connection': 'Lost the connection. Reconnect and try again.',
    }[r] || (r ? 'Pairing failed: ' + r : 'No answer from the M500. Is Phone Remote still on?');
  }

  // ---------------------------------------------------------------- now playing
  function onNowNotify(ev) {
    const text = dec.decode(ev.target.value);
    if (text.trim() === READ_MARKER) {
      gatt(() => chars.now.readValue()).then((v) => applyNow(dec.decode(v))).catch(() => {});
      return;
    }
    applyNow(text);
  }

  function applyNow(text) {
    let j;
    try { j = JSON.parse(text); } catch (_) { return; }
    if (j.auth === false) { authorized = false; openPairSheet(); return; }
    np = j; npAt = performance.now();
    ui.title.textContent = j.title || 'Nothing playing';
    ui.artist.textContent = j.artist || '';
    ui.album.textContent = j.album || '';
    ui.quality.textContent = j.quality || '';
    ui.icoPlay.innerHTML = `<path d="${j.playing ? PAUSE_PATH : PLAY_PATH}"/>`;
    ui.art.classList.toggle('spin', !!j.playing);
    ui.btnLike.classList.toggle('on', !!j.liked);
    ui.btnShuffle.classList.toggle('on', !!j.shuffle);
    ui.btnRepeat.classList.toggle('on', j.repeat && j.repeat !== 'off');
    ui.repeatBadge.textContent = j.repeat === 'one' ? '1' : '';
    ui.tDur.textContent = fmt(j.dur);
    if (typeof j.vol === 'number' && !volTimer) applyVol(JSON.stringify({ vol: j.vol }));
    tickSeek();
    updateMediaSession();
  }

  function currentPos() {
    if (!np) return 0;
    const extra = np.playing ? performance.now() - npAt : 0;
    return Math.min(np.dur || Infinity, (np.pos || 0) + extra);
  }

  function tickSeek() {
    if (!np || seeking) return;
    const pos = currentPos();
    const dur = np.dur || 0;
    const frac = dur > 0 ? pos / dur : 0;
    ui.seek.value = Math.round(frac * 1000);
    ui.seek.style.setProperty('--fill', (frac * 100).toFixed(2) + '%');
    ui.tPos.textContent = fmt(pos);
  }
  setInterval(() => { if (np && np.playing) tickSeek(); }, 250);

  function onVolNotify(ev) { applyVol(dec.decode(ev.target.value)); }
  function applyVol(text) {
    let j; try { j = JSON.parse(text); } catch (_) { return; }
    if (typeof j.vol !== 'number') return;
    if (!volTimer) {
      ui.vol.value = j.vol;
      ui.vol.style.setProperty('--fill', j.vol + '%');
    }
    ui.volVal.textContent = j.muted ? 'muted' : j.vol + '%';
  }

  async function refreshStatus() {
    try {
      const v = await gatt(() => chars.status.readValue());
      const j = JSON.parse(dec.decode(v));
      const parts = [j.name || 'Miku M500'];
      if (typeof j.battery === 'number' && j.battery >= 0) parts.push(`🔋 ${j.battery}%${j.charging ? ' ⚡' : ''}`);
      ui.deviceLine.textContent = parts.join(' · ');
    } catch (_) {}
  }
  setInterval(() => { if (server && server.connected && authorized) refreshStatus(); }, 60000);

  // ---------------------------------------------------------------- commands
  function cmd(text) {
    if (!chars || !server || !server.connected) { toast('Not connected'); return; }
    if (!authorized) { openPairSheet(); return; }
    gatt(() => writeChar(chars.cmd, text, false)).catch((e) => {
      const m = (e && e.message) || '';
      if (/not permitted|NotSupportedError/i.test(m)) { authorized = false; openPairSheet(); }
      else toast('Command failed: ' + friendlyError(e));
    });
    if (navigator.vibrate) navigator.vibrate(8);
  }

  ui.btnPlay.addEventListener('click', () => {
    // Optimistic icon flip is avoided on purpose — the M500's notify is the truth.
    cmd('toggle');
  });
  ui.btnNext.addEventListener('click', () => cmd('next'));
  ui.btnPrev.addEventListener('click', () => cmd('prev'));
  ui.btnLike.addEventListener('click', () => cmd('like'));
  ui.btnShuffle.addEventListener('click', () => cmd('shuffle'));
  ui.btnRepeat.addEventListener('click', () => cmd('repeat'));
  ui.btnVolDown.addEventListener('click', () => cmd('voldown'));

  const beginSeek = () => { seeking = true; };
  ui.seek.addEventListener('pointerdown', beginSeek);
  ui.seek.addEventListener('touchstart', beginSeek, { passive: true });
  ui.seek.addEventListener('input', () => {
    seeking = true;
    if (!np) return;
    const ms = (ui.seek.value / 1000) * (np.dur || 0);
    ui.tPos.textContent = fmt(ms);
    ui.seek.style.setProperty('--fill', (ui.seek.value / 10).toFixed(2) + '%');
  });
  ui.seek.addEventListener('change', () => {
    if (np && np.dur > 0) {
      const ms = Math.round((ui.seek.value / 1000) * np.dur);
      cmd('seek:' + ms);
      np.pos = ms; npAt = performance.now();
    }
    seeking = false;
  });

  ui.vol.addEventListener('input', () => {
    ui.vol.style.setProperty('--fill', ui.vol.value + '%');
    ui.volVal.textContent = ui.vol.value + '%';
    clearTimeout(volTimer);
    volTimer = setTimeout(() => { volTimer = null; cmd('vol:' + ui.vol.value); }, 160);
  });

  // ---------------------------------------------------------------- disconnect / reconnect
  function onDisconnected() {
    authorized = false;
    chars = null;
    setDot('');
    if (pairWaiter) { clearTimeout(pairWaiter.timer); pairWaiter.resolve('err:no-connection'); pairWaiter = null; }
    ui.pairModal.classList.add('hidden');
    if (userDisconnected) { setPill('not connected'); showView(false); return; }
    setPill('reconnecting…', true);
    scheduleReconnect();
  }

  function scheduleReconnect() {
    clearTimeout(reconnectTimer);
    if (!device || reconnectAttempts >= 6) {
      setPill('disconnected', true);
      showView(false);
      ui.btnReconnect.classList.toggle('hidden', !device);
      ui.connectHint.textContent = device ? 'Lost the M500. Is Phone Remote still on?' : '';
      return;
    }
    const delay = Math.min(8000, 800 * Math.pow(1.6, reconnectAttempts++));
    reconnectTimer = setTimeout(() => connect(device), delay);
  }

  ui.btnDisconnect.addEventListener('click', () => {
    userDisconnected = true;
    try { device && device.gatt.connected && device.gatt.disconnect(); } catch (_) {}
    authorized = false;
    setDot(''); setPill('not connected'); showView(false);
    ui.btnReconnect.classList.toggle('hidden', !device);
    enableMediaSession(false);
  });

  ui.btnConnect.addEventListener('click', () => connect(null));
  ui.btnReconnect.addEventListener('click', () => { reconnectAttempts = 0; connect(device); });

  // Reconnect without the chooser when Chrome has remembered the device (getDevices is
  // available on recent Chrome; it needs the M500 to be advertising).
  async function tryRememberedDevice() {
    if (!navigator.bluetooth || !navigator.bluetooth.getDevices) return;
    let wanted = null;
    try { wanted = localStorage.getItem(LS_DEVICE); } catch (_) {}
    try {
      const list = await navigator.bluetooth.getDevices();
      const d = list.find((x) => x.id === wanted) || list.find((x) => /miku|m500/i.test(x.name || ''));
      if (!d) return;
      device = d;
      ui.btnReconnect.classList.remove('hidden');
      ui.btnReconnect.textContent = 'Reconnect to ' + (d.name || 'last M500');
      if (d.watchAdvertisements) {
        const ac = new AbortController();
        d.addEventListener('advertisementreceived', () => { ac.abort(); if (!server || !server.connected) connect(d); }, { once: true });
        await d.watchAdvertisements({ signal: ac.signal }).catch(() => {});
        setTimeout(() => ac.abort(), 20000);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------- pair sheet buttons
  ui.btnPairGo.addEventListener('click', doPair);
  ui.codeInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') doPair(); });
  ui.codeInput.addEventListener('input', () => { ui.codeInput.value = ui.codeInput.value.replace(/\D/g, '').slice(0, 6); });
  ui.btnPairCancel.addEventListener('click', () => {
    ui.pairModal.classList.add('hidden');
    userDisconnected = true;
    try { device && device.gatt.connected && device.gatt.disconnect(); } catch (_) {}
    setPill('not connected'); setDot(''); showView(false);
  });

  // ---------------------------------------------------------------- options
  function getBool(k) { try { return localStorage.getItem(k) === '1'; } catch (_) { return false; } }
  function setBool(k, v) { try { localStorage.setItem(k, v ? '1' : '0'); } catch (_) {} }
  function renderSwitches() {
    ui.swMediaSession.classList.toggle('on', getBool(LS_MS));
    ui.swMediaSession.setAttribute('aria-checked', String(getBool(LS_MS)));
    ui.swWakeLock.classList.toggle('on', getBool(LS_WAKE));
    ui.swWakeLock.setAttribute('aria-checked', String(getBool(LS_WAKE)));
  }
  ui.btnOptions.addEventListener('click', () => { renderSwitches(); ui.optionsModal.classList.remove('hidden'); });
  ui.btnOptionsClose.addEventListener('click', () => ui.optionsModal.classList.add('hidden'));
  ui.swMediaSession.addEventListener('click', () => {
    const v = !getBool(LS_MS); setBool(LS_MS, v); renderSwitches();
    enableMediaSession(v && authorized);
  });
  ui.swWakeLock.addEventListener('click', () => {
    const v = !getBool(LS_WAKE); setBool(LS_WAKE, v); renderSwitches();
    if (v) requestWakeLock(); else releaseWakeLock();
  });
  ui.btnForget.addEventListener('click', () => {
    try { localStorage.removeItem(LS_TOKEN); localStorage.removeItem(LS_DEVICE); } catch (_) {}
    if (chars && authorized) gatt(() => writeChar(chars.pair, 'unpair', true)).catch(() => {});
    ui.optionsModal.classList.add('hidden');
    toast('Forgot this M500 on this phone');
    authorized = false;
    if (server && server.connected) openPairSheet();
  });

  // ---------------------------------------------------------------- Media Session (lock-screen controls)
  // The OS only surfaces media controls for a page that is actually playing audio, so an
  // inaudible 1-second loop keeps the session alive. Opt-in.
  function silentWavUrl() {
    const rate = 8000, seconds = 1, n = rate * seconds;
    const buf = new ArrayBuffer(44 + n);
    const v = new DataView(buf);
    const str = (o, s) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); };
    str(0, 'RIFF'); v.setUint32(4, 36 + n, true); str(8, 'WAVE'); str(12, 'fmt ');
    v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
    v.setUint32(24, rate, true); v.setUint32(28, rate, true); v.setUint16(32, 1, true); v.setUint16(34, 8, true);
    str(36, 'data'); v.setUint32(40, n, true);
    for (let i = 0; i < n; i++) v.setUint8(44 + i, 128);
    return URL.createObjectURL(new Blob([buf], { type: 'audio/wav' }));
  }
  function enableMediaSession(on) {
    if (!('mediaSession' in navigator)) return;
    if (on) {
      if (!silentAudio) { silentAudio = new Audio(silentWavUrl()); silentAudio.loop = true; silentAudio.volume = 0.01; }
      silentAudio.play().catch(() => toast('Tap play once so the browser allows lock-screen controls'));
      const h = (a) => () => cmd(a);
      try {
        navigator.mediaSession.setActionHandler('play', h('play'));
        navigator.mediaSession.setActionHandler('pause', h('pause'));
        navigator.mediaSession.setActionHandler('previoustrack', h('prev'));
        navigator.mediaSession.setActionHandler('nexttrack', h('next'));
        navigator.mediaSession.setActionHandler('seekto', (d) => cmd('seek:' + Math.round(d.seekTime * 1000)));
      } catch (_) {}
      updateMediaSession();
    } else if (silentAudio) {
      silentAudio.pause();
      try { navigator.mediaSession.metadata = null; } catch (_) {}
    }
  }
  function updateMediaSession() {
    if (!('mediaSession' in navigator) || !silentAudio || silentAudio.paused || !np) return;
    try {
      navigator.mediaSession.metadata = new MediaMetadata({
        title: np.title || 'Miku M500', artist: np.artist || '', album: np.album || '',
        artwork: [{ src: 'icon.svg', sizes: '512x512', type: 'image/svg+xml' }],
      });
      navigator.mediaSession.playbackState = np.playing ? 'playing' : 'paused';
      if (np.dur > 0 && navigator.mediaSession.setPositionState) {
        navigator.mediaSession.setPositionState({ duration: np.dur / 1000, position: Math.min(np.dur, currentPos()) / 1000, playbackRate: np.playing ? 1 : 0 });
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------- wake lock
  async function requestWakeLock() {
    try { wakeLock = await navigator.wakeLock.request('screen'); } catch (_) {}
  }
  function releaseWakeLock() { try { wakeLock && wakeLock.release(); } catch (_) {} wakeLock = null; }
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && getBool(LS_WAKE) && authorized) requestWakeLock(); });

  // ---------------------------------------------------------------- boot
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
  if (!navigator.bluetooth) {
    ui.btnConnect.disabled = true;
    ui.connectHint.textContent = /iPhone|iPad/i.test(navigator.userAgent)
      ? 'iOS Safari has no Web Bluetooth. On iPhone, use the Bluefy browser; otherwise use an Android phone or a laptop with Chrome/Edge.'
      : 'This browser has no Web Bluetooth. Use Chrome or Edge (over HTTPS).';
    setPill('unsupported', true);
  } else if (!window.isSecureContext) {
    ui.btnConnect.disabled = true;
    ui.connectHint.textContent = 'Web Bluetooth needs HTTPS (or localhost).';
    setPill('needs https', true);
  } else {
    tryRememberedDevice();
    if (hashParam('code')) setPill('code ready · tap Connect');
  }
})();
