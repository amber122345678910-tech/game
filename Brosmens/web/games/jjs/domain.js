// Расширение территории (спека §5.7, §7): ручная печать 1.25 с (сбивается ударом/оглушением, не в воздухе),
// захват всех в радиусе 37.5 стадов, баннер «DOMAIN | EXPANSION» (HUD) + белая вспышка, затем интерьер:
//  • Unlimited (Infinite) Void — гиперпространство, тёмная звёздная пустота, жёлтое кольцо, белая граница;
//    все пойманные оглушены на всё время (уже начатые действия не отменяются). ~8 с.
//  • Malevolent Shrine — чёрная граница, красный оттенок, храм встаёт за кастером, постоянные белые разрезы:
//    2 урона каждые 0.165 с в течение 18 с (0.5 в блоке, блокирующих не убивает).
// Пойманные переносятся в «интерьер» — арену высоко над городом (те же позиции относительно кастера), снаружи
// виден непрозрачный купол. Смерть кастера или конец времени — домен рушится, все возвращаются на свои места.
import * as THREE from 'three';
import { G } from './ctx.js';
import { POSE } from './anim.js';
import { buildShrine } from './rig.js';
import { rand, tex, ease, canvasTex } from './util.js';

export const DOMAIN_R = 37.5;
const CAST = 1.25, BANNER = 0.9, WHITE = 0.5, REVEAL = BANNER + WHITE;
const DUR = { void: 8, shrine: 18 };
const LIFT = 320; // высота интерьера над местом каста
const _a = new THREE.Vector3(), _b = new THREE.Vector3(), _c = new THREE.Vector3();

G.domains = [];
export function domainAt(p, pad = 0) {
  for (const d of G.domains) if (!d.closing && Math.hypot(p.x - d.center.x, p.z - d.center.z) < d.r + pad) return d;
  return null;
}
export function inDomainOf(f) {
  for (const d of G.domains) if (!d.closing && d.caught.has(f)) return d;
  return null;
}

