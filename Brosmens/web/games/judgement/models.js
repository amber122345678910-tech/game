// Модели: люди (блочный аватар + оружие + аура зелья), Судья (скелет в синей толстовке), черепа-бластеры, кости.
import * as THREE from 'three';
import { buildAvatar3D } from '../../shared/avatar.js';
import { canvasTex, glowTex } from './fx.js';

const lam = (c, e = 0x000000, ei = 1) => new THREE.MeshLambertMaterial({ color: c, emissive: e, emissiveIntensity: ei });
const boxMesh = (w, h, d, m, x = 0, y = 0, z = 0) => { const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m); b.position.set(x, y, z); return b; };

let shadowTex = null;
function blobShadow(r) {
  shadowTex ||= canvasTex(64, 64, (g) => {
    const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
    gr.addColorStop(0, 'rgba(0,0,10,.75)'); gr.addColorStop(0.6, 'rgba(0,0,10,.35)'); gr.addColorStop(1, 'rgba(0,0,10,0)');
    g.fillStyle = gr; g.fillRect(0, 0, 64, 64);
  });
  const m = new THREE.Mesh(new THREE.PlaneGeometry(r * 2, r * 2), new THREE.MeshBasicMaterial({ map: shadowTex, transparent: true, depthWrite: false }));
  m.rotation.x = -Math.PI / 2; m.renderOrder = 1;
  return m;
}

function collectMats(root) {
  const mats = [];
  root.traverse((o) => {
    if (!o.isMesh || !o.material) return;
    for (const m of [].concat(o.material)) if (m.emissive && !mats.includes(m)) { m.userData.e0 = m.emissive.getHex(); mats.push(m); }
  });
  return mats;
}

// Оружие в правой руке (pivot armR: кисть около y=-1.6; «вперёд от кулака» = -Y)
function addWeapon(av, roleId) {
  const armR = av.parts.armR, armL = av.parts.armL;
  const g = new THREE.Group(); g.position.set(0, -1.55, 0); armR.add(g);
  if (roleId === 'det') {
    g.add(boxMesh(0.3, 0.55, 0.3, lam(0x5a2a1a), 0, -0.2, 0));
    g.add(boxMesh(0.55, 0.12, 0.42, lam(0xb8b8c8), 0, -0.48, 0));
    const blade = boxMesh(0.12, 1.5, 0.36, lam(0xe8eef8, 0x553333, 0.4), 0, -1.25, 0); g.add(blade);
    av.tip = new THREE.Object3D(); av.tip.position.set(0, -2, 0); g.add(av.tip);
  } else if (roleId === 'pat') {
    // игрушечный нож: пластиковая рукоять и закруглённое лезвие
    g.add(boxMesh(0.28, 0.55, 0.3, lam(0xc98a4a), 0, -0.2, 0));
    g.add(boxMesh(0.45, 0.1, 0.38, lam(0x9a6430), 0, -0.5, 0));
    g.add(boxMesh(0.12, 1.05, 0.32, lam(0xdfe3ea, 0x223040, 0.3), 0, -1.05, 0));
    g.add(boxMesh(0.12, 0.22, 0.22, lam(0xdfe3ea, 0x223040, 0.3), 0, -1.63, -0.03));
    av.tip = new THREE.Object3D(); av.tip.position.set(0, -1.7, 0); g.add(av.tip);
  } else if (roleId === 'brv') {
    const gm = lam(0xff8a1a, 0x5a2a00, 0.5), cuff = lam(0xfff1d6);
    for (const arm of [armR, armL]) {
      arm.add(boxMesh(1.25, 0.95, 1.25, gm, 0, -1.3, 0));
      arm.add(boxMesh(1.18, 0.22, 1.18, cuff, 0, -0.78, 0));
    }
    av.tip = new THREE.Object3D(); av.tip.position.set(0, -0.3, 0); g.add(av.tip);
  } else if (roleId === 'jus') {
    const dark = lam(0x2a2a30), gold = lam(0xffd23a, 0x5a4a00, 0.5);
    g.add(boxMesh(0.32, 0.3, 0.7, dark, 0, -0.1, -0.15)); // рукоять (смотрит назад вдоль руки)
    g.add(boxMesh(0.34, 1.25, 0.42, dark, 0, -0.65, 0.12)); // ствол-корпус
    g.add(boxMesh(0.2, 0.3, 0.2, gold, 0, -1.35, 0.15));
    g.add(boxMesh(0.12, 0.22, 0.12, gold, 0, -0.4, 0.36));
    // шляпа ковбоя
    const hat = lam(0x6b4a2a), band = lam(0xffd23a);
    av.parts.head.add(boxMesh(2.1, 0.12, 2.1, hat, 0, 0.72, 0));
    av.parts.head.add(boxMesh(1.25, 0.55, 1.25, hat, 0, 1.0, 0));
    av.parts.head.add(boxMesh(1.28, 0.14, 1.28, band, 0, 0.82, 0));
    av.tip = new THREE.Object3D(); av.tip.position.set(0, -1.55, 0.15); g.add(av.tip);
  }
  av.weapon = g;
}

