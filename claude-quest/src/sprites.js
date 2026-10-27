// Пиксельная графика: всё рисуется прямоугольниками, без картинок
const TILE = 16;
const hsh = (x, y) => (((x * 73856093) ^ (y * 19349663) ^ 0x5bd1e995) >>> 0) % 1000;

function R(c, x, y, w, h, col) {
  c.fillStyle = col;
  c.fillRect(Math.round(x), Math.round(y), w, h);
}

const ZONE_PAL = {
  lab: { g: "#3a3d56", g2: "#34374e", line: "#2c2e42", wall: "#1e2033", wallTop: "#4b4f72", deco: "#5c628e", liquid: "#3fd16b", tree: "#2c2e42" },
  slime: { g: "#2f6b3a", g2: "#367a42", line: "#285a31", wall: "#3b2f2a", wallTop: "#5b4a3f", deco: "#9be36b", liquid: "#6dff5a", tree: "#1f4d28" },
  forest: { g: "#1e4a45", g2: "#22544e", line: "#183c38", wall: "#24323a", wallTop: "#3a4f5c", deco: "#7fd8c2", liquid: "#3a8fd6", tree: "#103a2a", path: "#5a4a3a" },
  loop: { g: "#4d4466", g2: "#554b70", line: "#3e3754", wall: "#2a2238", wallTop: "#7a5a7a", deco: "#f2c46b", liquid: "#5a7ad6", tree: "#3a2a4a", path: "#6d6386" },
  robo: { g: "#454b57", g2: "#4c5260", line: "#3a3f49", wall: "#262a33", wallTop: "#69707f", deco: "#ffcf3a", liquid: "#3ad6ff", tree: "#262a33", path: "#5a606e" },
  cube: { g: "#7b7e8c", g2: "#838695", line: "#6d707d", wall: "#3b6fd1", wallTop: "#5b8ff1", deco: "#ffd84a", liquid: "#ff5a1f", tree: "#2f9e44", path: "#9a9dab" },
  core: { g: "#14101f", g2: "#191428", line: "#0d0a16", wall: "#2a0f3a", wallTop: "#5a1f7a", deco: "#ff3a8a", liquid: "#ff3a8a", tree: "#2a0f3a", path: "#221a33" },
};

const SOLID_TILES = new Set(["#", "~", "T", "o", "x", "w", "^", "B"]);

