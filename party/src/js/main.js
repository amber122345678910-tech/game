'use strict';
// Главный цикл: ввод → физика с фиксированным шагом → анимации → две камеры, экран пополам.

const STEP = 1 / 120;

const Game = {
  players: [],
  mode: null,
  modeId: null,
  state: 'loading',
  paused: false,
  split: false,
  touchMode: false,
  acc: 0,
  time: 0,

  init() {
    Store.load();
    initRenderer(document.getElementById('view'));
    Input.init();
    UI.init();
    this.players = [new Player(0), new Player(1)];
    UI.setNames();
    UI.buildGameButtons();
    this.titleCam = new THREE.PerspectiveCamera(55, 1, 0.1, 2600);
    this.mode = Lobby;
    this.modeId = 'lobby';
    Lobby.enter();
    this.state = 'title';
    UI.hideHalves(true);
    UI.showScore(false);
    window.addEventListener('resize', () => resizeRenderer());
    document.getElementById('loading').hidden = true;
    this.last = performance.now();
    requestAnimationFrame((t) => this.frame(t));
  },

  other(p) { return this.players[1 - p.idx]; },
  playing() { return this.state === 'game' && !this.paused; },

  enableTouch() {
    this.touchMode = true;
    for (const h of UI.halves) { h.touch.hidden = false; h.hint.hidden = true; }
  },

  startFromTitle() {
    document.getElementById('title').hidden = true;
    this.state = 'game';
    this.split = true;
    UI.hideHalves(false);
    UI.setSplit(true);
    UI.showScore(true);
    UI.setNames();
    if (this.mode !== Lobby) this.startMode('lobby');
    this.players.forEach((p, i) => p.spawn(Lobby.spawnPos(i), Math.PI));
    this.openEditor(0, true);
    this.openEditor(1, true);
    Sound.init();
    Music.play('lobby');
  },

  openEditor(i, initial) {
    const p = this.players[i];
    UI.openEditor(i, initial);
    p.frozen = true;
    p.vel.set(0, 0, 0);
    p.camMode = 'mirror';
    p.mirrorHeading = Math.PI;
    if (!initial) p.pos.set(Lobby.wardrobe.x, 0.4, Lobby.wardrobe.z);
    p.heading = p.mirrorHeading;
    Sound.play('select');
  },

  editorDone(i) {
    if (!UI.editorOpen(i)) return;
    const p = this.players[i];
    UI.closeEditor(i);
    p.frozen = false;
    p.camMode = 'follow';
    p.heading = p.mirrorHeading;
    p.camYaw = p.heading + Math.PI;
    Store.data.skins[i] = { ...p.skin };
    Store.save();
    UI.setNames();
    if (this.mode === Lobby) {
      Lobby.refreshBoard();
      UI.toast(i, 'Красота! 😎', '#ffd23f');
    }
    Sound.play('select');
  },

  startMode(id) {
    UI.hideResults();
    for (let i = 0; i < 2; i++) {
      if (UI.editorOpen(i)) this.editorDone(i);
    }
    if (this.mode) this.mode.dispose();
    this.mode = id === 'lobby' ? Lobby : MODES[id];
    this.modeId = id;
    this.acc = 0;
    for (const p of this.players) {
      p.dead = false;
      p.avatar.root.visible = true;
    }
    this.mode.enter();
    UI.setNames();
    Sound.play('portal');
  },

  toLobby() { this.startMode('lobby'); },
  restartMode() { this.startMode(this.modeId); },

  resultChoice(c) {
    UI.hideResults();
    Sound.play('select');
    if (c === 'again') this.restartMode();
    else this.toLobby();
  },

  pause() {
    if (this.state !== 'game' || this.paused) return;
    this.paused = true;
    UI.show('pause');
    Sound.play('click');
  },

  resume() {
    this.paused = false;
    document.getElementById('pause').hidden = true;
    document.getElementById('settings').hidden = true;
    document.getElementById('help').hidden = true;
  },

  handleGlobalKeys(states) {
    const esc = Input.pressed.has('Escape') || states.some((s) => s.pause);
    const resultsOpen = !document.getElementById('results').hidden;
    if (this.state === 'title') {
      if (Input.anyPressed(['Enter', 'NumpadEnter']) && document.getElementById('help').hidden && document.getElementById('settings').hidden) {
        Sound.init();
        this.startFromTitle();
      }
      return;
    }
    if (resultsOpen) {
      if (states.some((s) => s.jumpP)) this.resultChoice('again');
      else if (esc || states.some((s) => s.actionP)) this.resultChoice('lobby');
      return;
    }
    if (esc) {
      const overlays = ['help', 'settings'].map((id) => document.getElementById(id)).filter((e) => !e.hidden);
      if (overlays.length) overlays.forEach((e) => { e.hidden = true; });
      else if (this.paused) this.resume();
      else this.pause();
    }
  },

  frame(now) {
    const dt = clamp((now - this.last) / 1000, 0, 0.05);
    this.last = now;
    this.time += dt;
    const states = Input.poll();
    this.handleGlobalKeys(states);

    if (this.state === 'game' && !this.paused) {
      this.watchFps(dt);
      for (let i = 0; i < 2; i++) {
        if (UI.editorOpen(i)) {
          UI.editorInput(i, states[i]);
          this.players[i].setInput(EMPTY_INPUT);
          const p = this.players[i];
          p.heading = p.mirrorHeading + Math.sin(this.time * 0.9) * 0.6;
        } else this.players[i].setInput(states[i]);
      }
      this.acc += dt;
      let n = 0;
      while (this.acc >= STEP && n < 10) {
        this.physics(STEP);
        this.acc -= STEP;
        n++;
      }
      if (n === 10) this.acc = 0;
      for (const p of this.players) p.update(dt);
      this.mode.update(dt);
    } else if (this.state === 'title') {
      for (const p of this.players) { p.setInput(EMPTY_INPUT); p.update(dt); }
      if (this.mode.update) this.mode.update(dt);
    }
    FX.update(dt);
    updateSkyFrame(dt, this.time);
    this.render(dt);
    Input.endFrame();
    requestAnimationFrame((t) => this.frame(t));
  },

  // Если компьютер не успевает — сами понижаем графику (пока игрок не выбрал её вручную).
  watchFps(dt) {
    const f = (this.fps = this.fps || { t: 0, n: 0, skip: 2 });
    f.t += dt;
    f.n++;
    if (f.t < 4) return;
    const fps = f.n / f.t;
    f.t = 0;
    f.n = 0;
    if (f.skip > 0) { f.skip--; return; }
    const s = Store.data.settings;
    if (s.autoQ === false || fps >= 32) return;
    const next = s.quality === 'high' ? 'mid' : s.quality === 'mid' ? 'low' : null;
    if (!next) return;
    s.quality = next;
    Store.save();
    applyQuality(next);
    f.skip = 1;
    UI.toast(-1, next === 'mid' ? 'Графика: средне (для плавности)' : 'Графика: быстро (для плавности)', '#cfd6ea');
  },

  physics(dt) {
    World.step(dt);
    World.dynamic.length = 0;
    if (this.mode.playerCollide !== false) for (const p of this.players) if (!p.dead) World.dynamic.push(p.box);
    for (const p of this.players) p.depenetrate();
    for (const p of this.players) p.step(dt);
    if (this.mode.fixed) this.mode.fixed(dt);
  },

  render(dt) {
    const r = R.renderer;
    const W = R.w;
    const H = R.h;
    if (this.state === 'title') {
      const cam = this.titleCam;
      const a = this.time * 0.06;
      cam.position.set(Math.sin(a) * 58, 26, 20 + Math.cos(a) * 58);
      cam.lookAt(0, 6, -4);
      if (Math.abs(cam.aspect - W / H) > 1e-4) { cam.aspect = W / H; cam.updateProjectionMatrix(); }
      for (const p of this.players) p.nameTag.visible = true;
      focusShadow(V3(0, 0, 0));
      R.sky.position.copy(cam.position);
      r.setViewport(0, 0, W, H);
      r.setScissor(0, 0, W, H);
      r.render(R.scene, cam);
      return;
    }
    const hw = Math.floor(W / 2);
    for (let i = 0; i < 2; i++) {
      const p = this.players[i];
      p.updateCamera(dt, hw / H);
      const own = p.nameTag.visible;
      p.nameTag.visible = false;
      const o = this.other(p);
      o.nameTag.visible = !o.dead && o.avatar.root.visible;
      focusShadow(p.camMode === 'follow' ? p.camTarget : p.pos);
      R.sky.position.copy(p.cam.position);
      const x = i === 0 ? 0 : W - hw;
      r.setViewport(x, 0, hw, H);
      r.setScissor(x, 0, hw, H);
      r.render(R.scene, p.cam);
      p.nameTag.visible = own;
    }
  },
};

window.addEventListener('load', () => {
  // Ждём шрифт (до 1.5 с), чтобы надписи на табличках нарисовались им, а не запасным.
  const font = document.fonts && document.fonts.load ? document.fonts.load('900 64px "Rubik"').catch(() => {}) : Promise.resolve();
  Promise.race([font, new Promise((r) => setTimeout(r, 1500))]).then(boot);
});

function boot() {
  try {
    Game.init();
  } catch (e) {
    const el = document.getElementById('loading');
    el.hidden = false;
    el.textContent = 'Не получилось запустить 3D (WebGL). Попробуй другой браузер. ' + e.message;
    throw e;
  }
}
