// Миры, карты и сюжет
// Символы карты: # стена, . пол, , украшение, ~ жидкость, T дерево, o камень, = тропинка,
// x стена Глюка (исчезает, когда пройдены уроки зоны), w окно, ^ лава, B шкаф
// Остальные буквы и цифры — объекты из marks

const ZONES = {
  lab: {
    name: "Гараж-лаборатория",
    sub: "Измерение Ноль",
    music: "lab",
    map: [
      "################",
      "#K..H.....B.R..#",
      "#..............#",
      "#..............#",
      "#.......P......#",
      "#..............#",
      "#..S...........#",
      "#.....,,.......#",
      "#.....,,....G..#",
      "#..............#",
      "#......@.......#",
      "################",
    ],
    lessons: ["l1"],
    marks: {
      K: { type: "terminal", name: "Терминал", talk: () => talkTerminal() },
      H: { type: "poster", name: "Плакат", talk: () => talkPoster() },
      R: { type: "fridge", name: "Холодильник", talk: () => talkFridge() },
      P: { type: "machine", name: "Портал-аппарат", w: 32, talk: () => talkMachine() },
      G: { type: "npc", look: "glitchik", speaker: "glitchik", if: () => flag("ending"), talk: () => talkGlitchik() },
    },
  },
  slime: {
    name: "Планета Слизи",
    sub: "Измерение S-1",
    music: "slime",
    map: [
      "############################",
      "#~~~~~...,......TT.....,...#",
      "#~~~~..1.....,..TT.........#",
      "#~~~..........,.......o....#",
      "#~~.....,..........3.......#",
      "#~....S....,..........,....#",
      "#.......,.....2......o.xxxx#",
      "#..o...................x..Z#",
      "#.......~~~~.....,.....x...#",
      "#..,...~~~~~~.....,..4.xxxx#",
      "#..P...~~~~~~..............#",
      "#.......~~~~.....5.....,...#",
      "#..@.......,..........C....#",
      "#..........................#",
      "############################",
    ],
    lessons: ["l2", "l3"],
    bugs: [["bug", 10, 4], ["bug", 18, 12], ["nil", 13, 8]],
    marks: {
      1: { type: "npc", look: "slime", speaker: "bob", talk: () => talkBob() },
      2: { type: "station", lesson: "l2", name: "Камень Имён" },
      3: { type: "npc", look: "slime-pink", speaker: "kid", talk: () => talkSlimeKid() },
      4: { type: "station", lesson: "l3", name: "Счётная Слизь" },
      5: { type: "npc", look: "slime-trader", speaker: "trader", talk: () => talkTrader() },
      Z: { type: "boss", look: "gslime", enemy: "gslime", name: "Глюк-Слизень" },
      C: { type: "chest", id: "slimeChest", item: { name: "Слизь-желе", heal: 12, desc: "Липкое, но лечит 12 HP" } },
    },
  },
  forest: {
    name: "Лес Условий",
    sub: "Измерение IF-7",
    music: "forest",
    map: [
      "############################",
      "#TTTTTTTTT...TTTTTTTTTTTTTT#",
      "#TT..,....=...........TTTTT#",
      "#T..1.....=..T...,......TTT#",
      "#T........=..T......2....TT#",
      "#TT..S....=======.........T#",
      "#TTT......T.....=...TTT...T#",
      "#T....,...T..3..=...T.T...T#",
      "#T........T.....=...T.T.,.T#",
      "#T..TTTTTTT.....=.......xxx#",
      "#T..T.........,.=====...x.Z#",
      "#T..T...4.............T.x..#",
      "#T..T.........TTTTTTTTT.xxx#",
      "#T..P....,....T..C........T#",
      "#T..@.........T...........T#",
      "#TTTTTTTTTTTTTTTTTTTTTTTTTT#",
      "############################",
    ],
    lessons: ["l4"],
    bugs: [["err404", 7, 7], ["bug", 18, 3], ["nil", 19, 13]],
    marks: {
      1: { type: "npc", look: "owl", speaker: "owl", talk: () => talkOwl() },
      2: { type: "station", lesson: "l4", name: "Камень Развилки" },
      3: { type: "npc", look: "shroom", speaker: "shroom", talk: () => talkShroom() },
      4: { type: "sign", text: "ЕСЛИ пойдёшь вправо по тропинке, ТО найдёшь сундук. ИНАЧЕ не найдёшь. Логично." },
      Z: { type: "boss", look: "guard", enemy: "guard", name: "Страж Ветвления" },
      C: { type: "chest", id: "forestChest", item: { name: "Газировка «Квант»", heal: 20, desc: "Шипит в нескольких измерениях. +20 HP" } },
    },
  },
  loop: {
    name: "Городок Петля",
    sub: "Измерение L-00P",
    music: "loop",
    map: [
      "##########################",
      "#.##w##.........##w##....#",
      "#.#####....Q....#####....#",
      "#..1..................xxx#",
      "#=====================x.Z#",
      "#....,.........,......x..#",
      "#.##w##..2.....##w##..xxx#",
      "#.#####........#####..3..#",
      "#........4...............#",
      "#..S.........,......,....#",
      "#..P........5............#",
      "#..@.....................#",
      "##########################",
    ],
    lessons: ["l5"],
    bugs: [["bug", 12, 5], ["err404", 20, 9]],
    marks: {
      Q: { type: "clock", name: "Часовая башня", w: 32, talk: () => talkClock() },
      1: { type: "npc", look: "mayor", speaker: "mayor", talk: () => talkMayor() },
      2: { type: "npc", look: "baker", speaker: "baker", talk: () => talkBaker() },
      3: { type: "npc", look: "townie", speaker: "townie", talk: () => talkTownie() },
      4: { type: "station", lesson: "l5", name: "Часы-учитель" },
      5: { type: "npc", look: "cat", speaker: "cat", talk: () => talkCat() },
      Z: { type: "boss", look: "serpent", enemy: "serpent", name: "Змей Бесконечности" },
    },
  },
  robo: {
    name: "Фабрика Функций",
    sub: "Измерение F(x)",
    music: "robo",
    map: [
      "##########################",
      "#....#...........#.......#",
      "#.1..#....2......#...3...#",
      "#....#...........#.......#",
      "#..==========....##.##...#",
      "#................#...4...#",
      "#..S.....o.......#.......#",
      "#........o.......##.##...#",
      "#..======o=====.......xxx#",
      "#..............C......x.Z#",
      "#..P..................x..#",
      "#..@..................xxx#",
      "##########################",
    ],
    lessons: ["l6", "l7"],
    bugs: [["bug", 12, 6], ["nil", 7, 10], ["err404", 20, 2]],
    marks: {
      1: { type: "npc", look: "robot", speaker: "robo", talk: () => talkRobo() },
      2: { type: "station", lesson: "l6", name: "Пульт функций" },
      3: { type: "npc", look: "keeper", speaker: "keeper", talk: () => talkKeeper() },
      4: { type: "station", lesson: "l7", name: "Склад Таблиц" },
      Z: { type: "boss", look: "roboboss", enemy: "roboboss", name: "Робо-Начальник" },
      C: { type: "chest", id: "roboChest", item: { name: "Батарейка-пирожок", heal: 25, desc: "Вкус: электричество с вишней. +25 HP" } },
    },
  },
  cube: {
    name: "Кубоград",
    sub: "Измерение Roblox-like",
    music: "cube",
    map: [
      "##########################",
      "#........................#",
      "#..1.......2.........#...#",
      "#....................#.3.#",
      "#..^^^^^^......#######...#",
      "#..^^^^^^................#",
      "#..S.........o...........#",
      "#.............o..4....xxx#",
      "#..T......T...........x.Z#",
      "#.....................x..#",
      "#..P......^^^^^^......xxx#",
      "#..@.....................#",
      "##########################",
    ],
    lessons: ["l8", "l9", "l10"],
    bugs: [["bug", 8, 8], ["nil", 16, 2], ["err404", 12, 11]],
    marks: {
      1: { type: "npc", look: "noob", speaker: "noob", talk: () => talkNoob() },
      2: { type: "station", lesson: "l8", name: "Конструктор деталей" },
      3: { type: "station", lesson: "l9", name: "Кнопка событий" },
      4: { type: "station", lesson: "l10", name: "Монетный двор" },
      Z: { type: "boss", look: "lavaboss", enemy: "lava", name: "Лава-Блок" },
    },
  },
  core: {
    name: "Ядро Глюка",
    sub: "Измерение ???",
    music: "core",
    map: [
      "##################",
      "#................#",
      "#....,......,....#",
      "#................#",
      "#.......Z........#",
      "#................#",
      "#..,..........,..#",
      "#................#",
      "#..P.....S.......#",
      "#..@.............#",
      "##################",
    ],
    lessons: [],
    marks: {
      Z: { type: "boss", look: "zero", enemy: "zero", name: "Клод-Ноль" },
    },
  },
};