function drawTile(c, ch, x, y, zone, t, tx, ty) {
  const P = ZONE_PAL[zone] || ZONE_PAL.lab;
  const h = hsh(tx, ty);
  const ground = () => {
    R(c, x, y, 16, 16, (tx + ty) % 2 ? P.g : P.g2);
    if (zone === "cube") {
      // «шипики» базовой плиты Roblox
      R(c, x + 4, y + 4, 3, 3, P.line);
      R(c, x + 11, y + 11, 3, 3, P.line);
      R(c, x + 4, y + 3, 3, 1, P.g2);
    } else if (zone === "lab") {
      R(c, x, y + 15, 16, 1, P.line);
      if (h % 2) R(c, x + 8, y, 1, 16, P.line);
    } else if (zone === "robo") {
      R(c, x, y, 16, 1, P.line);
      R(c, x, y, 1, 16, P.line);
      R(c, x + 2, y + 2, 1, 1, "#777d8c");
      R(c, x + 13, y + 13, 1, 1, "#777d8c");
    } else if (zone === "core") {
      if (h % 7 === 0) R(c, x + (h % 13), y + (h % 11), 2, 2, (Math.floor(t * 3) + h) % 3 ? "#2a1f44" : P.deco);
    } else if (h % 5 === 0) {
      R(c, x + (h % 12) + 1, y + ((h >> 3) % 12) + 1, 2, 1, P.line);
    }
  };
  switch (ch) {
    case "#": {
      R(c, x, y, 16, 16, P.wall);
      R(c, x, y, 16, 4, P.wallTop);
      if (zone === "loop") {
        R(c, x + 2, y + 6, 5, 3, "#3a2e4e");
        R(c, x + 9, y + 10, 5, 3, "#3a2e4e");
      } else if (zone === "cube") {
        R(c, x, y, 16, 16, ["#3b6fd1", "#d13b3b", "#2f9e44", "#e8b923"][h % 4]);
        R(c, x, y, 16, 3, "rgba(255,255,255,0.25)");
        R(c, x + 3, y + 1, 3, 1, "rgba(0,0,0,0.25)");
        R(c, x + 10, y + 1, 3, 1, "rgba(0,0,0,0.25)");
      } else if (zone === "robo") {
        R(c, x + 3, y + 7, 10, 6, "#1b1e25");
        R(c, x + 4, y + 8, 2, 2, Math.floor(t * 2 + h) % 2 ? "#3aff7a" : "#1f6b3a");
      } else if (zone === "core") {
        if ((Math.floor(t * 4) + h) % 9 === 0) R(c, x + 2, y + 6, 12, 2, P.deco);
      } else {
        R(c, x, y + 4, 16, 1, "rgba(0,0,0,0.3)");
      }
      break;
    }
    case "w": {
      R(c, x, y, 16, 16, P.wall);
      R(c, x, y, 16, 4, P.wallTop);
      R(c, x + 3, y + 6, 10, 7, "#9fd3ff");
      R(c, x + 3, y + 6, 10, 2, "#d8f0ff");
      R(c, x + 7, y + 6, 1, 7, P.wall);
      break;
    }
    case "~": {
      R(c, x, y, 16, 16, P.liquid);
      const k = Math.floor(t * 2 + (tx + ty) * 0.7) % 4;
      R(c, x + 2 + k * 2, y + 4, 4, 1, "rgba(255,255,255,0.45)");
      R(c, x + 9 - k, y + 11, 4, 1, "rgba(255,255,255,0.3)");
      if (zone === "slime" && h % 4 === 0) R(c, x + 6, y + 7 - (k % 2), 2, 2, "rgba(255,255,255,0.6)");
      break;
    }
    case "^": {
      R(c, x, y, 16, 16, "#ff5a1f");
      const k = Math.floor(t * 3 + tx) % 3;
      R(c, x + 2 + k * 3, y + 3, 4, 2, "#ffd84a");
      R(c, x + 10 - k * 2, y + 10, 3, 2, "#ffb03a");
      break;
    }
    case "T": {
      ground();
      if (zone === "slime") {
        // гигантский гриб
        R(c, x + 6, y + 8, 4, 8, "#e9dcc0");
        R(c, x + 1, y + 2, 14, 7, "#d6457a");
        R(c, x + 3, y + 1, 10, 2, "#d6457a");
        R(c, x + 4, y + 4, 2, 2, "#ffd0e3");
        R(c, x + 10, y + 3, 2, 2, "#ffd0e3");
      } else if (zone === "cube") {
        R(c, x + 6, y + 9, 4, 7, "#7c5c46");
        R(c, x + 1, y + 1, 14, 9, "#2f9e44");
        R(c, x + 1, y + 1, 14, 2, "#4fbe64");
      } else {
        R(c, x + 6, y + 11, 4, 5, "#4a3424");
        R(c, x + 2, y + 4, 12, 8, P.tree);
        R(c, x + 4, y + 1, 8, 4, P.tree);
        R(c, x + 6, y, 4, 2, P.tree);
        R(c, x + 4, y + 5, 2, 2, "rgba(255,255,255,0.12)");
        if (zone === "forest" && h % 3 === 0) R(c, x + 10, y + 7, 1, 1, P.deco);
      }
      break;
    }
    case "o": {
      ground();
      R(c, x + 2, y + 6, 12, 9, zone === "cube" ? "#a3a2a5" : "#6c6a7a");
      R(c, x + 4, y + 4, 8, 3, zone === "cube" ? "#c3c2c5" : "#86849a");
      R(c, x + 3, y + 13, 10, 2, "rgba(0,0,0,0.3)");
      break;
    }
    case "B": {
      ground();
      R(c, x + 1, y + 2, 14, 13, "#5a3b2a");
      R(c, x + 1, y + 2, 14, 2, "#7a5640");
      R(c, x + 2, y + 6, 12, 1, "#3a2518");
      R(c, x + 2, y + 10, 12, 1, "#3a2518");
      R(c, x + 3, y + 4, 2, 2, "#d65a5a");
      R(c, x + 6, y + 4, 1, 2, "#5ad66b");
      R(c, x + 9, y + 7, 2, 3, "#5a8ad6");
      break;
    }
    case "x": {
      // стена Глюка
      R(c, x, y, 16, 16, "#120a1c");
      for (let i = 0; i < 6; i++) {
        const k = (h + i * 37 + Math.floor(t * 8) * 13) % 1000;
        R(c, x + (k % 14), y + ((k >> 4) % 14), 2 + (k % 3), 2, ["#ff3a8a", "#3affd8", "#ffe03a", "#8a3aff"][k % 4]);
      }
      break;
    }
    case "=": {
      R(c, x, y, 16, 16, P.path || P.g2);
      if (zone === "robo") {
        const k = Math.floor(t * 8) % 4;
        for (let i = 0; i < 4; i++) R(c, x + ((i * 4 + k) % 16), y + 2, 2, 12, "#3f4450");
      } else if (h % 3 === 0) R(c, x + (h % 11) + 2, y + 6, 3, 2, "rgba(0,0,0,0.2)");
      break;
    }
    case ",": {
      ground();
      if (zone === "slime") { R(c, x + 4, y + 9, 2, 3, "#9be36b"); R(c, x + 9, y + 5, 2, 3, "#9be36b"); R(c, x + 9, y + 4, 2, 1, "#ffe36b"); }
      else if (zone === "forest") { R(c, x + 5, y + 10, 1, 4, "#5fbf8a"); R(c, x + 4, y + 9, 3, 2, "#ff8ab0"); }
      else if (zone === "loop") { R(c, x + 6, y + 6, 4, 4, "#6a5f86"); }
      else R(c, x + 6, y + 7, 3, 2, P.deco);
      break;
    }
    default:
      ground();
  }
}

