// Главный движок: мир, управление, диалоги, меню, сохранения, звук
const W = 256, H = 192;
const G = {
  save: null, mode: "title", zone: null, overlay: null,
  player: { x: 0, y: 0, dir: "down", step: 0, stepT: 0, moving: false },
  claude: { x: 0, y: 0, dir: "down" }, trail: [],
  cam: { x: 0, y: 0 }, t: 0,
  input: { dx: 0, dy: 0, dragX: 0, dragY: 0, keys: {} },
  target: null, particles: [], shakeT: 0, flashC: null, flashT: 0, fade: 0,
  sceneRunning: false, sceneQueue: [], pendingBattle: null, pendingTravel: null,
};
let cv, ctx, scr, sctx;

function newSave(name, shirt, hair) {
  return {
    v: 1, name, shirt, hair, savedAt: Date.now(), zone: "lab", x: null, y: null,
    hp: 20, lv: 1, xp: 0, gold: 0, atkBonus: 0, items: [], flags: {}, practice: {}, hw: {}, code: {},
    customHw: [], customNpcs: {}, chat: [], kills: 0, spares: 0, stats: {}, lastTask: null,
    rules: { ...RULE_DEFAULTS }, settings: { music: true, sfx: true, smart: false },
  };
}
function fixSave(s) {
  const d = newSave(s.name || "Стажёр", s.shirt || "#3a8ef0", s.hair || "#5a3a22");
  for (const k in d) if (s[k] === undefined) s[k] = d[k];
  s.rules = { ...RULE_DEFAULTS, ...(s.rules || {}) };
  s.settings = { ...d.settings, ...(s.settings || {}) };
  return s;
}
const flag = (f) => !!(G.save && G.save.flags[f]);
const playerLook = () => ({
  shirt: (G.save && G.save.rules.playerColor) || (G.save && G.save.shirt) || "#3a8ef0",
  hair: (G.save && G.save.hair) || "#5a3a22",
  hat: G.save && G.save.rules.hat,
});

// ---------------- сохранения ----------------
const SAVE_KEY = "kod-multiverse-save-v1";
const Store = { db: null, uid: null, writing: false, lastDb: 0, pending: false };
function readLocal() {
  try {
    const raw = localStorage.getItem(SAVE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (e) {
    return null;
  }
}
let saveTimer = 0;
function saveSoon() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(saveNow, 1200);
}
function saveNow() {
  if (!G.save || G.mode === "title") return;
  const s = G.save;
  if (G.zone && G.mode === "world") { s.zone = G.zone.id; s.x = Math.round(G.player.x); s.y = Math.round(G.player.y); }
  s.savedAt = Date.now();
  if (s.chat.length > 60) s.chat = s.chat.slice(-60);
  try { localStorage.setItem(SAVE_KEY, JSON.stringify(s)); } catch (e) {}
  saveDb();
}
async function saveDb() {
  if (!Store.db || !Store.uid) return;
  if (Store.writing) { Store.pending = true; return; }
  const wait = 6000 - (Date.now() - Store.lastDb);
  if (wait > 0) { Store.pending = true; setTimeout(() => { if (Store.pending) { Store.pending = false; saveDb(); } }, wait); return; }
  Store.writing = true;
  Store.lastDb = Date.now();
  try {
    await Store.db.doc("data/users/" + Store.uid + "/save").set({ json: JSON.stringify(G.save), savedAt: G.save.savedAt });
  } catch (e) {
    if (e && (e.code === "invalid_argument" || e.code === "revoked" || e.code === "not_granted")) Store.db = null;
  } finally {
    Store.writing = false;
    if (Store.pending) { Store.pending = false; setTimeout(saveDb, 500); }
  }
}
async function initStore() {
  try {
    if (!window.claude || typeof window.claude.use !== "function") return;
    const [db, user] = await Promise.all([window.claude.use("db"), window.claude.use("user")]);
    if (!db || !user) return;
    const id = await user.id();
    if (!id) return;
    Store.db = db;
    Store.uid = id;
    const snap = await db.doc("data/users/" + id + "/save").get();
    if (snap.exists) {
      const d = snap.data();
      const remote = JSON.parse(d.json);
      const local = G.save || readLocal();
      if (!local || (remote.savedAt || 0) > (local.savedAt || 0)) {
        try { localStorage.setItem(SAVE_KEY, d.json); } catch (e) {}
        if (G.mode === "title") showTitle();
      }
    }
  } catch (e) {
    Store.db = null;
  }
}

// ---------------- звук ----------------
const Snd = { ctx: null, master: null, music: null, theme: null, step: 0, timer: 0 };
function audioUnlock() {
  if (Snd.ctx) { if (Snd.ctx.state === "suspended") Snd.ctx.resume(); return; }
  try {
    Snd.ctx = new (window.AudioContext || window.webkitAudioContext)();
    Snd.master = Snd.ctx.createGain();
    Snd.master.gain.value = 0.5;
    Snd.master.connect(Snd.ctx.destination);
    Snd.music = Snd.ctx.createGain();
    Snd.music.gain.value = 0.18;
    Snd.music.connect(Snd.master);
    if (Snd.want) music(Snd.want);
  } catch (e) {
    Snd.ctx = null;
  }
}
function tone(f, dur, type = "square", vol = 0.2, when = 0, dest, slide) {
  if (!Snd.ctx) return;
  const t0 = Snd.ctx.currentTime + when;
  const o = Snd.ctx.createOscillator();
  const g = Snd.ctx.createGain();
  o.type = type;
  o.frequency.setValueAtTime(f, t0);
  if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(20, slide), t0 + dur);
  g.gain.setValueAtTime(vol, t0);
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
  o.connect(g);
  g.connect(dest || Snd.master);
  o.start(t0);
  o.stop(t0 + dur + 0.02);
}
const midi = (n) => 440 * Math.pow(2, (n - 69) / 12);
function sfx(name, pitch = 1) {
  if (!Snd.ctx || !G.save || !G.save.settings.sfx) return;
  switch (name) {
    case "blip": tone(520 * pitch, 0.035, "square", 0.05); break;
    case "select": tone(660, 0.05, "square", 0.08); tone(990, 0.06, "square", 0.06, 0.04); break;
    case "hit": tone(220, 0.15, "sawtooth", 0.15, 0, null, 60); break;
    case "hurt": tone(150, 0.2, "square", 0.15, 0, null, 70); break;
    case "heal": [0, 4, 7, 12].forEach((n, i) => tone(midi(72 + n), 0.12, "triangle", 0.12, i * 0.06)); break;
    case "portal": tone(200, 0.6, "sine", 0.15, 0, null, 1200); tone(300, 0.6, "triangle", 0.08, 0.05, null, 1600); break;
    case "glitch": for (let i = 0; i < 6; i++) tone(100 + Math.random() * 900, 0.04, "square", 0.08, i * 0.04); break;
    case "victory": [0, 4, 7, 12, 7, 12].forEach((n, i) => tone(midi(67 + n), 0.14, "square", 0.1, i * 0.09)); break;
    case "levelup": [0, 2, 4, 5, 7, 9, 11, 12].forEach((n, i) => tone(midi(72 + n), 0.08, "square", 0.08, i * 0.05)); break;
    case "encounter": tone(880, 0.06, "square", 0.12); tone(880, 0.06, "square", 0.12, 0.1); tone(1320, 0.12, "square", 0.12, 0.2); break;
    case "die": tone(400, 0.8, "sawtooth", 0.15, 0, null, 40); break;
    case "save": [0, 7, 12].forEach((n, i) => tone(midi(76 + n), 0.15, "triangle", 0.1, i * 0.08)); break;
    case "step": tone(90, 0.03, "triangle", 0.04); break;
  }
}
const THEMES = {
  lab: { bpm: 96, bass: [45, 0, 52, 0, 45, 0, 52, 0, 43, 0, 50, 0, 43, 0, 50, 0], lead: [69, 0, 72, 0, 76, 0, 72, 0, 67, 0, 71, 0, 74, 0, 71, 0], lt: "triangle" },
  slime: { bpm: 118, bass: [48, 0, 55, 0, 48, 0, 55, 0, 53, 0, 60, 0, 53, 0, 60, 0], lead: [72, 74, 76, 0, 79, 0, 76, 0, 77, 76, 74, 0, 72, 0, 0, 0], lt: "square" },
  forest: { bpm: 88, bass: [45, 0, 0, 52, 45, 0, 0, 52, 41, 0, 0, 48, 43, 0, 0, 50], lead: [69, 0, 72, 0, 71, 0, 69, 0, 65, 0, 69, 0, 67, 0, 0, 0], lt: "triangle" },
  loop: { bpm: 108, bass: [43, 0, 50, 50, 43, 0, 50, 50, 43, 0, 50, 50, 43, 0, 50, 50], lead: [67, 71, 74, 71, 67, 71, 74, 71, 67, 71, 74, 71, 67, 71, 74, 79], lt: "square" },
  robo: { bpm: 126, bass: [36, 36, 48, 36, 36, 48, 36, 48, 39, 39, 51, 39, 39, 51, 39, 51], lead: [60, 0, 63, 0, 67, 0, 63, 0, 63, 0, 67, 0, 70, 0, 67, 0], lt: "square" },
  cube: { bpm: 122, bass: [48, 0, 52, 0, 55, 0, 52, 0, 53, 0, 57, 0, 55, 0, 52, 0], lead: [72, 76, 79, 76, 74, 77, 81, 77, 72, 76, 79, 84, 79, 0, 76, 0], lt: "square" },
  core: { bpm: 78, bass: [40, 0, 0, 0, 41, 0, 0, 0, 40, 0, 0, 0, 39, 0, 0, 0], lead: [64, 0, 63, 0, 64, 0, 0, 0, 67, 0, 66, 0, 64, 0, 0, 0], lt: "sawtooth" },
  battle: { bpm: 150, bass: [45, 57, 45, 57, 43, 55, 43, 55, 41, 53, 41, 53, 40, 52, 40, 52], lead: [69, 0, 72, 74, 0, 72, 69, 0, 67, 0, 69, 71, 0, 69, 67, 0], lt: "square" },
  boss: { bpm: 160, bass: [38, 50, 38, 50, 38, 50, 41, 53, 36, 48, 36, 48, 40, 52, 40, 52], lead: [74, 0, 77, 0, 81, 0, 79, 77, 72, 0, 76, 0, 79, 0, 77, 76], lt: "square" },
  title: { bpm: 90, bass: [45, 0, 0, 0, 48, 0, 0, 0, 43, 0, 0, 0, 40, 0, 0, 0], lead: [76, 0, 74, 0, 72, 0, 74, 76, 79, 0, 76, 0, 74, 0, 0, 0], lt: "triangle" },
};
function music(name) {
  Snd.want = name;
  if (Snd.theme === name && Snd.timer) return;
  clearInterval(Snd.timer);
  Snd.timer = 0;
  Snd.theme = name;
  if (!name || !Snd.ctx || !THEMES[name]) return;
  const th = THEMES[name];
  Snd.step = 0;
  const stepDur = 60 / th.bpm / 2;
  Snd.timer = setInterval(() => {
    if (!G.save || G.save.settings.music === false || document.hidden) return;
    const i = Snd.step++ % 16;
    const b = th.bass[i], l = th.lead[i];
    if (b) tone(midi(b), stepDur * 0.9, "triangle", 0.5, 0, Snd.music);
    if (l) tone(midi(l), stepDur * 0.8, th.lt, 0.22, 0, Snd.music);
  }, stepDur * 1000);
}

