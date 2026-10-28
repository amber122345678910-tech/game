// Блочные модели персонажей (R6-стиль), лица, 2D-портреты, Рика, храм.
import * as THREE from 'three';
import { Merger, FACE_UV, SKIN_UV } from './util.js';

export const LOOKS = {
  gojo: { shirt: '#1e2440', trim: '#323c66', pants: '#1e2440', shoe: '#131313', hair: '#f3f5ff', hair2: '#d6dcef', face: 'blind', color: '#5fb8ff' },
  sukuna: { shirt: '#efe8da', trim: '#2a2a2e', pants: '#ddd3c0', shoe: '#2a2a2e', hair: '#f29bb9', hair2: '#d97a9c', face: 'sukuna', color: '#ff4d6a' },
  yuji: { shirt: '#1d2335', trim: '#c9353c', pants: '#1d2335', shoe: '#e04a3f', hair: '#e3968a', hair2: '#4a2c26', face: 'yuji', color: '#ff8a3d' },
  yuta: { shirt: '#f2f2ee', trim: '#1b1b1b', pants: '#2a2b33', shoe: '#202020', hair: '#16161a', hair2: '#26262c', face: 'yuta', color: '#c77dff' },
};

// ---------- Лица ----------
export function drawFace(g, x, y, s, variant) {
  const R = (fx, fy, fw, fh, c) => { g.fillStyle = c; g.fillRect(x + fx * s, y + fy * s, fw * s, fh * s); };
  const line = (pts, c, w) => {
    g.strokeStyle = c; g.lineWidth = w * s; g.lineCap = 'round'; g.lineJoin = 'round';
    g.beginPath(); g.moveTo(x + pts[0] * s, y + pts[1] * s);
    for (let i = 2; i < pts.length; i += 2) g.lineTo(x + pts[i] * s, y + pts[i + 1] * s);
    g.stroke();
  };
  const D = '#1b1b1b';
  if (variant === 'blind') {
    // глаза закрыты повязкой — только ухмылка
    line([0.36, 0.71, 0.5, 0.74, 0.64, 0.67], '#3a2424', 0.04);
  } else if (variant === 'sukuna') {
    R(0.19, 0.36, 0.24, 0.11, '#fff'); R(0.57, 0.36, 0.24, 0.11, '#fff');
    R(0.27, 0.36, 0.1, 0.11, '#b3202e'); R(0.63, 0.36, 0.1, 0.11, '#b3202e');
    R(0.3, 0.38, 0.04, 0.07, D); R(0.66, 0.38, 0.04, 0.07, D);
    line([0.17, 0.31, 0.44, 0.36], D, 0.045); line([0.83, 0.31, 0.56, 0.36], D, 0.045);
    R(0.18, 0.35, 0.26, 0.025, D); R(0.56, 0.35, 0.26, 0.025, D);
    // вторая пара глаз
    R(0.12, 0.51, 0.14, 0.05, D); R(0.74, 0.51, 0.14, 0.05, D);
    R(0.16, 0.515, 0.06, 0.035, '#d0303f'); R(0.78, 0.515, 0.06, 0.035, '#d0303f');
    // метки
    R(0.06, 0.61, 0.24, 0.035, D); R(0.08, 0.67, 0.18, 0.035, D);
    R(0.7, 0.61, 0.24, 0.035, D); R(0.74, 0.67, 0.18, 0.035, D);
    R(0.43, 0.13, 0.14, 0.04, D); R(0.47, 0.17, 0.06, 0.08, D);
    R(0.31, 0.74, 0.38, 0.09, '#2a0c10'); R(0.33, 0.75, 0.34, 0.035, '#f4f0e6');
    for (let i = 0; i < 5; i++) R(0.355 + i * 0.065, 0.75, 0.012, 0.035, '#2a0c10');
  } else if (variant === 'yuji') {
    R(0.22, 0.36, 0.19, 0.13, '#fff'); R(0.59, 0.36, 0.19, 0.13, '#fff');
    R(0.27, 0.37, 0.11, 0.12, '#6b3a26'); R(0.62, 0.37, 0.11, 0.12, '#6b3a26');
    R(0.3, 0.4, 0.05, 0.06, D); R(0.65, 0.4, 0.05, 0.06, D);
    R(0.28, 0.375, 0.03, 0.03, '#fff'); R(0.63, 0.375, 0.03, 0.03, '#fff');
    line([0.2, 0.31, 0.42, 0.34], D, 0.05); line([0.8, 0.31, 0.58, 0.34], D, 0.05);
    R(0.25, 0.53, 0.12, 0.02, 'rgba(90,40,30,.7)');
    line([0.37, 0.69, 0.5, 0.75, 0.63, 0.69], '#3a1a1a', 0.045);
  } else if (variant === 'yuta') {
    R(0.21, 0.38, 0.2, 0.11, '#fff'); R(0.59, 0.38, 0.2, 0.11, '#fff');
    R(0.26, 0.38, 0.11, 0.11, '#151515'); R(0.63, 0.38, 0.11, 0.11, '#151515');
    R(0.28, 0.395, 0.03, 0.03, '#fff'); R(0.65, 0.395, 0.03, 0.03, '#fff');
    R(0.19, 0.36, 0.24, 0.03, D); R(0.57, 0.36, 0.24, 0.03, D);
    R(0.19, 0.51, 0.23, 0.04, 'rgba(80,45,100,.55)'); R(0.58, 0.51, 0.23, 0.04, 'rgba(80,45,100,.55)');
    line([0.42, 0.72, 0.58, 0.71], '#3a2424', 0.035);
  } else {
    R(0.28, 0.34, 0.1, 0.16, D); R(0.62, 0.34, 0.1, 0.16, D);
    line([0.35, 0.68, 0.5, 0.73, 0.65, 0.68], D, 0.05);
  }
}

