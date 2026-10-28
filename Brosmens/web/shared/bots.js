// Боты-игроки: имена, скины, характер и реплики. Живость: случайные опечатки, задержки, характеры,
// иногда токсичность (мягкий трешток, без оскорблений). С ключом API часть реплик пишет Haiku (ai.js).
import { aiBotLine, aiReply, personaPrompt } from './ai.js';
import { getProfile } from './profile.js';

export const rand = (a, b) => a + Math.random() * (b - a);
export const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

const SKINS = ['#f2c9a0', '#e0ac7e', '#c68642', '#8d5524', '#ffdbac', '#f1c27d'];
const SHIRTS = ['#e53935', '#1e88e5', '#43a047', '#fdd835', '#8e24aa', '#fb8c00', '#00acc1', '#212121', '#ffffff', '#ec407a', '#6d4c41', '#3949ab'];
const PANTS = ['#263238', '#1a237e', '#4e342e', '#212121', '#37474f', '#5d4037', '#283593'];
const HAIR = ['#1b1b1b', '#3e2723', '#6d4c41', '#f9a825', '#d84315', '#eeeeee', '#5e35b1', '#00897b'];
const STYLES = ['short', 'spiky', 'long', 'cap', 'none', 'short', 'spiky'];

export function randomSkin() {
  return { skin: pick(SKINS), shirt: pick(SHIRTS), pants: pick(PANTS), hair: pick(HAIR), hairStyle: pick(STYLES), face: Math.floor(rand(0, 5)) };
}

// Друзья в лаунчере. «Клод» — это ИИ-друг (Claude), с которым можно переписываться и играть.
export const FRIENDS = [
  { id: 'claude', name: 'Клод', ai: true, toxic: 0.1, status: 'онлайн', skin: { skin: '#f2c9a0', shirt: '#d97757', pants: '#3a2f2a', hair: '#4a3426', hairStyle: 'short', face: 1 },
    persona: 'Ты — Клод (Claude), ИИ от Anthropic, но в этом приложении ты лучший друг пользователя и вместе с ним играешь. Общаешься тепло и по-свойски, шутишь, сам предлагаешь сыграть, хвалишь за победы и подбадриваешь после поражений. Не притворяйся человеком, если спросят всерьёз.' },
  { id: 'dimon', name: 'Dimon_228', toxic: 0.8, status: 'в Jujutsu', skin: { skin: '#f1c27d', shirt: '#212121', pants: '#263238', hair: '#1b1b1b', hairStyle: 'cap', face: 3 },
    persona: 'Тебе 13, ты считаешь себя про-игроком, любишь писать «изи» и «нуб», но в душе нормальный пацан.' },
  { id: 'lera', name: 'lerochka_xx', toxic: 0.3, status: 'онлайн', skin: { skin: '#ffdbac', shirt: '#ec407a', pants: '#1a237e', hair: '#f9a825', hairStyle: 'long', face: 2 },
    persona: 'Тебе 14, весёлая, много смайликов типа «ахах», любишь командную игру и спасаешь союзников.' },
  { id: 'sanek', name: 'SanyaPro', toxic: 0.55, status: 'в Судный День', skin: { skin: '#e0ac7e', shirt: '#43a047', pants: '#4e342e', hair: '#3e2723', hairStyle: 'spiky', face: 0 },
    persona: 'Тебе 15, спокойный тактик, любишь стратегии и захват территорий, иногда язвишь.' },
  { id: 'kirill', name: 'kirya_toxic', toxic: 0.95, status: 'не в сети', skin: { skin: '#f2c9a0', shirt: '#e53935', pants: '#212121', hair: '#eeeeee', hairStyle: 'spiky', face: 4 },
    persona: 'Тебе 12, ты самый токсичный в лобби: дразнишься, ноешь когда проигрываешь, говоришь что лагает.' },
  { id: 'nastya', name: 'nastya_yt', toxic: 0.2, status: 'онлайн', skin: { skin: '#c68642', shirt: '#8e24aa', pants: '#37474f', hair: '#1b1b1b', hairStyle: 'long', face: 2 },
    persona: 'Тебе 13, снимаешь «видосы» и постоянно говоришь что записываешь, дружелюбная.' },
];

