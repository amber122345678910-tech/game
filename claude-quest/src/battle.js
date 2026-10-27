// Бои в стиле Undertale: БОЙ / КОД / ВЕЩИ / ПОЩАДА + уворот сердечком. Клод сражается вместе с тобой.
const ENEMIES = {
  bug: {
    name: "Баг", look: "bug", color: "#e0425a", hp: 14, atk: 3, xp: 6, gold: 4, patterns: ["rain", "aim"],
    intro: "* Баг выполз из старого кода!",
    flavor: ["* Баг делает вид, что он фича.", "* Пахнет непойманной ошибкой.", "* Баг шевелит усиками в ритме бага."],
    taunts: ["Я не баг, я фича!", "Ж-ж-ж!", "Поймай меня!", "Работает же? Не трогай!"],
    acts: [{ t: "Сказать «ты фича»", text: "* Ты называешь Бага фичей. Баг польщён.", mercy: 60 }],
    spare: "* Баг уползает обратно в старый код. Иногда лучше не трогать то, что работает.",
  },
  nil: {
    name: "Нулик", look: "nil", hp: 16, atk: 3, xp: 7, gold: 5, patterns: ["ring", "side"],
    intro: "* Из пустоты появляется Нулик.",
    flavor: ["* Нулик смотрит в никуда. Потому что он и есть никуда.", "* Нулик — значение по умолчанию. Ему грустно."],
    taunts: ["Я nil. Я ничто.", "attempt to index nil!", "Пусто... пусто...", "Меня никто не присвоил"],
    acts: [{ t: "Дать значение", text: "* Ты пишешь: local nulik = \"друг\". Нулик впервые что-то значит!", mercy: 100 }],
    spare: "* Нулик больше не nil. Теперь он \"друг\".",
  },
  err404: {
    name: "Ошибка 404", look: "ghost", color: "#e6e6f2", hp: 18, atk: 4, xp: 8, gold: 6, patterns: ["code", "bars"],
    intro: "* Ошибка 404 не найдена. Ой, нет, найдена!",
    flavor: ["* Ошибка 404 ищет свою страницу.", "* Привидение мигает, как плохой Wi-Fi."],
    taunts: ["Не найдено!", "Такой страницы нет!", "А может, и тебя нет?", "Проверь адрес!"],
    acts: [{ t: "Помочь найти", text: "* Ты помогаешь Ошибке найти её страницу. Это была главная!", mercy: 70 }],
    spare: "* Ошибка 404 нашла свою страницу и исчезла со статусом 200 OK.",
  },
  gslime: {
    name: "Глюк-Слизень", look: "slime", color: "#c03aff", hp: 60, atk: 4, xp: 30, gold: 20, boss: true, glitch: true, scale: 4,
    patterns: ["rain", "code", "bounce"],
    intro: "* Глюк-Слизень перекрывает путь! Он мерцает всеми цветами ошибки.",
    flavor: ["* Глюк-Слизень пытается вспомнить своё имя.", "* С него капает стёртый код.", "* Слизень булькает: local name = nil"],
    taunts: ["У меня нет имени!", "local name = nil!", "БУЛЬК!", "Вы все станете nil!"],
    acts: [{ t: "Погладить", text: "* Ты гладишь Глюк-Слизня. Липко. Но ему приятно.", mercy: 30 }, { t: "Предложить имя", text: "* Ты говоришь: «Тебе подойдёт имя». Слизень замирает.", mercy: 35 }],
    spare: "* Глюк-Слизень больше не хочет драться.",
    music: "boss",
  },
  guard: {
    name: "Страж Ветвления", look: "tree", hp: 85, atk: 5, xp: 45, gold: 30, boss: true, scale: 4,
    patterns: ["bars", "aim", "wave"],
    intro: "* Страж Ветвления встаёт на развилке. ЕСЛИ ты пройдёшь — ТО...",
    flavor: ["* Страж не может решить, if он или else.", "* У Стража две головы. Они спорят."],
    taunts: ["ЕСЛИ ты слаб, ТО...", "ИНАЧЕ!", "then! then! then!", "elseif?!"],
    acts: [{ t: "Поставить then", text: "* Ты дописываешь Стражу пропущенное then. Ему становится легче.", mercy: 30 }, { t: "Закрыть end", text: "* Ты закрываешь его условие словом end. Наконец-то!", mercy: 30 }],
    spare: "* Условие Стража выполнено. Он пропускает тебя.",
    music: "boss",
  },
  serpent: {
    name: "Змей Бесконечности", look: "serpent", hp: 110, atk: 6, xp: 60, gold: 40, boss: true, scale: 4,
    patterns: ["loop", "ring", "rain"],
    intro: "* Змей Бесконечности свернулся в кольцо. while true do...",
    flavor: ["* Змей кусает свой хвост. Снова.", "* Ты слышишь тиканье: вторник, вторник, вторник..."],
    taunts: ["while true dooo...", "Без конца!", "Ещё круг!", "Я не умею ждать!"],
    acts: [{ t: "Предложить wait()", text: "* Ты показываешь Змею wait(1). Он замирает на секунду. Ему... понравилось?", mercy: 40 }, { t: "Посчитать круги", text: "* Ты считаешь: 1, 2, 3... Змей впервые узнаёт, сколько кругов сделал.", mercy: 20 }],
    spare: "* Цикл Змея наконец получил паузу.",
    music: "boss",
  },
  roboboss: {
    name: "Робо-Начальник", look: "boss-robot", hp: 140, atk: 7, xp: 80, gold: 50, boss: true, scale: 4,
    patterns: ["side", "glitch", "code"],
    intro: "* Робо-Начальник загружает функцию уничтожить_стажёра()...",
    flavor: ["* Робо-Начальник пересчитывает своих роботов. Ошибается.", "* Из Робо-Начальника торчит return без значения."],
    taunts: ["return ПОБЕДА!", "ВЫЗОВ ФУНКЦИИ!", "ТЫ — nil!", "ПАРАМЕТР ОТКЛОНЁН!"],
    acts: [{ t: "Предложить функцию отдыхать()", text: "* Ты пишешь ему: local function отдыхать() wait(5) end. Начальник задумался.", mercy: 35 }, { t: "Похвалить роботов", text: "* Ты хвалишь его роботов. Глаза Начальника мигают теплее.", mercy: 25 }],
    spare: "* Робо-Начальник вызывает новую функцию: дружить().",
    music: "boss",
  },
  lava: {
    name: "Лава-Блок", look: "lava", hp: 170, atk: 8, xp: 100, gold: 60, boss: true, scale: 4,
    patterns: ["lava", "rain", "bounce"],
    intro: "* Лава-Блок раскаляется! Это настоящий kill brick!",
    flavor: ["* Лава-Блок пышет жаром. Anchored = true.", "* Рядом с ним Health тает на глазах."],
    taunts: ["Health = 0!", "КОСНИСЬ МЕНЯ!", "Я горячий!", "Touched:Connect(ТЕБЯ)!"],
    acts: [{ t: "Охладить", text: "* Ты пишешь: lava.Color = Color3.fromRGB(0, 150, 255). Лава-Блок синеет от удивления.", mercy: 35 }, { t: "Предложить стать heal brick", text: "* «А можно лечить, а не убивать?» Лава-Блок впервые об этом думает.", mercy: 30 }],
    spare: "* Лава-Блок остывает и становится просто тёплым.",
    music: "boss",
  },
  zero: {
    name: "Клод-Ноль", look: "claude", color: "#6a6a7a", hp: 260, atk: 9, xp: 200, gold: 100, boss: true, glitch: true, scale: 4, final: true,
    patterns: ["glitch", "loop", "code", "aim", "lava"],
    intro: "* Клод-Ноль. Первая программа Профессора. Цикл без конца.",
    flavor: ["* Клод-Ноль повторяет: while true do while true do while true do", "* В его глазах — бесконечный цикл.", "* Профессор Клод не может на это смотреть."],
    taunts: ["НЕТ ПАУЗЫ!", "ВЕЧНЫЙ ЦИКЛ!", "Я ЕМ КОД!", "СОЗДАТЕЛЬ ЗАБЫЛ wait()!", "ОСТАНОВИ... МЕНЯ..."],
    acts: [{ t: "Вставить wait()", text: "* Ты пытаешься вставить wait() в его цикл. Он дёргается, но слушает.", mercy: 20 }, { t: "Позвать Профессора", text: "* Профессор Клод говорит: «Прости, что забыл тебя». Клод-Ноль замирает.", mercy: 25 }],
    spare: "* Клод-Ноль останавливает свой цикл.",
    music: "boss",
  },
};

