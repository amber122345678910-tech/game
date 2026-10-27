// Пиксельная графика: всё рисуется прямоугольниками, без картинок.
// Персонажи и предметы один раз рисуются в маленький canvas с тёмной обводкой 1px (как в Undertale) и берутся из кэша.
const TILE = 16;
const hsh = (x, y) => (((x * 73856093) ^ (y * 19349663) ^ 0x5bd1e995) >>> 0) % 1000;

function R(c, x, y, w, h, col) {
  c.fillStyle = col;
  c.fillRect(Math.round(x), Math.round(y), w, h);
}

// цвет светлее (k > 0) или темнее (k < 0); понимает #rgb и #rrggbb
const SHADES = new Map();
function pxShade(col, k) {
  const key = col + "/" + k;
  let v = SHADES.get(key);
  if (v) return v;
  let m = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(col || "");
  if (!m) return col;
  let hex = m[1];
  if (hex.length === 3) hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
  const n = parseInt(hex, 16);
  const f = (a) => Math.max(0, Math.min(255, Math.round(k >= 0 ? a + (255 - a) * k : a * (1 + k))));
  v = "#" + ((1 << 24) | (f(n >> 16) << 16) | (f((n >> 8) & 255) << 8) | f(n & 255)).toString(16).slice(1);
  if (SHADES.size > 800) SHADES.clear();
  SHADES.set(key, v);
  return v;
}

// ---------- спрайты с обводкой ----------
const INK = "#0d0b16";
const SPR = { cache: new Map(), raw: false, tmp: null };
const BOX_CH = [-6, -10, 28, 34]; // запас вокруг 16x20 для шляп, пушки и обводки
const BOX_OBJ = [-4, -10, 24, 34];
const BOX_PROP = [-3, -8, 22, 26];
function pxCanvas(w, h) {
  const k = document.createElement("canvas");
  k.width = w;
  k.height = h;
  return k;
}
// силуэт, сдвинутый на s пикселей в 4 стороны, закрашиваем тёмным и кладём спрайт сверху
function pxOutline(dst, src, w, h, ink, s = 1) {
  const g = dst.getContext("2d");
  g.clearRect(0, 0, dst.width, dst.height);
  g.globalCompositeOperation = "source-over";
  g.drawImage(src, 0, 0, w, h, s, 0, w, h);
  g.drawImage(src, 0, 0, w, h, -s, 0, w, h);
  g.drawImage(src, 0, 0, w, h, 0, s, w, h);
  g.drawImage(src, 0, 0, w, h, 0, -s, w, h);
  g.globalCompositeOperation = "source-in";
  g.fillStyle = ink;
  g.fillRect(0, 0, w, h);
  g.globalCompositeOperation = "source-over";
  g.drawImage(src, 0, 0, w, h, 0, 0, w, h);
}
// key — всё, от чего зависит картинка (направление, кадр, цвета)
function sprite(c, key, x, y, draw, box = BOX_CH, ink = INK) {
  if (SPR.raw) { draw(c, x, y); return; }
  let k = SPR.cache.get(key);
  if (!k) {
    const [bx, by, bw, bh] = box;
    if (!SPR.tmp || SPR.tmp.width < bw || SPR.tmp.height < bh) SPR.tmp = pxCanvas(Math.max(bw, 64), Math.max(bh, 96));
    const tg = SPR.tmp.getContext("2d");
    tg.clearRect(0, 0, SPR.tmp.width, SPR.tmp.height);
    draw(tg, -bx, -by);
    k = pxCanvas(bw, bh);
    pxOutline(k, SPR.tmp, bw, bh, ink);
    if (SPR.cache.size >= 500) SPR.cache.delete(SPR.cache.keys().next().value);
    SPR.cache.set(key, k);
  }
  c.drawImage(k, x + box[0], y + box[1]);
}

const ZONE_PAL = {
  lab: {
    g: "#3a3d56", g2: "#34374e", line: "#2c2e42", hi: "#454966", wall: "#1e2033", wallTop: "#4b4f72", deco: "#5c628e", liquid: "#3fd16b", tree: "#2c2e42",
    cap: "#25273c", rim: "#5c628e", face: "#3d4060", faceHi: "#555a82", faceLo: "#1e2033",
  },
  slime: {
    g: "#2f6b3a", g2: "#2b6236", line: "#245530", hi: "#3f8a4a", wall: "#3b2f2a", wallTop: "#5b4a3f", deco: "#9be36b", liquid: "#5ef04a", tree: "#1f4d28",
    cap: "#2c5e34", rim: "#5aa858", face: "#6b5444", faceHi: "#8a6c52", faceLo: "#3b2f2a",
  },
  forest: {
    g: "#1e4a45", g2: "#1b433f", line: "#163a36", hi: "#2a5e56", wall: "#24323a", wallTop: "#3a4f5c", deco: "#7fd8c2", liquid: "#3a8fd6", tree: "#1d5a3c", path: "#5a4a3a",
    cap: "#18332f", rim: "#3f7a6a", face: "#3a4f5c", faceHi: "#506a7a", faceLo: "#202c34",
  },
  loop: {
    g: "#5a5076", g2: "#52496c", line: "#3a3352", hi: "#6e6390", wall: "#2a2238", wallTop: "#7a5a7a", deco: "#f2c46b", liquid: "#5a7ad6", tree: "#3a2a4a", path: "#6d6386",
    cap: "#2f2640", rim: "#8a6a8a", face: "#4a3a5e", faceHi: "#6a5480", faceLo: "#241c30",
  },
  robo: {
    g: "#454b57", g2: "#414753", line: "#30343d", hi: "#5a606e", wall: "#262a33", wallTop: "#69707f", deco: "#ffcf3a", liquid: "#3ad6ff", tree: "#262a33", path: "#5a606e",
    cap: "#2a2e37", rim: "#ffcf3a", face: "#565d6c", faceHi: "#737b8c", faceLo: "#262a33",
  },
  cube: {
    g: "#7b7e8c", g2: "#838695", line: "#6d707d", hi: "#9a9dab", wall: "#3b6fd1", wallTop: "#5b8ff1", deco: "#ffd84a", liquid: "#ff5a1f", tree: "#2f9e44", path: "#9a9dab",
    cap: "#5b8ff1", rim: "#8ab0ff", face: "#3b6fd1", faceHi: "#5b8ff1", faceLo: "#264a99",
  },
  core: {
    g: "#14101f", g2: "#171224", line: "#1f1830", hi: "#2a2140", wall: "#2a0f3a", wallTop: "#5a1f7a", deco: "#ff3a8a", liquid: "#ff3a8a", tree: "#2a0f3a", path: "#221a33",
    cap: "#1a0b26", rim: "#8a2a7a", face: "#2a0f3a", faceHi: "#4a1a66", faceLo: "#0f0618",
  },
};

const SOLID_TILES = new Set(["#", "~", "T", "o", "x", "w", "^", "B"]);

// ---------- тайлы ----------
// nb(dx, dy) — символ соседнего тайла (null — за краем карты). Без nb соседей нет.
const NB_NONE = () => ".";
const isWall = (d) => d === null || d === "#" || d === "w";
const castsShade = (d) => d === "#" || d === "w" || d === "x";

function drawTile(c, ch, x, y, zone, t, tx, ty, nb) {
  const P = ZONE_PAL[zone] || ZONE_PAL.lab;
  const h = hsh(tx, ty);
  const N = nb || NB_NONE;
  switch (ch) {
    case "#":
    case "w":
      return wallTile(c, ch, x, y, zone, P, h, tx, ty, N);
    case "~":
      return liquidTile(c, x, y, P, h, t, tx, ty, N);
    case "^":
      return lavaTile(c, x, y, h, t, tx, ty, N);
    case "x":
      return glitchTile(c, x, y, h, t);
    case "=":
      if (zone === "robo") return beltTile(c, x, y, t, N);
      pathTile(c, x, y, zone, P, h, tx, ty, N);
      break;
    case ",":
      groundTile(c, x, y, zone, P, h, tx, ty);
      decoTile(c, x, y, zone, P, h, N);
      break;
    case "T":
    case "o":
    case "B":
      groundTile(c, x, y, zone, P, h, tx, ty);
      if (!nb) { floorShadow(c, x, y, N); drawProp(c, ch, x, y, zone, tx, ty); return; }
      break;
    default:
      groundTile(c, x, y, zone, P, h, tx, ty);
  }
  floorShadow(c, x, y, N);
}

// мягкая тень на полу под стеной и слева от неё
function floorShadow(c, x, y, N) {
  if (castsShade(N(0, -1))) { R(c, x, y, 16, 2, "rgba(0,0,0,0.3)"); R(c, x, y + 2, 16, 2, "rgba(0,0,0,0.13)"); }
  if (castsShade(N(-1, 0))) R(c, x, y, 2, 16, "rgba(0,0,0,0.13)");
}

function groundTile(c, x, y, zone, P, h, tx, ty) {
  if (zone === "lab") {
    // плитки гаража с фаской
    R(c, x, y, 16, 16, (tx + ty) % 2 ? P.g : P.g2);
    R(c, x, y, 16, 1, P.hi); R(c, x, y, 1, 16, P.hi);
    R(c, x, y + 15, 16, 1, P.line); R(c, x + 15, y, 1, 16, P.line);
    if (h % 9 === 0) { R(c, x + 3, y + 3, 1, 1, P.line); R(c, x + 12, y + 12, 1, 1, P.line); }
    if (h % 13 === 2) { R(c, x + 4 + (h % 5), y + 7, 5, 2, P.line); R(c, x + 5 + (h % 5), y + 6, 2, 1, P.line); }
  } else if (zone === "slime") {
    // трава: пятна, травинки, цветочки
    R(c, x, y, 16, 16, P.g);
    R(c, x + (h % 10), y + ((h >> 3) % 10), 6, 3, P.g2);
    for (let i = 0; i < 3; i++) {
      const k = (h * (i + 3) * 7 + i * 131) % 1000;
      const bx = x + 1 + (k % 13), by = y + 2 + ((k >> 4) % 12);
      R(c, bx, by + 1, 1, 1, P.line); R(c, bx + 1, by, 1, 2, P.hi);
    }
    if (h % 17 === 0) {
      const fx = x + 3 + (h % 9), fy = y + 4 + ((h >> 2) % 8);
      R(c, fx - 1, fy, 3, 1, "#ff8ad0"); R(c, fx, fy - 1, 1, 3, "#ff8ad0"); R(c, fx, fy, 1, 1, "#ffe36b");
    }
  } else if (zone === "forest") {
    // мох, корни, камешки
    R(c, x, y, 16, 16, P.g);
    R(c, x + (h % 9) + 1, y + ((h >> 3) % 9) + 2, 5, 3, P.g2);
    R(c, x + ((h >> 2) % 10) + 2, y + ((h >> 5) % 10) + 1, 3, 1, P.hi);
    if (h % 11 === 4) { R(c, x + 2, y + 9, 6, 1, "#3a2e24"); R(c, x + 7, y + 10, 4, 1, "#3a2e24"); R(c, x + 10, y + 11, 1, 2, "#3a2e24"); }
    if (h % 7 === 1) R(c, x + (h % 12) + 2, y + ((h >> 2) % 12) + 2, 2, 1, "#2f5a54");
    R(c, x + (h % 13) + 1, y + ((h >> 5) % 13) + 1, 1, 1, P.line);
  } else if (zone === "loop") {
    // брусчатка: камни через ряд со сдвигом
    R(c, x, y, 16, 16, P.line);
    const rows = [[0, 4, 0], [5, 5, 4], [11, 4, 0]];
    for (let r = 0; r < 3; r++) {
      const [yy, hh, off] = rows[r];
      for (let sx = -off; sx < 16; sx += 8) {
        const xs = Math.max(0, sx), xe = Math.min(16, sx + 7);
        if (xe <= xs) continue;
        const id = Math.floor((tx * 16 + sx + off) / 8);
        const v = hsh(id, ty * 3 + r) % 3;
        R(c, x + xs, y + yy, xe - xs, hh, v === 0 ? P.g2 : P.g);
        R(c, x + xs, y + yy, xe - xs, 1, v === 2 ? pxShade(P.hi, 0.1) : P.hi);
      }
    }
  } else if (zone === "robo") {
    // стальные плиты с заклёпками
    R(c, x, y, 16, 16, (tx + ty) % 2 ? P.g : P.g2);
    R(c, x, y, 16, 1, P.hi); R(c, x, y, 1, 16, P.hi);
    R(c, x, y + 15, 16, 1, P.line); R(c, x + 15, y, 1, 16, P.line);
    R(c, x + 2, y + 2, 1, 1, "#7a8190"); R(c, x + 13, y + 2, 1, 1, "#7a8190");
    R(c, x + 2, y + 13, 1, 1, "#7a8190"); R(c, x + 13, y + 13, 1, 1, "#7a8190");
    if (h % 4 === 0) for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) R(c, x + 3 + i * 4 + (j % 2) * 2, y + 4 + j * 3, 2, 1, P.line);
    if (h % 9 === 5) { R(c, x + 5, y + 7, 6, 3, "#33373f"); R(c, x + 6, y + 6, 3, 1, "#33373f"); R(c, x + 7, y + 8, 2, 1, "#4a5a7a"); }
  } else if (zone === "cube") {
    // базовая плита Roblox с «шипиками»
    R(c, x, y, 16, 16, P.g);
    for (const sx of [2, 10]) for (const sy of [2, 10]) {
      R(c, x + sx + 1, y + sy, 2, 1, "#878a98");
      R(c, x + sx, y + sy + 3, 4, 1, "#737684");
    }
    R(c, x, y + 15, 16, 1, "#777a88");
  } else if (zone === "core") {
    // пустота с сеткой и мусорными пикселями
    R(c, x, y, 16, 16, (tx + ty) % 2 ? P.g : P.g2);
    R(c, x, y, 16, 1, P.line); R(c, x, y, 1, 16, P.line);
    if (h % 5 === 0) R(c, x + (h % 12) + 2, y + ((h >> 3) % 12) + 2, 1, 1, "#3a2a5a");
    if (h % 7 === 0) R(c, x + (h % 13), y + (h % 11), 2, 2, "#2a1f44");
  } else {
    R(c, x, y, 16, 16, (tx + ty) % 2 ? P.g : P.g2);
    if (h % 5 === 0) R(c, x + (h % 12) + 1, y + ((h >> 3) % 12) + 1, 2, 1, P.line);
  }
}

