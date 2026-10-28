// Процедурная музыка «Судного Дня» (свой WebAudio-контекст, создаётся по первому касанию).
//  • boss  — оригинальный чиптюн-рок, 120 BPM, ре минор: квадрат+пила ведут 4-тактовый хук, треугольный бас восьмыми,
//            шумовые хэты и малый, синусовая бочка. 16 тактов: A A' B B'.
//  • lobby — джазовый «лаунж отеля», 96 BPM со свингом: райд, шагающий бас, мягкие аккорды электропиано, вибрафон.
// Планировщик с упреждением (таймер 25 мс, горизонт 0.1 с). Громкость = настройки «Громкость»/10 и «Звук»;
// приглушение −40% (интро), жёсткая остановка (финальный удар), пауза при сворачивании. ≤12 голосов.
// Свои звуки игры (jdsfx.js) играют через audioOut() — в том же контексте и с той же громкостью.
import { getSettings } from '../../shared/profile.js';

let ctx = null, master = null, musicBus = null, sfxBus = null, noiseBuf = null;
let want = null, cur = null, song = null, timer = 0, duckK = 1;

const midi = (name) => {
  const m = /^([A-G])(#|b)?(-?\d)$/.exec(name);
  const base = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 }[m[1]] + (m[2] === '#' ? 1 : m[2] === 'b' ? -1 : 0);
  return base + (+m[3] + 1) * 12;
};
const hz = (n) => 440 * Math.pow(2, ((typeof n === 'string' ? midi(n) : n) - 69) / 12);

function volume() {
  const s = getSettings();
  return s.sound === false ? 0 : Math.max(0, Math.min(10, s.volume ?? 7)) / 10;
}
function ensure() {
  if (ctx) return ctx;
  const C = window.AudioContext || window.webkitAudioContext;
  if (!C) return null;
  ctx = new C();
  master = ctx.createGain(); master.gain.value = volume();
  const comp = ctx.createDynamicsCompressor(); comp.threshold.value = -14; comp.ratio.value = 3;
  master.connect(comp).connect(ctx.destination);
  musicBus = ctx.createGain(); musicBus.gain.value = 0.42; musicBus.connect(master);
  sfxBus = ctx.createGain(); sfxBus.gain.value = 0.8; sfxBus.connect(master);
  noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
  const d = noiseBuf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  timer = setInterval(tick, 25);
  if (want) startSong(want);
  return ctx;
}
for (const ev of ['pointerdown', 'touchstart', 'keydown']) addEventListener(ev, () => { ensure(); if (ctx?.state === 'suspended' && !document.hidden) ctx.resume(); }, { passive: true });
document.addEventListener('visibilitychange', () => { if (!ctx) return; if (document.hidden) ctx.suspend(); else ctx.resume(); });

// ---------- инструменты ----------
function env(g, t, a, peak, hold, rel) {
  g.gain.setValueAtTime(0.0001, t);
  g.gain.linearRampToValueAtTime(peak, t + a);
  if (hold > 0) g.gain.setValueAtTime(peak, t + a + hold);
  g.gain.exponentialRampToValueAtTime(0.0001, t + a + hold + rel);
}
function osc(type, f, t, dur, out, detune = 0) {
  const o = ctx.createOscillator(); o.type = type; o.frequency.setValueAtTime(f, t); if (detune) o.detune.value = detune;
  o.connect(out); o.start(t); o.stop(t + dur + 0.05);
  return o;
}
function noise(t, dur, out, type, f, q = 1) {
  const s = ctx.createBufferSource(); s.buffer = noiseBuf;
  const fl = ctx.createBiquadFilter(); fl.type = type; fl.frequency.value = f; fl.Q.value = q;
  s.connect(fl).connect(out); s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.02);
  return fl;
}
function gain(out, v = 1) { const g = ctx.createGain(); g.gain.value = v; g.connect(out); return g; }

