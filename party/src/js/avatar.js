'use strict';
// Блочный персонаж как в Роблоксе (R6): голова, торс, 2 руки, 2 ноги + одежда, лицо, причёски, шапки, аксессуары.

const SKIN_TONES = [
  { n: 'Нуб-жёлтый', c: '#f5cd30' }, { n: 'Светлая', c: '#f7d9bb' }, { n: 'Персиковая', c: '#eab892' },
  { n: 'Загар', c: '#c98d63' }, { n: 'Шоколад', c: '#8d5a3a' }, { n: 'Тёмная', c: '#5c3a26' },
  { n: 'Зомби', c: '#86c06c' }, { n: 'Синяя', c: '#62a8f0' }, { n: 'Розовая', c: '#ffa6d2' },
  { n: 'Серая', c: '#a7abb3' }, { n: 'Белая', c: '#f2f3f5' }, { n: 'Фиолетовая', c: '#a07ae0' },
];

const PALETTE = [
  { n: 'Красный', c: '#e63e3e' }, { n: 'Оранжевый', c: '#ff8c1a' }, { n: 'Жёлтый', c: '#ffd23f' },
  { n: 'Лайм', c: '#7ed321' }, { n: 'Зелёный', c: '#2fa84f' }, { n: 'Бирюзовый', c: '#1fc7c1' },
  { n: 'Голубой', c: '#5ab8ff' }, { n: 'Синий', c: '#2463eb' }, { n: 'Тёмно-синий', c: '#22306a' },
  { n: 'Фиолетовый', c: '#8a4fff' }, { n: 'Лавандовый', c: '#c3a6ff' }, { n: 'Розовый', c: '#ff6fb5' },
  { n: 'Нежно-розовый', c: '#ffc4dd' }, { n: 'Белый', c: '#f4f4f4' }, { n: 'Серый', c: '#8a8f98' },
  { n: 'Чёрный', c: '#26262b' }, { n: 'Коричневый', c: '#7a4a2a' }, { n: 'Бежевый', c: '#d9b98c' },
  { n: 'Мятный', c: '#9ff0c8' }, { n: 'Вишнёвый', c: '#9c1c3c' },
];

const HAIR_COLORS = [
  { n: 'Каштановый', c: '#5a3420' }, { n: 'Чёрный', c: '#1f1b1b' }, { n: 'Блонд', c: '#f2d16b' },
  { n: 'Рыжий', c: '#d2572b' }, { n: 'Розовый', c: '#ff7ac0' }, { n: 'Голубой', c: '#58c4ff' },
  { n: 'Фиолетовый', c: '#9d5cff' }, { n: 'Белый', c: '#efefef' }, { n: 'Зелёный', c: '#4ccf6a' },
  { n: 'Мятный', c: '#8ff0d0' },
];

const FACES = [
  { id: 'smile', n: 'Улыбка' }, { id: 'grin', n: 'Хи-хи' }, { id: 'cool', n: 'Крутые очки' }, { id: 'wink', n: 'Подмигивает' },
  { id: 'kawaii', n: 'Кавай' }, { id: 'cat', n: 'Котик :3' }, { id: 'hearts', n: 'Влюблённые глаза' }, { id: 'stars', n: 'Звёздочки' },
  { id: 'tongue', n: 'Язык :P' }, { id: 'angry', n: 'Злюка' }, { id: 'shock', n: 'Шок' }, { id: 'sleepy', n: 'Соня' },
  { id: 'robot', n: 'Робот' }, { id: 'zombie', n: 'Зомби' }, { id: 'ninja', n: 'Ниндзя' },
];

const HAIRS = [
  { id: 'none', n: 'Лысый' }, { id: 'short', n: 'Короткая' }, { id: 'long', n: 'Длинная' }, { id: 'pigtails', n: 'Хвостики' },
  { id: 'bacon', n: 'Бекон' }, { id: 'spiky', n: 'Ёжик' }, { id: 'bun', n: 'Пучок' }, { id: 'bob', n: 'Каре' }, { id: 'mohawk', n: 'Ирокез' },
];

const HATS = [
  { id: 'none', n: 'Нет' }, { id: 'crown', n: 'Корона' }, { id: 'tophat', n: 'Цилиндр' }, { id: 'cap', n: 'Кепка' },
  { id: 'beanie', n: 'Шапка с помпоном' }, { id: 'cowboy', n: 'Ковбойская' }, { id: 'catears', n: 'Кошачьи ушки' },
  { id: 'bunny', n: 'Заячьи ушки' }, { id: 'halo', n: 'Нимб' }, { id: 'horns', n: 'Рожки' }, { id: 'headphones', n: 'Наушники' },
  { id: 'flowers', n: 'Венок' }, { id: 'viking', n: 'Шлем викинга' }, { id: 'party', n: 'Колпак' }, { id: 'bow', n: 'Бантик' },
];

const PATTERNS = [
  { id: 'plain', n: 'Без рисунка' }, { id: 'stripes', n: 'Полоски' }, { id: 'heart', n: 'Сердце' }, { id: 'star', n: 'Звезда' },
  { id: 'bolt', n: 'Молния' }, { id: 'smile', n: 'Смайлик' }, { id: 'tie', n: 'Галстук' }, { id: 'rainbow', n: 'Радуга' },
  { id: 'skull', n: 'Черепок' }, { id: 'one', n: 'Номер 1' }, { id: 'flower', n: 'Цветок' }, { id: 'overalls', n: 'Комбинезон' },
];

const BOTTOMS = [{ id: 'pants', n: 'Брюки' }, { id: 'shorts', n: 'Шорты' }, { id: 'skirt', n: 'Юбка' }];

const BACKS = [
  { id: 'none', n: 'Нет' }, { id: 'angel', n: 'Крылья ангела' }, { id: 'bat', n: 'Крылья демона' }, { id: 'fairy', n: 'Крылья феи' },
  { id: 'cape', n: 'Плащ героя' }, { id: 'backpack', n: 'Рюкзак' }, { id: 'tail', n: 'Хвостик' }, { id: 'sword', n: 'Меч' }, { id: 'jetpack', n: 'Реактивный ранец' },
];

const TRAILS = [
  { id: 'none', n: 'Нет' }, { id: 'rainbow', n: 'Радуга' }, { id: 'fire', n: 'Огонь' }, { id: 'hearts', n: 'Сердечки' },
  { id: 'stars', n: 'Звёзды' }, { id: 'sparkle', n: 'Блёстки' }, { id: 'bubbles', n: 'Пузыри' },
];