const faceCache = new Map();
function faceTex(id, skin) {
  const key = id + skin;
  if (faceCache.has(key)) return faceCache.get(key);
  const c = document.createElement('canvas');
  c.width = 128; c.height = 160;
  const g = c.getContext('2d');
  g.fillStyle = skin; g.fillRect(0, 0, 128, 160);
  g.fillStyle = '#ffffff'; g.fillRect(0, 128, 64, 32);
  drawFace(g, 0, 0, 128, LOOKS[id].face);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.generateMipmaps = false; t.minFilter = THREE.LinearFilter;
  faceCache.set(key, t);
  return t;
}

// ---------- Геометрия частей ----------
function hair(m, id, L) {
  const H = L.hair, H2 = L.hair2;
  if (id === 'gojo') {
    m.box(0, 1.28, -0.02, 1.32, 0.32, 1.32, H);
    m.box(0.63, 0.98, -0.05, 0.12, 0.62, 1.2, H); m.box(-0.63, 0.98, -0.05, 0.12, 0.62, 1.2, H);
    m.box(0, 0.92, -0.63, 1.3, 0.85, 0.12, H);
    const sp = [[-0.38, -0.35, 0.9], [0.02, -0.38, 1.0], [0.4, -0.32, 0.85], [-0.42, 0.05, 1.05], [0, 0.02, 1.2], [0.42, 0.06, 1.0], [-0.3, 0.42, 0.75], [0.08, 0.45, 0.85], [0.42, 0.4, 0.7]];
    for (const [x, z, h] of sp) m.box(x, 1.38 + h / 2, z, 0.4, h, 0.4, x * z > 0 ? H2 : H, { rx: z * 0.75, rz: -x * 0.75 });
    m.box(-0.32, 1.02, 0.61, 0.3, 0.48, 0.14, H); m.box(0.08, 1.05, 0.63, 0.34, 0.42, 0.14, H2); m.box(0.4, 1.0, 0.61, 0.26, 0.5, 0.14, H);
    // повязка
    m.box(0, 0.72, 0, 1.27, 0.32, 1.27, '#101116');
    m.box(0, 0.74, -0.7, 0.3, 0.26, 0.16, '#101116');
    m.box(0.12, 0.52, -0.72, 0.16, 0.42, 0.06, '#101116', { rz: 0.3 });
  } else if (id === 'sukuna') {
    m.box(0, 1.27, -0.04, 1.3, 0.3, 1.3, H);
    m.box(0, 0.95, -0.62, 1.28, 0.75, 0.14, H);
    m.box(0.63, 1.05, -0.1, 0.1, 0.42, 1.0, H); m.box(-0.63, 1.05, -0.1, 0.1, 0.42, 1.0, H);
    for (const x of [-0.4, 0, 0.4]) for (const z of [0.25, -0.15, -0.5]) {
      m.box(x, 1.5, z - 0.05, 0.36, 0.72, 0.36, (x + z) > 0 ? H : H2, { rx: -0.65 - (z < 0 ? 0.35 : 0), rz: -x * 0.6 });
    }
    m.box(-0.25, 1.46, 0.48, 0.3, 0.42, 0.3, H, { rx: 0.25 }); m.box(0.25, 1.46, 0.48, 0.3, 0.42, 0.3, H, { rx: 0.25 });
  } else if (id === 'yuji') {
    m.box(0, 1.02, -0.03, 1.26, 0.55, 1.26, H2);
    m.box(0, 1.32, -0.05, 1.18, 0.32, 1.12, H);
    m.box(-0.3, 1.52, -0.2, 0.36, 0.5, 0.36, H, { rx: -0.55, rz: 0.2 });
    m.box(0.28, 1.52, -0.25, 0.36, 0.5, 0.36, H, { rx: -0.6, rz: -0.2 });
    m.box(0, 1.56, 0.08, 0.36, 0.5, 0.36, H, { rx: -0.3 });
    m.box(-0.22, 1.35, 0.6, 0.28, 0.42, 0.22, H, { rx: 0.7 }); m.box(0.22, 1.35, 0.6, 0.28, 0.42, 0.22, H, { rx: 0.7 });
  } else if (id === 'yuta') {
    m.box(0, 1.28, -0.02, 1.32, 0.32, 1.32, H);
    m.box(0, 0.8, -0.63, 1.32, 1.1, 0.16, H);
    m.box(0.64, 0.88, -0.05, 0.12, 0.85, 1.18, H); m.box(-0.64, 0.88, -0.05, 0.12, 0.85, 1.18, H);
    const bangs = [[-0.45, 0.5, 0.15], [-0.2, 0.6, -0.1], [0.08, 0.52, 0.12], [0.34, 0.62, -0.15], [0.5, 0.45, 0.1]];
    for (const [x, h, rz] of bangs) m.box(x, 1.2 - h / 2 + 0.1, 0.63, 0.27, h, 0.12, H, { rz });
    m.box(-0.3, 1.5, 0.1, 0.4, 0.35, 0.5, H2, { rz: 0.4 }); m.box(0.25, 1.5, -0.2, 0.4, 0.35, 0.5, H, { rz: -0.35 });
    m.box(0, 1.48, -0.45, 0.5, 0.3, 0.4, H2, { rx: -0.4 });
  }
}