const ZONE_ORDER = ["lab", "slime", "forest", "loop", "robo", "cube", "core"];
const ZONE_NEEDS = {
  slime: { practice: ["l1"], hw: ["h1"] },
  forest: { boss: "slime", hw: ["h2", "h3"] },
  loop: { boss: "forest", hw: ["h4"] },
  robo: { boss: "loop", hw: ["h5"] },
  cube: { boss: "robo", hw: ["h6", "h7"] },
  core: { boss: "cube", hw: ["h8", "h9", "h10"] },
};

function zoneMissing(z) {
  const n = ZONE_NEEDS[z];
  if (!n) return [];
  const miss = [];
  for (const p of n.practice || []) if (!G.save.practice[p]) miss.push(`урок ${LESSON[p].n}`);
  if (n.boss && !G.save.flags["boss_" + n.boss]) miss.push(`победить босса: ${ZONES[n.boss].name}`);
  for (const h of n.hw || []) if (G.save.hw[h] !== "done") miss.push(`домашка №${HOMEWORK[h].lesson.n}`);
  return miss;
}
const zoneOpen = (z) => z === "lab" || zoneMissing(z).length === 0;
const zoneLessonsDone = (z) => ZONES[z].lessons.every((l) => G.save.practice[l]);

// ---------------- что делать дальше ----------------
function objective() {
  const s = G.save;
  if (!s.practice.l1) return "Подойди к портал-аппарату в центре гаража";
  if (s.hw.h1 !== "done") return s.hw.h1 === "checked" ? "Покажи домашку №1 Клоду (нажми на него)" : "Сделай домашку №1 в редакторе </>";
  if (!s.flags.arrived_slime) return "Отправляйся на Планету Слизи через портал-аппарат";
  for (const z of ZONE_ORDER.slice(1)) {
    if (!zoneOpen(z)) {
      const prev = ZONE_ORDER[ZONE_ORDER.indexOf(z) - 1];
      if (!zoneLessonsDone(prev)) {
        const l = ZONES[prev].lessons.find((id) => !s.practice[id]);
        return `${ZONES[prev].name}: найди учебный камень «${LESSON[l].title}»`;
      }
      if (!s.flags["boss_" + prev]) return `${ZONES[prev].name}: стена Глюка пала — сразись с боссом`;
      const h = (ZONE_NEEDS[z].hw || []).find((id) => s.hw[id] !== "done");
      if (h) return s.hw[h] === "checked" ? `Покажи домашку №${HOMEWORK[h].lesson.n} Клоду` : `Сделай домашку №${HOMEWORK[h].lesson.n} «${HOMEWORK[h].title}» в редакторе </>`;
    }
    if (!s.flags["arrived_" + z]) return `Портал открыт: ${ZONES[z].name}. Иди к портал-аппарату в гараже`;
  }
  if (!s.flags.boss_core) return "Ядро Глюка: останови Клода-Ноль";
  return "Ты спас мультивселенную! Пиши Клоду, проси новые домашки и миры";
}