const PRESETS = [
  { n: 'Нуб', s: { tone: 0, face: 'smile', hair: 'none', hairColor: 0, hat: 'none', shirt: 6, pattern: 'plain', bottom: 'pants', pants: 3, back: 'none', trail: 'none' } },
  { n: 'Принцесса', s: { tone: 1, face: 'kawaii', hair: 'long', hairColor: 2, hat: 'crown', shirt: 11, pattern: 'heart', bottom: 'skirt', pants: 12, back: 'fairy', trail: 'hearts' } },
  { n: 'Бекон', s: { tone: 2, face: 'smile', hair: 'bacon', hairColor: 0, hat: 'none', shirt: 4, pattern: 'plain', bottom: 'pants', pants: 16, back: 'none', trail: 'none' } },
  { n: 'Ниндзя', s: { tone: 3, face: 'ninja', hair: 'spiky', hairColor: 1, hat: 'none', shirt: 15, pattern: 'plain', bottom: 'pants', pants: 15, back: 'sword', trail: 'sparkle' } },
  { n: 'Котик', s: { tone: 10, face: 'cat', hair: 'bob', hairColor: 7, hat: 'catears', shirt: 12, pattern: 'stripes', bottom: 'shorts', pants: 14, back: 'tail', trail: 'stars' } },
  { n: 'Ангел', s: { tone: 1, face: 'stars', hair: 'pigtails', hairColor: 2, hat: 'halo', shirt: 13, pattern: 'plain', bottom: 'skirt', pants: 13, back: 'angel', trail: 'sparkle' } },
  { n: 'Демон', s: { tone: 0, face: 'angry', hair: 'mohawk', hairColor: 1, hat: 'horns', shirt: 19, pattern: 'skull', bottom: 'pants', pants: 15, back: 'bat', trail: 'fire' } },
  { n: 'Робот', s: { tone: 9, face: 'robot', hair: 'none', hairColor: 7, hat: 'headphones', shirt: 14, pattern: 'bolt', bottom: 'pants', pants: 8, back: 'jetpack', trail: 'fire' } },
  { n: 'Зомби', s: { tone: 6, face: 'zombie', hair: 'short', hairColor: 1, hat: 'none', shirt: 5, pattern: 'plain', bottom: 'shorts', pants: 16, back: 'none', trail: 'bubbles' } },
  { n: 'Ковбой', s: { tone: 3, face: 'grin', hair: 'short', hairColor: 3, hat: 'cowboy', shirt: 0, pattern: 'tie', bottom: 'pants', pants: 7, back: 'none', trail: 'none' } },
  { n: 'Супергерой', s: { tone: 2, face: 'cool', hair: 'short', hairColor: 1, hat: 'none', shirt: 7, pattern: 'bolt', bottom: 'pants', pants: 0, back: 'cape', trail: 'rainbow' } },
  { n: 'Зайка', s: { tone: 1, face: 'hearts', hair: 'bun', hairColor: 4, hat: 'bunny', shirt: 10, pattern: 'flower', bottom: 'skirt', pants: 18, back: 'backpack', trail: 'rainbow' } },
  { n: 'Викинг', s: { tone: 2, face: 'grin', hair: 'long', hairColor: 3, hat: 'viking', shirt: 16, pattern: 'plain', bottom: 'pants', pants: 17, back: 'sword', trail: 'none' } },
  { n: 'Пижамка', s: { tone: 1, face: 'sleepy', hair: 'short', hairColor: 0, hat: 'beanie', shirt: 6, pattern: 'star', bottom: 'pants', pants: 6, back: 'none', trail: 'bubbles' } },
];

function defaultSkin(i) {
  return { ...(i === 1 ? PRESETS[1].s : PRESETS[10].s) };
}

function randomSkin() {
  return {
    tone: randi(0, SKIN_TONES.length - 1), face: pick(FACES).id, hair: pick(HAIRS).id, hairColor: randi(0, HAIR_COLORS.length - 1),
    hat: chance(0.6) ? pick(HATS).id : 'none', shirt: randi(0, PALETTE.length - 1), pattern: pick(PATTERNS).id,
    bottom: pick(BOTTOMS).id, pants: randi(0, PALETTE.length - 1), back: chance(0.6) ? pick(BACKS).id : 'none', trail: pick(TRAILS).id,
  };
}

// ---------------------------------------------------------------------------
// Рисование лица и принтов на canvas.