// ---------- персонажи ----------
function shadow(c, x, y, w) {
  c.fillStyle = "rgba(0,0,0,0.28)";
  c.fillRect(Math.round(x + 8 - w / 2), Math.round(y + 18), w, 2);
}

function drawHat(c, x, y, hat, dir) {
  if (!hat || hat === "none") return;
  if (hat === "crown") {
    R(c, x + 4, y - 3, 8, 3, "#ffd84a");
    R(c, x + 4, y - 5, 2, 2, "#ffd84a"); R(c, x + 7, y - 5, 2, 2, "#ffd84a"); R(c, x + 10, y - 5, 2, 2, "#ffd84a");
    R(c, x + 7, y - 2, 2, 1, "#e0425a");
  } else if (hat === "cap") {
    R(c, x + 3, y - 1, 10, 3, "#e0425a");
    if (dir !== "up") R(c, dir === "left" ? x : x + 9, y + 1, 7, 2, "#b5223a");
  } else if (hat === "wizard") {
    R(c, x + 3, y, 10, 2, "#5a3ad6");
    R(c, x + 5, y - 3, 6, 3, "#5a3ad6");
    R(c, x + 7, y - 6, 3, 3, "#5a3ad6");
    R(c, x + 7, y - 2, 1, 1, "#ffe36b");
  } else if (hat === "horns") {
    R(c, x + 3, y - 2, 2, 3, "#f2f2f2"); R(c, x + 11, y - 2, 2, 3, "#f2f2f2");
  } else if (hat === "tophat") {
    R(c, x + 3, y, 10, 2, "#1a1a22");
    R(c, x + 5, y - 5, 6, 5, "#1a1a22");
    R(c, x + 5, y - 2, 6, 1, "#c03a3a");
  } else if (hat === "antenna") {
    R(c, x + 7, y - 4, 1, 4, "#9aa"); R(c, x + 6, y - 6, 3, 2, "#ff3a3a");
  }
}

// ребёнок-стажёр (и жители): 16x20
function drawKid(c, x, y, dir, step, o = {}) {
  const skin = o.skin || "#f2c9a0";
  const hair = o.hair || "#5a3a22";
  const shirt = o.shirt || "#3a8ef0";
  const pants = o.pants || "#2a2f5a";
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 10);
  const b = step ? 1 : 0;
  // ноги
  if (dir === "left" || dir === "right") {
    R(c, x + 6, y + 16, 2, 3 - b, pants); R(c, x + 6, y + 19 - b, 3, 1, "#222");
    R(c, x + 9, y + 16, 2, 3 - (1 - b), pants); R(c, x + 9, y + 19 - (1 - b), 3, 1, "#222");
  } else {
    R(c, x + 5, y + 16, 2, 3 - b, pants); R(c, x + 5, y + 19 - b, 2, 1, "#222");
    R(c, x + 9, y + 16, 2, 3 - (1 - b), pants); R(c, x + 9, y + 19 - (1 - b), 2, 1, "#222");
  }
  // тело
  R(c, x + 4, y + 10, 8, 6, shirt);
  R(c, x + 4, y + 15, 8, 1, "rgba(0,0,0,0.25)");
  if (o.stripe) R(c, x + 4, y + 12, 8, 1, o.stripe);
  // руки
  if (dir === "left") R(c, x + 6, y + 11 + b, 2, 4, skin);
  else if (dir === "right") R(c, x + 8, y + 11 + b, 2, 4, skin);
  else { R(c, x + 2, y + 10 + b, 2, 5, shirt); R(c, x + 12, y + 11 - b, 2, 5, shirt); R(c, x + 2, y + 14 + b, 2, 1, skin); R(c, x + 12, y + 15 - b, 2, 1, skin); }
  // голова
  R(c, x + 4, y + 2, 8, 8, skin);
  if (dir === "up") {
    R(c, x + 3, y + 1, 10, 8, hair);
  } else {
    R(c, x + 3, y + 1, 10, 3, hair);
    if (dir === "down") {
      R(c, x + 3, y + 4, 1, 3, hair); R(c, x + 12, y + 4, 1, 3, hair);
      R(c, x + 6, y + 5, 1, 2, "#1a1a22"); R(c, x + 9, y + 5, 1, 2, "#1a1a22");
      R(c, x + 7, y + 8, 2, 1, "#c98a6a");
    } else if (dir === "left") {
      R(c, x + 9, y + 3, 4, 4, hair);
      R(c, x + 5, y + 5, 1, 2, "#1a1a22");
    } else {
      R(c, x + 3, y + 3, 4, 4, hair);
      R(c, x + 10, y + 5, 1, 2, "#1a1a22");
    }
  }
  drawHat(c, x, y + 1, o.hat, dir);
}