const geoCache = new Map();
function getGeos(id, skin) {
  const key = id + skin;
  if (geoCache.has(key)) return geoCache.get(key);
  const L = LOOKS[id];
  // голова
  const hm = new Merger(true);
  hm.box(0, 0.6, 0, 1.2, 1.2, 1.2, '#ffffff', { uvFront: FACE_UV, uvAll: SKIN_UV });
  hair(hm, id, L);
  // торс
  const t = new Merger();
  t.box(0, 1, 0, 2, 2, 1, L.shirt);
  if (id === 'gojo') {
    t.box(0, 2.12, 0, 1.5, 0.45, 1.1, L.shirt);
    t.box(0, 1.92, 0.56, 0.24, 0.24, 0.08, '#c9b26a');
    t.box(0, 1.0, 0.505, 0.07, 1.75, 0.02, L.trim);
    t.box(0, 0.12, 0, 2.02, 0.22, 1.02, '#14182b');
  } else if (id === 'sukuna') {
    t.box(0, 0.38, 0, 2.04, 0.45, 1.04, '#2a2a2e');
    t.box(-0.3, 1.45, 0.51, 0.16, 1.15, 0.03, '#cfc4ad', { rz: -0.42 });
    t.box(0.3, 1.45, 0.51, 0.16, 1.15, 0.03, '#cfc4ad', { rz: 0.42 });
    t.box(0, 2.08, -0.05, 1.5, 0.3, 1.1, '#2a2a2e');
  } else if (id === 'yuji') {
    t.box(0, 2.08, -0.48, 1.7, 0.7, 0.55, L.trim);
    t.box(0.72, 2.02, -0.08, 0.26, 0.42, 0.9, L.trim); t.box(-0.72, 2.02, -0.08, 0.26, 0.42, 0.9, L.trim);
    t.box(0, 1.05, 0.505, 0.08, 1.75, 0.02, '#9aa3b5');
    t.box(0, 0.5, 0.51, 1.3, 0.5, 0.04, '#151a29');
  } else if (id === 'yuta') {
    t.box(0, 2.12, 0, 1.5, 0.42, 1.1, L.shirt);
    for (const y of [1.72, 1.32, 0.92, 0.52]) t.box(0, y, 0.52, 0.15, 0.15, 0.06, '#1b1b1b');
    t.box(0, 0.12, 0, 2.02, 0.22, 1.02, '#dcdcd6');
    t.box(1.12, 0.55, -0.15, 0.22, 0.32, 3.0, '#1b1b1b', { rx: 0.55 });
  }
  // руки
  const a = new Merger();
  if (id === 'sukuna') {
    a.box(0, -0.12, 0, 1.18, 1.26, 1.18, L.shirt);
    a.box(0, -1.1, 0, 0.98, 0.8, 0.98, skin);
    a.box(0, -0.9, 0, 1.0, 0.07, 1.0, '#1b1b1b'); a.box(0, -1.08, 0, 1.0, 0.07, 1.0, '#1b1b1b');
  } else {
    a.box(0, -0.1, 0, 1, 1.2, 1, L.shirt);
    a.box(0, -0.66, 0, 1.04, 0.14, 1.04, id === 'yuji' ? L.trim : id === 'yuta' ? '#dcdcd6' : L.trim);
    a.box(0, -1.1, 0, 0.98, 0.8, 0.98, skin);
  }
  // ноги
  const l = new Merger();
  l.box(0, -0.8, 0, 1, 1.6, 1, L.pants);
  l.box(0, -1.8, 0.06, 1.02, 0.4, 1.12, L.shoe);
  if (id === 'yuji') l.box(0, -1.94, 0.06, 1.04, 0.14, 1.14, '#f0f0f0');
  const out = { head: hm.build(), torso: t.build(), arm: a.build(), leg: l.build(), katana: null };
  if (id === 'yuta') {
    const k = new Merger();
    k.box(0, 0, 0.25, 0.26, 0.3, 1.3, '#1b1b1b');
    k.box(0, 0, 0.0, 0.28, 0.32, 0.12, '#e8e0c8'); k.box(0, 0, 0.5, 0.28, 0.32, 0.12, '#e8e0c8');
    k.box(0, 0, 0.95, 0.62, 0.62, 0.12, '#c9a43a');
    k.box(0, 0.02, 3.4, 0.08, 0.3, 4.8, '#e9eef4');
    k.box(0, 0.13, 3.4, 0.1, 0.08, 4.8, '#9aa4ae');
    out.katana = k.build();
  }
  geoCache.set(key, out);
  return out;
}

