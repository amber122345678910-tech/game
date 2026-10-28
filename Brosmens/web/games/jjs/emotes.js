// Эмоции для колеса 🕺 (как в JJS: 4 слота на страницу). Любой прыжок, M1, блок, удар или движение отменяют эмоцию.
// pose(f, t, out) пишет позу в out; dur — длительность (99 = пока не отменят).
import { K, POSE } from './anim.js';

const N = POSE.idle.gojo; // спокойная стойка
const set = (out, base, o) => { out.set(base); for (const k in o) out[K[k]] = o[k]; return out; };

export const EMOTES = [
  {
    id: 'wave', name: 'Привет', icon: '👋', dur: 2.6,
    pose: (f, t, out) => set(out, N, { rax: -2.85, raz: -0.25 + Math.sin(t * 9) * 0.45, hyaw: 0.15, hx: -0.1, twist: 0.1 }),
  },
  {
    id: 'dance', name: 'Танец', icon: '🕺', dur: 99,
    pose: (f, t, out) => {
      const s = Math.sin(t * 6.5), c = Math.cos(t * 6.5);
      return set(out, N, { hy: -0.15 + Math.abs(s) * 0.25, twist: Math.sin(t * 3.25) * 0.5, roll: s * 0.06, lax: -2.4 - s * 0.5, laz: 0.4, rax: -0.6 + s * 0.5, raz: -0.6, llx: Math.max(0, s) * -0.7, rlx: Math.max(0, -s) * -0.7, hx: c * 0.12 });
    },
  },
  {
    id: 'flex', name: 'Флекс', icon: '💪', dur: 99,
    pose: (f, t, out) => {
      const k = 1 + Math.sin(t * 5) * 0.05;
      return set(out, N, { lax: -0.35, laz: 1.45 * k, lay: 0.7, rax: -0.35, raz: -1.45 * k, ray: -0.7, cx: -0.15, hx: -0.15, hy: -0.05, llz: 0.2, rlz: -0.2 });
    },
  },
  {
    id: 'bow', name: 'Поклон', icon: '🙇', dur: 2.2,
    pose: (f, t, out) => {
      const k = t < 0.4 ? t / 0.4 : t > 1.7 ? Math.max(0, (2.2 - t) / 0.5) : 1;
      return set(out, N, { cx: 0.95 * k, hx: 0.3 * k, hy: -0.15 * k, lax: 0.15, laz: 0.05, rax: -0.9 * k, raz: 0.7 * k, llx: -0.15 * k, rlx: -0.15 * k });
    },
  },
  {
    id: 'laugh', name: 'Смех', icon: '🤣', dur: 99,
    pose: (f, t, out) => {
      const sh = Math.sin(t * 28) * 0.05;
      return set(out, N, { cx: -0.3 + sh, hx: -0.45 + sh * 2, hy: Math.abs(Math.sin(t * 14)) * 0.08, lax: -0.6, laz: -0.5, rax: -0.6, raz: 0.5 });
    },
  },
  {
    id: 'sit', name: 'Сесть', icon: '🧘', dur: 99,
    pose: (f, t, out) => {
      const k = Math.min(1, t / 0.35);
      return set(out, N, { hy: -1.55 * k, llx: -1.55 * k, rlx: -1.55 * k, llz: 0.12, rlz: -0.12, lax: -0.5 * k, laz: 0.2, rax: -0.5 * k, raz: -0.2, cx: 0.08, hx: Math.sin(t * 0.8) * 0.06 });
    },
  },
  {
    id: 'clap', name: 'Хлопки', icon: '👏', dur: 99,
    pose: (f, t, out) => {
      const o = (Math.sin(t * 16) + 1) * 0.5;
      return set(out, N, { lax: -1.35, laz: -0.62 + o * 0.55, rax: -1.35, raz: 0.62 - o * 0.55, hx: -0.12, cx: 0.05 });
    },
  },
  {
    id: 'win', name: 'Победа', icon: '🏆', dur: 3.2,
    pose: (f, t, out) => {
      const j = Math.abs(Math.sin(t * 5));
      return set(out, N, { hy: j * 0.35, rax: -2.95, raz: -0.45, lax: -2.95, laz: 0.45, hx: -0.3, llx: -j * 0.5, rlx: -j * 0.4 });
    },
  },
];