function drawFace(g, w, h, type) {
  const ink = '#1d1a1f';
  const ex = w * 0.37;
  const ex2 = w * 0.63;
  const ey = h * 0.42;
  g.lineCap = 'round';
  g.lineJoin = 'round';
  const eye = (x, y, rx = w * 0.035, ry = h * 0.1) => { g.fillStyle = ink; g.beginPath(); g.ellipse(x, y, rx, ry, 0, 0, TAU); g.fill(); };
  const shine = (x, y, r) => { g.fillStyle = '#fff'; g.beginPath(); g.arc(x, y, r, 0, TAU); g.fill(); };
  const smile = (r = w * 0.14, y = h * 0.55, lw = h * 0.045, a0 = 0.18, a1 = 0.82) => {
    g.strokeStyle = ink; g.lineWidth = lw; g.beginPath(); g.arc(w / 2, y, r, Math.PI * a0, Math.PI * a1); g.stroke();
  };
  const blush = () => { g.fillStyle = 'rgba(255,110,150,0.45)'; for (const x of [w * 0.27, w * 0.73]) { g.beginPath(); g.ellipse(x, h * 0.62, w * 0.06, h * 0.05, 0, 0, TAU); g.fill(); } };
  const heart = (x, y, s, col) => {
    g.fillStyle = col; g.beginPath(); g.moveTo(x, y + s * 0.9);
    g.bezierCurveTo(x - s * 1.4, y, x - s * 0.8, y - s * 1.1, x, y - s * 0.4);
    g.bezierCurveTo(x + s * 0.8, y - s * 1.1, x + s * 1.4, y, x, y + s * 0.9); g.fill();
  };
  const star = (x, y, r, col) => {
    g.fillStyle = col; g.beginPath();
    for (let i = 0; i < 10; i++) { const rr = i % 2 ? r * 0.45 : r; const a = -Math.PI / 2 + i * Math.PI / 5; g.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr); }
    g.closePath(); g.fill();
  };
  switch (type) {
    case 'grin':
      eye(ex, ey); eye(ex2, ey);
      g.fillStyle = ink; g.beginPath(); g.moveTo(w * 0.33, h * 0.6); g.quadraticCurveTo(w / 2, h * 0.92, w * 0.67, h * 0.6); g.closePath(); g.fill();
      g.fillStyle = '#fff'; g.fillRect(w * 0.36, h * 0.6, w * 0.28, h * 0.06);
      break;
    case 'cool':
      g.fillStyle = ink;
      roundRect(g, w * 0.24, h * 0.3, w * 0.22, h * 0.2, 10); g.fill();
      roundRect(g, w * 0.54, h * 0.3, w * 0.22, h * 0.2, 10); g.fill();
      g.fillRect(w * 0.44, h * 0.34, w * 0.12, h * 0.04);
      g.fillStyle = 'rgba(255,255,255,0.55)'; g.fillRect(w * 0.27, h * 0.33, w * 0.05, h * 0.05); g.fillRect(w * 0.57, h * 0.33, w * 0.05, h * 0.05);
      g.strokeStyle = ink; g.lineWidth = h * 0.045; g.beginPath(); g.moveTo(w * 0.42, h * 0.68); g.quadraticCurveTo(w * 0.55, h * 0.74, w * 0.63, h * 0.62); g.stroke();
      break;
    case 'wink':
      eye(ex, ey);
      g.strokeStyle = ink; g.lineWidth = h * 0.045; g.beginPath(); g.arc(ex2, ey + h * 0.04, w * 0.045, Math.PI * 1.1, Math.PI * 1.9); g.stroke();
      smile(); blush();
      break;
    case 'kawaii':
      for (const x of [ex, ex2]) { eye(x, ey, w * 0.06, h * 0.13); shine(x + w * 0.02, ey - h * 0.05, w * 0.022); shine(x - w * 0.015, ey + h * 0.04, w * 0.01); }
      smile(w * 0.05, h * 0.6, h * 0.035); blush();
      break;
    case 'cat':
      for (const x of [ex, ex2]) { eye(x, ey, w * 0.05, h * 0.11); shine(x + w * 0.015, ey - h * 0.04, w * 0.017); }
      g.strokeStyle = ink; g.lineWidth = h * 0.035; g.beginPath();
      g.arc(w * 0.46, h * 0.62, w * 0.04, 0, Math.PI); g.arc(w * 0.54, h * 0.62, w * 0.04, 0, Math.PI); g.stroke();
      g.lineWidth = h * 0.02;
      for (const s of [-1, 1]) for (const k of [-1, 0, 1]) { g.beginPath(); g.moveTo(w / 2 + s * w * 0.14, h * 0.62 + k * h * 0.05); g.lineTo(w / 2 + s * w * 0.27, h * 0.6 + k * h * 0.09); g.stroke(); }
      g.fillStyle = '#ff7aa8'; g.beginPath(); g.moveTo(w * 0.48, h * 0.56); g.lineTo(w * 0.52, h * 0.56); g.lineTo(w * 0.5, h * 0.59); g.fill();
      break;
    case 'hearts':
      heart(ex, ey, w * 0.06, '#ff3d71'); heart(ex2, ey, w * 0.06, '#ff3d71');
      smile(); blush();
      break;
    case 'stars':
      star(ex, ey, w * 0.07, '#ffc21a'); star(ex2, ey, w * 0.07, '#ffc21a');
      g.fillStyle = ink; g.beginPath(); g.arc(w / 2, h * 0.6, w * 0.08, 0, Math.PI); g.fill();
      break;
    case 'tongue':
      eye(ex, ey); eye(ex2, ey);
      g.strokeStyle = ink; g.lineWidth = h * 0.045; g.beginPath(); g.moveTo(w * 0.38, h * 0.62); g.lineTo(w * 0.62, h * 0.62); g.stroke();
      g.fillStyle = '#ff6b8a'; g.beginPath(); g.ellipse(w * 0.55, h * 0.68, w * 0.05, h * 0.07, 0, 0, TAU); g.fill();
      break;
    case 'angry':
      eye(ex, ey + h * 0.03); eye(ex2, ey + h * 0.03);
      g.strokeStyle = ink; g.lineWidth = h * 0.05;
      g.beginPath(); g.moveTo(w * 0.28, h * 0.22); g.lineTo(w * 0.43, h * 0.3); g.moveTo(w * 0.72, h * 0.22); g.lineTo(w * 0.57, h * 0.3); g.stroke();
      g.beginPath(); g.arc(w / 2, h * 0.78, w * 0.1, Math.PI * 1.15, Math.PI * 1.85); g.stroke();
      break;
    case 'shock':
      for (const x of [ex, ex2]) { g.fillStyle = '#fff'; g.beginPath(); g.arc(x, ey, w * 0.06, 0, TAU); g.fill(); g.strokeStyle = ink; g.lineWidth = 4; g.stroke(); eye(x, ey, w * 0.022, w * 0.022); }
      g.fillStyle = ink; g.beginPath(); g.ellipse(w / 2, h * 0.7, w * 0.05, h * 0.1, 0, 0, TAU); g.fill();
      break;
    case 'sleepy':
      g.strokeStyle = ink; g.lineWidth = h * 0.045;
      for (const x of [ex, ex2]) { g.beginPath(); g.arc(x, ey, w * 0.05, Math.PI * 0.15, Math.PI * 0.85); g.stroke(); }
      g.beginPath(); g.arc(w / 2, h * 0.64, w * 0.04, 0, TAU); g.stroke();
      g.fillStyle = '#7f8cff'; g.font = `900 ${h * 0.16}px ${FONT}`; g.fillText('z', w * 0.74, h * 0.25); g.font = `900 ${h * 0.11}px ${FONT}`; g.fillText('z', w * 0.83, h * 0.13);
      break;
    case 'robot':
      g.fillStyle = '#16202c'; roundRect(g, w * 0.18, h * 0.26, w * 0.64, h * 0.3, 18); g.fill();
      g.fillStyle = '#39f0ff'; g.shadowColor = '#39f0ff'; g.shadowBlur = 16;
      roundRect(g, w * 0.27, h * 0.34, w * 0.14, h * 0.13, 6); g.fill(); roundRect(g, w * 0.59, h * 0.34, w * 0.14, h * 0.13, 6); g.fill();
      g.shadowBlur = 0;
      g.fillStyle = '#16202c'; for (let i = 0; i < 5; i++) g.fillRect(w * (0.36 + i * 0.06), h * 0.68, w * 0.035, h * 0.07);
      break;
    case 'zombie':
      eye(ex, ey, w * 0.05, h * 0.07);
      g.strokeStyle = ink; g.lineWidth = h * 0.04;
      g.beginPath(); g.moveTo(ex2 - 14, ey - 14); g.lineTo(ex2 + 14, ey + 14); g.moveTo(ex2 + 14, ey - 14); g.lineTo(ex2 - 14, ey + 14); g.stroke();
      g.beginPath(); g.moveTo(w * 0.36, h * 0.7); g.lineTo(w * 0.45, h * 0.66); g.lineTo(w * 0.55, h * 0.71); g.lineTo(w * 0.64, h * 0.66); g.stroke();
      g.lineWidth = h * 0.02; for (const x of [0.41, 0.5, 0.59]) { g.beginPath(); g.moveTo(w * x, h * 0.63); g.lineTo(w * x, h * 0.74); g.stroke(); }
      break;
    case 'ninja':
      g.fillStyle = '#1d1d24'; g.fillRect(0, 0, w, h * 0.26); g.fillRect(0, h * 0.52, w, h * 0.48);
      g.fillStyle = '#c62828'; g.fillRect(0, h * 0.18, w, h * 0.08);
      g.fillStyle = ink;
      g.beginPath(); g.ellipse(ex, ey, w * 0.05, h * 0.05, 0.2, 0, TAU); g.fill();
      g.beginPath(); g.ellipse(ex2, ey, w * 0.05, h * 0.05, -0.2, 0, TAU); g.fill();
      break;
    default:
      eye(ex, ey); eye(ex2, ey); smile();
  }
}

const PATTERN_COL = { heart: '#ff3d71', star: '#ffd23f', bolt: '#ffd23f', smile: '#ffd23f', tie: '#d62839', skull: '#ffffff', one: '#ffffff', flower: '#ff6fb5' };

