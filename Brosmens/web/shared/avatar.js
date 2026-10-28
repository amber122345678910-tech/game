// Блочный аватар (в стиле классических R6-персонажей): 2D-рисунок для меню и 3D-модель для игр.
// skin = { skin, shirt, pants, hair, hairStyle: 'short'|'spiky'|'long'|'cap'|'none', face: 0..4 }

function shade(hex, k) {
  const n = parseInt(hex.slice(1), 16);
  const c = (v) => Math.max(0, Math.min(255, Math.round(v * k)));
  return `rgb(${c(n >> 16)},${c((n >> 8) & 255)},${c(n & 255)})`;
}

// Лицо на квадрате size×size (используется и в 2D, и как текстура 3D-головы)
export function drawFace(g, x, y, size, face = 0) {
  const s = size;
  g.fillStyle = '#1b1b1b';
  const eyeW = s * 0.1, eyeH = s * (face === 3 ? 0.06 : 0.16);
  g.fillRect(x + s * 0.28, y + s * 0.34, eyeW, eyeH);
  g.fillRect(x + s * 0.62, y + s * 0.34, eyeW, eyeH);
  g.lineWidth = Math.max(1.5, s * 0.05);
  g.strokeStyle = '#1b1b1b';
  g.lineCap = 'round';
  g.beginPath();
  if (face === 0 || face === 2) g.arc(x + s * 0.5, y + s * 0.56, s * 0.18, 0.15 * Math.PI, 0.85 * Math.PI);
  else if (face === 1) { g.arc(x + s * 0.5, y + s * 0.58, s * 0.14, 0.1 * Math.PI, 0.9 * Math.PI); g.moveTo(x + s * 0.36, y + s * 0.62); }
  else if (face === 3) { g.moveTo(x + s * 0.35, y + s * 0.7); g.lineTo(x + s * 0.65, y + s * 0.66); }
  else { g.moveTo(x + s * 0.36, y + s * 0.72); g.quadraticCurveTo(x + s * 0.5, y + s * 0.6, x + s * 0.64, y + s * 0.72); }
  g.stroke();
  if (face === 2) { // румянец
    g.fillStyle = 'rgba(255,90,120,.35)';
    g.fillRect(x + s * 0.16, y + s * 0.55, s * 0.12, s * 0.07);
    g.fillRect(x + s * 0.72, y + s * 0.55, s * 0.12, s * 0.07);
  }
}

function hair2D(g, x, y, s, skin) {
  const st = skin.hairStyle || 'short';
  if (st === 'none') return;
  g.fillStyle = skin.hair;
  if (st === 'cap') {
    g.fillRect(x - s * 0.04, y - s * 0.12, s * 1.08, s * 0.32);
    g.fillRect(x + s * 0.5, y + s * 0.1, s * 0.62, s * 0.1);
  } else if (st === 'spiky') {
    g.beginPath();
    g.moveTo(x - s * 0.05, y + s * 0.3);
    for (let i = 0; i <= 5; i++) {
      g.lineTo(x + (i / 5) * s * 1.1 - s * 0.05, y - s * (i % 2 ? 0.28 : 0.02));
    }
    g.lineTo(x + s * 1.05, y + s * 0.3);
    g.closePath(); g.fill();
  } else if (st === 'long') {
    g.fillRect(x - s * 0.08, y - s * 0.1, s * 1.16, s * 0.3);
    g.fillRect(x - s * 0.1, y, s * 0.16, s * 1.1);
    g.fillRect(x + s * 0.94, y, s * 0.16, s * 1.1);
  } else {
    g.fillRect(x - s * 0.04, y - s * 0.1, s * 1.08, s * 0.28);
  }
}

// Рисует аватар на canvas (вписывает в его размер). opts.headOnly — только голова (для иконок друзей)
export function drawAvatar(canvas, skin, { headOnly = false, bg = null } = {}) {
  const g = canvas.getContext('2d');
  const W = canvas.width, H = canvas.height;
  g.clearRect(0, 0, W, H);
  if (bg) { g.fillStyle = bg; g.fillRect(0, 0, W, H); }
  if (headOnly) {
    const s = Math.min(W, H) * 0.62;
    const x = (W - s) / 2, y = H * 0.26;
    g.fillStyle = shade(skin.shirt, 1); g.fillRect(W * 0.12, y + s * 1.05, W * 0.76, H);
    g.fillStyle = skin.skin; g.fillRect(x, y, s, s);
    g.fillStyle = shade(skin.skin, 0.85); g.fillRect(x + s * 0.9, y, s * 0.1, s);
    drawFace(g, x, y, s, skin.face);
    hair2D(g, x, y, s, skin);
    return;
  }
  const u = Math.min(W / 4.4, H / 6.2);
  const ox = W / 2, oy = (H - u * 6) / 2 + u * 0.3;
  const box = (c, x, y, w, h) => {
    g.fillStyle = c; g.fillRect(ox + x * u, oy + y * u, w * u, h * u);
    g.fillStyle = 'rgba(0,0,0,.14)'; g.fillRect(ox + (x + w * 0.82) * u, oy + y * u, w * 0.18 * u, h * u);
  };
  box(skin.skin, -0.6, 0, 1.2, 1.2); // голова
  drawFace(g, ox - 0.6 * u, oy, 1.2 * u, skin.face);
  hair2D(g, ox - 0.6 * u, oy, 1.2 * u, skin);
  box(skin.shirt, -1, 1.3, 2, 2); // торс
  box(skin.shirt, -2, 1.3, 1, 1.2); box(skin.skin, -2, 2.5, 1, 0.8); // левая рука
  box(skin.shirt, 1, 1.3, 1, 1.2); box(skin.skin, 1, 2.5, 1, 0.8); // правая
  box(skin.pants, -1, 3.3, 1, 2); box(skin.pants, 0, 3.3, 1, 2); // ноги
}

