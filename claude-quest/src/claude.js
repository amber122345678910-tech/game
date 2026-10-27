// Живой Профессор Клод: чат прямо в игре, может менять правила через инструменты
const Claude = { sample: null, checked: false, toolsOk: false, maxTools: 0, busy: false, ctl: null, ctx: null };

async function initClaude() {
  try {
    if (window.claude && typeof window.claude.use === "function") {
      const s = await window.claude.use("sample");
      Claude.sample = s || null;
      if (s) {
        try {
          const lim = await s.limits();
          Claude.toolsOk = !!(lim && lim.tools);
          Claude.maxTools = lim && lim.tools ? lim.tools.maxCount : 0;
        } catch (e) {
          Claude.toolsOk = false;
        }
      }
    }
  } catch (e) {
    Claude.sample = null;
  }
  Claude.checked = true;
  updateChatBanner();
}

function updateChatBanner() {
  const el = document.getElementById("chatBanner");
  if (!el) return;
  if (!Claude.checked) { el.textContent = "Подключаю мозг Клода…"; el.hidden = false; return; }
  if (Claude.disabled) { el.innerHTML = Claude.disabled; el.hidden = false; return; }
  if (!Claude.sample) {
    el.innerHTML = "Офлайн-режим: понимаю «что дальше», «домашка», «объясни урок», «быстрее», «снег», «корона», «босс», «вылечи».";
    el.hidden = false;
    return;
  }
  el.hidden = true;
}

function stateForClaude() {
  const s = G.save;
  const rules = {};
  for (const k in s.rules) if (s.rules[k] !== RULE_DEFAULTS[k]) rules[k] = s.rules[k];
  const st = {
    имя_игрока: s.name,
    мир: G.zone ? ZONES[G.zone.id].name : "меню",
    открытые_миры: ZONE_ORDER.filter(zoneOpen),
    LV: s.lv, HP: `${s.hp}/${playerMaxHp()}`, атака: playerAtk(), монеты: s.gold,
    вещи: s.items.map((i) => i.name),
    изменённые_правила: rules,
    уроки_пройдены: LESSONS.filter((l) => s.practice[l.id]).map((l) => `${l.n}. ${l.title}`),
    домашки: Object.fromEntries(Object.entries(s.hw).map(([k, v]) => [`№${HOMEWORK[k].lesson.n} ${HOMEWORK[k].title}`, { given: "задана", checked: "проверена, не показана", done: "сдана" }[v]])),
    особые_домашки: (s.customHw || []).map((h) => `${h.title}: ${h.status === "done" ? "сдана" : "в работе"}`),
    что_делать_дальше: objective(),
    в_бою: Battle.active ? Battle.b.def.name : false,
  };
  return JSON.stringify(st, null, 1);
}

function rulesPrompt(extra) {
  return `Ты — Профессор Клод, персонаж пиксельной игры «Код Мультивселенной» (стиль Undertale, приключения с порталами по мультивселенной). Ты гениальный, немного безумный и саркастичный, но очень добрый учёный-ИИ: оранжевая искра в лабораторном халате с портальной пушкой. Игрок — твой стажёр. Скорее всего это школьник, он учит программирование с нуля и играет с телефона (компьютера у него нет).

Как отвечать:
- Только по-русски, простыми словами, как другу. Коротко: обычно 2–5 предложений. Длиннее — только если объясняешь код.
- Код на Luau (Roblox) — в блоках \`\`\`lua. Объясняй каждую новую штуку, с аналогиями из игр и жизни.
- Ты учитель: если просят решить домашку целиком, сначала дай подсказку и кусочек кода. Если ученик уже пробовал и застрял — покажи решение и объясни по строчкам.
- В игре есть свой мини-Roblox (кнопка </> → редактор): работают print, переменные, if, циклы, функции, таблицы, wait/task.wait, Instance.new("Part"), Vector3, Color3, BrickColor, Enum.Material, Enum.PartType, Anchored, Transparency, Touched, ClickDetector, Players.PlayerAdded, leaderstats, IntValue, TweenService, Debris. Нет ScreenGui, DataStore, вращения деталей и звуков. Про них объясняй, как это делается в настоящем Roblox Studio.
- Шути в характере, но без грубости и взрослых тем.

Изменения игры:
- У тебя есть инструменты, которые по-настоящему меняют игру. Если игрок просит что-то поменять (скорость, здоровье, сложность, погода, цвет, шляпа, новый враг или бой, новый персонаж, переместиться, новая домашка, код в редактор) — вызови нужный инструмент, а потом в ответе в характере скажи, что сделал.
- Если просьбу нельзя выполнить инструментами (новый мир, новая механика), честно скажи: это может сделать Клод в том чате Claude, где делали игру, — пусть попросит там.
- Ничего не меняй без просьбы игрока. Не делай игру скучной: бессмертие можно, но подшути над этим.

Состояние игры сейчас:
${stateForClaude()}${extra ? "\n\n" + extra : ""}`;
}

const LOOKS = ["slime", "bug", "ghost", "robot", "nil", "lava", "cat", "noob", "owl", "kid", "claude", "serpent", "tree"];
function clampNum(v, a, b, d) {
  v = Number(v);
  if (!isFinite(v)) return d;
  return Math.max(a, Math.min(b, v));
}

