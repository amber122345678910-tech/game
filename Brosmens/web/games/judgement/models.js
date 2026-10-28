// Модели: люди (блочный аватар + оружие + душа), Судья (скелет в синей толстовке), черепа-бластеры, кости.
import * as THREE from 'three';
import { buildAvatar3D } from '../../shared/avatar.js';
import { canvasTex, glowTex, heartTex, textSprite } from './fx.js';

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
    g.add(boxMesh(0.22, 1.4, 0.22, lam(0xf2f2f2), 0, -0.55, 0));
    g.add(boxMesh(0.42, 0.42, 0.42, lam(0x45d8ff, 0x1a7090, 0.8), 0, -1.35, 0));
    const rib = new THREE.Mesh(new THREE.PlaneGeometry(0.35, 2.2), new THREE.MeshLambertMaterial({ color: 0x8fe9ff, emissive: 0x1a6080, side: THREE.DoubleSide }));
    rib.position.set(0, -0.2, -0.5); rib.rotation.x = 0.6; g.add(rib);
    av.ribbon = rib;
    av.tip = new THREE.Object3D(); av.tip.position.set(0, -1.4, 0); g.add(av.tip);
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

export function buildHuman(skin, role, name, showTag = true) {
  const av = buildAvatar3D(THREE, skin, { scale: 1 });
  addWeapon(av, role.id);
  // душа над головой
  const heart = new THREE.Sprite(new THREE.SpriteMaterial({ map: heartTex(role.color), transparent: true, depthWrite: false, fog: false }));
  heart.position.y = 6.5; heart.scale.setScalar(1.25); heart.renderOrder = 6;
  av.root.add(heart);
  av.heart = heart;
  if (showTag) { const tag = textSprite(name, '#ffffff', { font: 26 }); tag.position.y = 7.6; tag.scale.multiplyScalar(0.8); av.root.add(tag); av.tag = tag; }
  const sh = blobShadow(1.6); av.shadow = sh;
  av.mats = collectMats(av.root);
  return av;
}

// ---------- Судья ----------
function skullFaceTex() {
  return canvasTex(128, 128, (g) => {
    g.fillStyle = '#f4f3ec'; g.fillRect(0, 0, 128, 128);
    g.fillStyle = 'rgba(0,0,0,.06)'; g.fillRect(0, 100, 128, 28);
    // глазницы
    g.fillStyle = '#0b0b12';
    g.beginPath(); g.ellipse(38, 52, 17, 18, 0, 0, 7); g.fill();
    g.beginPath(); g.ellipse(90, 52, 17, 18, 0, 0, 7); g.fill();
    // зрачок-огонёк в правой глазнице
    g.fillStyle = '#ffffff'; g.beginPath(); g.arc(38, 53, 5, 0, 7); g.fill();
    // нос
    g.fillStyle = '#15151c'; g.beginPath(); g.moveTo(64, 70); g.lineTo(58, 80); g.lineTo(70, 80); g.closePath(); g.fill();
    // широкая ухмылка
    g.strokeStyle = '#15151c'; g.lineWidth = 4; g.lineCap = 'round';
    g.beginPath(); g.moveTo(20, 88); g.quadraticCurveTo(64, 112, 108, 88); g.stroke();
    g.lineWidth = 2.5;
    for (let i = 0; i < 9; i++) { const x = 30 + i * 8.5, y = 90 + Math.sin(((x - 20) / 88) * Math.PI) * 11; g.beginPath(); g.moveTo(x, y - 6); g.lineTo(x, y + 6); g.stroke(); }
  });
}
function hoodieTex() {
  return canvasTex(128, 128, (g) => {
    g.fillStyle = '#2f62d6'; g.fillRect(0, 0, 128, 128);
    g.fillStyle = '#2753bb'; g.fillRect(26, 70, 76, 34); // карман
    g.fillStyle = '#1d3f93'; g.fillRect(26, 70, 76, 4);
    g.fillStyle = '#e8e8f0'; g.fillRect(62, 0, 4, 128); // молния
    g.fillStyle = '#ffffff'; g.fillRect(42, 4, 4, 36); g.fillRect(82, 4, 4, 36); // шнурки
    g.fillRect(40, 38, 8, 6); g.fillRect(80, 38, 8, 6);
    g.fillStyle = 'rgba(0,0,0,.15)'; g.fillRect(0, 118, 128, 10);
  });
}

