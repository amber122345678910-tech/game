// «Зал Суда»: длинный золотой коридор (как Judgement Hall в UJD). Шахматный пол из золотых и лососевых плит
// с жёлтыми рамками, ряды каннелированных колонн у стен, арочные светящиеся окна с лучами света,
// тёмный потолок, тусклый проход в дальнем конце, тёплая дымка и оранжевые пылинки. Свет — яркий, «роблоксовский».
import * as THREE from 'three';
import { canvasTex, glowTex } from './fx.js';
import { HALL_X, HALL_Z, HALL_H, COLUMNS, COL_X, COL_R, COL_STEP } from './data.js';

const TILE = 8; // стада на плиту

function floorTexture() {
  // 512 px = 2×2 плиты: простая тёмно-золотая и лососевая с жёлтой квадратной рамкой внутри
  const t = canvasTex(512, 512, (g) => {
    const T = 256;
    for (let r = 0; r < 2; r++) for (let c = 0; c < 2; c++) {
      const x = c * T, y = r * T, ring = (r + c) % 2 === 1;
      g.fillStyle = ring ? '#D2903C' : '#B48A0C';
      g.fillRect(x, y, T, T);
      if (ring) {
        const a = Math.round(T * 0.15), b = Math.round(T * 0.13);
        g.fillStyle = '#D2C036'; g.fillRect(x + a, y + a, T - a * 2, T - a * 2);
        g.fillStyle = '#D2903C'; g.fillRect(x + a + b, y + a + b, T - (a + b) * 2, T - (a + b) * 2);
        // лёгкий блик рамки
        g.fillStyle = 'rgba(255,250,180,.18)'; g.fillRect(x + a, y + a, T - a * 2, 3); g.fillRect(x + a, y + a, 3, T - a * 2);
      }
      // едва заметные разводы пластика, чтобы плита не была мёртво-плоской
      for (let k = 0; k < 5; k++) {
        const s = 40 + Math.random() * 90;
        g.fillStyle = `rgba(${Math.random() < 0.5 ? '255,240,190' : '60,40,0'},0.025)`;
        g.fillRect(x + Math.random() * (T - s), y + Math.random() * (T - s), s, s);
      }
      // тонкий шов между плитами
      g.fillStyle = 'rgba(70,45,0,.22)'; g.fillRect(x, y + T - 2, T, 2); g.fillRect(x + T - 2, y, 2, T);
    }
  });
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = 8;
  return t;
}

// Стена: золотая внизу, к потолку уходит в густую тень
function wallTexture() {
  const t = canvasTex(8, 256, (g) => {
    const gr = g.createLinearGradient(0, 256, 0, 0);
    gr.addColorStop(0, '#c49a2a'); gr.addColorStop(0.45, '#b48a1c'); gr.addColorStop(0.72, '#6e5010'); gr.addColorStop(1, '#2a1d06');
    g.fillStyle = gr; g.fillRect(0, 0, 8, 256);
  });
  return t;
}

// Арочное окно: тёплое стекло, тёмные переплёты, золотая рама (альфа вне арки)
function windowTexture() {
  return canvasTex(128, 256, (g) => {
    const W = 128, H = 256, r = W / 2, top = r;
    const arch = (inset) => { g.beginPath(); g.moveTo(inset, H - inset); g.lineTo(inset, top); g.arc(W / 2, top, r - inset, Math.PI, 0); g.lineTo(W - inset, H - inset); g.closePath(); };
    g.fillStyle = '#7a5a0c'; arch(0); g.fill();
    const gr = g.createRadialGradient(W / 2, H * 0.45, 8, W / 2, H * 0.45, H * 0.6);
    gr.addColorStop(0, '#fffbd8'); gr.addColorStop(0.5, '#ffef8a'); gr.addColorStop(1, '#ffd84a');
    g.fillStyle = gr; arch(9); g.fill();
    g.fillStyle = 'rgba(150,105,10,.85)';
    g.fillRect(W / 2 - 3, top - r + 9, 6, H - top + r - 18);
    g.fillRect(9, H * 0.55, W - 18, 5); g.fillRect(9, H * 0.8, W - 18, 5);
    g.lineWidth = 5; g.strokeStyle = 'rgba(150,105,10,.85)'; g.beginPath(); g.arc(W / 2, top, r * 0.55, Math.PI, 0); g.stroke();
  });
}