// Модель бойца: root на земле, смотрит в +Z. Правая рука/нога — на -X.
export function buildModel(id, skin) {
  const geos = getGeos(id, skin);
  const bodyMat = new THREE.MeshLambertMaterial({ vertexColors: true });
  const headMat = new THREE.MeshLambertMaterial({ vertexColors: true, map: faceTex(id, skin) });
  const root = new THREE.Group();
  const spin = new THREE.Group(); spin.position.y = 2.6; root.add(spin);
  const pelvis = new THREE.Group(); pelvis.position.y = -0.6; spin.add(pelvis);
  const chest = new THREE.Group(); pelvis.add(chest);
  const meshes = [];
  const mk = (geo, mat, parent) => { const me = new THREE.Mesh(geo, mat); me.castShadow = true; parent.add(me); meshes.push(me); return me; };
  mk(geos.torso, bodyMat, chest);
  const neck = new THREE.Group(); neck.position.y = 2; chest.add(neck);
  mk(geos.head, headMat, neck);
  const armL = new THREE.Group(); armL.position.set(1.5, 1.5, 0); chest.add(armL); mk(geos.arm, bodyMat, armL);
  const armR = new THREE.Group(); armR.position.set(-1.5, 1.5, 0); chest.add(armR); mk(geos.arm, bodyMat, armR);
  const legL = new THREE.Group(); legL.position.set(0.5, 0, 0); pelvis.add(legL); mk(geos.leg, bodyMat, legL);
  const legR = new THREE.Group(); legR.position.set(-0.5, 0, 0); pelvis.add(legR); mk(geos.leg, bodyMat, legR);
  const handL = new THREE.Object3D(); handL.position.y = -1.5; armL.add(handL);
  const handR = new THREE.Object3D(); handR.position.y = -1.5; armR.add(handR);
  const footR = new THREE.Object3D(); footR.position.y = -2; legR.add(footR);
  let katana = null;
  if (geos.katana) {
    katana = new THREE.Group(); katana.position.y = -1.42; armR.add(katana);
    mk(geos.katana, bodyMat, katana);
  }
  return { root, spin, pelvis, chest, neck, armL, armR, legL, legR, handL, handR, footR, katana, bodyMat, headMat, meshes };
}