function pathTile(c, x, y, zone, P, h, tx, ty, N) {
  const pc = P.path || P.g2;
  const isP = (d) => d === "=";
  R(c, x, y, 16, 16, pc);
  if (zone === "loop") {
    // мостовая из кирпичиков
    const mo = pxShade(pc, -0.18), lt = pxShade(pc, 0.12);
    for (let r = 0; r < 4; r++) {
      R(c, x, y + r * 4 + 3, 16, 1, mo);
      R(c, x, y + r * 4, 16, 1, lt);
      const off = r % 2 ? 4 : 0;
      R(c, x + off + 3, y + r * 4, 1, 3, mo);
      R(c, x + off + 11, y + r * 4, 1, 3, mo);
    }
  } else {
    // земляная тропинка с камешками
    const lt = pxShade(pc, 0.14), dk = pxShade(pc, -0.18);
    R(c, x + (h % 11) + 2, y + ((h >> 4) % 11) + 2, 2, 1, lt);
    R(c, x + ((h >> 2) % 9) + 4, y + ((h >> 3) % 9) + 4, 1, 1, dk);
    R(c, x + ((h >> 5) % 12) + 1, y + (h % 12) + 2, 2, 1, dk);
    if (zone === "forest" || zone === "slime") {
      // травяная бахрома по краям
      const gc = P.g;
      for (let i = 0; i < 16; i += 3) {
        const a = (i + h) % 2;
        if (!isP(N(0, -1)) && !isWall(N(0, -1))) R(c, x + i, y, 2, 1 + a, gc);
        if (!isP(N(0, 1)) && !isWall(N(0, 1))) R(c, x + i, y + 15 - a, 2, 1 + a, gc);
        if (!isP(N(-1, 0)) && !isWall(N(-1, 0))) R(c, x, y + i, 1 + a, 2, gc);
        if (!isP(N(1, 0)) && !isWall(N(1, 0))) R(c, x + 15 - a, y + i, 1 + a, 2, gc);
      }
    }
  }
}

function decoTile(c, x, y, zone, P, h, N) {
  if (zone === "lab") {
    // коврик
    const rug = (d) => d === ",";
    R(c, x, y, 16, 16, "#6a2a3a");
    R(c, x + 4, y + 4, 2, 2, "#8a3a4a"); R(c, x + 10, y + 10, 2, 2, "#8a3a4a");
    R(c, x + 10, y + 4, 2, 2, "#5a2232"); R(c, x + 4, y + 10, 2, 2, "#5a2232");
    if (!rug(N(0, -1))) { R(c, x, y, 16, 2, "#a85a4a"); R(c, x, y + 2, 16, 1, "#d8a050"); }
    if (!rug(N(0, 1))) { R(c, x, y + 14, 16, 2, "#a85a4a"); R(c, x, y + 13, 16, 1, "#d8a050"); }
    if (!rug(N(-1, 0))) { R(c, x, y, 2, 16, "#a85a4a"); R(c, x + 2, y + 2, 1, 12, "#d8a050"); }
    if (!rug(N(1, 0))) { R(c, x + 14, y, 2, 16, "#a85a4a"); R(c, x + 13, y + 2, 1, 12, "#d8a050"); }
  } else if (zone === "slime") {
    R(c, x + 4, y + 9, 1, 3, "#5ac85a"); R(c, x + 5, y + 7, 1, 5, "#9be36b"); R(c, x + 6, y + 10, 1, 2, "#5ac85a");
    R(c, x + 10, y + 6, 1, 5, "#4aa84a");
    R(c, x + 9, y + 4, 3, 1, "#ff8ad0"); R(c, x + 10, y + 3, 1, 3, "#ff8ad0"); R(c, x + 10, y + 4, 1, 1, "#ffe36b");
  } else if (zone === "forest") {
    R(c, x + 3, y + 10, 1, 4, "#3f9a6a"); R(c, x + 2, y + 9, 1, 2, "#3f9a6a"); R(c, x + 4, y + 9, 1, 2, "#5fbf8a");
    R(c, x + 5, y + 10, 1, 4, "#5fbf8a");
    R(c, x + 4, y + 8, 3, 2, "#ff8ab0"); R(c, x + 5, y + 8, 1, 1, "#ffe8f0");
    R(c, x + 10, y + 10, 4, 2, "#7fd8c2"); R(c, x + 11, y + 12, 2, 2, "#e8fbff"); R(c, x + 11, y + 10, 1, 1, "#e8fbff");
  } else if (zone === "loop") {
    // клумба
    R(c, x + 4, y + 8, 8, 5, "#3e6a4a"); R(c, x + 5, y + 7, 6, 1, "#4e8a5a"); R(c, x + 4, y + 13, 8, 1, "#2a4a34");
    R(c, x + 5, y + 8, 1, 1, "#ff7aa0"); R(c, x + 8, y + 9, 1, 1, "#ffd84a"); R(c, x + 10, y + 8, 1, 1, "#ff7aa0"); R(c, x + 6, y + 11, 1, 1, "#ffd84a");
  } else if (zone === "robo") {
    R(c, x + 4, y + 8, 8, 3, "#22252c"); R(c, x + 5, y + 7, 6, 1, "#22252c"); R(c, x + 6, y + 8, 2, 1, "#3a5a8a"); R(c, x + 9, y + 9, 1, 1, "#6a4a8a");
    R(c, x + 11, y + 3, 2, 2, "#9aa3b5"); R(c, x + 11, y + 4, 2, 1, "#5a606e");
  } else if (zone === "cube") {
    R(c, x + 3, y + 6, 10, 6, "#e8b923"); R(c, x + 3, y + 6, 10, 1, "#ffd84a"); R(c, x + 3, y + 11, 10, 1, "#a8850f");
    R(c, x + 5, y + 7, 2, 2, "#ffe36b"); R(c, x + 9, y + 7, 2, 2, "#ffe36b");
  } else if (zone === "core") {
    R(c, x + 6, y + 6, 2, 6, "#8a2a7a"); R(c, x + 7, y + 4, 1, 2, "#ff3a8a"); R(c, x + 9, y + 9, 2, 3, "#5a1f7a"); R(c, x + 9, y + 8, 1, 1, "#c03aff");
  } else R(c, x + 6, y + 7, 3, 2, P.deco);
}

function wallTile(c, ch, x, y, zone, P, h, tx, ty, N) {
  const face = !isWall(N(0, 1));
  const edge = N(-1, 0) === null || N(1, 0) === null || N(0, -1) === null || N(0, 1) === null;
  if (zone === "loop" && !edge) return houseTile(c, ch, x, y, h, N, face);
  if (zone === "cube") return brickTile(c, x, y, tx, ty, N, face);
  const top = !isWall(N(0, -1)), lf = !isWall(N(-1, 0)), rt = !isWall(N(1, 0));
  const side = zone === "robo" ? "#737b8c" : P.rim;
  const rimD = pxShade(side, -0.35);
  const capH = face ? 5 : 16;
  // верх стены
  R(c, x, y, 16, capH, P.cap);
  capTexture(c, x, y, zone, P, h, capH);
  if (zone === "robo" && top) {
    for (let i = 0; i < 16; i += 4) { R(c, x + i, y, 2, 2, "#ffcf3a"); R(c, x + i + 2, y, 2, 2, "#1b1e25"); }
  } else if (top) R(c, x, y, 16, 1, P.rim);
  if (lf) R(c, x, y, 1, capH, side);
  if (rt) R(c, x + 15, y, 1, capH, rimD);
  if (!face) return;
  // лицевая сторона
  R(c, x, y + 5, 16, 1, P.faceHi);
  R(c, x, y + 6, 16, 10, P.face);
  faceTexture(c, x, y, zone, P, h, N);
  R(c, x, y + 15, 16, 1, P.faceLo);
  if (lf) R(c, x, y + 5, 1, 11, P.faceHi);
  if (rt) R(c, x + 15, y + 5, 1, 11, P.faceLo);
  if (ch === "w") {
    R(c, x + 3, y + 6, 10, 8, P.faceLo);
    R(c, x + 4, y + 7, 8, 6, "#9fd3ff");
    R(c, x + 4, y + 7, 8, 2, "#d8f0ff");
    R(c, x + 7, y + 7, 1, 6, P.faceLo);
  }
}

function capTexture(c, x, y, zone, P, h, hh) {
  const lt = pxShade(P.cap, 0.08), dk = pxShade(P.cap, -0.25);
  if (zone === "slime") {
    // трава на обрыве
    for (let i = 0; i < 4; i++) { const k = (h * (i + 2) * 13) % 1000; R(c, x + (k % 14) + 1, y + 1 + ((k >> 4) % Math.max(1, hh - 2)), 1, 1, P.rim); }
  } else if (zone === "forest") {
    R(c, x + (h % 10) + 1, y + 1 + ((h >> 3) % Math.max(1, hh - 2)), 4, 1, lt);
    if (hh > 5) R(c, x + ((h >> 2) % 9) + 3, y + 8 + (h % 5), 3, 2, lt);
  } else if (zone === "core") {
    if (h % 3 === 0) R(c, x + (h % 13) + 1, y + 1 + ((h >> 4) % Math.max(1, hh - 2)), 1, 1, "#5a1f7a");
  } else if (hh > 5) {
    // плоский верх стены: редкие швы
    R(c, x, y + 8, 16, 1, dk);
    if (h % 2) R(c, x + 7, y, 1, 8, dk); else R(c, x + 7, y + 9, 1, 7, dk);
    R(c, x + 2, y + 2, 1, 1, lt);
  }
}

function faceTexture(c, x, y, zone, P, h, N) {
  const lo = pxShade(P.face, -0.22), hi = P.faceHi;
  if (zone === "lab") {
    // металлические панели гаража и плинтус
    R(c, x + 7, y + 6, 1, 7, lo); R(c, x + 8, y + 6, 1, 7, hi);
    R(c, x + 15, y + 6, 1, 7, lo);
    R(c, x, y + 13, 16, 2, P.faceLo);
    R(c, x + 2, y + 8, 1, 1, hi); R(c, x + 11, y + 8, 1, 1, hi);
    if (h % 7 === 0) { R(c, x + 11, y + 5, 2, 8, "#2c2e42"); R(c, x + 11, y + 5, 1, 8, "#5c628e"); }
  } else if (zone === "slime") {
    // земляной обрыв: слои и камешки, свисает трава
    R(c, x, y + 9 + (h % 2), 16, 1, lo);
    R(c, x, y + 13 - (h % 2), 16, 1, lo);
    R(c, x + (h % 12) + 1, y + 7 + ((h >> 3) % 5), 2, 1, hi);
    R(c, x + ((h >> 2) % 12) + 2, y + 11, 1, 1, hi);
    R(c, x, y + 5, 16, 1, pxShade(P.cap, -0.2));
    R(c, x + (h % 5) + 1, y + 6, 2, 2, P.cap); R(c, x + (h % 7) + 8, y + 6, 1, 3, P.cap);
  } else if (zone === "robo") {
    R(c, x + 1, y + 7, 14, 7, pxShade(P.face, 0.06));
    R(c, x + 1, y + 7, 14, 1, hi); R(c, x + 1, y + 13, 14, 1, lo);
    R(c, x + 2, y + 8, 1, 1, "#9aa3b5"); R(c, x + 13, y + 12, 1, 1, "#9aa3b5");
    if (h % 3 === 0) { R(c, x + 11, y + 7, 4, 4, "#1b1e25"); R(c, x + 12, y + 8, 2, 2, "#1f6b3a"); }
    if (h % 4 === 1) for (let i = 0; i < 14; i += 4) { R(c, x + 1 + i, y + 12, 2, 1, "#ffcf3a"); R(c, x + 3 + i, y + 12, 2, 1, "#1b1e25"); }
  } else if (zone === "core") {
    // тёмный кристалл с дорожками схемы
    R(c, x + 2, y + 8, 6, 1, hi); R(c, x + 7, y + 8, 1, 4, hi); R(c, x + 7, y + 11, 6, 1, hi);
    R(c, x + 2, y + 8, 1, 1, "#8a2a7a"); R(c, x + 12, y + 11, 1, 1, "#8a2a7a");
    if (h % 2) { R(c, x + 10, y + 6, 1, 3, lo); R(c, x + 4, y + 12, 3, 1, lo); }
  } else {
    // каменная кладка (лес, Петля)
    const off = h % 2 ? 4 : 0;
    R(c, x, y + 9, 16, 1, P.faceLo); R(c, x, y + 12, 16, 1, P.faceLo);
    R(c, x + off + 3, y + 6, 1, 3, P.faceLo); R(c, x + off + 11, y + 6, 1, 3, P.faceLo);
    R(c, x + 7 - off, y + 10, 1, 2, P.faceLo); R(c, x + 15 - off, y + 10, 1, 2, P.faceLo);
    R(c, x + off + 5, y + 13, 1, 2, P.faceLo);
    R(c, x + 1, y + 6, 2, 1, hi); R(c, x + 9, y + 10, 2, 1, hi);
    if (zone === "forest") { R(c, x + (h % 9) + 2, y + 6, 3, 1, P.rim); R(c, x + (h % 9) + 3, y + 7, 1, 2, P.rim); }
  }
}