function drawPattern(g, w, h, type, shirtHex, pantsHex) {
  const c = PATTERN_COL[type] || '#fff';
  const cx = w / 2;
  const cy = h * 0.45;
  g.lineJoin = 'round';
  g.lineCap = 'round';
  switch (type) {
    case 'heart':
      g.fillStyle = c; g.beginPath(); g.moveTo(cx, cy + 60);
      g.bezierCurveTo(cx - 95, cy - 5, cx - 50, cy - 75, cx, cy - 30); g.bezierCurveTo(cx + 50, cy - 75, cx + 95, cy - 5, cx, cy + 60); g.fill();
      break;
    case 'star':
      g.fillStyle = c; g.beginPath();
      for (let i = 0; i < 10; i++) { const r = i % 2 ? 30 : 70; const a = -Math.PI / 2 + i * Math.PI / 5; g.lineTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r); }
      g.closePath(); g.fill(); g.strokeStyle = 'rgba(0,0,0,0.25)'; g.lineWidth = 6; g.stroke();
      break;
    case 'bolt':
      g.fillStyle = c; g.beginPath();
      [[cx + 20, cy - 80], [cx - 40, cy + 10], [cx - 2, cy + 10], [cx - 22, cy + 80], [cx + 45, cy - 12], [cx + 6, cy - 12]].forEach(([x, y], i) => (i ? g.lineTo(x, y) : g.moveTo(x, y)));
      g.closePath(); g.fill(); g.strokeStyle = 'rgba(0,0,0,0.3)'; g.lineWidth = 6; g.stroke();
      break;
    case 'smile':
      g.fillStyle = c; g.beginPath(); g.arc(cx, cy, 62, 0, TAU); g.fill();
      g.fillStyle = '#1d1a1f'; g.beginPath(); g.ellipse(cx - 22, cy - 15, 7, 14, 0, 0, TAU); g.ellipse(cx + 22, cy - 15, 7, 14, 0, 0, TAU); g.fill();
      g.strokeStyle = '#1d1a1f'; g.lineWidth = 8; g.beginPath(); g.arc(cx, cy + 4, 32, 0.2 * Math.PI, 0.8 * Math.PI); g.stroke();
      break;
    case 'tie':
      g.fillStyle = '#ffffff'; g.beginPath(); g.moveTo(cx - 70, 0); g.lineTo(cx, 60); g.lineTo(cx + 70, 0); g.closePath(); g.fill();
      g.fillStyle = c; g.beginPath(); g.moveTo(cx - 16, 26); g.lineTo(cx + 16, 26); g.lineTo(cx + 10, 46); g.lineTo(cx + 28, 190); g.lineTo(cx, 222); g.lineTo(cx - 28, 190); g.lineTo(cx - 10, 46); g.closePath(); g.fill();
      break;
    case 'rainbow':
      ['#e63e3e', '#ff8c1a', '#ffd23f', '#7ed321', '#5ab8ff', '#8a4fff'].forEach((col, i) => { g.strokeStyle = col; g.lineWidth = 14; g.beginPath(); g.arc(cx, cy + 50, 100 - i * 14, Math.PI, TAU); g.stroke(); });
      g.fillStyle = '#fff'; for (const x of [cx - 90, cx + 90]) { g.beginPath(); g.arc(x, cy + 52, 22, 0, TAU); g.arc(x + 18, cy + 46, 18, 0, TAU); g.arc(x - 18, cy + 46, 16, 0, TAU); g.fill(); }
      break;
    case 'skull':
      g.fillStyle = c; g.beginPath(); g.arc(cx, cy - 10, 55, 0, TAU); g.fill(); g.fillRect(cx - 32, cy + 25, 64, 36);
      g.fillStyle = '#1d1a1f'; g.beginPath(); g.arc(cx - 22, cy - 10, 15, 0, TAU); g.arc(cx + 22, cy - 10, 15, 0, TAU); g.fill();
      g.beginPath(); g.moveTo(cx, cy + 6); g.lineTo(cx - 8, cy + 22); g.lineTo(cx + 8, cy + 22); g.fill();
      for (const x of [-18, -6, 6, 18]) g.fillRect(cx + x - 2, cy + 34, 4, 24);
      break;
    case 'one':
      g.fillStyle = c; g.font = `900 180px ${FONT}`; g.textAlign = 'center'; g.textBaseline = 'middle';
      g.lineWidth = 12; g.strokeStyle = 'rgba(0,0,0,0.35)'; g.strokeText('1', cx, cy + 10); g.fillText('1', cx, cy + 10);
      break;
    case 'flower':
      g.fillStyle = c; for (let i = 0; i < 6; i++) { const a = (i / 6) * TAU; g.beginPath(); g.arc(cx + Math.cos(a) * 36, cy + Math.sin(a) * 36, 28, 0, TAU); g.fill(); }
      g.fillStyle = '#ffd23f'; g.beginPath(); g.arc(cx, cy, 24, 0, TAU); g.fill();
      break;
    case 'overalls':
      g.fillStyle = pantsHex; g.fillRect(cx - 70, h * 0.45, 140, h * 0.55);
      g.fillRect(cx - 82, 0, 30, h * 0.5); g.fillRect(cx + 52, 0, 30, h * 0.5);
      g.fillStyle = '#ffd23f'; for (const x of [cx - 67, cx + 67]) { g.beginPath(); g.arc(x, h * 0.47, 9, 0, TAU); g.fill(); }
      g.fillStyle = 'rgba(0,0,0,0.18)'; g.fillRect(cx - 40, h * 0.6, 80, 40);
      break;
  }
}

function stripeTexture(baseHex, stripeHex) {
  return canvasTex(64, 64, (g, w, h) => {
    g.fillStyle = baseHex;
    g.fillRect(0, 0, w, h);
    g.fillStyle = stripeHex;
    for (let i = 0; i < 4; i++) g.fillRect(0, i * 16, w, 8);
  });
}

function baconTexture(hex) {
  return canvasTex(128, 128, (g, w, h) => {
    g.fillStyle = shade(hex, -0.15);
    g.fillRect(0, 0, w, h);
    for (let i = 0; i < 6; i++) {
      g.strokeStyle = i % 2 ? shade(hex, 0.25) : shade(hex, 0.45);
      g.lineWidth = 9;
      g.beginPath();
      for (let x = -10; x <= w + 10; x += 8) g.lineTo(x, i * 22 + 10 + Math.sin(x * 0.12 + i) * 6);
      g.stroke();
    }
  });
}

// ---------------------------------------------------------------------------

function headGeo() {
  const pts = [];
  const r = 0.62;
  const hh = 0.62;
  const cr = 0.18;
  pts.push(new THREE.Vector2(0, -hh));
  for (let i = 0; i <= 6; i++) {
    const a = -Math.PI / 2 + (i / 6) * (Math.PI / 2);
    pts.push(new THREE.Vector2(r - cr + Math.cos(a) * cr, -hh + cr + Math.sin(a) * cr));
  }
  for (let i = 0; i <= 6; i++) {
    const a = (i / 6) * (Math.PI / 2);
    pts.push(new THREE.Vector2(r - cr + Math.cos(a) * cr, hh - cr + Math.sin(a) * cr));
  }
  pts.push(new THREE.Vector2(0, hh));
  return new THREE.LatheGeometry(pts, 28);
}

const AV_GEO = {};
const AV_SHARED = new Set();
function avGeo(key, make) {
  if (!AV_GEO[key]) {
    AV_GEO[key] = make();
    AV_SHARED.add(AV_GEO[key]);
  }
  return AV_GEO[key];
}

function smoothMat(hex, o = {}) {
  return new THREE.MeshStandardMaterial({ color: hex, roughness: o.rough == null ? 0.5 : o.rough, metalness: o.metal || 0, ...o.extra });
}

class Avatar {
  constructor(skin, opts = {}) {
    this.root = new THREE.Group();
    this.body = new THREE.Group();
    this.root.add(this.body);
    this.opts = opts;
    this.phase = 0;
    this.t = 0;
    this.slapT = -1;
    this.pushT = -1;
    this.cheer = false;
    this.glove = null;
    this.mats = [];
    this.texs = [];
    this.ownGeos = [];
    this.setSkin(skin);
  }

  mat(hex, o) {
    const m = smoothMat(hex, o);
    this.mats.push(m);
    return m;
  }

  tex(t) {
    this.texs.push(t);
    return t;
  }

  mesh(geo, mat, parent, x = 0, y = 0, z = 0) {
    if (!AV_SHARED.has(geo) && !this.ownGeos.includes(geo)) this.ownGeos.push(geo);
    const m = new THREE.Mesh(geo, mat);
    m.position.set(x, y, z);
    m.castShadow = true;
    m.receiveShadow = true;
    parent.add(m);
    return m;
  }

  disposeBody() {
    while (this.body.children.length) this.body.remove(this.body.children[0]);
    for (const m of this.mats) m.dispose();
    for (const t of this.texs) t.dispose();
    this.mats = [];
    this.texs = [];
    for (const g of this.ownGeos || []) g.dispose();
    this.ownGeos = [];
  }

  geo(g) {
    return g;
  }