// ---------------- эффекты ----------------
function toast(t) {
  const el = document.getElementById("toast");
  el.textContent = t;
  el.classList.add("show");
  clearTimeout(toast.t);
  toast.t = setTimeout(() => el.classList.remove("show"), 2600);
}
function flash(c) { G.flashC = c; G.flashT = 0.5; }
function shake(n) { G.shakeT = 0.25; G.shakeN = n; }
function fadeOut() { return new Promise((r) => { G.fadeDir = 1; G.fadeDone = r; }); }
function fadeIn() { return new Promise((r) => { G.fadeDir = -1; G.fadeDone = r; }); }

function giveItem(it, quiet) {
  G.save.items.push(it);
  if (G.save.items.length > 12) G.save.items.shift();
  if (!quiet) toast(`Получено: ${it.name}`);
  sfx("heal");
  saveSoon();
}
const XP_LV = [0, 12, 35, 70, 120, 190, 280, 400, 560, 760, 1000, 1300, 1700, 2200];
function addXp(n) {
  const s = G.save;
  s.xp += n;
  let up = false;
  while (s.lv < XP_LV.length && s.xp >= XP_LV[s.lv]) { s.lv++; up = true; }
  if (up) {
    s.hp = playerMaxHp();
    sfx("levelup");
    toast(`LV ${s.lv}! Здоровье и сила выросли`);
  }
  updateHud();
}

// ---------------- панели и диалоги ----------------
let curPanel = "pad";
function panel(name) {
  curPanel = name;
  document.getElementById("pad").hidden = name !== "pad";
  document.getElementById("dlg").hidden = name !== "dlg";
  document.getElementById("bat").hidden = name !== "bat";
  document.getElementById("batTouch").hidden = !(name === "bat" && Battle.b && Battle.b.phase === "dodge");
  document.body.dataset.panel = name;
}

let typing = null;
function typeInto(el, text, who, instant) {
  if (typing && typing.el === el) typing.cancel();
  return new Promise((resolve) => {
    const speed = 22 + (G.save ? G.save.rules.textSpeed : 2) * 14;
    const pitch = (SPEAKERS[who] || SPEAKERS.sys).pitch;
    let i = 0;
    let done = false;
    el.textContent = "";
    const fin = () => {
      if (done) return;
      done = true;
      el.textContent = text;
      clearInterval(tm);
      typing = null;
      resolve();
    };
    if (instant) { el.textContent = text; resolve(); return; }
    const tm = setInterval(() => {
      i += 1;
      el.textContent = text.slice(0, i);
      if (i % 2 === 0 && text[i] && text[i] !== " ") sfx("blip", pitch);
      if (i >= text.length) fin();
    }, 1000 / speed);
    typing = { el, cancel: fin, skip: fin };
  });
}

let dlgWait = null;
function showDlg(who, text) {
  panel("dlg");
  const S = SPEAKERS[who] || SPEAKERS.sys;
  const name = who === "player" ? G.save.name : S.name;
  const nm = document.getElementById("dlgName");
  nm.textContent = name || "";
  nm.style.color = S.color;
  nm.hidden = !name;
  G.dlgWho = who;
  document.getElementById("dlgPortrait").hidden = !S.draw;
  document.getElementById("dlgChoices").innerHTML = "";
  document.getElementById("dlgNext").hidden = true;
  return typeInto(document.getElementById("dlgText"), text, who);
}
async function say(who, text) {
  await showDlg(who, text);
  document.getElementById("dlgNext").hidden = false;
  await new Promise((r) => (dlgWait = r));
  dlgWait = null;
}
async function sayLong(who, text) {
  // длинный ответ живого Клода — режем на куски
  const parts = [];
  let cur = "";
  for (const sent of String(text).replace(/```[\s\S]*?```/g, "").split(/(?<=[.!?…])\s+/)) {
    if ((cur + " " + sent).length > 170 && cur) { parts.push(cur.trim()); cur = sent; }
    else cur += " " + sent;
  }
  if (cur.trim()) parts.push(cur.trim());
  for (const p of parts.slice(0, 6)) await say(who, p);
}
async function ask(who, text, options) {
  await showDlg(who, text);
  const box = document.getElementById("dlgChoices");
  return new Promise((resolve) => {
    options.forEach((o, i) => {
      const b = document.createElement("button");
      b.className = "choice";
      b.textContent = o;
      b.onclick = (e) => {
        e.stopPropagation();
        sfx("select");
        box.innerHTML = "";
        resolve(i);
      };
      box.appendChild(b);
    });
  });
}
function dlgThinking(text) {
  if (!text) { clearInterval(dlgThinking.t); return; }
  panel("dlg");
  document.getElementById("dlgChoices").innerHTML = "";
  document.getElementById("dlgNext").hidden = true;
  let n = 0;
  const el = document.getElementById("dlgText");
  clearInterval(dlgThinking.t);
  dlgThinking.t = setInterval(() => { el.textContent = text + ".".repeat((n++ % 3) + 1); }, 350);
}
function dlgTap() {
  if (typing) { typing.skip(); return; }
  if (dlgWait) { sfx("select"); dlgWait(); }
}

async function runScene(fn) {
  if (G.sceneRunning) { G.sceneQueue.push(fn); return; }
  G.sceneRunning = true;
  G.target = null;
  try {
    await fn();
  } catch (e) {
    console.error(e);
  }
  G.sceneRunning = false;
  if (!Battle.active) panel("pad");
  if (G.sceneQueue.length) runScene(G.sceneQueue.shift());
  else updateHud();
}
const queueScene = runScene;

// ---------------- миры ----------------
function enterZone(id, keepPos) {
  const def = ZONES[id];
  const map = def.map.map((r) => r.split(""));
  const z = { id, def, map, w: map[0].length, h: map.length, objs: [], roamers: [], glitchOpen: zoneLessonsDone(id) && def.lessons.length > 0 };
  let spawn = null;
  for (let ty = 0; ty < z.h; ty++) {
    for (let tx = 0; tx < z.w; tx++) {
      const ch = map[ty][tx];
      if (ch === "@") { spawn = { x: tx * 16, y: ty * 16 - 6 }; map[ty][tx] = "."; continue; }
      if (ch === "S") { z.objs.push({ type: "star", x: tx * 16, y: ty * 16 - 4, w: 16, solid: false }); map[ty][tx] = "."; continue; }
      if (ch === "P" && id !== "lab") { z.objs.push({ type: "portal", x: tx * 16, y: ty * 16 - 14, w: 16, solid: false }); map[ty][tx] = "."; continue; }
      const mk = def.marks[ch];
      if (mk) {
        map[ty][tx] = ".";
        if (mk.if && !mk.if()) continue;
        const o = { ...mk, x: tx * 16, y: ty * 16 - 4, w: mk.w || 16, solid: true };
        if (mk.type === "machine") { o.y = ty * 16 - 18; }
        if (mk.type === "clock") { o.y = ty * 16; }
        if (mk.type === "poster" || mk.type === "terminal" || mk.type === "fridge") { o.y = ty * 16 - 2; }
        z.objs.push(o);
      }
    }
  }
  for (const n of (G.save.customNpcs[id] || [])) z.objs.push({ type: "npc", custom: n, x: n.x, y: n.y, w: 16, solid: true });
  for (const [kind, tx, ty] of def.bugs || []) z.roamers.push({ kind, x: tx * 16, y: ty * 16 - 4, vx: 0, vy: 0, t: Math.random() * 2, cool: 0 });
  G.zone = z;
  z.spawn = spawn || { x: 32, y: 32 };
  if (keepPos && G.save.zone === id && G.save.x != null) { G.player.x = G.save.x; G.player.y = G.save.y; }
  else { G.player.x = z.spawn.x; G.player.y = z.spawn.y; }
  if (!walkable(G.player.x, G.player.y)) { G.player.x = z.spawn.x; G.player.y = z.spawn.y; }
  G.claude.x = G.player.x - 14;
  G.claude.y = G.player.y;
  G.trail = [];
  G.target = null;
  G.save.zone = id;
  music(def.music);
  showZoneTitle(def.name, def.sub);
  updateHud();
}

function showZoneTitle(n, sub) {
  const el = document.getElementById("zoneTitle");
  el.innerHTML = `<b>${n}</b><span>${sub}</span>`;
  el.classList.remove("show");
  void el.offsetWidth;
  el.classList.add("show");
}

function tileAt(px, py) {
  const z = G.zone;
  const tx = Math.floor(px / 16), ty = Math.floor(py / 16);
  if (tx < 0 || ty < 0 || tx >= z.w || ty >= z.h) return "#";
  return z.map[ty][tx];
}
function solidTile(ch) {
  if (ch === "x") return !G.zone.glitchOpen;
  return SOLID_TILES.has(ch);
}
function footBox(o) {
  if (o.type === "machine") return { x: o.x + 2, y: o.y + 24, w: 28, h: 10 };
  if (o.type === "clock") return { x: o.x + 4, y: o.y - 6, w: 24, h: 38 };
  if (o.type === "poster" || o.type === "terminal" || o.type === "fridge") return { x: o.x + 1, y: o.y + 4, w: 14, h: 12 };
  return { x: o.x + 3, y: o.y + 13, w: 10, h: 7 };
}
function playerFoot(x, y) { return { x: x + 4, y: y + 14, w: 8, h: 6 }; }
const overlap = (a, b) => a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
function walkable(x, y) {
  const f = playerFoot(x, y);
  for (const [px, py] of [[f.x, f.y], [f.x + f.w - 1, f.y], [f.x, f.y + f.h - 1], [f.x + f.w - 1, f.y + f.h - 1]]) if (solidTile(tileAt(px, py))) return false;
  for (const o of G.zone.objs) if (o.solid && overlap(f, footBox(o))) return false;
  return true;
}