// Луч света: яркий у окна, гаснет к полу, мягкие края
function shaftTexture() {
  return canvasTex(64, 128, (g) => {
    const img = g.createImageData(64, 128);
    for (let y = 0; y < 128; y++) for (let x = 0; x < 64; x++) {
      const u = x / 63, v = y / 127;
      const a = Math.pow(Math.sin(u * Math.PI), 1.6) * Math.pow(1 - v, 1.3) * (0.75 + 0.25 * Math.sin(u * 19 + v * 3));
      const i = (y * 64 + x) * 4;
      img.data[i] = 255; img.data[i + 1] = 226; img.data[i + 2] = 140; img.data[i + 3] = Math.min(255, a * 255);
    }
    g.putImageData(img, 0, 0);
  });
}

function poolTexture() {
  return canvasTex(64, 64, (g) => {
    const img = g.createImageData(64, 64);
    for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
      const u = x / 63 * 2 - 1, v = y / 63 * 2 - 1;
      const a = Math.max(0, 1 - Math.pow(Math.abs(u), 3)) * Math.max(0, 1 - Math.pow(Math.abs(v), 2.2));
      const i = (y * 64 + x) * 4;
      img.data[i] = 255; img.data[i + 1] = 236; img.data[i + 2] = 170; img.data[i + 3] = a * 255;
    }
    g.putImageData(img, 0, 0);
  });
}

function doorTexture() {
  return canvasTex(128, 256, (g) => {
    const W = 128, H = 256, r = W / 2;
    g.fillStyle = '#8a6a14'; g.beginPath(); g.moveTo(0, H); g.lineTo(0, r); g.arc(r, r, r, Math.PI, 0); g.lineTo(W, H); g.fill();
    const gr = g.createLinearGradient(0, H, 0, 0);
    gr.addColorStop(0, '#3a2a08'); gr.addColorStop(0.5, '#160f03'); gr.addColorStop(1, '#070401');
    g.fillStyle = gr; g.beginPath(); g.moveTo(10, H); g.lineTo(10, r); g.arc(r, r, r - 10, Math.PI, 0); g.lineTo(W - 10, H); g.fill();
  });
}

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
const box = (w, h, d, x, y, z) => new THREE.BoxGeometry(w, h, d).translate(x, y, z);
const cyl = (r, h, y, seg = 20) => new THREE.CylinderGeometry(r, r, h, seg).translate(0, y, 0);

// Каннелированный ствол колонны (ребро/желобок через вершину)
function flutedShaft(r, h, y0) {
  const seg = 32;
  const g = new THREE.CylinderGeometry(r, r, h, seg, 1, true);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), z = p.getZ(i);
    const a = Math.atan2(z, x), k = Math.round(((a + Math.PI) / (Math.PI * 2)) * seg) % 2 ? 0.9 : 1;
    p.setX(i, Math.cos(a) * r * k); p.setZ(i, Math.sin(a) * r * k);
  }
  g.translate(0, y0 + h / 2, 0);
  g.computeVertexNormals();
  return g;
}