const Battle = {
  active: false,
  b: null,
};

function playerMaxHp() {
  return 16 + G.save.lv * 4 + (G.save.rules.maxHpBonus || 0);
}
function playerAtk() {
  return 3 + G.save.lv * 2 + (G.save.atkBonus || 0) + (G.save.rules.attackBonus || 0);
}

function startBattle(id, extra) {
  return new Promise((resolve) => {
    const def = typeof id === "string" ? ENEMIES[id] : id;
    if (!def) return resolve("flee");
    const b = {
      def, id: typeof id === "string" ? id : "custom",
      hp: def.hp, maxHp: def.hp, mercy: 0, turn: 0,
      phase: "intro", t: 0, hurt: 0, msg: "", resolve,
      box: { x: 16, y: 104, w: 224, h: 62, tw: 224, th: 62 },
      heart: { x: 128, y: 136 }, bullets: [], inv: 0, shield: 0,
      dmgNums: [], bubble: null, claudeLine: null, fight: null,
      roamer: extra && extra.roamer,
    };
    Battle.b = b;
    Battle.active = true;
    G.mode = "battle";
    music(def.music || (def.boss ? "boss" : "battle"));
    sfx("encounter");
    panel("bat");
    battleMenuIntro();
  });
}

// текст боя. mode: "tap" — ждём нажатия (▼), число — подержать столько мс, иначе — сразу дальше
function bText(t, mode) {
  const b = Battle.b;
  const el = document.getElementById("batText");
  Battle.wait = null;
  return new Promise((res) => {
    typeInto(el, t, "sys").then(() => {
      // бой сбросили или текст уже сменился — эту ветку не продолжаем / не держим
      if (!b || Battle.b !== b) return;
      if (el.textContent !== t) return res();
      if (mode === "tap") {
        const m = document.createElement("span");
        m.className = "batNext";
        m.textContent = "▼";
        m.style.cssText = "display:inline-block;margin-left:8px;color:var(--gold);animation:bob .8s steps(2) infinite";
        el.appendChild(m);
        // и большая кнопка «Дальше» на месте кнопок боя
        const box = document.getElementById("batBtns");
        box.innerHTML = "";
        box.className = "";
        const nb = document.createElement("button");
        nb.className = "bbtn wide next";
        nb.textContent = "Дальше ▼";
        nb.onclick = () => batTap();
        box.appendChild(nb);
        Battle.wait = { res, at: performance.now(), m, nb };
      } else if (mode > 0) setTimeout(() => { if (Battle.b === b) res(); }, mode);
      else res();
    });
  });
}
// нажатие во время боя: сначала дописать текст, потом — дальше (если ждём ▼)
function batTap() {
  if (typing && typing.el.id === "batText") { typing.skip(); return; }
  const w = Battle.wait;
  if (!w || performance.now() - w.at < 250) return;
  Battle.wait = null;
  w.m.remove();
  w.nb.remove();
  sfx("select");
  w.res();
}
function bButtons(list) {
  const el = document.getElementById("batBtns");
  el.innerHTML = "";
  el.className = list.length > 4 || list.some((o) => o.cls === "quiz") ? "list" : "";
  return new Promise((res) => {
    list.forEach((o, i) => {
      const btn = document.createElement("button");
      btn.className = "bbtn" + (o.cls ? " " + o.cls : "");
      btn.innerHTML = o.html || "";
      if (!o.html) btn.textContent = o.t;
      btn.disabled = !!o.disabled;
      btn.onclick = () => {
        sfx("select");
        el.innerHTML = "";
        res(i);
      };
      el.appendChild(btn);
    });
  });
}