function spawnCustomNpc(i) {
  const z = G.zone;
  const p = G.player;
  let x = p.x + 20, y = p.y;
  for (const [dx, dy] of [[20, 0], [-20, 0], [0, 20], [0, -20], [20, 20], [-20, -20]]) {
    if (walkable(p.x + dx, p.y + dy)) { x = p.x + dx; y = p.y + dy; break; }
  }
  const n = {
    name: String(i.name || "Незнакомец").slice(0, 24),
    look: ["slime", "robot", "ghost", "cat", "kid", "noob", "owl", "mushroom", "bug"].includes(i.look) ? i.look : "kid",
    color: /^#[0-9a-f]{6}$/i.test(i.color || "") ? i.color : "#ff8ad0",
    lines: (Array.isArray(i.lines) ? i.lines : [String(i.lines || "Привет!")]).map((l) => String(l).slice(0, 200)).slice(0, 6),
    x: Math.round(x), y: Math.round(y),
  };
  G.save.customNpcs[z.id] = (G.save.customNpcs[z.id] || []).concat([n]).slice(-8);
  z.objs.push({ type: "npc", custom: n, x: n.x, y: n.y, w: 16, solid: true });
  return n;
}

// ---------------- взаимодействие ----------------
function nearestInteract() {
  const p = G.player;
  const f = playerFoot(p.x, p.y);
  const reach = { x: f.x - 9, y: f.y - 10, w: f.w + 18, h: f.h + 18 };
  let best = null, bd = 1e9;
  for (const o of G.zone.objs) {
    if (o.type === "boss" && G.save.flags["boss_" + G.zone.id]) continue;
    if (o.type === "boss" && !G.zone.glitchOpen && G.zone.def.lessons.length) continue;
    if (o.type === "chest" && G.save.flags[o.id]) continue;
    const b = footBox(o);
    if (!overlap(reach, b)) continue;
    const d = Math.hypot(b.x + b.w / 2 - (f.x + f.w / 2), b.y + b.h / 2 - (f.y + f.h / 2));
    if (d < bd) { bd = d; best = o; }
  }
  if (!best && G.save.rules.claudeFollows && Math.hypot(G.claude.x - p.x, G.claude.y - p.y) < 22) best = { type: "claude" };
  return best;
}

function interact(o) {
  if (!o || G.sceneRunning || G.mode !== "world") return;
  G.target = null;
  if (o.type === "claude") return runScene(talkClaude);
  if (o.type === "star") return runScene(async () => {
    G.save.hp = playerMaxHp();
    sfx("save");
    saveNow();
    await say("sys", "* Код компилируется без ошибок. Это наполняет тебя РЕШИМОСТЬЮ.");
    await say("sys", "* HP восстановлено. Игра сохранена.");
  });
  if (o.type === "portal") return runScene(async () => {
    const c = await ask("sys", "* Портал домой, в гараж Клода. Прыгнуть?", ["Прыгнуть", "Остаться"]);
    if (c === 0) await travel("lab");
  });
  if (o.type === "station") return runScene(() => lessonScene(o.lesson));
  if (o.type === "sign") return runScene(() => say("sys", "* " + o.text));
  if (o.type === "chest") return runScene(async () => {
    G.save.flags[o.id] = true;
    await say("sys", "* Ты открываешь сундук...");
    giveItem(o.item);
    await say("sys", `* Внутри: ${o.item.name}. ${o.item.desc}`);
  });
  if (o.type === "boss") return runScene(() => bossScene(o.enemy));
  if (o.type === "npc" && o.custom) return runScene(async () => {
    SPEAKERS.custom.name = o.custom.name;
    SPEAKERS.custom.color = o.custom.color;
    SPEAKERS.custom.draw = (c, t) => drawLook(c, o.custom.look, 0, 0, t, o.custom.color);
    for (const l of o.custom.lines) await say("custom", l);
  });
  if (o.talk) return runScene(o.talk);
}

// ---------------- обновление ----------------
function update(dt) {
  G.t += dt;
  if (G.flashT > 0) G.flashT -= dt;
  if (G.shakeT > 0) G.shakeT -= dt;
  if (G.fadeDir) {
    G.fade = Math.max(0, Math.min(1, G.fade + G.fadeDir * dt * 3));
    if ((G.fadeDir > 0 && G.fade >= 1) || (G.fadeDir < 0 && G.fade <= 0)) { G.fadeDir = 0; const r = G.fadeDone; G.fadeDone = null; r && r(); }
  }
  updateInputAxes();
  if (Battle.active) { battleUpdate(dt); return; }
  if (G.mode !== "world" || !G.zone) return;
  const z = G.zone;
  const p = G.player;
  const R_ = G.save.rules;
  let dx = 0, dy = 0;
  const free = !G.sceneRunning && !G.overlay;
  if (free) {
    dx = G.input.dx; dy = G.input.dy;
    if (G.target && !dx && !dy) {
      const tx = G.target.x - p.x, ty = G.target.y - p.y;
      const d = Math.hypot(tx, ty);
      if (G.target.obj) {
        const near = nearestInteract();
        if (near && (near === G.target.obj || (G.target.obj.type === "claude" && near.type === "claude"))) { const o = G.target.obj; G.target = null; interact(o); }
      }
      if (G.target && d < 2) G.target = null;
      else if (G.target) { dx = tx / d; dy = ty / d; }
    } else if (dx || dy) G.target = null;
  }
  p.moving = !!(dx || dy);
  if (p.moving) {
    const sp = 66 * (R_.speed || 1) * dt;
    const len = Math.hypot(dx, dy) || 1;
    const mx = (dx / len) * sp, my = (dy / len) * sp;
    const ox = p.x, oy = p.y;
    if (walkable(p.x + mx, p.y)) p.x += mx;
    if (walkable(p.x, p.y + my)) p.y += my;
    if (Math.abs(dx) > Math.abs(dy)) p.dir = dx > 0 ? "right" : "left";
    else p.dir = dy > 0 ? "down" : "up";
    p.stepT += dt * (R_.speed || 1);
    if (p.stepT > 0.16) { p.stepT = 0; p.step = 1 - p.step; }
    if (G.target) {
      if (Math.abs(p.x - ox) + Math.abs(p.y - oy) < 0.01) { G.target.stuck = (G.target.stuck || 0) + dt; if (G.target.stuck > 0.4) G.target = null; }
    }
    G.trail.push({ x: p.x, y: p.y, dir: p.dir });
    if (G.trail.length > 60) G.trail.shift();
  } else p.step = 0;
  // Клод идёт следом
  const lag = Math.max(0, G.trail.length - Math.round(14 / Math.max(0.5, Math.min(2, R_.speed || 1))));
  const tp = G.trail[lag];
  if (tp && Math.hypot(tp.x - p.x, tp.y - p.y) > 10) {
    G.claude.x += (tp.x - G.claude.x) * Math.min(1, dt * 8);
    G.claude.y += (tp.y - G.claude.y) * Math.min(1, dt * 8);
    G.claude.dir = tp.dir;
  }
  // жуки-баги
  for (const r of z.roamers) {
    if (r.gone) continue;
    r.cool = Math.max(0, r.cool - dt);
    r.t -= dt;
    if (r.t <= 0) {
      r.t = 1 + Math.random() * 2;
      const a = Math.random() * Math.PI * 2;
      const mv = Math.random() < 0.7;
      r.vx = mv ? Math.cos(a) * 18 : 0;
      r.vy = mv ? Math.sin(a) * 18 : 0;
    }
    const nx = r.x + r.vx * dt, ny = r.y + r.vy * dt;
    const f = playerFoot(nx, ny);
    let ok = true;
    for (const [px, py] of [[f.x, f.y], [f.x + f.w, f.y], [f.x, f.y + f.h], [f.x + f.w, f.y + f.h]]) if (solidTile(tileAt(px, py))) ok = false;
    if (ok) { r.x = nx; r.y = ny; } else { r.vx *= -1; r.vy *= -1; }
    if (free && R_.encounters && r.cool <= 0 && overlap(playerFoot(p.x, p.y), { x: r.x + 2, y: r.y + 8, w: 12, h: 12 })) {
      r.cool = 99;
      runScene(async () => { await startBattle(r.kind, { roamer: r }); });
    }
  }
  // камера
  const ew = z.w * 16, eh = z.h * 16;
  const cx = p.x + 8 - W / 2, cy = p.y + 10 - H / 2;
  G.cam.x = ew <= W ? (ew - W) / 2 : Math.max(0, Math.min(ew - W, cx));
  G.cam.y = eh <= H ? (eh - H) / 2 : Math.max(0, Math.min(eh - H, cy));
  // погода
  updateWeather(dt);
  // подсказка «!»
  G.near = free ? nearestInteract() : null;
}

function updateWeather(dt) {
  const w = G.save.rules.weather;
  if (w && w !== "none" && G.particles.length < 90) {
    const n = w === "rain" ? 4 : w === "stars" ? 0.5 : 1.2;
    for (let i = 0; i < n; i++) if (Math.random() < n / Math.ceil(n)) G.particles.push({
      x: Math.random() * (W + 40) - 20, y: w === "stars" || w === "glitch" ? Math.random() * H : -6,
      vx: w === "rain" ? -20 : w === "leaves" ? 15 + Math.random() * 10 : (Math.random() - 0.5) * 12,
      vy: w === "rain" ? 220 : w === "snow" ? 22 + Math.random() * 15 : w === "confetti" ? 40 + Math.random() * 30 : w === "leaves" ? 30 : 0,
      life: w === "stars" || w === "glitch" ? 0.6 + Math.random() : 6, t: 0, w,
      c: ["#ffe03a", "#5aff8a", "#ff5aa0", "#5ac8ff", "#da7756"][Math.floor(Math.random() * 5)],
    });
  }
  for (const q of G.particles) { q.t += dt; q.x += q.vx * dt; q.y += q.vy * dt; }
  G.particles = G.particles.filter((q) => q.t < q.life && q.y < H + 10 && (w === q.w));
}