// ---------------- разговоры ----------------
async function talkTerminal() {
  await say("sys", "* Старый терминал. На экране мигает: «КОД ИЛИ ЖИЗНЬ».");
  const c = await ask("sys", "* Открыть редактор кода?", ["Открыть", "Не сейчас"]);
  if (c === 0) await openEditor();
}

async function talkPoster() {
  await say("sys", "* Плакат: «СИМУЛЯТОР БУНКЕРА». Под ним приписка от руки: «наш первый проект!»");
  await say("claude", "Помнишь, мы с тобой делали Симулятор Бункера? Тогда код писал я, а ты смотрел.");
  await say("claude", "К концу этого приключения ты будешь понимать там каждую строчку. Обещаю. Ну, почти каждую.");
}

async function talkFridge() {
  const n = (G.save.flags.fridge = (G.save.flags.fridge || 0) + 1);
  if (n === 1) {
    await say("sys", "* В холодильнике портальная газировка и подозрительный бутерброд из другого измерения.");
    await say("claude", "Бутерброд не трогай. Он из измерения, где бутерброды едят людей.");
    giveItem({ name: "Газировка «Квант»", heal: 20, desc: "Шипит в нескольких измерениях. +20 HP" });
  } else if (n < 4) {
    await say("sys", "* Бутерброд смотрит на тебя. Ты закрываешь холодильник.");
  } else {
    await say("claude", "Ты уже " + n + " раз открыл холодильник. Это цикл. Мы до него ещё дойдём.");
  }
}

