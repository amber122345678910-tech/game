// Собственные синтезированные звуки Jujutsu Brosmens (WebAudio, без файлов): разные M1 по номеру удара, тяжёлый
// 4-й удар, «дзинь» блока, вжух рывка, стекло Limitless, бум Red, всасывание Blue, треск Чёрной вспышки, «шинг»
// Dismantle, глухие удары тела, хор пробуждения, гонг домена и фоновые петли внутри домена.
// Свой AudioContext создаётся при первом жесте; громкость и «Звук» — из общих настроек.
import { getSettings } from '../../shared/profile.js';

let ctx = null, master = null, bus = null, mus = null, verb = null, noiseBuf = null, shaper = null;
const rnd = (a, b) => a + Math.random() * (b - a);

function ac() {
  if (!ctx && navigator.userActivation && !navigator.userActivation.hasBeenActive) return null;
  if (!ctx) {
    const C = window.AudioContext || window.webkitAudioContext;
    if (!C) return null;
    try { ctx = new C(); } catch { return null; }
    master = ctx.createGain(); master.gain.value = 0.6;
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -14; comp.knee.value = 10; comp.ratio.value = 5; comp.attack.value = 0.003; comp.release.value = 0.2;
    master.connect(comp).connect(ctx.destination);
    bus = ctx.createGain(); bus.connect(master);
    mus = ctx.createGain(); mus.gain.value = 0; mus.connect(master);
    // короткий «зал» для гонга, хора и музыки домена
    verb = ctx.createConvolver();
    const len = Math.floor(ctx.sampleRate * 2.2), ir = ctx.createBuffer(2, len, ctx.sampleRate);
    for (let ch = 0; ch < 2; ch++) { const d = ir.getChannelData(ch); for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 2.6); }
    verb.buffer = ir;
    const vg = ctx.createGain(); vg.gain.value = 0.32; verb.connect(vg).connect(master);
    noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    shaper = ctx.createWaveShaper();
    const cv = new Float32Array(512);
    for (let i = 0; i < 512; i++) { const x = (i / 511) * 2 - 1; cv[i] = Math.tanh(x * 3.2); }
    shaper.curve = cv;
    shaper.connect(bus);
  }
  if (ctx.state === 'suspended') ctx.resume();
  return ctx;
}
for (const ev of ['pointerdown', 'touchstart', 'keydown']) addEventListener(ev, () => ac(), { once: true, passive: true });

// ---------- примитивы ----------
function env(g, t, a, peak, dur, sustain = 0) {
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(Math.max(0.0002, peak), t + a);
  if (sustain > 0) g.gain.setValueAtTime(Math.max(0.0002, peak), t + a + sustain);
  g.gain.exponentialRampToValueAtTime(0.0001, t + a + sustain + dur);
}
// осциллятор с глиссандо
function osc(type, f0, f1, dur, vol, { at = 0, a = 0.004, dest = bus, sus = 0, detune = 0 } = {}) {
  const t = ctx.currentTime + at;
  const o = ctx.createOscillator(), g = ctx.createGain();
  o.type = type; o.detune.value = detune;
  o.frequency.setValueAtTime(f0, t);
  if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(Math.max(1, f1), t + a + sus + dur);
  env(g, t, a, vol, dur, sus);
  o.connect(g).connect(dest);
  o.start(t); o.stop(t + a + sus + dur + 0.05);
  return o;
}
// шум через фильтр с разверткой частоты
function nz(dur, vol, type, f0, f1, { at = 0, q = 1, a = 0.003, dest = bus, sus = 0 } = {}) {
  const t = ctx.currentTime + at;
  const s = ctx.createBufferSource(); s.buffer = noiseBuf;
  const f = ctx.createBiquadFilter(); f.type = type; f.Q.value = q;
  f.frequency.setValueAtTime(f0, t);
  if (f1 !== f0) f.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + a + sus + dur);
  const g = ctx.createGain();
  env(g, t, a, vol, dur, sus);
  s.connect(f).connect(g).connect(dest);
  s.start(t, Math.random() * 0.6); s.stop(t + a + sus + dur + 0.05);
  return f;
}

