// Лобби между раундами (в духе «отеля» UJD, всё своё): тёплый оранжево-жёлтый шахматный пол (#B06010/#C09008),
// кремовые стены (#C0B888) с деревянными панелями, красный ковёр-кольцо вокруг фонтана с золотым сердцем,
// вывеска «МАГАЗИН ДУШ» радужными пиксельными буквами, доска «ОЧЕРЕДЬ» (кто следующий Судья), ларёк с пирогами,
// полка с зельями, кресла. По лобби гуляют аватары игроков сервера (имена над головой, иногда прыгают).
// Свой аватар водишь джойстиком (как в роблоксе: 16 ст/с, прыжок 50, гравитация 196.2); подойдёшь к стойке
// «МАГАЗИН ДУШ» — откроется магазин (lobby.zone === 'shop').
import * as THREE from 'three';
import { buildAvatar3D, animateAvatar } from '../../shared/avatar.js';
import { canvasTex, glowTex, drawHeart } from './fx.js';
import { drawPixText, measurePixText, pixTexture } from './pixfont.js';
import { GRAV, JUMP_V } from './data.js';

const RX = 34, RZ = 28, RH = 24;           // половины комнаты и высота
const FOUNT_R = 9.6;                        // ближе к центру не ходят боты (фонтан + ковёр)
const ME_R = 8.2;                           // свой аватар упирается в чашу фонтана
// препятствия (x0, x1, z0, z1) — стойка магазина, ларёк с пирогами, кресла; радиус аватара добавляется
const OBST = [[-20.2, -3.8, -27.2, -23.8], [26.9, 35.9, -9.9, -6.1], [29.3, 33, 15.2, 18.8], [29.3, 33, 20.2, 23.8]];
const lerpAngle = (a, b, t) => { let d = (b - a) % (Math.PI * 2); if (d > Math.PI) d -= Math.PI * 2; else if (d < -Math.PI) d += Math.PI * 2; return a + d * t; };
function pushOut(p, r) {
  for (const [x0, x1, z0, z1] of OBST) {
    if (p.x < x0 - r || p.x > x1 + r || p.z < z0 - r || p.z > z1 + r) continue;
    const dl = p.x - (x0 - r), dr = x1 + r - p.x, dn = p.z - (z0 - r), df = z1 + r - p.z, m = Math.min(dl, dr, dn, df);
    if (m === dl) p.x = x0 - r; else if (m === dr) p.x = x1 + r; else if (m === dn) p.z = z0 - r; else p.z = z1 + r;
  }
}
const SOULS = ['#F80000', '#F86800', '#F0F800', '#00F820', '#00F8F8', '#0010F8', '#B000F8', '#F840E0'];
const lam = (c, e = 0, ei = 1) => new THREE.MeshLambertMaterial({ color: c, emissive: e, emissiveIntensity: ei });
const rand = (a, b) => a + Math.random() * (b - a);