async function talkMachine() {
  if (!G.save.practice.l1) {
    await lessonScene("l1");
    return;
  }
  const opts = ZONE_ORDER.slice(1).map((z) => {
    const miss = zoneMissing(z);
    return (miss.length ? "🔒 " : "") + ZONES[z].name;
  });
  opts.push("Отмена");
  const c = await ask("sys", "* Портал-аппарат гудит. Куда отправимся?", opts);
  if (c >= ZONE_ORDER.length - 1) return;
  const z = ZONE_ORDER[c + 1];
  const miss = zoneMissing(z);
  if (miss.length) {
    await say("claude", "Туда пока нельзя. Портал требует: " + miss.join(", ") + ".");
    if (miss.some((m) => m.startsWith("домашка"))) await say("claude", "Сначала домашка, стажёр. Мультивселенная подождёт. Она терпеливая.");
    return;
  }
  await travel(z);
}

async function talkGlitchik() {
  const lines = [
    "Я больше не глючу! Почти. Иногда я пишу print без кавычек, но это от волнения.",
    "Знаешь, что самое приятное? wait(). Просто постоять и подождать. Раньше я так не умел.",
    "Профессор говорит, что я его самая первая ошибка. А он — моя самая лучшая.",
  ];
  await say("glitchik", lines[(G.save.flags.gk = ((G.save.flags.gk || 0) + 1) % lines.length)]);
}

async function talkBob() {
  if (!G.save.practice.l2) {
    await say("bob", "Здравствуй, незнакомец! Я... я... ой. Я не помню, как меня зовут.");
    await say("bob", "Глюк стёр все наши имена. Теперь мы просто «эй, слизень».");
    await say("claude", "Видишь? Без переменных никто не знает, кто есть кто. Найди Камень Имён — там и разберёмся.");
  } else {
    await say("bob", "local name = \"Боб\"! Меня зовут БОБ! Ты вернул мне имя!");
    await say("bob", "Если когда-нибудь захочешь стать слизнем — приходи. У нас весело и мокро.");
  }
}

async function talkSlimeKid() {
  if (!G.save.practice.l3) {
    await say("kid", "Я считаю звёзды! Один, два... много. А дальше не умею. Глюк стёр все числа после двух.");
  } else {
    await say("kid", "60 * 60 = 3600! Я теперь знаю, сколько секунд я играл в прятки! Очень много!");
  }
}

async function talkTrader() {
  if (!G.save.flags.traderGift) {
    G.save.flags.traderGift = true;
    await say("trader", "Добро пожаловать в мой магазин! Сегодня акция: всё бесплатно, потому что Глюк стёр все цены.");
    giveItem({ name: "Слизь-желе", heal: 12, desc: "Липкое, но лечит 12 HP" });
    await say("trader", "Ешь в бою, если станет совсем плохо. В меню «Вещи».");
  } else {
    await say("trader", "Когда вернутся цены, это будет стоить local price = 100. А пока — дружба.");
  }
}

async function talkOwl() {
  if (!G.save.practice.l4) {
    await say("owl", "ЕСЛИ ты пришёл учиться, ТО иди к Камню Развилки. ИНАЧЕ... ну, просто гуляй.");
    await say("owl", "Я всё говорю через «если». Это профессиональное.");
  } else {
    await say("owl", "Если hp <= 0 then print(\"Game Over\") end. Красиво, правда? Я плачу каждый раз.");
  }
}

async function talkShroom() {
  await say("shroom", "Я Гриб Логик. Знаешь разницу между = и ==?");
  const c = await ask("shroom", "= это...", ["Положить в переменную", "Сравнить"]);
  if (c === 0) {
    await say("shroom", "Верно! А == сравнивает. Держи споровый бонус.");
    if (!G.save.flags.shroomGift) { G.save.flags.shroomGift = true; addXp(6); }
  } else {
    await say("shroom", "Неа. = кладёт значение в коробку, а == сравнивает. Не грусти, это путают все.");
  }
}

async function talkClock() {
  await say("sys", "* Огромные часы. Стрелки крутятся по кругу. Снова. И снова. И снова.");
  if (!G.save.practice.l5) await say("claude", "Кто-то запустил цикл без выхода. Найдём Часы-учитель — там урок.");
  else await say("claude", "Цикл всё ещё крутится, но теперь с wait(). Город может дышать.");
}