// ---------- меши (пул по виду) ----------
const pool = { void: [], shrine: [] };
let ringTex = null, holeTex = null, shrineSkyTex = null;
function voidTextures() {
  if (ringTex) return;
  ringTex = canvasTex(256, 256, (g, w) => {
    const c = w / 2;
    const gr = g.createRadialGradient(c, c, c * 0.62, c, c, c * 0.98);
    gr.addColorStop(0, 'rgba(255,200,60,0)'); gr.addColorStop(0.3, 'rgba(255,214,90,.55)'); gr.addColorStop(0.42, 'rgba(255,252,220,1)');
    gr.addColorStop(0.55, 'rgba(255,200,70,.6)'); gr.addColorStop(0.8, 'rgba(255,140,20,.12)'); gr.addColorStop(1, 'rgba(255,120,0,0)');
    g.fillStyle = gr; g.fillRect(0, 0, w, w);
  });
  holeTex = canvasTex(256, 256, (g, w) => {
    const c = w / 2;
    let gr = g.createRadialGradient(c, c, 0, c, c, c);
    gr.addColorStop(0, 'rgba(255,190,60,0)'); gr.addColorStop(0.42, 'rgba(255,200,70,0)'); gr.addColorStop(0.5, 'rgba(255,236,150,1)');
    gr.addColorStop(0.56, 'rgba(255,190,60,.85)'); gr.addColorStop(0.75, 'rgba(255,150,30,.25)'); gr.addColorStop(1, 'rgba(255,120,0,0)');
    g.fillStyle = gr; g.fillRect(0, 0, w, w);
    gr = g.createRadialGradient(c, c, 0, c, c, c * 0.47);
    gr.addColorStop(0, 'rgba(0,0,0,1)'); gr.addColorStop(0.9, 'rgba(0,0,0,1)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
    g.globalCompositeOperation = 'source-over'; g.fillStyle = gr; g.beginPath(); g.arc(c, c, c * 0.47, 0, 7); g.fill();
  });
}
function shrineSky() {
  if (shrineSkyTex) return shrineSkyTex;
  shrineSkyTex = canvasTex(512, 256, (g, w, h) => {
    const gr = g.createLinearGradient(0, 0, 0, h);
    gr.addColorStop(0, '#000000'); gr.addColorStop(0.42, '#120203'); gr.addColorStop(0.5, '#5a0a0c'); gr.addColorStop(0.54, '#2a0405'); gr.addColorStop(1, '#0a0101');
    g.fillStyle = gr; g.fillRect(0, 0, w, h);
    // красный дым на горизонте
    for (let i = 0; i < 70; i++) {
      const x = Math.random() * w, y = h * (0.44 + Math.random() * 0.1), r = 10 + Math.random() * 34;
      const rg = g.createRadialGradient(x, y, 0, x, y, r);
      rg.addColorStop(0, `rgba(${150 + Math.random() * 80 | 0},10,14,.35)`); rg.addColorStop(1, 'rgba(80,0,0,0)');
      g.fillStyle = rg; g.fillRect(x - r, y - r, r * 2, r * 2);
    }
  });
  return shrineSkyTex;
}
function getMeshes(kind) {
  let m = pool[kind].find((x) => !x.busy);
  if (!m) {
    const add = { transparent: true, depthWrite: false, fog: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide };
    const sphere = new THREE.SphereGeometry(1, 40, 22);
    // внутренняя сторона (видна изнутри) и внешняя оболочка (видна снаружи)
    const inner = new THREE.Mesh(sphere, new THREE.MeshBasicMaterial({ map: kind === 'void' ? tex('void') : shrineSky(), side: THREE.BackSide, fog: false, transparent: true }));
    // оболочка у земли — её видят те, кто остался снаружи (белая у Пустоты, чёрная у Гробницы)
    const outer = new THREE.Mesh(sphere, new THREE.MeshBasicMaterial({ color: kind === 'void' ? 0xf4f8ff : 0x050303, side: THREE.DoubleSide, fog: false, transparent: true }));
    const floor = new THREE.Mesh(new THREE.CircleGeometry(1, 56), new THREE.MeshBasicMaterial({ map: kind === 'void' ? tex('void') : tex('shrine'), color: kind === 'void' ? 0x8a90b8 : 0x7a5a5a, fog: false, transparent: true }));
    floor.rotation.x = -Math.PI / 2;
    // граница у земли: белая (Пустота) или чёрная (Гробница) светящаяся полоса
    const band = new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 1, 56, 1, true), new THREE.MeshBasicMaterial(kind === 'void' ? { ...add, color: 0xffffff } : { color: 0x000000, transparent: true, depthWrite: false, fog: false, side: THREE.DoubleSide }));
    inner.renderOrder = 3; outer.renderOrder = 4; floor.renderOrder = 2; band.renderOrder = 5;
    const objs = [inner, outer, floor, band];
    m = { kind, busy: false, inner, outer, floor, band, objs };
    if (kind === 'void') {
      voidTextures();
      const ring = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), new THREE.MeshBasicMaterial({ map: ringTex, ...add }));
      const hole = new THREE.Sprite(new THREE.SpriteMaterial({ map: holeTex, transparent: true, depthWrite: false, fog: false }));
      ring.renderOrder = 6; hole.renderOrder = 6;
      m.ring = ring; m.hole = hole; objs.push(ring, hole);
    } else {
      const sh = buildShrine();
      m.shrine = sh; objs.push(sh.root);
    }
    for (const o of objs) { o.frustumCulled = false; G.scene.add(o); }
    pool[kind].push(m);
  }
  m.busy = true;
  for (const o of m.objs) o.visible = true;
  return m;
}
function freeMeshes(m) { m.busy = false; for (const o of m.objs) o.visible = false; }
export function resetDomains() {
  for (const k in pool) for (const m of pool[k]) freeMeshes(m);
  for (const d of G.domains) G.world?.removeFloor(d.floor);
  G.domains.length = 0;
}