const I = {
  lead(bus, t, f, dur) { // квадрат + чуть расстроенная пила через фильтр
    const g = gain(bus, 0); env(g, t, 0.006, 0.13, Math.max(0, dur - 0.09), 0.08);
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.setValueAtTime(3600, t); lp.frequency.exponentialRampToValueAtTime(2000, t + dur); lp.Q.value = 2; lp.connect(g);
    osc('square', f, t, dur + 0.1, lp); osc('sawtooth', f, t, dur + 0.1, lp, 9);
  },
  bass(bus, t, f, dur) { // треугольник + тихий квадрат октавой выше (слышно в динамике телефона)
    const g = gain(bus, 0); env(g, t, 0.005, 0.32, dur * 0.5, dur * 0.5);
    osc('triangle', f, t, dur, g);
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 900; lp.connect(g);
    const g2 = gain(lp, 0.22); osc('square', f * 2, t, dur, g2);
  },
  kick(bus, t) {
    const g = gain(bus, 0); env(g, t, 0.002, 0.85, 0.02, 0.22);
    const o = osc('sine', 150, t, 0.3, g); o.frequency.exponentialRampToValueAtTime(42, t + 0.14);
  },
  snare(bus, t, v = 1) {
    const g = gain(bus, 0); env(g, t, 0.002, 0.42 * v, 0.01, 0.15);
    noise(t, 0.2, g, 'bandpass', 1900, 0.7);
    const g2 = gain(bus, 0); env(g2, t, 0.002, 0.18 * v, 0, 0.08); osc('triangle', 190, t, 0.1, g2);
  },
  hat(bus, t, v = 1, open = false) {
    const g = gain(bus, 0); env(g, t, 0.001, 0.13 * v, 0, open ? 0.18 : 0.035);
    noise(t, open ? 0.22 : 0.06, g, 'highpass', 7200, 0.8);
  },
  ride(bus, t, v = 1) {
    const g = gain(bus, 0); env(g, t, 0.002, 0.055 * v, 0, 0.32);
    noise(t, 0.36, g, 'bandpass', 7800, 2.2);
  },
  brush(bus, t) { const g = gain(bus, 0); env(g, t, 0.01, 0.06, 0.02, 0.12); noise(t, 0.18, g, 'bandpass', 2600, 0.5); },
  epiano(bus, t, notes, tine = true) { // мягкий синус + короткий «тайн» сверху
    const g = gain(bus, 0); env(g, t, 0.01, 0.06, 0.05, 0.72);
    for (const n of notes) osc('sine', hz(n), t, 0.85, g);
    if (tine) { const g2 = gain(bus, 0); env(g2, t, 0.002, 0.03, 0, 0.18); osc('sine', hz(notes[notes.length - 1]) * 4, t, 0.22, g2); }
  },
  wbass(bus, t, f, dur) {
    const g = gain(bus, 0); env(g, t, 0.012, 0.3, dur * 0.4, dur * 0.55);
    osc('triangle', f, t, dur, g); const g2 = gain(g, 0.35); osc('sine', f * 2, t, dur, g2);
  },
  vibe(bus, t, f, dur) {
    const g = gain(bus, 0); env(g, t, 0.004, 0.07, 0, Math.min(1.6, dur + 0.6));
    const o = osc('sine', f, t, dur + 0.7, g);
    const lfo = ctx.createOscillator(), lg = ctx.createGain(); lfo.frequency.value = 5.5; lg.gain.value = 0.02; lfo.connect(lg).connect(g.gain); lfo.start(t); lfo.stop(t + dur + 0.7);
    return o;
  },
};