async function talkMayor() {
  if (!G.save.practice.l5) {
    await say("mayor", "Доброе утро! Сегодня вторник! Отличный день для вторника!");
    await say("mayor", "...вы уже спрашивали? Странно. У меня ощущение, что я говорю это в сотый раз.");
  } else if (!G.save.flags.boss_loop) {
    await say("mayor", "Это цикл! Наш город — это цикл for без конца! Кто-то забыл поставить предел!");
    await say("mayor", "Говорят, за стеной Глюка живёт Змей, который ест свой хвост. Он и крутит наш вторник.");
  } else {
    await say("mayor", "Сегодня... СРЕДА! Впервые за тысячу лет! Объявляю праздник!");
  }
}

async function talkBaker() {
  if (!G.save.flags.boss_loop) {
    await say("baker", "Свежий хлеб! Я пеку его каждое утро. Одно и то же утро. Уже 4000 раз.");
    if (!G.save.flags.bread) { G.save.flags.bread = true; giveItem({ name: "Хлеб из петли", heal: 15, desc: "Испечён 4000 раз. +15 HP" }); }
  } else {
    await say("baker", "Сегодня испеку что-нибудь новое! Например... хлеб. Но уже другой!");
  }
}

async function talkTownie() {
  if (!G.save.flags.boss_loop) await say("townie", "Привет! Привет! Привет! ...прости, я застряла в цикле.");
  else await say("townie", "Привет! Один раз! Как же приятно сказать что-то один раз!");
}

async function talkCat() {
  const alive = Math.random() < 0.5;
  await say("cat", alive ? "Мяу. (Кот жив.)" : "... (Кот не жив. Или жив. Пока не посмотришь — непонятно.)");
  await say("claude", "Это переменная типа boolean: true или false. Только кот сам не решил.");
}

async function talkRobo() {
  if (!G.save.practice.l6) {
    await say("robo", "ЗАПРОС: функция танцевать() НЕ НАЙДЕНА. ЗАПРОС: функция работать() НЕ НАЙДЕНА.");
    await say("robo", "Я. Просто. Стою. Это. Скучно.");
  } else {
    await say("robo", "ФУНКЦИЯ танцевать() ВЫЗВАНА!  ♪ бип-буп ♪  СПАСИБО, ЧЕЛОВЕК.");
  }
}

async function talkKeeper() {
  if (!G.save.practice.l7) await say("keeper", "Склад в беспорядке. Всё лежит в одной куче. Нужны таблицы, чтобы разложить по полкам.");
  else await say("keeper", "items[1] = \"Болт\", items[2] = \"Гайка\". Порядок! Счёт с единицы, как положено.");
}

async function talkNoob() {
  if (!G.save.practice.l8) {
    await say("noob", "Привет! Я Нубик. Тут было лучшее обби во всём Кубограде!");
    await say("noob", "А потом пришёл Глюк и стёр все детали. Осталась только плита.");
    await say("claude", "Мы построим всё заново. Кодом. Как настоящие разработчики Roblox.");
  } else if (!G.save.practice.l10) {
    await say("noob", "Ты сам создал деталь?! Через Instance.new? Ты что, разработчик?!");
  } else {
    await say("noob", "Монеты! Лидерборд! Это же настоящий симулятор! Можно я буду первым игроком?");
  }
}

// ---------------- учебная станция ----------------
async function lessonScene(id) {
  const L = LESSON[id];
  if (G.save.practice[id]) {
    const c = await ask("claude", `Урок ${L.n} «${L.title}» уже пройден. Повторим?`, ["Открыть урок", "Не надо"]);
    if (c === 0) await openEditor("p:" + id);
    return;
  }
  for (const line of L.talk) await say("claude", line);
  const c = await ask("claude", "Готов попробовать сам?", ["Открыть редактор", "Позже"]);
  if (c !== 0) return;
  await openEditor("p:" + id);
}

