// «Живые» игроки: если в настройках введён ключ Anthropic API, реплики пишет Claude Haiku 5.5.
// Без ключа (или при ошибке/лимите) — возвращается null, и вызывающий код берёт заготовку из bots.js.
import { getApiKey, getProfile } from './profile.js';

const MODEL = 'claude-haiku-5-5';
const COUNT_KEY = 'brosmens.ai.count';

let clientPromise = null;
let lastKey = '';
let lastBotLine = 0;

export function aiEnabled() {
  return !!getApiKey();
}

function bump() {
  const today = new Date().toISOString().slice(0, 10);
  let c = { day: today, n: 0 };
  try { c = JSON.parse(localStorage.getItem(COUNT_KEY)) || c; } catch {}
  if (c.day !== today) c = { day: today, n: 0 };
  if (c.n >= getProfile().settings.aiDailyLimit) return false;
  c.n++;
  try { localStorage.setItem(COUNT_KEY, JSON.stringify(c)); } catch {}
  return true;
}

export function aiUsedToday() {
  try {
    const c = JSON.parse(localStorage.getItem(COUNT_KEY));
    return c && c.day === new Date().toISOString().slice(0, 10) ? c.n : 0;
  } catch { return 0; }
}

async function client() {
  const key = getApiKey();
  if (!key) return null;
  if (!clientPromise || key !== lastKey) {
    lastKey = key;
    clientPromise = import('../vendor/anthropic.mjs').then(
      ({ Anthropic }) => new Anthropic({ apiKey: key, dangerouslyAllowBrowser: true, maxRetries: 1, timeout: 20000 }),
    );
  }
  return clientPromise;
}

const STYLE = `Пиши по-русски, как живой человек в игровом чате: коротко (обычно 3–15 слов), строчными буквами, со сленгом, без кавычек и без описаний действий.
Можно подкалывать и трешток в меру, но без мата, без оскорблений внешности, национальности, религии и т.п.
Никогда не пиши за других участников. Если тебя всерьёз спрашивают, бот ли ты или ИИ — честно признай, что ты ИИ-игрок в приложении «Бросменс».`;

// Персонаж → системный промпт
export function personaPrompt(p) {
  return `Ты — ${p.name}, игрок в мобильном приложении «Бросменс» (сборник игр в стиле роблокса). ${p.persona || ''}
Токсичность по шкале 0–1: ${(p.toxic ?? 0.3).toFixed(1)} (чем выше, тем дерзее, но в рамках правил ниже).
${STYLE}`;
}

// Свободный диалог: history = [{role:'user'|'assistant', content:string}], последним — user.
// Возвращает текст или null.
export async function aiReply({ system, history, maxTokens = 220 }) {
  if (!aiEnabled() || !history?.length || !bump()) return null;
  try {
    const c = await client();
    const msgs = [];
    for (const m of history.slice(-16)) {
      const text = String(m.content || '').slice(0, 600);
      if (!text) continue;
      if (msgs.length && msgs[msgs.length - 1].role === m.role) msgs[msgs.length - 1].content += '\n' + text;
      else msgs.push({ role: m.role, content: text });
    }
    while (msgs.length && msgs[0].role !== 'user') msgs.shift();
    if (!msgs.length || msgs[msgs.length - 1].role !== 'user') return null;
    const res = await c.messages.create({
      model: MODEL,
      max_tokens: maxTokens,
      thinking: { type: 'disabled' },
      output_config: { effort: 'low' },
      system,
      messages: msgs,
    });
    const text = res.content.filter((b) => b.type === 'text').map((b) => b.text).join(' ').trim();
    return text ? text.replace(/^["«]|["»]$/g, '').slice(0, 300) : null;
  } catch (e) {
    console.warn('AI error', e?.status || '', e?.message || e);
    return null;
  }
}

// Реплика бота на игровое событие. Экономия: не чаще раза в minGapMs на всё приложение.
// event — короткое описание по-русски ("тебя убил Игрок комбо", "раунд начался" ...)
export async function aiBotLine(bot, event, { minGapMs = 20000, chatLog = [] } = {}) {
  const now = performance.now();
  if (!aiEnabled() || now - lastBotLine < minGapMs) return null;
  lastBotLine = now;
  const recent = chatLog.slice(-6).map((m) => `${m.name}: ${m.text}`).join('\n');
  const prompt = `${recent ? 'Последние сообщения чата:\n' + recent + '\n\n' : ''}Событие в игре: ${event}\nНапиши одну реплику в чат от своего лица.`;
  return aiReply({ system: personaPrompt(bot), history: [{ role: 'user', content: prompt }], maxTokens: 120 });
}