// ---------- банк ----------
function thud(pitch, v, { body = 0.7, click = 0.5, len = 0.13 } = {}) {
  osc('sine', 110 * pitch, 60 * pitch, len, body * v, { a: 0.002 });
  osc('triangle', 220 * pitch, 90 * pitch, len * 0.5, 0.25 * v, { a: 0.002 });
  nz(0.045, click * v, 'lowpass', 3200 * pitch, 700, { q: 0.7 });
}
function heavyHit(v, pitch = 1) {
  thud(0.85 * pitch, v, { body: 0.9, click: 0.7, len: 0.16 });
  osc('sine', 85 * pitch, 30, 0.45, 0.9 * v, { a: 0.003 });                 // «саб» вниз
  nz(0.14, 0.6 * v, 'bandpass', 1400, 500, { q: 1.4, dest: shaper });       // хруст
  nz(0.3, 0.35 * v, 'lowpass', 900, 80, { at: 0.02 });
}
const BANK = {
  // M1 1–3: глухие удары, каждый следующий выше; 4-й — тяжёлый с саб-провалом и хрустом
  m1_1: (v) => thud(1.0 * rnd(0.92, 1.08), v),
  m1_2: (v) => thud(1.14 * rnd(0.92, 1.08), v),
  m1_3: (v) => thud(1.3 * rnd(0.92, 1.08), v),
  m1_4: (v) => heavyHit(v, rnd(0.94, 1.06)),
  hit: (v) => thud(rnd(0.95, 1.35), v * 0.9),
  heavy: (v) => heavyHit(v, rnd(0.9, 1.1)),
  // блок: металлический «дзинь» — два расстроенных квадрата 1.8–2.4 кГц
  block: (v) => {
    const f = rnd(1800, 2400);
    const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 900; hp.connect(bus);
    osc('square', f, f * 0.985, 0.13, 0.13 * v, { a: 0.001, dest: hp });
    osc('square', f * 1.065, f * 1.05, 0.11, 0.1 * v, { a: 0.001, dest: hp, at: 0.004 });
    osc('sine', f * 2.01, f * 2, 0.2, 0.06 * v, { a: 0.001 });
    nz(0.03, 0.25 * v, 'highpass', 5000, 3000);
  },
  // рывок: вжух с разверткой фильтра
  dash: (v) => {
    const f = nz(0.08, 0.5 * v, 'bandpass', 380, 2600, { q: 1.6, a: 0.06, sus: 0.04 });
    f.frequency.exponentialRampToValueAtTime(700, ctx.currentTime + 0.32);
    nz(0.2, 0.18 * v, 'highpass', 3000, 1500, { a: 0.05 });
  },
  swing: (v) => nz(0.11, 0.32 * v, 'bandpass', 700 * rnd(0.9, 1.15), 2600, { q: 2, a: 0.03 }),
  slash: (v) => { nz(0.2, 0.42 * v, 'highpass', 7000, 1400, { a: 0.006 }); osc('sawtooth', 1600, 380, 0.16, 0.07 * v); },
  // Limitless: разбитое стекло — 6 случайных «звонов» 2–5 кГц и яркий шум
  glass: (v) => {
    nz(0.22, 0.6 * v, 'highpass', 6500, 3500, { a: 0.002 });
    nz(0.08, 0.4 * v, 'bandpass', 3000, 6000, { q: 0.8 });
    for (let i = 0; i < 6; i++) { const f = rnd(2000, 5000); osc('sine', f, f * rnd(0.97, 1.0), rnd(0.18, 0.5), rnd(0.07, 0.14) * v, { at: rnd(0, 0.12), a: 0.001 }); }
    osc('triangle', 900, 300, 0.12, 0.12 * v);
  },
  // Red: глубокий бум
  red: (v) => {
    osc('sine', 72, 26, 1.1, 1.0 * v, { a: 0.004 });
    osc('sine', 140, 45, 0.5, 0.45 * v);
    nz(1.0, 0.9 * v, 'lowpass', 1100, 55, { a: 0.003 });
    nz(0.18, 0.55 * v, 'bandpass', 900, 300, { q: 0.9, dest: shaper });
    nz(1.6, 0.18 * v, 'lowpass', 400, 60, { at: 0.05, dest: verb });
  },
  // Blue: всасывание — нарастающий отфильтрованный шум
  blue: (v) => {
    const t = ctx.currentTime;
    const s = ctx.createBufferSource(); s.buffer = noiseBuf; s.loop = true;
    const f = ctx.createBiquadFilter(); f.type = 'bandpass'; f.Q.value = 3;
    f.frequency.setValueAtTime(180, t); f.frequency.exponentialRampToValueAtTime(3200, t + 0.62);
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.7 * v, t + 0.55); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.72);
    s.connect(f).connect(g).connect(bus); s.start(t); s.stop(t + 0.8);
    osc('sine', 70, 320, 0.6, 0.35 * v, { a: 0.1 });
    osc('triangle', 400, 1600, 0.55, 0.06 * v, { a: 0.2 });
  },
  // Чёрная вспышка: электрический треск (быстрые полосовые всплески) + хвост с кольцевой модуляцией
  bflash: (v) => {
    let at = 0;
    for (let i = 0; i < 11; i++) { nz(rnd(0.012, 0.03), rnd(0.35, 0.7) * v, 'bandpass', rnd(1500, 5200), rnd(900, 4000), { at, q: rnd(2, 6), a: 0.001, dest: i % 3 ? bus : shaper }); at += rnd(0.012, 0.035); }
    // кольцевая модуляция: несущая 860 Гц × модулятор 47 Гц
    const t = ctx.currentTime + 0.05;
    const car = ctx.createOscillator(), mod = ctx.createOscillator(), rm = ctx.createGain(), g = ctx.createGain();
    car.type = 'sawtooth'; car.frequency.setValueAtTime(860, t); car.frequency.exponentialRampToValueAtTime(320, t + 0.6);
    mod.type = 'square'; mod.frequency.value = 47;
    rm.gain.value = 0; mod.connect(rm.gain); car.connect(rm);
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 2400;
    env(g, t, 0.005, 0.22 * v, 0.6);
    rm.connect(lp).connect(g).connect(bus);
    car.start(t); mod.start(t); car.stop(t + 0.7); mod.stop(t + 0.7);
    heavyHit(v * 0.8, 0.8);
  },
  // Dismantle: «шинг» — металлические призвуки и шипящий срез
  shing: (v) => {
    nz(0.16, 0.5 * v, 'highpass', 8000, 2500, { a: 0.003 });
    for (const [f, k] of [[3150, 1], [4720, 0.7], [6130, 0.5], [2380, 0.6]]) osc('sine', f * 1.02, f * 0.97, 0.42, 0.075 * k * v, { a: 0.002 });
    osc('sawtooth', 2200, 700, 0.09, 0.06 * v);
  },
  // тело о землю (рэгдолл): два глухих удара «конечностей»
  thump: (v) => {
    const p = rnd(0.85, 1.15);
    osc('sine', 150 * p, 48, 0.14, 0.65 * v, { a: 0.002 });
    nz(0.09, 0.4 * v, 'lowpass', 600, 150);
    osc('sine', 120 * p, 45, 0.1, 0.35 * v, { at: rnd(0.05, 0.09), a: 0.002 });
    nz(0.06, 0.2 * v, 'lowpass', 500, 120, { at: 0.07 });
  },
  // пробуждение: нарастающий «хор» из расстроенных пил
  awaken: (v) => {
    const t = ctx.currentTime;
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.Q.value = 2;
    lp.frequency.setValueAtTime(500, t); lp.frequency.exponentialRampToValueAtTime(3800, t + 1.3);
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.32 * v, t + 1.1); g.gain.setValueAtTime(0.32 * v, t + 1.5); g.gain.exponentialRampToValueAtTime(0.0001, t + 2.6);
    lp.connect(g); g.connect(bus); g.connect(verb);
    for (const f of [220, 261.63, 329.63, 440, 523.25]) for (const dt of [-9, 0, 8]) {
      const o = ctx.createOscillator(); o.type = 'sawtooth'; o.detune.value = dt + rnd(-3, 3);
      o.frequency.setValueAtTime(f * 0.75, t); o.frequency.exponentialRampToValueAtTime(f, t + 1.2);
      o.connect(lp); o.start(t); o.stop(t + 2.7);
    }
    nz(1.2, 0.2 * v, 'highpass', 1500, 6000, { a: 0.9, dest: verb });
    osc('sine', 55, 55, 1.2, 0.5 * v, { a: 0.6 });
  },
  // гонг домена: негармонические призвуки с длинным хвостом
  gong: (v) => {
    const f0 = 98;
    for (const [r, k, d] of [[1, 1, 3.8], [1.483, 0.6, 3.0], [1.932, 0.45, 2.6], [2.546, 0.35, 2.1], [3.37, 0.25, 1.6], [4.13, 0.16, 1.2], [5.4, 0.1, 0.8]]) {
      osc('sine', f0 * r * 1.004, f0 * r, d, 0.32 * k * v, { a: 0.006 });
      osc('sine', f0 * r, f0 * r, d, 0.12 * k * v, { a: 0.006, dest: verb });
    }
    nz(0.08, 0.6 * v, 'lowpass', 2400, 400);
    osc('sine', 50, 38, 1.4, 0.6 * v, { a: 0.01 });
  },
};