// Душа-сердце, полоска HP и имя над головой — DOM-«билборды» в hud.js (постоянный экранный размер).
export function buildHuman(skin, role) {
  const av = buildAvatar3D(THREE, skin, { scale: 1 });
  addWeapon(av, role.id);
  av.barY = 6.1; // высота якоря полоски над ногами
  const sh = blobShadow(1.6); av.shadow = sh;
  // аура активного зелья (цвет задаётся при питье)
  const aura = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), color: 0xffffff, transparent: true, opacity: 0.35, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
  aura.scale.set(5.2, 7.2, 1); aura.position.y = 2.7; aura.visible = false; aura.renderOrder = 2; av.root.add(aura); av.aura = aura;
  av.mats = collectMats(av.root);
  return av;
}

// ---------- Судья ----------
// Оригинальный «скелет в толстовке» по силуэту UJD: большой круглый череп (≈40% роста) с отдельной «маской» лица
// (глазницы, зрачки-точки, нос-треугольник, широкая ухмылка), пухлая синяя толстовка нараспашку с белой футболкой,
// серый меховой обод капюшона вокруг шеи (виден и сзади), белые шнурки и манжеты, чёрные шорты с белой полосой,
// розовые пушистые тапки. Рост ≈6 ед. Глаз: голубое свечение с жёлтой серединкой.
function judgeFaceTex() {
  return canvasTex(256, 256, (g) => {
    g.clearRect(0, 0, 256, 256);
    // лёгкая тень под глазницами и у скул
    const sh = (x, y, r) => { const gr = g.createRadialGradient(x, y, r * 0.4, x, y, r); gr.addColorStop(0, 'rgba(60,60,80,.16)'); gr.addColorStop(1, 'rgba(60,60,80,0)'); g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2); };
    sh(84, 98, 52); sh(172, 98, 52);
    // глазницы
    g.fillStyle = '#0b0b12';
    g.beginPath(); g.ellipse(84, 94, 29, 30, 0, 0, 7); g.fill();
    g.beginPath(); g.ellipse(172, 94, 29, 30, 0, 0, 7); g.fill();
    // нос
    g.beginPath(); g.moveTo(128, 128); g.lineTo(117, 150); g.lineTo(139, 150); g.closePath(); g.fill();
    // широкая ухмылка: верхняя и нижняя линии + прямоугольные зубы
    const up = (t) => [40 + t * 176, 164 + Math.sin(t * Math.PI) * 26], lo = (t) => [48 + t * 160, 178 + Math.sin(t * Math.PI) * 30];
    g.strokeStyle = '#121218'; g.lineCap = 'round'; g.lineJoin = 'round';
    g.lineWidth = 6;
    g.beginPath(); for (let i = 0; i <= 24; i++) { const [x, y] = up(i / 24); i ? g.lineTo(x, y) : g.moveTo(x, y); } g.stroke();
    g.lineWidth = 5;
    g.beginPath(); for (let i = 0; i <= 24; i++) { const [x, y] = lo(i / 24); i ? g.lineTo(x, y) : g.moveTo(x, y); } g.stroke();
    g.lineWidth = 4;
    for (let i = 1; i < 12; i++) { const t = i / 12, [x1, y1] = up(t), [x2, y2] = lo((x1 - 48) / 160); g.beginPath(); g.moveTo(x1, y1); g.lineTo(x2, y2); g.stroke(); }
    // уголки улыбки
    g.lineWidth = 5;
    g.beginPath(); g.moveTo(40, 164); g.lineTo(32, 156); g.moveTo(216, 164); g.lineTo(224, 156); g.stroke();
  });
}
// Серп разреза: тонкая светящаяся красная дуга, утончается к концам
function slashCrescentTex() {
  return canvasTex(256, 72, (g) => {
    const W = 256, H = 72;
    g.clearRect(0, 0, W, H);
    const arc = (w, col, blur) => {
      g.save(); g.shadowColor = '#ff0000'; g.shadowBlur = blur;
      g.beginPath();
      for (let i = 0; i <= 40; i++) { const t = i / 40, x = 10 + t * (W - 20), y = H * 0.72 - Math.sin(t * Math.PI) * H * 0.42; const th = w * Math.sin(t * Math.PI); i ? g.lineTo(x, y - th) : g.moveTo(x, y - th); }
      for (let i = 40; i >= 0; i--) { const t = i / 40, x = 10 + t * (W - 20), y = H * 0.72 - Math.sin(t * Math.PI) * H * 0.42; const th = w * Math.sin(t * Math.PI); g.lineTo(x, y + th * 0.6); }
      g.closePath(); g.fillStyle = col; g.fill(); g.restore();
    };
    arc(9, '#ff0000', 14);
    arc(4, '#ff5a5a', 4);
    arc(1.6, '#ffd0d0', 0);
  });
}