// ---------- Рика ----------
let rikaGeo = null, rikaArmGeo = null, rikaBigArmGeo = null;
function rikaGeos() {
  if (rikaGeo) return;
  const DK = '#26222c', DK2 = '#1a171f', PALE = '#d9d2de', BONE = '#efe9df';
  const b = new Merger();
  b.box(0, 3.0, 0, 3.6, 2.6, 3.0, DK2); b.box(0, 1.2, -0.3, 2.4, 1.8, 2.0, DK2); b.box(0, 0.1, -0.6, 1.2, 1.2, 1.2, DK2);
  b.box(0, 6.2, 0.2, 5.4, 4.6, 3.8, DK, { rx: 0.25 });
  b.box(0, 7.9, 0.4, 6.6, 1.4, 3.4, DK, { rx: 0.2 });
  // голова
  b.box(0, 10.0, 1.4, 4.6, 3.8, 4.0, DK);
  b.box(0, 9.3, 3.42, 3.6, 1.5, 0.2, '#4a0b14');
  for (let i = 0; i < 6; i++) { b.box(-1.5 + i * 0.6, 9.9, 3.5, 0.34, 0.45, 0.2, BONE); b.box(-1.5 + i * 0.6, 8.7, 3.5, 0.34, 0.45, 0.2, BONE); }
  b.box(-1.15, 11.0, 3.42, 0.95, 0.6, 0.2, '#ffffff'); b.box(1.15, 11.0, 3.42, 0.95, 0.6, 0.2, '#ffffff');
  b.box(-1.15, 11.0, 3.5, 0.35, 0.4, 0.15, '#111'); b.box(1.15, 11.0, 3.5, 0.35, 0.4, 0.15, '#111');
  b.box(0, 12.2, 1.2, 5.0, 0.8, 4.3, '#0e0d10');
  for (let i = 0; i < 6; i++) b.box(-2.0 + i * 0.8, 9.6, -0.8, 0.6, 4.6, 0.6, '#0e0d10', { rx: -0.2 });
  b.box(0, 11.6, 3.5, 4.6, 0.25, 0.1, PALE);
  rikaGeo = b.build();
  const a = new Merger();
  a.box(0, -2.0, 0, 1.7, 4.4, 1.7, DK);
  a.box(0, -5.6, 0.2, 1.5, 3.6, 1.5, DK);
  a.box(0, -8.0, 0.3, 2.2, 1.6, 2.2, PALE);
  for (const x of [-0.7, 0, 0.7]) a.box(x, -9.3, 0.6, 0.35, 1.4, 0.35, BONE, { rx: 0.35 });
  rikaArmGeo = a.build();
  const g = new Merger();
  g.box(0, 6, 0, 2.8, 12, 2.8, DK);
  g.box(0, -0.3, 0.3, 4.2, 2.6, 4.2, PALE);
  for (const x of [-1.4, 0, 1.4]) g.box(x, -2.4, 0.7, 0.6, 2.4, 0.6, BONE, { rx: 0.3 });
  g.box(0, 12.5, 0, 3.4, 1.6, 3.4, DK2);
  rikaBigArmGeo = g.build();
}

export function buildRika() {
  rikaGeos();
  const mat = new THREE.MeshLambertMaterial({ vertexColors: true, emissive: 0x150820 });
  const root = new THREE.Group();
  const body = new THREE.Group(); root.add(body);
  const me = new THREE.Mesh(rikaGeo, mat); me.castShadow = true; body.add(me);
  const armL = new THREE.Group(); armL.position.set(3.4, 7.4, 0.5); body.add(armL);
  const armR = new THREE.Group(); armR.position.set(-3.4, 7.4, 0.5); body.add(armR);
  const al = new THREE.Mesh(rikaArmGeo, mat); al.castShadow = true; armL.add(al);
  const ar = new THREE.Mesh(rikaArmGeo, mat); ar.castShadow = true; armR.add(ar);
  return { root, body, armL, armR, mat };
}
export function buildRikaArm() {
  rikaGeos();
  const mat = new THREE.MeshLambertMaterial({ vertexColors: true, emissive: 0x150820 });
  const root = new THREE.Group();
  const me = new THREE.Mesh(rikaBigArmGeo, mat); me.castShadow = true; root.add(me);
  return { root, mat };
}