// ---------- музыка доменов (процедурные петли) ----------
const music = { kind: null, timer: 0, next: 0, step: 0, nodes: [] };
const midi = (n) => 440 * Math.pow(2, (n - 69) / 12);
// Пустота: воздушный пэд + арпеджио (Am9 → Fmaj7 → Cmaj7 → G6)
const VOID_CH = [[57, 60, 64, 67, 71], [53, 57, 60, 64, 67], [48, 52, 55, 59, 64], [55, 59, 62, 64, 69]];
function voidStep(t, i) {
  const bar = Math.floor(i / 16) % 4, ch = VOID_CH[bar], st = i % 16;
  if (st === 0) {
    // пэд: три расстроенных треугольника на ноту, медленная атака
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 1300;
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.09, t + 1.2); g.gain.setValueAtTime(0.09, t + 3.4); g.gain.exponentialRampToValueAtTime(0.0001, t + 5);
    lp.connect(g); g.connect(mus); g.connect(verb);
    for (const n of ch.slice(0, 4)) for (const dt of [-7, 0, 7]) { const o = ctx.createOscillator(); o.type = 'triangle'; o.frequency.value = midi(n); o.detune.value = dt; o.connect(lp); o.start(t); o.stop(t + 5.1); }
    const b = ctx.createOscillator(), bg = ctx.createGain(); b.type = 'sine'; b.frequency.value = midi(ch[0] - 12);
    bg.gain.setValueAtTime(0.0001, t); bg.gain.exponentialRampToValueAtTime(0.12, t + 0.8); bg.gain.exponentialRampToValueAtTime(0.0001, t + 4.8);
    b.connect(bg).connect(mus); b.start(t); b.stop(t + 5);
  }
  // арпеджио восьмыми (вверх-вниз по аккорду, октавой выше), мягкий «пинг» с эхом
  const seq = [0, 1, 2, 3, 4, 3, 2, 1];
  const n = ch[seq[st % 8]] + 12 + (st >= 8 ? 12 : 0);
  const o = ctx.createOscillator(), g = ctx.createGain(); o.type = 'sine'; o.frequency.value = midi(n);
  g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.07, t + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.9);
  o.connect(g); g.connect(mus); g.connect(verb); o.start(t); o.stop(t + 0.95);
}
// Гробница: тайко-удары поверх низкого гула
const TAIKO = [1, 0, 0, 0.5, 0, 0, 1, 0, 0.8, 0, 0.5, 0.5, 1, 0, 0.6, 0];
function taiko(t, k) {
  const o = ctx.createOscillator(), g = ctx.createGain(); o.type = 'sine';
  o.frequency.setValueAtTime(105, t); o.frequency.exponentialRampToValueAtTime(44, t + 0.35);
  g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.55 * k, t + 0.004); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.5);
  o.connect(g).connect(mus); o.start(t); o.stop(t + 0.55);
  const s = ctx.createBufferSource(); s.buffer = noiseBuf; const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 700; const ng = ctx.createGain();
  ng.gain.setValueAtTime(0.0001, t); ng.gain.exponentialRampToValueAtTime(0.3 * k, t + 0.003); ng.gain.exponentialRampToValueAtTime(0.0001, t + 0.12);
  s.connect(f).connect(ng).connect(mus); s.start(t, Math.random() * 0.5); s.stop(t + 0.15);
}
function shrineStep(t, i) {
  const st = i % 16;
  if (st === 0) {
    // гул: пила 41 Гц + квинта через низкочастотный фильтр с медленным «дыханием»
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 260; lp.Q.value = 4;
    const lfo = ctx.createOscillator(), lg = ctx.createGain(); lfo.frequency.value = 0.35; lg.gain.value = 120; lfo.connect(lg).connect(lp.frequency);
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.15, t + 0.5); g.gain.setValueAtTime(0.15, t + 3.0); g.gain.exponentialRampToValueAtTime(0.0001, t + 3.8);
    lp.connect(g).connect(mus);
    for (const [f, dt] of [[41.2, -6], [41.2, 6], [61.7, 0], [82.4, 3]]) { const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = f; o.detune.value = dt; o.connect(lp); o.start(t); o.stop(t + 3.9); }
    lfo.start(t); lfo.stop(t + 3.9);
  }
  const k = TAIKO[st];
  if (k) taiko(t, k * rnd(0.85, 1.05));
  // редкий «свист» разреза
  if (st === 7 && Math.random() < 0.6) { const s = ctx.createBufferSource(); s.buffer = noiseBuf; const f = ctx.createBiquadFilter(); f.type = 'highpass'; f.frequency.setValueAtTime(7000, t); f.frequency.exponentialRampToValueAtTime(2000, t + 0.15); const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.12, t + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.18); s.connect(f).connect(g).connect(mus); s.start(t, Math.random() * 0.5); s.stop(t + 0.2); }
}
function tickMusic() {
  if (!ctx || !music.kind) return;
  const STEP = music.kind === 'void' ? 0.3 : 0.2;
  while (music.next < ctx.currentTime + 0.25) {
    if (music.next < ctx.currentTime) music.next = ctx.currentTime + 0.02;
    try { (music.kind === 'void' ? voidStep : shrineStep)(music.next, music.step); } catch (e) { if (audio.debug) console.error(e); }
    music.step++; music.next += STEP;
  }
}