// ---------- «Приговор» (босс) ----------
// мелодия: [нота, длительность в шестнадцатых]; '-' — пауза
const A1 = [['A4', 2], ['D5', 2], ['F5', 2], ['A5', 3], ['G5', 1], ['F5', 2], ['E5', 2], ['F5', 2]];
const A2 = [['D5', 2], ['F5', 2], ['Bb5', 4], ['A5', 2], ['G5', 2], ['F5', 2], ['D5', 2]];
const A3 = [['E5', 2], ['G5', 2], ['C6', 3], ['Bb5', 1], ['A5', 2], ['G5', 2], ['E5', 2], ['C5', 2]];
const A4 = [['C#5', 2], ['E5', 2], ['A5', 4], ['G5', 1], ['F5', 1], ['E5', 2], ['C#5', 4]];
const A7 = [['E5', 2], ['G5', 2], ['C6', 2], ['D6', 2], ['E6', 4], ['D6', 2], ['C6', 2]];
const A8 = [['A5', 3], ['G5', 1], ['F5', 2], ['E5', 2], ['D5', 4], ['C#5', 4]];
const B1 = [['G5', 3], ['Bb5', 3], ['D6', 2], ['C6', 2], ['Bb5', 2], ['A5', 2], ['G5', 2]];
const B2 = [['F5', 3], ['A5', 3], ['D6', 4], ['-', 2], ['A5', 2], ['F5', 2]];
const B3 = [['D5', 2], ['F5', 2], ['Bb5', 2], ['D6', 2], ['C6', 2], ['Bb5', 2], ['A5', 2], ['F5', 2]];
const B4 = [['E5', 4], ['C#5', 4], ['A4', 4], ['-', 4]];
const B8 = [['A4', 2], ['C#5', 2], ['E5', 2], ['G5', 2], ['A5', 4], ['-', 4]];
const BOSS = {
  bpm: 120, steps: 16,
  bars: [
    [A1, 'D'], [A2, 'Bb'], [A3, 'C'], [A4, 'A'], [A1, 'D'], [A2, 'Bb'], [A7, 'C'], [A8, 'A'],
    [B1, 'G'], [B2, 'D'], [B3, 'Bb'], [B4, 'A'], [B1, 'G'], [B2, 'D'], [B3, 'Bb'], [B8, 'A'],
  ],
  root: { D: 'D2', Bb: 'Bb1', C: 'C2', A: 'A1', G: 'G1' },
  minor: { D: true, G: true },
};
// раскладываем мелодию по шагам один раз
for (const bar of BOSS.bars) {
  if (bar.steps) continue;
  const ev = []; let s = 0;
  for (const [n, d] of bar[0]) { if (n !== '-') ev[s] = [hz(n), d]; s += d; }
  bar.steps = ev;
}
function bossStep(bus, t, i, sd) {
  const bars = BOSS.bars, bi = Math.floor(i / 16) % bars.length, s = i % 16, bar = bars[bi], B = bi >= 8;
  const n = bar.steps[s];
  if (n) I.lead(bus, t, n[0], n[1] * sd * 0.92);
  // бас восьмыми: корень, октава, иногда квинта
  if (s % 2 === 0) {
    const r = midi(BOSS.root[bar[1]]), pat = [0, 12, 0, 12, 0, 12, 7, 12];
    I.bass(bus, t, hz(r + pat[s / 2]), sd * 1.7);
  }
  // барабаны
  if (s === 0 || s === 6 || s === 8 || (B && s === 11)) I.kick(bus, t);
  if (s === 4 || s === 12) I.snare(bus, t);
  if (bi === 15 && s >= 13) I.snare(bus, t, 0.6);
  if (B ? true : s % 2 === 0) I.hat(bus, t, s % 4 === 2 ? 1 : 0.6, s === 14 && bi % 4 === 3);
}

// ---------- «Лаунж отеля» (лобби) ----------
const CH = [
  ['F', ['A3', 'C4', 'E4', 'G4'], ['F2', 'A2', 'C3', 'E3']],
  ['Dm', ['F3', 'A3', 'C4', 'E4'], ['D3', 'C3', 'A2', 'F2']],
  ['Gm', ['Bb3', 'D4', 'F4', 'A4'], ['G2', 'Bb2', 'D3', 'F3']],
  ['C7', ['Bb3', 'D4', 'E4', 'A4'], ['C3', 'E3', 'G2', 'Bb2']],
  ['Am', ['C4', 'E4', 'G4', 'B4'], ['A2', 'C3', 'E3', 'G3']],
  ['D7', ['C4', 'E4', 'F#4', 'B4'], ['D3', 'F#3', 'A2', 'C3']],
  ['Gm', ['Bb3', 'D4', 'F4', 'A4'], ['G2', 'A2', 'Bb2', 'B2']],
  ['C7', ['Bb3', 'E4', 'A4', 'D5'], ['C3', 'Bb2', 'G2', 'E2']],
];
// вибрафон: [номер восьмой (0..7), нота, длительность в восьмых]
const VIBE = [
  [[0, 'C5', 3], [3, 'A4', 1], [4, 'G4', 3]],
  [[0, 'F4', 2], [2, 'A4', 2], [4, 'D5', 4]],
  [[0, 'D5', 2], [2, 'C5', 2], [4, 'Bb4', 2], [6, 'A4', 2]],
  [[0, 'G4', 5], [5, 'E4', 3]],
  [[0, 'E5', 3], [3, 'C5', 1], [4, 'A4', 3]],
  [[0, 'F#4', 2], [2, 'A4', 2], [4, 'C5', 2], [6, 'D5', 2]],
  [[0, 'F5', 4], [4, 'D5', 4]],
  [[0, 'E5', 2], [2, 'C5', 2], [4, 'Bb4', 2], [6, 'G4', 2]],
];
const LOBBY = { bpm: 96, steps: 8 };
function lobbyStep(bus, t, i, sd) {
  const bi = Math.floor(i / 8) % CH.length, s = i % 8, ch = CH[bi], beat = sd * 2;
  // аккорды «чарльстоном»: на раз и на «и» второй доли
  if (s === 0) I.epiano(bus, t, ch[1]);
  if (s === 3) I.epiano(bus, t, ch[1].slice(1), false);
  // шагающий бас четвертями
  if (s % 2 === 0) I.wbass(bus, t, hz(ch[2][s / 2]) * 2, beat * 0.9);
  // свинговый райд: динь, динь-да динь, динь-да
  if (s % 2 === 0 || s === 3 || s === 7) I.ride(bus, t, s % 2 ? 0.6 : 1);
  if (s === 2 || s === 6) I.brush(bus, t);
  for (const v of VIBE[bi]) if (v[0] === s) I.vibe(bus, t, hz(v[1]), v[2] * sd * 1.1);
}