// первая строка боя остаётся над кнопками, пока не выберешь действие
function battleMenuIntro() {
  battleMenu(Battle.b.def.intro);
}

function nameWithMercy() {
  const b = Battle.b;
  return b.mercy >= 100 ? `<span style="color:#ffe03a">${b.def.name}</span>` : b.def.name;
}

async function battleMenu(text) {
  const b = Battle.b;
  if (!b) return;
  b.phase = "menu";
  setBox(224, 62);
  const fl = b.def.flavor[b.turn % b.def.flavor.length];
  bText(text || (b.mercy >= 100 ? `* ${b.def.name} больше не хочет драться. Можно пощадить.` : fl));
  const c = await bButtons([
    { html: "<b>⚔</b> БОЙ", cls: "fight" },
    { html: "<b>&lt;/&gt;</b> КОД", cls: "act" },
    { html: "<b>✚</b> ВЕЩИ", cls: "item" },
    { html: "<b>♥</b> ПОЩАДА", cls: "mercy" + (b.mercy >= 100 ? " ready" : "") },
  ]);
  if (c === 0) return doFight();
  if (c === 1) return doAct();
  if (c === 2) return doItem();
  return doMercy();
}

// ---------- БОЙ: остановить полоску ----------
function doFight() {
  const b = Battle.b;
  b.phase = "fight";
  b.fight = { x: 0, dir: 1, done: false, t: 0 };
  bText("* Нажми, когда полоска будет в центре!");
  const el = document.getElementById("batBtns");
  el.innerHTML = "";
  const btn = document.createElement("button");
  btn.className = "bbtn fight wide";
  btn.textContent = "УДАР!";
  btn.onclick = () => strike();
  el.appendChild(btn);
}

function strike() {
  const b = Battle.b;
  if (!b || b.phase !== "fight" || b.fight.done) return;
  b.fight.done = true;
  document.getElementById("batBtns").innerHTML = "";
  const acc = 1 - Math.min(1, Math.abs(b.fight.x - 0.5) * 2);
  let dmg = Math.round(playerAtk() * (0.35 + acc * 1.1));
  const crit = acc > 0.9;
  if (crit) dmg = Math.round(dmg * 1.6);
  if (b.def.boss) dmg = Math.max(1, Math.round(dmg * 0.8));
  sfx("hit");
  hitEnemy(dmg, crit ? "КРИТ!" : null);
  setTimeout(() => afterPlayer("fight"), 700);
}

function hitEnemy(dmg, label) {
  const b = Battle.b;
  b.hp = Math.max(0, b.hp - dmg);
  b.hurt = 0.5;
  b.dmgNums.push({ v: dmg, label, t: 0, x: 128 + (Math.random() * 30 - 15) });
}

// ---------- КОД: действия и вопросы ----------
async function doAct() {
  const b = Battle.b;
  b.phase = "act";
  const acts = [{ t: "🔍 Проверить" }, { t: "🧠 Отладить (вопрос)" }, ...b.def.acts.map((a) => ({ t: a.t })), { t: "← Назад" }];
  const c = await bButtons(acts);
  if (c === acts.length - 1) return battleMenu();
  if (c === 0) {
    await bText(`* ${b.def.name} — АТК ${b.def.atk}, HP ${b.hp}/${b.maxHp}. ${b.def.boss ? "Босс. Сражается за свой код." : "Мелкая ошибка в коде мира."}`, "tap");
    return afterPlayer("check");
  }
  if (c === 1) return doQuiz();
  const a = b.def.acts[c - 2];
  b.mercy = Math.min(100, b.mercy + a.mercy);
  sfx("heal");
  await bText(a.text, "tap");
  afterPlayer("act");
}

function quizPool() {
  const done = LESSONS.filter((l) => G.save.practice[l.id]);
  const z = G.zone && ZONES[G.zone.id];
  const local = done.filter((l) => z && z.lessons.includes(l.id));
  const src = local.length && Math.random() < 0.6 ? local : done.length ? done : [LESSONS[0]];
  const L = src[Math.floor(Math.random() * src.length)];
  return L.quiz[Math.floor(Math.random() * L.quiz.length)];
}

async function doQuiz() {
  const b = Battle.b;
  b.phase = "quiz";
  const q = quizPool();
  const order = q.a.map((_, i) => i).sort(() => Math.random() - 0.5);
  bText("* Клод: «Ответь правильно — и я выстрелю твоим кодом!»\n" + q.q);
  const c = await bButtons(order.map((i) => ({ t: q.a[i], cls: "quiz" })));
  const right = order[c] === q.ok;
  if (right) {
    sfx("heal");
    b.mercy = Math.min(100, b.mercy + 45);
    const dmg = Math.round(6 + G.save.lv * 3 + playerAtk() * 0.6);
    await bText("* ПРАВИЛЬНО! " + q.why, "tap");
    b.claudeLine = "КОМБО КОДА!";
    sfx("portal");
    hitEnemy(dmg, "КОМБО!");
    G.save.stats.right = (G.save.stats.right || 0) + 1;
    setTimeout(() => afterPlayer("quizRight"), 600);
  } else {
    sfx("hurt");
    await bText(`* Мимо! Правильно: «${q.a[q.ok]}». ${q.why}`, "tap");
    G.save.stats.wrong = (G.save.stats.wrong || 0) + 1;
    afterPlayer("quizWrong");
  }
}

