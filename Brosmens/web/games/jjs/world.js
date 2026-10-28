// Карта: городской квартал как в JJS — бетонные стены по периметру, внешнее и внутреннее кольцо дорог,
// маленькая петля вокруг площади с 4 деревьями, пастельные дома с плоскими крышами (на многие можно забраться
// по наружной лестнице), белые башни-близнецы с мостом на севере, тёмное кафе ЮВ от площади, кладбище на западе.
// Вся статика склеена в 3 меша (дома/детали, плоские «наклейки» дорог, дальний город). Север = −Z.
import * as THREE from 'three';
import { Merger, mulberry32, clamp, canvasTex } from './util.js';

export const BOUND = 106.8;
const STEP = 0.7;
const WALL = 110; // центр стены (внутренняя грань 108)

// Палитра (спека §8.1)
const ASPHALT = '#2B2B2B', LINE = '#f2f2ee', CONCRETE = '#BDBDBD', WALK = '#cbcac6', CURB = '#9d9c98';
const BCOLS = ['#C9B6F2', '#D7ECC9', '#F4EDA0', '#F6C9A4', '#EAB0B0', '#B94A48', '#8A8FD0'];
const ROOF = '#7A7C88', WIN = '#9AA6B8', TOWER = '#E6EEF4';
const LEAF = ['#2F8F2F', '#35963a', '#2a852c'], TRUNK = '#8B4A2B';