function makeTools() {
  const list = [
    {
      name: "change_rules",
      description: "Меняет правила игры. Передай только поля, которые нужно изменить. Возвращает новые правила.",
      inputSchema: {
        type: "object",
        properties: {
          speed: { type: "number", description: "Скорость ходьбы игрока, 0.3–5. Обычно 1." },
          maxHpBonus: { type: "number", description: "Добавка к максимальному HP, 0–500." },
          attackBonus: { type: "number", description: "Добавка к силе атаки, 0–100." },
          enemyDamage: { type: "number", description: "Множитель урона врагов, 0–5. 0 = враги не ранят, 1 = обычно." },
          bulletSpeed: { type: "number", description: "Скорость пуль врагов, 0.3–3. 1 = обычно." },
          godMode: { type: "boolean", description: "Бессмертие в бою." },
          weather: { type: "string", enum: ["none", "rain", "snow", "confetti", "glitch", "stars", "leaves"] },
          worldHue: { type: "number", description: "Сдвиг цвета всего мира в градусах 0–360. 0 = обычный." },
          playerColor: { type: "string", description: "Цвет одежды игрока в формате #rrggbb. Пустая строка = обычный." },
          playerSize: { type: "number", description: "Размер игрока 0.5–2." },
          hat: { type: "string", enum: ["none", "crown", "cap", "wizard", "horns", "tophat", "antenna"] },
          night: { type: "boolean", description: "Ночь: темно, светло только вокруг игрока." },
          encounters: { type: "boolean", description: "Ползают ли по мирам жуки-баги, с которыми можно подраться." },
          claudeFollows: { type: "boolean", description: "Ходит ли Клод за игроком." },
          textSpeed: { type: "number", description: "Скорость текста в диалогах 1–5." },
          heal: { type: "boolean", description: "true = полностью вылечить игрока." },
          reset: { type: "boolean", description: "true = вернуть все правила к обычным." },
        },
      },
      execute(i) {
        const r = G.save.rules;
        if (i.reset) Object.assign(r, RULE_DEFAULTS);
        if (i.speed !== undefined) r.speed = clampNum(i.speed, 0.3, 5, 1);
        if (i.maxHpBonus !== undefined) r.maxHpBonus = Math.round(clampNum(i.maxHpBonus, 0, 500, 0));
        if (i.attackBonus !== undefined) r.attackBonus = Math.round(clampNum(i.attackBonus, 0, 100, 0));
        if (i.enemyDamage !== undefined) r.enemyDamage = clampNum(i.enemyDamage, 0, 5, 1);
        if (i.bulletSpeed !== undefined) r.bulletSpeed = clampNum(i.bulletSpeed, 0.3, 3, 1);
        if (i.godMode !== undefined) r.godMode = !!i.godMode;
        if (i.weather !== undefined) r.weather = ["none", "rain", "snow", "confetti", "glitch", "stars", "leaves"].includes(i.weather) ? i.weather : "none";
        if (i.worldHue !== undefined) r.worldHue = clampNum(i.worldHue, 0, 360, 0);
        if (i.playerColor !== undefined) r.playerColor = /^#[0-9a-f]{6}$/i.test(i.playerColor) ? i.playerColor : "";
        if (i.playerSize !== undefined) r.playerSize = clampNum(i.playerSize, 0.5, 2, 1);
        if (i.hat !== undefined) r.hat = ["none", "crown", "cap", "wizard", "horns", "tophat", "antenna"].includes(i.hat) ? i.hat : "none";
        if (i.night !== undefined) r.night = !!i.night;
        if (i.encounters !== undefined) r.encounters = !!i.encounters;
        if (i.claudeFollows !== undefined) r.claudeFollows = !!i.claudeFollows;
        if (i.textSpeed !== undefined) r.textSpeed = clampNum(i.textSpeed, 1, 5, 2);
        G.save.hp = Math.min(G.save.hp, playerMaxHp());
        if (i.heal) G.save.hp = playerMaxHp();
        applyRules();
        chatNote("⚙ Правила игры изменены");
        saveSoon();
        return { ok: true, rules: r, hp: `${G.save.hp}/${playerMaxHp()}` };
      },
    },
    {
      name: "give_reward",
      description: "Выдаёт игроку предмет (лечит в бою), опыт или монеты.",
      inputSchema: {
        type: "object",
        properties: {
          item_name: { type: "string" },
          item_heal: { type: "number", description: "Сколько HP лечит предмет, 1–99" },
          item_description: { type: "string" },
          xp: { type: "number", description: "Опыт 0–200" },
          gold: { type: "number", description: "Монеты 0–500" },
        },
      },
      execute(i) {
        const got = [];
        if (i.item_name) {
          giveItem({ name: String(i.item_name).slice(0, 30), heal: Math.round(clampNum(i.item_heal, 1, 99, 10)), desc: String(i.item_description || "Подарок Профессора").slice(0, 80) }, true);
          got.push("предмет " + i.item_name);
        }
        if (i.xp) { addXp(Math.round(clampNum(i.xp, 0, 200, 0))); got.push(i.xp + " XP"); }
        if (i.gold) { G.save.gold += Math.round(clampNum(i.gold, 0, 500, 0)); got.push(i.gold + " монет"); }
        updateHud();
        chatNote("🎁 Получено: " + (got.join(", ") || "ничего"));
        saveSoon();
        return { ok: true, got };
      },
    },
    {
      name: "start_battle",
      description: "Создаёт врага и начинает бой, как только игрок закроет чат. Бой как в Undertale: игрок уворачивается сердечком, а Клод помогает.",
      inputSchema: {
        type: "object",
        properties: {
          name: { type: "string" },
          look: { type: "string", enum: LOOKS },
          color: { type: "string", description: "#rrggbb" },
          hp: { type: "number", description: "5–999. Обычный враг 15–40, босс 80–300." },
          attack: { type: "number", description: "Урон за попадание 1–30, обычно 3–8." },
          boss: { type: "boolean" },
          intro: { type: "string", description: "Фраза при появлении, начинается со звёздочки: * ..." },
          taunts: { type: "array", items: { type: "string" }, description: "Короткие реплики врага" },
          patterns: {
            type: "array",
            items: { type: "string", enum: ["rain", "aim", "side", "ring", "bars", "code", "loop", "glitch", "bounce", "wave", "lava"] },
            description: "Атаки: rain — дождь, aim — прицельные, side — с боков, ring — кольца, bars — стены с проходом, code — падающий код, loop — спираль, glitch — вспышки, bounce — мячи, wave — волна, lava — снизу",
          },
          act: { type: "string", description: "Мирное действие, которым врага можно убедить сдаться" },
        },
        required: ["name"],
      },
      execute(i) {
        G.pendingBattle = customEnemy(i);
        chatNote(`⚔ Бой с «${G.pendingBattle.name}» начнётся, когда закроешь чат`);
        return { ok: true, note: "Бой начнётся после закрытия чата" };
      },
    },
    {
      name: "spawn_npc",
      description: "Ставит нового персонажа рядом с игроком в текущем мире. Он говорит свои фразы, когда игрок к нему подходит.",
      inputSchema: {
        type: "object",
        properties: {
          name: { type: "string" },
          look: { type: "string", enum: ["slime", "robot", "ghost", "cat", "kid", "noob", "owl", "mushroom", "bug"] },
          color: { type: "string", description: "#rrggbb" },
          lines: { type: "array", items: { type: "string" } },
        },
        required: ["name", "lines"],
      },
      execute(i) {
        if (!G.zone) throw new Error("Игрок сейчас не в мире");
        const npc = spawnCustomNpc(i);
        chatNote(`👤 В мире появился ${npc.name}`);
        saveSoon();
        return { ok: true, where: ZONES[G.zone.id].name };
      },
    },
    {
      name: "teleport",
      description: "Перемещает игрока в другой мир (только в уже открытые). Сработает после закрытия чата.",
      inputSchema: { type: "object", properties: { zone: { type: "string", enum: ZONE_ORDER } }, required: ["zone"] },
      execute(i) {
        const z = String(i.zone);
        if (!ZONES[z]) throw new Error("Нет такого мира");
        if (!zoneOpen(z)) throw new Error("Этот мир ещё закрыт: " + zoneMissing(z).join(", "));
        G.pendingTravel = z;
        chatNote(`🌀 Портал в «${ZONES[z].name}» откроется после закрытия чата`);
        return { ok: true };
      },
    },
    {
      name: "add_homework",
      description: "Даёт игроку новую особую домашку. Игрок напишет код в редакторе и покажет тебе в мире.",
      inputSchema: {
        type: "object",
        properties: {
          title: { type: "string" },
          task: { type: "string", description: "Понятное задание на 1–3 предложения" },
          example: { type: "string", description: "Необязательная подсказка-код" },
        },
        required: ["title", "task"],
      },
      execute(i) {
        const h = { id: "c" + Date.now().toString(36), title: String(i.title).slice(0, 50), task: String(i.task).slice(0, 500), example: i.example ? String(i.example).slice(0, 1500) : "", status: "given" };
        G.save.customHw = (G.save.customHw || []).concat([h]).slice(-20);
        chatNote(`📜 Новая домашка: «${h.title}» (в редакторе </>)`);
        saveSoon();
        return { ok: true, id: h.id };
      },
    },
    {
      name: "put_code_in_editor",
      description: "Кладёт код в песочницу редактора, чтобы игрок открыл и запустил его.",
      inputSchema: { type: "object", properties: { code: { type: "string" } }, required: ["code"] },
      execute(i) {
        G.save.code.sandbox = String(i.code).slice(0, 8000);
        chatNote("🧪 Код положен в Песочницу редактора");
        saveSoon();
        return { ok: true };
      },
    },
  ];
  return Claude.maxTools ? list.slice(0, Claude.maxTools) : list;
}