// точка на сфере радиуса r по «координатам текстуры» маски лица
const FACE = { phi0: Math.PI / 2 - 1.05, phiL: 2.1, th0: 0.62, thL: 1.62 };
function facePoint(u, v, r, out) {
  const phi = FACE.phi0 + u * FACE.phiL, th = FACE.th0 + v * FACE.thL;
  return out.set(-r * Math.cos(phi) * Math.sin(th), r * Math.cos(th), r * Math.sin(phi) * Math.sin(th));
}
// чуть «мохнатый» тор: вершины слегка смещены случайно (мех капюшона)
function furRing(R, tube) {
  const g = new THREE.TorusGeometry(R, tube, 9, 22);
  const p = g.attributes.position;
  const seen = new Map();
  for (let i = 0; i < p.count; i++) {
    const key = p.getX(i).toFixed(3) + p.getY(i).toFixed(3) + p.getZ(i).toFixed(3);
    let k = seen.get(key); if (k === undefined) { k = 1 + (Math.random() - 0.5) * 0.16; seen.set(key, k); }
    const x = p.getX(i), y = p.getY(i), z = p.getZ(i), a = Math.atan2(y, x), cx = Math.cos(a) * R, cy = Math.sin(a) * R;
    p.setXYZ(i, cx + (x - cx) * k, cy + (y - cy) * k, z * k);
  }
  g.computeVertexNormals();
  g.rotateX(Math.PI / 2);
  return g;
}