// ---------- Храм (Malevolent Shrine) ----------
let shrineGeo = null;
export function buildShrine() {
  if (!shrineGeo) {
    const m = new Merger();
    const ST = '#2b2524', RD = '#6a1818', RF = '#241616', BN = '#e8dcc8';
    m.box(0, 0.75, 0, 15, 1.5, 11, ST);
    m.box(0, 0.3, 6.2, 8, 0.6, 2, ST);
    for (const x of [-5.8, 5.8]) for (const z of [-3.8, 3.8]) m.box(x, 6, z, 1.3, 9, 1.3, RD);
    m.box(0, 10.8, 0, 17, 1.2, 12.5, RF);
    m.box(0, 12.1, 0, 13, 1.2, 9.5, RF);
    m.box(0, 13.2, 0, 8, 1.0, 6, RF);
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) m.box(sx * 8.6, 11.6, sz * 6.2, 1.2, 0.6, 1.2, RD, { rz: sx * 0.6, rx: -sz * 0.4 });
    m.box(-3.2, 15.6, 0, 1.1, 4.4, 1.1, BN, { rz: 0.45 }); m.box(3.2, 15.6, 0, 1.1, 4.4, 1.1, BN, { rz: -0.45 });
    m.box(-4.4, 17.6, 0, 0.8, 1.8, 0.8, BN, { rz: 1.0 }); m.box(4.4, 17.6, 0, 0.8, 1.8, 0.8, BN, { rz: -1.0 });
    // пасть
    m.box(0, 5.6, 3.9, 7.4, 6.4, 0.6, '#3a0d0d');
    m.box(0, 5.6, 4.0, 6.0, 5.0, 0.6, '#0c0303');
    for (let i = 0; i < 7; i++) { m.box(-2.6 + i * 0.86, 7.8, 4.3, 0.5, 0.9, 0.3, BN); m.box(-2.6 + i * 0.86, 3.4, 4.3, 0.5, 0.9, 0.3, BN); }
    // черепа
    for (let i = 0; i < 16; i++) {
      const a = (i / 16) * Math.PI * 2, R = 8.5 + (i % 3);
      m.box(Math.cos(a) * R, 0.5, Math.sin(a) * R * 0.8, 1, 1, 1, BN, { ry: a });
      if (i % 2) m.box(Math.cos(a) * R, 1.4, Math.sin(a) * R * 0.8, 0.8, 0.8, 0.8, BN, { ry: a * 2 });
    }
    shrineGeo = m.build();
  }
  const mat = new THREE.MeshLambertMaterial({ vertexColors: true, emissive: 0x2a0303 });
  const me = new THREE.Mesh(shrineGeo, mat);
  me.castShadow = true;
  const root = new THREE.Group(); root.add(me);
  return { root, mat };
}