// ---------- окно чата ----------
function openChat(prefill, ctx) {
  const el = document.getElementById("chat");
  el.hidden = false;
  G.overlay = "chat";
  Claude.ctx = ctx || null;
  renderChat();
  renderChips();
  updateChatBanner();
  fitSheet();
  const inp = document.getElementById("chatInput");
  if (prefill) inp.value = prefill;
  document.getElementById("chatCtx").hidden = !ctx;
  // на телефоне не открываем клавиатуру сразу — пусть сначала прочитает
  if (!(window.matchMedia && matchMedia("(pointer: coarse)").matches)) setTimeout(() => inp.focus(), 50);
  fitChat();
}

function closeChat() {
  if (Claude.ctl) Claude.ctl.abort();
  document.getElementById("chatInput").blur();
  document.getElementById("chat").hidden = true;
  fitChat();
  G.overlay = null;
  if (document.getElementById("editor").hidden === false) G.overlay = "editor";
  if (G.pendingTravel && G.overlay !== "editor") {
    const z = G.pendingTravel;
    G.pendingTravel = null;
    queueScene(() => travel(z));
  }
  if (G.pendingBattle && G.overlay !== "editor" && !Battle.active && G.mode === "world") {
    const e = G.pendingBattle;
    G.pendingBattle = null;
    queueScene(async () => { await startBattle(e); });
  }
}

// клавиатура телефона открыта: page.html прячет баннер и подсказки (#chat.kb), поле — в одну строку
function fitChat() {
  const el = document.getElementById("chat");
  const inp = document.getElementById("chatInput");
  const vv = window.visualViewport;
  const h = vv ? vv.height : window.innerHeight;
  const kb = !el.hidden && document.activeElement === inp && h < 520;
  if (el.classList.contains("kb") === kb) return;
  el.classList.toggle("kb", kb);
  inp.rows = kb ? 1 : 2;
  if (kb) document.getElementById("chatLog").scrollTop = 1e9;
}