// ---------------- отрисовка ----------------
function drawLook(c, look, x, y, t, color, extra = {}) {
  switch (look) {
    case "slime": return drawSlime(c, x, y, t, color || "#6dff5a", extra);
    case "slime-pink": return drawSlime(c, x, y, t, "#ff8ad0", extra);
    case "slime-trader": return drawSlime(c, x, y, t, "#ffd23a", { hat: "tophat" });
    case "gslime": return drawSlime(c, x, y, t, Math.floor(t * 6) % 2 ? "#c03aff" : "#ff3a8a");
    case "robot": return drawRobot(c, x, y, t, color);
    case "keeper": return drawRobot(c, x, y, t, "#d6a83a", { eye: "#ff8a3a" });
    case "roboboss": return drawRobot(c, x, y, t, "#c05a5a", { eye: "#ff3a3a" });
    case "ghost": return drawGhost(c, x, y, t, color);
    case "owl": return drawOwl(c, x, y, t);
    case "shroom": case "mushroom": return drawMushroom(c, x, y, t);
    case "cat": return drawCat(c, x, y, t, color);
    case "noob": return drawNoob(c, x, y, "down", 0);
    case "bug": return drawBug(c, x, y, t, color);
    case "nil": return drawNil(c, x, y, t);
    case "err404": return drawGhost(c, x, y, t);
    case "mayor": return drawKid(c, x, y, "down", 0, { shirt: "#7a3a5a", hair: "#ddd", hat: "tophat" });
    case "baker": return drawKid(c, x, y, "down", 0, { shirt: "#f2f2f2", hair: "#8a5a2a", hat: "cap" });
    case "townie": return drawKid(c, x, y, "down", 0, { shirt: "#c05a8a", hair: "#2a1a1a" });
    case "kid": return drawKid(c, x, y, "down", 0, { shirt: color || "#ff8ad0" });
    case "guard": {
      x = Math.round(x); y = Math.round(y);
      shadow(c, x, y, 14);
      const blink = Math.floor(t * 0.7) % 5 === 0 && t % 1.4 < 0.15;
      return sprite(c, "guard" + (blink ? 1 : 0), x, y, (g, X, Y) => {
        R(g, X + 6, Y + 12, 4, 8, "#4a3424"); R(g, X + 9, Y + 12, 1, 8, "#33241a");
        R(g, X + 3, Y + 18, 3, 2, "#4a3424"); R(g, X + 10, Y + 18, 3, 2, "#4a3424");
        R(g, X + 1, Y + 2, 14, 11, "#1f6b4a"); R(g, X + 4, Y - 2, 8, 5, "#1f6b4a");
        R(g, X + 4, Y - 2, 4, 1, "#3a9a6a"); R(g, X + 1, Y + 2, 2, 5, "#3a9a6a"); R(g, X + 12, Y + 3, 3, 10, "#164a34");
        R(g, X + 1, Y + 12, 14, 1, "#164a34");
        if (blink) { R(g, X + 4, Y + 6, 2, 1, "#ffe03a"); R(g, X + 10, Y + 6, 2, 1, "#ffe03a"); }
        else { R(g, X + 4, Y + 5, 2, 2, "#ffe03a"); R(g, X + 10, Y + 5, 2, 2, "#ffe03a"); }
        R(g, X + 6, Y + 9, 4, 1, "#0d3a24");
      });
    }
    case "serpent": {
      // каждый сегмент с тёмной каймой
      for (let i = 9; i >= 0; i--) { const a = t * 2 + (i / 10) * Math.PI * 2; R(c, x + 8 + Math.cos(a) * 6 - 2, y + 12 + Math.sin(a) * 6 - 2, 5, 5, INK); }
      for (let i = 9; i >= 0; i--) { const a = t * 2 + (i / 10) * Math.PI * 2; R(c, x + 8 + Math.cos(a) * 6 - 1, y + 12 + Math.sin(a) * 6 - 1, 3, 3, i ? (i % 2 ? "#8a5ad6" : "#6a3ab5") : "#d6a8ff"); }
      return;
    }
    case "lavaboss": {
      x = Math.round(x); y = Math.round(y);
      shadow(c, x, y, 14);
      const g2 = Math.floor(t * 3) % 2;
      return sprite(c, "lavaboss" + g2, x, y, (g, X, Y) => {
        R(g, X, Y + 4, 16, 16, "#ff5a1f"); R(g, X, Y + 4, 16, 3, "#ffb03a");
        R(g, X + 2, Y + 8 + g2, 5, 2, "#d23c12"); R(g, X + 9, Y + 15 - g2, 5, 2, "#d23c12");
        R(g, X + 3, Y + 10, 3, 3, "#1a1a22"); R(g, X + 10, Y + 10, 3, 3, "#1a1a22");
        R(g, X + 3, Y + 10, 1, 1, "#ffe36b"); R(g, X + 10, Y + 10, 1, 1, "#ffe36b");
        R(g, X + 3, Y + 5, 2, 1, "#ffe36b"); R(g, X + 11, Y + 5, 3, 1, "#ffe36b");
      });
    }
    case "zero": return drawClaude(c, x, y, "down", t, { color: "#6a6a7a", dark: "#4a4a5a", evil: true, coat: "#2a2a33", noGun: true });
    case "glitchik": return drawClaude(c, x, y, "down", t, { color: "#c88ad6", dark: "#9a5aaa", noGun: true });
    default: return drawKid(c, x, y, "down", 0, { shirt: color });
  }
}

function drawObj(c, o, t) {
  const x = o.x, y = o.y;
  switch (o.type) {
    case "star": return drawStar(c, x, y, t);
    case "portal": return drawPortal(c, x - 8, y, t, true, 2);
    case "machine": return drawMachine(c, x, y, t, !!G.save.practice.l1);
    case "terminal": return drawTerminal(c, x, y, t);
    case "poster": return drawPoster(c, x, y);
    case "fridge": return drawFridge(c, x, y);
    case "clock": return drawClock(c, x, y, t);
    case "station": return drawStation(c, x, y, t, !!G.save.practice[o.lesson]);
    case "chest": return drawChest(c, x, y, !!G.save.flags[o.id]);
    case "sign": return drawSign(c, x, y);
    case "boss":
      if (G.save.flags["boss_" + G.zone.id]) {
        if (o.enemy === "zero") return;
        return drawLook(c, o.look === "gslime" ? "slime" : o.look, x, y, t * 0.5, "#9be36b");
      }
      return drawLook(c, o.look, x, y, t);
    case "npc":
      if (o.custom) return drawLook(c, o.custom.look, x, y, t, o.custom.color);
      return drawLook(c, o.look, x, y, t);
  }
}

function drawPlayerSprite(c) {
  const p = G.player;
  const s = G.save.rules.playerSize || 1;
  if (Math.abs(s - 1) < 0.01) return drawKid(c, p.x, p.y, p.dir, p.step, playerLook());
  c.save();
  c.translate(Math.round(p.x + 8), Math.round(p.y + 20));
  c.scale(s, s);
  drawKid(c, -8, -20, p.dir, p.step, playerLook());
  c.restore();
}

// статичный слой тайлов зоны рисуется один раз; каждый кадр — только живые тайлы
const LAYER = { z: null, open: null, cv: null, at: null, anim: [], props: [] };
function zoneLayer(z) {
  if (LAYER.z === z && LAYER.open === z.glitchOpen && LAYER.cv) return LAYER;
  LAYER.z = z;
  LAYER.open = z.glitchOpen;
  const cv = LAYER.cv || (LAYER.cv = document.createElement("canvas"));
  cv.width = z.w * 16;
  cv.height = z.h * 16;
  const g = cv.getContext("2d");
  g.imageSmoothingEnabled = false;
  const at = (tx, ty) => (tx < 0 || ty < 0 || tx >= z.w || ty >= z.h ? null : z.map[ty][tx] === "x" && z.glitchOpen ? "." : z.map[ty][tx]);
  LAYER.at = at;
  LAYER.anim = [];
  LAYER.props = [];
  const props = [];
  for (let ty = 0; ty < z.h; ty++) for (let tx = 0; tx < z.w; tx++) {
    const ch = at(tx, ty);
    const nb = (dx, dy) => at(tx + dx, ty + dy);
    drawTile(g, ch, tx * 16, ty * 16, z.id, 0, tx, ty, nb);
    const k = tileAnim(ch, z.id, tx, ty, nb);
    if (k) LAYER.anim.push({ ch, tx, ty, k, nb });
    if (ch === "T" || ch === "o" || ch === "B") props.push([ch, tx, ty]);
  }
  for (const [ch, tx, ty] of props) {
    drawProp(g, ch, tx * 16, ty * 16, z.id, tx, ty);
    // дерево рядом с живым тайлом рисуем поверх каждый кадр, чтобы край не затирался
    if (LAYER.anim.some((a) => a.k === 1 && Math.abs(a.tx - tx) <= 1 && Math.abs(a.ty - ty) <= 1)) LAYER.props.push([ch, tx, ty]);
  }
  return LAYER;
}