// Профессор Клод: оранжевая «искра» в лабораторном халате, 16x20
const CLAUDE = "#da7756";
const CLAUDE_D = "#b5583a";
function drawClaude(c, x, y, dir, t, o = {}) {
  x = Math.round(x);
  const bob = Math.round(Math.sin(t * 4) * 1);
  y = Math.round(y) + bob;
  const col = o.color || CLAUDE;
  const dark = o.dark || CLAUDE_D;
  shadow(c, x, y - bob, 10);
  // лучи искры
  R(c, x + 7, y, 2, 3, col);
  R(c, x + 2, y + 2, 2, 2, col); R(c, x + 3, y + 3, 2, 2, col);
  R(c, x + 12, y + 2, 2, 2, col); R(c, x + 11, y + 3, 2, 2, col);
  R(c, x, y + 6, 3, 2, col); R(c, x + 13, y + 6, 3, 2, col);
  // голова-ядро
  R(c, x + 4, y + 3, 8, 7, col);
  R(c, x + 5, y + 2, 6, 1, col);
  R(c, x + 4, y + 9, 8, 1, dark);
  // очки-гоглы на лбу
  R(c, x + 4, y + 3, 8, 1, "#3a2e2a");
  R(c, x + 5, y + 2, 2, 2, "#7fe7ff"); R(c, x + 9, y + 2, 2, 2, "#7fe7ff");
  // глаза
  if (dir !== "up") {
    const ox = dir === "left" ? -1 : dir === "right" ? 1 : 0;
    const blink = Math.floor(t * 1.3) % 5 === 0 && t % 0.77 < 0.12;
    if (blink) { R(c, x + 5 + ox, y + 6, 2, 1, "#1a1a22"); R(c, x + 9 + ox, y + 6, 2, 1, "#1a1a22"); }
    else {
      R(c, x + 5 + ox, y + 5, 2, 2, "#fff"); R(c, x + 9 + ox, y + 5, 2, 2, "#fff");
      R(c, x + 6 + ox, y + 6, 1, 1, "#1a1a22"); R(c, x + 10 + ox, y + 6, 1, 1, "#1a1a22");
    }
    if (o.evil) { R(c, x + 5 + ox, y + 5, 2, 2, "#ff2a4a"); R(c, x + 9 + ox, y + 5, 2, 2, "#ff2a4a"); }
    R(c, x + 7 + ox, y + 8, 2, 1, dark);
  }
  // халат
  R(c, x + 4, y + 10, 8, 7, o.coat || "#eef0f4");
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
    R(c, dir === "left" ? gx - 1 : gx + 3, y + 11, 2, 4, "#5aff8a");
  }
  // ножки
  R(c, x + 5, y + 17, 2, 2, col); R(c, x + 9, y + 17, 2, 2, col);
}

function drawSlime(c, x, y, t, col = "#6dff5a", o = {}) {
  x = Math.round(x); y = Math.round(y);
  const sq = Math.round(Math.sin(t * 5 + (o.phase || 0)) * 1);
  shadow(c, x, y, 12);
  const top = y + 8 + sq;
  R(c, x + 3, top, 10, 11 - sq, col);
  R(c, x + 2, top + 3, 12, 8 - sq, col);
  R(c, x + 5, top - 1, 6, 1, col);
  R(c, x + 4, top + 1, 2, 2, "rgba(255,255,255,0.6)");
  R(c, x + 2, top + 10 - sq, 12, 1, "rgba(0,0,0,0.2)");
  R(c, x + 5, top + 4, 2, 2, "#1a1a22"); R(c, x + 9, top + 4, 2, 2, "#1a1a22");
  if (o.happy) R(c, x + 6, top + 7, 4, 1, "#1a1a22");
  else R(c, x + 7, top + 7, 2, 1, "#1a1a22");
  drawHat(c, x, top - 1, o.hat, "down");
}