// есть ли что сдать Клоду: проверенная домашка, готовое особое задание или уже написанный код
function hwToShow() {
  const s = G.save;
  if (!s) return false;
  for (const h of Object.keys(HOMEWORK)) {
    if (s.hw[h] === "checked") return true;
    const code = (s.code["h:" + h] || "").trim();
    if (s.hw[h] === "given" && code && code !== (HOMEWORK[h].starter || "").trim()) return true;
  }
  return (s.customHw || []).some((h) => {
    const code = (s.code["c:" + h.id] || "").trim();
    return h.status === "ready" || (h.status !== "done" && code && code !== "-- " + h.title);
  });
}

// кнопка «📜 Сдать домашку» первой в подсказках чата
function renderChips() {
  const box = document.getElementById("chatChips");
  let b = document.getElementById("chatHwChip");
  if (!(hwToShow() && G.mode === "world" && !Battle.active)) {
    if (b) b.remove();
    return;
  }
  if (!b) {
    b = document.createElement("button");
    b.id = "chatHwChip";
    b.className = "hwChip";
    b.textContent = "📜 Сдать домашку";
    box.prepend(b);
  }
  box.scrollLeft = 0;
}

// закрываем чат (и редактор) и показываем домашку Клоду в мире
function handInHomework() {
  closeChat();
  if (!document.getElementById("editor").hidden) closeEditor();
  if (G.mode !== "world" || Battle.active) return;
  if (!G.sceneQueue.includes(showHomework)) runScene(showHomework);
}

function mdToHtml(t) {
  const parts = String(t).split(/```(?:lua|luau)?\n?/);
  let html = "";
  parts.forEach((p, i) => {
    if (i % 2) {
      const code = p.replace(/\n$/, "");
      html += `<div class="code"><pre>${highlight(code)}</pre><button class="pill tocode" data-code="${encodeURIComponent(code)}">▶ В редактор</button></div>`;
    } else {
      html += escHtml(p)
        .replace(/`([^`\n]+)`/g, "<code>$1</code>")
        .replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>")
        .replace(/\n/g, "<br>");
    }
  });
  return html;
}

function renderChat() {
  const box = document.getElementById("chatLog");
  box.innerHTML = "";
  const hist = G.save.chat.slice(-40);
  if (!hist.length) {
    addBubble("assistant", `Профессор Клод на связи! Спрашивай что угодно про код, Roblox или эту игру. Я могу и игру менять: скажи «сделай меня быстрее», «включи снег» или «создай босса-пиццу».`, true);
  }
  for (const m of hist) {
    if (m.role === "note") addNote(m.content);
    else if (m.role === "user") {
      const u = userShown(m);
      addBubble("user", u.text, false, u.att);
    } else addBubble(m.role, m.content, true);
  }
  box.scrollTop = box.scrollHeight;
}

// что показать в пузыре ученика: только его текст, без кода из редактора (старые сохранения — обрезаем)
function userShown(m) {
  const c = String(m.content || "");
  const cut = c.indexOf("\n\n[Из редактора]");
  if (m.display != null) return { text: m.display, att: !!m.ctx };
  return { text: cut >= 0 ? c.slice(0, cut) : c, att: cut >= 0 };
}

function addBubble(role, text, md, att) {
  const box = document.getElementById("chatLog");
  const row = document.createElement("div");
  row.className = "msg " + (role === "user" ? "me" : "cl");
  if (role !== "user") {
    const cv = document.createElement("canvas");
    cv.width = 16;
    cv.height = 20;
    cv.className = "avatar";
    const c = cv.getContext("2d");
    drawClaude(c, 0, 0, "down", 0.3);
    row.appendChild(cv);
  }
  const b = document.createElement("div");
  b.className = "bubble";
  if (md) b.innerHTML = mdToHtml(text);
  else b.textContent = text;
  if (att) {
    const a = document.createElement("div");
    a.className = "att";
    a.textContent = "📎 код из редактора";
    b.appendChild(a);
  }
  row.appendChild(b);
  box.appendChild(row);
  box.scrollTop = box.scrollHeight;
  return b;
}

function addNote(t) {
  const box = document.getElementById("chatLog");
  const n = document.createElement("div");
  n.className = "note";
  n.textContent = t;
  box.appendChild(n);
  box.scrollTop = box.scrollHeight;
}

function chatNote(t) {
  G.save.chat.push({ role: "note", content: t });
  if (!document.getElementById("chat").hidden) addNote(t);
  else toast(t);
}

function chatTurns() {
  // последние реплики без служебных заметок; начинаем с user
  const h = G.save.chat.filter((m) => m.role === "user" || m.role === "assistant").slice(-14);
  while (h.length && h[0].role !== "user") h.shift();
  return h.map((m) => ({ role: m.role, content: String(m.content).slice(0, 4000) }));
}