// ---------- ВЕЩИ ----------
async function doItem() {
  const b = Battle.b;
  const items = G.save.items;
  if (!items.length) return battleMenu("* Карманы пусты. Только фантик от конфеты.");
  const list = items.map((it) => ({ t: `${it.name} (+${it.heal})` }));
  list.push({ t: "← Назад" });
  const c = await bButtons(list);
  if (c === list.length - 1) return battleMenu();
  const it = items.splice(c, 1)[0];
  const max = playerMaxHp();
  G.save.hp = Math.min(max, G.save.hp + it.heal);
  updateHud();
  sfx("heal");
  await bText(`* Ты съедаешь «${it.name}». HP +${it.heal}.`, 1000);
  afterPlayer("item");
}

// ---------- ПОЩАДА ----------
async function doMercy() {
  const b = Battle.b;
  const opts = [{ t: b.mercy >= 100 ? "♥ Пощадить" : "Пощадить" }];
  if (!b.def.boss) opts.push({ t: "Сбежать" });
  opts.push({ t: "← Назад" });
  const c = await bButtons(opts);
  if (c === opts.length - 1) return battleMenu();
  if (c === 0) {
    if (b.mercy >= 100) return endBattle("spare");
    await bText(`* ${b.def.name} пока не готов мириться.`, 900);
    return afterPlayer("mercyFail");
  }
  if (Math.random() < 0.7) {
    await bText("* Ты сбегаешь! Клод: «Тактическое отступление! Это не трусость, это стратегия!»", "tap");
    return endBattle("flee");
  }
  await bText("* Не получилось сбежать!", 900);
  afterPlayer("fleeFail");
}

// ---------- ход Клода ----------
async function afterPlayer(kind) {
  const b = Battle.b;
  if (!b) return;
  if (b.hp <= 0) return endBattle("win");
  b.turn++;
  const max = playerMaxHp();
  let line = null;
  if (G.save.hp < max * 0.4 && (b.lastHeal || -9) < b.turn - 2) {
    const heal = Math.round(max * 0.35);
    G.save.hp = Math.min(max, G.save.hp + heal);
    b.lastHeal = b.turn;
    updateHud();
    sfx("heal");
    line = `Клод бросает тебе портальную газировку: +${heal} HP!`;
  } else if (kind === "quizRight") {
    line = ["Клод заряжает портальную пушку твоим кодом! Вжух!", "Клод: «Видал? Это ТВОЙ код так бьёт!»", "Клод: «Правильный ответ — лучшее оружие во мультивселенной!»"][b.turn % 3];
  } else if (kind === "item" || kind === "quizWrong") {
    b.shield = 1;
    line = "Клод ставит силовой щит: следующий удар будет слабее!";
  } else if (kind === "fight") {
    const d = Math.round(2 + G.save.lv * 1.5 + Math.random() * 3);
    hitEnemy(d, "Клод");
    sfx("hit");
    line = `Клод стреляет из портальной пушки: −${d} HP!`;
  } else if (kind === "mercyFail") {
    line = "Клод: «Он ещё не готов. Попробуй КОД — разговор или вопрос!»";
  } else if (kind === "act") {
    line = b.mercy >= 100 ? "Клод: «Он сдаётся! Жми ПОЩАДА!»" : "Клод одобрительно кивает: «Дипломатия. Уважаю.»";
  } else {
    line = "Клод протирает очки и анализирует врага.";
  }
  b.claudeLine = line;
  await bText("* " + line, 700);
  if (b.hp <= 0) return endBattle("win");
  enemyTurn();
}

