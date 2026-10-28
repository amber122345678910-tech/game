// Звуки синтезируются на лету (WebAudio) — никаких файлов, работает офлайн.
// sfx.play('hit'), sfx.play('beam', {vol: .5}). Имена: ui, hit, heavy, swing, slash, dash, jump,
// beam, charge, boom, block, death, coin, spawn, win, lose, bone, tp, build, march.
import { getSettings } from './profile.js';

let ctx = null;
let master = null;
let noiseBuf = null;

function ac() {
  if (!ctx) {
    const C = window.AudioContext || window.webkitAudioContext;
    if (!C) return null;
    ctx = new C();
    master = ctx.createGain();
    master.gain.value = 0.55;
    const comp = ctx.createDynamicsCompressor();
    master.connect(comp).connect(ctx.destination);
    noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  }
  if (ctx.state === 'suspended') ctx.resume();
  return ctx;
}

for (const ev of ['pointerdown', 'touchstart', 'keydown']) {
  window.addEventListener(ev, () => ac(), { once: true, passive: true });
}

function env(g, t, a, peak, dur) {
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(peak, t + a);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
}

function tone(type, f0, f1, dur, vol, delay = 0) {
  const c = ac(); if (!c) return;
  const t = c.currentTime + delay;
  const o = c.createOscillator();
  const g = c.createGain();
  o.type = type;
  o.frequency.setValueAtTime(f0, t);
  o.frequency.exponentialRampToValueAtTime(Math.max(1, f1), t + dur);
  env(g, t, 0.005, vol, dur);
  o.connect(g).connect(master);
  o.start(t); o.stop(t + dur + 0.05);
}

function noise(dur, vol, fType, f0, f1, delay = 0, q = 1) {
  const c = ac(); if (!c) return;
  const t = c.currentTime + delay;
  const s = c.createBufferSource();
  s.buffer = noiseBuf;
  const f = c.createBiquadFilter();
  f.type = fType; f.Q.value = q;
  f.frequency.setValueAtTime(f0, t);
  f.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
  const g = c.createGain();
  env(g, t, 0.004, vol, dur);
  s.connect(f).connect(g).connect(master);
  s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.05);
}

const BANK = {
  ui: (v) => tone('triangle', 880, 1320, 0.08, 0.25 * v),
  hit: (v) => { noise(0.12, 0.6 * v, 'lowpass', 2400, 300); tone('square', 180, 60, 0.1, 0.3 * v); },
  heavy: (v) => { noise(0.35, 0.9 * v, 'lowpass', 1800, 80); tone('sine', 120, 35, 0.4, 0.8 * v); },
  swing: (v) => noise(0.16, 0.35 * v, 'bandpass', 600, 2600, 0, 2),
  slash: (v) => { noise(0.22, 0.5 * v, 'highpass', 6000, 1200); tone('sawtooth', 1400, 300, 0.18, 0.12 * v); },
  dash: (v) => noise(0.25, 0.4 * v, 'bandpass', 300, 1800, 0, 1.5),
  jump: (v) => tone('sine', 300, 620, 0.15, 0.25 * v),
  beam: (v) => { tone('sawtooth', 90, 70, 1.0, 0.35 * v); noise(1.0, 0.5 * v, 'bandpass', 900, 2400, 0, 0.7); tone('square', 600, 1200, 0.9, 0.08 * v); },
  charge: (v) => tone('sawtooth', 120, 900, 0.9, 0.2 * v),
  boom: (v) => { noise(1.1, 1.0 * v, 'lowpass', 1200, 40); tone('sine', 80, 25, 0.9, 0.9 * v); },
  block: (v) => { tone('square', 900, 700, 0.06, 0.25 * v); noise(0.06, 0.3 * v, 'highpass', 4000, 3000); },
  death: (v) => { tone('sawtooth', 400, 60, 0.6, 0.3 * v); noise(0.5, 0.4 * v, 'lowpass', 1000, 100); },
  coin: (v) => { tone('square', 988, 988, 0.07, 0.15 * v); tone('square', 1319, 1319, 0.2, 0.15 * v, 0.07); },
  spawn: (v) => tone('triangle', 400, 1200, 0.3, 0.25 * v),
  win: (v) => [523, 659, 784, 1047].forEach((f, i) => tone('triangle', f, f, 0.25, 0.3 * v, i * 0.12)),
  lose: (v) => [392, 330, 262].forEach((f, i) => tone('triangle', f, f * 0.98, 0.35, 0.3 * v, i * 0.18)),
  bone: (v) => { tone('square', 1200, 400, 0.08, 0.15 * v); noise(0.08, 0.25 * v, 'highpass', 3000, 2000); },
  tp: (v) => { tone('sine', 1800, 200, 0.18, 0.25 * v); tone('sine', 200, 1800, 0.18, 0.15 * v, 0.05); },
  build: (v) => { noise(0.1, 0.4 * v, 'lowpass', 1500, 400); noise(0.1, 0.4 * v, 'lowpass', 1500, 400, 0.15); },
  march: (v) => [0, 0.12, 0.24].forEach((d) => noise(0.06, 0.3 * v, 'lowpass', 800, 200, d)),
};

export const sfx = {
  play(name, { vol = 1 } = {}) {
    const st = getSettings();
    if (!st.sound || !st.volume) return;
    const f = BANK[name];
    if (master) master.gain.value = 0.8 * (st.volume / 10);
    if (f) try { f(vol); } catch {}
  },
  unlock: ac,
};