async function sendChat() {
  const inp = document.getElementById("chatInput");
  const text = inp.value.trim();
  if (!text || Claude.busy) return;
  inp.value = "";
  // модель получает код из редактора, а в пузыре — только то, что написал ученик
  let content = text;
  const c = Claude.ctx;
  if (c) {
    content += `\n\n[Из редактора] Задание: ${c.task || "песочница"}\nКод:\n\`\`\`lua\n${String(c.code || "").slice(0, 3000)}\n\`\`\`\nВывод:\n${String(c.out || "(пусто)").slice(0, 800)}`;
    Claude.ctx = null;
    document.getElementById("chatCtx").hidden = true;
  }
  G.save.chat.push(c ? { role: "user", content, display: text, ctx: true } : { role: "user", content });
  addBubble("user", text, false, !!c);
  saveSoon();
  if (!Claude.sample || Claude.disabled) {
    const reply = offlineReply(text, c);
    G.save.chat.push({ role: "assistant", content: reply });
    setTimeout(() => { addBubble("assistant", reply, true); renderChips(); }, 250);
    return;
  }
  Claude.busy = true;
  setChatBusy(true);
  const bubble = addBubble("assistant", "", false);
  bubble.innerHTML = '<span class="thinking">Клод думает<i>.</i><i>.</i><i>.</i></span>';
  Claude.ctl = new AbortController();
  const smart = !!G.save.settings.smart;
  const opts = {
    signal: Claude.ctl.signal,
    modelTier: smart ? "default" : "quick",
    cache: false,
    onText: ({ text }) => {
      bubble.textContent = text;
      document.getElementById("chatLog").scrollTop = 1e9;
    },
  };
  if (Claude.toolsOk) {
    opts.tools = makeTools();
    delete opts.cache;
  }
  try {
    const turns = [{ role: "user", content: rulesPrompt() }, ...chatTurns()];
    const res = await Claude.sample(turns, opts);
    const out = res.text.trim();
    bubble.innerHTML = mdToHtml(out) + (res.truncated ? "<br><i>(оборвалось — спроси покороче)</i>" : "");
    G.save.chat.push({ role: "assistant", content: out });
  } catch (e) {
    const code = e && e.code;
    if (code === "cancelled") {
      bubble.textContent = e.text || "(остановлено)";
      if (e.text) G.save.chat.push({ role: "assistant", content: e.text });
    } else if (code === "not_granted" || code === "sampling_disabled" || code === "not_declared" || code === "capability_disabled" || code === "capability_removed") {
      Claude.disabled = "Живой Клод выключен: доступ к Claude не разрешён. Сейчас я в офлайн-режиме. Чтобы включить, открой игру заново и нажми «Разрешить».";
      updateChatBanner();
      const reply = offlineReply(text, c);
      bubble.innerHTML = mdToHtml(reply);
      G.save.chat.push({ role: "assistant", content: reply });
    } else if (code === "rate_limited") {
      bubble.textContent = "Мой мозг перегрелся (лимит запросов). Подожди минутку и спроси снова.";
    } else if (code === "refused") {
      bubble.textContent = "Про это я говорить не буду. Давай лучше про код!";
    } else if (code === "tools_unavailable") {
      Claude.toolsOk = false;
      bubble.textContent = "Мои инструменты сейчас недоступны. Спроси ещё раз — отвечу без них.";
    } else {
      bubble.textContent = (e && e.text ? e.text + "\n\n" : "") + "Связь с мозгом прервалась. Попробуй ещё раз.";
    }
  } finally {
    Claude.busy = false;
    Claude.ctl = null;
    setChatBusy(false);
    renderChips();
    if (G.save.chat.length > 80) G.save.chat = G.save.chat.slice(-60);
    saveSoon();
    document.getElementById("chatLog").scrollTop = 1e9;
  }
}

function setChatBusy(b) {
  document.getElementById("chatSend").hidden = b;
  document.getElementById("chatStop").hidden = !b;
}

// проверка домашки живым Клодом; null — если мозг не подключён
async function claudeReview(title, task, code, autoPassed) {
  if (!Claude.sample || Claude.disabled) return null;
  dlgThinking("Клод вчитывается в твой код");
  try {
    const prompt = rulesPrompt() + `

Ученик показывает тебе домашку в игровом мире.
Задание «${title}»: ${task}
${autoPassed ? "Автопроверка игры: код работает и выполняет задание." : "Автопроверки нет — реши сам, выполнено ли задание."}
Код ученика:
\`\`\`lua
${String(code).slice(0, 4000)}
\`\`\`
Ответь от лица Профессора Клода 2–4 короткими предложениями без блоков кода: похвали что-то конкретное в этом коде и дай один совет, как сделать ещё лучше.
${autoPassed ? "" : "Последней отдельной строкой напиши ровно VERDICT: PASS (задание выполнено, пусть и не идеально) или VERDICT: FAIL (задание не выполнено или в коде явная ошибка — тогда объясни, что исправить)."}`;
    const res = await Claude.sample(prompt, { modelTier: autoPassed ? "quick" : "default", cache: false });
    let text = res.text.trim();
    const m = text.match(/VERDICT:\s*(PASS|FAIL)/i);
    const pass = autoPassed || (m ? m[1].toUpperCase() === "PASS" : true);
    text = text.replace(/VERDICT:\s*(PASS|FAIL)/gi, "").trim();
    return { text, pass };
  } catch (e) {
    if (e && (e.code === "not_granted" || e.code === "sampling_disabled")) {
      Claude.disabled = "Живой Клод выключен: доступ к Claude не разрешён.";
    }
    return null;
  } finally {
    dlgThinking(null);
  }
}