// дома в Городке Петля: крыша из черепицы и фасад
function houseTile(c, ch, x, y, h, N, face) {
  const roof = "#8e3a5c", roofL = "#b4527a", roofD = "#5e2440";
  if (!face) {
    R(c, x, y, 16, 16, roof);
    for (let r = 0; r < 4; r++) {
      const yy = y + r * 4;
      R(c, x, yy + 3, 16, 1, roofD);
      R(c, x, yy, 16, 1, roofL);
      for (let i = r % 2 ? 2 : 0; i < 16; i += 4) R(c, x + i, yy + 1, 1, 2, roofD);
    }
    if (!isWall(N(0, -1))) R(c, x, y, 16, 1, "#d87a9a");
    if (!isWall(N(-1, 0))) R(c, x, y, 1, 16, roofD);
    if (!isWall(N(1, 0))) R(c, x + 15, y, 1, 16, roofD);
    if (ch === "w") {
      R(c, x + 3, y + 3, 10, 2, roofD);
      R(c, x + 4, y + 5, 8, 9, "#5a3a3a");
      R(c, x + 5, y + 6, 6, 7, "#ffd27a");
      R(c, x + 5, y + 6, 6, 2, "#fff0b8");
      R(c, x + 7, y + 6, 2, 7, "#5a3a3a");
      R(c, x + 5, y + 9, 6, 1, "#5a3a3a");
    }
    return;
  }
  R(c, x, y, 16, 3, roofD);
  R(c, x, y + 3, 16, 13, "#d8c8a8");
  R(c, x, y + 3, 16, 1, "#a8987a");
  R(c, x, y + 15, 16, 1, "#8a7a5a");
  if (!isWall(N(-1, 0))) R(c, x, y + 3, 2, 13, "#5a3a3a");
  if (!isWall(N(1, 0))) R(c, x + 14, y + 3, 2, 13, "#5a3a3a");
  if (N(0, -1) === "w") {
    // дверь под окном-мансардой
    R(c, x + 4, y + 5, 8, 11, "#5a3a3a");
    R(c, x + 5, y + 6, 6, 10, "#8a5a3a");
    R(c, x + 5, y + 6, 6, 1, "#a8744a");
    R(c, x + 7, y + 7, 2, 8, "#7a4a2a");
    R(c, x + 10, y + 11, 1, 1, "#ffd27a");
  } else if (ch === "w" || h % 3 !== 1) {
    R(c, x + 4, y + 5, 8, 7, "#5a3a3a");
    R(c, x + 5, y + 6, 6, 5, "#ffd27a");
    R(c, x + 5, y + 6, 3, 2, "#fff0b8");
    R(c, x + 7, y + 6, 1, 5, "#5a3a3a"); R(c, x + 5, y + 8, 6, 1, "#5a3a3a");
    R(c, x + 4, y + 12, 8, 2, "#7a4a3a");
    R(c, x + 5, y + 11, 1, 1, "#ff6a8a"); R(c, x + 8, y + 11, 1, 1, "#ffd84a"); R(c, x + 10, y + 11, 1, 1, "#ff6a8a");
  } else {
    R(c, x, y + 8, 16, 1, "#5a3a3a");
    R(c, x + 4, y + 3, 1, 12, "#5a3a3a"); R(c, x + 11, y + 3, 1, 12, "#5a3a3a");
  }
}

// цветные кубики Кубограда
function brickTile(c, x, y, tx, ty, N, face) {
  const col = ["#3b6fd1", "#d13b3b", "#2f9e44", "#e8b923"][hsh(tx >> 1, ty) % 4];
  const top = pxShade(col, 0.2), stud = pxShade(col, 0.35), dk = pxShade(col, -0.35), sd = pxShade(col, -0.15);
  const studAt = (sx, sy) => { R(c, sx, sy, 4, 3, stud); R(c, sx + 1, sy, 2, 1, pxShade(col, 0.55)); R(c, sx, sy + 3, 4, 1, sd); };
  if (!face) {
    R(c, x, y, 16, 16, top);
    studAt(x + 2, y + 2); studAt(x + 10, y + 2); studAt(x + 2, y + 10); studAt(x + 10, y + 10);
    if (!isWall(N(0, -1))) R(c, x, y, 16, 1, pxShade(col, 0.5));
    if (!isWall(N(-1, 0))) R(c, x, y, 1, 16, sd);
    if (!isWall(N(1, 0))) R(c, x + 15, y, 1, 16, dk);
    return;
  }
  R(c, x, y, 16, 6, top);
  studAt(x + 2, y + 1); studAt(x + 10, y + 1);
  if (!isWall(N(0, -1))) R(c, x, y, 16, 1, pxShade(col, 0.5));
  R(c, x, y + 6, 16, 10, col);
  R(c, x, y + 6, 16, 1, pxShade(col, 0.3));
  R(c, x + 1, y + 8, 3, 1, pxShade(col, 0.15));
  R(c, x, y + 14, 16, 2, sd);
  R(c, x, y + 15, 16, 1, dk);
  if (!isWall(N(-1, 0))) R(c, x, y, 1, 16, sd);
  if (!isWall(N(1, 0))) R(c, x + 15, y, 1, 16, dk);
}

// живые тайлы: жидкость, лава, стена Глюка, конвейер
function liquidTile(c, x, y, P, h, t, tx, ty, N) {
  const L = P.liquid;
  const d1 = pxShade(L, -0.16), d2 = pxShade(L, -0.42), l1 = pxShade(L, 0.42), l2 = pxShade(L, 0.75);
  const lq = (d) => d === "~" || d === null;
  // в середине глубже, у берегов мелко и светлее
  R(c, x, y, 16, 16, d1);
  if (!lq(N(0, -1))) R(c, x, y, 16, 6, L);
  if (!lq(N(0, 1))) R(c, x, y + 11, 16, 5, L);
  if (!lq(N(-1, 0))) R(c, x, y, 4, 16, L);
  if (!lq(N(1, 0))) R(c, x + 12, y, 4, 16, L);
  if (h % 2) R(c, x + (h % 9), y + 7 + ((h >> 4) % 4), 6, 1, pxShade(L, -0.24));
  // волны: блик и тень под ним
  const k = Math.floor(t * 2 + (tx + ty) * 0.7) % 4;
  R(c, x + 2 + k * 2, y + 5, 4, 1, l1);
  R(c, x + 3 + k * 2, y + 6, 3, 1, d1);
  if (h % 3 !== 1) R(c, x + 9 - k, y + 11, 3, 1, l1);
  // пузыри
  if (h % 3 === 0) {
    const ph = (t * 0.7 + h / 97) % 1;
    const bx = x + 3 + (h % 9), by = y + 13 - Math.floor(ph * 9);
    if (ph < 0.82) { R(c, bx, by, 2, 2, l1); R(c, bx, by, 1, 1, l2); }
    else { R(c, bx - 1, by, 1, 1, l2); R(c, bx + 2, by, 1, 1, l2); R(c, bx, by - 1, 2, 1, l2); }
  }
  // берега
  if (!lq(N(0, -1))) { R(c, x, y, 16, 2, d2); R(c, x, y + 2, 16, 1, l1); }
  if (!lq(N(0, 1))) R(c, x, y + 15, 16, 1, l2);
  if (!lq(N(-1, 0))) R(c, x, y, 1, 16, l1);
  if (!lq(N(1, 0))) R(c, x + 15, y, 1, 16, d1);
  if (castsShade(N(0, -1))) R(c, x, y, 16, 3, "rgba(0,0,0,0.25)");
}

function lavaTile(c, x, y, h, t, tx, ty, N) {
  const lv = (d) => d === "^" || d === null;
  R(c, x, y, 16, 16, "#ff5a1f");
  const s = Math.floor(t * 2 + tx * 3);
  R(c, x + ((s + h) % 11), y + 2 + (h % 4), 5, 2, "#d23c12");
  R(c, x + ((s * 2 + 7 + h) % 10) + 1, y + 9 + (h % 4), 5, 2, "#d23c12");
  R(c, x + ((s + h) % 11) + 1, y + 2 + (h % 4), 2, 1, "#ff8a3a");
  const k = Math.floor(t * 3 + tx) % 3;
  R(c, x + 2 + k * 3, y + 6 + (h % 3), 3, 1, "#ffd84a");
  R(c, x + 10 - k * 2, y + 12, 3, 1, "#ffb03a");
  if (h % 2 === 0) {
    const ph = (t * 0.9 + h / 89) % 1;
    if (ph > 0.55) {
      const r = ph > 0.88 ? 3 : 2;
      R(c, x + 4 + (h % 7), y + 6 + (h % 5), r, r, "#ffe36b");
      if (ph > 0.88) R(c, x + 5 + (h % 7), y + 7 + (h % 5), 1, 1, "#fff8d0");
    }
  }
  if (!lv(N(0, -1))) { R(c, x, y, 16, 2, "#7a2a10"); R(c, x, y + 2, 16, 1, "#ffb03a"); }
  if (!lv(N(0, 1))) R(c, x, y + 15, 16, 1, "#ffd84a");
  if (!lv(N(-1, 0))) R(c, x, y, 1, 16, "#c43a12");
  if (!lv(N(1, 0))) R(c, x + 15, y, 1, 16, "#c43a12");
}

function glitchTile(c, x, y, h, t) {
  const f = Math.floor(t * 8);
  R(c, x, y, 16, 16, "#120a1c");
  for (let j = 1; j < 16; j += 3) R(c, x, y + j, 16, 1, "#1c1030");
  for (let i = 0; i < 6; i++) {
    const k = (h + i * 37 + f * 13) % 1000;
    R(c, x + (k % 14), y + ((k >> 4) % 14), 2 + (k % 3), 2, ["#ff3a8a", "#3affd8", "#ffe03a", "#8a3aff"][k % 4]);
  }
  if ((f + h) % 11 === 0) R(c, x, y + (h % 13), 16, 2, "#ff3a8a");
  if ((f + h) % 13 === 5) R(c, x, y + ((h >> 3) % 13), 16, 1, "#3affd8");
  R(c, x, y, 16, 1, "#2a1440");
  R(c, x, y + 15, 16, 1, "#08040e");
}

function beltTile(c, x, y, t, N) {
  R(c, x, y, 16, 16, "#2a2e37");
  const k = Math.floor(t * 12) % 4;
  for (let i = 0; i < 4; i++) { const sx = x + ((i * 4 + k) % 16); R(c, sx, y + 4, 2, 9, "#3f4450"); R(c, sx, y + 4, 1, 9, "#4c5260"); }
  R(c, x, y, 16, 3, "#69707f"); R(c, x, y, 16, 1, "#8a92a3"); R(c, x, y + 3, 16, 1, "#1b1e25");
  R(c, x, y + 13, 16, 1, "#1b1e25"); R(c, x, y + 14, 16, 2, "#4c5260");
  const r = Math.floor(t * 12) % 8;
  R(c, x + r, y + 1, 1, 1, "#c8d0dc"); R(c, x + ((r + 8) % 16), y + 1, 1, 1, "#c8d0dc");
  if (castsShade(N(0, -1))) R(c, x, y, 16, 3, "rgba(0,0,0,0.25)");
}

// какие тайлы живые: 1 — перерисовать целиком, 2 — только мелкие детали поверх
function tileAnim(ch, zone, tx, ty, nb) {
  if (ch === "~" || ch === "^" || ch === "x") return 1;
  if (ch === "=" && zone === "robo") return 1;
  const h = hsh(tx, ty);
  const N = nb || NB_NONE;
  if (ch === "#" && zone === "robo" && h % 3 === 0 && !isWall(N(0, 1))) return 2;
  if (ch === "#" && zone === "core" && !isWall(N(0, 1))) return 2;
  if (zone === "core" && !SOLID_TILES.has(ch) && h % 7 === 0) return 2;
  return 0;
}
function drawTileFx(c, ch, x, y, zone, t, tx, ty) {
  const h = hsh(tx, ty);
  if (zone === "robo") { R(c, x + 12, y + 8, 2, 2, Math.floor(t * 2 + h) % 2 ? "#3aff7a" : "#1f6b3a"); return; }
  if (zone === "core") {
    if (ch === "#") { if ((Math.floor(t * 4) + h) % 9 === 0) R(c, x + 2, y + 9, 12, 1, "#ff3a8a"); return; }
    R(c, x + (h % 13), y + (h % 11), 2, 2, (Math.floor(t * 3) + h) % 3 ? "#2a1f44" : "#ff3a8a");
  }
}