// ---------- ход врага: уворот ----------
const PATTERNS = {
  rain: { w: 120, h: 70, every: 0.22, spawn(b, bx) { addBullet({ x: bx.x + Math.random() * bx.w, y: bx.y - 4, vy: 55 + Math.random() * 25, r: 3, color: "#fff" }); } },
  aim: { w: 110, h: 80, every: 0.55, spawn(b, bx) {
    const side = Math.floor(Math.random() * 4);
    const x = side === 0 ? bx.x - 4 : side === 1 ? bx.x + bx.w + 4 : bx.x + Math.random() * bx.w;
    const y = side === 2 ? bx.y - 4 : side === 3 ? bx.y + bx.h + 4 : bx.y + Math.random() * bx.h;
    const a = Math.atan2(b.heart.y - y, b.heart.x - x);
    addBullet({ x, y, vx: Math.cos(a) * 75, vy: Math.sin(a) * 75, r: 3, color: "#ffe03a" });
  } },
  side: { w: 150, h: 60, every: 0.35, spawn(b, bx) {
    const l = Math.random() < 0.5;
    addBullet({ x: l ? bx.x - 6 : bx.x + bx.w + 6, y: bx.y + 4 + Math.random() * (bx.h - 8), vx: l ? 85 : -85, w: 10, h: 4, color: "#3affd8" });
  } },
  ring: { w: 110, h: 90, every: 1.1, spawn(b, bx) {
    const n = 12, gap = Math.floor(Math.random() * n), cx = bx.x + bx.w / 2, cy = bx.y + bx.h / 2;
    for (let i = 0; i < n; i++) {
      if (i === gap || i === (gap + 1) % n) continue;
      const a = (i / n) * Math.PI * 2;
      addBullet({ x: cx, y: cy, vx: Math.cos(a) * 45, vy: Math.sin(a) * 45, r: 3, color: "#8a8aff" });
    }
  } },
  bars: { w: 160, h: 66, every: 0.8, spawn(b, bx) {
    const l = Math.random() < 0.5;
    const gapY = bx.y + 10 + Math.random() * (bx.h - 30);
    const x = l ? bx.x - 6 : bx.x + bx.w + 6;
    const vx = l ? 70 : -70;
    addBullet({ x, y: bx.y + (gapY - bx.y) / 2, vx, w: 5, h: gapY - bx.y, color: "#fff" });
    addBullet({ x, y: gapY + 20 + (bx.y + bx.h - gapY - 20) / 2, vx, w: 5, h: bx.y + bx.h - gapY - 20, color: "#fff" });
  } },
  code: { w: 130, h: 76, every: 0.3, spawn(b, bx) {
    const words = ["nil", "end", "{}", "==", "do", "()", "--", "..", "if", "0"];
    const w = words[Math.floor(Math.random() * words.length)];
    addBullet({ x: bx.x + 6 + Math.random() * (bx.w - 12), y: bx.y - 6, vy: 50 + Math.random() * 20, text: w, w: w.length * 5, h: 7, color: "#5aff8a" });
  } },
  loop: { w: 110, h: 90, every: 0.12, spawn(b, bx) {
    const cx = bx.x + bx.w / 2, cy = bx.y + bx.h / 2;
    b.loopA = (b.loopA || 0) + 0.55;
    addBullet({ x: cx, y: cy, orbit: { a: b.loopA, r: 4, vr: 32, va: 1.6 }, r: 3, color: "#d6a8ff" });
  } },
  glitch: { w: 120, h: 80, every: 0.45, spawn(b, bx) {
    const s = 14 + Math.random() * 14;
    addBullet({ x: bx.x + Math.random() * (bx.w - s) + s / 2, y: bx.y + Math.random() * (bx.h - s) + s / 2, w: s, h: s, warn: 0.6, life: 1.25, color: ["#ff3a8a", "#3affd8", "#ffe03a"][Math.floor(Math.random() * 3)] });
  } },
  bounce: { w: 120, h: 80, every: 1.4, spawn(b, bx) {
    if (b.bullets.filter((q) => q.bounce).length >= 4) return;
    addBullet({ x: bx.x + 10, y: bx.y + 10, vx: 60 + Math.random() * 30, vy: 50 + Math.random() * 30, r: 5, bounce: true, color: "#ff8a3a" });
  } },
  wave: { w: 140, h: 76, every: 0.9, spawn(b, bx) {
    const gap = Math.floor(Math.random() * 6);
    for (let i = 0; i < 9; i++) {
      if (i === gap || i === gap + 1) continue;
      addBullet({ x: bx.x + 8 + i * ((bx.w - 16) / 8), y: bx.y - 4, vy: 40, r: 3, wobble: i, color: "#7fd8c2" });
    }
  } },
  lava: { w: 130, h: 80, every: 0.28, spawn(b, bx) {
    b.lavaT = (b.lavaT || 0) + 0.28;
    addBullet({ x: bx.x + Math.random() * bx.w, y: bx.y + bx.h + 4, vy: -(60 + Math.random() * 30), r: 3, color: "#ff5a1f", grav: 70 });
  } },
};

function addBullet(o) {
  Battle.b.bullets.push(Object.assign({ vx: 0, vy: 0, t: 0 }, o));
}

function setBox(w, h) {
  const bx = Battle.b.box;
  bx.tw = w;
  bx.th = h;
}

function enemyTurn() {
  const b = Battle.b;
  b.phase = "dodge";
  const pats = b.def.patterns;
  const pname = pats[b.turn % pats.length];
  const p = PATTERNS[pname] || PATTERNS.rain;
  b.pattern = p;
  b.patName = pname;
  setBox(p.w, p.h);
  b.heart.x = 128;
  b.heart.y = 104 + 31;
  b.dodgeT = 0;
  b.dodgeLen = b.def.boss ? 6.5 : 5;
  b.spawnAcc = 0;
  b.bullets = [];
  b.bubble = { text: b.def.taunts[b.turn % b.def.taunts.length], t: 0 };
  document.getElementById("batBtns").innerHTML = "";
  typeInto(document.getElementById("batText"), "* Уворачивайся! Води пальцем по этому полю 👇", "sys", true);
  document.getElementById("batTouch").hidden = false;
}

function endDodge() {
  const b = Battle.b;
  b.bullets = [];
  b.bubble = null;
  document.getElementById("batTouch").hidden = true;
  if (G.save.hp <= 0) return gameOver();
  battleMenu();
}

async function gameOver() {
  const b = Battle.b;
  b.phase = "dead";
  music(null);
  sfx("die");
  updateHud();
  await bText("* Твоё сердце раскололось...", "tap");
  await bText("* Клод: «Стажёр! Вставай! Мультивселенная без тебя не справится. И я тоже.»");
  const c = await bButtons([{ t: "НЕ СДАВАТЬСЯ (заново)", cls: "fight wide" }, { t: "Вернуться к порталу", cls: "wide" }]);
  G.save.hp = playerMaxHp();
  updateHud();
  if (c === 0) {
    b.hp = b.maxHp;
    b.mercy = 0;
    b.turn = 0;
    music(b.def.music || (b.def.boss ? "boss" : "battle"));
    battleMenuIntro();
  } else {
    finishBattle("flee", true);
  }
}