export const audio = {
  // true — звук обработан здесь (или звук выключен); false — пусть играет общий sfx
  play(name, vol = 1) {
    const f = BANK[name];
    if (!f) return false;
    const st = getSettings();
    if (!st.sound || !st.volume) return true;
    if (!ac()) return true;
    master.gain.value = 0.85 * (st.volume / 10);
    try { f(Math.min(1.5, vol)); } catch (e) { if (audio.debug) throw e; }
    return true;
  },
  has: (name) => !!BANK[name],
  // Фоновая петля домена: 'void' | 'shrine' | null
  music(kind) {
    if (kind === music.kind) return;
    const st = getSettings();
    if (kind && (!st.sound || !st.volume)) kind = null;
    if (!ac()) { music.kind = null; return; }
    const t = ctx.currentTime;
    mus.gain.cancelScheduledValues(t);
    mus.gain.setValueAtTime(Math.max(0.0001, mus.gain.value), t);
    if (!kind) {
      mus.gain.exponentialRampToValueAtTime(0.0001, t + 0.7);
      music.kind = null;
      clearInterval(music.timer); music.timer = 0;
      return;
    }
    master.gain.value = 0.85 * (st.volume / 10);
    mus.gain.exponentialRampToValueAtTime(0.75, t + 0.8);
    music.kind = kind; music.step = 0; music.next = t + 0.05;
    if (!music.timer) music.timer = setInterval(tickMusic, 60);
    tickMusic();
  },
  unlock: ac,
  debug: false,
  get state() { return ctx ? ctx.state : 'none'; },
};