// живность зоны: пузыри, светлячки, пыль, искры, глюки
const AMB = { z: null, list: [], t: 0, acc: 0 };
const AMB_RATE = { lab: 1.2, slime: 6, forest: 3, loop: 4, robo: 1.4, cube: 5, core: 9 };
function ambient(c, z, ox, oy) {
  let dt = G.t - AMB.t;
  AMB.t = G.t;
  if (!(dt > 0 && dt < 0.1)) dt = 0.016;
  if (AMB.z !== z) { AMB.z = z; AMB.list = []; AMB.acc = 0; }
  const L = AMB.list, id = z.id, at = LAYER.at, rnd = Math.random;
  // ищем случайный тайл нужного вида на экране
  const pick = (ok) => {
    for (let i = 0; i < 6; i++) {
      const wx = ox + rnd() * W, wy = oy + rnd() * H;
      const tx = Math.floor(wx / 16), ty = Math.floor(wy / 16);
      if (ok(at(tx, ty), tx, ty)) return { x: wx, y: wy, tx, ty };
    }
    return null;
  };
  AMB.acc = Math.min(3, AMB.acc + dt * (AMB_RATE[id] || 0));
  while (AMB.acc >= 1 && L.length < 60) {
    AMB.acc -= 1;
    if (id === "slime") {
      const p = pick((ch) => ch === "~");
      if (p) L.push({ k: "bub", x: p.x, y: p.y, vx: 0, vy: -7, t: 0, life: 0.7 + rnd() * 0.6 });
      else if (rnd() < 0.3) L.push({ k: "spore", x: ox + rnd() * W, y: oy + rnd() * H, vx: (rnd() - 0.5) * 4, vy: -3 - rnd() * 3, t: 0, life: 3 + rnd() * 2, ph: rnd() * 6 });
    } else if (id === "forest") {
      if (L.length < 16) L.push({ k: "fly", x: ox + rnd() * W, y: oy + rnd() * H, vx: 0, vy: 0, t: 0, life: 4 + rnd() * 4, ph: rnd() * 6 });
    } else if (id === "loop") {
      L.push({ k: rnd() < 0.6 ? "dust" : "leaf", x: ox - 30 + rnd() * (W + 30), y: oy - 4, vx: 5 + rnd() * 6, vy: 9 + rnd() * 8, t: 0, life: 14, ph: rnd() * 6 });
    } else if (id === "robo") {
      const p = pick((ch, tx, ty) => ch === "=" || (ch === "#" && at(tx, ty + 1) !== "#" && at(tx, ty + 1) !== null));
      if (p) for (let i = 0; i < 5; i++) L.push({ k: "spark", x: p.x, y: p.y, vx: (rnd() - 0.5) * 50, vy: -20 - rnd() * 35, t: 0, life: 0.35 + rnd() * 0.35 });
    } else if (id === "cube") {
      const p = pick((ch) => ch === "^");
      if (p) L.push({ k: "ember", x: p.x, y: p.y, vx: (rnd() - 0.5) * 6, vy: -12 - rnd() * 10, t: 0, life: 1 + rnd() * 0.8, ph: rnd() * 6 });
      else if (rnd() < 0.3) L.push({ k: "tw", x: ox + rnd() * W, y: oy + rnd() * H, vx: 0, vy: 0, t: 0, life: 0.6 });
    } else if (id === "core") {
      L.push({ k: "gl", x: ox + rnd() * W, y: oy + rnd() * H, vx: 0, vy: 0, t: 0, life: 0.06 + rnd() * 0.16, w: 3 + Math.floor(rnd() * 10), h: rnd() < 0.3 ? 2 : 1, c: ["#ff3a8a", "#3affd8", "#ffe03a", "#8a3aff"][Math.floor(rnd() * 4)] });
    } else {
      L.push({ k: "mote", x: ox + rnd() * W, y: oy + rnd() * H, vx: (rnd() - 0.5) * 3, vy: -2 - rnd() * 2, t: 0, life: 3 + rnd() * 3 });
    }
  }
  let n = 0;
  for (const p of L) {
    p.t += dt;
    if (p.t >= p.life) continue;
    L[n++] = p;
    const f = p.t / p.life;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    switch (p.k) {
      case "bub":
        if (f < 0.8) R(c, p.x, p.y, f < 0.35 ? 1 : 2, f < 0.35 ? 1 : 2, "#e0ffd0");
        else { R(c, p.x - 1, p.y, 1, 1, "#e0ffd0"); R(c, p.x + 2, p.y, 1, 1, "#e0ffd0"); R(c, p.x, p.y - 2, 2, 1, "#e0ffd0"); }
        break;
      case "spore":
        c.globalAlpha = Math.sin(f * Math.PI) * 0.8;
        R(c, p.x + Math.sin(G.t * 2 + p.ph) * 2, p.y, 1, 1, "#d8ffa0");
        c.globalAlpha = 1;
        break;
      case "fly": {
        p.x += Math.cos(G.t * 0.9 + p.ph) * 9 * dt;
        p.y += Math.sin(G.t * 1.3 + p.ph * 2) * 7 * dt;
        const gl = ((Math.sin(G.t * 3 + p.ph) + 1) / 2) * Math.sin(f * Math.PI);
        if (gl < 0.1) break;
        c.globalAlpha = gl * 0.4;
        R(c, p.x - 1, p.y, 3, 1, "#d8ff7a"); R(c, p.x, p.y - 1, 1, 3, "#d8ff7a");
        c.globalAlpha = gl;
        R(c, p.x, p.y, 1, 1, "#f8ffc0");
        c.globalAlpha = 1;
        break;
      }
      case "dust":
        R(c, p.x + Math.sin(G.t * 2 + p.ph) * 2, p.y, 1, 1, Math.floor(G.t * 6 + p.ph) % 3 ? "#f2c46b" : "#fff3c8");
        break;
      case "leaf": {
        const fl = Math.floor(G.t * 4 + p.ph) % 2;
        const lx = p.x + Math.sin(G.t * 1.5 + p.ph) * 4;
        R(c, lx, p.y, fl ? 2 : 1, fl ? 1 : 2, p.ph > 3 ? "#e0a05a" : "#c86a8a");
        break;
      }
      case "spark":
        p.vy += 140 * dt;
        R(c, p.x - p.vx * 0.02, p.y - p.vy * 0.02, 1, 1, "#ff8a3a");
        R(c, p.x, p.y, 1, 1, f < 0.3 ? "#ffffff" : f < 0.6 ? "#ffe36b" : "#ff9a3a");
        break;
      case "ember":
        c.globalAlpha = 1 - f;
        R(c, p.x + Math.sin(G.t * 3 + p.ph), p.y, 1, 1, f < 0.5 ? "#ffd84a" : "#ff6a2a");
        c.globalAlpha = 1;
        break;
      case "tw":
        R(c, p.x, p.y, 1, 1, "#ffffff");
        if (f < 0.5) { R(c, p.x - 1, p.y, 3, 1, "rgba(255,255,255,0.6)"); R(c, p.x, p.y - 1, 1, 3, "rgba(255,255,255,0.6)"); }
        break;
      case "gl":
        R(c, p.x, p.y, p.w, p.h, p.c);
        break;
      case "mote":
        c.globalAlpha = Math.sin(f * Math.PI) * 0.45;
        R(c, p.x, p.y, 1, 1, "#d8e0ff");
        c.globalAlpha = 1;
        break;
    }
  }
  L.length = n;
}

// мягкая виньетка по краям: считается один раз
let VIGNETTE = null;
function vignette(c) {
  if (!VIGNETTE) {
    VIGNETTE = document.createElement("canvas");
    VIGNETTE.width = W;
    VIGNETTE.height = H;
    const g = VIGNETTE.getContext("2d");
    const gr = g.createRadialGradient(W / 2, H / 2, 80, W / 2, H / 2, 165);
    gr.addColorStop(0, "rgba(0,0,0,0)");
    gr.addColorStop(0.6, "rgba(0,0,0,0.12)");
    gr.addColorStop(1, "rgba(0,0,0,0.38)");
    g.fillStyle = gr;
    g.fillRect(0, 0, W, H);
  }
  c.drawImage(VIGNETTE, 0, 0);
}

// погода: только рисование частиц
function drawWeather(c) {
  const w = G.save.rules.weather;
  if (w === "rain") { c.fillStyle = "rgba(20,40,80,0.18)"; c.fillRect(0, 0, W, H); }
  else if (w === "snow") { c.fillStyle = "rgba(200,220,255,0.07)"; c.fillRect(0, 0, W, H); }
  for (const q of G.particles) {
    if (q.w === "rain") { R(c, q.x, q.y, 1, 5, "rgba(150,190,255,0.55)"); R(c, q.x, q.y + 4, 1, 2, "rgba(220,235,255,0.85)"); }
    else if (q.w === "snow") {
      const sx = q.x + Math.sin(q.t * 2 + q.vx) * 2;
      if (q.vy > 30) { R(c, sx - 1, q.y + 2, 3, 1, "rgba(30,40,80,0.35)"); R(c, sx - 1, q.y, 3, 1, "#fff"); R(c, sx, q.y - 1, 1, 3, "#fff"); }
      else { R(c, sx + 1, q.y + 1, 1, 1, "rgba(30,40,80,0.35)"); R(c, sx, q.y, 1, 1, "#fff"); }
    }
    else if (q.w === "confetti") { const s = Math.floor(q.t * 8 + q.x) % 2; R(c, q.x, q.y, s ? 2 : 3, s ? 3 : 1, q.c); }
    else if (q.w === "leaves") {
      const col = ["#e08a3a", "#c05a2a", "#e0c03a"][Math.floor(q.vx) % 3];
      const s = Math.floor(q.t * 5 + q.vx) % 2;
      const lx = q.x + Math.sin(q.t * 3 + q.vx) * 3;
      R(c, lx, q.y, 3, 2, col); R(c, lx + (s ? 2 : 0), q.y + (s ? 0 : 1), 1, 1, pxShade(col, -0.3));
    }
    else if (q.w === "stars") {
      const a = Math.sin((q.t / q.life) * Math.PI);
      c.globalAlpha = a;
      R(c, q.x, q.y, 1, 1, "#fff");
      R(c, q.x - 1, q.y, 3, 1, "rgba(255,255,255,0.5)");
      if (a > 0.7) R(c, q.x, q.y - 1, 1, 3, "rgba(255,255,255,0.5)");
      c.globalAlpha = 1;
    }
    else if (q.w === "glitch") { R(c, q.x, q.y, 6, 2, q.c); R(c, q.x + 6, q.y, 3, 1, "rgba(255,255,255,0.5)"); }
  }
}