function drawRobot(c, x, y, t, col = "#9aa3b5", o = {}) {
  x = Math.round(x); y = Math.round(y);
  const b = Math.floor(t * 2) % 2;
  shadow(c, x, y, 12);
  R(c, x + 7, y, 2, 3, "#5a606e"); R(c, x + 6, y - 1, 4, 2, b ? "#ff3a3a" : "#ffcf3a");
  R(c, x + 3, y + 3, 10, 7, col);
  R(c, x + 4, y + 5, 8, 3, "#1b1e25");
  R(c, x + 5 + b * 4, y + 6, 2, 1, o.eye || "#3affd8");
  R(c, x + 4, y + 10, 8, 6, col);
  R(c, x + 6, y + 11, 4, 3, "#5a606e");
  R(c, x + 7, y + 12, 2, 1, b ? "#3aff7a" : "#1f6b3a");
  R(c, x + 2, y + 11, 2, 4, "#5a606e"); R(c, x + 12, y + 11, 2, 4, "#5a606e");
  R(c, x + 5, y + 16, 2, 3, "#5a606e"); R(c, x + 9, y + 16, 2, 3, "#5a606e");
}

function drawOwl(c, x, y, t) {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 10);
  R(c, x + 3, y + 4, 10, 14, "#8a6a4a");
  R(c, x + 4, y + 2, 2, 3, "#8a6a4a"); R(c, x + 10, y + 2, 2, 3, "#8a6a4a");
  R(c, x + 5, y + 10, 6, 7, "#c9a77a");
  const blink = Math.floor(t * 0.8) % 4 === 0 && (t % 1.25) < 0.15;
  R(c, x + 4, y + 5, 4, 4, "#fff"); R(c, x + 8, y + 5, 4, 4, "#fff");
  if (!blink) { R(c, x + 5, y + 6, 2, 2, "#1a1a22"); R(c, x + 9, y + 6, 2, 2, "#1a1a22"); }
  else { R(c, x + 4, y + 7, 4, 1, "#1a1a22"); R(c, x + 8, y + 7, 4, 1, "#1a1a22"); }
  R(c, x + 7, y + 9, 2, 2, "#ffb03a");
  R(c, x + 5, y + 18, 2, 1, "#ffb03a"); R(c, x + 9, y + 18, 2, 1, "#ffb03a");
}

function drawGhost(c, x, y, t, col = "#f2f2f7") {
  x = Math.round(x);
  y = Math.round(y + Math.sin(t * 3) * 2);
  R(c, x + 3, y + 2, 10, 14, col);
  R(c, x + 5, y + 1, 6, 1, col);
  for (let i = 0; i < 5; i++) R(c, x + 3 + i * 2, y + 16 + ((i + Math.floor(t * 6)) % 2), 2, 2, col);
  R(c, x + 5, y + 6, 2, 3, "#1a1a22"); R(c, x + 9, y + 6, 2, 3, "#1a1a22");
  R(c, x + 6, y + 11, 4, 2, "#1a1a22");
}

function drawNoob(c, x, y, dir, step) {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 10);
  const b = step ? 1 : 0;
  R(c, x + 4, y + 14, 3, 5 - b, "#4b974b"); R(c, x + 9, y + 14, 3, 5 - (1 - b), "#4b974b");
  R(c, x + 4, y + 8, 8, 6, "#0d69ac");
  R(c, x + 1, y + 8 + b, 3, 6, "#f5cd30"); R(c, x + 12, y + 8 + (1 - b), 3, 6, "#f5cd30");
  R(c, x + 5, y + 2, 6, 6, "#f5cd30");
  if (dir !== "up") {
    R(c, x + 6, y + 4, 1, 1, "#1a1a22"); R(c, x + 9, y + 4, 1, 1, "#1a1a22");
    R(c, x + 6, y + 6, 4, 1, "#1a1a22");
  }
}

