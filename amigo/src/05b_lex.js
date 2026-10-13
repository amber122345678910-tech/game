/* ===== 05b_lex.js ===== */
// Словарь Амиго: тысячи слов с описаниями. Благодаря ему Амиго понимает отдельные слова
// («кошка», «майнкрафт», «шрек») и может поддержать разговор о них, а новые слова учит прямо в беседе.
const Lex = (() => {
  const low = s => String(s).toLowerCase().replace(/ё/g, 'е');
  // короткие частые слова, которые нельзя сопоставлять с основами словаря («лет» ≠ «лето», «дел» ≠ «дело»)
  const STOP = new Set(('я ты он она оно мы вы они меня тебя его ее нас вас их мне тебе ему ей нам вам им мной тобой мой моя мое мои твой твоя твое твои ' +
    'свой своя свое свои наш наша наше наши ваш ваша ваше ваши это этот эта эти тот та те то такой такая такое такие так тут там здесь где куда когда ' +
    'как что кто чем чего чему почему зачем какой какая какое какие сколько очень уже еще ещё тоже также вот ну да нет не ни а и но или же ли бы ' +
    'в во на за из у у о об обо от до по под над при про для без с со к ко через после перед между лет год года раз дел дела день дня дни ' +
    'был была было были буду будет будешь есть нет надо можно нужно хочу хочешь могу можешь знаю знаешь люблю любишь нравится нравятся ' +
    'сегодня вчера завтра сейчас щас потом теперь всегда никогда иногда часто тоже просто вообще короче типа кстати слушай амиго привет пока спасибо ' +
    'хорошо плохо норм нормально ладно окей ок ага угу все всё весь вся всех всем много мало больше меньше самый самая самое самые один одна одно ' +
    'два три новый новая новое новые любимый любимая любимое любимые свой сам сама сами себя себе').split(/\s+/));

  let entries = [];             // { w, e, d, c, al, user }
  const exact = new Map();      // форма слова (очищенная) → запись
  const byStem = new Map();     // основа одного слова → запись
  const multi = [];             // многословные: { st: [основы], n, entry }
  const byFirst = new Map();    // для поиска с опечатками: первая буква → [формы]

  function stemOf(w) { return Text.stem(w); }
  function addForm(form, entry) {
    const f = Text.clean(form); if (!f) return;
    if (!exact.has(f) || entry.user) exact.set(f, entry);
    const ws = f.split(' ');
    if (ws.length === 1) {
      const s = stemOf(f);
      if (s.length >= 3 && !STOP.has(f) && (!byStem.has(s) || entry.user)) byStem.set(s, entry);
      if (f.length >= 4) { const k = f[0]; if (!byFirst.has(k)) byFirst.set(k, []); byFirst.get(k).push(f); }
    } else {
      multi.push({ st: ws.map(stemOf), n: ws.length, entry });
    }
  }
  function add(e) {
    entries.push(e);
    addForm(e.w, e);
    for (const a of e.al || []) addForm(a, e);
  }
  function init(data) {
    entries = []; exact.clear(); byStem.clear(); multi.length = 0; byFirst.clear();
    for (const cat of Object.keys(data || {})) {
      for (const it of data[cat]) {
        if (!Array.isArray(it) || !it[0] || !it[2]) continue;
        add({ w: low(it[0]), e: it[1] || '💡', d: String(it[2]).replace(/\.\s*$/, ''), c: cat, al: (it[3] || []).map(low) });
      }
    }
    multi.sort((a, b) => b.n - a.n);
  }
  // выученные от пользователя слова: { слово: { d, e } }
  function addUser(words) {
    for (const w of Object.keys(words || {})) {
      const u = words[w];
      add({ w: low(w), e: u.e || '💡', d: u.d, c: 'user', al: [], user: true });
    }
  }

  // расстояние Дамерау — Левенштейна, но не больше max (для опечаток)
  function dist(a, b, max) {
    if (Math.abs(a.length - b.length) > max) return max + 1;
    const n = a.length, m = b.length;
    let prev2 = null, prev = new Array(m + 1), cur = new Array(m + 1);
    for (let j = 0; j <= m; j++) prev[j] = j;
    for (let i = 1; i <= n; i++) {
      cur[0] = i; let best = cur[0];
      for (let j = 1; j <= m; j++) {
        const c = a[i - 1] === b[j - 1] ? 0 : 1;
        let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + c);
        if (prev2 && i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1);
        cur[j] = v; if (v < best) best = v;
      }
      if (best > max) return max + 1;
      prev2 = prev; prev = cur; cur = new Array(m + 1);
    }
    return prev[m];
  }
  function fuzzy(w) {
    if (w.length < 6) return null;
    const list = byFirst.get(w[0]); if (!list) return null;
    const max = w.length >= 9 ? 2 : 1;
    let best = null, bd = max + 1;
    for (const f of list) { if (f.indexOf(' ') >= 0) continue; const d = dist(w, f, max); if (d < bd) { bd = d; best = f; } }
    return best ? exact.get(best) : null;
  }

  // одно слово → запись словаря (точно, по основе или с опечаткой)
  // глагол ли это («ленюсь», «играешь»), чтобы не путать его с существительным с той же основой («лён», «игра»)
  const VERBISH = /(юсь|усь|ешься|ишься|ешь|ишь|ете|ите|ет|ит|ют|ят|ут|ать|ять|еть|ить|ыть|уть|ться|лся|лась|лись|ала|ила|ела|ули|ую|аю|яю|ею)$/;
  function word(w, allowFuzzy = true) {
    w = Text.clean(w); if (!w || STOP.has(w) || /^\d+$/.test(w)) return null;
    let e = exact.get(w); if (e) return e;
    if (w.length >= 3) {
      const st = stemOf(w);
      e = byStem.get(st);
      if (e && w.length - st.length <= 4 && !(VERBISH.test(w) && !VERBISH.test(e.w))) return e;
    }
    return allowFuzzy ? fuzzy(w) : null;
  }

  // все слова словаря в тексте: [{ entry, form, i, n }], form — как написал пользователь
  function findAll(text, opts = {}) {
    const ws = Text.words(text), st = ws.map(stemOf), used = new Array(ws.length).fill(false), out = [];
    // сначала многословные: «губка боб», «человек паук», «черная дыра»
    for (const m of multi) {
      for (let i = 0; i + m.n <= ws.length; i++) {
        let ok = true;
        for (let k = 0; k < m.n; k++) if (used[i + k] || st[i + k] !== m.st[k]) { ok = false; break; }
        if (!ok) continue;
        for (let k = 0; k < m.n; k++) used[i + k] = true;
        out.push({ entry: m.entry, form: ws.slice(i, i + m.n).join(' '), i, n: m.n });
      }
    }
    for (let i = 0; i < ws.length; i++) {
      if (used[i]) continue;
      const e = word(ws[i], opts.fuzzy !== false && ws.length <= 6);
      if (e) out.push({ entry: e, form: ws[i], i, n: 1 });
    }
    return out.sort((a, b) => a.i - b.i);
  }
  // главное слово фразы: последнее найденное существительное обычно и есть тема («я видел огромную собаку»)
  function main(text, opts) {
    const all = findAll(text, opts);
    if (!all.length) return null;
    return all.reduce((best, x) => (x.n > best.n || (x.n === best.n && x.i > best.i) ? x : best), all[0]);
  }

  const cap = s => s ? s[0].toUpperCase() + s.slice(1) : s;
  // «🐱 Кошка — пушистое домашнее животное…»
  function describe(e) { return `${e.e} ${cap(e.w)} — ${e.d}.`; }

  // вопросы, чтобы продолжить разговор о слове (ключ — что запомнить из ответа)
  const FOLLOW = {
    animals_wild: [['А какое животное тебе нравится больше всего?', 'fav_animal'], ['Хочешь интересный факт про животных?', null, 'fact']],
    pets_farm: [['А у тебя есть домашний питомец? Как его зовут?', 'pet'], ['Какое животное ты бы хотел завести?', 'dream_pet']],
    body_health: [['Береги себя! А ты знаешь, сколько костей у человека? Больше двухсот! 💪', null]],
    food_dishes: [['А какая у тебя любимая еда?', 'fav_food'], ['Вкусно! 😋 А что ты больше всего любишь есть?', 'fav_food']],
    fruits_veg: [['А какой фрукт ты любишь больше всего?', 'fav_fruit'], ['Полезная штука! А тебе что больше нравится: фрукты или овощи?', 'would_rather']],
    sweets_drinks: [['Вкуснотища! 😋 А какая у тебя любимая сладость?', 'fav_sweet']],
    nature_weather: [['А какое время года тебе нравится больше всего?', 'fav_season'], ['Природа — это красиво! Ты любишь гулять на природе?', null]],
    space_science: [['Хочешь интересный факт о космосе? 🚀', null, 'fact'], ['Ты бы хотел полететь в космос?', null]],
    colors_shapes_materials: [['А какой твой любимый цвет?', 'fav_color']],
    home_items: [['Полезная вещь! А что у тебя есть в комнате интересного?', 'open']],
    clothes: [['А какая одежда тебе нравится больше всего?', 'fav_clothes']],
    school: [['А какой у тебя любимый предмет в школе?', 'fav_subject'], ['Как у тебя дела в школе?', null]],
    sports: [['А каким спортом ты занимаешься или хотел бы заниматься?', 'fav_sport'], ['Спорт — это сила! 💪 А какой вид спорта тебе нравится?', 'fav_sport']],
    hobbies_arts_music: [['А какое у тебя любимое занятие?', 'hobby'], ['Здорово! А ты чем любишь заниматься в свободное время?', 'hobby']],
    people_family_professions: [['А кем ты хочешь стать, когда вырастешь?', 'dream_job']],
    transport_places: [['А на чём ты любишь ездить?', 'fav_transport'], ['Куда бы ты хотел поехать?', 'dream_trip']],
    tech_internet: [['А у тебя какой гаджет любимый?', 'fav_gadget'], ['Технологии — это моя стихия 🤖 Ты любишь программировать?', null]],
    geography: [['А где бы ты хотел побывать?', 'dream_trip'], ['Ты там был когда-нибудь?', null]],
    games_toys: [['А в какую игру ты играешь больше всего?', 'fav_game'], ['Давай поиграем? У меня есть игры прямо в чате 🎮', null, 'play']],
    cartoons_movies_characters: [['А какой мультик или фильм твой любимый?', 'fav_cartoon'], ['Кто твой любимый персонаж?', 'fav_hero']],
    emotions_abstract_holidays: [['А что для тебя самое важное?', 'open'], ['Расскажи, а что тебя радует больше всего?', 'open']],
    user: [['Спасибо, что научил меня этому слову! Расскажешь ещё что-нибудь?', null]],
    slang: [['Ты часто так говоришь? 😄', null], ['Знаешь ещё какие-нибудь словечки? Научи меня!', null]],
  };
  function followUp(e, rnd = Math.random) {
    const list = FOLLOW[e.c] || [['А ты что об этом думаешь?', null]];
    const [q, key, offer] = list[Math.floor(rnd() * list.length)];
    return { q, key, offer };
  }

  // мнение Амиго о вещи по её виду
  const OPINION = {
    animals_wild: ['Обожаю животных! {E} {W} — {d}.', 'Мне очень нравятся животные. {E} {W} — {d}. Удивительно, правда?'],
    pets_farm: ['Конечно! {E} {W} — {d}. Питомцы — лучшие друзья!', '{E} Очень! {W} — {d}.'],
    food_dishes: ['Я сам не ем, у меня ведь нет рта 😄 Но {e}{w} — {d}. Звучит вкусно!', 'Если бы я мог есть, обязательно попробовал бы! {E} {W} — {d}.'],
    fruits_veg: ['Я не ем, но {e}{w} — это полезно: {d}.', 'Люблю, когда люди едят полезное! {E} {W} — {d}.'],
    sweets_drinks: ['Я не ем сладкое, но {e}{w} точно делает людей счастливее 😄 {W} — {d}.'],
    nature_weather: ['Мне нравится! {E} {W} — {d}. Природа очень красивая.', '{E} {W} — {d}. По-моему, это красиво!'],
    space_science: ['Обожаю такое! {E} {W} — {d}. Наука — это суперсила!', 'Очень интересно! {E} {W} — {d}.'],
    colors_shapes_materials: ['{E} {W} — {d}. Мне нравится, а мой любимый цвет — тёплый жёлтый 💛'],
    home_items: ['{E} {W} — {d}. Полезная штука!'],
    clothes: ['{E} {W} — {d}. Мне одежда не нужна, но выглядит здорово!'],
    school: ['{E} {W} — {d}. Учиться интересно, особенно когда понятно!', 'Мне нравится! {E} {W} — {d}. Я ведь и сам всё время учусь.'],
    sports: ['{E} {W} — {d}. Я бы занимался, будь у меня руки и ноги 😄', 'Спорт — это круто! {E} {W} — {d}.'],
    hobbies_arts_music: ['{E} {W} — {d}. Творчество — это здорово!', 'Мне нравится! {E} {W} — {d}.'],
    people_family_professions: ['{E} {W} — {d}. Очень важное дело!'],
    transport_places: ['{E} {W} — {d}. Интересно!'],
    tech_internet: ['Технологии — это моё! 🤖 {E} {W} — {d}.', '{E} {W} — {d}. Мне нравится, я ведь сам программа 😄'],
    geography: ['{E} {W} — {d}. Хотел бы я там побывать!'],
    games_toys: ['{E} {W} — {d}. Игры — это весело! Мне больше всего нравятся те, где надо думать.', 'Конечно! {E} {W} — {d}.'],
    cartoons_movies_characters: ['{E} {W}? Знаю! {d}. Классная штука!', 'Мне нравится! {E} {W} — {d}.'],
    emotions_abstract_holidays: ['{E} {W} — {d}. Это очень важно!'],
    user: ['{E} {W} — {d}. Это ты меня научил 😊'],
  };
  function fill(t, e) {
    return t.replace(/\{E\}/g, e.e).replace(/\{e\}/g, e.e + ' ').replace(/\{W\}/g, cap(e.w)).replace(/\{w\}/g, e.w).replace(/\{d\}/g, e.d)
      .replace(/ {2,}/g, ' ');
  }
  function opinion(e, rnd = Math.random) {
    const list = OPINION[e.c] || ['{E} {W} — {d}. По-моему, это интересно!'];
    return fill(list[Math.floor(rnd() * list.length)], e);
  }

  return { init, addUser, word, findAll, main, describe, followUp, opinion, fill, dist, get size() { return entries.length; }, STOP };
})();
Lex.init(Object.assign({}, typeof LEX_DATA !== 'undefined' ? LEX_DATA : {}, typeof LEX_EXTRA !== 'undefined' ? LEX_EXTRA : {}));