export function buildJudge() {
  const root = new THREE.Group(); const body = new THREE.Group(); root.add(body);
  const blue = lam(0x2c66d8, 0x0a1a40, 0.35), blueD = lam(0x2150b4), fur = lam(0xc4c8d4, 0x40444e, 0.45), boneM = lam(0xf6f6f8, 0x7c7e8c, 0.55);
  const shirt = lam(0xf6f6f8, 0x6c6e7a, 0.5), shorts = lam(0x17171d), stripe = lam(0xf0f0f0, 0x505058, 0.5), slipper = lam(0xff88c4, 0x40102a, 0.3), sole = lam(0xf6f0f4, 0x505058, 0.4);
  const HIP = 1.85;
  const hips = new THREE.Group(); hips.position.y = HIP; body.add(hips);
  // толстовка: пухлая «капсула» + открытый перед с белой футболкой
  const torsoG = new THREE.CapsuleGeometry(1, 0.5, 4, 14); torsoG.scale(1.18, 0.8, 0.78); torsoG.translate(0, 1.02, 0);
  const torso = new THREE.Mesh(torsoG, blue); torso.userData.sy = true; hips.add(torso);
  hips.add(boxMesh(0.72, 1.45, 0.16, shirt, 0, 1.15, 0.7));
  const edges = mergeGeos([new THREE.BoxGeometry(0.12, 1.55, 0.14).translate(-0.42, 1.12, 0.74), new THREE.BoxGeometry(0.12, 1.55, 0.14).translate(0.42, 1.12, 0.74),
    new THREE.BoxGeometry(2.0, 0.22, 1.25).translate(0, 0.16, 0)]);
  hips.add(new THREE.Mesh(edges, blueD));
  // шорты (верх) — под толстовкой
  hips.add(boxMesh(1.9, 0.5, 1.05, shorts, 0, -0.05, 0));
  // капюшон сзади + меховой обод вокруг шеи
  const hood = new THREE.Mesh(new THREE.SphereGeometry(0.95, 12, 6, 0, Math.PI * 2, 0, Math.PI / 2), blueD);
  hood.scale.set(1.15, 0.62, 0.7); hood.position.set(0, 1.78, -0.42); hood.rotation.x = -0.5; hips.add(hood);
  const ring = new THREE.Mesh(furRing(0.98, 0.34), fur); ring.scale.set(1.08, 1, 0.82); ring.position.y = 1.98; hips.add(ring);
  // шнурки капюшона
  hips.add(new THREE.Mesh(mergeGeos([
    new THREE.BoxGeometry(0.07, 0.6, 0.07).translate(-0.3, 1.58, 0.86), new THREE.BoxGeometry(0.07, 0.6, 0.07).translate(0.3, 1.58, 0.86),
    new THREE.BoxGeometry(0.13, 0.13, 0.13).translate(-0.3, 1.27, 0.87), new THREE.BoxGeometry(0.13, 0.13, 0.13).translate(0.3, 1.27, 0.87),
  ]), stripe));
  // голова: большой круглый череп + маска лица + зрачки + светящийся глаз
  const neck = new THREE.Group(); neck.position.y = 2.02; hips.add(neck);
  const R = 1.22;
  const skullG = new THREE.SphereGeometry(R, 14, 10); skullG.scale(1.1, 0.97, 1.0);
  const head = new THREE.Mesh(skullG, boneM); head.position.y = 1.0; neck.add(head);
  const faceG = new THREE.SphereGeometry(R * 1.012, 18, 12, FACE.phi0, FACE.phiL, FACE.th0, FACE.thL); faceG.scale(1.1, 0.97, 1.0);
  const faceMat = new THREE.MeshLambertMaterial({ map: judgeFaceTex(), transparent: true, alphaTest: 0.35, emissive: 0x7c7e8c, emissiveIntensity: 0.55 });
  head.add(new THREE.Mesh(faceG, faceMat));
  const P = new THREE.Vector3();
  const pupilMat = new THREE.MeshBasicMaterial({ color: 0xffffff });
  const pupils = [0.33, 0.67].map((u) => {
    const s = new THREE.Mesh(new THREE.SphereGeometry(0.075, 6, 4), pupilMat);
    facePoint(u, 0.31, R * 1.035, P); s.position.set(P.x * 1.1, P.y * 0.97, P.z); head.add(s); return s;
  });
  // светящийся глаз — правая глазница с точки зрения зрителя
  const eye = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), color: 0x3fe0ff, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
  facePoint(0.67, 0.31, R * 1.07, P); eye.position.set(P.x * 1.1, P.y * 0.97, P.z); eye.renderOrder = 7; head.add(eye);
  const core = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), color: 0xfff060, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
  core.scale.setScalar(0.34); core.renderOrder = 8; eye.add(core);
  const EYE = 0.95; eye.scale.setScalar(EYE);
  // красный разрез поперёк груди (катсцена смерти): серп #FF0000 из левого-нижнего угла в правый-верхний
  const slash = new THREE.Mesh(new THREE.PlaneGeometry(2.7, 0.75), new THREE.MeshBasicMaterial({ map: slashCrescentTex(), transparent: true, depthWrite: false, side: THREE.DoubleSide, fog: false }));
  slash.position.set(0, 1.1, 1.02); slash.rotation.z = 0.62; slash.renderOrder = 9; slash.visible = false;
  hips.add(slash);

  const limb = (x, isArm) => {
    const pivot = new THREE.Group(); pivot.position.set(x, isArm ? 1.68 : 0, 0); hips.add(pivot);
    if (isArm) {
      const sl = new THREE.CapsuleGeometry(0.43, 0.75, 3, 10); sl.translate(0, -0.72, 0);
      pivot.add(new THREE.Mesh(sl, blue));
      const cuff = new THREE.CylinderGeometry(0.4, 0.4, 0.2, 10).translate(0, -1.52, 0);
      pivot.add(new THREE.Mesh(cuff, fur));
      pivot.add(boxMesh(0.42, 0.42, 0.42, boneM, 0, -1.78, 0));
    } else {
      const sx = x > 0 ? 1 : -1;
      pivot.add(boxMesh(0.98, 0.62, 1.02, shorts, 0, -0.42, 0));
      pivot.add(boxMesh(0.06, 0.6, 0.5, stripe, sx * 0.5, -0.42, 0));
      pivot.add(boxMesh(0.34, 0.8, 0.34, boneM, 0, -1.05, 0));
      const sg = new THREE.SphereGeometry(0.5, 10, 7); sg.scale(1.15, 0.6, 1.6);
      const sp = new THREE.Mesh(sg, slipper); sp.position.set(0, -1.55, 0.2); pivot.add(sp);
      const so = new THREE.SphereGeometry(0.5, 10, 5); so.scale(1.12, 0.22, 1.56);
      const sl = new THREE.Mesh(so, sole); sl.position.set(0, -1.76, 0.2); pivot.add(sl);
    }
    return pivot;
  };
  const armL = limb(-1.27, true), armR = limb(1.27, true), legL = limb(-0.5, false), legR = limb(0.5, false);
  const sh = blobShadow(2.0);
  const av = {
    root, body, parts: { hips, torso, neck, head, armL, armR, legL, legR }, height: 6.05, hipY: HIP, baseScale: 1,
    eye, eyeSize: EYE, pupils, shadow: sh, barY: 6.95, slash,
    pocket: { x: -0.4, z: 0.3 }, // «руки в карманах»: поворот плеч (x — вперёд, z — к телу)
    // глаза: 'pupils' — белые точки, 'dark' — пустые глазницы, 'glow' — левый зрачок + голубой глаз
    setEyes(mode) {
      pupils[0].visible = mode !== 'dark';
      pupils[1].visible = mode === 'pupils';
      eye.visible = mode === 'glow';
    },
  };
  av.setEyes('glow');
  av.mats = collectMats(root);
  // растворение (смерть): все материалы модели, включая глаз и разрез; 1 — как было
  const all = [];
  root.traverse((o) => { if (o.material) for (const m of [].concat(o.material)) if (!all.includes(m)) { m.userData.op0 = m.opacity; m.userData.tr0 = m.transparent; m.userData.at0 = m.alphaTest; all.push(m); } });
  av.fade = 1;
  av.setFade = (a) => {
    if (a === av.fade) return;
    av.fade = a;
    for (const m of all) {
      const tr = a < 0.999 || m.userData.tr0;
      if (m.transparent !== tr) { m.transparent = tr; m.needsUpdate = true; }
      m.opacity = m.userData.op0 * a;
      if (m.userData.at0) m.alphaTest = Math.max(0.01, m.userData.at0 * a);
    }
  };
  av.reset = () => { av.setFade(1); slash.visible = false; slash.scale.set(1, 1, 1); };
  return av;
}