// ---------- офлайн-Клод: простые команды без интернета ----------
// слово, которое начинается с одной из основ (у кириллицы нет \b, поэтому границы делаем сами)
const offW = (stems) => new RegExp("(?<![а-яa-z0-9_])(?:" + stems + ")", "i");
// просьбы: «сделай», «включи», «дай», «хочу»…
const OFF_ASK = offW("сдела|включ|выключ|отключ|дай|дайт|хочу|надень|наден|одень|сним|убер|убра|верн|вылеч|полеч|подлеч|созда|вызов|позов|начн|давай|постав|покрас|перекрас|увелич|уменьш|ускор|замедл|пусть|стань|преврат|запуст|устрой|сбрось|можешь|сможешь|пожалуйста|добав|восстанов|измени|поменя");
const OFF_OFF = offW("выключ|отключ|убер|убра|сним|без(?![а-я])|не надо|хватит");
const OFF_TOPICS = [
  [/print|вывод|напечат|принт/, "l1"],
  [/перемен|local|(?<![а-яa-z])(hp|хп)(?![а-яa-z])|отн(ять|ими|имать)|вычест|вычит|прибав/, "l2"],
  [/random|случайн|числ|математ|умнож|делени|раздел|кубик|посчита/, "l3"],
  [/(?<![a-z])(if|else|elseif)(?![a-z])|услов|если|сравн|больше|меньше|равно|[<>~=]=/, "l4"],
  [/цикл|(?<![a-z])(for|while)(?![a-z])|повтор|wait|пауз/, "l5"],
  [/функц|function|return/, "l6"],
  [/таблиц|список|массив|ipairs|инвентар/, "l7"],
  [/part|детал|instance|vector|color|цвет|anchored/, "l8"],
  [/событ|touched|click|connect|касан|кнопк|клик/, "l9"],
  [/leaderstats|монет|лидер|coins|playeradded/, "l10"],
];

// шпаргалка урока текстом для чата: без HTML, код — в блоках ```lua
function lessonText(L) {
  const unesc = (t) => t.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  const text = L.card
    .replace(/<pre>([\s\S]*?)<\/pre>/g, (_, c) => "\n```lua\n" + unesc(c) + "\n```\n")
    .split(/(```lua\n[\s\S]*?\n```)/)
    .map((p, i) => (i % 2 ? p : unesc(p.replace(/<code>([\s\S]*?)<\/code>/g, "`$1`").replace(/<b>([\s\S]*?)<\/b>/g, "**$1**").replace(/\s*<li>/g, "\n• ").replace(/<p>/g, "\n\n").replace(/<[^>]+>/g, "").replace(/[ \t]*\n[ \t]*/g, "\n"))))
    .join("")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return `Урок ${L.n} «${L.title}», коротко:\n\n${text}`;
}

// урок, про который сейчас речь: открытый в редакторе, следующий непройденный или урок текущей домашки
function currentLesson() {
  const s = G.save;
  if (!document.getElementById("editor").hidden && Editor.key) {
    const T = taskFor(Editor.key);
    if (T.lesson) return T.lesson;
  }
  const next = LESSONS.find((L) => !s.practice[L.id] && (L.id === "l1" || s.flags["arrived_" + L.zone]));
  if (next) return next;
  const hid = pendingHw();
  if (hid) return HOMEWORK[hid].lesson;
  return LESSONS.filter((L) => s.practice[L.id]).pop() || LESSONS[0];
}

// подсказка: текст — как есть, код (строчки латиницей) — блоком
function hintText(h) {
  const lines = String(h).split("\n");
  const i = lines.findIndex((l) => /^[\x20-\x7e]/.test(l));
  if (i < 0) return h;
  return (i ? lines.slice(0, i).join("\n") + "\n" : "") + "```lua\n" + lines.slice(i).join("\n") + "\n```";
}

// офлайн: рассказать про домашку
function offlineHw(m) {
  const s = G.save;
  syncHomework();
  const ids = Object.keys(HOMEWORK);
  const num = m.match(/(?:№|номер)\s*(\d+)|(?<![0-9a-z])(\d+)(?![0-9])/);
  let named = num ? ids.find((h) => HOMEWORK[h].lesson.n === +(num[1] || num[2])) : null;
  if (!named) named = ids.find((h) => m.includes(HOMEWORK[h].title.toLowerCase().replace(/ё/g, "е").slice(0, 5)));
  const help = offW("помог|помощ|подскаж|не понима|не получа|не могу|застрял").test(m);
  const how = "Как сдать: нажми </> — домашка откроется сама. Напиши код → ✓ Проверить → закрой чат и нажми «📜 Сдать домашку» (или подойди ко мне в мире).";
  const about = (h) => {
    const H = HOMEWORK[h];
    let t = `Домашка №${H.lesson.n} «${H.title}»: ${H.task}`;
    if (help && H.hint) t += "\n\nПодсказка:\n" + hintText(H.hint);
    return t;
  };
  let pre = "";
  if (offW("нов|ещ[её] домашк|друг(ую|ая) домашк").test(m) && !named) pre = "Новые домашки придумывает живой Клод — он включается, когда игра открыта по ссылке в Claude. ";
  if (named) {
    const st = s.hw[named];
    const H = HOMEWORK[named];
    if (st === "given") return `${about(named)}\n\n${how}`;
    if (st === "checked") return `Домашка №${H.lesson.n} «${H.title}» уже проверена ✅ Закрой чат и нажми «📜 Сдать домашку».`;
    if (st === "done") pre = `Домашку №${H.lesson.n} ты уже сдал ⭐ `;
    else pre = `Домашка №${H.lesson.n} «${H.title}» будет позже — после урока ${H.lesson.n} «${H.lesson.title}». `;
  }
  const hid = pendingHw();
  if (hid && s.hw[hid] === "checked") return `${pre}Домашка №${HOMEWORK[hid].lesson.n} уже проверена ✅ Закрой чат и нажми «📜 Сдать домашку».`;
  if (hid) return `${pre}${pre ? "А пока сделай эту. " : ""}${about(hid)}\n\n${how}`;
  const custom = (s.customHw || []).find((h) => h.status !== "done");
  if (custom) return `${pre}Особое задание «${custom.title}»: ${custom.task}\n\nОткрой его в редакторе </>, напиши код и нажми «Готово».`;
  return `${pre}Сейчас домашек нет — все сданы! Что дальше: ${objective()}.`;
}

