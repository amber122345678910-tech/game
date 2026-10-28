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
