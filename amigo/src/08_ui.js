/* ===== 08_ui.js ===== */
// Интерфейс Амиго: чат, аватар, голос, таймеры, панель «Мозг» и настройки.
const STORE_KEY = 'amigo.v1', CHAT_KEY = 'amigo.chat.v1', UI_KEY = 'amigo.ui.v1';
const DEFAULT_CHIPS = ['Что ты умеешь?', 'Расскажи шутку', 'Сколько будет 17 × 23?', 'Загадай загадку', 'Что такое чёрная дыра?', 'Как ты работаешь?', 'Сыграем в угадай число', 'Интересный факт', 'Викторина', 'Какой сегодня день?'];
const SRC_LABEL = { memory: 'из моей памяти', wiki: 'Википедия', claude: 'супер-мозг Claude', web: 'интернет', taught: 'ты научил', codex: 'Кодекс' };
const CODEX_CHIPS = ['Кот ловит рыбу под водой', 'Динозавр прыгает через кактусы', 'Корабль стреляет в пришельцев', 'Пингвин прыгает по льдинам вверх', 'Машинка объезжает машины', 'Собирай монетки и убегай от призраков', 'Лопай шарики на время', 'Вертолёт летит между горами'];

class App {
  constructor(brain) {
    this.brain = brain;
    this.el = id => document.getElementById(id);
    this.log = [];
    this.busy = false;
    this.timers = [];
    this.lossHistory = brain.model.history.slice();
    this.uiState = U.store.get(UI_KEY, {});
  }

