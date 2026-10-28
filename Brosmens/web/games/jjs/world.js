// Карта: роблокс-подобный городской парк. Вся статика склеена в пару мешей (1–3 draw call).
import * as THREE from 'three';
import { Merger, mulberry32, clamp, tex } from './util.js';

export const BOUND = 77;
const STEP = 0.7;

export function buildWorld(scene, { shadows = true } = {}) {
  const rng = mulberry32(20261028);
  const r = (a, b) => a + rng() * (b - a);
  const rpick = (arr) => arr[Math.floor(rng() * arr.length)];
  const solids = [];
  const M = new Merger(); // основная статика
  const F = new Merger(); // плоские «наклейки» (дороги, тропинки)
  const FAR = new Merger(); // дальние здания

  const solidBox = (x, y0, z, w, h, d) => solids.push({ t: 0, minX: x - w / 2, maxX: x + w / 2, minY: y0, maxY: y0 + h, minZ: z - d / 2, maxZ: z + d / 2 });
  const solidCyl = (x, z, rad, y0, y1) => solids.push({ t: 1, x, z, r: rad, minY: y0, maxY: y1 });

  // ---------- Земля ----------
  const gt = tex('grass'); gt.repeat.set(110, 110);
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(900, 900), new THREE.MeshLambertMaterial({ map: gt }));
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  scene.add(ground);

  const flat = (x, z, w, d, color, top = 0.06) => F.box(x, top / 2, z, w, top, d, color);

  // Тротуары, дороги, площадь
  const SIDE = '#c9c7c0', ROAD = '#3a3c42', PLAZA = '#b8b2a6', PATH = '#bdb3a0';
  for (const s of [-1, 1]) {
    flat(0, s * 43, 92, 6, SIDE, 0.1); flat(s * 43, 0, 6, 80, SIDE, 0.1); // внутренний тротуар
    flat(0, s * 53, 132, 14, ROAD, 0.07); flat(s * 53, 0, 14, 92, ROAD, 0.07); // дорога
    flat(0, s * 63, 132, 6, SIDE, 0.1); flat(s * 63, 0, 6, 120, SIDE, 0.1); // внешний тротуар
    flat(0, s * 73, 160, 14, PLAZA, 0.08); flat(s * 73, 0, 14, 132, PLAZA, 0.08); // площадь у зданий
    // тропинки парка
    flat(0, s * 26, 6, 28, PATH, 0.07); flat(s * 26, 0, 28, 6, PATH, 0.07);
  }
  // разметка
  const LINE = '#f2c94c', WL = '#f4f4f0';
  for (const s of [-1, 1]) {
    for (let a = -58; a < 58; a += 6) {
      flat(a + 1.5, s * 53, 3, 0.35, LINE, 0.1);
      if (Math.abs(a) < 44) flat(s * 53, a + 1.5, 0.35, 3, LINE, 0.1);
    }
    flat(0, s * 46.6, 120, 0.3, WL, 0.1); flat(0, s * 59.4, 120, 0.3, WL, 0.1);
    flat(s * 46.6, 0, 0.3, 92, WL, 0.1); flat(s * 59.4, 0, 0.3, 92, WL, 0.1);
    // зебры
    for (let k = -2; k <= 2; k++) {
      flat(k * 1.6, s * 53, 0.9, 11, WL, 0.11);
      flat(s * 53, k * 1.6, 11, 0.9, WL, 0.11);
    }
  }
  // круглая площадь с фонтаном
  {
    const g = new THREE.CylinderGeometry(13, 13, 0.08, 32);
    F.geo(g, new THREE.Matrix4().makeTranslation(0, 0.04, 0), PATH);
    const g2 = new THREE.CylinderGeometry(10.5, 10.5, 0.1, 32);
    F.geo(g2, new THREE.Matrix4().makeTranslation(0, 0.05, 0), '#c9c0ae');
  }

  // ---------- Фонтан ----------
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2;
    M.box(Math.cos(a) * 7, 0.75, Math.sin(a) * 7, 3.9, 1.5, 1.2, '#c7c4bd', { ry: -a + Math.PI / 2 });
  }
  M.cyl(0, 0.55, 0, 6.6, 0.9, '#3d9be0', 24);
  M.box(0, 2, 0, 1.6, 4, 1.6, '#d2cfc8');
  M.cyl(0, 3.9, 0, 2.6, 0.6, '#c7c4bd', 16, 2.9);
  M.cyl(0, 4.25, 0, 2.3, 0.15, '#58b4f0', 16);
  M.box(0, 4.8, 0, 0.7, 1.2, 0.7, '#d2cfc8');
  solidCyl(0, 0, 7.6, 0, 1.5);
  solidCyl(0, 0, 1.6, 0, 4.4);
  const camBlock = []; // только для камеры: стволы и кроны деревьев, колонна фонтана
  camBlock.push({ t: 0, minX: -1.3, maxX: 1.3, minY: 0, maxY: 4.6, minZ: -1.3, maxZ: 1.3 });

  // ---------- Деревья ----------
  const trees = [];
  const LEAF = ['#3f8f3a', '#4ba043', '#348a3c', '#5aac48'];
  const tree = (x, z) => {
    const h = r(6.6, 8.2);
    M.box(x, h / 2, z, 1.3, h, 1.3, '#6b4a2b');
    const c1 = rpick(LEAF), c2 = rpick(LEAF);
    const s = r(5.6, 7.2);
    M.box(x, h + 1.4, z, s, 3.2, s, c1, { ry: r(0, 1) });
    M.box(x, h + 3.6, z, s * 0.7, 2.4, s * 0.7, c2, { ry: r(0, 1) });
    if (rng() < 0.5) M.box(x, h + 5.2, z, s * 0.4, 1.4, s * 0.4, c1);
    solidCyl(x, z, 0.95, 0, h);
    const hs = s * 0.62;
    camBlock.push({ t: 0, minX: x - hs, maxX: x + hs, minY: h - 0.2, maxY: h + 5, minZ: z - hs, maxZ: z + hs });
    // ствол тоже загораживает камеру (иначе первый кадр — коричневая стена во весь экран)
    camBlock.push({ t: 0, minX: x - 0.95, maxX: x + 0.95, minY: 0, maxY: h, minZ: z - 0.95, maxZ: z + 0.95 });
    trees.push({ x, z });
  };
  for (let tries = 0; tries < 400 && trees.length < 22; tries++) {
    const x = r(-37, 37), z = r(-37, 37);
    if (Math.abs(x) < 6 || Math.abs(z) < 6) continue;
    if (Math.hypot(x, z) < 17) continue;
    if (trees.some((t) => Math.hypot(t.x - x, t.z - z) < 8)) continue;
    tree(x, z);
  }
  // деревья вдоль внешнего тротуара
  for (const s of [-1, 1]) for (let a = -48; a <= 48; a += 24) {
    if (Math.abs(a) < 8) continue;
    tree(a, s * 67.5); tree(s * 67.5, a);
  }

  // ---------- Живая изгородь по краю парка ----------
  const HEDGE = '#2f7d34';
  for (const s of [-1, 1]) {
    for (const [a0, a1] of [[-39.5, -4.5], [4.5, 39.5]]) {
      const c = (a0 + a1) / 2, L = a1 - a0;
      M.box(c, 0.9, s * 39.5, L, 1.8, 1.4, HEDGE); solidBox(c, 0, s * 39.5, L, 1.8, 1.4);
      M.box(s * 39.5, 0.9, c, 1.4, 1.8, L, HEDGE); solidBox(s * 39.5, 0, c, 1.4, 1.8, L);
    }
  }

  // ---------- Скамейки и фонари ----------
  const bench = (x, z, rot) => {
    const mx = new THREE.Matrix4().makeRotationY(rot).setPosition(x, 0, z);
    M.box(0, 1.1, 0, 4.4, 0.35, 1.4, '#8a5a32', { m: mx });
    M.box(0, 1.9, -0.6, 4.4, 1.1, 0.25, '#8a5a32', { m: mx });
    M.box(-1.8, 0.55, 0, 0.3, 1.1, 1.2, '#30333a', { m: mx });
    M.box(1.8, 0.55, 0, 0.3, 1.1, 1.2, '#30333a', { m: mx });
    const along = Math.abs(Math.sin(rot)) > 0.5;
    solidBox(x, 0, z, along ? 1.6 : 4.4, 1.3, along ? 4.4 : 1.6);
  };
  for (const s of [-1, 1]) {
    bench(5.5, s * 22, -Math.PI / 2); bench(-5.5, s * 30, Math.PI / 2);
    bench(s * 22, 5.5, Math.PI); bench(s * 30, -5.5, 0);
  }
  const lamp = (x, z) => {
    M.box(x, 4.5, z, 0.45, 9, 0.45, '#2f3238');
    M.box(x, 9.1, z, 1.3, 0.5, 1.3, '#2f3238');
    M.box(x, 8.7, z, 1.0, 0.4, 1.0, '#fff2b0');
    solidCyl(x, z, 0.4, 0, 9);
  };
  for (const s of [-1, 1]) for (const t of [-1, 1]) lamp(s * 9, t * 9);
  for (const s of [-1, 1]) for (let a = -36; a <= 36; a += 18) { lamp(a, s * 41.2); lamp(s * 41.2, a); }

  // ---------- Машины ----------
  const CARS = ['#d63c3c', '#2f6fed', '#f2c230', '#e8e8e8', '#2b2b2b', '#3fae5a', '#f08a24', '#8e44ad'];
  const car = (x, z, alongX) => {
    const col = rpick(CARS);
    const mx = new THREE.Matrix4().makeRotationY(alongX ? Math.PI / 2 : 0).setPosition(x, 0, z);
    M.box(0, 1.35, 0, 4.2, 1.5, 8.4, col, { m: mx });
    M.box(0, 2.75, -0.4, 3.7, 1.3, 4.2, '#9fc6e6', { m: mx });
    M.box(0, 3.5, -0.4, 3.8, 0.25, 4.3, col, { m: mx });
    M.box(0, 1.3, 4.22, 3.2, 0.5, 0.1, '#fff6c8', { m: mx });
    M.box(0, 1.3, -4.22, 3.2, 0.4, 0.1, '#c0392b', { m: mx });
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) M.box(sx * 2.05, 0.65, sz * 2.7, 0.7, 1.3, 1.5, '#1b1b1b', { m: mx });
    if (alongX) solidBox(x, 0, z, 8.4, 3.6, 4.2); else solidBox(x, 0, z, 4.2, 3.6, 8.4);
  };
  car(-30, 57.5, true); car(22, 48.5, true); car(-14, -57.5, true); car(36, -48.5, true);
  car(57.5, 24, false); car(48.5, -28, false); car(-57.5, -18, false); car(-48.5, 30, false);

  // ---------- Мелочи у зданий ----------
  const crate = (x, z, s = 3, y = 0) => { M.box(x, y + s / 2, z, s, s, s, '#b0844c', { ry: r(-0.2, 0.2) }); M.box(x, y + s / 2, z, s * 1.02, s * 0.15, s * 1.02, '#7a5a30'); solidBox(x, y, z, s, s, s); };
  crate(-70, 70); crate(-66.5, 70.5); crate(-69, 70, 2.4, 3);
  crate(70, -66); crate(70, -70.5, 2.6);
  crate(66, 71); crate(-71, -64, 2.6);
  const vending = (x, z, ry) => { M.box(x, 2, z, 2, 4, 1.6, '#d63c3c', { ry }); M.box(x, 2.6, z, 1.5, 2.2, 1.65, '#bfe6ff', { ry }); solidBox(x, 0, z, 2, 4, 2); };
  vending(-74, 20, 0); vending(74, -20, 0); vending(20, -74, 0);
  const dumpster = (x, z) => { M.box(x, 1.5, z, 5, 3, 3, '#2f6b3a'); M.box(x, 3.1, z, 5.2, 0.3, 3.2, '#24502c'); solidBox(x, 0, z, 5, 3.2, 3); };
  dumpster(40, 74); dumpster(-44, -74); dumpster(74, 44);
  // остановка
  const busStop = (x, z) => {
    M.box(x, 4.2, z, 8, 0.3, 3.4, '#2f3238'); M.box(x, 2.1, z - 1.5, 8, 4.2, 0.2, '#9fc6e6');
    M.box(x - 3.9, 2.1, z, 0.25, 4.2, 3.4, '#2f3238'); M.box(x + 3.9, 2.1, z, 0.25, 4.2, 3.4, '#2f3238');
    M.box(x, 1, z - 0.8, 6, 0.3, 1.2, '#8a5a32');
    solidBox(x, 0, z - 1.5, 8, 4.2, 0.4);
  };
  busStop(-20, 67.5);

  // ---------- Здания по периметру ----------
  const BCOL = ['#c96a4a', '#d9c7a1', '#8a9bb0', '#e8e4dc', '#5f8f8a', '#b5555e', '#7a6a8f', '#d5a24f', '#a7b6c2', '#c48b6b'];
  const AWN = ['#d63c3c', '#2f6fed', '#3fae5a', '#f2c230'];
  const building = (cx, cz, w, d, h, nx, nz) => {
    // nx,nz — нормаль фасада, смотрящего в арену
    const col = rpick(BCOL);
    M.box(cx, h / 2, cz, w, h, d, col);
    solidBox(cx, 0, cz, w, h, d);
    // крыша: бортик и коробки
    M.box(cx, h + 0.4, cz + d / 2 - 0.3, w, 0.8, 0.6, '#55585f'); M.box(cx, h + 0.4, cz - d / 2 + 0.3, w, 0.8, 0.6, '#55585f');
    M.box(cx + w / 2 - 0.3, h + 0.4, cz, 0.6, 0.8, d, '#55585f'); M.box(cx - w / 2 + 0.3, h + 0.4, cz, 0.6, 0.8, d, '#55585f');
    M.box(cx + r(-w / 4, w / 4), h + 1, cz + r(-d / 4, d / 4), r(2, 4), 2, r(2, 4), '#9a9ea6');
    if (rng() < 0.35) M.cyl(cx + r(-w / 4, w / 4), h + 2.5, cz + r(-d / 4, d / 4), 1.6, 5, '#7a6a5a', 10);
    // фасад к арене
    const along = nz !== 0; // фасад вдоль X
    const faceLen = along ? w : d;
    const fx = cx + nx * (along ? 0 : w / 2), fz = cz + nz * (along ? d / 2 : 0);
    const cols = Math.max(2, Math.floor((faceLen - 3) / 3.6));
    const step = (faceLen - 3) / cols;
    const lit = rng() < 0.3;
    for (let y = 7.5; y < h - 2.5; y += 4.6) {
      for (let i = 0; i < cols; i++) {
        const t = -faceLen / 2 + 1.5 + step * (i + 0.5);
        const wc = lit && rng() < 0.25 ? '#f3dc8a' : rng() < 0.15 ? '#3d6a94' : '#2c4a6e';
        if (along) M.box(fx + t, y, fz, 1.9, 2.5, 0.35, wc);
        else M.box(fx, y, fz + t, 0.35, 2.5, 1.9, wc);
      }
      // карниз между этажами
      if (along) M.box(fx, y - 2.2, fz, faceLen, 0.3, 0.5, '#6b6f78');
      else M.box(fx, y - 2.2, fz, 0.5, 0.3, faceLen, '#6b6f78');
    }
    // первый этаж: витрина и навес
    const aw = rpick(AWN);
    if (along) {
      M.box(fx, 2.4, fz, faceLen * 0.7, 3.6, 0.3, '#9fc6e6');
      M.box(fx, 4.9, fz + nz * 1.2, faceLen * 0.75, 0.3, 2.6, aw, { rx: nz * 0.25 });
    } else {
      M.box(fx, 2.4, fz, 0.3, 3.6, faceLen * 0.7, '#9fc6e6');
      M.box(fx + nx * 1.2, 4.9, fz, 2.6, 0.3, faceLen * 0.75, aw, { rz: -nx * 0.25 });
    }
  };
  for (const s of [-1, 1]) {
    let a = -80;
    while (a < 80) {
      const w = Math.min(r(14, 22), 80 - a);
      if (w < 6) break;
      const d = r(16, 24), h = r(16, 44), inner = 80 + r(0, 2.5);
      building(a + w / 2, s * (inner + d / 2), w, d, h, 0, -s);
      a += w + r(0, 1.5);
    }
    a = -80;
    while (a < 80) {
      const w = Math.min(r(14, 22), 80 - a);
      if (w < 6) break;
      const d = r(16, 24), h = r(16, 44), inner = 80 + r(0, 2.5);
      building(s * (inner + d / 2), a + w / 2, d, w, h, -s, 0);
      a += w + r(0, 1.5);
    }
  }
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    const h = r(46, 62);
    M.box(sx * 96, h / 2, sz * 96, 30, h, 30, rpick(BCOL));
    M.box(sx * 96, h + 3, sz * 96, 8, 6, 8, '#9a9ea6');
    solidBox(sx * 96, 0, sz * 96, 30, h, 30);
  }
  // Дальние небоскрёбы (силуэт города)
  const FCOL = ['#8f9fb3', '#a3a9b8', '#7d8aa0', '#b6b9c4', '#93a3a8'];
  for (let i = 0; i < 46; i++) {
    const a = (i / 46) * Math.PI * 2 + r(-0.05, 0.05);
    const R = r(150, 230), w = r(20, 40), h = r(35, 110);
    FAR.box(Math.cos(a) * R, h / 2, Math.sin(a) * R, w, h, w * r(0.7, 1.3), rpick(FCOL), { ry: -a });
  }

  const statMat = new THREE.MeshLambertMaterial({ vertexColors: true });
  const stat = new THREE.Mesh(M.build(), statMat);
  stat.receiveShadow = true; stat.castShadow = shadows;
  scene.add(stat);
  const flatMesh = new THREE.Mesh(F.build(), statMat);
  flatMesh.receiveShadow = true;
  scene.add(flatMesh);
  const far = new THREE.Mesh(FAR.build(), statMat);
  scene.add(far);

  // ---------- Небо, солнце, облака ----------
  const sky = new THREE.Mesh(
    new THREE.SphereGeometry(950, 24, 12),
    new THREE.ShaderMaterial({
      side: THREE.BackSide, depthWrite: false, fog: false,
      uniforms: { top: { value: new THREE.Color('#2f7fe0') }, mid: { value: new THREE.Color('#79b8f2') }, bot: { value: new THREE.Color('#d8ecff') } },
      vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix*modelViewMatrix*vec4(position,1.); }',
      fragmentShader: 'uniform vec3 top, mid, bot; varying vec3 vP; void main(){ float h = vP.y; vec3 c = h > 0.15 ? mix(mid, top, clamp((h-0.15)/0.6,0.,1.)) : mix(bot, mid, clamp((h+0.05)/0.2,0.,1.)); gl_FragColor = vec4(c,1.); }',
    }),
  );
  sky.renderOrder = -10;
  scene.add(sky);
  const sunDir = new THREE.Vector3(0.45, 0.72, 0.38).normalize();
  const sun = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex('glow'), color: 0xfff6d0, fog: false, depthWrite: false, blending: THREE.AdditiveBlending, transparent: true }));
  sun.position.copy(sunDir).multiplyScalar(800); sun.scale.setScalar(260);
  const sunCore = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex('glow'), color: 0xffffff, fog: false, depthWrite: false, transparent: true }));
  sunCore.position.copy(sun.position); sunCore.scale.setScalar(70);
  scene.add(sun, sunCore);

  const CL = new Merger();
  for (let i = 0; i < 16; i++) {
    const a = r(0, Math.PI * 2), R = r(160, 520), y = r(120, 190);
    const cx = Math.cos(a) * R, cz = Math.sin(a) * R;
    const n = 3 + Math.floor(r(0, 4));
    for (let k = 0; k < n; k++) CL.box(cx + r(-25, 25), y + r(-3, 5), cz + r(-15, 15), r(18, 40), r(7, 12), r(14, 26), '#ffffff');
  }
  const clouds = new THREE.Mesh(CL.build(), new THREE.MeshLambertMaterial({ vertexColors: true, emissive: 0x9aa6b8, fog: false }));
  scene.add(clouds);

  // ---------- Запросы ----------
  function groundAt(x, z, y) {
    let g = 0;
    for (let i = 0; i < solids.length; i++) {
      const s = solids[i];
      if (s.maxY > y + STEP || s.maxY <= g) continue;
      if (s.t === 0) { if (x >= s.minX && x <= s.maxX && z >= s.minZ && z <= s.maxZ) g = s.maxY; }
      else { const dx = x - s.x, dz = z - s.z; if (dx * dx + dz * dz <= s.r * s.r) g = s.maxY; }
    }
    return g;
  }
  // Выталкивает цилиндр-персонажа из препятствий. Возвращает true, если упёрся.
  function collide(pos, radius, height = 5.2) {
    let hit = false;
    for (let i = 0; i < solids.length; i++) {
      const s = solids[i];
      if (pos.y >= s.maxY - STEP || pos.y + height <= s.minY) continue;
      if (s.t === 0) {
        const cx = clamp(pos.x, s.minX, s.maxX), cz = clamp(pos.z, s.minZ, s.maxZ);
        const dx = pos.x - cx, dz = pos.z - cz, d2 = dx * dx + dz * dz;
        if (d2 >= radius * radius) continue;
        hit = true;
        if (d2 > 1e-6) {
          const d = Math.sqrt(d2), push = radius - d;
          pos.x += (dx / d) * push; pos.z += (dz / d) * push;
        } else {
          const l = pos.x - s.minX, rr = s.maxX - pos.x, b = pos.z - s.minZ, t = s.maxZ - pos.z;
          const m = Math.min(l, rr, b, t);
          if (m === l) pos.x = s.minX - radius; else if (m === rr) pos.x = s.maxX + radius;
          else if (m === b) pos.z = s.minZ - radius; else pos.z = s.maxZ + radius;
        }
      } else {
        const dx = pos.x - s.x, dz = pos.z - s.z, d2 = dx * dx + dz * dz, R = s.r + radius;
        if (d2 >= R * R) continue;
        hit = true;
        const d = Math.sqrt(d2) || 0.001;
        pos.x = s.x + (dx / d) * R; pos.z = s.z + (dz / d) * R;
      }
    }
    if (pos.x > BOUND) { pos.x = BOUND; hit = true; } else if (pos.x < -BOUND) { pos.x = -BOUND; hit = true; }
    if (pos.z > BOUND) { pos.z = BOUND; hit = true; } else if (pos.z < -BOUND) { pos.z = -BOUND; hit = true; }
    return hit;
  }
  function pointBlocked(p) {
    if (p.y < 0.05) return true;
    for (let i = 0; i < solids.length; i++) {
      const s = solids[i];
      if (p.y < s.minY || p.y > s.maxY) continue;
      if (s.t === 0) { if (p.x >= s.minX && p.x <= s.maxX && p.z >= s.minZ && p.z <= s.maxZ) return true; }
      else { const dx = p.x - s.x, dz = p.z - s.z; if (dx * dx + dz * dz <= s.r * s.r) return true; }
    }
    return false;
  }
  // Луч для камеры: расстояние до первого препятствия (только крупные блоки)
  function rayDist(o, d, maxLen) {
    let best = maxLen;
    const n1 = solids.length, n = n1 + camBlock.length;
    for (let i = 0; i < n; i++) {
      const s = i < n1 ? solids[i] : camBlock[i - n1];
      if (s.t !== 0 || s.maxY < 2.5) continue;
      let tmin = 0, tmax = best;
      let ok = true;
      for (let ax = 0; ax < 3 && ok; ax++) {
        const oa = ax === 0 ? o.x : ax === 1 ? o.y : o.z;
        const da = ax === 0 ? d.x : ax === 1 ? d.y : d.z;
        const mn = ax === 0 ? s.minX : ax === 1 ? s.minY : s.minZ;
        const mx = ax === 0 ? s.maxX : ax === 1 ? s.maxY : s.maxZ;
        if (Math.abs(da) < 1e-6) { if (oa < mn || oa > mx) ok = false; continue; }
        let t1 = (mn - oa) / da, t2 = (mx - oa) / da;
        if (t1 > t2) { const tt = t1; t1 = t2; t2 = tt; }
        if (t1 > tmin) tmin = t1;
        if (t2 < tmax) tmax = t2;
        if (tmin > tmax) ok = false;
      }
      if (ok && tmin < best && tmin >= 0) best = tmin;
    }
    return best;
  }

  const spawns = [];
  for (const s of [-1, 1]) {
    spawns.push([s * 25, 25], [s * 25, -25], [0, s * 33], [s * 33, 0], [s * 53, s * 10], [-s * 10, s * 53], [s * 70, -s * 30], [s * 30, s * 70]);
  }

  return { solids, groundAt, collide, pointBlocked, rayDist, spawns, sunDir, clouds, update(dt) { clouds.rotation.y += dt * 0.004; } };
}