function drawBug(c, x, y, t, col = "#e0425a") {
  x = Math.round(x); y = Math.round(y);
  const k = Math.floor(t * 8) % 2;
  shadow(c, x, y, 10);
  R(c, x + 3, y + 9, 10, 8, col);
  R(c, x + 7, y + 9, 1, 8, "#1a1a22");
  R(c, x + 5, y + 6, 6, 3, "#1a1a22");
  R(c, x + 5, y + 4 + k, 1, 2, "#1a1a22"); R(c, x + 10, y + 4 + (1 - k), 1, 2, "#1a1a22");
  R(c, x + 6, y + 7, 1, 1, "#ffe03a"); R(c, x + 9, y + 7, 1, 1, "#ffe03a");
  R(c, x + 4, y + 11, 2, 2, "#1a1a22"); R(c, x + 9, y + 13, 2, 2, "#1a1a22");
  R(c, x + 1, y + 10 + k, 2, 1, "#1a1a22"); R(c, x + 13, y + 10 + k, 2, 1, "#1a1a22");
  R(c, x + 1, y + 14 - k, 2, 1, "#1a1a22"); R(c, x + 13, y + 14 - k, 2, 1, "#1a1a22");
}

function drawNil(c, x, y, t) {
  x = Math.round(x);
  y = Math.round(y + Math.sin(t * 2) * 2);
  R(c, x + 3, y + 4, 10, 10, "#0a0a12");
  R(c, x + 4, y + 3, 8, 12, "#0a0a12");
  R(c, x + 2, y + 5, 12, 8, "#0a0a12");
  R(c, x + 5, y + 7, 2, 2, "#8a8aff"); R(c, x + 9, y + 7, 2, 2, "#8a8aff");
  c.fillStyle = "#8a8aff";
  c.font = "5px monospace";
  c.fillText("nil", x + 4, y + 13);
}

function drawMushroom(c, x, y, t) {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 10);
  R(c, x + 5, y + 10, 6, 8, "#efe2c8");
  R(c, x + 6, y + 13, 1, 2, "#1a1a22"); R(c, x + 9, y + 13, 1, 2, "#1a1a22");
  R(c, x + 2, y + 4, 12, 6, "#3ab5d6");
  R(c, x + 4, y + 2, 8, 2, "#3ab5d6");
  R(c, x + 4, y + 5, 2, 2, "#e8fbff"); R(c, x + 10, y + 4, 2, 2, "#e8fbff");
}

function drawCat(c, x, y, t, col = "#3a3a44") {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 10);
  R(c, x + 4, y + 10, 9, 7, col);
  R(c, x + 3, y + 4, 8, 7, col);
  R(c, x + 3, y + 2, 2, 2, col); R(c, x + 9, y + 2, 2, 2, col);
  R(c, x + 5, y + 6, 1, 2, "#ffe03a"); R(c, x + 8, y + 6, 1, 2, "#ffe03a");
  const k = Math.floor(t * 2) % 2;
  R(c, x + 13, y + 8 - k, 2, 6, col);
}

function drawStar(c, x, y, t) {
  x = Math.round(x); y = Math.round(y);
  const g = Math.floor(t * 4) % 2;
  const col = g ? "#ffe36b" : "#ffd23a";
  R(c, x + 7, y + 3, 2, 12, col);
  R(c, x + 2, y + 8, 12, 2, col);
  R(c, x + 5, y + 6, 6, 6, col);
  R(c, x + 4, y + 12, 2, 2, col); R(c, x + 10, y + 12, 2, 2, col);
  if (g) { R(c, x + 1, y + 2, 1, 1, "#fff"); R(c, x + 14, y + 4, 1, 1, "#fff"); }
}

function drawPortal(c, x, y, t, open = true, w = 2) {
  x = Math.round(x); y = Math.round(y);
  const W = 16 * w;
  if (!open) {
    R(c, x + 4, y + 4, W - 8, 26, "#2a2d3a");
    R(c, x + 6, y + 6, W - 12, 22, "#1a1c26");
    if (Math.floor(t * 6) % 3 === 0) R(c, x + W / 2 - 1, y + 10, 2, 8, "#5aff8a");
    return;
  }
  const cols = ["#2aff6a", "#9affb0", "#18c94a", "#d8ffe0"];
  for (let r = 0; r < 5; r++) {
    c.fillStyle = cols[(r + Math.floor(t * 8)) % 4];
    const rx = W / 2 - 2 - r * 2.2, ry = 15 - r * 2.6;
    c.beginPath();
    c.ellipse(x + W / 2, y + 16, Math.max(1, rx), Math.max(1, ry), 0, 0, Math.PI * 2);
    c.fill();
  }
  for (let i = 0; i < 6; i++) {
    const a = t * 3 + i;
    R(c, x + W / 2 + Math.cos(a) * (W / 2 - 3), y + 16 + Math.sin(a) * 13, 1, 1, "#eaffef");
  }
}