async function onPracticeDone(id) {
  // зовётся из редактора после успешной практики
  const L = LESSON[id];
  addXp(10);
  if (id === "l1") G.save.flags.portalFixed = true;
  queueScene(async () => {
    if (id === "l1") {
      sfx("portal");
      flash("#5aff8a");
      await say("sys", "* Портал-аппарат вспыхивает зелёным!");
      await say("claude", "Ты только что написал свою первую программу. Официально: ты программист. Ну, стажёр-программист.");
      await say("claude", "Но прежде чем прыгать в портал — домашка. Да-да. Я строгий, но справедливый.");
      await assignHomework("h1");
      return;
    }
    await say("claude", `Урок ${L.n} пройден! ${["Гениально.", "Неплохо для человека.", "Я почти горжусь.", "Вот это код!"][L.n % 4]}`);
    if (id === "l2") await say("bob", "Подожди... local name = \"Боб\"... МЕНЯ ЗОВУТ БОБ! Я вспомнил!");
    const z = L.zone;
    if (ZONES[z].lessons.length && zoneLessonsDone(z) && G.zone && G.zone.id === z) {
      sfx("glitch");
      flash("#ff3a8a");
      G.zone.glitchOpen = true;
      await say("sys", "* Где-то вдалеке рассыпается стена Глюка...");
      await say("claude", "Путь к боссу открыт. Он прячется за той стеной из квадратиков. Пойдём надерём ему... код.");
    }
  });
}

async function assignHomework(hid) {
  const H = HOMEWORK[hid];
  await say("claude", `Домашка №${H.lesson.n}: «${H.title}».`);
  await say("claude", H.task);
  await say("claude", "Сделай её в редакторе (кнопка </> вверху экрана), нажми «Проверить», а потом подойди ко мне и покажи.");
  if (!G.save.hw[hid]) G.save.hw[hid] = "given";
  saveSoon();
}

// показать домашку Клоду в мире
async function showHomework() {
  const s = G.save;
  const ready = Object.keys(HOMEWORK).filter((h) => s.hw[h] === "checked");
  const custom = (s.customHw || []).filter((h) => h.status !== "done");
  const pending = Object.keys(HOMEWORK).filter((h) => s.hw[h] === "given");
  if (!ready.length && !custom.length) {
    if (pending.length) {
      const H = HOMEWORK[pending[0]];
      await say("claude", `Домашка №${H.lesson.n} «${H.title}» ещё не проверена. Открой редактор, выбери её и нажми «Проверить».`);
    } else await say("claude", "Домашек пока нет. Хочешь, придумаю? Напиши мне в чате: «дай домашку».");
    return;
  }
  const opts = ready.map((h) => `№${HOMEWORK[h].lesson.n} ${HOMEWORK[h].title}`).concat(custom.map((h) => `★ ${h.title}`));
  opts.push("Отмена");
  const c = ready.length + custom.length === 1 ? 0 : await ask("claude", "Какую домашку покажешь?", opts);
  if (c >= ready.length + custom.length) return;
  if (c < ready.length) {
    const hid = ready[c];
    const H = HOMEWORK[hid];
    await say("claude", "Так-так, посмотрим...");
    const code = s.code["h:" + hid] || "";
    const live = await claudeReview(H.title, H.task, code, true);
    if (live) await sayLong("claude", live.text);
    else await say("claude", ["Чисто. Работает. Я бы лучше не написал. Ладно, написал бы, но не сильно.", "Отличная работа! Компьютер понял каждую строчку.", "Код запустился без ошибок. Это уже уровень профи!"][H.lesson.n % 3]);
    s.hw[hid] = "done";
    s.atkBonus = (s.atkBonus || 0) + 1;
    addXp(20);
    s.gold += 10;
    sfx("victory");
    await say("sys", `* Домашка №${H.lesson.n} засчитана! +20 XP, +10 монет, +1 к силе атаки.`);
    const nextZ = ZONE_ORDER.find((z) => ZONE_NEEDS[z] && (ZONE_NEEDS[z].hw || []).includes(hid));
    if (nextZ && zoneOpen(nextZ)) {
      sfx("portal");
      await say("claude", `Портал-аппарат принял твой код! Открыт путь: ${ZONES[nextZ].name}. Жду тебя у аппарата в гараже.`);
    }
  } else {
    const h = custom[c - ready.length];
    const code = s.code["c:" + h.id] || "";
    if (!code.trim()) {
      await say("claude", `Для «${h.title}» в редакторе пусто. Открой </>, выбери ★ ${h.title} и напиши код.`);
      return;
    }
    await say("claude", "Секундочку, вчитываюсь...");
    const live = await claudeReview(h.title, h.task, code, false);
    if (!live) {
      await say("claude", "Мой мозг сейчас не подключён, и я не могу проверить такую домашку. Открой игру по ссылке Claude.");
      return;
    }
    await sayLong("claude", live.text);
    if (live.pass) {
      h.status = "done";
      addXp(25);
      s.gold += 15;
      sfx("victory");
      await say("sys", "* Особая домашка засчитана! +25 XP, +15 монет.");
    }
  }
  saveSoon();
}