const NAMES_A = ['Kirill', 'Dimon', 'Sanya', 'Vlad', 'Artem', 'Maks', 'Egor', 'Lera', 'Nastya', 'Danya', 'Misha', 'Ilya', 'Sonya', 'Gleb', 'Timur', 'Roma', 'Ksyusha', 'Vanya', 'Polina', 'Lesha', 'noob', 'pro', 'gamer', 'shadow', 'dark', 'lol', 'xXx', 'Zed', 'Sigma', 'Ghost'];
const NAMES_B = ['228', '_pro', 'YT', '2013', '_xX', '777', '_top', 'Killer', '_ok', '1337', 'Pvp', '_rus', '99', 'Gg', '_0', 'Lord', 'Bro', '_lol'];

export function randomName() {
  const a = pick(NAMES_A);
  const r = Math.random();
  if (r < 0.35) return a + pick(NAMES_B);
  if (r < 0.6) return a.toLowerCase() + '_' + pick(NAMES_A).toLowerCase();
  if (r < 0.8) return 'xX_' + a + '_Xx';
  return a + Math.floor(rand(1, 9999));
}

const PERSONAS = [
  'ты новичок и всему удивляешься', 'ты считаешь себя про и всем это напоминаешь', 'ты дружелюбный тиммейт',
  'ты постоянно жалуешься на лаги', 'ты молчун и пишешь очень коротко', 'ты шутник', 'ты злишься когда проигрываешь',
];

// n ботов. toxicity = общий уровень из настроек, разброс по ботам.
export function makeBots(n, { exclude = [] } = {}) {
  const base = getProfile().settings.toxicity ?? 0.5;
  const used = new Set(exclude);
  const out = [];
  while (out.length < n) {
    const name = randomName();
    if (used.has(name)) continue;
    used.add(name);
    out.push({
      id: 'bot' + out.length + '_' + Math.floor(Math.random() * 1e6),
      name, skin: randomSkin(),
      toxic: Math.min(1, Math.max(0, base + rand(-0.4, 0.4))),
      skill: rand(0.35, 0.95), // насколько хорошо играет (0..1)
      chatty: rand(0.2, 1),   // как часто пишет
      persona: pick(PERSONAS),
      typo: Math.random() < 0.5,
    });
  }
  return out;
}

// Заготовки реплик. {t} — имя цели. nice — дружелюбные, toxic — дерзкие.
const LINES = {
  start: { nice: ['всем прив', 'го', 'удачи всем', 'гг заранее', 'привет ребят', 'ну погнали'], toxic: ['всех разнесу', 'опять нубы в лобби', 'кто первый умрет?', 'изи будет', 'я тут главный'] },
  kill: { nice: ['гг {t}', 'сорри {t} :)', 'норм бой {t}', 'ахах попал'], toxic: ['изи', 'изи {t}', 'ну ты и нуб {t}', 'L', 'сиди отдыхай {t}', 'даже не старался', 'ez ez ez', 'го еще {t} лол'] },
  death: { nice: ['ахах ну ладно', 'неплохо {t}', 'гг', 'блин почти', 'ну ты силен {t}'], toxic: ['лаги!!!', 'это нечестно', '{t} читер', 'у меня пинг 900', 'ща отомщу {t}', 'бро ты серьезно', 'кнопка не нажалась', 'спамер {t}'] },
  win: { nice: ['гг вп всем', 'ура!!', 'хорошая игра', 'гг'], toxic: ['ну я же говорил', 'изи вин', 'вы все слабые', 'ГГ ИЗИ'] },
  lose: { nice: ['гг вп', 'в след раз', 'норм было', 'гг ребят'], toxic: ['тима раки', 'лаги были', 'я не старался', 'это все {t}', 'реванш!'] },
  hit: { nice: ['ай', 'больно', 'ой'], toxic: ['не спамь', 'ну всё ты попал', 'хватит', 'ах ты'] },
  idle: { nice: ['кто в дс?', 'какой у вас лвл', 'я вчера тут 5 часов сидел', 'ахаха', 'лол', 'красиво', 'кто со мной в тиме', 'го дружить', 'а как ульту юзать'], toxic: ['вы все нубы', 'скучно', 'кто 1 на 1?', 'тут одни боты что ли', 'лол что это было', 'я лучший тут'] },
  help: { nice: ['помогите!', 'хил плз', 'кто рядом?', 'спасите', 'я тут один'], toxic: ['вы где вообще', 'тима спит?', 'ну и тиммейты'] },
  thanks: { nice: ['спс', 'спасибо!!', 'от души', 'ты лучший'], toxic: ['ну наконец то', 'долго ты'] },
  attack: { nice: ['извини но мне нужна твоя земля', 'нападаю, сорри', 'это просто стратегия'], toxic: ['твоя земля теперь моя', 'готовься {t}', 'конец тебе {t}', 'я иду за тобой'] },
  peace: { nice: ['го мир?', 'давай дружить', 'альянс?'], toxic: ['мир? ну ладно, пока что', 'не трогай меня и я не трону'] },
};