// ---------- Череп-бластер ----------
// Статичные части запечены в 2 меша (кость/тёмное), челюсть — третий: ~5 draw call на череп.
const skullMats = {};
let skullGeos = null;
function bx(w, h, d, x, y, z, ry = 0) {
  const g = new THREE.BoxGeometry(w, h, d);
  if (ry) g.rotateY(ry);
  g.translate(x, y, z);
  return g;
}
export function buildSkull() {
  skullMats.bone ||= lam(0xf6f6fb, 0x30384a, 0.6);
  skullMats.dark ||= new THREE.MeshBasicMaterial({ color: 0x05050a });
  if (!skullGeos) {
    const bone = [bx(2.6, 2.0, 2.2, 0, 0.5, -0.5), bx(2.0, 0.8, 1.9, 0, 0.15, 1.3), bx(0.4, 0.4, 1.6, -1.35, 0.9, -1.3, 0.5), bx(0.4, 0.4, 1.6, 1.35, 0.9, -1.3, -0.5)];
    for (let i = 0; i < 5; i++) bone.push(bx(0.22, 0.25, 0.16, -0.8 + i * 0.4, -0.32, 2.15));
    const dark = [bx(0.7, 0.55, 0.12, -0.62, 0.72, 0.62), bx(0.7, 0.55, 0.12, 0.62, 0.72, 0.62), bx(0.35, 0.22, 0.12, 0, 0.25, 2.25)];
    const jaw = [bx(1.9, 0.5, 2.5, 0, -0.25, 1.35)];
    for (let i = 0; i < 5; i++) jaw.push(bx(0.22, 0.25, 0.16, -0.8 + i * 0.4, 0.1, 2.5));
    skullGeos = { bone: mergeGeos(bone), dark: mergeGeos(dark), jaw: mergeGeos(jaw) };
  }
  const g = new THREE.Group();
  const s = new THREE.Group(); g.add(s); // для масштабирования
  s.add(new THREE.Mesh(skullGeos.bone, skullMats.bone));
  s.add(new THREE.Mesh(skullGeos.dark, skullMats.dark));
  const jaw = new THREE.Group(); jaw.position.set(0, -0.25, -0.2); s.add(jaw);
  jaw.add(new THREE.Mesh(skullGeos.jaw, skullMats.bone));
  const eyes = [];
  for (const x of [-0.62, 0.62]) {
    const e = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), color: 0x7ff3ff, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
    e.position.set(x, 0.72, 0.75); e.scale.setScalar(0.1); e.renderOrder = 7; s.add(e); eyes.push(e);
  }
  return { group: g, inner: s, jaw, eyes };
}

// ---------- Кость (геометрия для инстансов) ----------
export const BONE_H = 1.8; // кость «по колено» (≈1.5–2 стада): прыжок роблокса (≈6.4) перелетает Зону костей
function mergeGeos(list) {
  const pos = [], nor = [];
  for (const g0 of list) {
    const g = g0.index ? g0.toNonIndexed() : g0;
    pos.push(...g.attributes.position.array); nor.push(...g.attributes.normal.array);
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  return out;
}
// Кость: круглый стержень и по два шарика-мыщелка на обоих концах (низ y=0, верх y=BONE_H)
export function boneGeometry() {
  const H = BONE_H, kr = 0.23;
  const shaft = new THREE.CylinderGeometry(0.16, 0.16, H - kr * 2, 6, 1, true); shaft.translate(0, H / 2, 0);
  const knobs = [];
  for (const y of [kr, H - kr]) for (const x of [-0.15, 0.15]) knobs.push(new THREE.SphereGeometry(kr, 6, 4).translate(x, y, 0));
  return mergeGeos([shaft, ...knobs]);
}