// ---------- каст (ручная печать) ----------
export function castDomain(f, kind) {
  const pop = (txt) => { if (f.isPlayer) G.hud.pop(f.headPos(_a), txt, '#c8c8c8', 0.9); };
  if (!f.onGround || f.airborne()) { pop('НЕ В ВОЗДУХЕ'); return false; }
  if (domainAt(f.pos, 4)) { pop('ВНУТРИ ДОМЕНА'); return false; }
  const col = kind === 'void' ? '#bfe6ff' : '#ff3050';
  const sign = kind === 'void' ? POSE.sign2 : POSE.sign;
  const idle = f.idlePose;
  let shell = null;
  const freeShell = () => { if (shell) { G.fx.release(shell); shell = null; } };
  f.startAction({
    name: kind === 'void' ? 'void' : 'shrine', kind: 'domain', dur: CAST, windup: 0.3, noFeint: true, poseSpeed: 18,
    frames: [[0, idle], [0.2, sign], [1, sign]],
    update: (ff, dt, t) => {
      // свечение у рук и растущая полупрозрачная сфера в последние 0.45 с
      ff.handPos('R', _a);
      if (Math.random() < 0.7) G.fx.add.spawn(_a.x + rand(-0.3, 0.3), _a.y + rand(-0.3, 0.3), _a.z + rand(-0.3, 0.3), rand(-1, 1), rand(1, 3), rand(-1, 1), Math.random() < 0.5 ? '#ffffff' : col, 1, 0.8, 0.1, 0.35);
      if (t > CAST - 0.45) {
        if (!shell) { shell = G.fx.pool('sphere'); shell.mat.color.set(kind === 'void' ? '#e8f4ff' : '#ff2040'); }
        const k = (t - (CAST - 0.45)) / 0.45;
        ff.chestPos(_b); shell.obj.position.copy(_b); shell.obj.scale.setScalar(1 + k * 5); shell.mat.opacity = 0.25 + k * 0.35;
      }
    },
    onEnd: (ff) => { freeShell(); openDomain(ff, kind); },
    onCancel: (ff, a) => {
      freeShell();
      // сбитая печать: домен не раскрылся — короткая перезарядка вместо 120 с
      if (a.cdArr && a.slot != null) { a.cdArr[a.slot] = 8; if (ff.cd === a.cdArr) ff.cdMax[a.slot] = 8; }
      ff.chestPos(_b); G.fx.burst(_b, col, 6, 0.2);
      if (ff.isPlayer) G.hud.pop(ff.headPos(_a), 'ПЕЧАТЬ СБИТА', '#ffffff', 1.1);
    },
  });
  G.sound('charge', f.pos, 0.6);
  // ближайшие игроки видят предупреждение — у них 1.25 с, чтобы сбить печать
  G.callout(f, 'Domain Expansion…', col, false, 1.2);
  return true;
}