  setSkin(skin) {
    this.disposeBody();
    this.skin = { ...skin };
    const s = this.skin;
    const skinHex = SKIN_TONES[s.tone % SKIN_TONES.length].c;
    const shirtHex = PALETTE[s.shirt % PALETTE.length].c;
    const pantsHex = PALETTE[s.pants % PALETTE.length].c;
    const hairHex = HAIR_COLORS[s.hairColor % HAIR_COLORS.length].c;
    this.colors = { skin: skinHex, shirt: shirtHex, pants: pantsHex, hair: hairHex };
    const skinM = this.mat(skinHex);
    let shirtM;
    if (s.pattern === 'stripes') {
      const st = this.tex(stripeTexture(shirtHex, shade(shirtHex, isLight(shirtHex) ? -0.35 : 0.55)));
      shirtM = this.mat('#ffffff', { extra: { map: st } });
    } else shirtM = this.mat(shirtHex);
    const pantsM = this.mat(pantsHex);
    const shoeM = this.mat(isLight(pantsHex) ? '#3a3a44' : '#f2f2f2', { rough: 0.6 });
    const B = this.body;

    const legG = avGeo('leg', () => roundedBox(0.98, 2, 0.98, 0.12, 2));
    const legTopG = avGeo('legTop', () => roundedBox(1.0, 0.9, 1.0, 0.12, 2));
    const shoeG = avGeo('shoe', () => roundedBox(1.02, 0.36, 1.12, 0.12, 2));
    const torsoG = avGeo('torso', () => roundedBox(2, 2, 1, 0.14, 2));
    const armG = avGeo('arm', () => roundedBox(0.96, 2, 0.96, 0.14, 2));
    const sleeveG = avGeo('sleeve', () => roundedBox(1.02, 0.85, 1.02, 0.14, 2));
    const headG = avGeo('head', headGeo);

    // Ноги
    this.legL = new THREE.Group();
    this.legR = new THREE.Group();
    this.legL.position.set(0.5, 2, 0);
    this.legR.position.set(-0.5, 2, 0);
    B.add(this.legL, this.legR);
    for (const leg of [this.legL, this.legR]) {
      const full = s.bottom === 'pants';
      this.mesh(legG, full ? pantsM : skinM, leg, 0, -1, 0);
      if (s.bottom === 'shorts') this.mesh(legTopG, pantsM, leg, 0, -0.42, 0);
      this.mesh(shoeG, shoeM, leg, 0, -1.84, 0.04);
    }

    // Торс
    this.torso = this.mesh(torsoG, shirtM, B, 0, 3, 0);
    if (s.pattern !== 'plain' && s.pattern !== 'stripes') {
      const pt = this.tex(canvasTex(256, 256, (g, w, h) => drawPattern(g, w, h, s.pattern, shirtHex, pantsHex), { repeat: false }));
      const dec = new THREE.Mesh(avGeo('decal', () => new THREE.PlaneGeometry(1.86, 1.86)), this.mat('#ffffff', { extra: { map: pt, transparent: true, polygonOffset: true, polygonOffsetFactor: -2 } }));
      dec.position.set(0, 3, 0.505);
      B.add(dec);
    }
    if (s.bottom === 'skirt') {
      const sk = this.mesh(avGeo('skirt', () => new THREE.CylinderGeometry(1.08, 1.55, 1.25, 20, 1, true)), this.mat(pantsHex, { extra: { side: THREE.DoubleSide } }), B, 0, 1.55, 0);
      sk.scale.z = 0.62;
    }

    // Руки (вращение 'YXZ', чтобы шлепок шёл по горизонтали)
    this.armL = new THREE.Group();
    this.armR = new THREE.Group();
    this.armL.position.set(1.5, 3.75, 0);
    this.armR.position.set(-1.5, 3.75, 0);
    this.armL.rotation.order = 'YXZ';
    this.armR.rotation.order = 'YXZ';
    B.add(this.armL, this.armR);
    for (const arm of [this.armL, this.armR]) {
      this.mesh(armG, skinM, arm, 0, -0.75, 0);
      this.mesh(sleeveG, shirtM, arm, 0, -0.17, 0);
    }
    this.handR = new THREE.Group();
    this.handR.position.set(0, -1.7, 0);
    this.armR.add(this.handR);

    // Голова
    this.head = new THREE.Group();
    this.head.position.set(0, 4, 0);
    B.add(this.head);
    this.mesh(headG, skinM, this.head, 0, 0.62, 0);
    const faceTex = this.tex(canvasTex(320, 232, (g, w, h) => drawFace(g, w, h, s.face), { repeat: false }));
    const face = new THREE.Mesh(
      avGeo('face', () => new THREE.CylinderGeometry(0.628, 0.628, 0.9, 20, 1, true, -1.0, 2.0)),
      this.mat('#ffffff', { extra: { map: faceTex, transparent: true, polygonOffset: true, polygonOffsetFactor: -2 } }),
    );
    face.position.y = 0.62;
    this.head.add(face);

    this.buildHair(s.hair, hairHex);
    this.buildHat(s.hat, s.hair !== 'none' && s.hair !== 'mohawk');
    this.buildBack(s.back, hairHex, shirtHex);
    if (this.glove) this.setGlove(this.gloveType);
    this.trailType = s.trail;
  }

  buildHair(type, hex) {
    if (type === 'none') return;
    const H = this.head;
    const m = type === 'bacon' ? this.mat('#ffffff', { extra: { map: this.tex(baconTexture(hex)) }, rough: 0.7 }) : this.mat(hex, { rough: 0.7 });
    const cap = () => this.mesh(this.geo(roundedBox(1.38, 0.5, 1.38, 0.2, 2)), m, H, 0, 1.12, -0.02);
    const back = (h = 0.95, y = 0.72) => this.mesh(this.geo(roundedBox(1.36, h, 0.42, 0.16, 2)), m, H, 0, y, -0.5);
    switch (type) {
      case 'short':
        cap(); back();
        this.mesh(this.geo(roundedBox(1.2, 0.26, 0.32, 0.1, 2)), m, H, 0.08, 1.0, 0.52).rotation.z = 0.12;
        break;
      case 'long':
        cap(); back(2.0, 0.25);
        for (const sx of [-1, 1]) this.mesh(this.geo(roundedBox(0.3, 1.55, 0.95, 0.12, 2)), m, H, sx * 0.67, 0.5, -0.12);
        this.mesh(this.geo(roundedBox(1.25, 0.24, 0.3, 0.1, 2)), m, H, 0, 1.03, 0.52);
        break;
      case 'pigtails':
        cap(); back();
        for (const sx of [-1, 1]) {
          const p = this.mesh(avGeo('ball', () => new THREE.SphereGeometry(0.34, 14, 10)), m, H, sx * 0.88, 0.45, -0.2);
          p.scale.set(1, 1.7, 1);
          this.mesh(avGeo('tie', () => new THREE.SphereGeometry(0.14, 10, 8)), this.mat('#ff4d8d'), H, sx * 0.78, 0.98, -0.2);
        }
        break;
      case 'bacon':
        this.mesh(this.geo(roundedBox(1.42, 0.62, 1.42, 0.24, 2)), m, H, 0, 1.12, -0.02);
        back(0.85, 0.75);
        for (let i = 0; i < 5; i++) this.mesh(this.geo(roundedBox(0.34, 0.24, 0.5, 0.1, 1)), m, H, -0.55 + i * 0.27, 1.42, 0.2 - (i % 2) * 0.35).rotation.y = i * 0.5;
        break;
      case 'spiky':
        cap(); back();
        for (let i = 0; i < 7; i++) {
          const c = this.mesh(avGeo('spike', () => new THREE.ConeGeometry(0.24, 0.8, 6)), m, H, -0.5 + (i % 4) * 0.33, 1.42, i < 4 ? 0.12 : -0.3);
          c.rotation.set(i < 4 ? 0.3 : -0.4, 0, (i % 4 - 1.5) * -0.35);
        }
        break;
      case 'bun':
        cap(); back();
        this.mesh(avGeo('bun', () => new THREE.SphereGeometry(0.42, 16, 12)), m, H, 0, 1.45, -0.35);
        break;
      case 'bob':
        cap(); back(1.15, 0.62);
        for (const sx of [-1, 1]) this.mesh(this.geo(roundedBox(0.3, 1.15, 1.05, 0.12, 2)), m, H, sx * 0.68, 0.62, -0.06);
        this.mesh(this.geo(roundedBox(1.3, 0.3, 0.3, 0.1, 2)), m, H, 0, 1.0, 0.52);
        break;
      case 'mohawk':
        this.mesh(this.geo(roundedBox(0.34, 0.8, 1.35, 0.14, 2)), m, H, 0, 1.4, -0.05);
        break;
    }
  }

