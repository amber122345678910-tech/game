/* ===== 05c_gamelist.js ===== */
// Список игр, которые Амиго запускает прямо в чате (сами игры — в 08b_games.js).
// strict — название однозначное, игру можно запускать по одному слову;
// loose — слово неоднозначное, нужна просьба поиграть рядом («давай», «запусти», «игра»...).
const GAME_LIST = {
  snake: { title: 'Змейка', icon: '🐍', strict: /змейк|snake/, loose: /зме[йия]/, help: 'Стрелки, WASD или свайпы. Собирай яблоки и не врезайся.' },
  tetris: { title: 'Тетрис', icon: '🧱', strict: /тетрис|tetris/, help: '← → двигать, ↑ повернуть, ↓ быстрее, пробел — бросить вниз.' },
  g2048: { title: '2048', icon: '🔢', strict: /игр\S*\s+2048|2048\s+игр/, loose: /2048/, help: 'Стрелки или свайпы. Соединяй одинаковые плитки и собери 2048.' },
  ttt: { title: 'Крестики-нолики', icon: '❌', strict: /крестик|нолик|tic.?tac/, help: 'Ты играешь крестиками, Амиго — ноликами.' },
  mines: { title: 'Сапёр', icon: '💣', strict: /сап[её]р|minesweeper/, loose: /(^|\s)мины(?![а-я])/, help: 'Открывай клетки. Флажок — правой кнопкой, долгим нажатием или в режиме 🚩.' },
  memory: { title: 'Найди пару', icon: '🃏', strict: /найди пару|мемори|memory/, loose: /пары|карточк/, help: 'Переворачивай карточки и находи одинаковые пары.' },
  breakout: { title: 'Арканоид', icon: '🏏', strict: /арканоид|breakout/, loose: /кирпич/, help: 'Двигай платформу пальцем, мышкой или стрелками. Пробел — запустить мяч.' },
  pong: { title: 'Понг', icon: '🏓', strict: /(^|\s)понг|pong/, loose: /пинг.?понг|теннис/, help: 'Двигай нижнюю ракетку. Кто первым наберёт 7 очков, тот победил.' },
  flappy: { title: 'Летучий Амиго', icon: '🐤', strict: /флэппи|флеппи|flappy|летуч\S* амиго/, loose: /птичк/, help: 'Нажимай на экран или пробел, чтобы взлететь. Пролетай между трубами.' },
  catcher: { title: 'Звездопад', icon: '⭐', strict: /звездопад/, loose: /поймай|лови|звёзд|звезд/, help: 'Лови звёзды корзинкой и уворачивайся от метеоритов.' },
};
const GameList = {
  keys: Object.keys(GAME_LIST),
  // ключ игры по тексту или null; ctx — в тексте уже есть просьба поиграть; strictOnly — только точные названия
  find(text, ctx, strictOnly) {
    const t = String(text).toLowerCase().replace(/ё/g, 'е');
    const want = ctx || /(игр|сыгра|поигра|запусти|включи)/.test(t);
    for (const k of this.keys) { const g = GAME_LIST[k]; if (g.strict.test(t) || (!strictOnly && want && g.loose && g.loose.test(t))) return k; }
    return null;
  },
  // настройки из просьбы: «сделай змейку быстрее и красную»
  opts(text) {
    const t = String(text).toLowerCase().replace(/ё/g, 'е'), o = {};
    if (/быстр|сложн|трудн|хардкор|посложнее/.test(t)) o.speed = 1.45;
    else if (/медлен|легк|прост|полегче|для малыш/.test(t)) o.speed = 0.7;
    const colors = [[/красн/, '#E53935'], [/оранж/, '#F07B16'], [/желт|золот/, '#E0B000'], [/зелен/, '#2E9D4E'], [/голуб/, '#2AA7D8'], [/син/, '#1E63D6'],
      [/фиолет/, '#8E44AD'], [/розов/, '#E85D9A'], [/черн/, '#2B2B2B'], [/бел/, '#F2F2F2'], [/радуж/, 'rainbow']];
    for (const [re, c] of colors) if (re.test(t)) { o.color = c; break; }
    if (/без стен|сквозь стен|через стен/.test(t)) o.wrap = true;
    return o;
  },
  list() { return this.keys.map(k => GAME_LIST[k].icon + ' ' + GAME_LIST[k].title).join(', '); },
};