export function buildJudge() {
  const root = new THREE.Group(); const body = new THREE.Group(); body.scale.setScalar(1.25); root.add(body);
  const hood = lam(0x2f62d6), hoodD = lam(0x2348a8), fur = lam(0xdde4f2), bone = lam(0xf4f3ec, 0x222230, 0.4), shorts = lam(0x15151d), stripe = lam(0xf0f0f0), shoe = lam(0xff7fb0);
  const hips = new THREE.Group(); hips.position.y = 2; body.add(hips);
  const tmats = [hood, hood, hood, hood, new THREE.MeshLambertMaterial({ map: hoodieTex() }), hood];
  const torso = new THREE.Mesh(new THREE.BoxGeometry(2.3, 2.1, 1.25), tmats); torso.position.y = 1.05; hips.add(torso);
  hips.add(boxMesh(2.4, 0.3, 1.35, hoodD, 0, 0.12, 0));
  // меховой капюшон
  hips.add(boxMesh(2.5, 0.42, 0.42, fur, 0, 2.05, -0.55));
  hips.add(boxMesh(0.42, 0.42, 1.35, fur, -1.05, 2.05, 0)); hips.add(boxMesh(0.42, 0.42, 1.35, fur, 1.05, 2.05, 0));
  hips.add(boxMesh(1.8, 0.7, 0.4, hoodD, 0, 1.75, -0.75));
  const neck = new THREE.Group(); neck.position.y = 2.05; hips.add(neck);
  const hm = [bone, bone, bone, bone, new THREE.MeshLambertMaterial({ map: skullFaceTex(), emissive: 0x222230, emissiveIntensity: 0.4 }), bone];
  const head = new THREE.Mesh(new THREE.BoxGeometry(1.9, 1.75, 1.7), hm); head.position.y = 0.95; neck.add(head);
  // светящийся глаз (левый для зрителя)
  const eye = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), color: 0x3fe0ff, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
  eye.position.set(-0.43, 0.12, 0.9); eye.scale.setScalar(0.7); eye.renderOrder = 7; head.add(eye);

  const limb = (x, isArm) => {
    const pivot = new THREE.Group(); pivot.position.set(x, isArm ? 1.65 : 0, 0); hips.add(pivot);
    if (isArm) {
      pivot.add(boxMesh(1.0, 1.4, 1.0, hood, 0, -0.45, 0));
      pivot.add(boxMesh(1.08, 0.3, 1.08, fur, 0, -1.15, 0));
      pivot.add(boxMesh(0.7, 0.6, 0.7, bone, 0, -1.55, 0));
    } else {
      pivot.add(boxMesh(1.05, 0.95, 1.08, shorts, 0, -0.45, 0));
      pivot.add(boxMesh(0.12, 0.85, 1.1, stripe, x > 0 ? 0.48 : -0.48, -0.45, 0));
      pivot.add(boxMesh(0.42, 0.85, 0.42, bone, 0, -1.3, 0));
      pivot.add(boxMesh(0.95, 0.4, 1.35, shoe, 0, -1.8, 0.15));
    }
    return pivot;
  };
  const armL = limb(-1.65, true), armR = limb(1.65, true), legL = limb(-0.55, false), legR = limb(0.55, false);
  // кость-дубина в руке (видна во время удара)
  const club = new THREE.Group(); club.position.set(0, -1.6, 0); armR.add(club);
  club.add(boxMesh(0.32, 3.2, 0.32, bone, 0, -1.5, 0));
  for (const s of [-1, 1]) { club.add(boxMesh(0.36, 0.36, 0.36, bone, s * 0.22, -3.15, 0)); club.add(boxMesh(0.36, 0.36, 0.36, bone, s * 0.22, 0.05, 0)); }
  club.visible = false;
  const tag = textSprite('⚖ ' + 'Судья', '#7fb4ff', { font: 28 }); tag.position.y = 9.4; root.add(tag);
  const sh = blobShadow(2.2);
  const av = { root, body, parts: { hips, torso, neck, head, armL, armR, legL, legR }, height: 6.6, eye, club, tag, shadow: sh };
  av.mats = collectMats(root);
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
export const BONE_H = 2.4;
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
export function boneGeometry() {
  const H = BONE_H;
  const shaft = new THREE.BoxGeometry(0.34, H - 0.4, 0.34); shaft.translate(0, (H - 0.4) / 2, 0);
  const k1 = new THREE.BoxGeometry(0.3, 0.42, 0.42); k1.translate(-0.17, H - 0.21, 0);
  const k2 = new THREE.BoxGeometry(0.3, 0.42, 0.42); k2.translate(0.17, H - 0.21, 0);
  return mergeGeos([shaft, k1, k2]);
}