// ---------- деревья, камни, шкафы (с обводкой) ----------
function drawProp(c, ch, x, y, zone, tx, ty, noShadow) {
  const P = ZONE_PAL[zone] || ZONE_PAL.lab;
  const v = hsh(tx, ty) % 3;
  x = Math.round(x); y = Math.round(y);
  if (!noShadow) {
    c.fillStyle = "rgba(0,0,0,0.25)";
    c.fillRect(x + 3, y + 14, 10, 2);
    c.fillRect(x + 2, y + 15, 12, 1);
  }
  sprite(c, "pr" + zone + ch + v, x, y, (g, X, Y) => propBody(g, ch, X, Y, zone, P, v), BOX_PROP);
}

function propBody(c, ch, x, y, zone, P, v) {
  if (ch === "B") {
    // шкаф с книгами
    R(c, x + 1, y + 1, 14, 14, "#5a3b2a");
    R(c, x + 1, y + 1, 14, 2, "#7a5640");
    R(c, x + 14, y + 3, 1, 12, "#43291c");
    for (const sy of [3, 8]) {
      R(c, x + 2, y + sy, 12, 4, "#2a1810");
      const books = ["#d65a5a", "#5ad66b", "#5a8ad6", "#e8c35a", "#c05ad6"];
      for (let i = 0; i < 5; i++) {
        const bh = 3 + ((i + sy + v) % 2);
        R(c, x + 3 + i * 2, y + sy + 4 - bh, 2, bh, books[(i + sy + v) % 5]);
        R(c, x + 3 + i * 2, y + sy + 4 - bh, 1, 1, "rgba(255,255,255,0.35)");
      }
      R(c, x + 2, y + sy + 4, 12, 1, "#7a5640");
    }
    R(c, x + 2, y + 13, 12, 2, "#43291c");
    return;
  }
  if (ch === "o") {
    if (zone === "robo") {
      if (v === 2) {
        // ящик
        R(c, x + 2, y + 3, 12, 12, "#8a6a3a");
        R(c, x + 2, y + 3, 12, 1, "#aa8a52"); R(c, x + 2, y + 14, 12, 1, "#5a4422");
        R(c, x + 2, y + 3, 1, 12, "#5a4422"); R(c, x + 13, y + 3, 1, 12, "#5a4422");
        for (let i = 0; i < 9; i++) { R(c, x + 3 + i, y + 4 + i, 2, 1, "#6a4e28"); R(c, x + 11 - i, y + 4 + i, 2, 1, "#6a4e28"); }
      } else {
        // бочка
        const bc = v ? "#3a6a9a" : "#9a3a3a";
        R(c, x + 3, y + 3, 10, 12, bc);
        R(c, x + 4, y + 2, 8, 2, pxShade(bc, 0.3)); R(c, x + 5, y + 2, 6, 1, pxShade(bc, -0.3));
        R(c, x + 3, y + 6, 10, 1, pxShade(bc, -0.35)); R(c, x + 3, y + 11, 10, 1, pxShade(bc, -0.35));
        R(c, x + 5, y + 4, 1, 10, pxShade(bc, 0.35)); R(c, x + 11, y + 4, 2, 11, pxShade(bc, -0.2));
        R(c, x + 6, y + 7, 4, 3, "#ffcf3a"); R(c, x + 7, y + 8, 2, 1, "#1b1e25");
      }
      return;
    }
    if (zone === "cube") {
      R(c, x + 2, y + 6, 12, 9, "#a3a2a5");
      R(c, x + 2, y + 2, 12, 4, "#c3c2c5");
      R(c, x + 3, y + 3, 3, 2, "#d8d7da"); R(c, x + 10, y + 3, 3, 2, "#d8d7da");
      R(c, x + 2, y + 6, 12, 1, "#e0dfe2"); R(c, x + 11, y + 7, 3, 8, "#8a898c");
      return;
    }
    // валун
    const b = "#6c6a7a", lt = "#8e8ca0", dk = "#4e4c5c";
    R(c, x + 4, y + 4, 8, 1, b); R(c, x + 3, y + 5, 10, 1, b); R(c, x + 2, y + 6, 12, 8, b); R(c, x + 3, y + 14, 10, 1, b);
    R(c, x + 4, y + 5, 4, 1, lt); R(c, x + 3, y + 6, 3, 3, lt); R(c, x + 6, y + 6, 2, 1, lt);
    R(c, x + 11, y + 8, 3, 6, dk); R(c, x + 4, y + 13, 9, 1, dk);
    R(c, x + 8, y + 8, 1, 3, dk); R(c, x + 9, y + 10, 1, 2, dk);
    if (zone === "slime") { R(c, x + 4, y + 4, 5, 1, "#5aa858"); R(c, x + 3, y + 5, 3, 1, "#9be36b"); }
    return;
  }
  // T
  if (zone === "slime") {
    // гигантский гриб
    const cap = ["#d6457a", "#e0703a", "#8a45d6"][v], capL = pxShade(cap, 0.3), capD = pxShade(cap, -0.35);
    R(c, x + 6, y + 8, 4, 8, "#e9dcc0"); R(c, x + 9, y + 8, 1, 8, "#c9b89a"); R(c, x + 6, y + 8, 1, 8, "#fff6e0");
    R(c, x + 1, y + 3, 14, 6, cap); R(c, x + 3, y + 1, 10, 2, cap); R(c, x + 5, y, 6, 1, cap);
    R(c, x + 3, y + 1, 4, 1, capL); R(c, x + 2, y + 3, 2, 2, capL);
    R(c, x + 2, y + 8, 12, 1, capD); R(c, x + 12, y + 3, 3, 5, capD);
    R(c, x + 4, y + 4, 2, 2, "#ffd0e3"); R(c, x + 10, y + 2, 2, 2, "#ffd0e3"); R(c, x + 7, y + 5, 2, 1, "#ffd0e3");
    return;
  }
  if (zone === "cube") {
    // кубическое дерево
    R(c, x + 6, y + 10, 4, 6, "#7c5c46"); R(c, x + 9, y + 10, 1, 6, "#5a4232");
    R(c, x + 1, y + 1, 14, 10, "#2f9e44");
    R(c, x + 1, y + 1, 14, 3, "#4fbe64");
    R(c, x + 3, y + 1, 3, 2, "#6fd884"); R(c, x + 10, y + 1, 3, 2, "#6fd884");
    R(c, x + 11, y + 4, 4, 7, "#24803a"); R(c, x + 1, y + 10, 14, 1, "#1c6a30");
    return;
  }
  const tr = v === 1 ? pxShade(P.tree, 0.1) : P.tree;
  const tL = pxShade(tr, 0.28), tD = pxShade(tr, -0.32);
  if (v === 2 && zone === "forest") {
    // круглое дерево
    R(c, x + 7, y + 11, 3, 5, "#4a3424"); R(c, x + 9, y + 11, 1, 5, "#33241a");
    R(c, x + 3, y, 10, 2, tr); R(c, x + 1, y + 2, 14, 8, tr); R(c, x + 2, y + 10, 12, 2, tr);
    R(c, x + 3, y + 1, 4, 2, tL); R(c, x + 2, y + 3, 3, 3, tL);
    R(c, x + 11, y + 4, 4, 6, tD); R(c, x + 3, y + 11, 11, 1, tD);
    R(c, x + 6, y + 5, 1, 1, "#ff8ab0"); R(c, x + 10, y + 3, 1, 1, "#ff8ab0"); R(c, x + 8, y + 8, 1, 1, "#ff8ab0");
    return;
  }
  // ёлка в три яруса
  R(c, x + 7, y + 12, 3, 4, "#4a3424"); R(c, x + 9, y + 12, 1, 4, "#33241a");
  R(c, x + 3, y + 7, 10, 1, tr); R(c, x + 2, y + 8, 12, 1, tr); R(c, x + 1, y + 9, 14, 3, tr);
  R(c, x + 1, y + 11, 14, 1, tD); R(c, x + 11, y + 8, 4, 3, tD); R(c, x + 2, y + 9, 3, 1, tL);
  R(c, x + 4, y + 3, 8, 1, tr); R(c, x + 3, y + 4, 10, 3, tr);
  R(c, x + 3, y + 6, 10, 1, tD); R(c, x + 10, y + 4, 3, 2, tD); R(c, x + 4, y + 4, 2, 1, tL);
  R(c, x + 7, y - 2, 2, 1, tr); R(c, x + 6, y - 1, 4, 2, tr); R(c, x + 5, y + 1, 6, 2, tr);
  R(c, x + 5, y + 2, 6, 1, tD); R(c, x + 9, y, 1, 2, tD); R(c, x + 6, y, 1, 1, tL);
  if (zone === "forest" && v === 1) { R(c, x + 4, y + 10, 1, 1, "#ffe36b"); R(c, x + 9, y + 5, 1, 1, "#ff8ab0"); }
}

// ---------- персонажи ----------
function shadow(c, x, y, w) {
  if (SPR.raw) return;
  const l = Math.round(x + 8 - w / 2), t = Math.round(y + 18);
  c.fillStyle = "rgba(0,0,0,0.26)";
  c.fillRect(l + 1, t - 1, w - 2, 1);
  c.fillRect(l, t, w, 2);
  c.fillRect(l + 2, t + 2, w - 4, 1);
}

function drawHat(c, x, y, hat, dir) {
  if (!hat || hat === "none") return;
  if (hat === "crown") {
    R(c, x + 4, y - 3, 8, 3, "#ffd84a");
    R(c, x + 4, y - 5, 2, 2, "#ffd84a"); R(c, x + 7, y - 5, 2, 2, "#ffd84a"); R(c, x + 10, y - 5, 2, 2, "#ffd84a");
    R(c, x + 4, y - 1, 8, 1, "#c8961a");
    R(c, x + 7, y - 2, 2, 1, "#e0425a");
  } else if (hat === "cap") {
    R(c, x + 3, y - 1, 10, 3, "#e0425a");
    R(c, x + 4, y - 1, 4, 1, "#f2707e");
    if (dir !== "up") R(c, dir === "left" ? x : x + 9, y + 1, 7, 2, "#b5223a");
  } else if (hat === "wizard") {
    R(c, x + 3, y, 10, 2, "#5a3ad6");
    R(c, x + 5, y - 3, 6, 3, "#5a3ad6");
    R(c, x + 7, y - 6, 3, 3, "#5a3ad6");
    R(c, x + 5, y - 3, 2, 3, "#7a5af0");
    R(c, x + 7, y - 2, 1, 1, "#ffe36b"); R(c, x + 9, y - 4, 1, 1, "#ffe36b");
  } else if (hat === "horns") {
    R(c, x + 3, y - 2, 2, 3, "#f2f2f2"); R(c, x + 11, y - 2, 2, 3, "#f2f2f2");
    R(c, x + 3, y - 2, 1, 1, "#c8c8d0"); R(c, x + 12, y - 2, 1, 1, "#c8c8d0");
  } else if (hat === "tophat") {
    R(c, x + 3, y, 10, 2, "#1a1a22");
    R(c, x + 5, y - 5, 6, 5, "#1a1a22");
    R(c, x + 5, y - 5, 1, 5, "#3a3a48");
    R(c, x + 5, y - 2, 6, 1, "#c03a3a");
  } else if (hat === "antenna") {
    R(c, x + 7, y - 4, 1, 4, "#9aa"); R(c, x + 6, y - 6, 3, 2, "#ff3a3a"); R(c, x + 6, y - 6, 1, 1, "#ffb0b0");
  }
}

// ребёнок-стажёр (и жители): 16x20
function drawKid(c, x, y, dir, step, o = {}) {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 10);
  const key = "kid" + dir + (step ? 1 : 0) + "|" + (o.skin || "") + "|" + (o.hair || "") + "|" + (o.shirt || "") + "|" + (o.pants || "") + "|" + (o.stripe || "") + "|" + (o.hat || "");
  sprite(c, key, x, y, (g, X, Y) => kidBody(g, X, Y, dir, step, o));
}
function kidBody(c, x, y, dir, step, o) {
  const skin = o.skin || "#f2c9a0";
  const hair = o.hair || "#5a3a22";
  const shirt = o.shirt || "#3a8ef0";
  const pants = o.pants || "#2a2f5a";
  const shirtD = pxShade(shirt, -0.3), shirtL = pxShade(shirt, 0.22);
  const hairL = pxShade(hair, 0.3), hairD = pxShade(hair, -0.25);
  const skinD = pxShade(skin, -0.14);
  const shoe = "#24202c";
  const b = step ? 1 : 0;
  // ноги
  if (dir === "left" || dir === "right") {
    R(c, x + 6, y + 16, 2, 3 - b, pants); R(c, x + 6, y + 19 - b, 3, 1, shoe);
    R(c, x + 9, y + 16, 2, 3 - (1 - b), pants); R(c, x + 9, y + 19 - (1 - b), 3, 1, shoe);
  } else {
    R(c, x + 5, y + 16, 2, 3 - b, pants); R(c, x + 5, y + 19 - b, 2, 1, shoe);
    R(c, x + 9, y + 16, 2, 3 - (1 - b), pants); R(c, x + 9, y + 19 - (1 - b), 2, 1, shoe);
  }
  // тело
  R(c, x + 4, y + 10, 8, 6, shirt);
  R(c, x + 4, y + 10, 8, 1, shirtL);
  R(c, x + 4, y + 15, 8, 1, shirtD);
  R(c, x + 11, y + 11, 1, 4, shirtD);
  if (o.stripe) R(c, x + 4, y + 12, 8, 1, o.stripe);
  // руки
  if (dir === "left") { R(c, x + 6, y + 11 + b, 2, 3, shirtD); R(c, x + 6, y + 14 + b, 2, 1, skin); }
  else if (dir === "right") { R(c, x + 8, y + 11 + b, 2, 3, shirtD); R(c, x + 8, y + 14 + b, 2, 1, skin); }
  else { R(c, x + 2, y + 10 + b, 2, 5, shirt); R(c, x + 12, y + 11 - b, 2, 5, shirtD); R(c, x + 2, y + 14 + b, 2, 1, skin); R(c, x + 12, y + 15 - b, 2, 1, skin); }
  // голова
  R(c, x + 4, y + 2, 8, 8, skin);
  R(c, x + 4, y + 9, 8, 1, skinD);
  if (dir === "up") {
    R(c, x + 3, y + 1, 10, 8, hair);
    R(c, x + 5, y + 2, 4, 1, hairL);
    R(c, x + 4, y + 8, 8, 1, hairD);
  } else {
    R(c, x + 3, y + 1, 10, 3, hair);
    R(c, x + 5, y + 1, 4, 1, hairL);
    if (dir === "down") {
      R(c, x + 3, y + 4, 1, 3, hair); R(c, x + 12, y + 4, 1, 3, hair);
      R(c, x + 6, y + 5, 1, 2, "#1a1a22"); R(c, x + 9, y + 5, 1, 2, "#1a1a22");
      R(c, x + 5, y + 7, 1, 1, "#f0a08a"); R(c, x + 10, y + 7, 1, 1, "#f0a08a");
      R(c, x + 7, y + 8, 2, 1, "#c98a6a");
    } else if (dir === "left") {
      R(c, x + 9, y + 3, 4, 4, hair); R(c, x + 10, y + 3, 2, 1, hairL);
      R(c, x + 5, y + 5, 1, 2, "#1a1a22");
      R(c, x + 6, y + 7, 1, 1, "#f0a08a");
    } else {
      R(c, x + 3, y + 3, 4, 4, hair); R(c, x + 4, y + 3, 2, 1, hairL);
      R(c, x + 10, y + 5, 1, 2, "#1a1a22");
      R(c, x + 9, y + 7, 1, 1, "#f0a08a");
    }
  }
  drawHat(c, x, y + 1, o.hat, dir);
}