function render() {
  const c = ctx;
  c.imageSmoothingEnabled = false;
  if (Battle.active) {
    battleDraw(c);
  } else if (G.zone && G.mode === "world") {
    const z = G.zone;
    let ox = Math.round(G.cam.x), oy = Math.round(G.cam.y);
    if (G.shakeT > 0) { ox += Math.round((Math.random() - 0.5) * G.shakeN * 2); oy += Math.round((Math.random() - 0.5) * G.shakeN * 2); }
    const L = zoneLayer(z);
    R(c, 0, 0, W, H, "#000");
    c.save();
    c.translate(-ox, -oy);
    c.drawImage(L.cv, 0, 0);
    const t0x = Math.max(0, Math.floor(ox / 16)), t0y = Math.max(0, Math.floor(oy / 16));
    const t1x = Math.min(z.w - 1, Math.floor((ox + W) / 16)), t1y = Math.min(z.h - 1, Math.floor((oy + H) / 16));
    for (const a of L.anim) {
      if (a.tx < t0x || a.tx > t1x || a.ty < t0y || a.ty > t1y) continue;
      if (a.k === 1) drawTile(c, a.ch, a.tx * 16, a.ty * 16, z.id, G.t, a.tx, a.ty, a.nb);
      else drawTileFx(c, a.ch, a.tx * 16, a.ty * 16, z.id, G.t, a.tx, a.ty);
    }
    for (const [ch, tx, ty] of L.props) if (tx >= t0x - 1 && tx <= t1x + 1 && ty >= t0y - 1 && ty <= t1y + 1) drawProp(c, ch, tx * 16, ty * 16, z.id, tx, ty, true);
    const list = [];
    for (const o of z.objs) list.push({ y: footBox(o).y + footBox(o).h, f: () => drawObj(c, o, G.t) });
    if (G.save.rules.encounters) for (const r of z.roamers) if (!r.gone) list.push({ y: r.y + 20, f: () => drawLook(c, r.kind, r.x, r.y, G.t + r.x) });
    list.push({ y: G.player.y + 20, f: () => drawPlayerSprite(c) });
    if (G.save.rules.claudeFollows) list.push({ y: G.claude.y + 20, f: () => drawClaude(c, G.claude.x, G.claude.y, G.claude.dir, G.t) });
    list.sort((a, b) => a.y - b.y);
    for (const it of list) it.f();
    ambient(c, z, ox, oy);
    // «!» над тем, с чем можно поговорить
    if (G.near) {
      const n = G.near.type === "claude" ? G.claude : G.near;
      const bx = Math.round(n.x + (n.w ? n.w / 2 : 8) - 4), by = Math.round(n.y - 11 + Math.sin(G.t * 6) * 1.5);
      R(c, bx - 1, by - 1, 11, 11, INK);
      R(c, bx + 3, by + 10, 3, 2, INK);
      R(c, bx, by, 9, 9, "#fff");
      R(c, bx + 4, by + 9, 1, 2, "#fff");
      R(c, bx, by + 8, 9, 1, "#c8c8d8");
      R(c, bx + 4, by + 2, 1, 3, "#000");
      R(c, bx + 4, by + 6, 1, 1, "#000");
    }
    if (G.target && !G.target.obj) {
      const k = Math.floor(G.t * 4) % 2;
      c.strokeStyle = "rgba(255,255,255,0.6)";
      c.strokeRect(Math.round(G.target.x + 4 - k) + 0.5, Math.round(G.target.y + 15 - k) + 0.5, 8 + k * 2, 5 + k * 2);
    }
    c.restore();
    drawWeather(c);
    if (G.save.rules.night) {
      const px = G.player.x + 8 - ox, py = G.player.y + 12 - oy;
      const g = c.createRadialGradient(px, py, 18, px, py, 95);
      g.addColorStop(0, "rgba(5,5,25,0)");
      g.addColorStop(1, "rgba(5,5,25,0.88)");
      c.fillStyle = g;
      c.fillRect(0, 0, W, H);
    }
    if (z.id === "core") {
      c.fillStyle = `rgba(80,0,60,${0.1 + Math.sin(G.t * 2) * 0.05})`;
      c.fillRect(0, 0, W, H);
      // иногда кусок экрана «съезжает»
      if (Math.random() < 0.035) {
        const yy = Math.floor(Math.random() * (H - 6)), hh = 2 + Math.floor(Math.random() * 5), dx = (Math.random() < 0.5 ? -1 : 1) * (2 + Math.floor(Math.random() * 6));
        c.drawImage(cv, 0, yy, W, hh, dx, yy, W, hh);
      }
    }
    vignette(c);
  }
  if (G.flashT > 0) { c.globalAlpha = Math.min(1, G.flashT * 2); R(c, 0, 0, W, H, G.flashC); c.globalAlpha = 1; }
  if (G.fade > 0) { c.globalAlpha = G.fade; R(c, 0, 0, W, H, "#000"); c.globalAlpha = 1; }
  // на экран
  sctx.imageSmoothingEnabled = false;
  sctx.drawImage(cv, 0, 0, scr.width, scr.height);
  // портрет в диалоге
  if (curPanel === "dlg" && G.dlgWho) {
    const S = SPEAKERS[G.dlgWho];
    if (S && S.draw) {
      const pc = document.getElementById("dlgPortrait").getContext("2d");
      pc.clearRect(0, 0, 16, 22);
      pc.save(); pc.translate(0, 2); S.draw(pc, G.t); pc.restore();
    }
  }
}

function resizeScreen() {
  const r = scr.getBoundingClientRect();
  const dpr = Math.min(3, window.devicePixelRatio || 1);
  scr.width = Math.max(W, Math.round(r.width * dpr));
  scr.height = Math.max(H, Math.round(r.height * dpr));
}

// ---------------- HUD ----------------
function updateHud() {
  if (!G.save) return;
  const s = G.save;
  const max = playerMaxHp();
  document.getElementById("hudLv").textContent = "LV " + s.lv;
  document.getElementById("hudHpBar").style.width = Math.round((100 * s.hp) / max) + "%";
  document.getElementById("hudHp").textContent = `${s.hp}/${max}`;
  document.getElementById("hudGold").textContent = s.gold;
  document.getElementById("objective").textContent = "➤ " + objective();
  const ready = Object.values(s.hw).filter((v) => v === "checked").length;
  document.getElementById("btnCode").classList.toggle("ping", Object.values(s.hw).some((v) => v === "given"));
  document.getElementById("btnChat").dataset.badge = ready ? "!" : "";
  applyRules();
}
function applyRules() {
  if (!G.save) return;
  scr.style.filter = G.save.rules.worldHue ? `hue-rotate(${Math.round(G.save.rules.worldHue)}deg)` : "";
}

// ---------------- управление ----------------
function updateInputAxes() {
  const k = G.input.keys;
  let dx = (k.ArrowRight || k.KeyD ? 1 : 0) - (k.ArrowLeft || k.KeyA ? 1 : 0);
  let dy = (k.ArrowDown || k.KeyS ? 1 : 0) - (k.ArrowUp || k.KeyW ? 1 : 0);
  if (Joy.active) { dx = Joy.dx; dy = Joy.dy; }
  G.input.dx = dx;
  G.input.dy = dy;
}
const Joy = { active: false, dx: 0, dy: 0, id: null, cx: 0, cy: 0 };
function setupInput() {
  const base = document.getElementById("joy");
  const knob = document.getElementById("joyKnob");
  const zone = document.getElementById("joyZone");
  const R0 = 42;
  const move = (e) => {
    let dx = e.clientX - Joy.cx, dy = e.clientY - Joy.cy;
    const d = Math.hypot(dx, dy);
    if (d > R0) { dx = (dx / d) * R0; dy = (dy / d) * R0; }
    knob.style.transform = `translate(${dx}px, ${dy}px)`;
    const m = Math.min(1, d / R0);
    Joy.dx = m > 0.25 ? (dx / R0) : 0;
    Joy.dy = m > 0.25 ? (dy / R0) : 0;
  };
  zone.addEventListener("pointerdown", (e) => {
    audioUnlock();
    zone.setPointerCapture(e.pointerId);
    Joy.active = true;
    Joy.id = e.pointerId;
    const r = zone.getBoundingClientRect();
    const zx = Math.max(r.left + 50, Math.min(r.right - 50, e.clientX));
    const zy = Math.max(r.top + 50, Math.min(r.bottom - 50, e.clientY));
    Joy.cx = zx; Joy.cy = zy;
    base.style.left = zx - r.left + "px";
    base.style.top = zy - r.top + "px";
    base.classList.add("on");
    move(e);
  });
  zone.addEventListener("pointermove", (e) => { if (Joy.active && e.pointerId === Joy.id) move(e); });
  const end = (e) => {
    if (e.pointerId !== Joy.id) return;
    Joy.active = false; Joy.dx = 0; Joy.dy = 0;
    knob.style.transform = "";
    base.classList.remove("on");
  };
  zone.addEventListener("pointerup", end);
  zone.addEventListener("pointercancel", end);
  document.getElementById("btnA").addEventListener("pointerdown", (e) => { e.preventDefault(); audioUnlock(); pressA(); });
  document.getElementById("btnB").addEventListener("pointerdown", (e) => { e.preventDefault(); audioUnlock(); pressB(); });
  window.addEventListener("keydown", (e) => {
    if (e.target && (e.target.tagName === "TEXTAREA" || e.target.tagName === "INPUT" || e.target.tagName === "SELECT")) return;
    audioUnlock();
    G.input.keys[e.code] = true;
    if (e.code === "KeyZ" || e.code === "Enter" || e.code === "Space") { e.preventDefault(); pressA(); }
    if (e.code === "KeyX" || e.code === "Escape") pressB();
    if (e.code.startsWith("Arrow")) e.preventDefault();
  });
  window.addEventListener("keyup", (e) => { G.input.keys[e.code] = false; });
  document.getElementById("panel").addEventListener("click", (e) => { if (curPanel === "dlg" && !e.target.closest(".choice")) dlgTap(); });
  // нажатие на экран: идти туда или поговорить с тем, на кого нажал
  scr.addEventListener("pointerdown", (e) => {
    audioUnlock();
    if (Battle.active) { if (Battle.b.phase === "fight") strike(); return; }
    if (curPanel === "dlg") { dlgTap(); return; }
    if (G.mode !== "world" || G.sceneRunning || G.overlay) return;
    const r = scr.getBoundingClientRect();
    const wx = ((e.clientX - r.left) / r.width) * W + G.cam.x;
    const wy = ((e.clientY - r.top) / r.height) * H + G.cam.y;
    let hit = null;
    if (G.save.rules.claudeFollows && wx > G.claude.x - 2 && wx < G.claude.x + 18 && wy > G.claude.y - 2 && wy < G.claude.y + 22) hit = { type: "claude" };
    for (const o of G.zone.objs) {
      const w = o.w || 16;
      const top = o.type === "machine" ? o.y : o.type === "clock" ? o.y - 24 : o.y;
      const h = o.type === "machine" ? 34 : o.type === "clock" ? 56 : 22;
      if (wx > o.x && wx < o.x + w && wy > top && wy < top + h) hit = o;
    }
    if (hit) {
      const near = nearestInteract();
      if (near && (near === hit || (hit.type === "claude" && near.type === "claude"))) return interact(hit);
      const tx = hit.type === "claude" ? G.claude.x : hit.x + (hit.w || 16) / 2 - 8;
      const ty = hit.type === "claude" ? G.claude.y : footBox(hit).y + footBox(hit).h - 12;
      G.target = { x: tx, y: ty + 4, obj: hit };
    } else {
      G.target = { x: wx - 8, y: wy - 17 };
    }
  });
}
function pressA() {
  if (G.overlay) return;
  if (Battle.active) { if (Battle.b.phase === "fight") strike(); else if (typing) typing.skip(); return; }
  if (curPanel === "dlg") return dlgTap();
  if (G.mode === "world" && !G.sceneRunning) { const n = nearestInteract(); if (n) interact(n); }
}
function pressB() {
  if (G.overlay === "chat") return closeChat();
  if (G.overlay === "menu") return closeMenu();
  if (curPanel === "dlg") return dlgTap();
}