function drawMachine(c, x, y, t, open) {
  x = Math.round(x); y = Math.round(y);
  R(c, x, y + 26, 32, 6, "#5a5f76");
  R(c, x + 1, y, 3, 28, "#6c7290"); R(c, x + 28, y, 3, 28, "#6c7290");
  R(c, x + 1, y, 30, 3, "#6c7290");
  R(c, x + 4, y + 30, 4, 2, Math.floor(t * 2) % 2 ? "#ff3a3a" : "#5a1a1a");
  R(c, x + 24, y + 30, 4, 2, open ? "#3aff7a" : "#1a3a1a");
  drawPortal(c, x, y - 1, t, open, 2);
}

function drawTerminal(c, x, y, t) {
  x = Math.round(x); y = Math.round(y);
  R(c, x + 1, y + 2, 14, 11, "#2a2d3a");
  R(c, x + 2, y + 3, 12, 8, "#0d1a12");
  const k = Math.floor(t * 3) % 4;
  R(c, x + 3, y + 4, 6, 1, "#3aff7a"); R(c, x + 3, y + 6, 8 - k, 1, "#3aff7a"); R(c, x + 3, y + 8, 4, 1, "#3aff7a");
  if (Math.floor(t * 2) % 2) R(c, x + 8, y + 8, 2, 1, "#3aff7a");
  R(c, x + 6, y + 13, 4, 2, "#2a2d3a"); R(c, x + 3, y + 15, 10, 1, "#2a2d3a");
}

function drawStation(c, x, y, t, done) {
  // учебный камень с книгой
  x = Math.round(x); y = Math.round(y);
  const glow = done ? "#5aff8a" : Math.floor(t * 3) % 2 ? "#ffe36b" : "#ffb03a";
  shadow(c, x, y, 14);
  R(c, x + 2, y + 9, 12, 9, "#6c6a7a");
  R(c, x + 3, y + 8, 10, 2, "#86849a");
  R(c, x + 3, y + 5, 10, 4, "#f2ead8");
  R(c, x + 7, y + 5, 2, 4, "#c9bfa6");
  R(c, x + 4, y + 6, 2, 1, "#8a7a5a"); R(c, x + 10, y + 6, 2, 1, "#8a7a5a");
  R(c, x + 7, y + 1 + (Math.floor(t * 2) % 2), 2, 2, glow);
  if (!done) { R(c, x + 4, y + 2, 1, 1, glow); R(c, x + 11, y + 3, 1, 1, glow); }
}

function drawChest(c, x, y, open) {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 14);
  R(c, x + 2, y + 8, 12, 10, "#8a5a2a");
  R(c, x + 2, y + 12, 12, 1, "#5a3a1a");
  if (open) R(c, x + 2, y + 4, 12, 4, "#6a4a2a");
  else { R(c, x + 2, y + 5, 12, 4, "#a06a32"); R(c, x + 7, y + 10, 2, 3, "#ffd84a"); }
}

function drawSign(c, x, y) {
  x = Math.round(x); y = Math.round(y);
  shadow(c, x, y, 8);
  R(c, x + 7, y + 10, 2, 9, "#6a4a2a");
  R(c, x + 2, y + 3, 12, 8, "#a07a4a");
  R(c, x + 3, y + 5, 10, 1, "#5a3a1a"); R(c, x + 3, y + 8, 7, 1, "#5a3a1a");
}

function drawPoster(c, x, y) {
  x = Math.round(x); y = Math.round(y);
  R(c, x + 1, y + 1, 14, 14, "#1e2a3a");
  R(c, x + 2, y + 2, 12, 12, "#2e5a8a");
  R(c, x + 4, y + 8, 8, 5, "#8a8f9a");
  R(c, x + 6, y + 6, 4, 2, "#8a8f9a");
  R(c, x + 7, y + 10, 2, 3, "#3a2a1a");
  R(c, x + 3, y + 3, 10, 2, "#ffd84a");
}

function drawFridge(c, x, y) {
  x = Math.round(x); y = Math.round(y);
  R(c, x + 2, y - 4, 12, 20, "#dfe6ee");
  R(c, x + 2, y + 3, 12, 1, "#9aa6b5");
  R(c, x + 11, y - 1, 1, 3, "#7a8696"); R(c, x + 11, y + 6, 1, 4, "#7a8696");
  R(c, x + 4, y - 2, 3, 3, "#ff8a3a");
}