// Профессор Клод: оранжевая «искра» в лабораторном халате, 16x20
const CLAUDE = "#da7756";
const CLAUDE_D = "#b5583a";
function drawClaude(c, x, y, dir, t, o = {}) {
  x = Math.round(x); y = Math.round(y);
  const bob = Math.round(Math.sin(t * 4) * 1);
  shadow(c, x, y, 10);
  const blink = Math.floor(t * 1.3) % 5 === 0 && t % 0.77 < 0.12;
  const key = "cl" + dir + bob + (blink ? 1 : 0) + "|" + (o.color || "") + "|" + (o.dark || "") + "|" + (o.coat || "") + (o.evil ? "e" : "") + (o.noGun ? "n" : "");
  // злой Клод-Ноль тёмный — обводим его неоновой линией, чтобы был виден
  sprite(c, key, x, y + bob, (g, X, Y) => claudeBody(g, X, Y, dir, blink, o), BOX_CH, o.evil ? "#b02a8a" : INK);
}
function claudeBody(c, x, y, dir, blink, o) {
  const col = o.color || CLAUDE;
  const dark = o.dark || CLAUDE_D;
  const lite = pxShade(col, 0.3);
  const coat = o.coat || "#eef0f4";
  const coatD = pxShade(coat, -0.16);
  // лучи искры
  R(c, x + 7, y, 2, 3, col);
  R(c, x + 2, y + 2, 2, 2, col); R(c, x + 3, y + 3, 2, 2, col);
  R(c, x + 12, y + 2, 2, 2, col); R(c, x + 11, y + 3, 2, 2, col);
  R(c, x, y + 6, 3, 2, col); R(c, x + 13, y + 6, 3, 2, col);
  R(c, x + 7, y, 1, 2, lite);
  // голова-ядро
  R(c, x + 4, y + 3, 8, 7, col);
  R(c, x + 5, y + 2, 6, 1, col);
  R(c, x + 4, y + 4, 1, 4, lite);
  R(c, x + 11, y + 4, 1, 5, dark);
  R(c, x + 4, y + 9, 8, 1, dark);
  // очки-гоглы на лбу
  R(c, x + 4, y + 3, 8, 1, "#3a2e2a");
  R(c, x + 5, y + 2, 2, 2, "#7fe7ff"); R(c, x + 9, y + 2, 2, 2, "#7fe7ff");
  R(c, x + 5, y + 2, 1, 1, "#e0fbff"); R(c, x + 9, y + 2, 1, 1, "#e0fbff");
  // глаза
  if (dir !== "up") {
    const ox = dir === "left" ? -1 : dir === "right" ? 1 : 0;
    if (blink) { R(c, x + 5 + ox, y + 6, 2, 1, "#1a1a22"); R(c, x + 9 + ox, y + 6, 2, 1, "#1a1a22"); }
    else {
      R(c, x + 5 + ox, y + 5, 2, 2, "#fff"); R(c, x + 9 + ox, y + 5, 2, 2, "#fff");
      R(c, x + 6 + ox, y + 6, 1, 1, "#1a1a22"); R(c, x + 10 + ox, y + 6, 1, 1, "#1a1a22");
    }
    if (o.evil) { R(c, x + 5 + ox, y + 5, 2, 2, "#ff2a4a"); R(c, x + 9 + ox, y + 5, 2, 2, "#ff2a4a"); }
    R(c, x + 7 + ox, y + 8, 2, 1, dark);
  }
  // халат
  R(c, x + 4, y + 10, 8, 7, coat);
  R(c, x + 11, y + 11, 1, 6, coatD);
  R(c, x + 7, y + 10, 2, 4, col);
  R(c, x + 4, y + 16, 8, 1, "#c8ccd6");
  R(c, x + 5, y + 13, 2, 2, "#c8ccd6");
  R(c, x + 6, y + 12, 1, 2, "#3a8ef0");
  // руки-лучики
  R(c, x + 2, y + 11, 2, 2, col); R(c, x + 12, y + 11, 2, 2, col);
  // портальная пушка
  if (!o.noGun) {
    const gx = dir === "left" ? x - 2 : x + 13;
    R(c, gx, y + 12, 4, 2, "#8a8fa0");
    R(c, gx, y + 12, 4, 1, "#b0b5c4");
    R(c, dir === "left" ? gx - 1 : gx + 3, y + 11, 2, 4, "#5aff8a");
  }
  // ножки
  R(c, x + 5, y + 17, 2, 2, col); R(c, x + 9, y + 17, 2, 2, col);
}

function drawSlime(c, x, y, t, col = "#6dff5a", o = {}) {
  x = Math.round(x); y = Math.round(y);
  const sq = Math.round(Math.sin(t * 5 + (o.phase || 0)) * 1);
  shadow(c, x, y, 12);
  sprite(c, "sl" + sq + col + (o.happy ? "h" : "") + (o.hat || ""), x, y, (g, X, Y) => slimeBody(g, X, Y, sq, col, o));
}
function slimeBody(c, x, y, sq, col, o) {
  const top = y + 8 + sq;
  const dk = pxShade(col, -0.3), md = pxShade(col, -0.14), lt = pxShade(col, 0.5);
  R(c, x + 3, top, 10, 11 - sq, col);
  R(c, x + 2, top + 3, 12, 8 - sq, col);
  R(c, x + 5, top - 1, 6, 1, col);
  R(c, x + 12, top + 3, 2, 6 - sq, md);
  R(c, x + 2, top + 10 - sq, 12, 1, dk);
  R(c, x + 2, top + 9 - sq, 1, 1, dk); R(c, x + 13, top + 9 - sq, 1, 1, dk);
  R(c, x + 4, top + 1, 2, 2, lt); R(c, x + 6, top, 2, 1, lt); R(c, x + 3, top + 4, 1, 2, lt);
  R(c, x + 5, top + 4, 2, 2, "#1a1a22"); R(c, x + 9, top + 4, 2, 2, "#1a1a22");
  R(c, x + 5, top + 4, 1, 1, "#fff"); R(c, x + 9, top + 4, 1, 1, "#fff");
  if (o.happy) R(c, x + 6, top + 7, 4, 1, "#1a1a22");
  else R(c, x + 7, top + 7, 2, 1, "#1a1a22");
  drawHat(c, x, top - 1, o.hat, "down");
}

function drawRobot(c, x, y, t, col = "#9aa3b5", o = {}) {
  x = Math.round(x); y = Math.round(y);
  const b = Math.floor(t * 2) % 2;
  shadow(c, x, y, 12);
  sprite(c, "rb" + b + col + (o.eye || ""), x, y, (g, X, Y) => robotBody(g, X, Y, b, col, o));
}
function robotBody(c, x, y, b, col, o) {
  const lt = pxShade(col, 0.3), dk = pxShade(col, -0.28);
  R(c, x + 7, y, 2, 3, "#5a606e"); R(c, x + 6, y - 1, 4, 2, b ? "#ff3a3a" : "#ffcf3a");
  R(c, x + 3, y + 3, 10, 7, col);
  R(c, x + 3, y + 3, 10, 1, lt); R(c, x + 12, y + 4, 1, 6, dk);
  R(c, x + 4, y + 5, 8, 3, "#1b1e25");
  R(c, x + 5 + b * 4, y + 6, 2, 1, o.eye || "#3affd8");
  R(c, x + 4, y + 10, 8, 6, col);
  R(c, x + 11, y + 10, 1, 6, dk); R(c, x + 4, y + 10, 8, 1, dk);
  R(c, x + 6, y + 11, 4, 3, "#5a606e");
  R(c, x + 7, y + 12, 2, 1, b ? "#3aff7a" : "#1f6b3a");
  R(c, x + 2, y + 11, 2, 4, "#5a606e"); R(c, x + 12, y + 11, 2, 4, "#5a606e");
  R(c, x + 5, y + 16, 2, 3, "#5a606e"); R(c, x + 9, y + 16, 2, 3, "#5a606e");
  R(c, x + 4, y + 19, 4, 1, "#3a3f49"); R(c, x + 8, y + 19, 4, 1, "#3a3f49");
}

function drawOwl(c, x, y, t) {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 10);
  const blink = Math.floor(t * 0.8) % 4 === 0 && (t % 1.25) < 0.15;
  sprite(c, "owl" + (blink ? 1 : 0), x, y, (g, X, Y) => owlBody(g, X, Y, blink));
}
function owlBody(c, x, y, blink) {
  R(c, x + 3, y + 4, 10, 14, "#8a6a4a");
  R(c, x + 4, y + 2, 2, 3, "#8a6a4a"); R(c, x + 10, y + 2, 2, 3, "#8a6a4a");
  R(c, x + 3, y + 10, 2, 7, "#6a4e34"); R(c, x + 11, y + 10, 2, 7, "#6a4e34");
  R(c, x + 5, y + 10, 6, 7, "#c9a77a");
  R(c, x + 6, y + 12, 1, 1, "#a8865a"); R(c, x + 9, y + 13, 1, 1, "#a8865a"); R(c, x + 7, y + 15, 1, 1, "#a8865a");
  R(c, x + 4, y + 5, 4, 4, "#fff"); R(c, x + 8, y + 5, 4, 4, "#fff");
  if (!blink) { R(c, x + 5, y + 6, 2, 2, "#1a1a22"); R(c, x + 9, y + 6, 2, 2, "#1a1a22"); R(c, x + 5, y + 6, 1, 1, "#fff"); R(c, x + 9, y + 6, 1, 1, "#fff"); }
  else { R(c, x + 4, y + 7, 4, 1, "#1a1a22"); R(c, x + 8, y + 7, 4, 1, "#1a1a22"); }
  R(c, x + 7, y + 9, 2, 2, "#ffb03a");
  R(c, x + 5, y + 18, 2, 1, "#ffb03a"); R(c, x + 9, y + 18, 2, 1, "#ffb03a");
}

function drawGhost(c, x, y, t, col = "#f2f2f7") {
  x = Math.round(x); y = Math.round(y);
  const dy = Math.round(Math.sin(t * 3) * 2);
  const f = Math.floor(t * 6) % 2;
  shadow(c, x, y, 8);
  sprite(c, "gh" + dy + f + col, x, y + dy, (g, X, Y) => ghostBody(g, X, Y, f, col));
}
function ghostBody(c, x, y, f, col) {
  const dk = pxShade(col, -0.15);
  R(c, x + 3, y + 2, 10, 14, col);
  R(c, x + 5, y + 1, 6, 1, col);
  R(c, x + 11, y + 3, 2, 13, dk);
  for (let i = 0; i < 5; i++) R(c, x + 3 + i * 2, y + 16 + ((i + f) % 2), 2, 2, col);
  R(c, x + 5, y + 6, 2, 3, "#1a1a22"); R(c, x + 9, y + 6, 2, 3, "#1a1a22");
  R(c, x + 6, y + 11, 4, 2, "#1a1a22");
  R(c, x + 4, y + 3, 2, 1, "#fff");
}

