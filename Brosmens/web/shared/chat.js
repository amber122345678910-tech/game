// Игровой чат (окно слева сверху, как в роблоксе) + боты отвечают на сообщения игрока.
// const chat = createChat({ bots: () => [...], me: 'Игрок' });
// chat.say(name, text, color)   chat.system(text)   chat.botSay(bot, event, opts)   chat.log -> [{name,text}]
import { botReply, botSay, typingDelay, pick } from './bots.js';
import { getProfile } from './profile.js';
import { sfx } from './sfx.js';

const CSS = `
.bc-wrap{position:fixed;left:8px;top:44px;width:min(42vw,360px);z-index:50;font:600 13px/1.25 system-ui,sans-serif;pointer-events:none}
.bc-log{max-height:30vh;overflow:hidden;display:flex;flex-direction:column;justify-content:flex-end;gap:2px;padding:6px 8px;border-radius:8px;transition:background .3s}
.bc-wrap.open .bc-log{background:rgba(0,0,0,.45);max-height:45vh;overflow-y:auto;pointer-events:auto}
.bc-msg{color:#fff;text-shadow:0 1px 2px #000,0 0 2px #000;word-wrap:break-word;transition:opacity 1s}
.bc-msg.old{opacity:0}.bc-wrap.open .bc-msg.old{opacity:1}
.bc-msg b{font-weight:800}
.bc-sys{color:#ffe08a}
.bc-typing{color:#ddd;font-style:italic;font-weight:500}
.bc-btn{position:fixed;left:8px;top:6px;z-index:51;width:34px;height:32px;border-radius:8px;border:0;background:rgba(0,0,0,.5);color:#fff;font-size:17px}
.bc-in{display:none;margin-top:4px;pointer-events:auto}
.bc-wrap.open .bc-in{display:flex;gap:4px}
.bc-in input{flex:1;min-width:0;border:0;border-radius:8px;padding:8px;font:600 14px system-ui;background:rgba(255,255,255,.92)}
.bc-in button{border:0;border-radius:8px;padding:0 12px;background:#2f6fed;color:#fff;font-weight:800}
`;

const NAME_COLORS = ['#ff6b6b', '#ffd93d', '#6bcB77', '#4d96ff', '#c77dff', '#ff9f45', '#5ee6eb', '#ff7eb6'];
const colorOf = (name) => NAME_COLORS[[...name].reduce((a, c) => a + c.charCodeAt(0), 0) % NAME_COLORS.length];

export function createChat({ bots = () => [], me } = {}) {
  if (!document.getElementById('bc-css')) {
    const st = document.createElement('style'); st.id = 'bc-css'; st.textContent = CSS; document.head.appendChild(st);
  }
  const myName = me || getProfile().name;
  const wrap = document.createElement('div'); wrap.className = 'bc-wrap';
  const logEl = document.createElement('div'); logEl.className = 'bc-log';
  const form = document.createElement('form'); form.className = 'bc-in';
  form.innerHTML = '<input maxlength="120" placeholder="Напиши в чат..." enterkeyhint="send"><button>➤</button>';
  wrap.append(logEl, form);
  const btn = document.createElement('button'); btn.className = 'bc-btn'; btn.textContent = '💬';
  document.body.append(wrap);
  // как в роблоксе: кнопка чата сразу после кнопки меню ☰
  const topBar = document.querySelector('.ui-top');
  if (topBar) topBar.insertBefore(btn, topBar.children[1] || null);
  else document.body.append(btn);
  const input = form.querySelector('input');

  const log = [];
  const handlers = [];
  let typingEl = null;

  function add(html, cls = '') {
    const d = document.createElement('div');
    d.className = 'bc-msg ' + cls;
    d.innerHTML = html;
    logEl.appendChild(d);
    while (logEl.children.length > 60) logEl.firstChild.remove();
    setTimeout(() => d.classList.add('old'), 12000);
    logEl.scrollTop = logEl.scrollHeight;
    return d;
  }
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

  function say(name, text, color) {
    if (!text) return;
    log.push({ name, text });
    if (log.length > 40) log.shift();
    add(`<b style="color:${color || colorOf(name)}">${esc(name)}:</b> ${esc(text)}`);
  }

  // бот «печатает», потом пишет
  function typeThenSay(bot, text) {
    if (!text) return;
    setTimeout(() => {
      if (typingEl) typingEl.remove();
      say(bot.name, text);
    }, typingDelay(text));
  }

  btn.onclick = () => {
    wrap.classList.toggle('open');
    if (wrap.classList.contains('open')) setTimeout(() => input.focus(), 50);
    else input.blur();
  };
  form.onsubmit = (e) => {
    e.preventDefault();
    const text = input.value.trim();
    input.value = '';
    if (!text) return;
    say(myName, text, '#ffffff');
    sfx.play('ui', { vol: 0.5 });
    handlers.forEach((h) => h(text));
    // Кто-то из ботов отвечает (чаще — если обратились по имени)
    const list = bots().filter((b) => !b.dead);
    if (!list.length) return;
    const named = list.find((b) => text.toLowerCase().includes(b.name.toLowerCase().slice(0, 4)));
    const responders = named ? [named] : Math.random() < 0.85 ? [pick(list)] : [];
    if (!named && Math.random() < 0.3 && list.length > 1) responders.push(pick(list));
    responders.forEach((b, i) => {
      setTimeout(async () => {
        const r = await botReply(b, text, log);
        typeThenSay(b, r);
      }, 400 + i * 1500);
    });
  };
  // не даём игровым обработчикам клавиш ловить ввод
  input.addEventListener('keydown', (e) => e.stopPropagation());
  wrap.addEventListener('pointerdown', (e) => e.stopPropagation());

  return {
    log,
    say,
    system(text) { add(esc(text), 'bc-sys'); },
    onMessage(fn) { handlers.push(fn); },
    // Событийная реплика бота (может промолчать). Возвращает Promise.
    async botSay(bot, event, opts = {}) {
      const text = await botSay(bot, event, { ...opts, chatLog: log });
      typeThenSay(bot, text);
      return text;
    },
    isOpen: () => wrap.classList.contains('open'),
    destroy() { wrap.remove(); btn.remove(); },
  };
}