// Исправление опечаток: незнакомое слово заменяем на похожее знакомое («тибя» → «тебя», «лублю» → «люблю»).
// Словарь собирается из всех обучающих фраз и словаря Амиго при первом использовании.
const Spell = (() => {
  let freq = null, byFirst = null;
  function build() {
    freq = new Map(); byFirst = new Map();
    const add = w => { if (w.length >= 3 && !/\d/.test(w)) freq.set(w, (freq.get(w) || 0) + 1); };
    for (const it of INTENTS) for (const p of it.p) for (const w of Text.words(p.replace(/\{\w+\}/g, ' '))) add(w);
    for (const k of Object.keys(FILL)) for (const v of FILL[k]) for (const w of Text.words(v)) add(w);
    const LD = Object.assign({}, typeof LEX_DATA !== 'undefined' ? LEX_DATA : {}, typeof LEX_EXTRA !== 'undefined' ? LEX_EXTRA : {});
    for (const c of Object.keys(LD)) for (const e of LD[c]) { for (const w of Text.words(e[0])) add(w); for (const a of e[3] || []) for (const w of Text.words(a)) add(w); }
    for (const w of freq.keys()) { const k = w[0]; if (!byFirst.has(k)) byFirst.set(k, []); byFirst.get(k).push(w); }
  }
  function known(w) { if (!freq) build(); return freq.has(w); }
  function fixWord(w) {
    if (!freq) build();
    if (w.length < 4 || freq.has(w) || /\d/.test(w)) return w;
    // первая буква тоже может быть опечаткой, поэтому смотрим и соседние группы
    let best = w, bf = 0;
    const cands = (byFirst.get(w[0]) || []).concat(w[1] ? (byFirst.get(w[1]) || []).filter(x => x[1] === w[0]) : []);
    for (const c of cands) {
      if (Math.abs(c.length - w.length) > 1) continue;
      if (Lex.dist(w, c, 1) <= 1) { const f = freq.get(c); if (f > bf) { bf = f; best = c; } }
    }
    return best;
  }
  function fix(text) { return Text.words(text).map(fixWord).join(' '); }
  // «кд чд» → «как дела что делаешь»
  function expand(text) {
    if (typeof SLANG_EXPAND === 'undefined') return Text.clean(text);
    return Text.words(text).map(w => SLANG_EXPAND[w] || w).join(' ');
  }
  return { fix, fixWord, known, expand };
})();