// ---------- 2D-портрет для карточек ----------
export function drawPortrait(canvas, id, skin) {
  const g = canvas.getContext('2d');
  const W = canvas.width, H = canvas.height;
  const L = LOOKS[id];
  g.clearRect(0, 0, W, H);
  const bg = g.createRadialGradient(W / 2, H * 0.45, 4, W / 2, H * 0.5, W * 0.75);
  bg.addColorStop(0, L.color); bg.addColorStop(1, '#0b0b14');
  g.fillStyle = bg; g.fillRect(0, 0, W, H);
  // лучи
  g.save(); g.globalAlpha = 0.12; g.fillStyle = '#fff'; g.translate(W / 2, H * 0.45);
  for (let i = 0; i < 10; i++) { g.rotate(Math.PI / 5); g.beginPath(); g.moveTo(0, 0); g.lineTo(W, -14); g.lineTo(W, 14); g.fill(); }
  g.restore();
  const s = H * 0.42, x = W / 2 - s / 2, y = H * 0.24;
  const R = (fx, fy, fw, fh, c) => { g.fillStyle = c; g.fillRect(x + fx * s, y + fy * s, fw * s, fh * s); };
  // тело
  R(-0.55, 1.08, 2.1, 1.2, L.shirt);
  R(-0.55, 1.08, 0.12, 1.2, 'rgba(0,0,0,.18)');
  if (id === 'gojo') { R(0.18, 0.98, 0.64, 0.22, L.shirt); R(0.44, 1.08, 0.12, 0.12, '#c9b26a'); R(0.48, 1.22, 0.04, 1, L.trim); }
  if (id === 'sukuna') {
    g.fillStyle = '#cfc4ad'; g.beginPath(); g.moveTo(x + 0.2 * s, y + 1.08 * s); g.lineTo(x + 0.5 * s, y + 1.75 * s); g.lineTo(x + 0.8 * s, y + 1.08 * s); g.lineTo(x + 0.7 * s, y + 1.08 * s); g.lineTo(x + 0.5 * s, y + 1.55 * s); g.lineTo(x + 0.3 * s, y + 1.08 * s); g.fill();
    R(0.15, 1.0, 0.7, 0.12, '#2a2a2e');
  }
  if (id === 'yuji') { R(-0.1, 0.95, 1.2, 0.3, L.trim); R(0.48, 1.25, 0.05, 1, '#9aa3b5'); }
  if (id === 'yuta') {
    R(0.18, 0.98, 0.64, 0.2, L.shirt); for (let i = 0; i < 3; i++) R(0.46, 1.28 + i * 0.25, 0.08, 0.08, '#1b1b1b');
    g.save(); g.translate(x + 1.25 * s, y + 0.2 * s); g.rotate(0.5);
    g.fillStyle = '#1b1b1b'; g.fillRect(-0.05 * s, 0, 0.1 * s, 0.7 * s); g.fillStyle = '#c9a43a'; g.fillRect(-0.12 * s, 0.68 * s, 0.24 * s, 0.06 * s);
    g.restore();
  }
  // голова
  R(0, 0, 1, 1, skin); R(0.88, 0, 0.12, 1, 'rgba(0,0,0,.12)');
  drawFace(g, x, y, s, L.face);
  // волосы
  g.fillStyle = L.hair;
  const poly = (pts, c) => { g.fillStyle = c; g.beginPath(); g.moveTo(x + pts[0] * s, y + pts[1] * s); for (let i = 2; i < pts.length; i += 2) g.lineTo(x + pts[i] * s, y + pts[i + 1] * s); g.closePath(); g.fill(); };
  if (id === 'gojo') {
    poly([-0.1, 0.3, -0.25, -0.15, 0.0, 0.0, 0.05, -0.55, 0.25, -0.05, 0.38, -0.7, 0.52, -0.08, 0.66, -0.62, 0.78, -0.05, 1.05, -0.45, 1.0, 0.05, 1.25, -0.1, 1.1, 0.3], L.hair);
    poly([0.0, 0.12, 1.0, 0.12, 1.0, 0.36, 0.84, 0.3, 0.7, 0.42, 0.55, 0.3, 0.38, 0.44, 0.22, 0.3, 0.0, 0.38], L.hair);
    R(-0.04, 0.38, 1.08, 0.24, '#101116');
  } else if (id === 'sukuna') {
    poly([-0.08, 0.35, -0.12, 0.0, -0.3, -0.15, 0.05, -0.1, 0.1, -0.42, 0.3, -0.12, 0.5, -0.48, 0.65, -0.12, 0.92, -0.4, 0.95, -0.05, 1.3, -0.12, 1.08, 0.1, 1.08, 0.35, 0.95, 0.18, 0.05, 0.18], L.hair);
  } else if (id === 'yuji') {
    poly([-0.06, 0.45, -0.06, 0.05, 1.06, 0.05, 1.06, 0.45, 0.95, 0.2, 0.05, 0.2], L.hair2);
    poly([0.0, 0.12, 0.05, -0.15, 0.22, -0.32, 0.38, -0.12, 0.55, -0.35, 0.72, -0.12, 0.95, -0.25, 1.0, 0.12, 0.7, 0.2, 0.62, 0.32, 0.5, 0.18, 0.4, 0.32, 0.32, 0.18], L.hair);
  } else if (id === 'yuta') {
    poly([-0.1, 0.75, -0.12, 0.0, 0.1, -0.2, 0.4, -0.25, 0.7, -0.18, 1.0, -0.12, 1.12, 0.05, 1.1, 0.75, 1.0, 0.75, 0.98, 0.3, 0.88, 0.42, 0.78, 0.3, 0.62, 0.44, 0.5, 0.3, 0.35, 0.42, 0.22, 0.3, 0.1, 0.42, 0.02, 0.3, 0.02, 0.75], L.hair);
  }
}