// ---------- раскрытие ----------
function openDomain(f, kind) {
  if (f.dead) return;
  const center = f.pos.clone();
  const R = DOMAIN_R;
  const caught = new Set([f]);
  for (const o of G.fighters) {
    if (o.dead || o === f) continue;
    if (Math.hypot(o.pos.x - center.x, o.pos.z - center.z) <= R && Math.abs(o.pos.y - center.y) < R) caught.add(o);
  }
  // кто уже пойман чужим доменом — не забираем
  for (const d of G.domains) if (!d.closing) for (const o of d.caught) if (o !== f) caught.delete(o);
  const m = getMeshes(kind);
  f.fwd(_a);
  const ic = center.clone(); ic.y += LIFT;
  const D = { kind, owner: f, center, ic, r: R, t: 0, L: DUR[kind] + REVEAL, caught, m, tick: 0, closing: false, closeT: 0, fwd: _a.clone(), back: new Map() };
  // интерьер: круглый пол высоко над городом, все пойманные — туда же относительно кастера (под баннером/вспышкой)
  D.floor = { x: ic.x, z: ic.z, r: R + 1, y: ic.y };
  G.world.addFloor(D.floor);
  for (const o of caught) {
    D.back.set(o, o.pos.clone());
    o.pos.y = ic.y + Math.max(0, o.pos.y - center.y);
    o.vel.y = Math.max(0, o.vel.y); o.onGround = false;
  }
  // куда смотрит игрок — там на «небе» будет чёрная дыра
  const p = G.player;
  D.holeDir = new THREE.Vector3(-D.fwd.x, 0, -D.fwd.z);
  if (p && caught.has(p) && G.camRay) { D.holeDir.set(G.camRay.dir.x, 0, G.camRay.dir.z); if (D.holeDir.lengthSq() < 0.01) D.holeDir.set(-D.fwd.x, 0, -D.fwd.z); }
  D.holeDir.normalize();
  G.domains.push(D);
  if (p && caught.has(p)) G.hud.domainBanner(f, kind);
  else G.callout(f, kind === 'void' ? 'Domain Expansion: Infinite Void' : 'Domain Expansion: Malevolent Shrine', kind === 'void' ? '#bfe6ff' : '#ff3050');
  G.sound('gong', center, 1.2);
  G.shake(0.5, center);
  // Пустота: пойманным — «∞» над головой
  if (kind === 'void') for (const o of caught) if (o !== f) { o.headPos(_b); _b.y += 0.6; G.hud.pop(_b, '∞', '#bfe6ff', 1.6); }
  for (const o of caught) if (o !== f) o.brain?.onDomain?.(D);
  G.onDomain?.(D);
  G.addTask((dt) => tickDomain(D, dt));
}

function close(D) {
  if (D.closing) return;
  D.closing = true; D.closeT = 0;
  // домен рушится: все живые пойманные возвращаются туда, где стояли до переноса
  for (const o of D.caught) {
    if (o.dead) continue;
    const b = D.back.get(o);
    if (b) { o.pos.copy(b); o.vel.set(0, 0, 0); o.onGround = false; }
    else o.pos.y -= LIFT;
    if (o.isPlayer) G.hud.flash('#ffffff', 0.7, 2.6);
  }
  G.world.removeFloor(D.floor);
  for (const k of ['inner', 'floor', 'band', 'ring', 'hole']) if (D.m[k]) D.m[k].visible = false;
  if (D.m.shrine) D.m.shrine.root.visible = false;
}

