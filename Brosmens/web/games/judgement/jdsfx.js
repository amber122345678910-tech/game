// Свои звуки «Судного Дня» по таблице подсказок из спеки (§7.6), синтез WebAudio — без файлов.
// Играют в том же AudioContext, что и музыка (music.audioOut): общий регулятор «Громкость» и выключатель «Звук».
// Затухание по расстоянию и ограничение частоты — в G.jd (main.js), здесь только сами звуки.
//   whine  — «зарядка» бластера: нарастающий вой 0 → 0.8 с (o.dur)
//   roar   — выстрел бластера: широкий шумный рёв, гаснет вместе с лучом (o.dur, 2.4 с)
//   ting   — телеграф Зоны костей: короткий высокий «дзинь»;  shhk — кости выросли: сухой треск-«шшк»
//   whoosh — бросок кости (по одному на кость, o.det — расстройка);  wall — стена Синей атаки проезжает
//   hum(on) — низкий гул на всё время Синей атаки;  thoom — Отталкивание: глухой «бум» + ветер
//   miss   — «MISS»: свист мимо + шорох ткани;  hurt — короткий хрусткий «ай» (≤1 раз в 0.15 с на человека)
//   kr(level) — тихий треск, пока у тебя (или того, за кем смотришь) есть карма
//   bite / glug — пирог / зелье (бульк + звон);  chime — вторая жизнь (стеклянный звон)
//   slice  — финальный разрез (металлический «вжик»);  blip — буква в диалоге (низкий «бип»)
//   pop / crack / shatter — душа вылетает / трескается / рассыпается;  dust — Судья рассыпается в пыль
//   ring   — Круг бластеров;  reload — перезарядка;  tick — счётчик в лобби
import { audioOut } from './music.js';

let A = null;           // { ctx, out, noise } текущего вызова
let crackBuf = null, krV = null, humV = null;

function env(g, t, a, peak, hold, rel) {
  g.gain.setValueAtTime(0.0001, t);
  g.gain.linearRampToValueAtTime(peak, t + a);
  if (hold > 0) g.gain.setValueAtTime(peak, t + a + hold);
  g.gain.exponentialRampToValueAtTime(0.0001, t + a + hold + rel);
}
function gain(out, v = 0) { const g = A.ctx.createGain(); g.gain.value = v; g.connect(out); return g; }
function osc(type, f, t, dur, out, detune = 0) {
  const o = A.ctx.createOscillator(); o.type = type; o.frequency.setValueAtTime(f, t); if (detune) o.detune.value = detune;
  o.connect(out); o.start(t); o.stop(t + dur + 0.05);
  return o;
}
function filt(type, f, q, out) { const fl = A.ctx.createBiquadFilter(); fl.type = type; fl.frequency.value = f; fl.Q.value = q; fl.connect(out); return fl; }
function noise(t, dur, out, type, f, q = 1) {
  const s = A.ctx.createBufferSource(); s.buffer = A.noise;
  const fl = A.ctx.createBiquadFilter(); fl.type = type; fl.frequency.setValueAtTime(f, t); fl.Q.value = q;
  s.connect(fl).connect(out); s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.02);
  return fl;
}