  start() {
    const $ = this.el;
    this.logEl = $('log'); this.input = $('input'); this.avatar = $('avatar');
    $('composer').addEventListener('submit', e => { e.preventDefault(); if (this.busy) { if (this.ctl) this.ctl.abort(); return; } this.send(this.input.value); });
    this.cards = [];
    document.addEventListener('visibilitychange', () => { if (document.hidden && this.activeGame) this.activeGame.pause(); });
    this.input.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); if (!this.busy) this.send(this.input.value); } });
    this.input.addEventListener('input', () => this.autosize());
    $('btnBrain').addEventListener('click', () => this.toggleBrain());
    $('btnBrainClose').addEventListener('click', () => this.toggleBrain(false));
    $('btnSettings').addEventListener('click', () => this.openSettings(true));
    $('btnSetClose').addEventListener('click', () => this.openSettings(false));
    $('backdrop').addEventListener('click', () => this.openSettings(false));
    $('btnVoice').addEventListener('click', () => this.setVoice(!this.brain.settings.voice, true));
    $('btnRetrain').addEventListener('click', () => this.retrain());
    document.addEventListener('keydown', e => {
      if (e.key !== 'Escape') return;
      if (!$('settings').hidden) this.openSettings(false);
      else if (!$('brain').hidden && window.innerWidth < 1000) this.toggleBrain(false);
    });
    this.bindSettings();
    $('btnCodex').addEventListener('click', () => this.setCodex(!this.brain.settings.codexOn));
    $('codexClose').addEventListener('click', () => this.setCodex(false));
    for (const b of document.querySelectorAll('#codexBar [data-level]')) b.addEventListener('click', () => { this.brain.settings.codexLevel = b.dataset.level; this.brain.save(); this.renderCodex(); this.toast('Кодекс: ' + CODEX_LEVELS[b.dataset.level].name); });
    this.initMic();
    if (!('speechSynthesis' in window) && !this.native('canSpeak')) $('btnVoice').hidden = true;
    // приложение для Android: голос и кнопка «Назад»
    if (window.AmigoAndroid) {
      window.amigoOnSpeaking = on => { clearTimeout(this.talkT); this.avatar.classList.toggle('talk', !!on); };
      window.amigoOnBack = () => {
        if (this.activeGame && this.activeGame.running) { this.activeGame.pause(); return true; }
        if (!$('settings').hidden) { this.openSettings(false); return true; }
        if (!$('brain').hidden && window.innerWidth < 1000) { this.toggleBrain(false); return true; }
        return false;
      };
    }
    this.initInstall();

    // перерисовать схемы при смене темы и размера
    const redraw = () => this.drawAll();
    try { window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', redraw); } catch (e) { /* старый браузер */ }
    try { new MutationObserver(redraw).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'class'] }); } catch (e) { /* нет */ }
    let rt = 0; window.addEventListener('resize', () => { clearTimeout(rt); rt = setTimeout(redraw, 120); });
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(redraw);

    Online.Super.onChange = () => this.renderSettings();
    Online.Super.init();

    const wide = window.innerWidth >= 1000;
    this.toggleBrain(this.uiState.brain == null ? wide : this.uiState.brain && wide, false);
    this.renderStats(); this.renderTaught(); this.renderCodex(); this.setVoice(this.brain.settings.voice, false);
    this.restore();
    this.setStatus();
    if (this.brain.needsTuning) this.tune();
  }

  // ---------- сообщения ----------
  restore() {
    const saved = U.store.get(CHAT_KEY, []);
    if (Array.isArray(saved) && saved.length) {
      for (const m of saved) this.addMsg(m.who, m.text, m.meta || {}, { restore: true });
      this.brain.history = saved.slice(-20).map(m => ({ role: m.who === 'me' ? 'user' : 'assistant', content: m.text }));
      for (let i = saved.length - 1; i >= 0; i--) { const g = saved[i].meta && saved[i].meta.game; if (g && g.key === 'codex') { this.brain.lastSpec = g.opts; break; } }
      this.chips(null);
      this.scroll(true);
    } else this.greet();
  }
  greet() {
    const n = this.brain.profile.name;
    const text = n ? `С возвращением, ${n}! 😊 Чем займёмся?`
      : 'Хола! 👋 Я **Амиго** — нейросеть, которая живёт прямо в твоём телефоне или браузере. Я умею болтать почти обо всём, считать, играть, шутить, делать игры и учиться новому — даже без интернета.\n\nКак тебя зовут?';
    if (!n) this.brain.ctx = { type: 'ask_name' };
    this.addMsg('bot', text, { src: 'rule' });
    this.brain.history.push({ role: 'assistant', content: text });
    this.chips(n ? null : ['Что ты умеешь?', 'Расскажи шутку', 'Как ты работаешь?']);
  }
  renderText(el, text) {
    const esc = s => s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const inline = p => esc(p).replace(/^#{1,4}\s+(.+)$/gm, '<strong>$1</strong>')
      .replace(/^\s*[-*]\s+/gm, '• ')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/(^|[\s(])\*([^*\n]+)\*(?=[\s.,!?)]|$)/g, '$1<em>$2</em>')
      .replace(/`([^`\n]+)`/g, '<code>$1</code>')
      .replace(/\n/g, '<br>');
    // ``` блоки кода ``` показываем как есть
    el.innerHTML = String(text).split('```').map((p, i) => i % 2 ? '<pre><code>' + esc(p.replace(/^[\w+-]*\n/, '').replace(/\n$/, '')) + '</code></pre>' : inline(p)).join('');
  }
  addMsg(who, text, meta = {}, opt = {}) {
    const wrap = document.createElement('div');
    wrap.className = 'msg ' + who;
    const b = document.createElement('div');
    b.className = 'bubble';
    this.renderText(b, text);
    wrap.appendChild(b);
    if (meta.think && meta.think.length) wrap.appendChild(this.thinkLog(meta.think, meta.thinkSecs));
    if (meta.game) {
      wrap.classList.add('game');
      const card = new GameCard(this, meta.game);
      wrap.appendChild(card.el); this.cards.push(card); wrap.card = card;
    }
    if (who === 'bot') {
      const m = this.metaEl(meta);
      if (m) wrap.appendChild(m);
    }
    this.logEl.appendChild(wrap);
    if (!opt.restore && !opt.live) { this.log.push({ who, text, meta, ts: Date.now() }); this.saveChat(); }
    else if (opt.restore) this.log.push({ who, text, meta, ts: Date.now() });
    if (!opt.restore) this.scroll();
    wrap.bubble = b;
    return wrap;
  }
  metaEl(meta) {
    const parts = [];
    let label = '';
    if (meta.src === 'net' || (meta.src === 'skill' && meta.conf != null)) label = `нейросеть · ${meta.title || 'тема'} · ${Math.round((meta.conf || 0) * 100)}%`;
    else if (meta.src === 'skill') label = 'навык';
    else if (meta.src === 'talk') label = meta.conf != null && meta.title ? `нейросеть · ${meta.title} · ${Math.round(meta.conf * 100)}%` : 'разговор';
    else if (SRC_LABEL[meta.src]) label = SRC_LABEL[meta.src];
    if (meta.src === 'codex') label = 'Кодекс · ' + (CODEX_LEVELS[meta.codexLevel] || CODEX_LEVELS.high).name + ' · сам запрограммировал';
    if (label) { const s = document.createElement('span'); s.className = 'src ' + meta.src; s.textContent = label; parts.push(s); }
    if (meta.game && meta.game.key === 'codex') {
      const b = document.createElement('button'); b.type = 'button'; b.className = 'link-btn'; b.textContent = 'Показать код';
      b.addEventListener('click', () => this.showCode(meta.game.opts)); parts.push(b);
    }
    if (meta.codeSpec) {
      const b = document.createElement('button'); b.type = 'button'; b.className = 'link-btn'; b.textContent = '📋 Скопировать полный код (HTML)';
      b.addEventListener('click', () => this.copyCode(meta.codeSpec)); parts.push(b);
      const d = document.createElement('button'); d.type = 'button'; d.className = 'link-btn'; d.textContent = '⬇️ Скачать игру'; d.addEventListener('click', () => this.downloadCode(meta.codeSpec)); parts.push(d);
    }
    if (meta.link && /^https:\/\//.test(meta.link.url)) {
      const a = document.createElement('a'); a.href = meta.link.url; a.target = '_blank'; a.rel = 'noopener noreferrer'; a.textContent = 'статья: ' + meta.link.title; parts.push(a);
    }
    if (meta.phrase && (meta.conf != null || ['memory', 'taught', 'wiki', 'claude'].includes(meta.src)) && meta.src !== 'rule' && meta.src !== 'codex' && !meta.unsure) {
      const btn = document.createElement('button'); btn.type = 'button'; btn.className = 'link-btn'; btn.textContent = 'Не то';
      btn.title = 'Научить Амиго другому ответу';
      btn.addEventListener('click', () => this.teachFix(meta.phrase));
      parts.push(btn);
    }
    if (!parts.length) return null;
    const m = document.createElement('div'); m.className = 'meta';
    parts.forEach(p => m.appendChild(p));
    return m;
  }
  teachFix(phrase) {
    const text = this.brain.startTeach(phrase);
    this.addMsg('bot', text, { src: 'rule' });
    this.brain.history.push({ role: 'assistant', content: text });
    this.chips(['Отмена']);
    this.mood('learn', 2000);
    this.input.focus();
  }
  showTyping() {
    const w = document.createElement('div'); w.className = 'msg bot typing';
    w.innerHTML = '<div class="bubble" aria-label="Амиго печатает"><i></i><i></i><i></i></div>';
    this.logEl.appendChild(w); this.scroll();
    return w;
  }
  scroll(force) {
    const l = this.logEl;
    requestAnimationFrame(() => { l.scrollTop = l.scrollHeight; });
  }
  autosize() { const t = this.input; t.style.height = 'auto'; t.style.height = Math.min(t.scrollHeight, 140) + 'px'; }
  saveChat() {
    // код игр от супер-мозга большой: храним только три последние игры
    const items = this.log.slice(-80), keep = new Set(items.filter(m => m.meta && m.meta.game && m.meta.game.kind === 'custom').slice(-3));
    const out = items.map(m => m.meta && m.meta.game && m.meta.game.kind === 'custom' && !keep.has(m) ? Object.assign({}, m, { meta: Object.assign({}, m.meta, { game: Object.assign({}, m.meta.game, { html: null }) }) }) : m);
    if (!U.store.set(CHAT_KEY, out)) U.store.set(CHAT_KEY, out.map(m => m.meta && m.meta.game && m.meta.game.html ? Object.assign({}, m, { meta: Object.assign({}, m.meta, { game: Object.assign({}, m.meta.game, { html: null }) }) }) : m));
  }
  clearChat() { this.cards.forEach(c => c.destroy()); this.cards = []; this.activeGame = null; this.log = []; this.logEl.innerHTML = ''; this.saveChat(); this.brain.history = []; }
  gameRecord(title, points, label) {
    const text = `🏆 Новый рекорд в игре «${title}»! ${label}: ${points}. Так держать{,name}!`.replace('{,name}', this.brain.profile.name ? ', ' + this.brain.profile.name : '');
    this.addMsg('bot', text, { src: 'skill' });
    this.brain.history.push({ role: 'assistant', content: text });
    this.mood('happy', 2500);
  }

  chips(list) {
    const box = this.el('chips');
    box.innerHTML = '';
    const items = list && list.length ? list : U.shuffle((this.brain.settings.codexOn ? CODEX_CHIPS : DEFAULT_CHIPS).slice()).slice(0, 4);
    for (const c of items) {
      const b = document.createElement('button'); b.type = 'button'; b.className = 'chip'; b.textContent = c;
      b.addEventListener('click', () => {
        if (c === 'Показать мозг') return this.toggleBrain(true);
        if (c === 'Настройки') return this.openSettings(true);
        this.send(c);
      });
      box.appendChild(b);
    }
    box.scrollLeft = 0;
  }

  async send(raw) {
    const text = String(raw || '').trim();
    if (!text || this.busy) return;
    this.unlockAudio();
    this.input.value = ''; this.autosize();
    this.addMsg('me', text);
    this.busy = true; this.setSendStop(true);
    this.setStatus('думаю…', true); this.mood('think');
    const typing = this.showTyping();
    let live = null;
    this.ctl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    const io = {
      signal: this.ctl ? this.ctl.signal : undefined,
      onThinking: k => { this.setStatus(k === 'super' ? 'спрашиваю супер-мозг…' : k === 'codex' ? 'программирую игру…' : k === 'ultra' ? 'Кодекс Ультра думает…' : k === 'wiki' ? 'ищу в Википедии…' : 'смотрю в интернете…', true); if (k === 'codex' || k === 'ultra') this.mood('learn'); },
      onProgress: n => { const b = typing.querySelector('.bubble'); if (b) { b.classList.add('progress-text'); b.textContent = `🛠️ Пишу игру… ${U.num(n)} символов кода`; } this.setStatus('пишу игру…', true); },
      onThink: lines => { const b = typing.querySelector('.bubble'); if (b) { b.className = 'bubble think-live'; b.innerHTML = ''; b.appendChild(this.thinkList(lines, true)); } this.scroll(); },
      onStream: t => {
        if (!t) return;
        if (!live) { typing.remove(); live = this.addMsg('bot', t, {}, { live: true }); this.mood('think'); }
        else this.renderText(live.bubble, t);
        this.scroll();
      },
    };
    const t0 = Date.now();
    let a;
    try { a = await this.brain.reply(text, io); }
    catch (e) { a = { text: 'Ой, что-то сломалось 😵 Попробуй ещё раз.', src: 'rule' }; }
    if (!live) { const wait = 250 + Math.min(450, a.text.length * 3) - (Date.now() - t0); if (wait > 0) await new Promise(r => setTimeout(r, wait)); }
    typing.remove();
    const meta = { src: a.src, conf: a.conf, title: this.titleOf(a), link: a.link, phrase: text, unsure: a.unsure, game: a.game, codexLevel: a.codexLevel, think: a.think, thinkSecs: a.thinkSecs };
    if (live) live.remove();
    const w = this.addMsg('bot', a.text, meta);
    if (w.card) { w.card.focus(); this.scroll(); }
    this.busy = false; this.ctl = null; this.setSendStop(false);
    this.setStatus();
    this.mood(a.mood || 'idle', 2600);
    this.chips(a.chips);
    this.apply(a.action);
    this.speak(a.text);
    this.showThought(text, a);
  }
  setSendStop(on) {
    const b = this.el('btnSend');
    b.classList.toggle('stop', on);
    b.setAttribute('aria-label', on ? 'Остановить' : 'Отправить'); b.title = on ? 'Остановить' : '';
  }
  titleOf(a) {
    if (!a.intent) return '';
    if (a.intent === 'word') return 'слово из словаря';
    if (a.intent === 'answer') return 'ответ на мой вопрос';
    const it = this.brain.byTag.get(a.intent);
    return it ? it.t : a.intent;
  }
  apply(act) {
    if (!act) return;
    if (act.type === 'timer') this.startTimer(act.sec, act.label);
    else if (act.type === 'timer_cancel') this.cancelTimers();
    else if (act.type === 'clear') { const last = this.log[this.log.length - 1]; this.clearChat(); if (last) this.addMsg('bot', last.text, last.meta); }
    else if (act.type === 'voice') this.setVoice(act.on, false);
    else if (act.type === 'dance') this.mood('dance', 3200);
    else if (act.type === 'learned') { this.renderTaught(); this.tune(); }
    else if (act.type === 'codex') this.renderCodex();
    else if (act.type === 'code') this.showCode(act.spec);
  }

  // ---------- статус и настроение ----------
  setStatus(text, busy) {
    const s = this.el('status');
    if (text) { s.textContent = text; s.classList.toggle('busy', !!busy); return; }
    if (this.tuning) { s.textContent = 'учусь новому…'; s.classList.add('busy'); return; }
    const net = this.brain.net;
    s.textContent = `нейросеть · ${net.C} ${U.plural(net.C, 'тема', 'темы', 'тем')}`;
    const more = document.createElement('span'); more.className = 'wide'; more.textContent = ` · ${Math.round(net.params / 1000)} тыс. параметров`;
    s.appendChild(more);
    s.classList.remove('busy');
  }
  mood(m, ms) {
    clearTimeout(this.moodT);
    this.avatar.dataset.mood = m;
    if (ms) this.moodT = setTimeout(() => { this.avatar.dataset.mood = 'idle'; }, ms);
  }

  // ---------- голос ----------
  setVoice(on, announce) {
    this.brain.settings.voice = !!on; this.brain.save();
    this.el('btnVoice').setAttribute('aria-pressed', on ? 'true' : 'false');
    const sv = this.el('setVoice'); if (sv) sv.checked = !!on;
    if (!on && 'speechSynthesis' in window) speechSynthesis.cancel();
    if (!on) this.native('stopSpeaking');
    if (announce) this.toast(on ? 'Буду читать ответы вслух 🔊' : 'Голос выключен 🔇');
  }
  // мост к приложению для Android: там нет голосовых функций браузера, их даёт само приложение
  native(fn, ...a) {
    try { const N = window.AmigoAndroid; if (N && typeof N[fn] === 'function') return N[fn](...a); } catch (e) { /* нет моста */ }
    return undefined;
  }
  speak(text) {
    if (!this.brain.settings.voice) return;
    const plain = String(text).replace(/\*\*|`/g, '').replace(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]/gu, '').replace(/[•→]/g, ',').replace(/\s+/g, ' ').trim();
    if (!plain) return;
    if (this.native('canSpeak')) {
      const rate = this.brain.settings.rate || 1;
      this.native('speak', plain, rate);
      // приложение сообщит, когда закончит говорить; на всякий случай выключим «рот» и по таймеру
      this.avatar.classList.add('talk'); clearTimeout(this.talkT);
      this.talkT = setTimeout(() => this.avatar.classList.remove('talk'), Math.min(30000, plain.length * 90 / rate + 1000));
      return;
    }
    if (!('speechSynthesis' in window)) return;
    try {
      speechSynthesis.cancel();
      const u = new SpeechSynthesisUtterance(plain);
      u.lang = 'ru-RU'; u.rate = this.brain.settings.rate || 1; u.pitch = 1.15;
      const v = speechSynthesis.getVoices().find(v => /^ru/i.test(v.lang));
      if (v) u.voice = v;
      u.onstart = () => this.avatar.classList.add('talk');
      u.onend = u.onerror = () => this.avatar.classList.remove('talk');
      speechSynthesis.speak(u);
    } catch (e) { /* речь недоступна */ }
  }
  initMic() {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    const btn = this.el('btnMic');
    if (this.native('canListen')) {
      btn.hidden = false;
      window.amigoOnSpeech = t => {
        btn.classList.remove('listening'); this.listening = false;
        if (!t || !String(t).trim()) return this.toast('Я ничего не услышал. Попробуй ещё раз!');
        // Амиго ещё думает над прошлым сообщением — оставим услышанное в поле ввода
        if (this.busy) { this.input.value = String(t); this.autosize(); return this.toast('Я ещё думаю — отправь, когда отвечу 🙂'); }
        this.send(String(t));
      };
      btn.addEventListener('click', () => { if (this.listening) return; this.listening = true; btn.classList.add('listening'); this.native('listen'); });
      return;
    }
    if (!SR) return;
    btn.hidden = false;
    btn.addEventListener('click', () => {
      if (this.rec) { this.rec.stop(); return; }
      let rec;
      try { rec = new SR(); } catch (e) { btn.hidden = true; return; }
      rec.lang = 'ru-RU'; rec.interimResults = true; rec.maxAlternatives = 1;
      let finalText = '';
      rec.onresult = e => {
        let s = ''; finalText = '';
        for (const r of e.results) { s += r[0].transcript; if (r.isFinal) finalText += r[0].transcript; }
        this.input.value = s; this.autosize();
      };
      rec.onerror = e => {
        if (e.error === 'not-allowed' || e.error === 'service-not-allowed') { this.toast('Микрофон здесь недоступен. Можно писать текстом 🙂'); btn.hidden = true; }
        else if (e.error === 'no-speech') this.toast('Я ничего не услышал. Попробуй ещё раз!');
      };
      rec.onend = () => { this.rec = null; btn.classList.remove('listening'); const t = (finalText || this.input.value).trim(); if (t) this.send(t); };
      try { rec.start(); this.rec = rec; btn.classList.add('listening'); this.toast('Говори, я слушаю 👂'); } catch (e) { this.toast('Не получилось включить микрофон'); }
    });
  }

  // уведомление, если Амиго свёрнут; на Android обычный Notification не работает — нужен service worker
  notify(body) {
    try {
      if (!document.hidden || !('Notification' in window) || Notification.permission !== 'granted') return;
      if ('serviceWorker' in navigator && navigator.serviceWorker.controller) navigator.serviceWorker.ready.then(r => r.showNotification('Амиго', { body, icon: 'icons/icon-192.png' })).catch(() => {});
      else new Notification('Амиго', { body });
    } catch (e) { /* нет уведомлений */ }
  }

  // ---------- установка на телефон ----------
  initInstall() {
    const btn = this.el('btnInstall'), hint = this.el('installHint'), ver = this.el('appVersion');
    if (!btn) return;
    const standalone = (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) || window.navigator.standalone === true;
    const v = this.native('version');
    const nt = this.brain.tags.length, nl = Lex.size;
    if (ver) ver.textContent = `Версия ${v || AMIGO_VERSION} · ${U.num(nt)} ${U.plural(nt, 'тема', 'темы', 'тем')} · ${U.num(nl)} ${U.plural(nl, 'слово', 'слова', 'слов')} в словаре`;
    if (window.AmigoAndroid || standalone) { hint.textContent = 'Амиго уже установлен как приложение 🎉 Он работает и без интернета.'; return; }
    const ios = /iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    if (ios) hint.textContent = 'На iPhone: открой Амиго в Safari, нажми «Поделиться» (квадрат со стрелкой) → «На экран „Домой“». Появится значок, как у приложения.';
    else if (location.protocol === 'file:') hint.textContent = 'Чтобы установить Амиго, открой его по ссылке из интернета (https://…), а не как файл. Или скачай Amigo.apk для Android — подробности в README.';
    window.addEventListener('beforeinstallprompt', e => {
      e.preventDefault(); this.installEvt = e; btn.hidden = false;
      hint.textContent = 'Нажми кнопку — и Амиго появится на главном экране как приложение. Он будет работать даже без интернета.';
    });
    btn.addEventListener('click', async () => {
      if (!this.installEvt) return;
      this.installEvt.prompt();
      try { const r = await this.installEvt.userChoice; if (r && r.outcome === 'accepted') this.toast('Ура! Амиго устанавливается 📱'); } catch (e) { /* отмена */ }
      this.installEvt = null; btn.hidden = true;
    });
    window.addEventListener('appinstalled', () => { btn.hidden = true; hint.textContent = 'Амиго установлен 🎉 Ищи его значок на главном экране.'; });
  }

  // ---------- таймеры ----------
  unlockAudio() {
    try { if (!this.audio) { const AC = window.AudioContext || window.webkitAudioContext; if (AC) this.audio = new AC(); } if (this.audio && this.audio.state === 'suspended') this.audio.resume(); } catch (e) { /* без звука */ }
  }
  beep() {
    const ac = this.audio; if (!ac) return;
    try {
      [0, 0.25, 0.5].forEach((d, i) => {
        const o = ac.createOscillator(), g = ac.createGain();
        o.type = 'sine'; o.frequency.value = i === 2 ? 1046 : 784;
        g.gain.setValueAtTime(0.0001, ac.currentTime + d); g.gain.exponentialRampToValueAtTime(0.25, ac.currentTime + d + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, ac.currentTime + d + 0.22);
        o.connect(g).connect(ac.destination); o.start(ac.currentTime + d); o.stop(ac.currentTime + d + 0.25);
      });
    } catch (e) { /* без звука */ }
  }
  startTimer(sec, label) {
    const t = { id: Date.now() + Math.random(), end: Date.now() + sec * 1000, label };
    this.timers.push(t);
    try { if (!window.AmigoAndroid && 'Notification' in window && Notification.permission === 'default') Notification.requestPermission().catch(() => {}); } catch (e) { /* нет уведомлений */ }
    if (!this.timerTick) this.timerTick = setInterval(() => this.renderTimers(), 500);
    this.renderTimers();
  }
  cancelTimers() { this.timers = []; this.renderTimers(); }
  renderTimers() {
    const box = this.el('timers'), now = Date.now();
    for (const t of this.timers.filter(t => t.end <= now)) {
      this.timers = this.timers.filter(x => x !== t);
      const text = this.brain.timerDone(t.label);
      this.addMsg('bot', text, { src: 'skill' });
      this.brain.history.push({ role: 'assistant', content: text });
      this.beep(); this.mood('wow', 3000); this.speak(text);
      this.notify(text.replace(/\*\*/g, ''));
    }
    box.innerHTML = '';
    for (const t of this.timers) {
      const s = Math.max(0, Math.ceil((t.end - now) / 1000)), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60;
      const b = document.createElement('button'); b.type = 'button'; b.className = 'timer-pill';
      b.textContent = '⏱ ' + (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(sec).padStart(2, '0');
      b.title = 'Отменить таймер' + (t.label ? ': ' + t.label : '');
      b.addEventListener('click', () => { this.timers = this.timers.filter(x => x !== t); this.renderTimers(); this.toast('Таймер отменён'); });
      box.appendChild(b);
    }
    if (!this.timers.length && this.timerTick) { clearInterval(this.timerTick); this.timerTick = 0; }
  }

  // ---------- обучение ----------
  progress(on, frac, text) {
    this.el('trainProgress').hidden = !on;
    if (on) { this.el('trainBar').style.width = Math.round(frac * 100) + '%'; this.el('trainText').textContent = text; }
  }
  async tune() {
    if (this.tuning) { this.tuneAgain = true; return; }
    this.tuning = true; this.setStatus(); this.mood('learn');
    const E = 8;
    this.progress(true, 0, 'Дообучаюсь на твоих фразах…');
    try {
      await this.brain.fineTune({ epochs: E, tick: U.tick, onEpoch: r => this.progress(true, r.epoch / E, `Дообучение: эпоха ${r.epoch} из ${E}, точность ${Math.round(r.acc * 100)}%`) });
    } catch (e) { console.error(e); }
    this.tuning = false; this.progress(false);
    this.setStatus(); this.mood('happy', 1500);
    this.renderStats(); this.renderTaught();
    if (this.tuneAgain) { this.tuneAgain = false; this.tune(); }
  }
  async retrain() {
    if (this.tuning) return;
    const btn = this.el('btnRetrain');
    btn.disabled = true; this.tuning = true; this.setStatus(); this.mood('learn');
    const E = this.brain.retrainEpochs, hist = [];
    this.lossTarget = E;
    this.lossHistory = hist;
    this.progress(true, 0, 'Готовлю примеры…');
    await U.tick();
    const t0 = Date.now();
    try {
      await this.brain.retrain({ tick: U.tick, yieldEvery: 12, onEpoch: r => { hist.push([r.loss, r.acc]); this.drawLoss(); this.progress(true, r.epoch / E, `Эпоха ${r.epoch} из ${E}: ошибка ${r.loss.toFixed(2)}, точность ${Math.round(r.acc * 100)}%`); } });
      this.toast(`Готово за ${Math.round((Date.now() - t0) / 1000)} с! Точность на обучении ${Math.round(hist[hist.length - 1][1] * 100)}%`);
    } catch (e) { console.error(e); this.toast('Не получилось переобучиться'); }
    this.tuning = false; btn.disabled = false; this.progress(false);
    this.setStatus(); this.mood('happy', 1500); this.renderStats(); this.drawLoss();
  }

  // ---------- панель «Мозг» ----------
  toggleBrain(open, remember = true) {
    const $ = this.el, b = $('brain');
    if (open == null) open = b.hidden;
    b.hidden = !open;
    $('app').classList.toggle('brain-open', open);
    $('btnBrain').setAttribute('aria-expanded', open ? 'true' : 'false');
    if (remember) { this.uiState.brain = open; U.store.set(UI_KEY, this.uiState); }
    if (open) requestAnimationFrame(() => this.drawAll());
  }
  drawAll() { if (this.el('brain').hidden) return; this.drawNet(this.lastCls); this.drawLoss(); }
  colors() {
    const cs = getComputedStyle(document.documentElement), v = n => cs.getPropertyValue(n).trim();
    return { ink: v('--ink'), muted: v('--muted'), line: v('--line'), coral: v('--coral'), teal: v('--teal'), accent: v('--accent'), surface: v('--surface'), s2: v('--surface-2'), mono: v('--f-mono') };
  }
  canvas(id) {
    const cv = this.el(id), dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = cv.clientWidth, h = cv.clientHeight;
    if (!w || !h) return null;
    if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
    const ctx = cv.getContext('2d'); ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, w, h);
    return { ctx, w, h };
  }
  showThought(text, a) {
    const cls = this.brain.lastCls;
    if (!cls || cls.text !== text) return;
    this.lastCls = cls;
    const said = this.el('said'), t0 = cls.top[0];
    const route = { claude: 'ответ дал супер-мозг Claude', wiki: 'ответ нашёлся в Википедии', memory: 'ответ из моей памяти и словаря', taught: 'ответ, которому ты меня научил', web: 'данные из интернета', skill: 'ответ построил навык', rule: 'сработало особое правило', talk: 'ответ построил разговорный модуль' }[a.src];
    said.textContent = '';
    const q = document.createElement('span'); q.textContent = `«${text.length > 60 ? text.slice(0, 59) + '…' : text}» → `;
    const b = document.createElement('b'); b.textContent = `${t0.title} (${Math.round(t0.p * 100)}%)`;
    said.append(q, b);
    if (route || a.unsure) said.append(document.createTextNode(a.unsure ? ' · я не уверен' : ' · ' + route));
    const bars = this.el('bars'); bars.innerHTML = '';
    for (const t of cls.top) {
      const li = document.createElement('li');
      li.innerHTML = '<span class="bar-label"></span><span class="bar-track"><span class="bar-fill"></span></span><span class="bar-val"></span>';
      li.children[0].textContent = t.title; li.children[0].title = t.title;
      li.children[2].textContent = Math.round(t.p * 100) + '%';
      bars.appendChild(li);
      requestAnimationFrame(() => { li.querySelector('.bar-fill').style.width = Math.max(1, t.p * 100) + '%'; });
    }
    this.animateNet(cls);
  }
  animateNet(cls) {
    if (this.el('brain').hidden) return;
    const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduce) return this.drawNet(cls, 1);
    const t0 = performance.now(), dur = 900;
    cancelAnimationFrame(this.netAnim);
    const step = now => { const k = Math.min(1, (now - t0) / dur); this.drawNet(cls, k); if (k < 1) this.netAnim = requestAnimationFrame(step); };
    this.netAnim = requestAnimationFrame(step);
  }
  featLabel(key) {
    if (!key) return '?';
    const k = key.slice(2);
    if (key[0] === 'w') return k;
    if (key[0] === 'b') return k.replace(' ', '+');
    return k.replace('<', '‹').replace('>', '›');
  }
  drawNet(cls, k = 1) {
    const c = this.canvas('netCanvas'); if (!c) return;
    const { ctx, w, h } = c, col = this.colors(), net = this.brain.net, H = net.H, C = net.C;
    const font = sz => `${sz}px ${col.mono || 'monospace'}`;
    const xIn = w * 0.27, xHid = w * 0.46, xOut = w * 0.61, top = 30, bottom = h - 26;
    ctx.font = font(10); ctx.fillStyle = col.muted; ctx.textBaseline = 'middle';
    ctx.textAlign = 'right'; ctx.fillText('признаки', xIn + 4, 14);
    ctx.textAlign = 'center'; ctx.fillText('нейроны', xHid, 14);
    ctx.textAlign = 'left'; ctx.fillText('темы', xOut - 4, 14);
    const ys = (n, i) => n === 1 ? (top + bottom) / 2 : top + (bottom - top) * i / (n - 1);
    if (!cls) {
      ctx.strokeStyle = col.line; ctx.lineWidth = 1;
      const A = [7, 10, 5], X = [xIn, xHid, xOut];
      for (let l = 0; l < 2; l++) for (let i = 0; i < A[l]; i++) for (let j = 0; j < A[l + 1]; j++) { ctx.beginPath(); ctx.moveTo(X[l], ys(A[l], i)); ctx.lineTo(X[l + 1], ys(A[l + 1], j)); ctx.stroke(); }
      for (let l = 0; l < 3; l++) for (let i = 0; i < A[l]; i++) { ctx.beginPath(); ctx.arc(X[l], ys(A[l], i), 5, 0, 7); ctx.fillStyle = col.surface; ctx.fill(); ctx.strokeStyle = col.muted; ctx.stroke(); }
      return;
    }
    // самые важные признаки фразы
    const x = cls.x, feats = [];
    for (let i = 0; i < x.idx.length; i++) {
      const row = x.idx[i] * H; let n = 0;
      for (let j = 0; j < H; j++) n += Math.abs(net.W1[row + j]);
      feats.push({ i: x.idx[i], v: x.val[i], s: x.val[i] * n, key: x.keys ? x.keys.get(x.idx[i]) : '' });
    }
    feats.sort((a, b) => b.s - a.s);
    const F = feats.slice(0, 8);
    const hidOrder = Array.from(cls.hid.keys()).sort((a, b) => cls.hid[b] - cls.hid[a]).slice(0, 10);
    const maxHid = cls.hid[hidOrder[0]] || 1;
    const outs = cls.top.map(t => ({ t, c: this.brain.tags.indexOf(t.tag) })).filter(o => o.c >= 0);
    // связи
    const edges = [];
    F.forEach((f, a) => hidOrder.forEach((hh, b) => edges.push({ l: 0, a, b, w: net.W1[f.i * H + hh] * f.v })));
    hidOrder.forEach((hh, a) => outs.forEach((o, b) => edges.push({ l: 1, a, b, w: (o.c < C ? net.W2[hh * C + o.c] : 0) * cls.hid[hh] })));
    const mx = [0, 0]; for (const e of edges) mx[e.l] = Math.max(mx[e.l], Math.abs(e.w));
    for (const e of edges) {
      const prog = e.l === 0 ? Math.min(1, k * 2) : Math.max(0, k * 2 - 1);
      const s = Math.abs(e.w) / (mx[e.l] || 1);
      if (s < 0.06 || !prog) continue;
      const x1 = e.l ? xHid : xIn, y1 = e.l ? ys(hidOrder.length, e.a) : ys(F.length, e.a);
      const x2 = e.l ? xOut : xHid, y2 = e.l ? ys(outs.length, e.b) : ys(hidOrder.length, e.b);
      ctx.globalAlpha = Math.min(0.9, 0.12 + s * 0.8) * prog;
      ctx.strokeStyle = e.w > 0 ? col.coral : col.teal; ctx.lineWidth = 0.6 + s * 2.4;
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x1 + (x2 - x1) * prog, y1 + (y2 - y1) * prog); ctx.stroke();
    }
    ctx.globalAlpha = 1;
    // узлы и подписи
    const node = (cx, cy, r, fill, a) => { ctx.beginPath(); ctx.arc(cx, cy, r, 0, 7); ctx.fillStyle = col.surface; ctx.fill(); ctx.globalAlpha = a; ctx.fillStyle = fill; ctx.fill(); ctx.globalAlpha = 1; ctx.lineWidth = 1.2; ctx.strokeStyle = col.ink; ctx.stroke(); };
    const fit = (s, maxW) => { if (ctx.measureText(s).width <= maxW) return s; while (s.length > 1 && ctx.measureText(s + '…').width > maxW) s = s.slice(0, -1); return s + '…'; };
    ctx.font = font(11); ctx.textAlign = 'right';
    const fmax = F.length ? F[0].s : 1;
    F.forEach((f, i) => { const y = ys(F.length, i); node(xIn, y, 5, col.accent, 0.25 + 0.75 * f.s / fmax); ctx.fillStyle = col.ink; ctx.fillText(fit(this.featLabel(f.key), xIn - 14), xIn - 10, y); });
    hidOrder.forEach((hh, i) => { const y = ys(hidOrder.length, i); node(xHid, y, 4.5, col.coral, Math.max(0.08, cls.hid[hh] / maxHid) * Math.min(1, k * 2)); });
    ctx.textAlign = 'left';
    outs.forEach((o, i) => {
      const y = ys(outs.length, i), a = Math.max(0, k * 2 - 1);
      node(xOut, y, 4 + 6 * o.t.p, col.accent, (0.15 + 0.85 * o.t.p) * a + 0.05);
      ctx.fillStyle = i === 0 ? col.ink : col.muted; ctx.font = font(i === 0 ? 11.5 : 11);
      const pct = Math.round(o.t.p * 100) + '%';
      const room = w - (xOut + 14) - 4 - ctx.measureText(' ' + pct).width;
      ctx.fillText(fit(o.t.title, room) + ' ' + pct, xOut + 14, y);
    });
    ctx.fillStyle = col.muted; ctx.font = font(9.5); ctx.textAlign = 'center';
    ctx.fillText(`${hidOrder.length} из ${H}`, xHid, h - 10);
  }
  drawLoss() {
    const c = this.canvas('lossCanvas'); if (!c) return;
    const { ctx, w, h } = c, col = this.colors(), H = this.lossHistory;
    const l = 10, r = w - 46, t = 12, b = h - 22;
    ctx.strokeStyle = col.line; ctx.lineWidth = 1; ctx.font = `10px ${col.mono || 'monospace'}`; ctx.fillStyle = col.muted; ctx.textBaseline = 'middle';
    for (let i = 0; i <= 4; i++) { const y = t + (b - t) * i / 4; ctx.beginPath(); ctx.moveTo(l, y); ctx.lineTo(r, y); ctx.stroke(); }
    ctx.textAlign = 'left'; ctx.fillText('100%', r + 6, t); ctx.fillText('0', r + 6, b);
    const E = this.lossTarget || this.brain.model.epochs || H.length || 1;
    ctx.textAlign = 'left'; ctx.fillText('эпоха 1', l, h - 8); ctx.textAlign = 'right'; ctx.fillText('эпоха ' + E, r, h - 8);
    if (!H.length) return;
    const maxL = Math.max(...H.map(p => p[0])) || 1;
    const X = i => E === 1 ? l : l + (r - l) * i / (E - 1);
    const line = (get, color) => {
      ctx.strokeStyle = color; ctx.lineWidth = 2.2; ctx.lineJoin = 'round'; ctx.beginPath();
      H.forEach((p, i) => { const y = b - (b - t) * get(p); if (i) ctx.lineTo(X(i), y); else ctx.moveTo(X(i), y); });
      ctx.stroke();
      const i = H.length - 1, y = b - (b - t) * get(H[i]);
      ctx.fillStyle = color; ctx.beginPath(); ctx.arc(X(i), y, 3.5, 0, 7); ctx.fill();
    };
    line(p => p[0] / maxL, col.coral);
    line(p => p[1], col.teal);
    const last = H[H.length - 1];
    this.el('lossNote').textContent = `итог: ошибка ${last[0].toFixed(2)}, точность ${Math.round(last[1] * 100)}%`;
  }
  renderStats() {
    const m = this.brain.model, net = this.brain.net;
    const rows = [['Входов', U.num(net.D)], ['Скрытых нейронов', net.H], ['Тем (выходов)', net.C], ['Параметров', U.num(net.params)],
      ['Примеров для обучения', U.num(m.examples)], ['Точность на новых фразах', Math.round(m.val.acc * 100) + '%']];
    if (m.codex) rows.push(['Нейросеть Кодекса', `${m.codex.tags.length} жанров · ${Math.round(m.codex.params / 1000)} тыс.`], ['Кодекс понимает жанр', Math.round(m.codex.val.acc * 100) + '%']);
    const dl = this.el('stats'); dl.innerHTML = '';
    for (const [k, v] of rows) { const d = document.createElement('div'); const dt = document.createElement('dt'); dt.textContent = k; const dd = document.createElement('dd'); dd.textContent = v; d.append(dt, dd); dl.appendChild(d); }
  }
  renderTaught() {
    const ul = this.el('taught'); ul.innerHTML = '';
    const list = this.brain.customs;
    if (!list.length) {
      const li = document.createElement('li'); li.className = 'empty';
      li.textContent = 'Пока ничего. Напиши «когда я говорю „привет, робот“, отвечай „бип-буп“» или нажми «Не то» под моим ответом.';
      ul.appendChild(li); return;
    }
    for (const c of list) {
      const li = document.createElement('li');
      const d = document.createElement('div');
      const q = document.createElement('div'); q.className = 'tq'; q.textContent = c.p.map(p => '«' + p + '»').join(', ');
      const a = document.createElement('div'); a.className = 'ta'; a.textContent = '→ ' + c.r[0];
      d.append(q, a);
      const btn = document.createElement('button'); btn.type = 'button'; btn.className = 'btn small'; btn.textContent = 'Забыть';
      btn.addEventListener('click', () => { this.brain.forgetCustom(c.tag); this.renderTaught(); this.setStatus(); this.toast('Забыл'); if (this.brain.needsTuning) this.tune(); });
      li.append(d, btn); ul.appendChild(li);
    }
  }

  // ---------- настройки ----------
  openSettings(open) {
    this.el('settings').hidden = !open; this.el('backdrop').hidden = !open;
    if (open) { this.renderSettings(); setTimeout(() => this.el('btnSetClose').focus(), 30); }
  }
  bindSettings() {
    const $ = this.el, S = this.brain.settings, save = () => { this.brain.save(); this.renderSettings(); };
    $('setVoice').addEventListener('change', e => this.setVoice(e.target.checked, false));
    $('setRate').addEventListener('input', e => { S.rate = +e.target.value; $('rateVal').textContent = S.rate.toFixed(1); this.brain.save(); });
    $('setOnline').addEventListener('change', e => { S.online = e.target.checked; save(); });
    $('setSuper').addEventListener('change', e => { S.superOn = e.target.checked; save(); });
    $('setTier').addEventListener('change', e => { S.superTier = e.target.value; save(); });
    $('setKey').addEventListener('change', e => { S.apiKey = e.target.value.trim(); save(); if (S.apiKey) this.toast('Ключ сохранён 🔑'); });
    $('setModel').addEventListener('change', e => { S.model = e.target.value; save(); });
    $('setCodexLevel').addEventListener('change', e => { S.codexLevel = e.target.value; save(); this.renderCodex(); });
    $('setCodexAsk').addEventListener('change', e => { S.codexAsk = e.target.checked; save(); });
    $('btnClear').addEventListener('click', () => { this.clearChat(); this.openSettings(false); this.greet(); this.toast('Чат очищен'); });
    $('btnForgetAll').addEventListener('click', e => {
      const b = e.currentTarget;
      if (!b.dataset.sure) { b.dataset.sure = '1'; b.textContent = 'Точно забыть? Нажми ещё раз'; setTimeout(() => { delete b.dataset.sure; b.textContent = 'Забыть всё обо мне'; }, 4000); return; }
      delete b.dataset.sure; b.textContent = 'Забыть всё обо мне';
      this.brain.profile = { name: '', facts: [], city: null, age: 0 };
      this.brain.customs = []; this.brain.codexMem = { words: {}, recipes: [] }; this.brain.lastSpec = null; this.brain.reset(); this.brain.save();
      this.clearChat(); this.renderTaught(); this.renderStats(); this.setStatus(); this.openSettings(false); this.greet();
      this.toast('Я всё забыл. Будем знакомиться заново!');
    });
  }
  renderSettings() {
    const $ = this.el, S = this.brain.settings, Sup = Online.Super;
    $('setVoice').checked = !!S.voice; $('setRate').value = S.rate || 1; $('rateVal').textContent = (S.rate || 1).toFixed(1);
    $('setOnline').checked = S.online !== false; $('setSuper').checked = !!S.superOn; $('setTier').value = S.superTier || 'quick';
    $('setKey').value = S.apiKey || ''; $('setModel').value = S.model || 'claude-opus-5-5';
    $('setCodexLevel').value = S.codexLevel || 'high'; $('setCodexAsk').checked = S.codexAsk !== false;
    $('codexAskHint').textContent = Sup.avail(S) ? 'Claude сейчас доступен.' : 'Сейчас Claude недоступен: в приложении Claude он подключается сам, а в обычном браузере нужен ключ API ниже.';
    const inClaude = Sup.sampleState === 'ready';
    $('superSample').hidden = !inClaude; $('superApi').hidden = inClaude;
    $('superHint').textContent = inClaude
      ? 'Я открыт внутри Claude и могу сам спрашивать Claude о том, чего не знаю. Первый раз Claude попросит разрешение. Ответы тратят лимит твоего аккаунта Claude.'
      : Sup.sampleState === 'unknown' ? 'Проверяю, доступен ли Claude…'
        : 'Вставь ключ Anthropic API, и я буду спрашивать Claude о том, чего не знаю сам. Без ключа я всё равно работаю: у меня своя нейросеть.';
    const mode = Sup.mode(S);
    $('superBadge').textContent = mode ? 'включён' : S.superOn && !inClaude && !S.apiKey ? 'нужен ключ' : 'выключен';
  }
  // ---------- Кодекс ----------
  setCodex(on) {
    this.brain.settings.codexOn = !!on; this.brain.save(); this.renderCodex();
    if (on) { this.toast('🧑‍💻 Режим Кодекс: опиши игру'); this.input.focus(); } else this.toast('Кодекс выключен');
    this.chips(null);
  }
  renderCodex() {
    const S = this.brain.settings, on = !!S.codexOn;
    this.el('codexBar').hidden = !on;
    this.el('btnCodex').setAttribute('aria-pressed', on ? 'true' : 'false');
    for (const b of document.querySelectorAll('#codexBar [data-level]')) b.setAttribute('aria-checked', b.dataset.level === (S.codexLevel || 'high') ? 'true' : 'false');
    this.input.placeholder = on ? 'Опиши игру, и я её запрограммирую…' : 'Напиши Амиго…';
    this.el('codexHint').textContent = { medium: 'простые игры', high: 'эффекты, бонусы, уровни, боссы', ultra: 'долго думаю, тестирую роботом, учусь' }[S.codexLevel || 'high'];
    this.renderCodexMem();
  }
  thinkList(lines, live) {
    const ol = document.createElement('ol'); ol.className = 'think-list';
    lines.forEach((l, i) => { const li = document.createElement('li'); li.textContent = l; if (live && i === lines.length - 1) li.className = 'now'; if (/^\s/.test(l)) li.classList.add('sub'); ol.appendChild(li); });
    if (live) { const h = document.createElement('div'); h.className = 'think-head'; h.textContent = '🧠 Кодекс Ультра думает…'; const box = document.createElement('div'); box.append(h, ol); return box; }
    return ol;
  }
  thinkLog(lines, secs) {
    const d = document.createElement('details'); d.className = 'think-log';
    const s = document.createElement('summary'); s.textContent = `🧠 Как я думал · ${lines.length} ${U.plural(lines.length, 'шаг', 'шага', 'шагов')}` + (secs ? ` · ${secs} с` : '');
    d.append(s, this.thinkList(lines, false));
    return d;
  }
  codeSources() { return { engine: codexEngineModule.toString(), view: codexViewModule.toString(), main: codexStandaloneMain.toString() }; }
  blueprint(spec) {
    const b = { title: spec.title, genre: spec.genre, level: spec.level, control: spec.control, hero: spec.hero, world: spec.theme.name, lives: spec.lives, pace: spec.pace,
      things: spec.things, spawns: spec.spawns, touch: spec.touch, abilities: spec.abilities, events: spec.events, powers: spec.powers, boss: spec.boss.on ? spec.boss : undefined,
      goal: spec.goal.level ? spec.goal : undefined, timeLimit: spec.timeLimit || undefined, learned: spec.learned.length ? spec.learned : undefined };
    return JSON.stringify(b, null, 1).replace(/\n\s+(?=[\]}"\d-])/g, m => m.length > 14 ? m : ' ').slice(0, 9000);
  }
  showCode(spec) {
    if (!spec) return;
    const html = CodexView.exportHtml(spec, this.codeSources()), n = html.split('\n').length;
    const text = `Код игры «${spec.title}». Это чертёж для моего движка: из него получается игра. Всего в файле игры ${U.num(n)} строк: движок Кодекса, художник и этот чертёж.\n\`\`\`json\n${this.blueprint(spec)}\n\`\`\``;
    this.addMsg('bot', text, { src: 'codex', codexLevel: spec.level, codeSpec: spec });
    this.chips(['Быстрее', 'Добавь босса', 'Вместо героя собака']);
  }
  copyCode(spec) {
    const html = CodexView.exportHtml(spec, this.codeSources());
    const fallback = () => { const ta = document.createElement('textarea'); ta.value = html; ta.className = 'code-copy'; ta.readOnly = true; this.logEl.appendChild(ta); ta.select(); this.toast('Выдели и скопируй код из поля ниже'); this.scroll(); };
    try { navigator.clipboard.writeText(html).then(() => this.toast('Код скопирован! Вставь его в файл .html и открой в браузере 📋'), fallback); } catch (e) { fallback(); }
  }
  async downloadCode(spec) {
    const html = CodexView.exportHtml(spec, this.codeSources()), filename = U.translit(spec.title || 'igra').replace(/[^\w-]+/g, '_') + '.html';
    // внутри приложения Claude файл отдаёт само приложение (спросит разрешение)
    if (window.claude && typeof window.claude.use === 'function') {
      let dl = null;
      try { dl = await window.claude.use('downloads'); } catch (e) { dl = null; }
      if (!dl) { this.toast('Скачать здесь нельзя — скопируй код'); return this.copyCode(spec); }
      try { await dl.save({ filename, data: html }); this.toast('Игра сохранена! Открой файл в браузере 🎮'); }
      catch (e) {
        const code = e && e.code;
        if (code === 'declined') return;
        if (code === 'rate_limited') return this.toast('Подожди секунду и нажми ещё раз');
        this.toast('Скачать не получилось — скопируй код'); this.copyCode(spec);
      }
      return;
    }
    try {
      const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([html], { type: 'text/html' }));
      a.download = filename; document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 4000);
    } catch (e) { this.copyCode(spec); }
  }
  renderCodexMem() {
    const ul = this.el('codexMem'); if (!ul) return;
    ul.innerHTML = '';
    const mem = this.brain.codexMem, words = Object.entries(mem.words), seen = new Set();
    for (const r of mem.recipes) {
      const li = document.createElement('li'), d = document.createElement('div');
      const q = document.createElement('div'); q.className = 'ta'; q.textContent = '🧩 ' + r.name;
      const a = document.createElement('div'); a.className = 'tq'; a.textContent = r.explain || '';
      d.append(q, a);
      const btn = document.createElement('button'); btn.type = 'button'; btn.className = 'btn small'; btn.textContent = 'Забыть';
      btn.addEventListener('click', () => { this.brain.forgetCodex('recipe', r.name); this.renderCodexMem(); });
      li.append(d, btn); ul.appendChild(li);
    }
    for (const [k, w] of words) {
      if (seen.has(w.name)) continue; seen.add(w.name);
      const li = document.createElement('li'), d = document.createElement('div'); d.className = 'ta'; d.textContent = w.emoji + ' ' + w.name;
      const btn = document.createElement('button'); btn.type = 'button'; btn.className = 'btn small'; btn.textContent = 'Забыть';
      btn.addEventListener('click', () => { this.brain.forgetCodex('word', w.name); this.renderCodexMem(); });
      li.append(d, btn); ul.appendChild(li);
    }
    if (!ul.children.length) { const li = document.createElement('li'); li.className = 'empty'; li.textContent = 'Пока ничего. В режиме Кодекс Ультра я спрашиваю у Claude, как сделать то, чего не умею, и записываю сюда.'; ul.appendChild(li); }
  }
  toast(text) {
    const t = this.el('toast');
    t.textContent = text; t.hidden = false;
    clearTimeout(this.toastT); this.toastT = setTimeout(() => { t.hidden = true; }, 2600);
  }
}