function drawNoob(c, x, y, dir, step) {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 10);
  const b = step ? 1 : 0;
  sprite(c, "noob" + dir + b, x, y, (g, X, Y) => noobBody(g, X, Y, dir, b));
}
function noobBody(c, x, y, dir, b) {
  R(c, x + 4, y + 14, 3, 5 - b, "#4b974b"); R(c, x + 9, y + 14, 3, 5 - (1 - b), "#4b974b");
  R(c, x + 4, y + 8, 8, 6, "#0d69ac");
  R(c, x + 4, y + 8, 8, 1, "#2a8ad0"); R(c, x + 11, y + 9, 1, 5, "#0a4a7a");
  R(c, x + 1, y + 8 + b, 3, 6, "#f5cd30"); R(c, x + 12, y + 8 + (1 - b), 3, 6, "#f5cd30");
  R(c, x + 5, y + 2, 6, 6, "#f5cd30");
  R(c, x + 5, y + 2, 6, 1, "#ffe36b"); R(c, x + 10, y + 3, 1, 5, "#d6aa1a");
  if (dir !== "up") {
    R(c, x + 6, y + 4, 1, 1, "#1a1a22"); R(c, x + 9, y + 4, 1, 1, "#1a1a22");
    R(c, x + 6, y + 6, 4, 1, "#1a1a22");
  }
}

function drawBug(c, x, y, t, col = "#e0425a") {
  x = Math.round(x); y = Math.round(y);
  const k = Math.floor(t * 8) % 2;
  shadow(c, x, y, 10);
  sprite(c, "bug" + k + col, x, y, (g, X, Y) => bugBody(g, X, Y, k, col));
}
function bugBody(c, x, y, k, col) {
  R(c, x + 3, y + 9, 10, 8, col);
  R(c, x + 4, y + 9, 3, 1, pxShade(col, 0.35)); R(c, x + 3, y + 10, 1, 3, pxShade(col, 0.35));
  R(c, x + 3, y + 16, 10, 1, pxShade(col, -0.3));
  R(c, x + 7, y + 9, 1, 8, "#1a1a22");
  R(c, x + 5, y + 6, 6, 3, "#1a1a22");
  R(c, x + 5, y + 4 + k, 1, 2, "#1a1a22"); R(c, x + 10, y + 4 + (1 - k), 1, 2, "#1a1a22");
  R(c, x + 6, y + 7, 1, 1, "#ffe03a"); R(c, x + 9, y + 7, 1, 1, "#ffe03a");
  R(c, x + 4, y + 11, 2, 2, "#1a1a22"); R(c, x + 9, y + 13, 2, 2, "#1a1a22");
  R(c, x + 1, y + 10 + k, 2, 1, "#1a1a22"); R(c, x + 13, y + 10 + k, 2, 1, "#1a1a22");
  R(c, x + 1, y + 14 - k, 2, 1, "#1a1a22"); R(c, x + 13, y + 14 - k, 2, 1, "#1a1a22");
}

function drawNil(c, x, y, t) {
  x = Math.round(x); y = Math.round(y);
  const dy = Math.round(Math.sin(t * 2) * 2);
  sprite(c, "nil" + dy, x, y + dy, nilBody, BOX_CH, "#4a4a8a");
}
function nilBody(c, x, y) {
  R(c, x + 3, y + 4, 10, 10, "#0a0a12");
  R(c, x + 4, y + 3, 8, 12, "#0a0a12");
  R(c, x + 2, y + 5, 12, 8, "#0a0a12");
  R(c, x + 4, y + 4, 2, 1, "#24244a");
  R(c, x + 5, y + 6, 2, 2, "#8a8aff"); R(c, x + 9, y + 6, 2, 2, "#8a8aff");
  R(c, x + 5, y + 6, 1, 1, "#d8d8ff"); R(c, x + 9, y + 6, 1, 1, "#d8d8ff");
  // надпись nil пикселями
  R(c, x + 4, y + 10, 2, 1, "#8a8aff"); R(c, x + 4, y + 11, 1, 2, "#8a8aff"); R(c, x + 6, y + 11, 1, 2, "#8a8aff");
  R(c, x + 8, y + 9, 1, 1, "#8a8aff"); R(c, x + 8, y + 11, 1, 2, "#8a8aff");
  R(c, x + 10, y + 9, 1, 4, "#8a8aff");
}

function drawMushroom(c, x, y, t) {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 10);
  sprite(c, "shroom", x, y, mushroomBody);
}
function mushroomBody(c, x, y) {
  R(c, x + 5, y + 10, 6, 8, "#efe2c8");
  R(c, x + 10, y + 10, 1, 8, "#cfc0a4");
  R(c, x + 6, y + 13, 1, 2, "#1a1a22"); R(c, x + 9, y + 13, 1, 2, "#1a1a22");
  R(c, x + 2, y + 4, 12, 6, "#3ab5d6");
  R(c, x + 4, y + 2, 8, 2, "#3ab5d6");
  R(c, x + 4, y + 2, 4, 1, "#7ad8f0"); R(c, x + 2, y + 9, 12, 1, "#2a8aa8"); R(c, x + 12, y + 5, 2, 4, "#2a8aa8");
  R(c, x + 4, y + 5, 2, 2, "#e8fbff"); R(c, x + 10, y + 4, 2, 2, "#e8fbff"); R(c, x + 7, y + 7, 1, 1, "#e8fbff");
}

function drawCat(c, x, y, t, col = "#3a3a44") {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 10);
  const k = Math.floor(t * 2) % 2;
  sprite(c, "cat" + k + col, x, y, (g, X, Y) => catBody(g, X, Y, k, col));
}
function catBody(c, x, y, k, col) {
  const lt = pxShade(col, 0.25);
  R(c, x + 4, y + 10, 9, 7, col);
  R(c, x + 3, y + 4, 8, 7, col);
  R(c, x + 3, y + 2, 2, 2, col); R(c, x + 9, y + 2, 2, 2, col);
  R(c, x + 4, y + 3, 1, 1, "#ff9ab0"); R(c, x + 9, y + 3, 1, 1, "#ff9ab0");
  R(c, x + 4, y + 4, 3, 1, lt);
  R(c, x + 5, y + 6, 1, 2, "#ffe03a"); R(c, x + 8, y + 6, 1, 2, "#ffe03a");
  R(c, x + 6, y + 9, 2, 1, "#ff9ab0");
  R(c, x + 5, y + 16, 2, 1, lt); R(c, x + 10, y + 16, 2, 1, lt);
  R(c, x + 13, y + 8 - k, 2, 6, col);
}

function drawStar(c, x, y, t) {
  x = Math.round(x); y = Math.round(y);
  const g = Math.floor(t * 4) % 2;
  sprite(c, "star" + g, x, y, (cc, X, Y) => starBody(cc, X, Y, g));
}
function starBody(c, x, y, g) {
  const col = g ? "#ffe36b" : "#ffd23a";
  R(c, x + 7, y + 3, 2, 12, col);
  R(c, x + 2, y + 8, 12, 2, col);
  R(c, x + 5, y + 6, 6, 6, col);
  R(c, x + 4, y + 12, 2, 2, col); R(c, x + 10, y + 12, 2, 2, col);
  R(c, x + 6, y + 7, 2, 2, "#fff8d0");
  R(c, x + 10, y + 10, 1, 2, "#e0a81a");
  if (g) { R(c, x + 1, y + 2, 1, 1, "#fff"); R(c, x + 14, y + 4, 1, 1, "#fff"); }
}

// портал: пиксельная спираль, кадры кэшируются
const PORTAL_FR = new Map();
function portalFrame(W, k) {
  const key = W + "|" + k;
  let cv = PORTAL_FR.get(key);
  if (cv) return cv;
  cv = pxCanvas(W, 32);
  const g = cv.getContext("2d");
  const cols = ["#18c94a", "#2aff6a", "#9affb0", "#d8ffe0"];
  const cx = W / 2, cy = 16, rx = W / 2 - 2, ry = 15;
  for (let j = 0; j < 32; j++) for (let i = 0; i < W; i++) {
    const dx = (i + 0.5 - cx) / rx, dy = (j + 0.5 - cy) / ry;
    const d = Math.sqrt(dx * dx + dy * dy);
    if (d > 1) continue;
    let col;
    if (d > 0.9) col = "#0f7a30";
    else if (d < 0.18) col = "#f2fff4";
    else {
      const a = Math.atan2(dy, dx) / (Math.PI * 2);
      const idx = (((Math.floor(d * 5 + a * 2 - k / 2) % 4) + 4) % 4);
      col = cols[idx];
    }
    g.fillStyle = col;
    g.fillRect(i, j, 1, 1);
  }
  PORTAL_FR.set(key, cv);
  return cv;
}
function portalGlow(W) {
  const key = "glow" + W;
  let cv = PORTAL_FR.get(key);
  if (cv) return cv;
  cv = pxCanvas(W + 12, 40);
  const g = cv.getContext("2d");
  const cx = (W + 12) / 2, cy = 20;
  for (let j = 0; j < 40; j++) for (let i = 0; i < W + 12; i++) {
    const dx = (i + 0.5 - cx) / (W / 2 + 5), dy = (j + 0.5 - cy) / 19.5;
    const d = Math.sqrt(dx * dx + dy * dy);
    if (d > 1) continue;
    g.fillStyle = d > 0.88 ? "rgba(90,255,140,0.12)" : "rgba(90,255,140,0.24)";
    g.fillRect(i, j, 1, 1);
  }
  PORTAL_FR.set(key, cv);
  return cv;
}
function drawPortal(c, x, y, t, open = true, w = 2) {
  x = Math.round(x); y = Math.round(y);
  const W = 16 * w;
  if (!open) {
    R(c, x + 3, y + 3, W - 6, 28, INK);
    R(c, x + 4, y + 4, W - 8, 26, "#2a2d3a");
    R(c, x + 6, y + 6, W - 12, 22, "#1a1c26");
    R(c, x + 6, y + 6, W - 12, 1, "#3a3d4c");
    if (Math.floor(t * 6) % 3 === 0) R(c, x + W / 2 - 1, y + 10, 2, 8, "#5aff8a");
    return;
  }
  // мягкое свечение
  c.globalAlpha = 0.75 + Math.sin(t * 3) * 0.25;
  c.drawImage(portalGlow(W), x - 6, y - 4);
  c.globalAlpha = 1;
  c.drawImage(portalFrame(W, Math.floor(t * 10) % 8), x, y);
  for (let i = 0; i < 6; i++) {
    const a = t * 3 + i;
    R(c, x + W / 2 + Math.cos(a) * (W / 2 - 3), y + 16 + Math.sin(a) * 13, 1, 1, "#eaffef");
  }
}

function drawMachine(c, x, y, t, open) {
  x = Math.round(x); y = Math.round(y);
  const red = Math.floor(t * 2) % 2;
  sprite(c, "mach" + red + (open ? 1 : 0), x, y, (g, X, Y) => machineBody(g, X, Y, red, open), [-3, -3, 38, 38]);
  drawPortal(c, x, y - 1, t, open, 2);
}
function machineBody(c, x, y, red, open) {
  R(c, x, y + 26, 32, 6, "#5a5f76");
  R(c, x, y + 26, 32, 1, "#7a809a"); R(c, x, y + 31, 32, 1, "#3a3d4c");
  R(c, x + 1, y, 3, 28, "#6c7290"); R(c, x + 28, y, 3, 28, "#6c7290");
  R(c, x + 1, y, 1, 28, "#8a90b0"); R(c, x + 30, y, 1, 28, "#4a4f66");
  R(c, x + 1, y, 30, 3, "#6c7290");
  R(c, x + 1, y, 30, 1, "#8a90b0");
  R(c, x + 4, y + 30, 4, 2, red ? "#ff3a3a" : "#5a1a1a");
  R(c, x + 24, y + 30, 4, 2, open ? "#3aff7a" : "#1a3a1a");
  R(c, x + 12, y + 28, 8, 2, "#3a3d4c"); R(c, x + 13, y + 28, 2, 1, "#ffcf3a");
}

function drawTerminal(c, x, y, t) {
  x = Math.round(x); y = Math.round(y);
  const k = Math.floor(t * 3) % 4, cur = Math.floor(t * 2) % 2;
  sprite(c, "term" + k + cur, x, y, (g, X, Y) => {
    R(g, X + 1, Y + 2, 14, 11, "#2a2d3a");
    R(g, X + 1, Y + 2, 14, 1, "#4a4e62");
    R(g, X + 2, Y + 3, 12, 8, "#0d1a12");
    R(g, X + 3, Y + 4, 6, 1, "#3aff7a"); R(g, X + 3, Y + 6, 8 - k, 1, "#3aff7a"); R(g, X + 3, Y + 8, 4, 1, "#3aff7a");
    if (cur) R(g, X + 8, Y + 8, 2, 1, "#3aff7a");
    R(g, X + 2, Y + 3, 12, 1, "rgba(120,255,160,0.15)");
    R(g, X + 6, Y + 13, 4, 2, "#2a2d3a"); R(g, X + 3, Y + 15, 10, 1, "#2a2d3a");
  }, BOX_OBJ);
}

