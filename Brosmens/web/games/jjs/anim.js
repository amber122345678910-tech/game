// Позы блочных персонажей: массив чисел, ключевые кадры, наложение на риг.
import { ease } from './util.js';

const KEYS = ['hy', 'lean', 'roll', 'twist', 'cx', 'cz', 'hx', 'hyaw', 'lax', 'lay', 'laz', 'rax', 'ray', 'raz', 'llx', 'llz', 'rlx', 'rlz', 'kat'];
export const K = {};
KEYS.forEach((k, i) => (K[k] = i));
export const NK = KEYS.length;

export function P(o = {}) {
  const a = new Float32Array(NK);
  for (const k in o) a[K[k]] = o[k];
  return a;
}
// Поза = база + изменения
export function PX(base, o) {
  const a = new Float32Array(base);
  for (const k in o) a[K[k]] = o[k];
  return a;
}

// Ключевые кадры: frames = [[t, pose], ...] (t — 0..1 доля действия). Пишет в out.
export function kf(frames, t, out) {
  if (t <= frames[0][0]) { out.set(frames[0][1]); return out; }
  for (let i = 1; i < frames.length; i++) {
    const [t1, p1] = frames[i];
    if (t <= t1) {
      const [t0, p0] = frames[i - 1];
      const k = ease.smooth((t - t0) / Math.max(1e-4, t1 - t0));
      for (let j = 0; j < NK; j++) out[j] = p0[j] + (p1[j] - p0[j]) * k;
      return out;
    }
  }
  out.set(frames[frames.length - 1][1]);
  return out;
}

export function blendInto(cur, target, k) {
  for (let j = 0; j < NK; j++) cur[j] += (target[j] - cur[j]) * k;
}

export function applyPose(m, a, extra) {
  m.spin.position.y = 2.6 + a[K.hy];
  m.spin.rotation.set(a[K.lean] + (extra ? extra.x : 0), 0, a[K.roll] + (extra ? extra.z : 0));
  m.chest.rotation.set(a[K.cx], a[K.twist], a[K.cz]);
  m.neck.rotation.set(a[K.hx], a[K.hyaw], 0);
  m.armL.rotation.set(a[K.lax], a[K.lay], a[K.laz]);
  m.armR.rotation.set(a[K.rax], a[K.ray], a[K.raz]);
  m.legL.rotation.set(a[K.llx], 0, a[K.llz]);
  m.legR.rotation.set(a[K.rlx], 0, a[K.rlz]);
  if (m.katana && m.katDrawn) m.katana.rotation.x = a[K.kat];
  if (m.arm2L && m.arm2L.visible) {
    m.arm2L.rotation.set(a[K.lax] * 0.6 + 0.35, a[K.lay] * 0.5, a[K.laz] + 0.4);
    m.arm2R.rotation.set(a[K.rax] * 0.6 + 0.35, a[K.ray] * 0.5, a[K.raz] - 0.4);
  }
}