const CUES = {
  // ---------- бластер ----------
  whine(v, o) {
    const t = A.ctx.currentTime, d = o.dur ?? 0.8;
    const g = gain(A.out); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.2 * v, t + d * 0.9); g.gain.exponentialRampToValueAtTime(0.0001, t + d + 0.06);
    const bp = filt('bandpass', 700, 2.5, g); bp.frequency.setValueAtTime(600, t); bp.frequency.exponentialRampToValueAtTime(2600, t + d);
    for (const [ty, det] of [['sawtooth', 0], ['square', 14]]) { const x = osc(ty, 170, t, d + 0.08, bp, det); x.frequency.exponentialRampToValueAtTime(1150, t + d); }
    const g2 = gain(A.out); g2.gain.setValueAtTime(0.0001, t); g2.gain.exponentialRampToValueAtTime(0.05 * v, t + d); g2.gain.exponentialRampToValueAtTime(0.0001, t + d + 0.05);
    const w = osc('sine', 900, t, d + 0.06, g2); w.frequency.exponentialRampToValueAtTime(3400, t + d);
  },
  roar(v, o) {
    const t = A.ctx.currentTime, d = o.dur ?? 2.4;
    const g = gain(A.out); g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(0.62 * v, t + 0.03);
    g.gain.setTargetAtTime(0.0001, t + 0.18, d / 4.2);
    // шумовая «стена» + низкий пилообразный гул с биениями + шипение сверху
    const lp = noise(t, d + 0.2, g, 'lowpass', 2600, 0.5); lp.frequency.setValueAtTime(3200, t); lp.frequency.exponentialRampToValueAtTime(900, t + d);
    noise(t, d + 0.2, gain(g, 0.6), 'bandpass', 700, 0.6);
    const lo = filt('lowpass', 420, 1, gain(g, 0.55));
    osc('sawtooth', 68, t, d + 0.2, lo); osc('sawtooth', 69.6, t, d + 0.2, lo); osc('square', 136, t, d + 0.2, gain(lo, 0.4));
    const h = gain(A.out); env(h, t, 0.01, 0.1 * v, 0.05, Math.min(1.2, d * 0.5)); noise(t, 1.3, h, 'highpass', 5200, 0.7);
  },
  ring(v) { const t = A.ctx.currentTime; const g = gain(A.out); env(g, t, 0.05, 0.12 * v, 0.3, 0.6); const x = osc('sawtooth', 110, t, 1.0, filt('lowpass', 1800, 1, g)); x.frequency.exponentialRampToValueAtTime(660, t + 0.9); },

  // ---------- кости ----------
  ting(v) {
    const t = A.ctx.currentTime;
    [[2637, 0.15, 0.32], [3951, 0.07, 0.22], [1318, 0.06, 0.3]].forEach(([f, p, r]) => { const g = gain(A.out); env(g, t, 0.002, p * v, 0, r); osc(f > 2000 ? 'sine' : 'triangle', f, t, r + 0.05, g); });
  },
  shhk(v) {
    const t = A.ctx.currentTime;
    for (let i = 0; i < 6; i++) { const d = i * 0.021 + Math.random() * 0.006; const g = gain(A.out); env(g, t + d, 0.001, (0.32 - i * 0.035) * v, 0.004, 0.022); noise(t + d, 0.04, g, 'highpass', 2600 + Math.random() * 1400, 1.2); }
    const g = gain(A.out); env(g, t, 0.002, 0.3 * v, 0, 0.08); const x = osc('square', 220, t, 0.1, filt('lowpass', 900, 1, g)); x.frequency.exponentialRampToValueAtTime(90, t + 0.08);
  },
  whoosh(v, o) {
    const t = A.ctx.currentTime + (o.delay || 0), k = 1 + (o.det || 0), d = 0.17 + Math.random() * 0.04;
    const g = gain(A.out); g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(0.24 * v, t + d * 0.35); g.gain.exponentialRampToValueAtTime(0.0001, t + d);
    const f = noise(t, d + 0.02, g, 'bandpass', 420 * k, 2.2); f.frequency.exponentialRampToValueAtTime(2700 * k, t + d * 0.8);
  },
  wall(v) {
    const t = A.ctx.currentTime, d = 0.42;
    const g = gain(A.out); g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(0.26 * v, t + 0.12); g.gain.exponentialRampToValueAtTime(0.0001, t + d);
    const f = noise(t, d + 0.02, g, 'bandpass', 260, 1.4); f.frequency.exponentialRampToValueAtTime(1300, t + d * 0.7);
  },
  thoom(v) {
    const t = A.ctx.currentTime;
    const g = gain(A.out); env(g, t, 0.004, 1.0 * v, 0.05, 0.55);
    const o = osc('sine', 85, t, 0.7, g); o.frequency.exponentialRampToValueAtTime(32, t + 0.5);
    const g2 = gain(A.out); env(g2, t, 0.004, 0.5 * v, 0.05, 0.35); noise(t, 0.5, g2, 'lowpass', 380);
    const g3 = gain(A.out); g3.gain.setValueAtTime(0.0001, t); g3.gain.linearRampToValueAtTime(0.32 * v, t + 0.25); g3.gain.exponentialRampToValueAtTime(0.0001, t + 1.0);
    const fl = noise(t, 1.05, g3, 'bandpass', 500, 0.9); fl.frequency.setValueAtTime(400, t); fl.frequency.exponentialRampToValueAtTime(1600, t + 0.35); fl.frequency.exponentialRampToValueAtTime(600, t + 1.0);
  },

  // ---------- попадания ----------
  miss(v) {
    const t = A.ctx.currentTime;
    const g = gain(A.out); g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(0.3 * v, t + 0.03); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.15);
    const f = noise(t, 0.16, g, 'bandpass', 900, 4); f.frequency.exponentialRampToValueAtTime(3600, t + 0.12);
    const g2 = gain(A.out); g2.gain.setValueAtTime(0.0001, t + 0.03); g2.gain.linearRampToValueAtTime(0.2 * v, t + 0.08); g2.gain.exponentialRampToValueAtTime(0.0001, t + 0.27);
    const f2 = noise(t + 0.03, 0.26, g2, 'lowpass', 1100, 0.7); f2.frequency.exponentialRampToValueAtTime(380, t + 0.26);
  },
  hurt(v) {
    const t = A.ctx.currentTime;
    const g = gain(A.out); env(g, t, 0.001, 0.2 * v, 0.02, 0.05);
    const x = osc('square', 330, t, 0.09, filt('lowpass', 2400, 1, g)); x.frequency.exponentialRampToValueAtTime(130, t + 0.07);
    const g2 = gain(A.out); env(g2, t, 0.001, 0.26 * v, 0.01, 0.04); noise(t, 0.06, g2, 'bandpass', 2100, 1.1);
  },

  // ---------- предметы ----------
  bite(v) {
    const t = A.ctx.currentTime;
    for (const d of [0, 0.12]) { const g = gain(A.out); env(g, t + d, 0.002, 0.35 * v, 0.01, 0.07); noise(t + d, 0.1, g, 'bandpass', 1500, 1.2); }
    const g = gain(A.out); env(g, t + 0.25, 0.005, 0.12 * v, 0.05, 0.3); osc('triangle', 1046, t + 0.25, 0.4, g);
  },
  glug(v) {
    const t = A.ctx.currentTime;
    for (let i = 0; i < 3; i++) { const g = gain(A.out), d = i * 0.11; env(g, t + d, 0.004, 0.25 * v, 0.02, 0.07); const o = osc('sine', 300 + i * 60, t + d, 0.12, g); o.frequency.exponentialRampToValueAtTime(700 + i * 90, t + d + 0.09); }
    [1318, 1976].forEach((f, i) => { const g = gain(A.out); env(g, t + 0.36 + i * 0.06, 0.004, 0.1 * v, 0.04, 0.5); osc('triangle', f, t + 0.36 + i * 0.06, 0.6, g); });
  },
  chime(v) {
    const t = A.ctx.currentTime;
    [1568, 2093, 2637, 3136].forEach((f, i) => { const g = gain(A.out); env(g, t + i * 0.05, 0.003, 0.16 * v, 0, 1.3); osc('sine', f, t + i * 0.05, 1.4, g); });
    const g = gain(A.out); env(g, t, 0.003, 0.08 * v, 0, 0.6); osc('triangle', 4186, t, 0.7, g);
  },
  reload(v) { const t = A.ctx.currentTime; [0, 0.09, 0.32].forEach((d, i) => { const g = gain(A.out); env(g, t + d, 0.001, (i === 2 ? 0.4 : 0.22) * v, 0, 0.04); noise(t + d, 0.05, g, 'highpass', i === 2 ? 2500 : 4200, 1); }); },

  // ---------- смерть ----------
  slice(v) {
    const t = A.ctx.currentTime;
    const g = gain(A.out); g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(0.55 * v, t + 0.015); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.24);
    const f = noise(t, 0.26, g, 'highpass', 7200, 0.8); f.frequency.exponentialRampToValueAtTime(2200, t + 0.2);
    // неровные обертоны — металлический звон лезвия
    [1870, 2655, 3530, 4420, 5990].forEach((fr, i) => { const gg = gain(A.out); env(gg, t + 0.01, 0.002, (0.1 - i * 0.012) * v, 0, 0.9 - i * 0.1); osc('sine', fr, t + 0.01, 1.0, gg); });
    const g3 = gain(A.out); env(g3, t, 0.002, 0.12 * v, 0, 0.16); const s = osc('sawtooth', 1600, t, 0.2, filt('highpass', 600, 1, g3)); s.frequency.exponentialRampToValueAtTime(380, t + 0.16);
  },
  pop(v) { const t = A.ctx.currentTime; const g = gain(A.out); env(g, t, 0.003, 0.18 * v, 0, 0.1); const o = osc('square', 440, t, 0.12, filt('lowpass', 2200, 1, g)); o.frequency.exponentialRampToValueAtTime(990, t + 0.08); },
  crack(v) {
    const t = A.ctx.currentTime;
    for (const [d, f0] of [[0, 1200], [0.07, 800]]) {
      const g = gain(A.out); env(g, t + d, 0.001, 0.32 * v, 0.01, 0.05); const o = osc('square', f0, t + d, 0.08, g); o.frequency.exponentialRampToValueAtTime(f0 * 0.3, t + d + 0.06);
      const g2 = gain(A.out); env(g2, t + d, 0.001, 0.3 * v, 0, 0.04); noise(t + d, 0.05, g2, 'highpass', 3200, 1);
    }
  },
  shatter(v) { const t = A.ctx.currentTime; for (let i = 0; i < 5; i++) { const d = i * 0.035 + Math.random() * 0.02, g = gain(A.out); env(g, t + d, 0.001, 0.09 * v, 0, 0.12); osc('triangle', 1800 + Math.random() * 1800, t + d, 0.15, g); } },
  dust(v) {
    const t = A.ctx.currentTime;
    const g = gain(A.out); g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(0.22 * v, t + 0.15); g.gain.exponentialRampToValueAtTime(0.0001, t + 1.0);
    const f = noise(t, 1.05, g, 'lowpass', 1400, 0.6); f.frequency.exponentialRampToValueAtTime(260, t + 1.0);
  },

  // ---------- интерфейс ----------
  blip(v, o) { // буква в диалоге Судьи: низкий короткий «бип» (лёгкий разброс высоты, как «голос»)
    const t = A.ctx.currentTime, f = (o.pitch ?? 165) * (1 + (Math.random() - 0.5) * 0.05);
    const g = gain(A.out); env(g, t, 0.002, 0.11 * v, 0.022, 0.025);
    osc('square', f, t, 0.06, filt('lowpass', 1500, 0.8, g));
  },
  tick(v) { const t = A.ctx.currentTime; const g = gain(A.out); env(g, t, 0.001, 0.08 * v, 0, 0.05); osc('square', 1320, t, 0.06, filt('lowpass', 3000, 1, g)); },
};