// офлайн: команды, которые меняют игру; каждую часть фразы («включи снег и надень корону») разбираем отдельно
function offlineCommands(m) {
  const s = G.save;
  const r = s.rules;
  const done = [];
  const set = (k, v, t) => { r[k] = v; done.push(t); };
  const short = m.split(/\s+/).filter(Boolean).length <= 2;
  let fight = false;
  for (const c of m.split(/\s+и\s+|[,;.!]+/).map((x) => x.trim()).filter(Boolean)) {
    const off = OFF_OFF.test(c);
    if (offW("сброс|сбрось").test(c) || /как было|обычные правила/.test(c)) { Object.assign(r, RULE_DEFAULTS); done.push("вернул обычные правила"); }
    const times = c.match(/в\s*(\d)\s*раз/);
    if (offW("медлен|помедлен|замедл").test(c)) set("speed", Math.max(0.3, times ? (r.speed || 1) / +times[1] : (r.speed || 1) - 0.4), "замедлил тебя");
    else if (offW("(по)?быстре|(по)?быстрей|ускор|быстр(ым|ой|ая)(?![а-я])").test(c)) set("speed", Math.min(5, times ? (r.speed || 1) * +times[1] : (r.speed || 1) + 0.75), "ускорил тебя");
    if (offW("бессмерт|неуязвим|god").test(c)) set("godMode", !off, off ? "выключил бессмертие" : "включил бессмертие (жульничество, но ладно)");
    for (const [re, w, name] of [["снег|снеж", "snow", "снег"], ["дожд|ливен|ливн", "rain", "дождь"], ["конфетт|праздник", "confetti", "конфетти"]]) {
      if (offW(re).test(c)) set("weather", off ? "none" : w, (off ? "выключил " : "включил ") + name);
    }
    if (off && offW("погод").test(c)) set("weather", "none", "убрал погоду");
    if (offW("ночь|ночн|темн|стемн").test(c)) set("night", !off, off ? "включил день" : "выключил солнце");
    else if (offW("(день|днем|утро|светло|светлее)(?![а-я])").test(c)) set("night", off, off ? "выключил солнце" : "включил день");
    let hat = false;
    for (const [re, h, name] of [["корон", "crown", "корону"], ["кепк", "cap", "кепку"], ["волшеб|колпак|маг(а|ом)?(?![а-я])", "wizard", "шляпу волшебника"], ["рог(а|и)?(?![а-я])", "horns", "рога"], ["цилиндр", "tophat", "цилиндр"], ["антенн", "antenna", "антенну"]]) {
      if (!offW(re).test(c)) continue;
      hat = true;
      if (off) set("hat", "none", "снял " + name);
      else set("hat", h, "надел на тебя " + name);
    }
    if (!hat && off && offW("шляп|шапк").test(c)) set("hat", "none", "снял шляпу");
    if (offW("гигант|огромн|великан|увелич|вырасти|больш(им|ой|ая|ого)(?![а-я])").test(c)) set("playerSize", 1.6, "увеличил тебя");
    else if (offW("маленьк|крошечн|уменьш|мелк(им|ий|ой)(?![а-я])").test(c)) set("playerSize", 0.6, "уменьшил тебя");
    // цвет одежды — только когда про игрока, а не про деталь
    const forMe = offW("покрас|перекрас|цвет|одежд|футболк|кофт").test(c) || offW("(меня|себя)(?![а-я])").test(c);
    if (forMe && !offW("детал|part|кубик|блок|кнопк|лав|монет|мир").test(c)) {
      for (const [re, hex] of [["красн", "#e0425a"], ["син(ий|ей|его|им|юю|яя|ее|ь)?(?![а-я])|голуб", "#3a6ef0"], ["зелен", "#3ac25a"], ["желт", "#f2c43a"], ["фиолет", "#8a3ad6"], ["розов", "#ff7ac0"], ["черн", "#2a2a33"], ["бел(ый|ым|ой|ую|ая|ого)(?![а-я])", "#f2f2f2"], ["оранж", "#ff8a3a"]]) {
        if (offW(re).test(c)) { set("playerColor", hex, "перекрасил одежду"); break; }
      }
    }
    if (offW("вылеч|полеч|подлеч|лечи|исцел").test(c) || /(дай|верни|восстанови|добавь|полн\S*)\s+(мне\s+)?(хп|hp|здоровь|жизн)/.test(c)) { s.hp = playerMaxHp(); done.push("вылечил тебя"); }
    const foes = offW("враг|монстр|жук|баг").test(c);
    if (offW("(по)?легче|(по)?проще").test(c) || (foes && offW("слаб").test(c))) set("enemyDamage", 0.5, "ослабил врагов");
    else if (offW("(по)?сложнее|(по)?труднее|хардкор").test(c) || (foes && offW("сильн").test(c))) set("enemyDamage", 2, "усилил врагов");
    else if (offW("сильнее|сильней").test(c)) set("attackBonus", (r.attackBonus || 0) + 5, "сделал тебя сильнее");
    if (foes && off) set("encounters", false, "убрал жуков из миров");
    // бой — только по ясной просьбе: «босс», «создай босса», «давай драться»
    const wantFight = offW("босс|битв|сраж|драк|подрат|подерем|деремся|бо[йя](?![а-я])").test(c) || (foes && OFF_ASK.test(c));
    if (wantFight && !off && !fight && (short || OFF_ASK.test(c))) {
      fight = true;
      G.pendingBattle = customEnemy({ name: "Офлайн-Глюк", look: "slime", color: "#ff5aa0", hp: 30, attack: 4, patterns: ["rain", "ring", "code"] });
      done.push("вызвал врага — бой начнётся, когда закроешь чат");
    }
  }
  return done;
}

