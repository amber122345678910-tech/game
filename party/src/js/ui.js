'use strict';
// Интерфейс поверх 3D: половинки экрана с HUD, гардероб скинов, меню, результаты.

const $ = (sel) => document.querySelector(sel);

const EDITOR_ROWS = [
  { key: 'preset', lbl: 'Готовый образ', list: () => PRESETS, name: (v) => PRESETS[v].n },
  { key: 'tone', lbl: 'Кожа', list: () => SKIN_TONES, sw: (v) => SKIN_TONES[v].c, name: (v) => SKIN_TONES[v].n },
  { key: 'face', lbl: 'Лицо', list: () => FACES, ids: true },
  { key: 'hair', lbl: 'Причёска', list: () => HAIRS, ids: true },
  { key: 'hairColor', lbl: 'Цвет волос', list: () => HAIR_COLORS, sw: (v) => HAIR_COLORS[v].c, name: (v) => HAIR_COLORS[v].n },
  { key: 'hat', lbl: 'Шапка', list: () => HATS, ids: true },
  { key: 'shirt', lbl: 'Футболка', list: () => PALETTE, sw: (v) => PALETTE[v].c, name: (v) => PALETTE[v].n },
  { key: 'pattern', lbl: 'Рисунок', list: () => PATTERNS, ids: true },
  { key: 'bottom', lbl: 'Низ', list: () => BOTTOMS, ids: true },
  { key: 'pants', lbl: 'Цвет низа', list: () => PALETTE, sw: (v) => PALETTE[v].c, name: (v) => PALETTE[v].n },
  { key: 'back', lbl: 'На спине', list: () => BACKS, ids: true },
  { key: 'trail', lbl: 'След', list: () => TRAILS, ids: true },
];