// ---------- Базовые позы ----------
export const POSE = {
  idle: {
    fist: P({ hy: -0.12, twist: 0.28, cx: 0.06, lax: -0.6, laz: 0.22, rax: -0.85, raz: -0.12, ray: 0.1, llz: 0.1, rlz: -0.1, llx: -0.15, rlx: 0.15 }),
    gojo: P({ hy: 0, twist: 0.12, hx: -0.1, lax: 0.18, laz: 0.12, rax: 0.18, raz: -0.12, llz: 0.05, rlz: -0.05 }),
    sukuna: P({ hy: -0.05, twist: 0.1, hx: -0.14, lax: -1.15, laz: -0.95, rax: -1.0, raz: 0.95, llz: 0.12, rlz: -0.12 }),
    katana: P({ hy: -0.18, twist: 0.35, cx: 0.08, rax: -0.55, raz: 0.18, ray: 0.2, kat: 0.3, lax: -0.6, laz: -0.45, llz: 0.12, rlz: -0.12, llx: -0.25, rlx: 0.2 }),
    // катана в ножнах: спокойная стойка, левая рука придерживает ножны
    katanaH: P({ hy: -0.06, twist: 0.12, cx: 0.04, hx: -0.04, lax: -0.32, laz: -0.12, lay: 0.2, rax: -0.2, raz: -0.12, llz: 0.08, rlz: -0.08 }),
  },
  air: P({ hy: 0.1, lax: -0.35, laz: 0.7, rax: -0.35, raz: -0.7, llx: -0.7, rlx: 0.35, cx: 0.05 }),
  fall: P({ hy: 0.1, lax: -1.9, laz: 0.4, rax: -1.9, raz: -0.4, llx: -0.25, rlx: 0.25, cx: -0.05 }),
  block: P({ hy: -0.3, cx: 0.18, rax: -1.75, raz: 0.62, lax: -1.75, laz: -0.62, llx: -0.3, rlx: 0.3, llz: 0.1, rlz: -0.1, twist: 0.1 }),
  blockK: P({ hy: -0.3, cx: 0.12, rax: -1.35, raz: 0.5, ray: 0.3, kat: 1.45, lax: -1.4, laz: -0.7, llx: -0.3, rlx: 0.3, twist: 0.2 }),
  stun1: P({ hy: -0.15, cx: -0.32, hx: -0.35, lax: -0.35, laz: 0.55, rax: -0.2, raz: -0.7, llx: 0.18, rlx: -0.22, twist: -0.3 }),
  stun2: P({ hy: -0.2, cx: -0.25, hx: -0.25, lax: -0.15, laz: 0.75, rax: -0.4, raz: -0.45, llx: -0.2, rlx: 0.15, twist: 0.35, cz: 0.15 }),
  dazed: P({ hy: -0.35, cx: 0.35, hx: 0.45, lax: 0.1, laz: 0.15, rax: 0.1, raz: -0.15, llz: 0.15, rlz: -0.15 }),
  down: P({ hy: -2.05, lean: -1.5, lax: -0.2, laz: 1.25, rax: -0.3, raz: -1.1, llx: -0.1, llz: 0.22, rlz: -0.18, hx: -0.2 }),
  dashF: P({ hy: -0.3, lean: 0.5, lax: 1.0, laz: 0.25, rax: 1.0, raz: -0.25, llx: -0.6, rlx: 0.7 }),
  dashB: P({ hy: -0.2, lean: -0.35, lax: -0.6, laz: 0.6, rax: -0.6, raz: -0.6, llx: -0.6, rlx: 0.2 }),
  dashL: P({ hy: -0.3, roll: 0.4, twist: 0.2, lax: -0.3, laz: 1.0, rax: -0.6, raz: -0.3, llz: 0.5, rlz: 0.15 }),
  dashR: P({ hy: -0.3, roll: -0.4, twist: -0.2, lax: -0.6, laz: 0.3, rax: -0.3, raz: -1.0, llz: -0.15, rlz: -0.5 }),
  cast: P({ hy: -0.1, twist: 0.3, rax: -1.6, raz: 0.1, lax: 0.1, laz: 0.2, cx: 0.05 }),
  sign: P({ hy: -0.05, rax: -1.35, raz: 0.55, lax: -1.35, laz: -0.55, hx: -0.15, twist: 0 }),
  sign2: P({ hy: -0.05, rax: -2.2, raz: 0.25, ray: 0.3, lax: 0.1, laz: 0.15, hx: -0.12, twist: -0.2 }),
  taunt: P({ hy: 0, rax: -2.9, raz: -0.3, lax: 0.1, laz: 0.2, hx: -0.25 }),
  roar: P({ hy: -0.35, cx: -0.25, hx: -0.5, lax: -0.6, laz: 1.2, rax: -0.6, raz: -1.2, llz: 0.25, rlz: -0.25 }),
  // «Бесконечность» — блок Сильнейшего сегодня: расслабленная стойка, одна рука в сторону, парит над землёй
  inf: P({ hy: 0.3, twist: 0.18, hx: -0.06, cx: -0.04, lax: -0.75, laz: 0.75, lay: -0.3, rax: 0.12, raz: -0.12, llz: 0.06, rlz: -0.06, llx: -0.12, rlx: 0.1 }),
  // пробуждения
  faint: P({ hy: -0.55, cx: 0.55, hx: 0.6, lax: 0.15, laz: 0.1, rax: 0.15, raz: -0.1, llz: 0.12, rlz: -0.12, llx: -0.2, rlx: 0.15 }),
  palm: P({ hy: -0.12, twist: 0.1, cx: 0.12, hx: -0.05, lax: -1.55, laz: -0.55, rax: -1.45, raz: 0.5, llz: 0.12, rlz: -0.12 }),
  unveil: P({ hy: 0, twist: -0.1, hx: -0.25, rax: -2.85, raz: 0.55, ray: 0.4, lax: 0.15, laz: 0.2 }),
  spread: P({ hy: -0.1, cx: -0.2, hx: -0.35, lax: -1.4, laz: 1.25, rax: -1.4, raz: -1.25, llz: 0.2, rlz: -0.2 }),
};