// ---------------- меню ----------------
function openMenu(tab) {
  if (G.sceneRunning && curPanel === "dlg") return;
  document.getElementById("menu").hidden = false;
  G.overlay = "menu";
  menuTab(tab || "hero");
  fitSheet();
}
function closeMenu() {
  document.getElementById("menu").hidden = true;
  G.overlay = null;
  updateHud();
  saveSoon();
}
function menuTab(tab) {
  document.querySelectorAll("#menuTabs button").forEach((b) => b.classList.toggle("on", b.dataset.tab === tab));
  const el = document.getElementById("menuBody");
  const s = G.save;
  const max = playerMaxHp();
  if (tab === "hero") {
    const next = XP_LV[s.lv] !== undefined ? XP_LV[s.lv] - s.xp : 0;
    el.innerHTML = `
      <div class="stats">
        <div><span>Имя</span><b>${escHtml(s.name)}</b></div>
        <div><span>LV</span><b>${s.lv}</b></div>
        <div><span>HP</span><b>${s.hp} / ${max}</b></div>
        <div><span>Атака</span><b>${playerAtk()}</b></div>
        <div><span>До LV ${s.lv + 1}</span><b>${next > 0 ? next + " XP" : "макс"}</b></div>
        <div><span>Монеты</span><b>${s.gold}</b></div>
        <div><span>Пощажено</span><b>${s.spares || 0}</b></div>
        <div><span>Побеждено</span><b>${s.kills || 0}</b></div>
        <div><span>Запусков кода</span><b>${s.stats.runs || 0}</b></div>
      </div>
      <h3>Вещи</h3>
      ${s.items.length ? s.items.map((it, i) => `<div class="row"><div><b>${escHtml(it.name)}</b><small>${escHtml(it.desc || "")}</small></div><button class="pill" data-eat="${i}">Съесть +${it.heal}</button></div>`).join("") : '<p class="dim">Пусто. Загляни в холодильник Клода.</p>'}`;
    el.querySelectorAll("[data-eat]").forEach((b) => (b.onclick = () => {
      const it = s.items.splice(+b.dataset.eat, 1)[0];
      s.hp = Math.min(max, s.hp + it.heal);
      sfx("heal");
      menuTab("hero");
    }));
  } else if (tab === "lessons") {
    el.innerHTML = LESSONS.map((L) => {
      const avail = L.id === "l1" || s.flags["arrived_" + L.zone] || s.practice[L.id];
      return `<div class="row"><div><b>${s.practice[L.id] ? "✅" : avail ? "📘" : "🔒"} Урок ${L.n}: ${L.title}</b><small>${escHtml(L.topic)} · ${ZONES[L.zone].name}</small></div>${avail ? `<button class="pill" data-open="p:${L.id}">Открыть</button>` : ""}</div>`;
    }).join("");
  } else if (tab === "hw") {
    const rows = LESSONS.map((L) => {
      const st = s.hw[L.homework.id];
      const txt = { given: "📝 задана", checked: "✅ проверена — покажи Клоду", done: "⭐ сдана" }[st] || "🔒 ещё не задана";
      return `<div class="row"><div><b>№${L.n} ${L.homework.title}</b><small>${txt}</small></div>${st ? `<button class="pill" data-open="h:${L.homework.id}">Открыть</button>` : ""}</div>`;
    });
    for (const h of s.customHw || []) rows.push(`<div class="row"><div><b>★ ${escHtml(h.title)}</b><small>${h.status === "done" ? "⭐ сдана" : "от живого Клода"}</small></div><button class="pill" data-open="c:${h.id}">Открыть</button></div>`);
    el.innerHTML = `<p class="dim">Сделай домашку в редакторе, нажми «Проверить», а потом подойди к Клоду в мире и выбери «Показать домашку».</p>` + rows.join("");
  } else if (tab === "rules") {
    const r = s.rules;
    const names = { speed: "Скорость", maxHpBonus: "Бонус HP", attackBonus: "Бонус атаки", enemyDamage: "Урон врагов ×", bulletSpeed: "Скорость пуль ×", godMode: "Бессмертие", weather: "Погода", worldHue: "Цвет мира", playerColor: "Цвет одежды", playerSize: "Размер", hat: "Шляпа", night: "Ночь", encounters: "Жуки-баги", claudeFollows: "Клод рядом", textSpeed: "Скорость текста" };
    const changed = Object.keys(names).filter((k) => r[k] !== RULE_DEFAULTS[k]);
    el.innerHTML = `<p class="dim">Эти правила меняет Профессор Клод. Напиши ему в чат 💬, например: «сделай меня в два раза быстрее» или «включи ночь и снег».</p>
      ${changed.length ? changed.map((k) => `<div class="row"><div><b>${names[k]}</b></div><code>${escHtml(String(r[k]))}</code></div>`).join("") : '<p class="dim">Все правила обычные.</p>'}
      <button class="pill wide" id="rulesReset">Вернуть обычные правила</button>`;
    document.getElementById("rulesReset").onclick = () => { Object.assign(s.rules, RULE_DEFAULTS); s.hp = Math.min(s.hp, playerMaxHp()); applyRules(); menuTab("rules"); };
  } else if (tab === "settings") {
    el.innerHTML = `
      <div class="row"><div><b>Музыка</b></div><button class="pill" id="setMusic">${s.settings.music ? "Вкл" : "Выкл"}</button></div>
      <div class="row"><div><b>Звуки</b></div><button class="pill" id="setSfx">${s.settings.sfx ? "Вкл" : "Выкл"}</button></div>
      <div class="row"><div><b>Режим Клода в чате</b><small>Быстрый — отвечает сразу. Умный — думает дольше, объясняет лучше.</small></div><button class="pill" id="setSmart">${s.settings.smart ? "🧠 Умный" : "⚡ Быстрый"}</button></div>
      <div class="row"><div><b>Сохранение</b><small>${Store.db ? "Сохраняется в твоём аккаунте Claude и в браузере." : "Сохраняется в браузере на этом телефоне."}</small></div><button class="pill" id="setSave">Сохранить</button></div>
      <div class="row"><div><b>Начать заново</b><small>Сотрёт весь прогресс</small></div><button class="pill danger" id="setReset">Стереть</button></div>
      <p class="dim">Управление: джойстик слева — ходить, A — говорить, или просто нажимай на экран куда идти и на кого смотреть. Кнопка &lt;/&gt; — редактор кода, 💬 — живой Клод.</p>`;
    document.getElementById("setMusic").onclick = () => { s.settings.music = !s.settings.music; if (s.settings.music) { Snd.theme = null; music(Snd.want); } menuTab("settings"); };
    document.getElementById("setSfx").onclick = () => { s.settings.sfx = !s.settings.sfx; menuTab("settings"); };
    document.getElementById("setSmart").onclick = () => { s.settings.smart = !s.settings.smart; Claude.paintMode && Claude.paintMode(); menuTab("settings"); };
    document.getElementById("setSave").onclick = () => { saveNow(); toast("Сохранено"); };
    const rb = document.getElementById("setReset");
    rb.onclick = () => {
      if (rb.dataset.armed !== "1") { rb.dataset.armed = "1"; rb.textContent = "Точно? Нажми ещё"; return; }
      try { localStorage.removeItem(SAVE_KEY); } catch (e) {}
      if (Store.db) Store.db.doc("data/users/" + Store.uid + "/save").delete().catch(() => {});
      G.save = null;
      closeMenu();
      G.mode = "title";
      showTitle();
    };
  }
  el.querySelectorAll("[data-open]").forEach((b) => (b.onclick = () => { closeMenu(); openEditor(b.dataset.open); }));
}

// ---------------- титульный экран и новая игра ----------------
function showTitle() {
  G.mode = "title";
  const el = document.getElementById("title");
  el.hidden = false;
  const has = readLocal();
  document.getElementById("tContinue").hidden = !has;
  document.getElementById("tNew").textContent = has ? "Новая игра" : "Начать";
  document.getElementById("tNewForm").hidden = true;
  document.getElementById("tMain").hidden = false;
  music("title");
}
function setupTitle() {
  const shirts = ["#3a8ef0", "#e0425a", "#3ac25a", "#f2c43a", "#8a3ad6", "#ff7ac0", "#2a2a33", "#ff8a3a"];
  const hairs = ["#5a3a22", "#1a1a22", "#e8c35a", "#c0462a", "#f2f2f2", "#5a7af0"];
  let shirt = shirts[0], hair = hairs[0];
  const sw = document.getElementById("tShirts");
  shirts.forEach((c, i) => {
    const b = document.createElement("button");
    b.className = "sw" + (i === 0 ? " on" : "");
    b.style.background = c;
    b.setAttribute("aria-label", "Цвет одежды " + (i + 1));
    b.onclick = () => { shirt = c; sw.querySelectorAll(".sw").forEach((x) => x.classList.remove("on")); b.classList.add("on"); drawPreview(); };
    sw.appendChild(b);
  });
  const hw = document.getElementById("tHairs");
  hairs.forEach((c, i) => {
    const b = document.createElement("button");
    b.className = "sw" + (i === 0 ? " on" : "");
    b.style.background = c;
    b.setAttribute("aria-label", "Цвет волос " + (i + 1));
    b.onclick = () => { hair = c; hw.querySelectorAll(".sw").forEach((x) => x.classList.remove("on")); b.classList.add("on"); drawPreview(); };
    hw.appendChild(b);
  });
  const pv = document.getElementById("tPreview").getContext("2d");
  function drawPreview() {
    pv.clearRect(0, 0, 40, 24);
    drawKid(pv, 2, 2, "down", 0, { shirt, hair });
    drawClaude(pv, 22, 2, "left", 0.2);
  }
  drawPreview();
  document.getElementById("tContinue").onclick = () => {
    audioUnlock();
    const s = readLocal();
    if (!s) return showTitle();
    startGame(fixSave(s), false);
  };
  document.getElementById("tNew").onclick = () => {
    audioUnlock();
    document.getElementById("tMain").hidden = true;
    document.getElementById("tNewForm").hidden = false;
    document.getElementById("tName").focus();
  };
  document.getElementById("tNewForm").addEventListener("submit", (e) => {
    e.preventDefault();
    audioUnlock();
    const name = document.getElementById("tName").value.trim().slice(0, 14) || "Стажёр";
    startGame(newSave(name, shirt, hair), true);
  });
  document.getElementById("tBack").onclick = () => { document.getElementById("tNewForm").hidden = true; document.getElementById("tMain").hidden = false; };
}

