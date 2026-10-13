/* ===== 06_online.js ===== */
// Связь с внешним миром (по желанию): Википедия, погода Open-Meteo и «супер-мозг» Claude.
// Всё это необязательно: без интернета Амиго работает сам.
const Online = (() => {
  async function getJSON(url, ms = 9000) {
    const ctl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    const timer = ctl ? setTimeout(() => ctl.abort(), ms) : null;
    try {
      const r = await fetch(url, ctl ? { signal: ctl.signal } : undefined);
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return await r.json();
    } finally { if (timer) clearTimeout(timer); }
  }

  // ---------- Википедия ----------
  async function wiki(query) {
    const q = String(query).trim().slice(0, 200);
    if (!q) return null;
    const url = 'https://ru.wikipedia.org/w/api.php?action=query&format=json&origin=*&redirects=1&prop=extracts|info&inprop=url&exintro=1&explaintext=1&exsentences=3' +
      '&generator=search&gsrlimit=3&gsrsearch=' + encodeURIComponent(q);
    const j = await getJSON(url);
    const pages = j && j.query && j.query.pages ? Object.values(j.query.pages) : [];
    pages.sort((a, b) => (a.index || 0) - (b.index || 0));
    for (const p of pages) {
      const ex = (p.extract || '').replace(/\s*\([^()]*(?:\([^()]*\)[^()]*)*\)/g, '').replace(/\s+/g, ' ').trim();
      if (!ex || /может (?:означать|относиться|иметь значения)|значения:?$/.test(ex)) continue;
      return { title: p.title, text: ex.length > 700 ? ex.slice(0, 700).replace(/\s+\S*$/, '') + '…' : ex,
        url: p.fullurl || 'https://ru.wikipedia.org/wiki/' + encodeURIComponent(p.title.replace(/ /g, '_')) };
    }
    return null;
  }

  // ---------- погода ----------
  async function geocode(name) {
    const j = await getJSON('https://geocoding-api.open-meteo.com/v1/search?count=1&language=ru&format=json&name=' + encodeURIComponent(name));
    const r = j && j.results && j.results[0];
    return r ? { name: r.name, lat: r.latitude, lon: r.longitude, country: r.country || '' } : null;
  }
  async function forecast(c) {
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${c.lat}&longitude=${c.lon}` +
      '&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m' +
      '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=3&wind_speed_unit=ms';
    return getJSON(url);
  }

  // ---------- супер-мозг: Claude ----------
  // В приложении Claude страница может спросить Claude сама (возможность sample).
  // В обычном браузере — через ключ Anthropic API, который пользователь вводит в настройках.
  const Super = {
    sample: null, sampleState: 'unknown', // unknown | ready | off
    init() {
      try {
        if (typeof window !== 'undefined' && window.claude && typeof window.claude.use === 'function') {
          window.claude.use('sample').then(s => { this.sample = s; this.sampleState = s ? 'ready' : 'off'; if (this.onChange) this.onChange(); })
            .catch(() => { this.sampleState = 'off'; });
        } else this.sampleState = 'off';
      } catch (e) { this.sampleState = 'off'; }
    },
    // доступен ли Claude вообще (даже если супер-мозг для разговоров выключен) — для вопросов Кодекса «как это сделать»
    avail(settings) {
      if (this.sample && this.sampleState === 'ready') return 'sample';
      if (settings.apiKey) return 'api';
      return null;
    },
    mode(settings) {
      if (!settings.superOn) return null;
      if (this.sample && this.sampleState === 'ready') return 'sample';
      if (settings.apiKey) return 'api';
      return null;
    },
    rules(profile) {
      const facts = (profile.facts || []).slice(-10).map(f => '- ' + f).join('\n');
      return 'Ты — Амиго, весёлая и добрая нейросеть-друг. «Амиго» по-испански значит «друг». Ты живёшь в браузере пользователя.\n' +
        'Говори всегда от лица Амиго: называй себя Амиго, не представляйся другим именем и не начинай ответы с рассказа о том, какая ты модель. ' +
        'Если тебя прямо спросят, как ты устроен, отвечай честно: у Амиго своя маленькая нейросеть, а на сложные вопросы ему помогает отвечать «супер-мозг» — модель Claude от Anthropic.\n' +
        'Как отвечать: на языке пользователя (обычно по-русски), тепло и по делу. Длина — сколько нужно для вопроса: на болтовню коротко, ' +
        'а если просят рассказ, стих, подробное объяснение, план или код — пиши полностью. Можно **жирный**, списки и блоки кода ```. Эмодзи — к месту. ' +
        'Пользователь может быть ребёнком, поэтому будь добрым и безопасным. Не выдумывай факты: если не уверен, так и скажи. ' +
        'С домашними заданиями объясняй решение по шагам, чтобы человек его понял. Если просят игру, скажи, что можно написать «сделай игру ...», и Амиго запустит её прямо в чате.\n' +
        (profile.name ? `Пользователя зовут ${profile.name}.\n` : '') +
        (facts ? 'Что известно о пользователе:\n' + facts + '\n' : '') +
        'Сегодня: ' + new Date().toLocaleDateString('ru-RU', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }) + '.';
    },
    // history — [{role:'user'|'assistant', content}] последних реплик; text — новый вопрос
    // opts: raw — без правил Амиго (для игр), tier — уровень модели, effort и maxTokens — для ключа API
    async ask(settings, profile, history, text, onText, signal, opts = {}) {
      const mode = opts.force ? this.avail(settings) : this.mode(settings);
      if (!mode) throw { code: 'no_super' };
      const turns = history.filter(t => t.content && t.content.trim()).slice(-12);
      while (turns.length && turns[0].role !== 'user') turns.shift();
      turns.push({ role: 'user', content: text });
      if (mode === 'sample') {
        const input = opts.raw ? [{ role: 'user', content: text }] : [{ role: 'user', content: this.rules(profile) + '\n\nДалее — разговор с пользователем.' }, ...turns];
        const tier = opts.tier || (settings.superTier === 'smart' ? 'default' : 'quick');
        try {
          const r = await this.sample(input, { cache: false, modelTier: tier, onText: u => onText && onText(u.text), signal });
          return { text: r.text, via: 'Claude', truncated: r.truncated };
        } catch (e) {
          if (e && (e.code === 'not_granted' || e.code === 'sampling_disabled' || e.code === 'not_declared' || e.code === 'capability_disabled' || e.code === 'capability_removed')) {
            this.sampleState = 'off'; if (this.onChange) this.onChange();
          }
          throw e;
        }
      }
      return this.api(settings, profile, opts.raw ? [{ role: 'user', content: text }] : turns, onText, signal, opts);
    },
    // прямой запрос к Anthropic Messages API с потоковой передачей ответа
    async api(settings, profile, turns, onText, signal, opts = {}) {
      const model = settings.model || 'claude-opus-5-5';
      const body = { model, max_tokens: opts.maxTokens || 16000, stream: true, messages: turns, output_config: { effort: opts.effort || 'low' } };
      if (!opts.raw) body.system = this.rules(profile);
      const headers = { 'content-type': 'application/json', 'x-api-key': settings.apiKey, 'anthropic-version': '2023-06-01', 'anthropic-dangerous-direct-browser-access': 'true' };
      // для Opus и Sonnet: если запрос отклонён фильтрами, сервер сам попробует подходящую модель
      if (!/haiku/.test(model)) { body.fallbacks = 'default'; headers['anthropic-beta'] = 'server-side-fallback-2026-07-01'; }
      let res;
      try { res = await fetch('https://api.anthropic.com/v1/messages', { method: 'POST', headers, body: JSON.stringify(body), signal }); }
      catch (e) { throw { code: e && e.name === 'AbortError' ? 'cancelled' : 'network' }; }
      if (!res.ok) {
        let msg = ''; try { const j = await res.json(); msg = j.error && j.error.message || ''; } catch (e) { /* пусто */ }
        throw { code: res.status === 401 ? 'bad_key' : res.status === 429 ? 'rate_limited' : res.status === 529 ? 'overloaded' : res.status === 403 ? 'forbidden' : 'http', status: res.status, message: msg };
      }
      const reader = res.body.getReader(), dec = new TextDecoder();
      let buf = '', text = '', stop = '';
      try { for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        let i;
        while ((i = buf.indexOf('\n\n')) >= 0) {
          const chunk = buf.slice(0, i); buf = buf.slice(i + 2);
          const line = chunk.split('\n').find(l => l.startsWith('data:'));
          if (!line) continue;
          let ev; try { ev = JSON.parse(line.slice(5)); } catch (e) { continue; }
          if (ev.type === 'content_block_delta' && ev.delta && ev.delta.type === 'text_delta') { text += ev.delta.text; if (onText) onText(text); }
          else if (ev.type === 'message_delta' && ev.delta && ev.delta.stop_reason) stop = ev.delta.stop_reason;
          else if (ev.type === 'error') throw { code: ev.error && ev.error.type === 'overloaded_error' ? 'overloaded' : 'http', message: ev.error && ev.error.message, text };
        }
      } } catch (e) {
        if (e && e.name === 'AbortError') throw { code: 'cancelled', text };
        if (e && e.code) throw e;
        throw { code: 'network', text };
      }
      if (stop === 'refusal') throw { code: 'refused', text: '' };
      if (!text.trim()) throw { code: 'empty' };
      return { text, via: 'Claude', truncated: stop === 'max_tokens' };
    },
  };
  function superError(e) {
    const c = e && e.code;
    return c === 'bad_key' ? 'Ключ API не подошёл. Проверь его в настройках.'
      : c === 'rate_limited' ? 'Супер-мозг сейчас перегружен запросами. Попробуй чуть позже.'
      : c === 'overloaded' ? 'Сервер Claude сейчас перегружен. Попробуй ещё раз через минуту.'
      : c === 'refused' ? 'Супер-мозг не стал отвечать на этот вопрос.'
      : c === 'not_granted' ? 'Ты не разрешил мне спрашивать Claude. Это можно изменить в настройках доступа страницы.'
      : c === 'network' ? 'Не получилось связаться с Claude: нет интернета?'
      : c === 'session_expired' ? 'Нужно заново войти в Claude.'
      : 'Супер-мозг сейчас недоступен.';
  }

  return { getJSON, wiki, geocode, forecast, Super, superError };
})();