// ---------- M1 (4 удара) ----------
const F = POSE.idle.fist;
const M1_FIST = [
  [[0, F], [0.3, PX(F, { twist: -0.45, rax: -0.7, raz: -0.3, lax: -1.2, laz: 0.3, cx: 0.0 })], [0.45, PX(F, { twist: 0.7, rax: -1.65, raz: 0.05, ray: 0, lax: -0.55, laz: 0.45, cx: 0.22, hy: -0.25, llx: -0.35, rlx: 0.4 })], [1, F]],
  [[0, F], [0.3, PX(F, { twist: 0.6, lax: -0.6, laz: 0.8, rax: -1.2, raz: -0.2 })], [0.45, PX(F, { twist: -0.75, lax: -1.6, laz: -0.25, lay: 0, rax: -0.8, raz: -0.3, cx: 0.22, hy: -0.25, llx: 0.35, rlx: -0.3 })], [1, F]],
  [[0, F], [0.3, PX(F, { twist: -0.3, hy: -0.4, rax: -0.2, raz: -0.4, cx: 0.25 })], [0.45, PX(F, { twist: 0.55, hy: -0.15, rax: -2.4, raz: 0.15, lax: -0.5, laz: 0.4, cx: -0.1, hx: -0.2, rlx: 0.35, llx: -0.3 })], [1, F]],
  [[0, F], [0.28, PX(F, { twist: -0.4, lean: 0.12, rlx: 0.6, hy: -0.15, rax: -0.3, raz: -0.6, lax: -0.3, laz: 0.6 })], [0.42, PX(F, { twist: 0.35, lean: -0.32, rlx: -1.75, llx: 0.25, hy: 0.05, rax: 0.4, raz: -0.9, lax: 0.4, laz: 0.9, cx: -0.1 })], [1, F]],
];
const GOJ = POSE.idle.gojo;
const M1_GOJO = [
  M1_FIST[0], M1_FIST[1],
  [[0, GOJ], [0.3, PX(GOJ, { twist: 0.4, rax: -0.4, lax: -0.6, laz: 0.5, hy: -0.2 })], [0.45, PX(GOJ, { twist: -0.5, lax: -1.65, laz: 0.1, cx: 0.2, hy: -0.3, llx: 0.3, rlx: -0.3, rax: 0.3 })], [1, GOJ]],
  [[0, GOJ], [0.28, PX(GOJ, { twist: -0.3, hy: -0.3, rax: -0.6, lax: -0.6, cx: 0.1 })], [0.42, PX(GOJ, { twist: 0, hy: -0.35, rax: -1.6, raz: 0.15, lax: -1.6, laz: -0.15, cx: 0.3, llx: -0.5, rlx: 0.5 })], [1, GOJ]],
];
const SK = POSE.idle.fist;
const M1_SUKUNA = [
  M1_FIST[0], M1_FIST[1], M1_FIST[2],
  [[0, SK], [0.28, PX(SK, { twist: -0.7, rax: -0.1, raz: -1.4, ray: -0.4, hy: -0.15 })], [0.45, PX(SK, { twist: 0.8, rax: -0.1, raz: -1.4, ray: 2.4, cx: 0.25, hy: -0.3, lax: -0.3, laz: 0.6, llx: -0.3, rlx: 0.3 })], [1, SK]],
];
const KT = POSE.idle.katana;
const M1_KATANA = [
  [[0, KT], [0.3, PX(KT, { rax: -2.6, raz: 0.3, kat: 0.6, twist: -0.2, lax: -2.3, laz: -0.3 })], [0.48, PX(KT, { rax: -0.5, raz: 0.5, kat: 1.2, twist: 0.4, cx: 0.3, hy: -0.35, lax: -0.6, laz: -0.5, llx: -0.35, rlx: 0.4 })], [1, KT]],
  [[0, KT], [0.3, PX(KT, { rax: -0.05, raz: -1.4, ray: -0.4, kat: 1.4, twist: -0.6 })], [0.48, PX(KT, { rax: -0.05, raz: -1.4, ray: 2.2, kat: 1.4, twist: 0.7, cx: 0.2, hy: -0.25, lax: -0.3, laz: 0.4 })], [1, KT]],
  [[0, KT], [0.3, PX(KT, { rax: -0.05, raz: 1.4, ray: -0.3, kat: 1.4, twist: 0.5, lax: -0.4 })], [0.48, PX(KT, { rax: -0.05, raz: 1.4, ray: -2.6, kat: 1.4, twist: -0.6, cx: 0.2, hy: -0.25 })], [1, KT]],
  [[0, KT], [0.28, PX(KT, { rax: -2.9, raz: -0.2, kat: 0.4, lax: -2.7, laz: 0.2, hy: 0.05, cx: -0.15, lean: -0.1 })], [0.45, PX(KT, { rax: -0.3, raz: 0.3, kat: 1.5, lax: -0.4, laz: -0.3, cx: 0.45, hy: -0.55, llx: -0.6, rlx: 0.6 })], [1, KT]],
];
export const M1ANIM = { fist: M1_FIST, gojo: M1_GOJO, sukuna: M1_SUKUNA, katana: M1_KATANA };