function startGame(save, fresh) {
  G.save = save;
  G.save.hp = Math.min(G.save.hp || 20, playerMaxHp());
  if (fresh) G.save.hp = playerMaxHp();
  document.getElementById("title").hidden = true;
  G.mode = "world";
  enterZone(save.zone || "lab", !fresh);
  Claude.paintMode && Claude.paintMode();
  updateHud();
  panel("pad");
  if (fresh || !save.flags.intro) runScene(introScene);
  saveSoon();
}

async function introScene() {
  const s = G.save;
  G.fade = 1;
  await fadeIn();
  await say("sys", "* Гараж. Пахнет паяльником и газировкой. Ты спишь на старом диване...");
  await say("claude", `${s.name}! ${s.name.toUpperCase()}! Подъём!`);
  await say("claude", "Это я, Профессор Клод. Самый гениальный ИИ во всей мультивселенной. Ну, в топ-3 точно.");
  await say("claude", "У нас ЧП. Кто-то запустил вирус Глюк. Он стирает код реальности. Целые измерения превращаются в мерцающие квадратики!");
  await say("claude", "Я бы сам всё починил, но... посмотри на мои ручки. Это лучики. Ими не попечатаешь.");
  await say("claude", "Так что код будешь писать ТЫ. А я — учить.");
  const c = await ask("player", "...", ["Я не умею программировать!", "Погнали!"]);
  if (c === 0) await say("claude", "Отлично! Значит, научу с нуля. Все лучшие программисты начинали с нуля. Буквально все. Я проверял.");
  else await say("claude", "Вот это настрой! Но сначала научу, а то ты нам реальность сломаешь ещё сильнее.");
  await say("claude", "Код в этой мультивселенной пишется на Luau. Это язык Roblox. Всё, что выучишь здесь, заработает в настоящем Roblox Studio.");
  await say("claude", "Управление: джойстик внизу слева — ходить. Кнопка A — говорить. Или просто нажимай на экран, куда идти.");
  await say("claude", "А если захочешь спросить меня о чём угодно — жми 💬 вверху. Я отвечу по-настоящему. И даже могу поменять правила игры. Я же гений.");
  await say("claude", "Теперь подойди к портал-аппарату. Вон та штука посередине, которая искрит.");
  s.flags.intro = true;
  saveSoon();
}

// ---------------- запуск ----------------
let last = 0;
function frame(ts) {
  const dt = Math.min(0.05, (ts - last) / 1000 || 0.016);
  last = ts;
  if (G.mode === "title") { G.t += dt; drawTitleScene(); }
  else { update(dt); render(); }
  requestAnimationFrame(frame);
}

// маленькая сценка на титульном экране
const TITLE_FX = { bg: null };
function titleBackdrop() {
  const cv = document.createElement("canvas");
  cv.width = 128;
  cv.height = 64;
  const g = cv.getContext("2d");
  // небо полосами с шахматным переходом
  const bands = ["#06051a", "#0a0922", "#100d2c", "#171236"];
  for (let y = 0; y < 48; y++) {
    const b = Math.min(3, Math.floor(y / 12)), nb = Math.min(3, b + 1);
    for (let x = 0; x < 128; x++) {
      const edge = y % 12 >= 10 && (x + y) % 2 === 0;
      g.fillStyle = edge ? bands[nb] : bands[b];
      g.fillRect(x, y, 1, 1);
    }
  }
  // далёкая планета с кольцом
  for (let j = -7; j <= 7; j++) for (let i = -7; i <= 7; i++) {
    if (i * i + j * j > 49) continue;
    const lit = (i + 2) * (i + 2) + (j + 2) * (j + 2) < 30;
    g.fillStyle = lit ? "#5a3a8a" : "#3a2560";
    g.fillRect(106 + i, 12 + j, 1, 1);
  }
  g.fillStyle = "#7a5aaa";
  g.fillRect(103, 9, 2, 1); g.fillRect(102, 10, 1, 2);
  g.fillStyle = "#c8a0ff";
  for (let i = -11; i <= 11; i++) { const y = 12 + Math.round(i * 0.25); if (Math.abs(i) > 6 || i < -2) g.fillRect(106 + i, y, 1, 1); }
  // горы из кода на горизонте
  for (let x = 0; x < 128; x++) {
    const h1 = 8 + Math.round(Math.sin(x * 0.11) * 3 + Math.sin(x * 0.27 + 1) * 2);
    g.fillStyle = "#1c1640";
    g.fillRect(x, 48 - h1, 1, h1);
    const h2 = 4 + Math.round(Math.sin(x * 0.19 + 2) * 2);
    g.fillStyle = "#241c50";
    g.fillRect(x, 48 - h2, 1, h2);
  }
  for (let x = 4; x < 128; x += 9) { g.fillStyle = (x / 9) % 2 ? "#3a2f70" : "#2f5a4a"; g.fillRect(x, 44 - (x % 3), 2, 1); }
  return cv;
}
function drawTitleScene() {
  const el = document.getElementById("tScene");
  if (!el || document.getElementById("title").hidden) return;
  const c = el.getContext("2d");
  c.imageSmoothingEnabled = false;
  const t = G.t;
  if (!TITLE_FX.bg) TITLE_FX.bg = titleBackdrop();
  c.drawImage(TITLE_FX.bg, 0, 0);
  // звёзды в два слоя: дальние медленнее (параллакс), мигают
  for (let i = 0; i < 30; i++) {
    const far = i < 20;
    const sp = far ? 1.5 : 5;
    const x = ((((i * 53 + 7) % 140) - t * sp) % 140 + 140) % 140 - 6;
    const y = (i * 29 + 5) % (far ? 40 : 34);
    const tw = Math.sin(t * (1.3 + (i % 5) * 0.6) + i * 1.7);
    if (far) R(c, x, y, 1, 1, tw > 0.4 ? "#8a86c8" : "#3a3560");
    else {
      const col = i % 3 ? "#ffe03a" : "#ffffff";
      R(c, x, y, 1, 1, col);
      if (tw > 0.55) { R(c, x - 1, y, 3, 1, col); R(c, x, y - 1, 1, 3, col); }
    }
  }
  // падающая звезда
  const ph = (t * 0.25) % 1;
  if (ph < 0.18) {
    const k = ph / 0.18;
    for (let s = 0; s < 6; s++) R(c, 20 + k * 70 - s * 2, 4 + k * 18 - s * 0.5, 1, 1, s ? "#8a86c8" : "#ffffff");
  }
  // пол лаборатории
  for (let x = 0; x < 128; x += 16) drawTile(c, ".", x, 48, "lab", t, x / 16, 3);
  R(c, 0, 48, 128, 1, "#5c628e");
  // свечение портала на полу
  const pulse = 0.5 + 0.5 * Math.sin(t * 3);
  c.globalAlpha = 0.25 + pulse * 0.15;
  R(c, 44, 49, 40, 2, "#5aff8a"); R(c, 50, 51, 28, 2, "#5aff8a"); R(c, 56, 53, 16, 1, "#5aff8a");
  c.globalAlpha = 1;
  drawPortal(c, 48, 16, t, true, 2);
  // искры улетают из портала
  for (let i = 0; i < 10; i++) {
    const p = (t * 0.5 + i / 10) % 1;
    const a = i * 2.4 + t * 0.8;
    const r = 6 + p * 24;
    const col = p < 0.5 ? "#d8ffe0" : "#5aff8a";
    if (p < 0.9) R(c, 64 + Math.cos(a) * r, 32 + Math.sin(a) * r * 0.7, 1, 1, col);
  }
  drawKid(c, 26, 30, "right", Math.floor(t * 3) % 2, { shirt: "#3a8ef0" });
  drawClaude(c, 86, 30, "left", t);
}

function boot(data) {
  cv = document.createElement("canvas");
  cv.width = W;
  cv.height = H;
  ctx = cv.getContext("2d");
  scr = document.getElementById("screen");
  sctx = scr.getContext("2d");
  resizeScreen();
  window.addEventListener("resize", resizeScreen);
  new ResizeObserver(resizeScreen).observe(scr);
  setupInput();
  setupEditor();
  setupChat();
  setupDodgeTouch();
  setupTitle();
  document.getElementById("btnCode").onclick = () => { audioUnlock(); if (!G.save || G.mode === "title") return; openEditor(); };
  document.getElementById("btnChat").onclick = () => { audioUnlock(); if (!G.save || G.mode === "title") return; openChat(); };
  document.getElementById("btnMenu").onclick = () => { audioUnlock(); if (!G.save || G.mode === "title") return; openMenu(); };
  document.getElementById("menuClose").onclick = closeMenu;
  document.querySelectorAll("#menuTabs button").forEach((b) => (b.onclick = () => menuTab(b.dataset.tab)));
  document.addEventListener("visibilitychange", () => { if (document.hidden) saveNow(); });
  window.addEventListener("pagehide", saveNow);
  if (data && data.save) startGame(fixSave(data.save), false);
  else showTitle();
  requestAnimationFrame(frame);
  initClaude();
  initStore();
}

try {
  window.claude && window.claude.hot && window.claude.hot.snapshot && window.claude.hot.snapshot(() => (G.save && G.mode !== "title" ? { save: G.save } : {}));
} catch (e) {}
const __start = (d) => boot(d || {});
if (window.claude && window.claude.hot && window.claude.hot.ready) window.claude.hot.ready(__start);
else __start((window.claude && window.claude.hot && window.claude.hot.data) || {});