async function endBattle(res) {
  const b = Battle.b;
  b.phase = "end";
  b.bullets = [];
  document.getElementById("batTouch").hidden = true;
  const s = G.save;
  if (res === "win") {
    music(null);
    sfx("victory");
    s.kills = (s.kills || 0) + 1;
    s.gold += b.def.gold;
    await bText(`* ПОБЕДА! ${b.def.name} повержен. +${b.def.xp} XP, +${b.def.gold} монет.`, "tap");
    addXp(b.def.xp);
  } else if (res === "spare") {
    music(null);
    sfx("heal");
    s.spares = (s.spares || 0) + 1;
    const g = Math.round(b.def.gold * 1.2);
    s.gold += g;
    const xp = Math.round(b.def.xp * 0.7);
    await bText(`${b.def.spare} +${xp} XP, +${g} монет.`, "tap");
    addXp(xp);
  }
  finishBattle(res);
}

function finishBattle(res, fled) {
  const b = Battle.b;
  Battle.active = false;
  Battle.b = null;
  G.mode = "world";
  panel("pad");
  if (G.zone) music(ZONES[G.zone.id].music);
  if (b.roamer) {
    if (res === "win" || res === "spare") b.roamer.gone = true;
    else b.roamer.cool = 3;
  }
  // «Вернуться к порталу»: встаём у портала (точка входа в мир), а не там, где проиграли
  if (fled) {
    enterZone(G.zone.id, false);
  }
  saveSoon();
  b.resolve(fled ? "flee" : res);
}

// ---------- обновление и отрисовка ----------
function battleUpdate(dt) {
  const b = Battle.b;
  if (!b) return;
  b.t += dt;
  b.hurt = Math.max(0, b.hurt - dt);
  const bx = b.box;
  bx.w += (bx.tw - bx.w) * Math.min(1, dt * 10);
  bx.h += (bx.th - bx.h) * Math.min(1, dt * 10);
  bx.x = 128 - bx.w / 2;
  bx.y = 104 + (62 - bx.h) / 2 + (bx.th > 62 ? 0 : 0);
  if (bx.th > 62) bx.y = 168 - bx.h;
  for (const d of b.dmgNums) d.t += dt;
  b.dmgNums = b.dmgNums.filter((d) => d.t < 1.2);
  if (b.phase === "fight" && !b.fight.done) {
    b.fight.x += dt * 0.85 * b.fight.dir;
    if (b.fight.x > 1) { b.fight.x = 1; b.fight.dir = -1; }
    if (b.fight.x < 0) { b.fight.x = 0; b.fight.dir = 1; b.fight.t++; if (b.fight.t > 2) strike(); }
  }
  if (b.phase === "dodge") {
    b.dodgeT += dt;
    if (b.bubble) b.bubble.t += dt;
    const R_ = G.save.rules;
    const sp = 95;
    b.heart.x += G.input.dx * sp * dt;
    b.heart.y += G.input.dy * sp * dt;
    b.heart.x += G.input.dragX;
    b.heart.y += G.input.dragY;
    G.input.dragX = 0;
    G.input.dragY = 0;
    b.heart.x = Math.max(bx.x + 4, Math.min(bx.x + bx.w - 4, b.heart.x));
    b.heart.y = Math.max(bx.y + 4, Math.min(bx.y + bx.h - 4, b.heart.y));
    if (b.dodgeT < b.dodgeLen - 0.8) {
      b.spawnAcc += dt;
      const every = b.pattern.every / Math.max(0.3, Math.sqrt(R_.bulletSpeed || 1));
      while (b.spawnAcc > every) { b.spawnAcc -= every; b.pattern.spawn(b, bx); }
    }
    const bs = R_.bulletSpeed || 1;
    b.inv = Math.max(0, b.inv - dt);
    for (const q of b.bullets) {
      q.t += dt;
      if (q.orbit) {
        q.orbit.r += q.orbit.vr * dt * bs;
        q.orbit.a += q.orbit.va * dt * bs;
        q.x = bx.x + bx.w / 2 + Math.cos(q.orbit.a) * q.orbit.r;
        q.y = bx.y + bx.h / 2 + Math.sin(q.orbit.a) * q.orbit.r;
        if (q.orbit.r > 70) q.dead = true;
      } else {
        if (q.grav) q.vy += q.grav * dt;
        q.x += q.vx * dt * bs;
        q.y += q.vy * dt * bs;
        if (q.wobble !== undefined) q.x += Math.sin(q.t * 4 + q.wobble) * 0.6;
        if (q.bounce) {
          if (q.x < bx.x + q.r || q.x > bx.x + bx.w - q.r) q.vx *= -1;
          if (q.y < bx.y + q.r || q.y > bx.y + bx.h - q.r) q.vy *= -1;
          q.x = Math.max(bx.x + q.r, Math.min(bx.x + bx.w - q.r, q.x));
          q.y = Math.max(bx.y + q.r, Math.min(bx.y + bx.h - q.r, q.y));
        }
      }
      if (q.life && q.t > q.life) q.dead = true;
      if (q.x < -40 || q.x > 300 || q.y < -40 || q.y > 240) q.dead = true;
      if (q.warn && q.t < q.warn) continue;
      // попадание
      const hx = b.heart.x, hy = b.heart.y;
      let hit = false;
      if (q.r) hit = Math.hypot(q.x - hx, q.y - hy) < q.r + 2.5;
      else hit = Math.abs(q.x - hx) < q.w / 2 + 2 && Math.abs(q.y - hy) < q.h / 2 + 2;
      if (hit && b.inv <= 0 && !R_.godMode) {
        let dmg = Math.max(1, Math.round(b.def.atk * (R_.enemyDamage ?? 1) * (b.shield ? 0.5 : 1)));
        if ((R_.enemyDamage ?? 1) === 0) dmg = 0;
        b.shield = 0;
        G.save.hp = Math.max(0, G.save.hp - dmg);
        updateHud();
        b.inv = 0.9;
        sfx("hurt");
        shake(3);
        if (!q.bounce && !q.orbit) q.dead = true;
        if (G.save.hp <= 0) { b.dodgeT = 999; }
      }
    }
    b.bullets = b.bullets.filter((q) => !q.dead);
    if (b.dodgeT >= b.dodgeLen) endDodge();
  }
}