export function buildWorld(scene, { shadows = true } = {}) {
  const rng = mulberry32(20261028);
  const r = (a, b) => a + rng() * (b - a);
  const rpick = (arr) => arr[Math.floor(rng() * arr.length)];
  const solids = [];
  const camBlock = []; // только для камеры: кроны деревьев
  const M = new Merger(); // основная статика
  const F = new Merger(); // плоские «наклейки» (дороги, разметка, тротуары)
  const FAR = new Merger(); // город за стеной

  const solidBox = (x, y0, z, w, h, d) => solids.push({ t: 0, minX: x - w / 2, maxX: x + w / 2, minY: y0, maxY: y0 + h, minZ: z - d / 2, maxZ: z + d / 2 });
  const solidRect = (x0, x1, z0, z1, y0, y1) => solids.push({ t: 0, minX: Math.min(x0, x1), maxX: Math.max(x0, x1), minY: y0, maxY: y1, minZ: Math.min(z0, z1), maxZ: Math.max(z0, z1) });
  const solidCyl = (x, z, rad, y0, y1) => solids.push({ t: 1, x, z, r: rad, minY: y0, maxY: y1 });
  // плоский прямоугольник по углам
  const flatR = (x0, x1, z0, z1, color, top = 0.06) => F.box((x0 + x1) / 2, top / 2, (z0 + z1) / 2, Math.abs(x1 - x0), top, Math.abs(z1 - z0), color);
  const boxR = (x0, x1, y0, y1, z0, z1, color, o) => M.box((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, Math.abs(x1 - x0), Math.abs(y1 - y0), Math.abs(z1 - z0), color, o);
  const shade = (hex, k) => { const c = new THREE.Color(hex); c.multiplyScalar(k); return '#' + c.getHexString(); };

  // ---------- Земля: светлый бетон ----------
  const gtex = canvasTex(128, 128, (g, w, h) => {
    g.fillStyle = '#c3c2bd'; g.fillRect(0, 0, w, h);
    for (let i = 0; i < 700; i++) { g.fillStyle = Math.random() < 0.5 ? 'rgba(0,0,0,.035)' : 'rgba(255,255,255,.05)'; const s = 1 + Math.floor(Math.random() * 3); g.fillRect(Math.floor(Math.random() * w), Math.floor(Math.random() * h), s, s); }
    g.fillStyle = 'rgba(0,0,0,.08)'; g.fillRect(0, 0, w, 1); g.fillRect(0, 0, 1, h);
  }, { repeat: true });
  gtex.repeat.set(60, 60);
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(600, 600), new THREE.MeshLambertMaterial({ map: gtex }));
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  scene.add(ground);

  // ---------- Дороги ----------
  // Кольца: внешнее (края 90–102), внутреннее (51–63), петля у площади (18–28); поперечные улицы |x|,|z| ≤ 6.
  const RINGS = [{ a: 90, b: 102 }, { a: 51, b: 63 }, { a: 18, b: 28 }];
  const roadSeg = (x0, x1, z0, z1, alongX, lines = true) => {
    flatR(x0, x1, z0, z1, ASPHALT, 0.07);
    if (!lines) return;
    if (alongX) { for (const zz of [Math.min(z0, z1) + 0.8, Math.max(z0, z1) - 0.8]) flatR(x0 + 0.4, x1 - 0.4, zz - 0.16, zz + 0.16, LINE, 0.09); }
    else { for (const xx of [Math.min(x0, x1) + 0.8, Math.max(x0, x1) - 0.8]) flatR(xx - 0.16, xx + 0.16, z0 + 0.4, z1 - 0.4, LINE, 0.09); }
  };
  // зебра поперёк дороги: полосы вдоль направления движения
  const zebra = (cx, cz, len, alongX) => {
    for (let k = -len / 2 + 1.2; k <= len / 2 - 1.2; k += 1.8) {
      if (alongX) flatR(cx - 1.4, cx + 1.4, cz + k - 0.45, cz + k + 0.45, LINE, 0.1);
      else flatR(cx + k - 0.45, cx + k + 0.45, cz - 1.4, cz + 1.4, LINE, 0.1);
    }
  };
  for (const s of [-1, 1]) {
    for (const R of RINGS) {
      const c = (R.a + R.b) / 2, w = R.b - R.a;
      // стороны кольца: между углом и поперечной улицей (по обе стороны от неё)
      for (const h of [-1, 1]) {
        const x0 = h * 6, x1 = h * R.a;
        roadSeg(Math.min(x0, x1), Math.max(x0, x1), s * R.a, s * R.b, true);
        roadSeg(s * R.a, s * R.b, Math.min(x0, x1), Math.max(x0, x1), false);
      }
      // перекрёсток с поперечной улицей и углы — без продольных линий
      flatR(-6, 6, s * R.a, s * R.b, ASPHALT, 0.07); flatR(s * R.a, s * R.b, -6, 6, ASPHALT, 0.07);
      for (const h of [-1, 1]) flatR(s * R.a, s * R.b, h * R.a, h * R.b, ASPHALT, 0.07);
      // зебры: на кольце по обе стороны от перекрёстка и на поперечной улице перед ним
      for (const h of [-1, 1]) {
        zebra(h * 8, s * c, w, true); zebra(s * c, h * 8, w, false);
        // на углах кольца — по одной зебре на каждом подходе
        zebra(h * (R.a - 2.2), s * c, w, true); zebra(s * c, h * (R.a - 2.2), w, false);
      }
    }
    // поперечные улицы: внешнее → внутреннее кольцо → петля площади
    for (const [a, b] of [[63, 90], [28, 51]]) {
      roadSeg(-6, 6, s * a, s * b, false); roadSeg(s * a, s * b, -6, 6, true);
      zebra(0, s * (a + 2.2), 12, false); zebra(0, s * (b - 2.2), 12, false);
      zebra(s * (a + 2.2), 0, 12, true); zebra(s * (b - 2.2), 0, 12, true);
    }
  }
  // тротуары вдоль дорог (светлая кромка с бордюром)
  const walkStrip = (x0, x1, z0, z1) => flatR(x0, x1, z0, z1, WALK, 0.05);
  for (const s of [-1, 1]) {
    walkStrip(-108, 108, s * 102, s * 108); walkStrip(s * 102, s * 108, -102, 102);
    for (const R of RINGS.slice(1)) {
      walkStrip(-R.b - 2.4, R.b + 2.4, s * (R.b + 1.2) - 1.2, s * (R.b + 1.2) + 1.2);
      walkStrip(s * (R.b + 1.2) - 1.2, s * (R.b + 1.2) + 1.2, -R.b - 2.4, R.b + 2.4);
      walkStrip(-R.a + 2.4, R.a - 2.4, s * (R.a - 1.2) - 1.2, s * (R.a - 1.2) + 1.2);
      walkStrip(s * (R.a - 1.2) - 1.2, s * (R.a - 1.2) + 1.2, -R.a + 2.4, R.a - 2.4);
    }
    walkStrip(-88, 88, s * 88.8 - 1.2, s * 88.8 + 1.2); walkStrip(s * 88.8 - 1.2, s * 88.8 + 1.2, -88, 88);
  }

  // ---------- Площадь: светлый бетон, плитка, 4 дерева в травяных клумбах 2×2 ----------
  flatR(-18, 18, -18, 18, '#cfcecb', 0.08);
  for (let k = -15; k <= 15; k += 5) { flatR(k - 0.06, k + 0.06, -18, 18, '#b4b3af', 0.085); flatR(-18, 18, k - 0.06, k + 0.06, '#b4b3af', 0.085); }
  const trees = [];
  const tree = (x, z, sc = 1, y0 = 0) => {
    // Y-ствол: толстый низ и две ветви, на них 2–3 «травяных» куба
    const h = 4.2 * sc;
    M.box(x, y0 + h / 2, z, 1.5 * sc, h, 1.5 * sc, TRUNK);
    M.box(x - 0.75 * sc, y0 + h + 1.3 * sc, z, 0.9 * sc, 3.2 * sc, 0.9 * sc, TRUNK, { rz: 0.5 });
    M.box(x + 0.75 * sc, y0 + h + 1.3 * sc, z, 0.9 * sc, 3.2 * sc, 0.9 * sc, TRUNK, { rz: -0.5 });
    const s1 = 6.4 * sc, top = y0 + h + 3.4 * sc;
    M.box(x - 1.1 * sc, top + 0.6 * sc, z + 0.4 * sc, s1, s1 * 0.78, s1, LEAF[0], { ry: r(-0.25, 0.25) });
    M.box(x + 1.3 * sc, top + 1.4 * sc, z - 0.6 * sc, s1 * 0.82, s1 * 0.74, s1 * 0.82, LEAF[1], { ry: r(-0.3, 0.3) });
    if (rng() < 0.7) M.box(x + r(-0.6, 0.6) * sc, top + 4.2 * sc, z + r(-0.6, 0.6) * sc, s1 * 0.55, s1 * 0.5, s1 * 0.55, LEAF[2], { ry: r(-0.4, 0.4) });
    solidCyl(x, z, 0.95 * sc, y0, y0 + h + 2);
    const hs = s1 * 0.75;
    camBlock.push({ t: 0, minX: x - hs, maxX: x + hs, minY: top - 2.4 * sc, maxY: top + 6 * sc, minZ: z - hs, maxZ: z + hs });
    camBlock.push({ t: 0, minX: x - 0.95 * sc, maxX: x + 0.95 * sc, minY: y0, maxY: top, minZ: z - 0.95 * sc, maxZ: z + 0.95 * sc });
    trees.push({ x, z, r: hs });
  };
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    const x = sx * 8.5, z = sz * 8.5;
    // клумба: бетонный бортик 0.6 + трава
    boxR(x - 3.6, x + 3.6, 0, 0.6, z - 3.6, z - 3.0, '#a9a8a4'); boxR(x - 3.6, x + 3.6, 0, 0.6, z + 3.0, z + 3.6, '#a9a8a4');
    boxR(x - 3.6, x - 3.0, 0, 0.6, z - 3.0, z + 3.0, '#a9a8a4'); boxR(x + 3.0, x + 3.6, 0, 0.6, z - 3.0, z + 3.0, '#a9a8a4');
    boxR(x - 3.0, x + 3.0, 0, 0.5, z - 3.0, z + 3.0, '#4f9a3f');
    solidRect(x - 3.6, x + 3.6, z - 3.6, z + 3.6, 0, 0.6);
    tree(x, z, 1, 0.5);
  }
  // скамейки вдоль площади
  const bench = (x, z, alongX) => {
    if (alongX) { boxR(x - 2.2, x + 2.2, 0.9, 1.25, z - 0.7, z + 0.7, '#8a5a32'); boxR(x - 2, x - 1.7, 0, 0.9, z - 0.6, z + 0.6, '#3a3c42'); boxR(x + 1.7, x + 2, 0, 0.9, z - 0.6, z + 0.6, '#3a3c42'); solidRect(x - 2.2, x + 2.2, z - 0.7, z + 0.7, 0, 1.25); }
    else { boxR(x - 0.7, x + 0.7, 0.9, 1.25, z - 2.2, z + 2.2, '#8a5a32'); boxR(x - 0.6, x + 0.6, 0, 0.9, z - 2, z - 1.7, '#3a3c42'); boxR(x - 0.6, x + 0.6, 0, 0.9, z + 1.7, z + 2, '#3a3c42'); solidRect(x - 0.7, x + 0.7, z - 2.2, z + 2.2, 0, 1.25); }
  };
  for (const s of [-1, 1]) { bench(0, s * 15.5, true); bench(s * 15.5, 0, false); }

  // ---------- Фонари: серый столб, квадратная голова ----------
  const lamp = (x, z, dx, dz) => {
    M.box(x, 4.2, z, 0.42, 8.4, 0.42, '#7d7f86');
    M.box(x + dx * 0.8, 8.3, z + dz * 0.8, dx ? 1.8 : 0.3, 0.3, dz ? 1.8 : 0.3, '#7d7f86');
    M.box(x + dx * 1.6, 8.0, z + dz * 1.6, 1.1, 0.55, 1.1, '#cfd0d2');
    M.box(x + dx * 1.6, 7.68, z + dz * 1.6, 0.85, 0.12, 0.85, '#fff4c8');
    solidCyl(x, z, 0.35, 0, 8.4);
  };
  for (const s of [-1, 1]) {
    for (const a of [-75, -45, -20, 20, 45, 75]) { lamp(a, s * 88.6, 0, s); lamp(s * 88.6, a, s, 0); }
    for (const a of [-40, -22, 22, 40]) { lamp(a, s * 64.6, 0, -s); lamp(s * 64.6, a, -s, 0); }
    lamp(s * 17, -17, 0, 0); lamp(s * 17, 17, 0, 0);
  }

  // ---------- Здания ----------
  // Пастельная коробка с плоской серой крышей, сеткой «утопленных» окон и (часто) наружной лестницей на крышу.
  const windowsOn = (x0, x1, z0, z1, h, face, col) => {
    // face: 'n','s','w','e'; окна #9AA6B8 с подоконником и перемычкой (кажутся утопленными)
    const along = face === 'n' || face === 's';
    const L = along ? x1 - x0 : z1 - z0;
    const n = Math.max(1, Math.floor((L - 2) / 3.8));
    const step = (L - 2) / n;
    const dark = shade(col, 0.72);
    for (let y = 2.4; y < h - 1.6; y += 4.4) {
      for (let i = 0; i < n; i++) {
        const t = (along ? x0 : z0) + 1 + step * (i + 0.5);
        const ww = Math.min(2.1, step - 1.1);
        // стекло — одна грань чуть перед стеной, подоконник и перемычка — выступающие планки (окно «утоплено»)
        if (along) {
          const zf = face === 'n' ? z0 : z1, o = face === 'n' ? -1 : 1;
          M.quad(t, y, zf + o * 0.04, ww, 2.3, 'z', o, WIN);
          M.box(t, y - 1.28, zf + o * 0.16, ww + 0.5, 0.26, 0.36, dark);
          M.box(t, y + 1.28, zf + o * 0.13, ww + 0.5, 0.26, 0.3, dark);
        } else {
          const xf = face === 'w' ? x0 : x1, o = face === 'w' ? -1 : 1;
          M.quad(xf + o * 0.04, y, t, ww, 2.3, 'x', o, WIN);
          M.box(xf + o * 0.16, y - 1.28, t, 0.36, 0.26, ww + 0.5, dark);
          M.box(xf + o * 0.13, y + 1.28, t, 0.3, 0.26, ww + 0.5, dark);
        }
      }
    }
  };
  // наружная лестница вдоль стены (сплошные ступени ≤0.6 — на них заходят без прыжка)
  const stairs = (x0, x1, z0, z1, top, dirAxis, dirSign) => {
    // ступени растут вдоль dirAxis ('x' | 'z') в сторону dirSign
    const n = Math.ceil(top / 0.58), rise = top / n;
    const L = dirAxis === 'x' ? x1 - x0 : z1 - z0, d = L / n;
    for (let k = 0; k < n; k++) {
      const yy = rise * (k + 1);
      const a = dirSign > 0 ? (dirAxis === 'x' ? x0 : z0) + d * k : (dirAxis === 'x' ? x1 : z1) - d * (k + 1);
      if (dirAxis === 'x') { boxR(a, a + d, 0, yy, z0, z1, k % 2 ? '#a3a3a0' : '#9a9a97'); solidRect(a, a + d, z0, z1, 0, yy); }
      else { boxR(x0, x1, 0, yy, a, a + d, k % 2 ? '#a3a3a0' : '#9a9a97'); solidRect(x0, x1, a, a + d, 0, yy); }
    }
  };
  const building = (x0, x1, z0, z1, h, col, o = {}) => {
    boxR(x0, x1, 0, h, z0, z1, col);
    solidRect(x0, x1, z0, z1, 0, h + 0.3);
    // крыша: плита, низкий бортик (перешагивается), пара коробок кондиционеров
    boxR(x0 - 0.2, x1 + 0.2, h, h + 0.3, z0 - 0.2, z1 + 0.2, ROOF);
    const pw = 0.45, py = h + 0.3, ph = 0.5, pc = '#666874';
    boxR(x0 - 0.2, x1 + 0.2, py, py + ph, z0 - 0.2, z0 - 0.2 + pw, pc); boxR(x0 - 0.2, x1 + 0.2, py, py + ph, z1 + 0.2 - pw, z1 + 0.2, pc);
    boxR(x0 - 0.2, x0 - 0.2 + pw, py, py + ph, z0 - 0.2, z1 + 0.2, pc); boxR(x1 + 0.2 - pw, x1 + 0.2, py, py + ph, z0 - 0.2, z1 + 0.2, pc);
    if (!o.bare) {
      const ax = r(x0 + 3, x1 - 3), az = r(z0 + 3, z1 - 3);
      boxR(ax - 1.2, ax + 1.2, py, py + 1.6, az - 1, az + 1, '#b7b9bf'); solidRect(ax - 1.2, ax + 1.2, az - 1, az + 1, py, py + 1.6);
      M.box(ax, py + 1.62, az, 1.6, 0.06, 1.6, '#55575e');
    }
    // нижняя полоса-цоколь и окна на всех фасадах
    const base = shade(col, 0.82);
    boxR(x0 - 0.12, x1 + 0.12, 0, 0.8, z0 - 0.12, z1 + 0.12, base);
    for (const f of ['n', 's', 'w', 'e']) windowsOn(x0, x1, z0, z1, h, f, col);
    // дверь на фасаде к дороге
    if (o.door) {
      const [fx, fz, axis] = o.door;
      if (axis === 'z') M.box(fx, 1.6, fz, 2.4, 3.2, 0.3, '#5a4436'); else M.box(fx, 1.6, fz, 0.3, 3.2, 2.4, '#5a4436');
    }
    if (o.stairs) stairs(...o.stairs, h + 0.3, o.stairDir[0], o.stairDir[1]);
  };
  // Участок: прямоугольник (с отступом от дорог) → 1–2 дома, лестница на один из них
  const lotHouses = (x0, x1, z0, z1, cfg = {}) => {
    const W = x1 - x0, D = z1 - z0;
    const alongX = W >= D;
    const parts = cfg.parts || (Math.max(W, D) > 34 ? 2 : 1);
    const gap = parts > 1 ? r(6, 9) : 0;
    const L = (alongX ? W : D) - gap;
    const cut = parts > 1 ? L * r(0.42, 0.58) : L;
    const segs = parts > 1 ? [[0, cut], [cut + gap, L + gap]] : [[0, L]];
    segs.forEach(([a, b], i) => {
      let bx0 = alongX ? x0 + a : x0, bx1 = alongX ? x0 + b : x1, bz0 = alongX ? z0 : z0 + a, bz1 = alongX ? z1 : z0 + b;
      const reach = cfg.reach ?? rng() < 0.7;
      const h = reach ? r(8.5, 13.5) : r(14, 22);
      let st = null, sd = null;
      if (reach) {
        // лестница вдоль длинной стены (полоса 3.2), ступени поднимаются вдоль неё
        if (alongX) {
          if (cfg.stairSide === 'n' || (cfg.stairSide !== 's' && rng() < 0.5)) { st = [bx0 + 1, bx1 - 1, bz0, bz0 + 3.2]; bz0 += 3.2; } else { st = [bx0 + 1, bx1 - 1, bz1 - 3.2, bz1]; bz1 -= 3.2; }
          sd = ['x', rng() < 0.5 ? 1 : -1];
        } else {
          if (cfg.stairSide === 'w' || (cfg.stairSide !== 'e' && rng() < 0.5)) { st = [bx0, bx0 + 3.2, bz0 + 1, bz1 - 1]; bx0 += 3.2; } else { st = [bx1 - 3.2, bx1, bz0 + 1, bz1 - 1]; bx1 -= 3.2; }
          sd = ['z', rng() < 0.5 ? 1 : -1];
        }
      }
      const col = cfg.colors ? cfg.colors[i % cfg.colors.length] : rpick(BCOLS);
      building(bx0, bx1, bz0, bz1, h, col, { stairs: st ? [st[0], st[1], st[2], st[3]] : null, stairDir: sd });
    });
  };
  const M_IN = 4.5; // отступ домов от края квартала (тротуар)
  // внутренние кварталы (между петлёй площади 28 и внутренним кольцом 51), Г-образные
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    const lo = 28 + M_IN, hi = 51 - M_IN, ar0 = 6 + M_IN, ar1 = 28 - 1;
    const R = (a0, a1, b0, b1) => [Math.min(sx * a0, sx * a1), Math.max(sx * a0, sx * a1), Math.min(sz * b0, sz * b1), Math.max(sz * b0, sz * b1)];
    if (sz < 0) {
      // север: башни-близнецы занимают «северные руки»; угол — дом
      const [x0, x1, z0, z1] = R(lo, hi, lo, hi); lotHouses(x0, x1, z0, z1, { parts: 1, reach: true });
      const [a0, a1, b0, b1] = R(lo, hi, ar0, ar1); lotHouses(a0, a1, b0, b1, { parts: 1 });
    } else if (sx > 0) {
      // ЮВ: угол — кафе (ниже), южная рука — дом, восточная — терраса кафе
      const [a0, a1, b0, b1] = R(ar0, ar1, lo, hi); lotHouses(a0, a1, b0, b1, { parts: 1, reach: true });
    } else {
      // ЮЗ: угол и южная рука — дома, западная рука — мини-сквер
      const [x0, x1, z0, z1] = R(lo, hi, lo, hi); lotHouses(x0, x1, z0, z1, { parts: 1 });
      const [a0, a1, b0, b1] = R(ar0, ar1, lo, hi); lotHouses(a0, a1, b0, b1, { parts: 1, reach: true });
      tree(sx * 38, sz * 12, 0.85); tree(sx * 44, sz * 22, 0.8);
    }
  }
  // внешние кварталы (между внутренним кольцом 63 и внешним 90)
  const o0 = 63 + M_IN, o1 = 90 - M_IN;
  for (const s of [-1, 1]) {
    for (const h of [-1, 1]) {
      // стороны С/Ю: |x| 6..63
      const a0 = h > 0 ? 6 + M_IN : -63 + M_IN * 0.5, a1 = h > 0 ? 63 - M_IN * 0.5 : -6 - M_IN;
      lotHouses(a0, a1, s > 0 ? o0 : -o1, s > 0 ? o1 : -o0, { stairSide: s > 0 ? 'n' : 's' });
      // стороны З/В (кроме кладбища на западе к югу от улицы)
      if (!(s < 0 && h > 0)) lotHouses(s > 0 ? o0 : -o1, s > 0 ? o1 : -o0, a0, a1, { stairSide: s > 0 ? 'w' : 'e' });
    }
    // угловые участки — по одному дому
    for (const h of [-1, 1]) {
      const x0 = s > 0 ? o0 : -o1, x1 = s > 0 ? o1 : -o0, z0 = h > 0 ? o0 : -o1, z1 = h > 0 ? o1 : -o0;
      lotHouses(x0 + 1, x1 - 1, z0 + 1, z1 - 1, { parts: 1, reach: rng() < 0.5 });
    }
  }
  // деревья у террасы кафе
  tree(47, 12.5, 0.8);

  // ---------- Башни-близнецы (север) с мостом ----------
  const TH = 58;
  for (const sx of [-1, 1]) {
    const x0 = sx > 0 ? 8.5 : -26.5, x1 = sx > 0 ? 26.5 : -8.5, z0 = -50, z1 = -32;
    boxR(x0, x1, 0, TH, z0, z1, TOWER);
    solidRect(x0, x1, z0, z1, 0, TH + 0.4);
    boxR(x0 - 0.3, x1 + 0.3, TH, TH + 0.4, z0 - 0.3, z1 + 0.3, '#c9d2da');
    boxR(x0 + 3, x1 - 3, TH + 0.4, TH + 3, z0 + 3, z1 - 3, '#cfd6dd');
    // вертикальные ленты окон по 4 сторонам + карнизы через этаж
    for (let y = 5.2; y < TH - 1; y += 5.2) {
      boxR(x0 - 0.15, x1 + 0.15, y - 0.2, y + 0.2, z0 - 0.15, z1 + 0.15, '#cdd6de');
      for (let k = 0; k < 5; k++) {
        const t = x0 + 2 + k * ((x1 - x0 - 4) / 4);
        M.quad(t, y + 2.5, z0 - 0.05, 1.9, 3.4, 'z', -1, WIN); M.quad(t, y + 2.5, z1 + 0.05, 1.9, 3.4, 'z', 1, WIN);
        const tz = z0 + 2 + k * ((z1 - z0 - 4) / 4);
        M.quad(x0 - 0.05, y + 2.5, tz, 1.9, 3.4, 'x', -1, WIN); M.quad(x1 + 0.05, y + 2.5, tz, 1.9, 3.4, 'x', 1, WIN);
      }
    }
    // вход и рекламный щит на фасаде
    boxR(x0 + 5, x1 - 5, 0, 4.2, z1, z1 + 0.25, '#7c8fa8');
    boxR(x0 + 2.5, x1 - 2.5, 30, 38, z1 + 0.2, z1 + 0.45, sx > 0 ? '#e85a7a' : '#4a8ee8');
    boxR(x0 + 3.3, x1 - 3.3, 31, 37, z1 + 0.45, z1 + 0.55, sx > 0 ? '#ffd6e0' : '#d6e8ff');
  }
  // мост на «9 этаже» над северной улицей
  const BY = 46.8;
  boxR(-8.5, 8.5, BY, BY + 0.8, -44, -38, '#d4dbe2'); solidRect(-8.5, 8.5, -44, -38, BY, BY + 0.8);
  boxR(-8.5, 8.5, BY + 0.8, BY + 4.2, -44, -43.7, '#a9c4dc', { shade: 1.05 }); boxR(-8.5, 8.5, BY + 0.8, BY + 4.2, -38.3, -38, '#a9c4dc');
  boxR(-8.5, 8.5, BY + 4.2, BY + 4.6, -44.2, -37.8, '#d4dbe2');
  camBlock.push({ t: 0, minX: -8.5, maxX: 8.5, minY: BY, maxY: BY + 4.6, minZ: -44, maxZ: -38 });

  // ---------- Кафе (ЮВ от площади): тёмно-серое, 2 этажа, открытый фасад к террасе, двускатная крыша ----------
  {
    const x0 = 32, x1 = 48.5, z0 = 32, z1 = 48.5, H = 11.5, C = '#4a4c52', CD = '#3a3b40';
    boxR(x0, x1, 0, H, z1 - 0.8, z1, C); solidRect(x0, x1, z1 - 0.8, z1, 0, H);           // задняя стена
    boxR(x0, x0 + 0.8, 0, H, z0, z1, C); solidRect(x0, x0 + 0.8, z0, z1, 0, H);           // западная
    boxR(x1 - 0.8, x1, 0, H, z0, z1, C); solidRect(x1 - 0.8, x1, z0, z1, 0, H);           // восточная
    boxR(x0, x1, H - 1.2, H, z0, z0 + 0.8, C);                                             // перемычка фасада
    for (const px of [x0 + 5.5, x1 - 5.5]) { boxR(px - 0.45, px + 0.45, 0, H, z0, z0 + 0.9, CD); solidRect(px - 0.45, px + 0.45, z0, z0 + 0.9, 0, H); }
    // пол и антресоль (задняя половина), лестница вдоль западной стены от входа
    flatR(x0, x1, z0, z1, '#8d7a66', 0.1);
    boxR(x0 + 0.8, x1 - 0.8, 5.6, 6.2, 40, z1 - 0.8, '#5c5e66'); solidRect(x0 + 0.8, x1 - 0.8, 40, z1 - 0.8, 5.6, 6.2);
    boxR(x0 + 3.8, x1 - 0.8, 6.2, 7.2, 40, 40.25, '#2b2c30');
    {
      const n = 11, rise = 6.2 / n, d = (40 - (z0 + 0.8)) / n;
      for (let k = 0; k < n; k++) { const za = z0 + 0.8 + d * k; boxR(x0 + 0.8, x0 + 3.8, 0, rise * (k + 1), za, za + d, '#6b5a4a'); solidRect(x0 + 0.8, x0 + 3.8, za, za + d, 0, rise * (k + 1)); }
    }
    // стойка и столики
    boxR(x0 + 6, x0 + 13, 0, 1.3, z1 - 4, z1 - 2.8, '#7a5236'); solidRect(x0 + 6, x0 + 13, z1 - 4, z1 - 2.8, 0, 1.3);
    // окна второго этажа на задней/боковых стенах
    for (let k = 0; k < 4; k++) M.box(x0 + 2.5 + k * 4, 8.6, z1 + 0.05, 2.2, 2, 0.12, '#c9b98a');
    // двускатная крыша (визуально) — сплошная коробка до конька
    const ridge = H + 4.2, half = (x1 - x0) / 2 + 0.8;
    const sl = Math.hypot(half, ridge - H), ang = Math.atan2(ridge - H, half);
    M.box(x0 + (x1 - x0) * 0.25 - 0.4, (H + ridge) / 2, (z0 + z1) / 2, sl, 0.5, z1 - z0 + 1.6, CD, { rz: ang });
    M.box(x0 + (x1 - x0) * 0.75 + 0.4, (H + ridge) / 2, (z0 + z1) / 2, sl, 0.5, z1 - z0 + 1.6, CD, { rz: -ang });
    boxR(x0, x1, H, H + 0.4, z0, z1, CD);
    solidRect(x0, x1, z0, z1, H, ridge);
    // треугольные фронтоны (ступеньками)
    for (let k = 0; k < 6; k++) { const yy = H + k * 0.7, w = (x1 - x0) * (1 - k / 6); boxR((x0 + x1) / 2 - w / 2, (x0 + x1) / 2 + w / 2, yy, yy + 0.7, z0 - 0.05, z0 + 0.6, C); boxR((x0 + x1) / 2 - w / 2, (x0 + x1) / 2 + w / 2, yy, yy + 0.7, z1 - 0.6, z1 + 0.05, C); }
    // навес-«маркиза» и вывеска без текста
    boxR(x0 + 1, x1 - 1, 4.6, 4.9, z0 - 2.6, z0, '#c94a3a', { rx: 0.18 });
    boxR(x0 + 4, x1 - 4, 9.1, 10.3, z0 - 0.15, z0 + 0.05, '#e9dcc2');
    // терраса: столики и стулья перед входом
    for (const [tx, tz] of [[36, 18], [43, 18], [36, 25], [43, 25]]) {
      M.cyl(tx, 1.1, tz, 1.3, 0.2, '#e8e2d6', 12); M.box(tx, 0.55, tz, 0.3, 1.1, 0.3, '#3a3b40');
      for (const [cx, cz] of [[-1.9, 0], [1.9, 0]]) { boxR(tx + cx - 0.45, tx + cx + 0.45, 0, 0.75, tz + cz - 0.45, tz + cz + 0.45, '#8a5a32'); boxR(tx + cx + (cx > 0 ? 0.3 : -0.45), tx + cx + (cx > 0 ? 0.45 : -0.3), 0.75, 1.7, tz - 0.45, tz + 0.45, '#8a5a32'); }
      solidCyl(tx, tz, 1.3, 0, 1.2);
    }
  }

  // ---------- Кладбище (запад, между кольцами, к югу от улицы) ----------
  {
    const x0 = -87, x1 = -66, z0 = 10, z1 = 58;
    flatR(x0, x1, z0, z1, '#6b4a2e', 0.09);
    for (let i = 0; i < 26; i++) { const px = r(x0 + 1, x1 - 1), pz = r(z0 + 1, z1 - 1), s = r(0.8, 2); flatR(px - s, px + s, pz - s * 0.6, pz + s * 0.6, rng() < 0.5 ? '#5c3f26' : '#7a5636', 0.1); }
    // ряды надгробий
    for (let row = 0; row < 5; row++) for (let c = 0; c < 4; c++) {
      if (rng() < 0.18) continue;
      const gx = x0 + 3.5 + c * 4.6 + r(-0.4, 0.4), gz = z0 + 6 + row * 8.5 + r(-0.6, 0.6), tilt = r(-0.12, 0.12);
      M.box(gx, 1.0, gz, 1.8, 2.0, 0.55, rng() < 0.5 ? '#8f8f8f' : '#a3a29f', { rz: tilt });
      M.box(gx, 2.05, gz, 1.2, 0.35, 0.55, '#8a8a8a', { rz: tilt });
      M.box(gx, 0.15, gz + 1.4, 1.6, 0.3, 2.2, '#4f3a24');
      solidBox(gx, 0, gz, 1.8, 2.2, 0.6);
    }
    // мёртвые деревья
    const dead = (x, z) => {
      M.box(x, 3.2, z, 0.8, 6.4, 0.8, '#4a3322');
      M.box(x - 1.0, 6.3, z, 0.4, 3.0, 0.4, '#4a3322', { rz: 0.7 }); M.box(x + 1.1, 5.4, z + 0.3, 0.4, 2.6, 0.4, '#4a3322', { rz: -0.8 });
      M.box(x + 0.2, 7.4, z - 0.6, 0.35, 2.4, 0.35, '#4a3322', { rx: 0.5 }); M.box(x - 1.9, 7.6, z, 0.3, 1.4, 0.3, '#4a3322', { rz: -0.3 });
      solidCyl(x, z, 0.5, 0, 6.4);
      camBlock.push({ t: 0, minX: x - 0.5, maxX: x + 0.5, minY: 0, maxY: 6.4, minZ: z - 0.5, maxZ: z + 0.5 });
    };
    dead(-84, 14); dead(-69, 33); dead(-83, 52);
    // забор с красными столбиками и проходом со стороны улицы
    const post = (x, z) => { M.box(x, 0.85, z, 0.42, 1.7, 0.42, '#a8322c'); solidCyl(x, z, 0.25, 0, 1.7); };
    const rail = (ax, az, bx, bz) => { boxR(Math.min(ax, bx) - 0.08, Math.max(ax, bx) + 0.08, 1.15, 1.32, Math.min(az, bz) - 0.08, Math.max(az, bz) + 0.08, '#8a2a24'); boxR(Math.min(ax, bx) - 0.08, Math.max(ax, bx) + 0.08, 0.55, 0.72, Math.min(az, bz) - 0.08, Math.max(az, bz) + 0.08, '#8a2a24'); };
    for (let z = z0; z <= z1 + 0.01; z += 4) { post(x1, z); post(x0, z); if (z + 4 <= z1 + 0.01 && Math.abs(z + 2 - 34) > 4) rail(x1, z, x1, z + 4); if (z + 4 <= z1 + 0.01) rail(x0, z, x0, z + 4); }
    for (let x = x0; x <= x1 + 0.01; x += 3.5) { post(x, z0); post(x, z1); if (x + 3.5 <= x1 + 0.01) { rail(x, z0, x + 3.5, z0); rail(x, z1, x + 3.5, z1); } }
  }

  // ---------- Граница: высокие серые бетонные стены ----------
  const WH = 26;
  for (const s of [-1, 1]) {
    boxR(-WALL - 2, WALL + 2, 0, WH, s * WALL - 2, s * WALL + 2, '#8f8f8d');
    boxR(s * WALL - 2, s * WALL + 2, 0, WH, -WALL - 2, WALL + 2, '#8f8f8d');
    solidRect(-WALL - 2, WALL + 2, s * WALL - 2, s * WALL + 2, 0, WH + 5);
    solidRect(s * WALL - 2, s * WALL + 2, -WALL - 2, WALL + 2, 0, WH + 5);
    // поясные полосы и швы панелей на внутренней стороне, колпак сверху
    for (const y of [6, 13, 20]) {
      boxR(-108, 108, y - 0.25, y + 0.25, s * 108 - 0.2 * s, s * 108, '#7c7c7a');
      boxR(s * 108 - 0.2 * s, s * 108, y - 0.25, y + 0.25, -108, 108, '#7c7c7a');
    }
    for (let a = -96; a <= 96; a += 12) {
      boxR(a - 0.12, a + 0.12, 0, WH, s * 108 - 0.15 * s, s * 108, '#7f7f7d');
      boxR(s * 108 - 0.15 * s, s * 108, 0, WH, a - 0.12, a + 0.12, '#7f7f7d');
    }
    boxR(-WALL - 2.4, WALL + 2.4, WH, WH + 0.7, s * WALL - 2.4, s * WALL + 2.4, '#a2a2a0');
    boxR(s * WALL - 2.4, s * WALL + 2.4, WH, WH + 0.7, -WALL - 2.4, WALL + 2.4, '#a2a2a0');
  }

  // ---------- Город за стеной (дальний план в дымке) + вокзал на севере ----------
  const FCOL = ['#b7ad9c', '#a9a294', '#c2b8a6', '#9f9a92', '#b9b0c4', '#c8bba8'];
  for (let i = 0; i < 52; i++) {
    const a = (i / 52) * Math.PI * 2 + r(-0.04, 0.04);
    const R = r(150, 240), w = r(18, 36), h = r(30, 95);
    FAR.box(Math.cos(a) * R, h / 2, Math.sin(a) * R, w, h, w * r(0.7, 1.3), rpick(FCOL), { ry: -a });
  }
  FAR.box(-20, 15, -140, 90, 30, 46, '#9b9a96'); FAR.box(-20, 31, -140, 94, 2.5, 50, '#86857f'); FAR.box(30, 20, -128, 22, 40, 22, '#dcdcd8');

  const statMat = new THREE.MeshLambertMaterial({ vertexColors: true });
  const stat = new THREE.Mesh(M.build(), statMat);
  stat.receiveShadow = true; stat.castShadow = shadows;
  scene.add(stat);
  const flatMesh = new THREE.Mesh(F.build(), statMat);
  flatMesh.receiveShadow = true;
  scene.add(flatMesh);
  const far = new THREE.Mesh(FAR.build(), statMat);
  scene.add(far);

  // ---------- Небо: тёплая дымка (#C9BBA3 у горизонта → #9E9282 в зените), мягкие белые облака ----------
  const sky = new THREE.Mesh(
    new THREE.SphereGeometry(950, 24, 12),
    new THREE.ShaderMaterial({
      side: THREE.BackSide, depthWrite: false, fog: false,
      uniforms: { top: { value: new THREE.Color('#9E9282') }, mid: { value: new THREE.Color('#bcae97') }, bot: { value: new THREE.Color('#C9BBA3') } },
      vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix*modelViewMatrix*vec4(position,1.); }',
      fragmentShader: 'uniform vec3 top, mid, bot; varying vec3 vP; void main(){ float h = vP.y; vec3 c = h > 0.12 ? mix(mid, top, clamp((h-0.12)/0.7,0.,1.)) : mix(bot, mid, clamp((h+0.02)/0.14,0.,1.)); gl_FragColor = vec4(c,1.); }',
    }),
  );
  sky.renderOrder = -10;
  scene.add(sky);
  const sunDir = new THREE.Vector3(0.42, 0.74, 0.3).normalize();
  const glowTex = canvasTex(64, 64, (g) => {
    const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
    gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.25, 'rgba(255,255,255,.6)'); gr.addColorStop(0.6, 'rgba(255,255,255,.14)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = gr; g.fillRect(0, 0, 64, 64);
  });
  const sun = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex, color: 0xfff0d6, fog: false, depthWrite: false, blending: THREE.AdditiveBlending, transparent: true, opacity: 0.55 }));
  sun.position.copy(sunDir).multiplyScalar(800); sun.scale.setScalar(300);
  const sunCore = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex, color: 0xfffbf0, fog: false, depthWrite: false, transparent: true, opacity: 0.9 }));
  sunCore.position.copy(sun.position); sunCore.scale.setScalar(64);
  scene.add(sun, sunCore);

  const CL = new Merger();
  for (let i = 0; i < 18; i++) {
    const a = r(0, Math.PI * 2), R = r(180, 520), y = r(130, 200);
    const cx = Math.cos(a) * R, cz = Math.sin(a) * R;
    const n = 3 + Math.floor(r(0, 4));
    for (let k = 0; k < n; k++) CL.box(cx + r(-26, 26), y + r(-3, 5), cz + r(-16, 16), r(18, 42), r(6, 11), r(14, 28), '#ffffff');
  }
  const clouds = new THREE.Mesh(CL.build(), new THREE.MeshLambertMaterial({ vertexColors: true, emissive: 0xc9bfae, fog: false, transparent: true, opacity: 0.92 }));
  scene.add(clouds);

  // ---------- Ускоряющая сетка для запросов коллизий ----------
  const GC = 16, GN = Math.ceil(240 / GC), G0 = -120;
  const grid = Array.from({ length: GN * GN }, () => []);
  const gi = (v) => clamp(Math.floor((v - G0) / GC), 0, GN - 1);
  solids.forEach((s, idx) => {
    const minX = s.t === 0 ? s.minX : s.x - s.r, maxX = s.t === 0 ? s.maxX : s.x + s.r;
    const minZ = s.t === 0 ? s.minZ : s.z - s.r, maxZ = s.t === 0 ? s.maxZ : s.z + s.r;
    for (let ix = gi(minX - 2); ix <= gi(maxX + 2); ix++) for (let iz = gi(minZ - 2); iz <= gi(maxZ + 2); iz++) grid[ix * GN + iz].push(idx);
  });
  const cell = (x, z) => grid[gi(x) * GN + gi(z)];

  // ---------- Запросы ----------
  // Временные «полы» (интерьеры доменов высоко над городом): круги {x, z, r, y}
  const floors = [];
  function groundAt(x, z, y) {
    let g = 0;
    for (let i = 0; i < floors.length; i++) {
      const fl = floors[i];
      if (fl.y <= y + STEP && fl.y > g && (x - fl.x) * (x - fl.x) + (z - fl.z) * (z - fl.z) <= fl.r * fl.r) g = fl.y;
    }
    const list = cell(x, z);
    for (let i = 0; i < list.length; i++) {
      const s = solids[list[i]];
      if (s.maxY > y + STEP || s.maxY <= g) continue;
      if (s.t === 0) { if (x >= s.minX && x <= s.maxX && z >= s.minZ && z <= s.maxZ) g = s.maxY; }
      else { const dx = x - s.x, dz = z - s.z; if (dx * dx + dz * dz <= s.r * s.r) g = s.maxY; }
    }
    return g;
  }
  // Выталкивает цилиндр-персонажа из препятствий. Возвращает true, если упёрся.
  function collide(pos, radius, height = 5.2) {
    let hit = false;
    const list = cell(pos.x, pos.z);
    for (let i = 0; i < list.length; i++) {
      const s = solids[list[i]];
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
    for (let i = 0; i < floors.length; i++) {
      const fl = floors[i];
      if (p.y < fl.y + 0.05 && p.y > fl.y - 4 && (p.x - fl.x) * (p.x - fl.x) + (p.z - fl.z) * (p.z - fl.z) <= fl.r * fl.r) return true;
    }
    if (Math.abs(p.x) > WALL + 2 || Math.abs(p.z) > WALL + 2) return true;
    const list = cell(p.x, p.z);
    for (let i = 0; i < list.length; i++) {
      const s = solids[list[i]];
      if (p.y < s.minY || p.y > s.maxY) continue;
      if (s.t === 0) { if (p.x >= s.minX && p.x <= s.maxX && p.z >= s.minZ && p.z <= s.maxZ) return true; }
      else { const dx = p.x - s.x, dz = p.z - s.z; if (dx * dx + dz * dz <= s.r * s.r) return true; }
    }
    return false;
  }
  // Луч для камеры: расстояние до первого препятствия (только крупные блоки)
  const big = solids.filter((s) => s.t === 0 && s.maxY >= 2.5).concat(camBlock);
  function rayDist(o, d, maxLen) {
    let best = maxLen;
    for (let i = 0; i < big.length; i++) {
      const s = big[i];
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

  // Точки появления: на кольцевых дорогах и площади (не под деревьями)
  const spawns = [];
  for (const s of [-1, 1]) {
    spawns.push([s * 12, 0], [0, s * 12], [s * 23, s * 10], [-s * 10, s * 23]);
    spawns.push([s * 57, -30], [s * 57, 30], [-30, s * 57], [30, s * 57], [s * 57, 0], [0, s * 57]);
    spawns.push([s * 96, -50], [s * 96, 50], [-50, s * 96], [50, s * 96], [s * 96, 0], [0, s * 96]);
  }
  const free = spawns.filter(([x, z]) => !trees.some((t) => Math.hypot(t.x - x, t.z - z) < t.r + 2) && groundAt(x, z, 60) < 0.5);

  return {
    solids, groundAt, collide, pointBlocked, rayDist, spawns: free, roam: free, sunDir, clouds,
    addFloor(fl) { floors.push(fl); }, removeFloor(fl) { const i = floors.indexOf(fl); if (i >= 0) floors.splice(i, 1); },
    update(dt) { clouds.rotation.y += dt * 0.004; },
  };
}