  buildHat(type, hasHair) {
    if (type === 'none') return;
    const H = this.head;
    const top = hasHair ? 1.36 : 1.24;
    const gold = this.mat('#ffcc33', { rough: 0.25, metal: 1 });
    switch (type) {
      case 'crown': {
        this.mesh(new THREE.CylinderGeometry(0.52, 0.5, 0.32, 18, 1, true), this.mat('#ffcc33', { rough: 0.25, metal: 1, extra: { side: THREE.DoubleSide } }), H, 0, top + 0.12, 0);
        for (let i = 0; i < 6; i++) {
          const a = (i / 6) * TAU;
          this.mesh(avGeo('crownSpike', () => new THREE.ConeGeometry(0.12, 0.34, 4)), gold, H, Math.sin(a) * 0.5, top + 0.43, Math.cos(a) * 0.5);
          this.mesh(avGeo('gem', () => new THREE.OctahedronGeometry(0.08)), this.mat(i % 2 ? '#e63e3e' : '#3ea6ff', { rough: 0.1, metal: 0.3 }), H, Math.sin(a) * 0.53, top + 0.12, Math.cos(a) * 0.53);
        }
        break;
      }
      case 'tophat': {
        const blk = this.mat('#1f1f26', { rough: 0.6 });
        this.mesh(new THREE.CylinderGeometry(0.85, 0.85, 0.07, 24), blk, H, 0, top + 0.02, 0);
        this.mesh(new THREE.CylinderGeometry(0.5, 0.48, 0.95, 24), blk, H, 0, top + 0.5, 0);
        this.mesh(new THREE.CylinderGeometry(0.505, 0.495, 0.18, 24), this.mat('#d62839'), H, 0, top + 0.15, 0);
        break;
      }
      case 'cap': {
        const c = this.mat('#e63e3e');
        this.mesh(new THREE.SphereGeometry(0.7, 20, 10, 0, TAU, 0, Math.PI / 2), c, H, 0, top - 0.28, 0);
        this.mesh(this.geo(roundedBox(1.0, 0.08, 0.65, 0.04, 1)), c, H, 0, top - 0.24, 0.82);
        this.mesh(new THREE.SphereGeometry(0.08, 8, 6), this.mat('#ffffff'), H, 0, top + 0.42, 0);
        break;
      }
      case 'beanie': {
        const c = this.mat('#5ab8ff', { rough: 0.9 });
        this.mesh(new THREE.SphereGeometry(0.72, 20, 10, 0, TAU, 0, Math.PI / 2), c, H, 0, top - 0.3, 0);
        const rim = this.mesh(new THREE.TorusGeometry(0.69, 0.13, 8, 24), this.mat('#ffffff', { rough: 0.9 }), H, 0, top - 0.25, 0);
        rim.rotation.x = Math.PI / 2;
        this.mesh(new THREE.SphereGeometry(0.22, 12, 8), this.mat('#ffffff', { rough: 1 }), H, 0, top + 0.5, 0);
        break;
      }
      case 'cowboy': {
        const c = this.mat('#8a5a35', { rough: 0.8 });
        const brim = this.mesh(new THREE.CylinderGeometry(1.15, 1.15, 0.08, 28), c, H, 0, top - 0.02, 0);
        brim.scale.z = 0.85;
        this.mesh(new THREE.CylinderGeometry(0.42, 0.52, 0.62, 20), c, H, 0, top + 0.3, 0);
        this.mesh(new THREE.CylinderGeometry(0.53, 0.53, 0.12, 20), this.mat('#2b1a10'), H, 0, top + 0.08, 0);
        break;
      }
      case 'catears': {
        const c = this.mat(this.colors.hair, { rough: 0.8 });
        const pinkM = this.mat('#ff9cc4');
        for (const sx of [-1, 1]) {
          const e = this.mesh(new THREE.ConeGeometry(0.3, 0.55, 4), c, H, sx * 0.4, top + 0.18, 0);
          e.rotation.set(0, Math.PI / 4, sx * -0.25);
          const i2 = this.mesh(new THREE.ConeGeometry(0.17, 0.36, 4), pinkM, H, sx * 0.4, top + 0.14, 0.12);
          i2.rotation.set(0, Math.PI / 4, sx * -0.25);
        }
        break;
      }
      case 'bunny': {
        const w = this.mat('#ffffff');
        const pk = this.mat('#ffb3d1');
        for (const sx of [-1, 1]) {
          const g = new THREE.Group();
          g.position.set(sx * 0.27, top - 0.05, -0.05);
          g.rotation.z = sx * -0.18;
          H.add(g);
          const e = this.mesh(new THREE.CapsuleGeometry(0.17, 0.95, 6, 12), w, g, 0, 0.65, 0);
          e.scale.z = 0.6;
          const inner = this.mesh(new THREE.CapsuleGeometry(0.09, 0.7, 4, 8), pk, g, 0, 0.65, 0.06);
          inner.scale.z = 0.4;
        }
        break;
      }
      case 'halo': {
        const h = new THREE.Mesh(new THREE.TorusGeometry(0.45, 0.07, 8, 32), new THREE.MeshBasicMaterial({ color: 0xffe066, toneMapped: false }));
        h.rotation.x = Math.PI / 2;
        h.position.y = top + 0.55;
        this.mats.push(h.material);
        H.add(h);
        this.halo = h;
        break;
      }
      case 'horns': {
        const r = this.mat('#d62839', { rough: 0.35 });
        for (const sx of [-1, 1]) {
          const c = this.mesh(new THREE.ConeGeometry(0.15, 0.5, 10), r, H, sx * 0.38, top + 0.1, 0.12);
          c.rotation.z = sx * -0.45;
        }
        break;
      }
      case 'headphones': {
        const d = this.mat('#2b2f3a', { rough: 0.4 });
        const band = this.mesh(new THREE.TorusGeometry(0.72, 0.07, 8, 24, Math.PI), d, H, 0, 0.62, 0);
        band.scale.y = 1.05;
        for (const sx of [-1, 1]) {
          const cup = this.mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.22, 16), this.mat('#ff6fb5', { rough: 0.35 }), H, sx * 0.72, 0.55, 0);
          cup.rotation.z = Math.PI / 2;
        }
        break;
      }
      case 'flowers': {
        const cols = ['#ff6fb5', '#ffd23f', '#ffffff', '#c3a6ff'];
        for (let i = 0; i < 10; i++) {
          const a = (i / 10) * TAU;
          this.mesh(avGeo('petal', () => new THREE.IcosahedronGeometry(0.15, 0)), this.mat(cols[i % 4]), H, Math.sin(a) * 0.62, top - 0.08, Math.cos(a) * 0.62);
        }
        break;
      }
      case 'viking': {
        const m = this.mat('#9aa3ad', { rough: 0.3, metal: 0.8 });
        this.mesh(new THREE.SphereGeometry(0.72, 20, 10, 0, TAU, 0, Math.PI / 2), m, H, 0, top - 0.3, 0);
        const rim = this.mesh(new THREE.TorusGeometry(0.7, 0.08, 8, 24), gold, H, 0, top - 0.28, 0);
        rim.rotation.x = Math.PI / 2;
        for (const sx of [-1, 1]) {
          const c = this.mesh(new THREE.ConeGeometry(0.16, 0.75, 10), this.mat('#f4ecd8'), H, sx * 0.85, top + 0.15, 0);
          c.rotation.z = sx * -1.0;
        }
        break;
      }
      case 'party': {
        const pt = this.tex(stripeTexture('#ff6fb5', '#ffd23f'));
        const c = this.mesh(new THREE.ConeGeometry(0.38, 0.9, 20), this.mat('#ffffff', { extra: { map: pt } }), H, 0.1, top + 0.4, 0);
        c.rotation.z = -0.15;
        this.mesh(new THREE.SphereGeometry(0.13, 10, 8), this.mat('#5ab8ff'), H, 0.17, top + 0.86, 0);
        break;
      }
      case 'bow': {
        const m = this.mat('#ff4d8d');
        const g = new THREE.Group();
        g.position.set(0.38, top - 0.02, 0.15);
        g.rotation.z = -0.3;
        H.add(g);
        for (const sx of [-1, 1]) {
          const l = this.mesh(new THREE.SphereGeometry(0.3, 12, 8), m, g, sx * 0.3, 0, 0);
          l.scale.set(1, 0.65, 0.35);
        }
        this.mesh(new THREE.SphereGeometry(0.13, 10, 8), m, g, 0, 0, 0.04);
        break;
      }
    }
  }

  buildBack(type, hairHex, shirtHex) {
    this.wings = null;
    this.cape = null;
    this.jet = null;
    if (type === 'none') return;
    const B = this.body;
    const wingShape = (bat) => {
      const s = new THREE.Shape();
      s.moveTo(0, 0);
      if (bat) {
        s.lineTo(0.4, 0.7); s.lineTo(1.4, 1.3); s.lineTo(2.3, 1.2);
        s.quadraticCurveTo(2.0, 0.6, 2.2, 0.1); s.quadraticCurveTo(1.7, 0.2, 1.6, -0.35);
        s.quadraticCurveTo(1.1, -0.1, 0.9, -0.6); s.quadraticCurveTo(0.5, -0.2, 0, -0.2);
      } else {
        s.quadraticCurveTo(0.4, 1.0, 1.3, 1.5); s.quadraticCurveTo(2.2, 1.7, 2.3, 1.1);
        s.quadraticCurveTo(2.2, 0.4, 1.7, 0.1); s.quadraticCurveTo(1.8, -0.4, 1.2, -0.7);
        s.quadraticCurveTo(0.6, -0.6, 0, -0.2);
      }
      return new THREE.ExtrudeGeometry(s, { depth: 0.08, bevelEnabled: false, curveSegments: 6 });
    };
    if (type === 'angel' || type === 'bat' || type === 'fairy') {
      this.wings = [];
      const mat = type === 'angel' ? this.mat('#ffffff', { rough: 0.8 }) : type === 'bat' ? this.mat('#3b1f4f', { rough: 0.5, extra: { side: THREE.DoubleSide } })
        : this.mat('#a8e4ff', { rough: 0.2, extra: { transparent: true, opacity: 0.6, side: THREE.DoubleSide } });
      for (const sx of [-1, 1]) {
        const pivot = new THREE.Group();
        pivot.position.set(sx * 0.2, 3.4, -0.55);
        B.add(pivot);
        let geo;
        if (type === 'fairy') {
          geo = this.geo(new THREE.CircleGeometry(1, 20));
          const up = this.mesh(geo, mat, pivot, 0.9, 0.55, 0);
          up.scale.set(1.0, 0.65, 1);
          up.rotation.z = 0.5;
          const lo = this.mesh(geo, mat, pivot, 0.7, -0.45, 0);
          lo.scale.set(0.7, 0.45, 1);
          lo.rotation.z = -0.5;
        } else {
          geo = this.geo(wingShape(type === 'bat'));
          this.mesh(geo, mat, pivot, 0, 0, -0.04);
        }
        pivot.scale.x = -sx;
        pivot.rotation.y = sx * 0.5;
        pivot.userData.side = sx;
        this.wings.push(pivot);
      }
    } else if (type === 'cape') {
      const pivot = new THREE.Group();
      pivot.position.set(0, 3.95, -0.56);
      B.add(pivot);
      const c = this.mesh(this.geo(new THREE.PlaneGeometry(1.9, 2.9, 1, 4)), this.mat('#d62839', { extra: { side: THREE.DoubleSide } }), pivot, 0, -1.45, 0);
      c.rotation.y = Math.PI;
      this.cape = pivot;
    } else if (type === 'backpack') {
      const m = this.mat('#ff8c1a', { rough: 0.7 });
      this.mesh(this.geo(roundedBox(1.5, 1.7, 0.7, 0.2, 2)), m, B, 0, 3.0, -0.88);
      this.mesh(this.geo(roundedBox(1.0, 0.6, 0.25, 0.1, 2)), this.mat('#ffd23f'), B, 0, 2.6, -1.25);
    } else if (type === 'tail') {
      const curve = new THREE.CatmullRomCurve3([V3(0, 2.3, -0.45), V3(0, 2.0, -1.0), V3(0, 2.3, -1.6), V3(0, 3.1, -1.8), V3(0, 3.5, -1.55)]);
      this.mesh(this.geo(new THREE.TubeGeometry(curve, 20, 0.17, 8)), this.mat(hairHex, { rough: 0.8 }), B);
    } else if (type === 'sword') {
      const g = new THREE.Group();
      g.position.set(0, 3.1, -0.65);
      g.rotation.z = 0.75;
      B.add(g);
      this.mesh(this.geo(roundedBox(0.28, 2.8, 0.1, 0.04, 1)), this.mat('#dfe6ee', { rough: 0.15, metal: 0.9 }), g, 0, 0.6, 0);
      this.mesh(this.geo(roundedBox(1.0, 0.18, 0.22, 0.06, 1)), this.mat('#ffcc33', { rough: 0.25, metal: 1 }), g, 0, -0.85, 0);
      this.mesh(this.geo(roundedBox(0.2, 0.7, 0.2, 0.06, 1)), this.mat('#5a3420'), g, 0, -1.3, 0);
    } else if (type === 'jetpack') {
      const m = this.mat('#9aa3ad', { rough: 0.3, metal: 0.7 });
      for (const sx of [-1, 1]) {
        this.mesh(new THREE.CylinderGeometry(0.34, 0.34, 1.5, 14), m, B, sx * 0.4, 3.0, -0.88);
        this.mesh(new THREE.ConeGeometry(0.34, 0.45, 14), this.mat('#e63e3e'), B, sx * 0.4, 3.97, -0.88);
        this.mesh(new THREE.CylinderGeometry(0.22, 0.3, 0.3, 12), this.mat('#2b2f3a'), B, sx * 0.4, 2.1, -0.88);
      }
      this.jet = true;
    }
  }

  // Перчатка для шлёп-битвы.
  setGlove(type) {
    if (this.glove) {
      this.handR.remove(this.glove);
      this.glove = null;
    }
    this.gloveType = type;
    if (!type) return;
    const g = new THREE.Group();
    const col = type === 'mega' ? '#ffcc33' : type === 'blue' ? '#2f7cf6' : '#e63e3e';
    const m = this.mat(col, { rough: 0.35 });
    const fist = new THREE.Mesh(avGeo('glove', () => roundedBox(1.5, 1.5, 1.5, 0.5, 3)), m);
    fist.position.y = -0.35;
    fist.castShadow = true;
    g.add(fist);
    const cuff = new THREE.Mesh(avGeo('cuff', () => new THREE.CylinderGeometry(0.62, 0.62, 0.45, 16)), this.mat('#ffffff'));
    cuff.position.y = 0.45;
    g.add(cuff);
    const thumb = new THREE.Mesh(avGeo('thumb', () => roundedBox(0.45, 0.8, 0.45, 0.2, 2)), m);
    thumb.position.set(0.7, -0.2, 0.25);
    thumb.rotation.z = 0.4;
    g.add(thumb);
    this.handR.add(g);
    this.glove = g;
  }

  setGloveColor(hex) {
    if (!this.glove) return;
    this.glove.children[0].material.color.set(hex);
    this.glove.children[2].material.color.set(hex);
  }

  // Части тела для разлёта при смерти.
  pieces() {
    const out = [];
    this.body.updateMatrixWorld(true);
    const take = (obj) => {
      obj.traverse((o) => {
        if (o.isMesh) {
          const m = new THREE.Mesh(o.geometry, o.material);
          o.getWorldPosition(m.position);
          o.getWorldQuaternion(m.quaternion);
          o.getWorldScale(m.scale);
          m.castShadow = true;
          out.push(m);
        }
      });
    };
    take(this.body);
    return out;
  }

  animate(dt, st) {
    this.t += dt;
    const t = this.t;
    let la = 0, ra = 0, ll = 0, rl = 0, laz = 0, raz = 0, ray = 0, lay = 0;
    const k = 16;
    if (st.climbing) {
      const c = Math.sin(t * 11);
      la = -2.7 + c * 0.45; ra = -2.7 - c * 0.45; ll = -0.5 + c * 0.4; rl = -0.5 - c * 0.4;
    } else if (!st.grounded) {
      if (st.vy > 0) { la = -2.9; ra = -2.9; ll = 0.35; rl = -0.35; }
      else { la = -2.5; ra = -2.5; laz = -0.35; raz = 0.35; ll = 0.25; rl = -0.25; }
    } else if (st.speed > 0.6) {
      this.phase += dt * st.speed * 0.62;
      const amp = Math.min(1, st.speed / 14) * 0.95;
      const s = Math.sin(this.phase) * amp;
      ll = s; rl = -s; la = -s * 0.95; ra = s * 0.95;
    } else {
      const s = Math.sin(t * 1.7) * 0.05;
      la = s; ra = -s; laz = -0.04; raz = 0.04;
    }
    if (this.cheer) {
      la = -2.8 + Math.sin(t * 12) * 0.35; ra = -2.8 - Math.sin(t * 12) * 0.35; laz = -0.3; raz = 0.3;
    }
    if (this.pushT >= 0) {
      this.pushT += dt;
      const p = this.pushT / 0.32;
      if (p >= 1) this.pushT = -1;
      else { const a = p < 0.35 ? p / 0.35 : 1 - (p - 0.35) / 0.65; la = ra = -1.55 * a + la * (1 - a); laz = raz = 0; }
    }
    let slap = false;
    if (this.slapT >= 0) {
      this.slapT += dt;
      const p = this.slapT / 0.36;
      if (p >= 1) this.slapT = -1;
      else {
        slap = true;
        ra = -1.45;
        raz = 0;
        if (p < 0.3) ray = lerp(0, -1.5, p / 0.3);
        else if (p < 0.55) ray = lerp(-1.5, 0.9, (p - 0.3) / 0.25);
        else ray = lerp(0.9, 0, (p - 0.55) / 0.45);
      }
    }
    const L = this.legL.rotation;
    const Rr = this.legR.rotation;
    L.x = damp(L.x, ll, k, dt);
    Rr.x = damp(Rr.x, rl, k, dt);
    const A = this.armL.rotation;
    const B = this.armR.rotation;
    A.x = damp(A.x, la, k, dt);
    A.z = damp(A.z, laz, k, dt);
    A.y = damp(A.y, lay, k, dt);
    if (slap) { B.x = ra; B.y = ray; B.z = 0; }
    else { B.x = damp(B.x, ra, k, dt); B.z = damp(B.z, raz, k, dt); B.y = damp(B.y, ray, k, dt); }
    this.head.rotation.y = damp(this.head.rotation.y, 0, 8, dt);
    if (this.halo) this.halo.position.y = 1.85 + Math.sin(t * 2.5) * 0.06 + (this.skin.hair !== 'none' ? 0.12 : 0);
    if (this.wings) {
      const flap = (!st.grounded ? Math.sin(t * 14) * 0.5 : Math.sin(t * 2.2) * 0.12);
      for (const w of this.wings) w.rotation.y = w.userData.side * (0.55 + flap);
    }
    if (this.cape) {
      const target = 0.12 + Math.min(1.1, st.speed / 16) + (!st.grounded && st.vy < 0 ? 0.6 : 0) + Math.sin(t * 9) * 0.05 * Math.min(1, st.speed / 8);
      this.cape.rotation.x = damp(this.cape.rotation.x, target, 6, dt);
    }
  }

  dispose() {
    this.disposeBody();
    if (this.root.parent) this.root.parent.remove(this.root);
  }
}