function battleDraw(c) {
  const b = Battle.b;
  if (!b) return;
  R(c, 0, 0, 256, 192, "#000");
  // фон за врагом: своя картинка у каждого мира
  battleBg(c, G.zone ? G.zone.id : "lab", b.t);
  if (b.phase !== "end" || b.hp > 0) battleSprite(c, b.def, 128, 52, b.t, b.hurt);
  // имя и полоска HP врага
  c.font = '8px "Press Start 2P", monospace';
  c.textAlign = "center";
  outText(c, b.def.name, 128, 10, b.mercy >= 100 ? "#ffe03a" : "#fff");
  if (b.hurt > 0 || b.phase === "fight") {
    R(c, 97, 85, 62, 7, "#000");
    R(c, 98, 86, 60, 5, "#5a1a1a");
    R(c, 98, 86, Math.round((60 * b.hp) / b.maxHp), 5, "#3aff6a");
    R(c, 98, 86, Math.round((60 * b.hp) / b.maxHp), 1, "#a8ffbe");
  }
  if (b.mercy > 0 && b.mercy < 100) {
    R(c, 97, 92, 62, 4, "#000");
    R(c, 98, 93, 60, 2, "#333");
    R(c, 98, 93, Math.round(0.6 * b.mercy), 2, "#ffe03a");
  }
  // цифры урона с обводкой
  for (const d of b.dmgNums) {
    const col = d.label === "Клод" ? "#ffb08a" : "#ff4a4a";
    const dy = Math.round(d.t * 20 + (d.t < 0.25 ? Math.sin(d.t * 12.5) * 6 : 0));
    c.font = '10px "Press Start 2P", monospace';
    outText(c, String(d.v), Math.round(d.x), 40 - dy, col);
    if (d.label) { c.font = '6px "Press Start 2P", monospace'; outText(c, d.label, Math.round(d.x), 50 - dy, col); }
  }
  // реплика врага: облачко справа, длинную фразу переносим, чтобы не уезжала за край
  if (b.bubble) {
    c.textAlign = "left";
    const bb = b.bubble;
    if (!bb.lines) {
      bb.lines = wrapMix(c, bb.text, 72, 12).slice(0, 3);
      bb.w = Math.ceil(Math.max(...bb.lines.map((l) => mixText(c, l, 0, 0, 12, false)))) + 10;
    }
    const w = bb.w, h = bb.lines.length * 11 + 7;
    const x = Math.min(170, 252 - w), y = 16;
    R(c, x - 1, y - 1, w + 2, h + 2, "#000");
    R(c, x - 5, y + 5, 5, 6, "#000");
    R(c, x, y, w, h, "#fff");
    R(c, x - 4, y + 6, 4, 4, "#fff");
    R(c, x, y + h - 1, w, 1, "#c8c8d8");
    c.fillStyle = "#000";
    let left = Math.floor(bb.t * 30);
    bb.lines.forEach((l, i) => {
      if (left <= 0) return;
      mixText(c, l.slice(0, left), x + 5, y + 12 + i * 11, 12);
      left -= l.length + 1;
    });
  }
  // рамка
  const bx = b.box;
  R(c, bx.x - 2, bx.y - 2, bx.w + 4, bx.h + 4, "#fff");
  R(c, bx.x, bx.y, bx.w, bx.h, "#000");
  if (b.phase !== "fight" && b.phase !== "dodge" && b.phase !== "dead" && bx.w > 150) {
    const cx = bx.x + bx.w / 2;
    drawKid(c, cx - 30, bx.y + 22, "up", Math.floor(b.t * 2) % 2, playerLook());
    drawClaude(c, cx + 14, bx.y + 22, "up", b.t);
    if (b.claudeLine) {
      // реплика Клода над рамкой: укорачиваем по ширине рамки (считаем один раз)
      c.textAlign = "left";
      if (!b.claudeFit || b.claudeFit.src !== b.claudeLine) {
        let t = b.claudeLine;
        while (t.length > 4 && mixText(c, t, 0, 0, 12, false) > bx.tw - 10) t = t.slice(0, -2).trimEnd() + "…";
        b.claudeFit = { src: b.claudeLine, t, w: mixText(c, t, 0, 0, 12, false) };
      }
      c.fillStyle = "#ffb08a";
      mixText(c, b.claudeFit.t, Math.round(cx - b.claudeFit.w / 2), bx.y + 15, 12);
    }
  }
  if (b.phase === "fight") {
    const x0 = bx.x + 6, w = bx.w - 12;
    R(c, x0, bx.y + 20, w, 22, "#111");
    for (let i = 0; i < 9; i++) R(c, x0 + (w * i) / 8, bx.y + 22, 1, 18, "#333");
    R(c, x0 + w / 2 - 6, bx.y + 20, 12, 22, "rgba(255,224,58,0.35)");
    R(c, x0 + w / 2 - 1, bx.y + 18, 2, 26, "#ffe03a");
    R(c, x0 + b.fight.x * w - 1, bx.y + 16, 3, 30, "#fff");
  }
  if (b.phase === "dodge" || b.phase === "dead") {
    c.save();
    c.beginPath();
    c.rect(bx.x, bx.y, bx.w, bx.h);
    c.clip();
    for (const q of b.bullets) {
      const warn = q.warn && q.t < q.warn;
      if (warn) {
        c.strokeStyle = Math.floor(q.t * 12) % 2 ? q.color : "#555";
        c.strokeRect(Math.round(q.x - q.w / 2) + 0.5, Math.round(q.y - q.h / 2) + 0.5, q.w, q.h);
        continue;
      }
      if (q.text) {
        c.fillStyle = q.color;
        c.font = '8px "Press Start 2P", monospace';
        c.textAlign = "center";
        c.fillText(q.text, q.x, q.y + 3);
      } else if (q.r) {
        c.fillStyle = q.color;
        c.beginPath();
        c.arc(Math.round(q.x), Math.round(q.y), q.r, 0, Math.PI * 2);
        c.fill();
      } else R(c, q.x - q.w / 2, q.y - q.h / 2, q.w, q.h, q.color);
    }
    c.restore();
    const blink = b.inv > 0 && Math.floor(b.inv * 12) % 2;
    if (!blink) drawHeart(c, b.heart.x - 4, b.heart.y - 3, G.save.rules.godMode ? "#ffe03a" : "#ff2a3a");
    if (b.shield) { c.strokeStyle = "#ffb08a"; c.beginPath(); c.arc(b.heart.x, b.heart.y, 8, 0, Math.PI * 2); c.stroke(); }
  }
  // низ: имя, LV, HP, Клод
  const max = playerMaxHp();
  c.textAlign = "left";
  c.font = '7px "Press Start 2P", monospace';
  c.fillStyle = "#fff";
  c.fillText(`${G.save.name.slice(0, 8).toUpperCase()}  LV ${G.save.lv}`, 10, 184);
  c.fillText("HP", 120, 184);
  R(c, 136, 177, 50, 8, "#8a1a1a");
  R(c, 136, 177, Math.round((50 * G.save.hp) / max), 8, "#ffe03a");
  c.fillText(`${G.save.hp}/${max}`, 190, 184);
  if (b.phase === "dodge" || b.phase === "dead" || b.phase === "fight") {
    c.save();
    c.translate(230, 168);
    drawClaude(c, 0, 0, "left", b.t, {});
    c.restore();
  }
}