function drawStation(c, x, y, t, done) {
  // учебный камень с книгой
  x = Math.round(x); y = Math.round(y);
  const gk = done ? 2 : Math.floor(t * 3) % 2;
  const up = Math.floor(t * 2) % 2;
  shadow(c, x, y, 14);
  sprite(c, "stn" + gk + up + (done ? 1 : 0), x, y, (g, X, Y) => stationBody(g, X, Y, gk, up, done), BOX_OBJ);
}
function stationBody(c, x, y, gk, up, done) {
  const glow = ["#ffb03a", "#ffe36b", "#5aff8a"][gk];
  R(c, x + 2, y + 9, 12, 9, "#6c6a7a");
  R(c, x + 2, y + 9, 3, 9, "#86849a"); R(c, x + 12, y + 10, 2, 8, "#4e4c5c");
  R(c, x + 3, y + 8, 10, 2, "#86849a");
  R(c, x + 6, y + 12, 4, 3, "#5a5868"); R(c, x + 7, y + 13, 2, 1, glow);
  R(c, x + 3, y + 5, 10, 4, "#f2ead8");
  R(c, x + 7, y + 5, 2, 4, "#c9bfa6");
  R(c, x + 4, y + 6, 2, 1, "#8a7a5a"); R(c, x + 10, y + 6, 2, 1, "#8a7a5a"); R(c, x + 4, y + 7, 2, 1, "#8a7a5a");
  R(c, x + 7, y + 1 + up, 2, 2, glow);
  if (!done) { R(c, x + 4, y + 2, 1, 1, glow); R(c, x + 11, y + 3, 1, 1, glow); }
}

function drawChest(c, x, y, open) {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 14);
  sprite(c, "chest" + (open ? 1 : 0), x, y, (g, X, Y) => {
    R(g, X + 2, Y + 8, 12, 10, "#8a5a2a");
    R(g, X + 2, Y + 8, 12, 1, "#aa7a42"); R(g, X + 12, Y + 9, 2, 9, "#6a4220");
    R(g, X + 2, Y + 12, 12, 1, "#5a3a1a");
    R(g, X + 4, Y + 8, 1, 10, "#c8a050"); R(g, X + 11, Y + 8, 1, 10, "#c8a050");
    if (open) { R(g, X + 2, Y + 4, 12, 4, "#6a4a2a"); R(g, X + 3, Y + 7, 10, 1, "#2a1a0a"); }
    else { R(g, X + 2, Y + 5, 12, 4, "#a06a32"); R(g, X + 2, Y + 5, 12, 1, "#c08a4a"); R(g, X + 7, Y + 10, 2, 3, "#ffd84a"); R(g, X + 7, Y + 10, 1, 1, "#fff3b0"); }
  }, BOX_OBJ);
}

function drawSign(c, x, y) {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 8);
  sprite(c, "sign", x, y, (g, X, Y) => {
    R(g, X + 7, Y + 10, 2, 9, "#6a4a2a"); R(g, X + 8, Y + 10, 1, 9, "#4a3018");
    R(g, X + 2, Y + 3, 12, 8, "#a07a4a");
    R(g, X + 2, Y + 3, 12, 1, "#c09a62"); R(g, X + 2, Y + 10, 12, 1, "#7a5630");
    R(g, X + 3, Y + 5, 10, 1, "#5a3a1a"); R(g, X + 3, Y + 8, 7, 1, "#5a3a1a");
  }, BOX_OBJ);
}

function drawPoster(c, x, y) {
  x = Math.round(x); y = Math.round(y);
  sprite(c, "poster", x, y, (g, X, Y) => {
    R(g, X + 1, Y + 1, 14, 14, "#1e2a3a");
    R(g, X + 2, Y + 2, 12, 12, "#2e5a8a");
    R(g, X + 2, Y + 9, 12, 5, "#244a72");
    R(g, X + 4, Y + 8, 8, 5, "#8a8f9a");
    R(g, X + 6, Y + 6, 4, 2, "#8a8f9a");
    R(g, X + 7, Y + 10, 2, 3, "#3a2a1a");
    R(g, X + 3, Y + 3, 10, 2, "#ffd84a");
    R(g, X + 11, Y + 6, 1, 1, "#fff"); R(g, X + 4, Y + 6, 1, 1, "#fff");
  }, BOX_OBJ);
}

function drawFridge(c, x, y) {
  x = Math.round(x); y = Math.round(y);
  sprite(c, "fridge", x, y, (g, X, Y) => {
    R(g, X + 2, Y - 4, 12, 20, "#dfe6ee");
    R(g, X + 2, Y - 4, 12, 1, "#f6faff"); R(g, X + 12, Y - 3, 2, 19, "#b8c4d2");
    R(g, X + 2, Y + 3, 12, 1, "#9aa6b5");
    R(g, X + 11, Y - 1, 1, 3, "#7a8696"); R(g, X + 11, Y + 6, 1, 4, "#7a8696");
    R(g, X + 4, Y - 2, 3, 3, "#ff8a3a"); R(g, X + 5, Y + 6, 2, 2, "#5ac8ff"); R(g, X + 4, Y + 9, 4, 1, "#f2f2f2");
  }, BOX_OBJ);
}

function drawClock(c, x, y, t) {
  x = Math.round(x); y = Math.round(y);
  sprite(c, "clock", x, y, clockBody, [-3, -36, 38, 72]);
  const cx = x + 16, cy = y - 4;
  // стрелки пикселями
  const hand = (a, len, col) => { for (let s = 0; s <= len; s++) R(c, cx + Math.round(Math.cos(a) * s), cy + Math.round(Math.sin(a) * s), 1, 1, col); };
  hand(t * 6, 7, "#1a1a22");
  hand(t / 2, 5, "#7a2a3a");
  R(c, cx, cy, 1, 1, "#f2c46b");
  // маятник
  const sw = Math.round(Math.sin(t * 3) * 2);
  R(c, x + 15 + sw, y + 18, 2, 6, "#c8961a");
  R(c, x + 14 + sw, y + 23, 4, 3, "#f2c46b");
}
function clockBody(c, x, y) {
  const br = "#3a2e4e", brL = "#4e3f66", brD = "#2a2038";
  R(c, x + 4, y - 20, 24, 52, br);
  R(c, x + 4, y - 20, 2, 52, brL); R(c, x + 26, y - 20, 2, 52, brD);
  for (let j = -16; j < 32; j += 5) { R(c, x + 6, y + j, 20, 1, brD); R(c, x + 10 + ((j / 5) & 1) * 6, y + j - 4, 1, 4, brD); }
  // крыша-шпиль
  R(c, x + 2, y - 24, 28, 5, "#7a5a7a"); R(c, x + 2, y - 24, 28, 1, "#9a7a9a"); R(c, x + 2, y - 20, 28, 1, "#5a3a5a");
  R(c, x + 8, y - 28, 16, 4, "#7a5a7a"); R(c, x + 13, y - 31, 6, 3, "#7a5a7a"); R(c, x + 15, y - 33, 2, 2, "#f2c46b");
  // циферблат
  R(c, x + 6, y - 14, 20, 20, "#c8961a");
  R(c, x + 7, y - 13, 18, 18, "#f2e6c8");
  R(c, x + 7, y - 13, 18, 1, "#fff8e0");
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2;
    R(c, x + 16 + Math.round(Math.cos(a) * 7), y - 4 + Math.round(Math.sin(a) * 7), 1, 1, i % 3 ? "#8a7a5a" : "#3a2a1a");
  }
  // окно для маятника и дверь
  R(c, x + 11, y + 10, 10, 18, "#1a1426");
  R(c, x + 11, y + 10, 10, 1, "#f2c46b");
  R(c, x + 10, y + 28, 12, 4, "#2a2038");
}

// иконка-портрет для диалогов: рисуем персонажа в маленький canvas
const PORTRAITS = {};
function speakerDraw(id) {
  const S = SPEAKERS[id] || SPEAKERS.sys;
  return S.draw;
}

const SPEAKERS = {
  claude: { name: "Профессор Клод", color: "#ffb08a", pitch: 1.5, draw: (c, t) => drawClaude(c, 0, 0, "down", t) },
  player: { name: "Ты", color: "#bfe0ff", pitch: 1.0, draw: (c, t) => drawKid(c, 0, 0, "down", 0, playerLook()) },
  sys: { name: "", color: "#ffffff", pitch: 0.8, draw: null },
  slime: { name: "Слизень", color: "#a8ff9a", pitch: 1.2, draw: (c, t) => drawSlime(c, 0, 0, t) },
  bob: { name: "Слизень Боб", color: "#a8ff9a", pitch: 1.1, draw: (c, t) => drawSlime(c, 0, 0, t, "#6dff5a", { happy: true }) },
  kid: { name: "Слизняш", color: "#ffd0e3", pitch: 1.6, draw: (c, t) => drawSlime(c, 0, 0, t, "#ff8ad0") },
  trader: { name: "Слизень-торговец", color: "#ffe36b", pitch: 0.9, draw: (c, t) => drawSlime(c, 0, 0, t, "#ffd23a", { hat: "tophat" }) },
  gslime: { name: "Глюк-Слизень", color: "#ff3a8a", pitch: 0.7, draw: (c, t) => drawSlime(c, 0, 0, t, "#c03aff") },
  owl: { name: "Сова Иначе", color: "#e9c99a", pitch: 0.9, draw: (c, t) => drawOwl(c, 0, 0, t) },
  shroom: { name: "Гриб Логик", color: "#9ae6ff", pitch: 1.3, draw: (c, t) => drawMushroom(c, 0, 0, t) },
  guard: { name: "Страж Ветвления", color: "#7fd8c2", pitch: 0.6, draw: null },
  mayor: { name: "Мэр Повторяшкин", color: "#f2c46b", pitch: 0.8, draw: (c, t) => drawKid(c, 0, 0, "down", 0, { shirt: "#7a3a5a", hair: "#ddd", hat: "tophat" }) },
  townie: { name: "Житель", color: "#d8c8ff", pitch: 1.1, draw: (c, t) => drawKid(c, 0, 0, "down", 0, { shirt: "#c05a8a", hair: "#2a1a1a" }) },
  baker: { name: "Пекарь Тесто", color: "#ffd8a8", pitch: 1.0, draw: (c, t) => drawKid(c, 0, 0, "down", 0, { shirt: "#f2f2f2", hair: "#8a5a2a", hat: "cap" }) },
  serpent: { name: "Змей Бесконечности", color: "#b08aff", pitch: 0.6, draw: null },
  robo: { name: "Робот Ж-2", color: "#9ae6ff", pitch: 1.4, draw: (c, t) => drawRobot(c, 0, 0, t) },
  keeper: { name: "Кладовщик Т-4", color: "#ffcf3a", pitch: 1.0, draw: (c, t) => drawRobot(c, 0, 0, t, "#d6a83a", { eye: "#ff8a3a" }) },
  roboboss: { name: "Робо-Начальник", color: "#ff8a8a", pitch: 0.6, draw: null },
  noob: { name: "Нубик", color: "#ffe36b", pitch: 1.2, draw: (c, t) => drawNoob(c, 0, 0, "down", 0) },
  lava: { name: "Лава-Блок", color: "#ff8a3a", pitch: 0.5, draw: null },
  zero: { name: "Клод-Ноль", color: "#b0b0c0", pitch: 0.6, draw: (c, t) => drawClaude(c, 0, 0, "down", t, { color: "#6a6a7a", dark: "#4a4a5a", evil: true, coat: "#2a2a33", noGun: true }) },
  glitchik: { name: "Глюкич", color: "#ff9ad0", pitch: 1.5, draw: (c, t) => drawClaude(c, 0, 0, "down", t, { color: "#c88ad6", dark: "#9a5aaa", noGun: true }) },
  cat: { name: "Кот Шрёдингера", color: "#cfcfe0", pitch: 1.2, draw: (c, t) => drawCat(c, 0, 0, t) },
  custom: { name: "", color: "#ffffff", pitch: 1.0, draw: null },
};

// ---------- большие спрайты для боя ----------
// враг рисуется в запасной canvas в масштабе, обводится (толщина = 1 пиксель спрайта) и при ударе вспыхивает белым
const BSPR = { a: null, b: null };
function battleSprite(c, e, cx, cy, t, hurt) {
  const sc = e.scale || 3;
  const P = 8;
  const w = (16 + P * 2) * sc, h = (20 + P * 2) * sc;
  if (!BSPR.a || BSPR.a.width < w || BSPR.a.height < h) { BSPR.a = pxCanvas(w, h); BSPR.b = pxCanvas(w, h); }
  const g = BSPR.a.getContext("2d");
  g.clearRect(0, 0, BSPR.a.width, BSPR.a.height);
  g.imageSmoothingEnabled = false;
  g.save();
  g.translate(P * sc, P * sc);
  g.scale(sc, sc);
  SPR.raw = true;
  try { battleLook(g, e, t); } finally { SPR.raw = false; }
  g.restore();
  // белая вспышка от удара
  if (hurt > 0.22 && Math.floor(hurt * 24) % 2 === 0) {
    g.globalCompositeOperation = "source-atop";
    g.fillStyle = "#fff";
    g.fillRect(0, 0, w, h);
    g.globalCompositeOperation = "source-over";
  }
  // тёмная обводка + тусклая светлая кайма, чтобы тёмные лапки и тела не терялись на фоне
  pxOutline(BSPR.b, BSPR.a, w, h, INK, sc);
  pxOutline(BSPR.a, BSPR.b, w, h, e.look === "claude" ? "#6a1a5a" : "#3a3456", sc);
  const shake = hurt > 0 ? Math.round(Math.sin(t * 60) * 3) : 0;
  const ox = Math.round(cx - 8 * sc + shake), oy = Math.round(cy - 10 * sc);
  c.drawImage(BSPR.a, 0, 0, w, h, ox - P * sc, oy - P * sc, w, h);
  // надписи на спрайте рисуем поверх, без обводки
  const lab = BATTLE_LABELS[e.look];
  if (lab) {
    c.save();
    c.translate(ox, oy);
    c.scale(sc, sc);
    c.textAlign = "left";
    c.font = lab.font;
    c.fillStyle = lab.color;
    for (const [txt, x, y] of lab.lines) c.fillText(txt, x, y);
    c.restore();
  }
  // эффект глюка у боссов
  if (e.glitch && Math.random() < 0.18) {
    const y = cy - 10 * sc + Math.random() * 20 * sc;
    const img = c.getImageData(Math.max(0, cx - 30 * sc / 3 * 3), Math.max(0, Math.round(y)), Math.round(20 * sc), 3);
    c.putImageData(img, Math.max(0, cx - 30 * sc / 3 * 3) + (Math.random() * 10 - 5), Math.round(y));
  }
}

