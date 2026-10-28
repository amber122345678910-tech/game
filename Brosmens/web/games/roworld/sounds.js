// BroWorld — свои синтезированные звуки поверх общего sfx (без файлов): горн начала войны.
import { sfx } from '../../shared/sfx.js';
import { getSettings } from '../../shared/profile.js';

// «НАЧАЛАСЬ ВОЙНА»: короткий военный горн (две ноты и долгая третья), медная окраска — пила через фильтр
export function horn() {
  const st = getSettings();
  if (!st.sound || !st.volume) return;
  const ctx = sfx.unlock && sfx.unlock();
  if (!ctx) return;
  const t0 = ctx.currentTime + 0.02;
  const out = ctx.createGain();
  out.gain.value = 0.32 * (st.volume / 10);
  const lp = ctx.createBiquadFilter();
  lp.type = 'lowpass'; lp.frequency.value = 1700; lp.Q.value = 1.2;
  lp.connect(out).connect(ctx.destination);
  const notes = [[196, 0, 0.32], [196, 0.38, 0.2], [262, 0.66, 1.25]];
  for (const [f, d, dur] of notes) {
    for (const det of [-6, 5]) {
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.type = 'sawtooth';
      o.frequency.setValueAtTime(f * 0.94, t0 + d);
      o.frequency.exponentialRampToValueAtTime(f, t0 + d + 0.06);
      o.detune.value = det;
      const vib = ctx.createOscillator(), vg = ctx.createGain();
      vib.frequency.value = 5.5; vg.gain.value = d > 0.5 ? 6 : 0;
      vib.connect(vg).connect(o.detune);
      g.gain.setValueAtTime(0.0001, t0 + d);
      g.gain.exponentialRampToValueAtTime(0.5, t0 + d + 0.05);
      g.gain.setValueAtTime(0.5, t0 + d + dur * 0.7);
      g.gain.exponentialRampToValueAtTime(0.0001, t0 + d + dur);
      o.connect(g).connect(lp);
      o.start(t0 + d); o.stop(t0 + d + dur + 0.05);
      vib.start(t0 + d); vib.stop(t0 + d + dur + 0.05);
    }
  }
}

// общий выход с громкостью из настроек; null — звук выключен или ещё не разрешён
function out(gain) {
  const st = getSettings();
  if (!st.sound || !st.volume) return null;
  const ctx = sfx.unlock && sfx.unlock();
  if (!ctx) return null;
  const g = ctx.createGain();
  g.gain.value = gain * (st.volume / 10);
  g.connect(ctx.destination);
  return { ctx, g, t0: ctx.currentTime + 0.01 };
}
let noiseBuf = null;
function noiseSrc(ctx) {
  if (!noiseBuf) {
    noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  }
  const s = ctx.createBufferSource(); s.buffer = noiseBuf; return s;
}

// запуск ракеты: нарастающий рёв двигателя (шум через полосовой фильтр, частота вверх)
export function nukeLaunch(big = false) {
  const o = out(big ? 0.4 : 0.3); if (!o) return;
  const { ctx, g, t0 } = o, dur = big ? 1.6 : 1.1;
  const s = noiseSrc(ctx), f = ctx.createBiquadFilter(), e = ctx.createGain();
  f.type = 'bandpass'; f.Q.value = 1.4;
  f.frequency.setValueAtTime(260, t0); f.frequency.exponentialRampToValueAtTime(2400, t0 + dur);
  e.gain.setValueAtTime(0.0001, t0); e.gain.exponentialRampToValueAtTime(0.9, t0 + 0.12); e.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
  s.connect(f).connect(e).connect(g); s.start(t0, Math.random()); s.stop(t0 + dur + 0.05);
}

// взрыв: глухой удар (синус вниз) и долгий низкочастотный рокот; far — тише и глуше
export function nukeBoom(big = false, far = false) {
  const o = out((big ? 0.75 : 0.55) * (far ? 0.35 : 1)); if (!o) return;
  const { ctx, g, t0 } = o, dur = big ? 3.2 : 2.0;
  const os = ctx.createOscillator(), oe = ctx.createGain();
  os.type = 'sine'; os.frequency.setValueAtTime(95, t0); os.frequency.exponentialRampToValueAtTime(24, t0 + dur * 0.7);
  oe.gain.setValueAtTime(0.0001, t0); oe.gain.exponentialRampToValueAtTime(1, t0 + 0.02); oe.gain.exponentialRampToValueAtTime(0.0001, t0 + dur * 0.75);
  os.connect(oe).connect(g); os.start(t0); os.stop(t0 + dur);
  const s = noiseSrc(ctx), f = ctx.createBiquadFilter(), e = ctx.createGain();
  f.type = 'lowpass'; f.frequency.setValueAtTime(far ? 500 : 1500, t0); f.frequency.exponentialRampToValueAtTime(60, t0 + dur);
  e.gain.setValueAtTime(0.0001, t0); e.gain.exponentialRampToValueAtTime(1, t0 + 0.015); e.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
  s.connect(f).connect(e).connect(g); s.start(t0, Math.random()); s.stop(t0 + dur + 0.05);
}

// тревога «ядерная угроза»: два коротких воя сирены
export function siren() {
  const o = out(0.16); if (!o) return;
  const { ctx, g, t0 } = o;
  for (let k = 0; k < 2; k++) {
    const os = ctx.createOscillator(), e = ctx.createGain(), t = t0 + k * 0.9;
    os.type = 'square';
    os.frequency.setValueAtTime(520, t); os.frequency.linearRampToValueAtTime(880, t + 0.42); os.frequency.linearRampToValueAtTime(520, t + 0.84);
    e.gain.setValueAtTime(0.0001, t); e.gain.exponentialRampToValueAtTime(0.6, t + 0.05); e.gain.setValueAtTime(0.6, t + 0.7); e.gain.exponentialRampToValueAtTime(0.0001, t + 0.86);
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 1800;
    os.connect(lp).connect(e).connect(g); os.start(t); os.stop(t + 0.9);
  }
}

// дипломатия: предложение союза — два мягких «динь» вверх; союз заключён — мажорное трезвучие;
// отказ — две ноты вниз (как alliance-suggested / -accepted / -declined в оригинале, но свои)
export function allyChime(kind) {
  const o = out(0.22); if (!o) return;
  const { ctx, g, t0 } = o;
  const seq = kind === true ? [[523, 0], [659, 0.09], [784, 0.18], [1047, 0.27]] : kind === false ? [[587, 0], [440, 0.14]] : [[784, 0], [1175, 0.13]];
  for (const [f, d] of seq) {
    for (const [mul, vol] of [[1, 0.5], [2, 0.12]]) {
      const os = ctx.createOscillator(), e = ctx.createGain();
      os.type = 'sine'; os.frequency.value = f * mul;
      e.gain.setValueAtTime(0.0001, t0 + d); e.gain.exponentialRampToValueAtTime(vol, t0 + d + 0.012); e.gain.exponentialRampToValueAtTime(0.0001, t0 + d + 0.55);
      os.connect(e).connect(g); os.start(t0 + d); os.stop(t0 + d + 0.6);
    }
  }
}