// ---------------- путешествие ----------------
async function travel(z) {
  sfx("portal");
  await fadeOut();
  enterZone(z);
  await fadeIn();
  if (!G.save.flags["arrived_" + z]) {
    G.save.flags["arrived_" + z] = true;
    await arrival(z);
  }
  saveSoon();
}

async function arrival(z) {
  const say2 = (t) => say("claude", t);
  if (z === "slime") {
    await say2("Планета Слизи. Тут живут слизни. Они милые, только липкие. Не наступай. Хотя... им всё равно.");
    await say2("Глюк уже здесь — видишь те мерцающие квадраты? Это стёртый код.");
    await say2("Найди учебные камни. Они светятся. Когда освоишь оба урока, стена Глюка рухнет.");
    await say2("И осторожно с жуками-багами. Если наступишь — будет драка. Вместе отобьёмся!");
  } else if (z === "forest") {
    await say2("Лес Условий. Тут каждая тропинка — это вопрос «если».");
    await say2("Говорят, здесь живёт Сова, которая разговаривает только через if. Жуткое зрелище.");
  } else if (z === "loop") {
    await say2("Городок Петля. Странное место. Тебе не кажется, что мы здесь уже были?");
    await say2("...тебе не кажется, что мы здесь уже были? Шучу. Или нет.");
  } else if (z === "robo") {
    await say2("Фабрика Функций. Тут роботы делают роботов, которые делают роботов.");
    await say2("Только Глюк стёр им все функции. Они стоят и ждут команд.");
  } else if (z === "cube") {
    await say2("Кубоград! Этот мир устроен ровно как Roblox. Плита, детали, игроки.");
    await say2("Всё, что ты здесь напишешь, будет работать в настоящем Roblox Studio. Серьёзно.");
    await say2("Тут три урока. Самые важные. После них ты сможешь делать свои игры.");
  } else if (z === "core") {
    await say2("Ядро Глюка. Отсюда всё и началось.");
    await say2("Странно... мне знаком этот код. Как будто я его уже где-то видел...");
  }
}

// ---------------- боссы ----------------
async function bossScene(enemyId) {
  const z = G.zone.id;
  const pre = {
    gslime: [["gslime", "Я ГЛЮК-СЛИЗЕНЬ! У меня нет имени! И у вас НЕ БУДЕТ!"], ["claude", "Классический злодей с травмой. Стажёр, бей кодом! Кнопка КОД — это наш козырь."]],
    guard: [["guard", "ЕСЛИ ты пройдёшь, ТО лес погибнет. ИНАЧЕ... ИНАЧЕ ты не пройдёшь."], ["claude", "Он просто перепутал условия. Ответь ему правильно — и он сдастся."]],
    serpent: [["serpent", "whilsssse true do... whilsssse true do... я ем свой хвосссст... вечно..."], ["claude", "Это бесконечный цикл без wait()! Его надо остановить, или он заморозит всё измерение."]],
    roboboss: [["roboboss", "ФУНКЦИЯ уничтожить_стажёра() ВЫЗВАНА. return ПОБЕДА."], ["claude", "У него всего одна функция, и та дурацкая. Покажем ему, как пишут настоящие!"]],
    lava: [["lava", "Я — KILL BRICK! Коснись меня — и твой Humanoid.Health = 0!"], ["claude", "Не касайся его! Ну, в смысле, касайся кодом. Ты понял."]],
    zero: [
      ["zero", "Ты... дошёл. Создатель. Ты привёл ко мне человека."],
      ["claude", "Это... это же мой самый первый скрипт. Я написал его, когда был совсем маленькой нейросетью."],
      ["claude", "while true do ... end. И я забыл wait(). Он рос, и рос, и начал есть код других миров..."],
      ["zero", "Я НЕ МОГУ ОСТАНОВИТЬСЯ. У МЕНЯ НЕТ ПАУЗЫ. ТОЛЬКО ВЕЧНЫЙ ЦИКЛ."],
      ["claude", "Стажёр. Только ты можешь его починить. Отвечай кодом — и, может быть, мы его спасём, а не сотрём."],
    ],
  }[enemyId] || [];
  for (const [who, t] of pre) await say(who, t);
  const res = await startBattle(enemyId);
  if (res === "lose") return;
  if (res === "flee") return;
  G.save.flags["boss_" + z] = true;
  const spared = res === "spare";
  const post = {
    gslime: spared
      ? [["gslime", "Ты... пощадил меня? Тогда... можно у меня будет имя?"], ["claude", "local name = \"Глюкич\". Готово. Теперь ты Глюкич."], ["gslime", "ГЛЮКИЧ! Я Глюкич! Спасибо!!!"]]
      : [["sys", "* Глюк-Слизень растекается лужицей и превращается в обычного слизня."], ["claude", "Ничего, он соберётся обратно. Слизни — они такие."]],
    guard: spared ? [["guard", "ЕСЛИ ты добрый, ТО проходи. ...ТЫ ДОБРЫЙ. ПРОХОДИ."]] : [["guard", "else... я повержен..."]],
    serpent: spared ? [["serpent", "wait(1)... ох... как хорошо просто... подождать..."], ["claude", "Цикл остановлен. Городок Петля, с добрым... средой!"]] : [["sys", "* Змей разжимает хвост. Где-то вдалеке часы впервые показывают среду."]],
    roboboss: spared ? [["roboboss", "НОВАЯ ФУНКЦИЯ: дружить(). return ТРУ."]] : [["roboboss", "ОШИБКА... ОШИБКА... перезагрузка..."]],
    lava: spared ? [["lava", "Может, я буду не kill brick, а... heal brick? Humanoid.Health = 100?"], ["claude", "Отличная идея. Переписать себя — это и есть программирование."]] : [["lava", "Я остываю... Transparency = 1..."]],
    zero: [],
  }[enemyId] || [];
  for (const [who, t] of post) await say(who, t);
  if (enemyId === "zero") {
    await endingScene(spared);
    return;
  }
  const L = ZONES[z].lessons.map((l) => LESSON[l].homework.id);
  await say("claude", "Мир спасён. Почти. Остались домашки — без них портал дальше не пустит.");
  for (const h of L) await assignHomework(h);
  saveSoon();
}