function tickDomain(D, dt) {
  const { m, center, ic, r: R } = D;
  D.t += dt;
  const t = D.t, f = D.owner;
  if (G.matchOver) { if (!D.closing) close(D); freeMeshes(m); G.domains.splice(G.domains.indexOf(D), 1); return false; }
  if (!D.closing && (f.dead || t >= D.L)) close(D);
  // оболочка у земли растёт из кастера и схлопывается в конце
  let s;
  if (D.closing) {
    D.closeT += dt;
    s = Math.max(0, 1 - ease.out3(Math.min(1, D.closeT / 0.6)));
    if (D.closeT >= 0.6) { freeMeshes(m); G.domains.splice(G.domains.indexOf(D), 1); return false; }
  } else s = ease.out3(Math.min(1, t / 0.6));
  const rr = Math.max(0.01, R * s);
  m.outer.position.copy(center); m.outer.scale.setScalar(rr);
  m.outer.material.opacity = D.kind === 'void' ? 0.96 : 0.97;
  if (D.closing) return true;
  // интерьер
  const reveal = Math.min(1, Math.max(0, (t - BANNER) / WHITE));
  m.inner.position.copy(ic); m.inner.scale.setScalar(R);
  m.floor.position.set(ic.x, ic.y + 0.06, ic.z); m.floor.scale.setScalar(R);
  m.band.position.set(ic.x, ic.y + 1.6, ic.z); m.band.scale.set(R * 0.985, 3.2, R * 0.985);
  m.inner.material.opacity = 0.4 + 0.6 * reveal;
  m.floor.material.opacity = 0.95;
  m.band.material.opacity = D.kind === 'void' ? 0.5 + Math.sin(t * 6) * 0.1 : 0.85;
  m.inner.rotation.y += dt * (D.kind === 'void' ? 0.05 : 0.01);
  // барьер: пойманные — внутри круга интерьера, остальные — снаружи оболочки
  for (const o of G.fighters) {
    if (o.dead) { if (D.caught.has(o)) D.caught.delete(o); continue; }
    if (D.caught.has(o)) {
      const dx = o.pos.x - ic.x, dz = o.pos.z - ic.z, d = Math.hypot(dx, dz) || 0.001, lim = R - 1.4;
      if (d > lim) { o.pos.x = ic.x + (dx / d) * lim; o.pos.z = ic.z + (dz / d) * lim; }
      if (o.pos.y < ic.y - 2) { o.pos.y = ic.y; o.vel.y = 0; } // не провалиться
    } else if (Math.abs(o.pos.y - center.y) < R) {
      const dx = o.pos.x - center.x, dz = o.pos.z - center.z, d = Math.hypot(dx, dz) || 0.001;
      if (d < rr + 1.4) { o.pos.x = center.x + (dx / d) * (rr + 1.4); o.pos.z = center.z + (dz / d) * (rr + 1.4); }
    }
  }
  if (D.kind === 'void') tickVoid(D, dt, t, R); else tickShrine(D, dt, t, R);
  return true;
}

function tickVoid(D, dt, t, rr) {
  const { m, owner } = D;
  const center = D.ic;
  // чёрная дыра с ярким жёлтым кольцом на «небе» пустоты и наклонный аккреционный диск вокруг неё
  const k = Math.min(1, Math.max(0, (t - REVEAL) / 1.2));
  _a.set(center.x + D.holeDir.x * rr * 0.72, center.y + rr * 0.3, center.z + D.holeDir.z * rr * 0.72);
  m.hole.position.copy(_a); m.hole.scale.setScalar(rr * 0.36 * (0.95 + 0.05 * Math.sin(t * 2))); m.hole.material.opacity = k;
  m.ring.position.copy(_a); m.ring.scale.setScalar(rr * 0.5);
  m.ring.lookAt(center.x, center.y + rr * 0.9, center.z); m.ring.rotateX(0.35); m.ring.rotateZ(t * 0.15);
  m.ring.material.opacity = 0.8 * k;
  // гиперпространство: розово-синие полосы, летящие от центра в первые ~1.2 с после вспышки
  if (!D.closing && t > REVEAL - 0.1 && t < REVEAL + 1.3) {
    for (let i = 0; i < 6; i++) {
      _b.set(rand(-1, 1), rand(-0.3, 0.8), rand(-1, 1)).normalize();
      _c.copy(center).addScaledVector(_b, rand(2, rr * 0.5)); _c.y = Math.max(center.y + 0.5, _c.y);
      _b.multiplyScalar(rand(70, 120));
      G.fx.str.add(_c, _b, Math.random() < 0.5 ? '#ff5fe0' : '#5fa8ff', rand(0.25, 0.45), 0.16, rand(6, 12), { drag: 0 });
    }
  }
  // звёздная пыль
  if (t > REVEAL && Math.random() < 0.6) {
    _a.set(center.x + rand(-1, 1) * rr * 0.7, center.y + rand(0.5, rr * 0.5), center.z + rand(-1, 1) * rr * 0.7);
    G.fx.add.spawn(_a.x, _a.y, _a.z, 0, rand(-0.5, 0.5), 0, Math.random() < 0.5 ? '#ffffff' : '#9fd8ff', 1, 0.5, 0.1, 1.4);
  }
  // оглушение всех пойманных на всё время домена, не отменяя уже начатых действий
  for (const o of D.caught) {
    if (o === owner || o.dead || G.isAlly(owner, o)) continue;
    if (!o.action && !o.rag) { o.stun = Math.max(o.stun, 0.25); o.broken = Math.max(o.broken, 0.25); o.blocking = false; }
    if (Math.random() < dt * 3) { o.headPos(_a); _a.x += rand(-1.5, 1.5); _a.z += rand(-1.5, 1.5); G.fx.add.spawn(_a.x, _a.y, _a.z, 0, 1.5, 0, '#bfe6ff', 0.9, 0.7, 0.1, 0.6); }
  }
}