// ---------- планировщик ----------
function startSong(name) {
  if (!ctx) return;
  if (song) stopSong(false);
  const bus = ctx.createGain(); bus.gain.value = 0; bus.connect(musicBus);
  bus.gain.setValueAtTime(0, ctx.currentTime); bus.gain.linearRampToValueAtTime(1, ctx.currentTime + 0.6);
  const def = name === 'boss' ? BOSS : LOBBY;
  song = { name, bus, i: 0, t: ctx.currentTime + 0.12, sd: 60 / def.bpm / (def.steps / 4), swing: name === 'lobby' };
  cur = name;
}
function stopSong(hard) {
  if (!song || !ctx) { song = null; cur = null; return; }
  const b = song.bus, now = ctx.currentTime;
  b.gain.cancelScheduledValues(now);
  if (hard) b.gain.setValueAtTime(0, now);
  else { b.gain.setValueAtTime(b.gain.value, now); b.gain.linearRampToValueAtTime(0, now + 0.8); }
  setTimeout(() => b.disconnect(), hard ? 300 : 1200);
  song = null; cur = null;
}
function tick() {
  if (!ctx || !song || ctx.state !== 'running') return;
  const horizon = ctx.currentTime + 0.1;
  // если вкладка спала — не догоняем пропущенное
  if (song.t < ctx.currentTime - 0.2) song.t = ctx.currentTime + 0.05;
  while (song.t < horizon) {
    let t = song.t;
    if (song.swing && song.i % 2 === 1) t += song.sd * 0.33; // свинг: вторая восьмая позже
    if (song.name === 'boss') bossStep(song.bus, t, song.i, song.sd); else lobbyStep(song.bus, t, song.i, song.sd);
    song.i++; song.t += song.sd;
  }
}

// ---------- общий выход для своих звуков (jdsfx.js) ----------
// Тот же AudioContext и тот же регулятор громкости («Звук»/«Громкость»), отдельная шина эффектов.
// null — звук выключен, контекст ещё не создан (нет касания) или свёрнут.
export function audioOut() {
  if (!ctx || ctx.state !== 'running' || !volume()) return null;
  return { ctx, out: sfxBus, noise: noiseBuf };
}

export const music = {
  // 'boss' | 'lobby' | null
  play(name) {
    want = name;
    if (!ctx) return;
    if (name === cur) return;
    if (!name) stopSong(false); else startSong(name);
  },
  stop(hard = false) { want = null; stopSong(hard); },
  duck(on) {
    const k = on ? 0.6 : 1;
    if (k === duckK) return; duckK = k;
    if (ctx) { const now = ctx.currentTime; musicBus.gain.cancelScheduledValues(now); musicBus.gain.setValueAtTime(musicBus.gain.value, now); musicBus.gain.linearRampToValueAtTime(0.42 * k, now + 0.4); }
  },
  applySettings() { if (ctx) master.gain.setTargetAtTime(volume(), ctx.currentTime, 0.05); },
  // финальный удар: тишина в тот же кадр (и без «хвостов» уже запланированных нот)
  silence() { want = null; stopSong(true); },
  get current() { return cur; },
};