// 4-й удар: апперкот (в прыжке/с зажатым прыжком) и удар вниз (в падении)
const _m1v = {};
export function m1Variant(style, base, kind) {
  const key = style + kind;
  if (_m1v[key]) return _m1v[key];
  const kat = style === 'katana';
  let fr;
  if (kind === 'up') {
    fr = [[0, base],
      [0.3, PX(base, { hy: -0.45, cx: 0.3, twist: -0.5, rax: 0.4, raz: -0.3, lax: -0.6, laz: 0.4, kat: kat ? 1.2 : 0, llx: -0.4, rlx: 0.4 })],
      [0.46, PX(base, { hy: 0.15, cx: -0.25, hx: -0.25, twist: 0.45, rax: -2.95, raz: 0.15, lax: -0.3, laz: 0.5, kat: kat ? 0.5 : 0, rlx: -0.6, llx: 0.2 })],
      [1, base]];
  } else {
    fr = [[0, base],
      [0.25, PX(base, { hy: 0.1, cx: -0.3, rax: -2.95, raz: -0.15, lax: -2.95, laz: 0.15, kat: kat ? 0.3 : 0, llx: -0.8, rlx: -0.3 })],
      [0.45, PX(base, { hy: -0.3, cx: 0.55, rax: -0.55, raz: 0.3, lax: -0.55, laz: -0.3, kat: kat ? 1.5 : 0, llx: -0.9, rlx: 0.25 })],
      [1, base]];
  }
  return (_m1v[key] = fr);
}

// Пробежка. lx/lz — направление движения в системе персонажа (вправо / вперёд):
// с Shift-lock персонаж смотрит по камере, поэтому вбок — приставной шаг, назад — пятится.
export function runPose(out, base, phase, speed01, katana, lx = 0, lz = 1) {
  out.set(base);
  const s = Math.sin(phase), c = Math.cos(phase);
  const al = Math.abs(lx), af = Math.abs(lz), tot = al + af || 1;
  const wS = al / tot, wF = af / tot;
  const back = lz < 0;
  const amp = (back ? 0.7 : 0.95) * speed01;
  out[K.llx] = -s * amp * wF; out[K.rlx] = s * amp * wF;
  out[K.llz] = 0; out[K.rlz] = 0;
  if (wS > 0.05) {
    // приставной шаг: ведущая нога в сторону движения, вторая подтягивается
    const k = wS * Math.min(1.1, speed01 + 0.2), up = Math.max(0, s), dn = Math.max(0, -s);
    if (lx > 0) { out[K.rlz] = -0.46 * up * k; out[K.llz] = -0.3 * dn * k; }
    else { out[K.llz] = 0.46 * up * k; out[K.rlz] = 0.3 * dn * k; }
    out[K.llx] -= s * 0.18 * k; out[K.rlx] += s * 0.18 * k;
    out[K.roll] = (lx > 0 ? 1 : -1) * 0.07 * k * Math.abs(s);
  }
  const armK = speed01 * (back ? 0.55 : 1) * (0.35 + 0.65 * wF);
  if (katana) {
    out[K.lax] = s * 0.8 * armK; out[K.laz] = 0.1;
    out[K.rax] = -0.35 - s * 0.3 * armK; out[K.raz] = -0.1; out[K.ray] = 0; out[K.kat] = 0.25;
  } else {
    out[K.lax] = s * 0.9 * armK; out[K.laz] = 0.08 + wS * 0.12;
    out[K.rax] = -s * 0.9 * armK; out[K.raz] = -0.08 - wS * 0.12; out[K.ray] = 0; out[K.lay] = 0;
  }
  out[K.twist] = s * 0.12 * speed01 * wF;
  out[K.cx] = (back ? -0.1 : 0.18) * speed01 * wF + 0.04 * wS;
  out[K.lean] = 0;
  out[K.hy] = Math.abs(c) * (back ? 0.14 : 0.22) * speed01 - 0.05;
  out[K.hx] = back ? 0.06 * speed01 : 0;
  return out;
}