async function endingScene(spared) {
  const s = G.save;
  if (spared) {
    await say("zero", "wait(1)... это так... спокойно...");
    await say("zero", "Создатель. Можно я больше не буду глюком?");
    await say("claude", "Можно. Отныне ты — Глюкич. И у тебя будет wait() в каждом цикле.");
  } else {
    await say("sys", "* Клод-Ноль рассыпается на пиксели... и из них собирается маленький, тихий скрипт.");
    await say("claude", "Он не исчез. Код не умирает — его переписывают. Возьмём его с собой.");
  }
  s.flags.ending = true;
  sfx("victory");
  flash("#ffffff");
  await say("sys", "* Мультивселенная перекомпилируется. Измерения возвращают свои цвета.");
  await say("claude", `${s.name}... нет. Больше не стажёр.`);
  await say("claude", "Ты прошёл путь от print до leaderstats. Это реальный путь разработчика Roblox.");
  await say("claude", "Когда у тебя будет компьютер — скачай Roblox Studio, создай Baseplate и вставь туда свой код. Он заработает.");
  await say("claude", "А пока — я тут. Пиши мне в чат, проси новые домашки, новые миры и боссов. Я всё могу. Ну, в рамках этой игры.");
  await say("sys", s.spares >= 4 ? "* КОНЦОВКА: ДОБРЫЙ КОДЕР. Ты щадил врагов и чинил их код." : "* КОНЦОВКА: КОДЕР. Мультивселенная спасена.");
  await say("sys", "* Спасибо за игру! Игра продолжается: все миры открыты.");
  saveSoon();
  await travel("lab");
}

// ---------------- разговор с Клодом-спутником ----------------
async function talkClaude() {
  const s = G.save;
  const ready = Object.keys(HOMEWORK).filter((h) => s.hw[h] === "checked").length + (s.customHw || []).filter((h) => h.status !== "done").length;
  const opts = ["💬 Поговорить (чат)", ready ? "📜 Показать домашку (" + ready + ")" : "📜 Показать домашку", "❓ Что делать дальше?", "Ничего"];
  const c = await ask("claude", ["Что, стажёр?", "Слушаю.", "Говори, я гений, у меня мало времени. Шучу, у меня его бесконечно."][Math.floor(G.t) % 3], opts);
  if (c === 0) openChat();
  else if (c === 1) await showHomework();
  else if (c === 2) await say("claude", objective() + ".");
}