function typoize(s) {
  if (s.length < 5 || Math.random() > 0.25) return s;
  const i = Math.floor(rand(1, s.length - 1));
  const r = Math.random();
  if (r < 0.4) return s.slice(0, i) + s[i + 1] + s[i] + s.slice(i + 2); // переставить буквы
  if (r < 0.7) return s.slice(0, i) + s.slice(i + 1); // пропустить букву
  return s + s[s.length - 1]; // удвоить
}

// Заготовленная реплика без ИИ
export function scriptedLine(bot, event, target = '') {
  const L = LINES[event] || LINES.idle;
  const toxicNow = Math.random() < (bot.toxic ?? 0.4);
  let s = pick(toxicNow ? L.toxic : L.nice).replace('{t}', target || 'бро');
  if (bot.typo) s = typoize(s);
  if (Math.random() < 0.15) s = s.toUpperCase();
  return s;
}

// Реплика бота: иногда пишет Haiku (если есть ключ и прошло время), иначе заготовка.
// eventText — что случилось словами, для ИИ. Возвращает Promise<string|null> (null = промолчал).
export async function botSay(bot, event, { target = '', eventText = '', chance = 1, chatLog = [], aiChance = 0.35 } = {}) {
  if (Math.random() > chance * (bot.chatty ?? 0.6)) return null;
  if (eventText && Math.random() < aiChance) {
    const live = await aiBotLine(bot, eventText, { chatLog });
    if (live) return live;
  }
  return scriptedLine(bot, event, target);
}

const REPLY_RULES = [
  [/прив|здаро|хай|ку\b|hello|hi\b/i, ['прив', 'здарова', 'ку', 'хай)', 'приветик']],
  [/нуб|лох|изи|слаб/i, ['сам нуб', 'ты на себя посмотри', 'ахах ну да ну да', 'го 1 на 1 тогда', 'кто бы говорил']],
  [/бот|ии|ai|робот/i, ['я бот, да, в этой игре все кроме тебя — ии-боты :)', 'ну вообще да, я ии-игрок', 'бип-буп, да я бот лол']],
  [/гг|gg/i, ['гг', 'гг вп', 'ggwp']],
  [/дружить|друз|альянс|мир/i, ['го', 'давай', 'ну можно', 'посмотрим)']],
  [/как дела|как ты/i, ['норм, играю', 'да нормально', 'лучше всех']],
  [/\?$/, ['хз', 'не знаю', 'может', 'а что?', 'ну типо да']],
];

// Ответ бота на сообщение игрока в чате (ИИ или правила)
export async function botReply(bot, userText, chatLog = []) {
  const recent = chatLog.slice(-8).map((m) => `${m.name}: ${m.text}`).join('\n');
  const live = await aiReply({
    system: personaPrompt(bot),
    history: [{ role: 'user', content: `Чат игры:\n${recent}\n\nИгрок написал: «${userText}». Ответь ему одной репликой.` }],
    maxTokens: 120,
  });
  if (live) return live;
  for (const [re, answers] of REPLY_RULES) if (re.test(userText)) return pick(answers);
  return Math.random() < 0.5 ? scriptedLine(bot, 'idle') : pick(['ахах', 'лол', 'ок', 'чего', 'ну да', 'согл', 'ага']);
}

// Задержка «печатает...»: как будто живой человек набирает сообщение
export function typingDelay(text) {
  return 600 + Math.min(4000, (text?.length || 5) * rand(45, 110));
}