const BATTLE_LABELS = {
  tree: { font: "4px monospace", color: "#1a1a22", lines: [["if", -1.5, 13], ["else", 13.6, 13]] },
  serpent: { font: "3px monospace", color: "#fff", lines: [["while true", 1.5, 11]] },
  "boss-robot": { font: "3px monospace", color: "#ffcf3a", lines: [["return", 3.5, 18.5]] },
};
function battleLook(c, e, tt) {
  switch (e.look) {
    case "slime": drawSlime(c, 0, 0, tt, e.color, { happy: e.happy }); break;
    case "bug": drawBug(c, 0, 0, tt, e.color); break;
    case "ghost": drawGhost(c, 0, 0, tt, e.color); break;
    case "nil": drawNil(c, 0, 0, tt); break;
    case "robot": drawRobot(c, 0, 0, tt, e.color); break;
    case "owl": drawOwl(c, 0, 0, tt); break;
    case "cat": drawCat(c, 0, 0, tt, e.color); break;
    case "noob": drawNoob(c, 0, 0, "down", Math.floor(tt * 4) % 2); break;
    case "kid": drawKid(c, 0, 0, "down", Math.floor(tt * 3) % 2, { shirt: e.color }); break;
    case "claude": drawClaude(c, 0, 0, "down", tt, { color: e.color || "#6a6a7a", dark: "#4a4a5a", evil: true, coat: "#2a2a33", noGun: true }); break;
    case "tree": {
      R(c, 6, 12, 4, 8, "#4a3424"); R(c, 9, 12, 1, 8, "#33241a");
      R(c, 1, 4, 14, 10, "#1f6b4a"); R(c, 3, 1, 10, 4, "#1f6b4a");
      R(c, 3, 1, 4, 1, "#3a9a6a"); R(c, 1, 4, 2, 4, "#3a9a6a"); R(c, 12, 5, 3, 9, "#164a34");
      R(c, 4, 6, 3, 3, "#fff"); R(c, 9, 6, 3, 3, "#fff");
      R(c, 5, 7, 1, 1, "#1a1a22"); R(c, 10, 7, 1, 1, "#1a1a22");
      R(c, 6, 11, 4, 1, "#1a1a22");
      R(c, -2, 9, 4, 6, "#c0c8d0"); R(c, 14, 9, 4, 6, "#c0c8d0");
      break;
    }
    case "serpent": {
      const n = 14;
      for (let i = 0; i < n; i++) {
        const a = tt * 1.5 + (i / n) * Math.PI * 2;
        const col = i === 0 ? "#d6a8ff" : i % 2 ? "#8a5ad6" : "#6a3ab5";
        R(c, 8 + Math.cos(a) * 8 - 1.5, 10 + Math.sin(a) * 8 - 1.5, 3, 3, col);
      }
      const a = tt * 1.5;
      R(c, 8 + Math.cos(a) * 8 - 2.5, 10 + Math.sin(a) * 8 - 2.5, 5, 5, "#d6a8ff");
      R(c, 8 + Math.cos(a) * 8 - 1, 10 + Math.sin(a) * 8 - 1, 1, 1, "#ff2a4a");
      break;
    }
    case "lava": {
      const g = Math.floor(tt * 3) % 2;
      R(c, 0, 2, 16, 16, "#ff5a1f");
      R(c, 0, 2, 16, 3, "#ffb03a");
      R(c, 3 + g, 5, 4, 2, "#d23c12"); R(c, 9, 12 - g, 5, 2, "#d23c12");
      R(c, 2 + g, 8, 3, 3, "#1a1a22"); R(c, 11 - g, 8, 3, 3, "#1a1a22");
      R(c, 2 + g, 8, 1, 1, "#ffe36b"); R(c, 11 - g, 8, 1, 1, "#ffe36b");
      R(c, 5, 14, 6, 2, "#1a1a22");
      R(c, 1, 17 + g, 3, 2, "#ff5a1f"); R(c, 12, 17 + (1 - g), 3, 2, "#ff5a1f");
      R(c, 3, 3, 2, 1, "#ffe36b"); R(c, 10, 4, 3, 1, "#ffe36b");
      break;
    }
    case "boss-robot": {
      R(c, -2, 2, 20, 12, "#c05a5a");
      R(c, -2, 2, 20, 1, "#e07a7a"); R(c, 15, 3, 3, 11, "#8a3a3a");
      R(c, 0, 4, 16, 6, "#1b1e25");
      const k = Math.floor(tt * 3) % 3;
      R(c, 2 + k * 4, 6, 3, 2, "#ff3a3a");
      R(c, 3, 14, 10, 6, "#8a3a3a");
      R(c, 6, 0, 4, 2, "#ffcf3a");
      break;
    }
    default: drawSlime(c, 0, 0, tt, e.color);
  }
}

// тематический фон боя за врагом: тусклый, чтобы пули было хорошо видно
const BATTLE_BG = new Map();
function battleBg(c, zone, t) {
  const id = ZONE_PAL[zone] ? zone : "lab";
  let bg = BATTLE_BG.get(id);
  if (!bg) { bg = makeBattleBg(id); BATTLE_BG.set(id, bg); }
  c.drawImage(bg, 0, 0);
  // живые детали
  if (id === "slime") {
    for (let i = 0; i < 7; i++) {
      const ph = (t * 0.18 + i * 0.37) % 1;
      R(c, (i * 47 + 13) % 256, 92 - ph * 84, 2, 2, ph > 0.85 ? "#0c2a12" : "#1a4a22");
    }
  } else if (id === "forest") {
    for (let i = 0; i < 9; i++) {
      const on = Math.sin(t * 2 + i * 1.7) > 0.2;
      if (!on) continue;
      const x = (i * 61 + Math.sin(t * 0.6 + i) * 14 + 256) % 256, y = 14 + ((i * 23) % 56) + Math.cos(t * 0.8 + i) * 4;
      R(c, x, y, 1, 1, "#9acb4a");
      R(c, x - 1, y, 3, 1, "rgba(150,200,80,0.25)");
    }
  } else if (id === "loop") {
    const hand = (a, len, col) => { for (let s = 3; s <= len; s += 1) R(c, 128 + Math.round(Math.cos(a) * s), 46 + Math.round(Math.sin(a) * s), 1, 1, col); };
    hand(t * 0.9 - Math.PI / 2, 32, "#2c2248");
    hand(t * 0.08 - Math.PI / 2, 22, "#2c2248");
  } else if (id === "robo") {
    for (let i = 0; i < 6; i++) R(c, 20 + i * 44, 16, 2, 2, Math.floor(t * 2 + i) % 3 === 0 ? "#6a1a1a" : "#2a0e0e");
  } else if (id === "core") {
    for (let i = 0; i < 4; i++) {
      const f = Math.floor(t * 10) + i * 7;
      if (f % 5 === 0) R(c, (f * 37) % 220, (f * 13) % 80, 10 + (f % 30), 2, i % 2 ? "#2a0a3a" : "#0a2a2e");
    }
  } else if (id === "cube") {
    for (let i = 0; i < 5; i++) {
      const ph = (t * 0.06 + i * 0.21) % 1;
      R(c, (i * 53 + 20) % 256, 90 - ph * 90, 5, 5, "#0f1d3d");
    }
  } else {
    R(c, 0, Math.floor((t * 18) % 96), 256, 1, "rgba(90,255,138,0.05)");
  }
}

function makeBattleBg(id) {
  const cv = pxCanvas(256, 100);
  const g = cv.getContext("2d");
  const grid = { lab: "#0f2a1a", slime: "#0e2a14", forest: "#0b2622", loop: "#1a1430", robo: "#151820", cube: "#0f1a33", core: "#1e0a26" }[id];
  R(g, 0, 0, 256, 100, { lab: "#05070a", slime: "#040c06", forest: "#030a0a", loop: "#08050f", robo: "#060709", cube: "#040814", core: "#07030c" }[id]);
  // сетка как в Undertale
  for (let i = 0; i < 256; i += 16) R(g, i, 0, 1, 100, grid);
  for (let j = 0; j < 100; j += 16) R(g, 0, j, 256, 1, grid);
  const hills = (base, amp, fr, ph, col) => { for (let x = 0; x < 256; x += 2) { const y = Math.round(base + Math.sin(x * fr + ph) * amp); R(g, x, y, 2, 100 - y, col); } };
  const pines = (base, size, step, col, seed) => {
    for (let x = -8; x < 264; x += step) {
      const s = size + (hsh(x, seed) % 6);
      for (let r = 0; r < s; r++) { const half = Math.floor(r / 2) + 1; R(g, x - half, base - s + r, half * 2, 1, col); }
      R(g, x - 1, base, 2, 100 - base, col);
    }
  };
  if (id === "slime") {
    hills(62, 6, 0.03, 0, "#0a2010");
    hills(74, 5, 0.05, 1, "#0d2814");
    for (let x = 18; x < 256; x += 57) { R(g, x, 64, 3, 10, "#0f2e16"); R(g, x - 4, 60, 11, 4, "#14361c"); }
  } else if (id === "forest") {
    pines(70, 14, 14, "#071a18", 1);
    pines(86, 18, 22, "#0a2420", 2);
  } else if (id === "loop") {
    for (let a = 0; a < 360; a += 2) {
      const r = a * Math.PI / 180;
      R(g, 128 + Math.round(Math.cos(r) * 38), 46 + Math.round(Math.sin(r) * 38), 1, 1, "#1e1634");
    }
    for (let i = 0; i < 12; i++) {
      const r = (i / 12) * Math.PI * 2;
      R(g, 128 + Math.round(Math.cos(r) * 33) - 1, 46 + Math.round(Math.sin(r) * 33) - 1, 2, 2, "#2a2048");
    }
    for (let x = 0; x < 256; x += 24) {
      const hh = 14 + (hsh(x, 3) % 12);
      R(g, x, 100 - hh, 20, hh, "#0e0a1a");
      R(g, x + 2, 100 - hh - 4, 16, 4, "#120d22");
      R(g, x + 6, 100 - hh + 5, 3, 3, "#2a2014");
    }
  } else if (id === "robo") {
    for (const y of [12, 34]) { R(g, 0, y, 256, 5, "#12151c"); R(g, 0, y, 256, 1, "#1a1e27"); for (let x = 10; x < 256; x += 44) R(g, x, y - 1, 4, 7, "#1a1e27"); }
    for (let x = 30; x < 256; x += 64) { R(g, x, 0, 6, 100, "#0d0f14"); R(g, x, 0, 1, 100, "#14171e"); }
  } else if (id === "cube") {
    for (let x = 0; x < 256; x += 18) {
      const hh = 20 + (hsh(x, 5) % 30);
      R(g, x, 100 - hh, 16, hh, "#0a1428");
      R(g, x + 3, 100 - hh - 2, 4, 2, "#0d1a33"); R(g, x + 9, 100 - hh - 2, 4, 2, "#0d1a33");
      for (let j = 100 - hh + 5; j < 96; j += 8) if (hsh(x, j) % 3 === 0) R(g, x + 5, j, 3, 3, "#16244a");
    }
  } else if (id === "core") {
    for (let i = 0; i < 18; i++) { const y = hsh(i, 9) % 100; R(g, (hsh(i, 4) % 200), y, 20 + (hsh(i, 2) % 60), 1, "#14081e"); }
  } else {
    for (let i = 0; i < 10; i++) { const x = hsh(i, 1) % 240, y = hsh(i, 2) % 80; R(g, x, y, 12, 1, "#0c1a24"); R(g, x + 12, y, 1, 6, "#0c1a24"); }
  }
  // снизу плавно уходит в чёрный
  const gr = g.createLinearGradient(0, 60, 0, 100);
  gr.addColorStop(0, "rgba(0,0,0,0)");
  gr.addColorStop(1, "rgba(0,0,0,1)");
  g.fillStyle = gr;
  g.fillRect(0, 60, 256, 40);
  return cv;
}

// текст с тёмной обводкой (цифры урона, имена)
const OUT8 = [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, -1], [-1, 1], [1, 1]];
function outText(c, s, x, y, col, ink = "#000") {
  c.fillStyle = ink;
  for (const [dx, dy] of OUT8) c.fillText(s, x + dx, y + dy);
  c.fillStyle = col;
  c.fillText(s, x, y);
}

function drawHeart(c, x, y, col = "#ff2a3a") {
  x = Math.round(x); y = Math.round(y);
  R(c, x + 1, y, 2, 1, col); R(c, x + 5, y, 2, 1, col);
  R(c, x, y + 1, 8, 3, col);
  R(c, x + 1, y + 4, 6, 1, col);
  R(c, x + 2, y + 5, 4, 1, col);
  R(c, x + 3, y + 6, 2, 1, col);
  R(c, x + 1, y + 1, 1, 1, "rgba(255,255,255,0.7)");
}