// управление пальцем во время уворота: относительное перемещение
function setupDodgeTouch() {
  const el = document.getElementById("batTouch");
  let last = null;
  const scale = () => 256 / document.getElementById("screen").getBoundingClientRect().width;
  el.addEventListener("pointerdown", (e) => { el.setPointerCapture(e.pointerId); last = [e.clientX, e.clientY]; });
  el.addEventListener("pointermove", (e) => {
    if (!last) return;
    const k = scale() * 1.15;
    G.input.dragX += (e.clientX - last[0]) * k;
    G.input.dragY += (e.clientY - last[1]) * k;
    last = [e.clientX, e.clientY];
  });
  const up = () => { last = null; };
  el.addEventListener("pointerup", up);
  el.addEventListener("pointercancel", up);
  // во время уворота можно водить пальцем и прямо по экрану игры
  const scr = document.getElementById("screen");
  let l2 = null;
  scr.addEventListener("pointerdown", (e) => { if (Battle.active && Battle.b.phase === "dodge") l2 = [e.clientX, e.clientY]; });
  scr.addEventListener("pointermove", (e) => {
    if (!l2 || !Battle.active) return;
    const k = scale();
    G.input.dragX += (e.clientX - l2[0]) * k;
    G.input.dragY += (e.clientY - l2[1]) * k;
    l2 = [e.clientX, e.clientY];
  });
  scr.addEventListener("pointerup", () => { l2 = null; });
  // нажатие на текст боя или пустое место пульта: дописать текст / «дальше ▼»
  document.getElementById("bat").addEventListener("click", (e) => {
    if (!Battle.active || G.overlay || e.target.closest("button") || e.target.closest("#batTouch")) return;
    batTap();
  });
}

// бой, созданный живым Клодом
function customEnemy(o) {
  const looks = ["slime", "bug", "ghost", "robot", "nil", "lava", "cat", "noob", "owl", "kid", "claude", "serpent", "tree"];
  const pats = Object.keys(PATTERNS);
  const name = String(o.name || "Безымянный монстр").slice(0, 28);
  return {
    name,
    look: looks.includes(o.look) ? o.look : "slime",
    color: /^#[0-9a-f]{6}$/i.test(o.color || "") ? o.color : "#c03aff",
    hp: Math.max(5, Math.min(999, Math.round(+o.hp || 40))),
    atk: Math.max(1, Math.min(30, Math.round(+o.attack || 4))),
    xp: Math.max(1, Math.min(300, Math.round(+o.xp || (+o.hp || 40) / 2))),
    gold: Math.max(0, Math.min(300, Math.round(+o.gold || 10))),
    boss: !!o.boss,
    scale: o.boss ? 4 : 3,
    glitch: !!o.glitch,
    patterns: (() => {
      const ok = Array.isArray(o.patterns) ? o.patterns.filter((p) => pats.includes(p)).slice(0, 4) : [];
      return ok.length ? ok : ["rain", "aim"];
    })(),
    intro: String(o.intro || `* ${name} появляется по велению Профессора Клода!`).slice(0, 160),
    flavor: [String(o.flavor || `* ${name} смотрит на тебя.`).slice(0, 140)],
    taunts: (Array.isArray(o.taunts) && o.taunts.length ? o.taunts : ["Ха!", "Попробуй увернись!", "Это бой!"]).map((t) => String(t).slice(0, 40)).slice(0, 6),
    acts: [{ t: String(o.act || "Подружиться").slice(0, 30), text: `* Ты пытаешься подружиться с ${name}.`, mercy: 50 }],
    spare: `* ${name} больше не хочет драться.`,
    music: o.boss ? "boss" : "battle",
  };
}