function tickShrine(D, dt, t, rr) {
  const { m, owner } = D;
  const center = D.ic;
  // храм поднимается за кастером
  const sh = m.shrine.root;
  if (t < 0.05 || !D.base) { D.base = center.clone().addScaledVector(D.fwd, -rr * 0.7); sh.rotation.y = Math.atan2(D.fwd.x, D.fwd.z); sh.scale.setScalar(1.35); }
  const rise = ease.out3(Math.min(1, Math.max(0, t - BANNER) / 0.8));
  sh.position.set(D.base.x, center.y - 28 * (1 - rise), D.base.z);
  // камера внутри храма — прячем его, чтобы не загораживал экран
  const cam = G.camera.position;
  _b.set(cam.x - D.base.x, 0, cam.z - D.base.z).applyAxisAngle(_c.set(0, 1, 0), -sh.rotation.y);
  sh.visible = !(Math.abs(_b.x) < 13 && Math.abs(_b.z) < 10 && cam.y < center.y + 22);
  if (t > BANNER && t < BANNER + 0.9 && Math.random() < 0.8) { _a.set(D.base.x + rand(-10, 10), center.y + 0.5, D.base.z + rand(-10, 10)); G.fx.debris(_a, 1, ['#2b2524', '#6a1818']); G.fx.dust(_a, 2, 3, '#3a1414'); }
  // постоянные белые разрезы по всей зоне
  if (t > REVEAL - 0.2) for (let i = 0; i < 3; i++) {
    const ang = rand(0, Math.PI * 2), r0 = Math.sqrt(Math.random()) * rr * 0.9;
    _a.set(center.x + Math.cos(ang) * r0, center.y + rand(0.5, 9), center.z + Math.sin(ang) * r0);
    _b.set(rand(-1, 1), rand(-0.5, 0.5), rand(-1, 1)).normalize();
    _c.copy(_a).addScaledVector(_b, rand(4, 9));
    G.fx.line(_a, _c, Math.random() < 0.2 ? '#ff4050' : '#ffffff', 0.1, rand(0.08, 0.16));
  }
  // 2 урона каждые 0.165 с (0.5 в блоке, блок не даёт умереть), не сбивают действия
  D.tick -= dt;
  if (t > REVEAL && D.tick <= 0) {
    D.tick += 0.165;
    let n = 0;
    for (const o of D.caught) {
      if (o === owner || o.dead) continue;
      const r = G.hit(owner, o, { dmg: 2, block360: true, chip: 0.25, chipKill: false, bypassRag: true, noCounter: true, noInterrupt: true, noPush: true, noStop: true, hitstop: 0, fx: 'none', shake: 0.05, sfx: n++ ? 'none' : 'slash', vol: 0.3, from: owner.pos });
      if (r) {
        o.chestPos(_a);
        _b.set(rand(-1, 1), rand(-0.8, 0.8), rand(-1, 1)).normalize();
        _c.copy(_a).addScaledVector(_b, 2.6); _a.addScaledVector(_b, -2.6);
        G.fx.line(_a, _c, '#ffffff', 0.09, 0.14);
        if (r === 'hit' && Math.random() < 0.4) { o.chestPos(_a); G.fx.particles(_a, { n: 2, color: '#c0101c', speed: 5, size: 0.4, size1: 0.2, life: 0.35, grav: 20 }); }
      }
    }
  }
}