// треск кармы: редкие щелчки с короткими «хвостами» (2 с, по кругу)
function crackleBuffer() {
  const ctx = A.ctx, len = ctx.sampleRate * 2, b = ctx.createBuffer(1, len, ctx.sampleRate), d = b.getChannelData(0);
  for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * 0.015;
  for (let i = 0; i < len; i++) {
    if (Math.random() > 0.0011) continue;
    const a = (0.35 + Math.random() * 0.65) * (Math.random() < 0.5 ? -1 : 1), tail = 20 + Math.floor(Math.random() * 60);
    for (let k = 0; k < tail && i + k < len; k++) d[i + k] += a * Math.exp(-k / (tail * 0.25)) * (k % 2 ? -0.6 : 1);
  }
  return b;
}

export const jdsfx = {
  play(name, vol = 1, o = {}) {
    const f = CUES[name];
    if (!f || vol <= 0.001) return;
    A = audioOut(); if (!A) return;
    try { f(vol, o); } catch {}
  },
  // громкость треска кармы 0..1 (0 — выключить); зовётся каждый кадр, меняет звук только при заметной разнице
  kr(level) {
    const out = level > 0.01 ? audioOut() : null;
    if (!out) {
      if (krV) { const v = krV, now = v.g.context.currentTime; krV = null; v.g.gain.setTargetAtTime(0, now, 0.08); try { v.src.stop(now + 0.4); } catch {} }
      return;
    }
    A = out;
    const now = A.ctx.currentTime;
    {
      if (!krV) {
        crackBuf ||= crackleBuffer();
        const g = gain(A.out, 0), hp = filt('highpass', 1400, 0.7, g), pk = filt('peaking', 3800, 1.5, hp); pk.gain.value = 6;
        const src = A.ctx.createBufferSource(); src.buffer = crackBuf; src.loop = true; src.connect(pk); src.start(now, Math.random() * 2);
        krV = { g, src, lv: -1 };
      }
      if (Math.abs(krV.lv - level) > 0.04) { krV.lv = level; krV.g.gain.setTargetAtTime(0.16 * level, now, 0.08); }
    }
  },
  // низкий гул на всё время Синей атаки
  hum(on) {
    if (!on) {
      if (!humV) return;
      const h = humV, now = h.g.context.currentTime; humV = null;
      h.g.gain.cancelScheduledValues(now); h.g.gain.setValueAtTime(h.g.gain.value, now); h.g.gain.linearRampToValueAtTime(0, now + 0.6);
      h.a.stop(now + 0.7); h.b.stop(now + 0.7); h.lfo.stop(now + 0.7);
      return;
    }
    const out = audioOut();
    if (!out) return;
    A = out;
    const now = A.ctx.currentTime;
    if (!humV) {
      const g = gain(A.out, 0); g.gain.setValueAtTime(0, now); g.gain.linearRampToValueAtTime(0.1, now + 0.8);
      const lp = filt('lowpass', 320, 1, g);
      const a = A.ctx.createOscillator(); a.type = 'sawtooth'; a.frequency.value = 55; a.connect(lp); a.start(now);
      const b = A.ctx.createOscillator(); b.type = 'sine'; b.frequency.value = 110.6; b.connect(g); b.start(now);
      const lfo = A.ctx.createOscillator(), lg = A.ctx.createGain(); lfo.frequency.value = 0.7; lg.gain.value = 60; lfo.connect(lg).connect(lp.frequency); lfo.start(now);
      humV = { g, a, b, lfo };
    }
  },
  stopLoops() { this.kr(0); this.hum(false); },
};