const UI = {
  halves: [],
  timers: {},

  init() {
    const wrap = $('#halves');
    for (let i = 0; i < 2; i++) {
      const h = document.createElement('div');
      h.className = 'half h' + i;
      h.innerHTML = `
        <div class="tag"><span class="dot"></span><span class="nm"></span></div>
        <div class="hud"></div>
        <div class="progress" hidden></div>
        <div class="toast"></div>
        <div class="banner"></div>
        <div class="sub"></div>
        <div class="prompt" hidden></div>
        <div class="hint" hidden></div>
        <div class="vignette"></div>
        <div class="flash"></div>
        <div class="editor" hidden></div>
        <div class="ready-badge" hidden></div>
        <div class="touch" hidden>
          <div class="stick" hidden><div class="knob"></div></div>
          <div class="tbtn" data-b="jump" style="right:24px;bottom:28px">⤒</div>
          <div class="tbtn" data-b="action" style="right:108px;bottom:22px;width:58px;height:58px;font-size:22px">✋</div>
        </div>`;
      wrap.appendChild(h);
      const q = (s) => h.querySelector(s);
      this.halves.push({
        el: h, tag: q('.tag'), nm: q('.nm'), hud: q('.hud'), progress: q('.progress'), toast: q('.toast'), banner: q('.banner'), sub: q('.sub'),
        prompt: q('.prompt'), hint: q('.hint'), vignette: q('.vignette'), flash: q('.flash'), editor: q('.editor'), ready: q('.ready-badge'), touch: q('.touch'),
      });
      Input.touchUI[i] = { half: h, stick: q('.stick'), knob: q('.knob'), jump: q('[data-b=jump]'), action: q('[data-b=action]') };
    }
    this.bindMenus();
  },

  setSplit(on) {
    $('#divider').hidden = !on;
    this.halves[1].el.hidden = !on;
    this.halves[0].el.classList.toggle('full', !on);
    $('#halves').hidden = false;
  },

  hideHalves(hide) { $('#halves').hidden = hide; },

  setNames() {
    for (let i = 0; i < 2; i++) this.halves[i].nm.textContent = Game.players[i].name;
    this.updateScore();
  },

  updateScore() {
    const sb = $('#scorebar');
    const [a, b] = Store.data.wins;
    sb.innerHTML = `<span class="n a">${esc(Game.players[0].name)}</span><span class="s">${a}</span><span style="opacity:.6">:</span><span class="s">${b}</span><span class="n b">${esc(Game.players[1].name)}</span>`;
  },

  showScore(on) { $('#scorebar').hidden = !on; },

  hud(i, html) {
    const el = this.halves[i].hud;
    if (el._html !== html) { el._html = html; el.innerHTML = html; }
  },

  progress(i, html) {
    const el = this.halves[i].progress;
    el.hidden = !html;
    if (html && el._html !== html) { el._html = html; el.innerHTML = html; }
  },

  prompt(i, html) {
    const el = this.halves[i].prompt;
    el.hidden = !html;
    if (html && el._html !== html) { el._html = html; el.innerHTML = html; }
  },

  hint(i, html) {
    const el = this.halves[i].hint;
    el.hidden = !html || Game.touchMode;
    if (html && el._html !== html) { el._html = html; el.innerHTML = html; }
  },

  banner(i, text, o = {}) {
    const targets = i === -1 ? [0, 1] : [i];
    for (const k of targets) {
      const H = this.halves[k];
      H.banner.className = 'banner' + (o.cls ? ' ' + o.cls : '');
      H.banner.textContent = text;
      void H.banner.offsetWidth;
      H.banner.classList.add('show');
      H.sub.textContent = o.sub || '';
      H.sub.classList.toggle('show', !!o.sub);
      clearTimeout(this.timers['b' + k]);
      if (o.dur !== 0) this.timers['b' + k] = setTimeout(() => { H.banner.classList.remove('show'); H.sub.classList.remove('show'); }, (o.dur || 1.4) * 1000);
    }
  },

  clearBanner(i) {
    for (const k of i === -1 ? [0, 1] : [i]) {
      this.halves[k].banner.classList.remove('show');
      this.halves[k].sub.classList.remove('show');
      clearTimeout(this.timers['b' + k]);
    }
  },

  toast(i, text, color) {
    for (const k of i === -1 ? [0, 1] : [i]) {
      const el = this.halves[k].toast;
      el.textContent = text;
      el.style.color = color || '#fff';
      el.classList.add('show');
      clearTimeout(this.timers['t' + k]);
      this.timers['t' + k] = setTimeout(() => el.classList.remove('show'), 1600);
    }
  },

  flash(i) {
    const el = this.halves[i].flash;
    el.classList.add('on');
    requestAnimationFrame(() => requestAnimationFrame(() => el.classList.remove('on')));
  },

  vignette(i, on) { this.halves[i].vignette.classList.toggle('on', !!on); },

  clearHud() {
    for (let i = 0; i < 2; i++) {
      this.hud(i, '');
      this.progress(i, '');
      this.prompt(i, '');
      this.hint(i, '');
      this.vignette(i, false);
      this.clearBanner(i);
      this.halves[i].ready.hidden = true;
    }
  },

  // ------------------------------------------------------------ гардероб

  openEditor(i, initial) {
    const H = this.halves[i];
    const p = Game.players[i];
    const same = PRESETS.findIndex((pr) => Object.keys(pr.s).every((k) => pr.s[k] === p.skin[k]));
    H.editorState = { row: 0, preset: same, initial };
    H.editor.hidden = false;
    H.ready.hidden = true;
    const keys = i === 0 ? '<kbd>W</kbd><kbd>S</kbd> выбор · <kbd>A</kbd><kbd>D</kbd> менять · <kbd>Пробел</kbd> готово'
      : '<kbd>↑</kbd><kbd>↓</kbd> выбор · <kbd>←</kbd><kbd>→</kbd> менять · <kbd>Enter</kbd> готово';
    H.editor.innerHTML = `
      <h3 style="color:${p.color}">${i === 0 ? 'ИГРОК 1' : 'ИГРОК 2'} · ГАРДЕРОБ</h3>
      <input type="text" id="name-${i}" maxlength="14" value="${esc(p.name)}" aria-label="Имя игрока ${i + 1}">
      <div class="rows"></div>
      <div class="ed-btns">
        <button class="btn small" data-act="random">🎲 Случайно</button>
        <button class="btn go small" data-act="ready">✔ Готово</button>
      </div>
      <div class="ed-hint">${keys}</div>`;
    const rows = H.editor.querySelector('.rows');
    EDITOR_ROWS.forEach((r, ri) => {
      const row = document.createElement('div');
      row.className = 'row';
      row.innerHTML = `<button data-d="-1" aria-label="назад">◀</button><div class="mid"><div class="lbl">${r.lbl}</div><div class="val"></div></div><button data-d="1" aria-label="вперёд">▶</button>`;
      row.addEventListener('click', (e) => {
        const b = e.target.closest('button');
        H.editorState.row = ri;
        if (b) this.editorChange(i, +b.dataset.d);
        this.renderEditor(i);
      });
      rows.appendChild(row);
    });
    const inp = H.editor.querySelector('input');
    inp.addEventListener('input', () => {
      const n = inp.value.trim().slice(0, 14) || 'Игрок ' + (i + 1);
      p.setName(n);
      Store.data.names[i] = n;
      Store.save();
      this.setNames();
    });
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === 'Escape') inp.blur(); e.stopPropagation(); });
    H.editor.querySelector('[data-act=random]').addEventListener('click', () => this.editorRandom(i));
    H.editor.querySelector('[data-act=ready]').addEventListener('click', () => Game.editorDone(i));
    this.renderEditor(i);
  },

  closeEditor(i) {
    const H = this.halves[i];
    H.editor.hidden = true;
    H.editor.innerHTML = '';
    H.editorState = null;
  },

  editorOpen(i) { return !!this.halves[i].editorState; },

  editorValue(i, r) {
    const p = Game.players[i];
    if (r.key === 'preset') return Math.max(0, this.halves[i].editorState.preset);
    const v = p.skin[r.key];
    if (r.ids) return Math.max(0, r.list().findIndex((x) => x.id === v));
    return v;
  },

  editorChange(i, d) {
    const H = this.halves[i];
    const r = EDITOR_ROWS[H.editorState.row];
    const p = Game.players[i];
    const n = r.list().length;
    const v = (this.editorValue(i, r) + d + n) % n;
    let skin = { ...p.skin };
    if (r.key === 'preset') {
      const cur = H.editorState.preset;
      const nv = cur < 0 ? (d > 0 ? 0 : n - 1) : v;
      H.editorState.preset = nv;
      skin = { ...PRESETS[nv].s };
    } else {
      if (r.ids) skin[r.key] = r.list()[v].id;
      else skin[r.key] = v;
      H.editorState.preset = -1;
    }
    p.setSkin(skin);
    Store.data.skins[i] = skin;
    Store.save();
    Sound.play('click');
    this.renderEditor(i);
  },

  editorRandom(i) {
    const p = Game.players[i];
    const skin = randomSkin();
    this.halves[i].editorState.preset = -1;
    p.setSkin(skin);
    Store.data.skins[i] = skin;
    Store.save();
    Sound.play('select');
    this.renderEditor(i);
  },

  renderEditor(i) {
    const H = this.halves[i];
    if (!H.editorState) return;
    const rows = H.editor.querySelectorAll('.row');
    EDITOR_ROWS.forEach((r, ri) => {
      const v = this.editorValue(i, r);
      let name = r.ids ? r.list()[v].n : r.name(v);
      if (r.key === 'preset' && H.editorState.preset < 0) name = 'Свой образ';
      const sw = r.sw ? `<span class="sw" style="background:${r.sw(v)}"></span>` : '';
      rows[ri].querySelector('.val').innerHTML = sw + esc(name);
      rows[ri].classList.toggle('sel', ri === H.editorState.row);
    });
    const sel = rows[H.editorState.row];
    if (sel && sel.scrollIntoView) sel.scrollIntoView({ block: 'nearest' });
  },

  editorInput(i, s) {
    const H = this.halves[i];
    if (!H.editorState) return;
    if (document.activeElement && document.activeElement.id === 'name-' + i) return;
    if (s.menuUp) { H.editorState.row = (H.editorState.row - 1 + EDITOR_ROWS.length) % EDITOR_ROWS.length; Sound.play('tick'); this.renderEditor(i); }
    if (s.menuDown) { H.editorState.row = (H.editorState.row + 1) % EDITOR_ROWS.length; Sound.play('tick'); this.renderEditor(i); }
    if (s.menuLeft) this.editorChange(i, -1);
    if (s.menuRight) this.editorChange(i, 1);
    if (s.jumpP) Game.editorDone(i);
    if (s.actionP) this.editorRandom(i);
  },

  showReady(i, text, sub) {
    const el = this.halves[i].ready;
    el.hidden = !text;
    if (text) el.innerHTML = esc(text) + (sub ? `<small>${esc(sub)}</small>` : '');
  },

  // ------------------------------------------------------------ экраны

  show(id, on = true) {
    const el = $('#' + id);
    el.hidden = !on;
    if (on) {
      const b = el.querySelector('.btn.go, .btn');
      if (b) setTimeout(() => b.focus({ preventScroll: true }), 30);
    }
  },

  bindMenus() {
    document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => { Sound.play('click'); b.closest('.screen').hidden = true; }));
    $('#btn-play').addEventListener('click', () => { Sound.init(); Sound.play('select'); Game.startFromTitle(); });
    $('#btn-help').addEventListener('click', () => { Sound.init(); Sound.play('click'); this.show('help'); });
    $('#btn-settings').addEventListener('click', () => { Sound.init(); Sound.play('click'); this.openSettings(); });
    $('#btn-full').addEventListener('click', () => {
      Sound.init();
      const el = document.documentElement;
      try {
        if (document.fullscreenElement) document.exitFullscreen();
        else if (el.requestFullscreen) el.requestFullscreen().catch(() => {});
      } catch (e) { /* полноэкранный режим недоступен */ }
    });
    $('#pz-resume').addEventListener('click', () => Game.resume());
    $('#pz-restart').addEventListener('click', () => { Game.resume(); Game.restartMode(); });
    $('#pz-lobby').addEventListener('click', () => { Game.resume(); Game.toLobby(); });
    $('#pz-settings').addEventListener('click', () => this.openSettings());
    $('#pz-help').addEventListener('click', () => this.show('help'));
    $('#res-again').addEventListener('click', () => Game.resultChoice('again'));
    $('#res-lobby').addEventListener('click', () => Game.resultChoice('lobby'));

    const music = $('#set-music');
    const sfx = $('#set-sfx');
    music.addEventListener('input', () => { Store.data.settings.music = +music.value; Sound.applyVolumes(); Store.save(); });
    sfx.addEventListener('input', () => { Store.data.settings.sfx = +sfx.value; Sound.applyVolumes(); Store.save(); });
    $('#set-quality').addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      Store.data.settings.quality = b.dataset.v;
      Store.save();
      applyQuality(b.dataset.v);
      this.syncSettings();
    });
    $('#set-pad').addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      Store.data.settings.pad = +b.dataset.v;
      Store.save();
      this.syncSettings();
    });
    $('#set-reset').addEventListener('click', () => {
      Store.data.wins = [0, 0];
      Store.data.games = {};
      Store.save();
      this.updateScore();
      if (Game.mode && Game.mode.refreshBoard) Game.mode.refreshBoard();
      Sound.play('click');
    });
  },

  openSettings() {
    this.syncSettings();
    this.show('settings');
  },

  syncSettings() {
    const s = Store.data.settings;
    $('#set-music').value = s.music;
    $('#set-sfx').value = s.sfx;
    document.querySelectorAll('#set-quality button').forEach((b) => b.classList.toggle('on', b.dataset.v === s.quality));
    document.querySelectorAll('#set-pad button').forEach((b) => b.classList.toggle('on', +b.dataset.v === s.pad));
  },

  buildGameButtons() {
    const box = $('#pz-games');
    box.innerHTML = '';
    for (const id of GAME_ORDER) {
      const m = MODES[id];
      const b = document.createElement('button');
      b.className = 'gbtn';
      b.style.background = m.color;
      b.innerHTML = `<span class="ic">${m.icon}</span><span>${esc(m.title)}</span>`;
      b.addEventListener('click', () => { Game.resume(); Game.startMode(id); });
      box.appendChild(b);
    }
  },

  showResults(who, lines) {
    $('#res-who').innerHTML = who;
    $('#res-lines').innerHTML = lines || '';
    this.show('results');
  },

  hideResults() { $('#results').hidden = true; },
};