export function buildWorld(scene) {
  const FOG = 0xC9A440;
  scene.background = new THREE.Color(FOG);
  scene.fog = new THREE.Fog(FOG, 60, 230);

  const hemi = new THREE.HemisphereLight(0xFFF4D0, 0x6B5210, 1.1); scene.add(hemi);
  const sun = new THREE.DirectionalLight(0xFFE8B0, 1.4); sun.position.set(40, 70, 25); scene.add(sun);
  const amb = new THREE.AmbientLight(0xFFE2A0, 0.35); scene.add(amb);
  const baseI = [hemi.intensity, sun.intensity, amb.intensity];

  // весь зал — одна группа: в лобби его прячем целиком (свет и туман общие)
  const hall = new THREE.Group(); scene.add(hall);
  const statics = [];
  const add = (o) => { o.matrixAutoUpdate = false; o.updateMatrix(); hall.add(o); statics.push(o); return o; };

  // ---------- пол ----------
  const FW = HALL_X * 2 + 6, FL = HALL_Z * 2 + 4;
  const ft = floorTexture(); ft.repeat.set(FW / (TILE * 2), FL / (TILE * 2)); 
  // плита центрирована по оси зала: границы плит на x,z = ±4, ±12, …
  const off = (half) => (((-(TILE / 2 + half) / (TILE * 2)) % 0.5) + 0.5) % 0.5;
  ft.offset.set(off(FW / 2), off(FL / 2));
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(FW, FL), new THREE.MeshLambertMaterial({ map: ft }));
  floor.rotation.x = -Math.PI / 2; add(floor);

  // ---------- стены, потолок, торцы ----------
  const wt = wallTexture();
  const wallMat = new THREE.MeshLambertMaterial({ map: wt, color: 0xffffff });
  for (const s of [-1, 1]) {
    const side = new THREE.Mesh(new THREE.BoxGeometry(2, HALL_H, HALL_Z * 2 + 4), wallMat); side.position.set(s * (HALL_X + 1), HALL_H / 2, 0); add(side);
    const end = new THREE.Mesh(new THREE.BoxGeometry(HALL_X * 2 + 4, HALL_H, 2), wallMat); end.position.set(0, HALL_H / 2, s * (HALL_Z + 1)); add(end);
  }
  const trimMat = new THREE.MeshLambertMaterial({ color: 0x8e6808 });
  const darkTrim = new THREE.MeshLambertMaterial({ color: 0x5a3e06 });
  // плинтус, антаблемент над колоннами и карниз — одним мешем
  const trimG = [];
  for (const s of [-1, 1]) {
    trimG.push(box(0.8, 1.2, HALL_Z * 2, s * (HALL_X - 0.4), 0.6, 0));
    trimG.push(box(HALL_X - COL_X + 2.4, 2.6, HALL_Z * 2, s * (HALL_X - (HALL_X - COL_X + 2.4) / 2), 27.3, 0));
    trimG.push(box(HALL_X - COL_X + 3.4, 0.9, HALL_Z * 2, s * (HALL_X - (HALL_X - COL_X + 3.4) / 2), 29.05, 0));
    trimG.push(box(HALL_X * 2, 1.2, 0.8, 0, 0.6, s * (HALL_Z - 0.4)));
  }
  add(new THREE.Mesh(mergeGeos(trimG), trimMat));
  const ceil = new THREE.Mesh(new THREE.PlaneGeometry(HALL_X * 2 + 4, HALL_Z * 2 + 4), new THREE.MeshBasicMaterial({ color: 0x1e1504 }));
  ceil.rotation.x = Math.PI / 2; ceil.position.y = HALL_H; add(ceil);
  // балки потолка
  const beams = [];
  for (let z = -HALL_Z + 7; z < HALL_Z; z += COL_STEP) beams.push(box(HALL_X * 2, 1.6, 1.8, 0, HALL_H - 0.8, z));
  add(new THREE.Mesh(mergeGeos(beams), darkTrim));
  // тусклый проход в дальнем конце (к «тронному залу») и дверь за спиной людей
  const doorMat = new THREE.MeshBasicMaterial({ map: doorTexture(), transparent: true, alphaTest: 0.5 });
  const door = new THREE.Mesh(new THREE.PlaneGeometry(13, 24), doorMat); door.position.set(0, 12, -HALL_Z + 0.05); add(door);
  const door2 = new THREE.Mesh(new THREE.PlaneGeometry(9, 15), doorMat); door2.position.set(0, 7.5, HALL_Z - 0.05); door2.rotation.y = Math.PI; add(door2);
  const doorGlow = new THREE.Mesh(new THREE.PlaneGeometry(26, 30), new THREE.MeshBasicMaterial({ map: glowTex(), color: 0x6a4a10, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0.6 }));
  doorGlow.position.set(0, 11, -HALL_Z + 0.2); add(doorGlow);

  // ---------- колонны (инстансы: ствол + база/капитель) ----------
  const colMat = new THREE.MeshLambertMaterial({ color: 0x9C7206 });
  const blockMat = new THREE.MeshLambertMaterial({ color: 0x8a6406 });
  const shaftGeo = flutedShaft(COL_R, 22.0, 2.2);
  const blockGeo = mergeGeos([
    box(4.4, 1.0, 4.4, 0, 0.5, 0), box(3.8, 0.7, 3.8, 0, 1.35, 0), cyl(2.05, 0.5, 1.95),
    cyl(2.05, 0.5, 24.45), box(3.7, 0.7, 3.7, 0, 25.05, 0), box(4.5, 0.8, 4.5, 0, 25.8, 0),
  ]);
  const shafts = new THREE.InstancedMesh(shaftGeo, colMat, COLUMNS.length);
  const blocks = new THREE.InstancedMesh(blockGeo, blockMat, COLUMNS.length);
  const M = new THREE.Matrix4();
  COLUMNS.forEach(([x, z], i) => { M.makeTranslation(x, 0, z); shafts.setMatrixAt(i, M); blocks.setMatrixAt(i, M); });
  add(shafts); add(blocks);

  // ---------- окна между колоннами + свечение + лучи + пятна света на полу ----------
  const winSpots = [];
  for (let k = 0; k < 11; k++) { const z = (k - 5) * COL_STEP; winSpots.push([-1, z], [1, z]); }
  const WW = 5.4, WH = 15, WY = 5.5;
  const winGeo = new THREE.PlaneGeometry(WW, WH).translate(0, WH / 2, 0);
  const windows = new THREE.InstancedMesh(winGeo, new THREE.MeshBasicMaterial({ map: windowTexture(), transparent: true, alphaTest: 0.4 }), winSpots.length);
  const haloGeo = new THREE.PlaneGeometry(WW * 2.6, WH * 1.7).translate(0, WH / 2, 0);
  const halos = new THREE.InstancedMesh(haloGeo, new THREE.MeshBasicMaterial({ map: glowTex(), color: 0xffd860, transparent: true, opacity: 0.55, depthWrite: false, blending: THREE.AdditiveBlending }), winSpots.length);
  // луч: верх у окна, низ на полу ближе к центру зала (лист в плоскости «вдоль стены + вниз-внутрь»)
  const SD = 12, SH = WY + WH * 0.62 - 0.15;
  const shaftG = new THREE.BufferGeometry();
  shaftG.setAttribute('position', new THREE.Float32BufferAttribute([0, 0, -WW * 0.55, 0, 0, WW * 0.55, SD, -SH, -WW * 0.75, SD, -SH, WW * 0.75], 3));
  shaftG.setAttribute('uv', new THREE.Float32BufferAttribute([0, 0, 1, 0, 0, 1, 1, 1], 2));
  shaftG.setIndex([0, 2, 1, 1, 2, 3]);
  const shaftsL = new THREE.InstancedMesh(shaftG, new THREE.MeshBasicMaterial({ map: shaftTexture(), transparent: true, opacity: 0.32, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }), winSpots.length);
  const poolGeo = new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2);
  const pools = new THREE.InstancedMesh(poolGeo, new THREE.MeshBasicMaterial({ map: poolTexture(), transparent: true, opacity: 0.28, depthWrite: false, blending: THREE.AdditiveBlending }), winSpots.length);
  const Q = new THREE.Quaternion(), S = new THREE.Vector3(), P = new THREE.Vector3(), Y = new THREE.Vector3(0, 1, 0);
  // порядок инстансов: чётные окна, потом нечётные — так при низком качестве остаются лучи «через одно»
  const order = winSpots.map((w, i) => i).sort((a, b) => (Math.floor(a / 2) % 2) - (Math.floor(b / 2) % 2));
  order.forEach((wi, i) => {
    const [s, z] = winSpots[wi];
    Q.setFromAxisAngle(Y, -s * Math.PI / 2);
    P.set(s * (HALL_X - 0.02), WY, z); S.set(1, 1, 1);
    M.compose(P, Q, S); windows.setMatrixAt(i, M);
    P.set(s * (HALL_X - 0.06), WY - 3.5, z); M.compose(P, Q, S); halos.setMatrixAt(i, M);
    M.makeScale(-s, 1, 1).setPosition(s * (HALL_X - 0.3), WY + WH * 0.62, z); shaftsL.setMatrixAt(i, M);
    M.makeScale(9, 1, WW * 1.6).setPosition(s * (HALL_X - 0.3 - SD * 0.9), 0.04, z); pools.setMatrixAt(i, M);
  });
  add(windows); add(halos); add(shaftsL); add(pools);
  halos.renderOrder = 1; shaftsL.renderOrder = 3; pools.renderOrder = 1;

  // ---------- парящие оранжевые пылинки ----------
  const MOTES = 280, mp = new Float32Array(MOTES * 3), mph = new Float32Array(MOTES);
  for (let i = 0; i < MOTES; i++) {
    mp[i * 3] = (Math.random() * 2 - 1) * (HALL_X - 2); mp[i * 3 + 1] = 0.5 + Math.random() * 24; mp[i * 3 + 2] = (Math.random() * 2 - 1) * (HALL_Z - 2);
    mph[i] = Math.random() * 10;
  }
  const mg = new THREE.BufferGeometry(); const mattr = new THREE.BufferAttribute(mp, 3).setUsage(THREE.DynamicDrawUsage); mg.setAttribute('position', mattr);
  const mpts = new THREE.Points(mg, new THREE.PointsMaterial({ map: glowTex(), size: 0.55, color: 0xFFB040, transparent: true, opacity: 0.85, depthWrite: false, blending: THREE.AdditiveBlending }));
  mpts.frustumCulled = false; hall.add(mpts);
  let moteN = MOTES;

  let dark = 0, darkT = 0;
  const fogBase = scene.fog.color.clone(), fogDark = new THREE.Color(0x2a1c04);
  const fogFar0 = scene.fog.far;
  return {
    floor,
    get visible() { return hall.visible; },
    setVisible(v) { hall.visible = v; },
    setDark(k) { darkT = k; },
    setQuality(level) {
      moteN = level <= 3 ? 70 : level <= 7 ? 170 : MOTES;
      mg.setDrawRange(0, moteN);
      const nw = winSpots.length;
      shaftsL.count = level <= 3 ? 0 : level <= 6 ? Math.ceil(nw / 2) : nw;
      shaftsL.visible = shaftsL.count > 0;
      pools.visible = level >= 3;
      halos.visible = level >= 2;
      scene.fog.far = fogFar0 + (level - 6) * 10;
    },
    update(t, dt) {
      const n = hall.visible ? moteN : 0;
      for (let i = 0; i < n; i++) {
        const i3 = i * 3;
        mp[i3 + 1] += dt * (0.35 + (mph[i] % 1) * 0.4);
        mp[i3] += Math.sin(t * 0.4 + mph[i]) * dt * 0.5;
        mp[i3 + 2] += Math.cos(t * 0.3 + mph[i] * 1.7) * dt * 0.3;
        if (mp[i3 + 1] > 25) mp[i3 + 1] = 0.4;
      }
      if (n) mattr.needsUpdate = true;
      shaftsL.material.opacity = 0.3 + Math.sin(t * 0.7) * 0.03;
      if (Math.abs(dark - darkT) > 0.002) {
        dark += (darkT - dark) * Math.min(1, dt * 3);
        const k = 1 - dark * 0.6;
        hemi.intensity = baseI[0] * k; sun.intensity = baseI[1] * k; amb.intensity = baseI[2] * k;
        scene.fog.color.copy(fogBase).lerp(fogDark, dark);
        scene.background.copy(scene.fog.color);
      }
    },
  };
}