function drawClock(c, x, y, t) {
  x = Math.round(x); y = Math.round(y);
  R(c, x + 4, y - 20, 24, 52, "#3a2e4e");
  R(c, x + 2, y - 24, 28, 6, "#7a5a7a");
  R(c, x + 6, y - 14, 20, 20, "#f2e6c8");
  const cx = x + 16, cy = y - 4;
  const a = t * 6;
  c.strokeStyle = "#1a1a22";
  c.lineWidth = 1;
  c.beginPath(); c.moveTo(cx, cy); c.lineTo(cx + Math.cos(a) * 7, cy + Math.sin(a) * 7); c.stroke();
  c.beginPath(); c.moveTo(cx, cy); c.lineTo(cx + Math.cos(a / 12) * 5, cy + Math.sin(a / 12) * 5); c.stroke();
  R(c, x + 12, y + 14, 8, 16, "#1a1426");
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
function battleSprite(c, e, cx, cy, t, hurt) {
  c.save();
  const sc = e.scale || 3;
  const shake = hurt > 0 ? Math.round(Math.sin(t * 60) * 3) : 0;
  c.translate(Math.round(cx - 8 * sc + shake), Math.round(cy - 10 * sc));
  c.scale(sc, sc);
  const tt = t;
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
      R(c, 6, 12, 4, 8, "#4a3424");
      R(c, 1, 4, 14, 10, "#1f6b4a"); R(c, 3, 1, 10, 4, "#1f6b4a");
      R(c, 4, 6, 3, 3, "#fff"); R(c, 9, 6, 3, 3, "#fff");
      R(c, 5, 7, 1, 1, "#1a1a22"); R(c, 10, 7, 1, 1, "#1a1a22");
      R(c, 6, 11, 4, 1, "#1a1a22");
      R(c, -2, 9, 4, 6, "#c0c8d0"); R(c, 14, 9, 4, 6, "#c0c8d0");
      c.fillStyle = "#1a1a22"; c.font = "4px monospace"; c.fillText("if", -1.5, 13); c.fillText("else", 13.6, 13);
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
      c.fillStyle = "#fff"; c.font = "3px monospace"; c.fillText("while true", 1.5, 11);
      break;
    }
    case "lava": {
      const g = Math.floor(tt * 3) % 2;
      R(c, 0, 2, 16, 16, "#ff5a1f");
      R(c, 0, 2, 16, 3, "#ffb03a");
      R(c, 2 + g, 8, 3, 3, "#1a1a22"); R(c, 11 - g, 8, 3, 3, "#1a1a22");
      R(c, 5, 14, 6, 2, "#1a1a22");
      R(c, 1, 17 + g, 3, 2, "#ff5a1f"); R(c, 12, 17 + (1 - g), 3, 2, "#ff5a1f");
      R(c, 3, 3, 2, 1, "#ffe36b"); R(c, 10, 4, 3, 1, "#ffe36b");
      break;
    }
    case "boss-robot": {
      R(c, -2, 2, 20, 12, "#c05a5a");
      R(c, 0, 4, 16, 6, "#1b1e25");
      const k = Math.floor(tt * 3) % 3;
      R(c, 2 + k * 4, 6, 3, 2, "#ff3a3a");
      R(c, 3, 14, 10, 6, "#8a3a3a");
      R(c, 6, 0, 4, 2, "#ffcf3a");
      c.fillStyle = "#ffcf3a"; c.font = "3px monospace"; c.fillText("return", 3.5, 18.5);
      break;
    }
    default: drawSlime(c, 0, 0, tt, e.color);
  }
  c.restore();
  // эффект глюка у боссов
  if (e.glitch && Math.random() < 0.18) {
    const y = cy - 10 * sc + Math.random() * 20 * sc;
    const img = c.getImageData(Math.max(0, cx - 30 * sc / 3 * 3), Math.max(0, Math.round(y)), Math.round(20 * sc), 3);
    c.putImageData(img, Math.max(0, cx - 30 * sc / 3 * 3) + (Math.random() * 10 - 5), Math.round(y));
  }
}

function drawHeart(c, x, y, col = "#ff2a3a") {
  x = Math.round(x); y = Math.round(y);
  R(c, x + 1, y, 2, 1, col); R(c, x + 5, y, 2, 1, col);
  R(c, x, y + 1, 8, 3, col);
  R(c, x + 1, y + 4, 6, 1, col);
  R(c, x + 2, y + 5, 4, 1, col);
  R(c, x + 3, y + 6, 2, 1, col);
}