function isLight(hex) {
  const [r, g, b] = hexToRgb(hex);
  return r * 0.299 + g * 0.587 + b * 0.114 > 160;
}

// ---------------------------------------------------------------------------
// След за персонажем: лента (радуга/огонь) или частицы (сердечки, звёзды, блёстки, пузыри).

class Trail {
  constructor(type) {
    this.type = type;
    this.timer = 0;
    this.pts = [];
    this.N = 26;
    this.mesh = null;
    if (type === 'rainbow' || type === 'fire') {
      const g = new THREE.BufferGeometry();
      this.pos = new Float32Array(this.N * 2 * 3);
      this.col = new Float32Array(this.N * 2 * 4);
      g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
      g.setAttribute('color', new THREE.BufferAttribute(this.col, 4));
      const idx = [];
      for (let i = 0; i < this.N - 1; i++) {
        const a = i * 2;
        idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
      }
      g.setIndex(idx);
      this.mesh = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ vertexColors: true, transparent: true, side: THREE.DoubleSide, depthWrite: false, toneMapped: false }));
      this.mesh.frustumCulled = false;
      this.mesh.renderOrder = 3;
      R.scene.add(this.mesh);
    }
  }

  update(dt, pos, moving, visible) {
    this.timer += dt;
    if (this.mesh) {
      this.mesh.visible = visible;
      if (this.timer > 0.025) {
        this.timer = 0;
        if (moving) this.pts.unshift(pos.clone());
        else if (this.pts.length) this.pts.pop();
        if (this.pts.length > this.N) this.pts.length = this.N;
      }
      const n = this.pts.length;
      const c = new THREE.Color();
      for (let i = 0; i < this.N; i++) {
        const p = this.pts[Math.min(i, n - 1)] || pos;
        const k = i / (this.N - 1);
        const w = 0.85 * (1 - k * 0.6);
        this.pos.set([p.x, p.y + w, p.z, p.x, p.y - w, p.z], i * 6);
        if (this.type === 'rainbow') c.setHSL((k * 0.9 + this.timer * 0) % 1, 0.95, 0.6);
        else c.setRGB(1, lerp(0.9, 0.2, k), lerp(0.3, 0.05, k));
        const a = i < n ? (1 - k) * 0.85 : 0;
        this.col.set([c.r, c.g, c.b, a, c.r, c.g, c.b, a * (this.type === 'fire' ? 0.3 : 1)], i * 8);
      }
      this.mesh.geometry.attributes.position.needsUpdate = true;
      this.mesh.geometry.attributes.color.needsUpdate = true;
      this.mesh.geometry.computeBoundingSphere();
      if (this.type === 'fire' && moving && visible && Math.random() < dt * 30) {
        FX.emit({ x: pos.x + rand(-0.4, 0.4), y: pos.y + rand(-0.8, 0.6), z: pos.z + rand(-0.4, 0.4), vy: rand(2, 5), life: 0.5, size: rand(0.25, 0.45), color: pick(['#ffb02e', '#ff6a1a', '#ffd34a']), glow: true, grav: -4 });
      }
      return;
    }
    if (!moving || !visible || this.type === 'none') return;
    if (this.timer < 0.07) return;
    this.timer = 0;
    const p = V3(pos.x + rand(-0.6, 0.6), pos.y + rand(-1, 1), pos.z + rand(-0.6, 0.6));
    if (this.type === 'hearts') FX.sprite('heart', p, { color: pick(['#ff4d8d', '#ff7ab0', '#ff2e63']), size: rand(0.5, 0.8), life: 1, vy: 1.5 });
    else if (this.type === 'stars') FX.sprite('star', p, { color: pick(['#ffd23f', '#fff1a8', '#ffc21a']), size: rand(0.5, 0.8), life: 0.9, vy: 1 });
    else if (this.type === 'sparkle') FX.emit({ x: p.x, y: p.y, z: p.z, vy: rand(0.5, 2), life: 0.7, size: rand(0.15, 0.3), color: pick(['#ffffff', '#bfe3ff', '#ffe9a8']), glow: true, grav: 0 });
    else if (this.type === 'bubbles') FX.sprite('glow', p, { color: pick(['#8fe3ff', '#bdf3ff', '#a8c8ff']), size: rand(0.4, 0.8), life: 1.2, vy: 2, grow: 0.6 });
  }

  dispose() {
    if (this.mesh) {
      R.scene.remove(this.mesh);
      this.mesh.geometry.dispose();
      this.mesh.material.dispose();
    }
  }
}