function offlineReply(msg, ctx) {
  const raw = String(msg || "");
  const m = raw.toLowerCase().replace(/ё/g, "е").trim();
  const words = m.split(/\s+/).filter(Boolean).length;
  // вопрос или код — сначала ищем ответ в уроках, игру не трогаем
  const question = raw.includes("?") || /^((а|и|ну)\s+)?(как|почему|что|зачем|где|когда|сколько|какой|какая|какое|какие|каким|чем|кто|откуда|куда|чего)(?![а-я])/.test(m);
  const polite = /^((а|ну)\s+)?(ты\s+)?(можешь|сможешь|можно(?!\s+ли)|пожалуйста)(?![а-я])/.test(m);
  const code = /```|[a-z_][\w.:]*\s*\(|[a-z_\]]\s*(==|~=|\+=|-=|=)\s*\S|(?<![a-z])(local|function|then|elseif|end|return)(?![a-z])/i.test(raw);
  const topic = () => {
    for (const [re, id] of OFF_TOPICS) if (re.test(m)) return lessonText(LESSON[id]);
    return null;
  };
  // из редактора: «Почему ошибка?» / «Помоги с заданием»
  if (ctx && offW("ошибк|помог|помощ|не понима|не получа|не могу|подскаж|застрял").test(m)) {
    const T = Editor.key ? taskFor(Editor.key) : null;
    let t = offW("ошибк").test(m) ? "Смотри в ошибку: там номер строки и подсказка. Чаще всего забывают кавычки, end, then или do, пишут Print с большой буквы или путают = и ==.\n\n" : "";
    t += `Задание: ${ctx.task || (T && T.task) || "песочница"}`;
    if (T && T.hint) t += "\n\nПодсказка:\n" + hintText(T.hint);
    return t;
  }
  if (offW("дальше").test(m) || /что (мне |теперь )?делать|куда (мне )?идти/.test(m)) return `Что дальше: ${objective()}.`;
  if (offW("домашк|домашн|дз(?![а-я])").test(m)) return offlineHw(m);
  if ((!question || polite) && !code && (polite || words <= 3 || OFF_ASK.test(m))) {
    const done = offlineCommands(m);
    if (done.length) {
      applyRules();
      updateHud();
      saveSoon();
      return "Готово: " + done.join(", ") + "! (Это офлайн-режим: я понимаю только простые команды. Полный мозг включается, когда игра открыта через Claude.)";
    }
  }
  const t = topic();
  if (t) return t;
  if (offW("урок|объясн|пример|шпаргалк|не понима|не понял").test(m)) return lessonText(currentLesson());
  if (code) return "Вижу код! Открой редактор </>, вставь его и нажми ▶ Запуск — посмотрим, что выйдет. Если будет ошибка, нажми «Почему ошибка?».";
  if (offW("спасиб|благодар").test(m)) return "Всегда пожалуйста, стажёр! Если что — я тут.";
  if (offW("привет|здравств|хай(?![а-я])|хелло|салют").test(m)) return "Привет, стажёр! Спроси про урок, напиши «что дальше» или дай команду: «снег», «корона», «быстрее».";
  return "Мой мозг сейчас не подключён к Claude, поэтому я понимаю только простые команды: «быстрее», «медленнее», «бессмертие», «снег», «дождь», «ночь», «корона», «вылечи», «босс», «сброс». Ещё могу: «что дальше», «домашка», «объясни урок» и вопросы про темы уроков (переменные, циклы, if, функции, Part, события). Чтобы говорить со мной по-настоящему, открой игру по ссылке в Claude.";
}

function setupChat() {
  document.getElementById("chatClose").onclick = closeChat;
  document.getElementById("chatSend").onclick = sendChat;
  document.getElementById("chatStop").onclick = () => Claude.ctl && Claude.ctl.abort();
  const inp = document.getElementById("chatInput");
  inp.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); sendChat(); }
  });
  // клавиатура телефона: следим за фокусом и размером экрана
  inp.addEventListener("focus", () => { fitChat(); setTimeout(fitChat, 300); });
  inp.addEventListener("blur", () => setTimeout(fitChat, 100));
  window.addEventListener("resize", fitChat);
  if (window.visualViewport) window.visualViewport.addEventListener("resize", fitChat);
  document.getElementById("chatChips").addEventListener("click", (e) => {
    const b = e.target.closest("button");
    if (!b) return;
    if (b.id === "chatHwChip") { handInHomework(); return; }
    inp.value = b.dataset.say || b.textContent;
    sendChat();
  });
  document.getElementById("chatLog").addEventListener("click", (e) => {
    const b = e.target.closest(".tocode");
    if (!b) return;
    G.save.code.sandbox = decodeURIComponent(b.dataset.code);
    saveSoon();
    inp.blur();
    document.getElementById("chat").hidden = true;
    fitChat();
    G.overlay = null;
    openEditor("sandbox");
  });
  const modeBtn = document.getElementById("chatMode");
  const paint = () => { modeBtn.textContent = G.save && G.save.settings.smart ? "🧠 Умный" : "⚡ Быстрый"; };
  modeBtn.onclick = () => { if (!G.save) return; G.save.settings.smart = !G.save.settings.smart; paint(); saveSoon(); toast(G.save.settings.smart ? "Умный режим: дольше думает, лучше объясняет" : "Быстрый режим: отвечает сразу"); };
  paint();
  Claude.paintMode = paint;
  drawClaude(document.getElementById("chatAva").getContext("2d"), 0, 0, "down", 0.3);
}