// ---------- 3D ----------
const faceCache = new Map();
function faceTexture(THREE, skin) {
  const key = skin.skin + skin.face;
  if (faceCache.has(key)) return faceCache.get(key);
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  g.fillStyle = skin.skin; g.fillRect(0, 0, 128, 128);
  drawFace(g, 0, 0, 128, skin.face);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  faceCache.set(key, t);
  return t;
}

// Возвращает { root, parts: {torso, head, armL, armR, legL, legR}, height }
// root стоит ногами в y=0, смотрит в +Z. armX/legX — пивоты в плечах/бёдрах (вращайте rotation.x/z).
export function buildAvatar3D(THREE, skin, { scale = 1, outline = false } = {}) {
  const root = new THREE.Group();
  const body = new THREE.Group();
  body.scale.setScalar(scale);
  root.add(body);
  const mat = (c) => new THREE.MeshLambertMaterial({ color: c });
  const box = (w, h, d, m) => {
    const me = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m);
    me.castShadow = true;
    return me;
  };
  const shirt = mat(skin.shirt), pants = mat(skin.pants), skinM = mat(skin.skin);

  const hips = new THREE.Group(); hips.position.y = 2; body.add(hips);
  const torso = box(2, 2, 1, shirt); torso.position.y = 1; hips.add(torso);

  const neck = new THREE.Group(); neck.position.y = 2; hips.add(neck);
  const headMats = [skinM, skinM, skinM, skinM, new THREE.MeshLambertMaterial({ map: faceTexture(THREE, skin) }), skinM];
  const head = box(1.2, 1.2, 1.2, headMats); head.position.y = 0.6; neck.add(head);
  addHair3D(THREE, head, skin);

  const limb = (x, upperM, lowerM, len, py, parent) => {
    const pivot = new THREE.Group(); pivot.position.set(x, py, 0); parent.add(pivot);
    const up = box(1, len * 0.6, 1, upperM); up.position.y = -len * 0.3; pivot.add(up);
    const lo = box(0.98, len * 0.4, 0.98, lowerM); lo.position.y = -len * 0.8; pivot.add(lo);
    return pivot;
  };
  const armL = limb(-1.5, shirt, skinM, 2, 1.9, hips);
  const armR = limb(1.5, shirt, skinM, 2, 1.9, hips);
  const legL = limb(-0.5, pants, pants, 2, 0, hips);
  const legR = limb(0.5, pants, pants, 2, 0, hips);
  armL.children.forEach((m) => (m.position.y += 0.4)); armR.children.forEach((m) => (m.position.y += 0.4));
  armL.position.y = 1.6; armR.position.y = 1.6;

  if (outline) {
    root.traverse((o) => {
      if (o.isMesh) {
        const e = new THREE.Mesh(o.geometry, new THREE.MeshBasicMaterial({ color: 0x000000, side: THREE.BackSide }));
        e.scale.setScalar(1.06); o.add(e);
      }
    });
  }
  return { root, body, parts: { hips, torso, neck, head, armL, armR, legL, legR }, height: 5.2 * scale };
}

function addHair3D(THREE, head, skin) {
  const st = skin.hairStyle || 'short';
  if (st === 'none') return;
  const m = new THREE.MeshLambertMaterial({ color: skin.hair });
  const add = (w, h, d, x, y, z, rx = 0, rz = 0) => {
    const me = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m);
    me.position.set(x, y, z); me.rotation.set(rx, 0, rz); me.castShadow = true; head.add(me); return me;
  };
  if (st === 'cap') { add(1.3, 0.35, 1.3, 0, 0.6, 0); add(1.1, 0.1, 0.7, 0, 0.45, 0.85); }
  else if (st === 'spiky') {
    add(1.3, 0.3, 1.3, 0, 0.6, -0.02);
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2;
      add(0.35, 0.6, 0.35, Math.cos(a) * 0.35, 0.85, Math.sin(a) * 0.35, Math.sin(a) * 0.5, -Math.cos(a) * 0.5);
    }
  } else if (st === 'long') { add(1.32, 0.3, 1.32, 0, 0.6, 0); add(1.32, 1.4, 0.3, 0, -0.05, -0.55); }
  else { add(1.28, 0.28, 1.28, 0, 0.6, -0.02); add(1.28, 0.6, 0.2, 0, 0.3, -0.56); }
}

// Простая процедурная анимация. state: 'idle'|'run'|'air'. phase — время в секундах.
export function animateAvatar(av, state, t, speed = 1) {
  const p = av.parts;
  if (state === 'run') {
    const s = Math.sin(t * 10 * speed);
    p.armL.rotation.x = s * 1.0; p.armR.rotation.x = -s * 1.0;
    p.legL.rotation.x = -s * 0.9; p.legR.rotation.x = s * 0.9;
    p.hips.position.y = 2 + Math.abs(Math.cos(t * 10 * speed)) * 0.12;
  } else if (state === 'air') {
    p.armL.rotation.x = -0.4; p.armR.rotation.x = -0.4; p.armL.rotation.z = -0.5; p.armR.rotation.z = 0.5;
    p.legL.rotation.x = 0.5; p.legR.rotation.x = -0.3;
  } else {
    const s = Math.sin(t * 2);
    p.armL.rotation.set(s * 0.05, 0, -0.06); p.armR.rotation.set(-s * 0.05, 0, 0.06);
    p.legL.rotation.set(0, 0, 0); p.legR.rotation.set(0, 0, 0);
    p.hips.position.y = 2 + s * 0.03;
  }
}