function mergeGeos(list) {
  const pos = [], nor = [], uv = [];
  for (const g0 of list) {
    const g = g0.index ? g0.toNonIndexed() : g0;
    pos.push(...g.attributes.position.array); nor.push(...g.attributes.normal.array);
    if (g.attributes.uv) uv.push(...g.attributes.uv.array); else uv.push(...new Array((g.attributes.position.count) * 2).fill(0));
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  out.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  return out;
}
const box = (w, h, d, x, y, z) => new THREE.BoxGeometry(w, h, d).translate(x, y, z);

function floorTex() {
  const t = canvasTex(256, 256, (g) => {
    for (let r = 0; r < 2; r++) for (let c = 0; c < 2; c++) {
      const odd = (r + c) % 2;
      g.fillStyle = odd ? '#C09008' : '#B06010'; g.fillRect(c * 128, r * 128, 128, 128);
      g.fillStyle = 'rgba(255,240,200,.07)'; g.fillRect(c * 128 + 6, r * 128 + 6, 116, 4);
      g.fillStyle = 'rgba(60,30,0,.18)'; g.fillRect(c * 128, r * 128 + 126, 128, 2); g.fillRect(c * 128 + 126, r * 128, 2, 128);
    }
  });
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8;
  return t;
}
function wallTex() {
  return canvasTex(64, 256, (g) => {
    g.fillStyle = '#C0B888'; g.fillRect(0, 0, 64, 256);
    // обои: тонкие вертикальные полоски
    g.fillStyle = 'rgba(150,130,80,.18)'; for (let x = 0; x < 64; x += 16) g.fillRect(x, 0, 3, 256);
    g.fillStyle = 'rgba(255,250,230,.12)'; for (let x = 8; x < 64; x += 16) g.fillRect(x, 0, 2, 256);
  });
}
function waterTex() {
  const t = canvasTex(64, 128, (g) => {
    g.fillStyle = 'rgba(150,225,255,.55)'; g.fillRect(0, 0, 64, 128);
    for (let i = 0; i < 26; i++) { g.fillStyle = `rgba(255,255,255,${0.15 + Math.random() * 0.35})`; g.fillRect(Math.random() * 64, Math.random() * 128, 1 + Math.random() * 2, 10 + Math.random() * 30); }
  });
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}
function poolTex() {
  const t = canvasTex(128, 128, (g) => {
    const gr = g.createRadialGradient(64, 64, 10, 64, 64, 64); gr.addColorStop(0, '#9fe8ff'); gr.addColorStop(1, '#3aa8e0');
    g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
    g.strokeStyle = 'rgba(255,255,255,.35)'; g.lineWidth = 2;
    for (let r = 14; r < 64; r += 12) { g.beginPath(); g.arc(64, 64, r + Math.random() * 3, 0, 7); g.stroke(); }
  });
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}
// вывеска радужными пиксельными буквами (каждая буква — цвет души)
function rainbowSignTex(text) {
  const px = 9, out = 4;
  const w = Math.ceil(measurePixText(text, px)) + out * 2 + 24, hh = 7 * px + out * 2 + 20;
  const t = canvasTex(w, hh, (g) => {
    g.fillStyle = '#101010'; g.fillRect(0, 0, w, hh);
    g.strokeStyle = '#ffffff'; g.lineWidth = 3; g.strokeRect(4, 4, w - 8, hh - 8);
    let x = 12 + out, k = 0;
    for (const ch of text) {
      if (ch !== ' ') drawPixText(g, ch, x, 10 + out, px, { fill: SOULS[k++ % SOULS.length], outline: '#000', outlineW: out });
      x += Math.round((measurePixText(ch, px) / px + 1) * px);
    }
  });
  t.userData.aspect = w / hh;
  return t;
}

function heartShape() {
  const s = new THREE.Shape();
  s.moveTo(0, -1.0);
  s.bezierCurveTo(-0.3, -0.7, -1.1, -0.25, -1.1, 0.3);
  s.bezierCurveTo(-1.1, 0.8, -0.55, 1.05, -0.28, 1.0);
  s.bezierCurveTo(-0.1, 0.97, 0, 0.82, 0, 0.7);
  s.bezierCurveTo(0, 0.82, 0.1, 0.97, 0.28, 1.0);
  s.bezierCurveTo(0.55, 1.05, 1.1, 0.8, 1.1, 0.3);
  s.bezierCurveTo(1.1, -0.25, 0.3, -0.7, 0, -1.0);
  return s;
}

export function buildLobby(scene, fx) {
  const group = new THREE.Group(); group.visible = false; scene.add(group);
  const statics = (o) => { o.matrixAutoUpdate = false; o.updateMatrix(); group.add(o); return o; };

  // ---------- пол, ковёр ----------
  const ft = floorTex(); ft.repeat.set((RX * 2) / 12, (RZ * 2) / 12);
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(RX * 2, RZ * 2), lam(0xffffff)); floor.material.map = ft;
  floor.rotation.x = -Math.PI / 2; statics(floor);
  const carpet = new THREE.Mesh(new THREE.RingGeometry(8.6, 12.4, 56).rotateX(-Math.PI / 2), lam(0xb3122a, 0x300008, 0.6)); carpet.position.y = 0.04; statics(carpet);
  const trimR = (a, b, y) => { const m = new THREE.Mesh(new THREE.RingGeometry(a, b, 56).rotateX(-Math.PI / 2), lam(0xe0b030, 0x402800, 0.6)); m.position.y = y; statics(m); };
  trimR(8.4, 8.75, 0.06); trimR(12.3, 12.65, 0.06);

  // ---------- стены, панели, потолок ----------
  const wt = wallTex(); wt.wrapS = THREE.RepeatWrapping; wt.repeat.set(10, 1);
  const wallMat = lam(0xffffff); wallMat.map = wt;
  const walls = [box(RX * 2, RH, 1, 0, RH / 2, -RZ - 0.5), box(RX * 2, RH, 1, 0, RH / 2, RZ + 0.5), box(1, RH, RZ * 2, -RX - 0.5, RH / 2, 0), box(1, RH, RZ * 2, RX + 0.5, RH / 2, 0)];
  statics(new THREE.Mesh(mergeGeos(walls), wallMat));
  const wood = [], gold = [];
  for (const s of [-1, 1]) {
    wood.push(box(RX * 2, 4.2, 0.5, 0, 2.1, s * (RZ - 0.25)), box(0.5, 4.2, RZ * 2, s * (RX - 0.25), 2.1, 0));
    gold.push(box(RX * 2, 0.35, 0.7, 0, 4.3, s * (RZ - 0.3)), box(0.7, 0.35, RZ * 2, s * (RX - 0.3), 4.3, 0));
    gold.push(box(RX * 2, 0.8, 0.9, 0, RH - 2.4, s * (RZ - 0.4)), box(0.9, 0.8, RZ * 2, s * (RX - 0.4), RH - 2.4, 0));
    // пилястры
    for (let x = -RX + 6; x <= RX - 6; x += 11) gold.push(box(1.2, RH - 7, 0.5, x, (RH - 7) / 2 + 4.4, s * (RZ - 0.3)));
    for (let z = -RZ + 6; z <= RZ - 6; z += 11) gold.push(box(0.5, RH - 7, 1.2, s * (RX - 0.3), (RH - 7) / 2 + 4.4, z));
  }
  statics(new THREE.Mesh(mergeGeos(wood), lam(0x7a4a1c)));
  statics(new THREE.Mesh(mergeGeos(gold), lam(0xd8a830, 0x3a2600, 0.5)));
  const ceil = new THREE.Mesh(new THREE.PlaneGeometry(RX * 2, RZ * 2), lam(0xd9cb98, 0x2a2010, 0.3)); ceil.rotation.x = Math.PI / 2; ceil.position.y = RH; statics(ceil);
  // люстры: золотое кольцо + тёплое свечение
  for (const [x, z] of [[-17, -10], [17, -10], [-17, 12], [17, 12], [0, 0]]) {
    const r = new THREE.Mesh(new THREE.TorusGeometry(1.6, 0.18, 6, 20).rotateX(Math.PI / 2), lam(0xe8b838, 0x604000, 0.7)); r.position.set(x, RH - 3.5, z); statics(r);
    const gl = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), color: 0xfff0b0, transparent: true, opacity: 0.85, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
    gl.position.set(x, RH - 3.6, z); gl.scale.setScalar(6); group.add(gl);
  }

  // ---------- фонтан с золотым сердцем ----------
  const cream = lam(0xeadcae, 0x3a3018, 0.4), goldM = lam(0xf0c040, 0x6a4a00, 0.6);
  statics(new THREE.Mesh(new THREE.CylinderGeometry(7, 7.3, 1.5, 40).translate(0, 0.75, 0), cream));
  const pool = new THREE.Mesh(new THREE.CircleGeometry(6.5, 40).rotateX(-Math.PI / 2), new THREE.MeshLambertMaterial({ map: poolTex(), emissive: 0x2a6a90, emissiveIntensity: 0.6 }));
  pool.position.y = 1.32; group.add(pool);
  statics(new THREE.Mesh(new THREE.CylinderGeometry(1.1, 1.4, 4.2, 18).translate(0, 3.3, 0), cream));
  statics(new THREE.Mesh(new THREE.CylinderGeometry(3.1, 1.3, 0.9, 30).translate(0, 5.6, 0), cream));
  statics(new THREE.Mesh(new THREE.TorusGeometry(3.05, 0.16, 6, 30).rotateX(Math.PI / 2).translate(0, 6.05, 0), goldM));
  statics(new THREE.Mesh(new THREE.TorusGeometry(7.1, 0.22, 6, 40).rotateX(Math.PI / 2).translate(0, 1.5, 0), goldM));
  const wtex = waterTex(); wtex.repeat.set(6, 1);
  const curtain = new THREE.Mesh(new THREE.CylinderGeometry(3.0, 3.5, 4.6, 30, 1, true).translate(0, 3.6, 0), new THREE.MeshBasicMaterial({ map: wtex, transparent: true, opacity: 0.6, depthWrite: false, side: THREE.DoubleSide }));
  group.add(curtain);
  const heart = new THREE.Mesh(new THREE.ExtrudeGeometry(heartShape(), { depth: 0.5, bevelEnabled: true, bevelThickness: 0.15, bevelSize: 0.12, bevelSegments: 2, curveSegments: 10 }).translate(0, 0, -0.25),
    lam(0xffcc30, 0x7a4a00, 0.8));
  heart.scale.setScalar(1.5); heart.position.set(0, 8.4, 0); group.add(heart);
  const hglow = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), color: 0xffd860, transparent: true, opacity: 0.55, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
  hglow.position.copy(heart.position); hglow.scale.setScalar(8); group.add(hglow);

  // ---------- «МАГАЗИН ДУШ» у дальней стены: чёрная стойка, висящие сердца ----------
  const sign = rainbowSignTex('МАГАЗИН ДУШ');
  const signH = 3.4, sm = new THREE.Mesh(new THREE.PlaneGeometry(signH * sign.userData.aspect, signH), new THREE.MeshBasicMaterial({ map: sign }));
  sm.position.set(-12, 12.5, -RZ + 0.05); statics(sm);
  statics(new THREE.Mesh(mergeGeos([box(16, 3.2, 3, -12, 1.6, -RZ + 2.5), box(16.4, 0.35, 3.4, -12, 3.3, -RZ + 2.5)]), lam(0x1a1a1a)));
  const strMat = new THREE.MeshBasicMaterial({ color: 0x40a0ff });
  SOULS.forEach((c, i) => {
    const x = -19 + i * 2, y = 7.5 + (i % 3) * 0.9;
    const hs = new THREE.Sprite(new THREE.SpriteMaterial({ map: canvasTex(32, 32, (g) => { g.imageSmoothingEnabled = false; drawHeart(g, 16, 16, 3.2, c); }), transparent: true }));
    hs.position.set(x, y, -RZ + 1.4); hs.scale.setScalar(1.3); group.add(hs);
    const st = new THREE.Mesh(new THREE.BoxGeometry(0.05, RH - y - 1, 0.05), strMat); st.position.set(x, (RH - 1 + y) / 2 + 0.5, -RZ + 1.4); statics(st);
  });

  // ---------- доска «ОЧЕРЕДЬ» на левой стене ----------
  const qc = document.createElement('canvas'); qc.width = 512; qc.height = 400;
  const qtex = new THREE.CanvasTexture(qc); qtex.colorSpace = THREE.SRGBColorSpace; qtex.anisotropy = 4;
  const qb = new THREE.Mesh(new THREE.PlaneGeometry(12.8, 10), new THREE.MeshBasicMaterial({ map: qtex }));
  qb.position.set(-RX + 0.06, 9.5, 2); qb.rotation.y = Math.PI / 2; statics(qb);
  const qglow = new THREE.Mesh(new THREE.PlaneGeometry(14.4, 11.6), new THREE.MeshBasicMaterial({ map: glowTex(), color: 0xffffff, transparent: true, opacity: 0.35, depthWrite: false, blending: THREE.AdditiveBlending }));
  qglow.position.set(-RX + 0.04, 9.5, 2); qglow.rotation.y = Math.PI / 2; statics(qglow);
  let qKey = '';
  function setQueue(rows) {
    const key = JSON.stringify(rows); if (key === qKey) return; qKey = key;
    const g = qc.getContext('2d');
    g.fillStyle = '#0a0a0a'; g.fillRect(0, 0, 512, 400);
    g.strokeStyle = '#ffffff'; g.lineWidth = 6; g.strokeRect(8, 8, 496, 384);
    drawPixText(g, 'ОЧЕРЕДЬ', 256, 26, 7, { fill: '#ffffff', align: 'center' });
    rows.slice(0, 5).forEach((r, i) => {
      const s = `${i + 1}. ${r.name.length > 14 ? r.name.slice(0, 13) + '…' : r.name}`;
      drawPixText(g, s, 34, 102 + i * 56, 4.5, { fill: r.me ? '#ffe040' : i === 0 ? '#3ff2ff' : '#ffffff' });
    });
    qtex.needsUpdate = true;
  }

  // ---------- ларёк с пирогами (правая стена) и полка зелий ----------
  const woodL = lam(0x9a6430), woodD = lam(0x6a4020);
  statics(new THREE.Mesh(mergeGeos([box(9, 3, 3.4, RX - 2.6, 1.5, -8), box(0.4, 7, 0.4, RX - 6.8, 3.5, -9.5), box(0.4, 7, 0.4, RX - 6.8, 3.5, -6.5)]), woodL));
  statics(new THREE.Mesh(mergeGeos([box(9.6, 0.3, 4, RX - 2.6, 3.15, -8)]), woodD));
  const awn = canvasTex(64, 16, (g) => { for (let i = 0; i < 8; i++) { g.fillStyle = i % 2 ? '#ffffff' : '#d42020'; g.fillRect(i * 8, 0, 8, 16); } });
  const aw = new THREE.Mesh(new THREE.BoxGeometry(4.2, 0.3, 10), new THREE.MeshLambertMaterial({ map: awn })); aw.position.set(RX - 4.6, 7.1, -8); aw.rotation.z = 0.35; statics(aw);
  const pieTop = lam(0xe0a050), pieCrust = lam(0xf0d090);
  for (let i = 0; i < 3; i++) {
    statics(new THREE.Mesh(new THREE.CylinderGeometry(0.8, 0.7, 0.35, 16).translate(RX - 4.5 + (i % 2) * 0.4, 3.5, -10.2 + i * 2.1), pieCrust));
    statics(new THREE.Mesh(new THREE.CylinderGeometry(0.72, 0.72, 0.08, 16).translate(RX - 4.5 + (i % 2) * 0.4, 3.7, -10.2 + i * 2.1), pieTop));
  }
  const pl = pixTexture('ПИРОГИ', 8, { fill: '#ffffff', outline: '#3a1a00', outlineW: 3 });
  const plm = new THREE.Mesh(new THREE.PlaneGeometry(2.0 * pl.userData.aspect, 2.0), new THREE.MeshBasicMaterial({ map: pl, transparent: true })); plm.position.set(RX - 0.08, 9.6, -8); plm.rotation.y = -Math.PI / 2; statics(plm);
  // полка зелий
  statics(new THREE.Mesh(mergeGeos([box(1.4, 0.3, 8, RX - 1, 4.6, 9), box(1.4, 0.3, 8, RX - 1, 7.2, 9)]), woodD));
  ['#3A4BFF', '#FF2020', '#20E040', '#FFE040'].forEach((c, i) => {
    for (const y of [4.75, 7.35]) {
      const m = lam(c, c, 0.55);
      const z = 6.2 + i * 1.9 + (y > 5 ? 0.4 : 0);
      statics(new THREE.Mesh(new THREE.SphereGeometry(0.42, 10, 8).translate(RX - 1, y + 0.45, z), m));
      statics(new THREE.Mesh(new THREE.CylinderGeometry(0.14, 0.14, 0.45, 8).translate(RX - 1, y + 1.0, z), lam(0xe8e8f0)));
    }
  });
  // кресла (белые) у правой стены
  const chair = lam(0xf4f2ec);
  for (const z of [17, 22]) statics(new THREE.Mesh(mergeGeos([box(3, 1.2, 3, RX - 3, 0.9, z), box(0.7, 2.6, 3, RX - 1.8, 1.9, z), box(3, 1.5, 0.6, RX - 3, 1.6, z - 1.5), box(3, 1.5, 0.6, RX - 3, 1.6, z + 1.5)]), chair));

  // ---------- игроки сервера (аватары) ----------
  let actors = [], me = null, zone = '';
  const input = { x: 0, z: 0, jump: false };
  const nameTex = new Map();
  function makeActor(p, i) {
    const av = buildAvatar3D(THREE, p.skin, { scale: 1 });
    av.barY = 6.1;
    const key = p.name;
    if (!nameTex.has(key)) nameTex.set(key, pixTexture(p.name, 6, { fill: '#D8DCE2', outline: '#1E1E1E', outlineW: 2 }));
    const t = nameTex.get(key);
    // имя над головой — у всех, кроме себя (как в роблоксе)
    if (!p.me) {
      const lbl = new THREE.Sprite(new THREE.SpriteMaterial({ map: t, transparent: true, depthWrite: false, fog: false }));
      lbl.scale.set(0.62 * t.userData.aspect, 0.62, 1); lbl.position.y = 6.2; lbl.renderOrder = 5; av.root.add(lbl);
    }
    const sh = new THREE.Mesh(new THREE.PlaneGeometry(3, 3).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ map: glowTex(), color: 0x000000, transparent: true, opacity: 0.35, depthWrite: false }));
    group.add(av.root); group.add(sh);
    const a0 = (i / 6) * Math.PI * 2 + 0.4, r = rand(14, 20);
    const a = { name: p.name, me: !!p.me, model: av, sh, pos: new THREE.Vector3(Math.sin(a0) * r, 0, Math.cos(a0) * r), tgt: new THREE.Vector3(), yaw: a0 + Math.PI, vy: 0, vx: 0, vz: 0, wait: rand(0.5, 3), animT: Math.random() * 9, moving: false, wave: 0, lobby: true };
    if (a.me) { a.pos.set(0, 0, 17); a.yaw = Math.PI; me = a; }
    return a;
  }
  function pickTarget(a) {
    for (let k = 0; k < 12; k++) {
      const x = rand(-RX + 4, RX - 6), z = rand(-RZ + 6, RZ - 4);
      const blocked = OBST.some(([x0, x1, z0, z1]) => x > x0 - 2 && x < x1 + 2 && z > z0 - 2 && z < z1 + 2);
      if (!blocked && Math.hypot(x, z) > FOUNT_R + 1 && Math.hypot(x - a.pos.x, z - a.pos.z) > 6) { a.tgt.set(x, 0, z); return; }
    }
    a.tgt.set(0, 0, 16);
  }
  function setActors(list) {
    for (const a of actors) { group.remove(a.model.root); group.remove(a.sh); a.model.root.traverse((o) => { if (o.isMesh) { o.geometry.dispose(); [].concat(o.material).forEach((m) => m.dispose()); } if (o.isSprite) o.material.dispose(); }); a.sh.geometry.dispose(); a.sh.material.dispose(); }
    me = null;
    actors = list.map(makeActor);
  }

  let t0 = 0;
  return {
    group,
    get actors() { return actors; },
    get me() { return me; },
    get zone() { return zone; },
    actorByName: (name) => actors.find((a) => a.name === name) || null,
    setActors, setQueue,
    // управление своим аватаром: (x, z) — направление в мире (длина ≤ 1)
    control(x, z) { input.x = x; input.z = z; },
    jump() { input.jump = true; },
    respawn() { if (me) { me.pos.set(0, 0, 17); me.vx = me.vz = me.vy = 0; me.yaw = Math.PI; } },
    wave(name) { const a = actors.find((x) => x.name === name); if (a) a.wave = 1.6; },
    setVisible(v) { group.visible = v; },
    update(t, dt) {
      t0 += dt;
      heart.rotation.y = t * 0.8; heart.position.y = 8.4 + Math.sin(t * 1.6) * 0.25; hglow.position.y = heart.position.y;
      wtex.offset.y = (wtex.offset.y + dt * 0.9) % 1;
      pool.material.map.offset.set(Math.sin(t * 0.3) * 0.02, Math.cos(t * 0.25) * 0.02);
      // брызги у основания струй
      if (fx && Math.random() < 0.7) { const a = Math.random() * Math.PI * 2; fx.spark(Math.cos(a) * 3.2, 1.5, Math.sin(a) * 3.2, Math.cos(a) * 1.2, 2.5 + Math.random() * 2, Math.sin(a) * 1.2, 0.5, 0.35, 0xbfefff, 9); }
      for (const a of actors) {
        a.animT += dt;
        if (a.me) { // свой аватар: джойстик, разгон ≈0.1 с, прыжок как в бою
          const k = 1 - Math.exp(-14 * dt);
          a.vx += (input.x * 16 - a.vx) * k; a.vz += (input.z * 16 - a.vz) * k;
          a.pos.x += a.vx * dt; a.pos.z += a.vz * dt;
          const sp = Math.hypot(a.vx, a.vz);
          a.moving = sp > 1.5;
          if (a.moving) a.yaw = lerpAngle(a.yaw, Math.atan2(a.vx, a.vz), 1 - Math.exp(-16 * dt));
          if (input.jump) { input.jump = false; if (a.pos.y <= 0.01) a.vy = JUMP_V; }
        } else if (a.moving) {
          const dx = a.tgt.x - a.pos.x, dz = a.tgt.z - a.pos.z, d = Math.hypot(dx, dz);
          a.walkT = (a.walkT || 0) + dt;
          if (d < 0.6 || a.walkT > 7) { a.moving = false; a.walkT = 0; a.wait = rand(1.2, 5); }
          else {
            let vx = (dx / d) * 16, vz = (dz / d) * 16;
            // обходим фонтан по касательной
            const r = Math.hypot(a.pos.x, a.pos.z);
            if (r < FOUNT_R + 1.5) { const nx = a.pos.x / r, nz = a.pos.z / r, dot = vx * nx + vz * nz; if (dot < 0) { vx -= dot * nx; vz -= dot * nz; vx += -nz * 6; vz += nx * 6; } }
            a.pos.x += vx * dt; a.pos.z += vz * dt;
            a.yaw = Math.atan2(vx, vz);
            if (a.pos.y <= 0 && Math.random() < dt * 0.25) a.vy = JUMP_V;
          }
        } else {
          a.wait -= dt;
          if (a.wait <= 0) { pickTarget(a); a.moving = true; }
          else if (a.pos.y <= 0 && Math.random() < dt * 0.12) a.vy = JUMP_V; // прыгают от скуки
        }
        // вертикаль (как в бою: гравитация роблокса)
        if (a.vy !== 0 || a.pos.y > 0) { a.vy -= GRAV * dt; a.pos.y += a.vy * dt; if (a.pos.y <= 0) { a.pos.y = 0; a.vy = 0; } }
        const fr = a.me ? ME_R : FOUNT_R, r = Math.hypot(a.pos.x, a.pos.z); if (r < fr) { a.pos.x *= fr / r; a.pos.z *= fr / r; }
        a.pos.x = Math.max(-RX + 1.6, Math.min(RX - 1.6, a.pos.x)); a.pos.z = Math.max(-RZ + 1.6, Math.min(RZ - 1.6, a.pos.z));
        pushOut(a.pos, 1.0);
        if (a.me) zone = a.pos.x > -21.5 && a.pos.x < -2.5 && a.pos.z < -21.6 ? 'shop' : '';
        const st = a.pos.y > 0.05 ? 'air' : a.moving ? 'run' : 'idle';
        animateAvatar(a.model, st, a.animT, 1);
        if (st === 'air') { const p = a.model.parts; p.armL.rotation.set(-2.8, 0, -0.15); p.armR.rotation.set(-2.8, 0, 0.15); p.legL.rotation.x = 0; p.legR.rotation.x = 0; }
        if (a.wave > 0) { a.wave -= dt; a.model.parts.armR.rotation.set(-2.6, 0, 0.3 + Math.sin(a.animT * 14) * 0.35); }
        a.model.root.position.copy(a.pos); a.model.root.rotation.y = a.yaw;
        a.sh.position.set(a.pos.x, 0.05, a.pos.z); a.sh.material.opacity = 0.35 / (1 + a.pos.y * 0.15);
      }
    },
  };
}
