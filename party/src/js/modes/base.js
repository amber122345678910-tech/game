'use strict';
// Общая основа мини-игр: заставка с правилами → отсчёт 3-2-1 → игра → итог.

const MODES = {};
const GAME_ORDER = ['obby', 'slap', 'blocks', 'soccer', 'glass', 'chained', 'lava'];

function disposeTree(root) {
  root.traverse((o) => {
    if (o.geometry && !AV_SHARED.has(o.geometry) && !o.geometry.userData.keep) o.geometry.dispose();
    if (o.material) {
      for (const m of Array.isArray(o.material) ? o.material : [o.material]) {
        if (m.userData.cached) continue;
        if (m.map && !SHARED_TEX.has(m.map)) m.map.dispose();
        m.dispose();
      }
    }
  });
}

class MiniGame {
  constructor(def) {
    Object.assign(this, {
      theme: 'day', music: 'lobby', ability: null, coop: false, camDist: 15, camPitch: 0.3, introTime: 3.2,
      respawnDelay: 1.6, autoRespawn: true, water: false, waterY: -6, killY: -60,
    }, def);
    MODES[this.id] = this;
  }

  enter() {
    World.clear();
    World.killY = this.killY;
    this.root = new THREE.Group();
    R.scene.add(this.root);
    setTheme(this.theme);
    R.water.visible = !!this.water;
    R.water.position.y = this.waterY;
    this.phase = 'intro';
    this.t = 0;
    this.playT = 0;
    this.endT = 0;
    this.result = null;
    this.spawns = [{ pos: V3(-3, 0, 0), heading: Math.PI }, { pos: V3(3, 0, 0), heading: Math.PI }];
    for (const p of Game.players) {
      p.ability = this.ability;
      p.power = {};
      p.dmg = 0;
      p.score = 0;
      p.speedMul = 1;
      p.jumpMul = 1;
      p.gravMul = 1;
      p.frozen = true;
      p.camMode = 'follow';
      p.camDist = this.camDist;
      p.camPitch = this.camPitch;
      p.avatar.setGlove(null);
      p.avatar.cheer = false;
      p.checkpoint.index = 0;
      p.stats = {};
    }
    this.build();
    this.spawnPlayers();
    UI.clearHud();
    UI.banner(-1, this.icon + ' ' + this.title, { sub: this.rules, dur: this.introTime - 0.2, cls: 'small' });
    for (let i = 0; i < 2; i++) UI.hint(i, this.hintFor(i));
    Music.play(this.music);
  }

  hintFor(i) {
    const k = i === 0 ? '<kbd>WASD</kbd> бег · <kbd>Пробел</kbd> прыжок · <kbd>Q</kbd><kbd>E</kbd> камера' : '<kbd>Стрелки</kbd> бег · <kbd>Enter</kbd> прыжок · <kbd>[</kbd><kbd>]</kbd> камера';
    if (!this.ability) return k;
    return k + (i === 0 ? ' · <kbd>F</kbd> ' : ' · <kbd>/</kbd> ') + (this.ability === 'slap' ? 'шлепок' : this.ability === 'kick' ? 'удар' : 'толчок');
  }

  spawnPlayers() {
    Game.players.forEach((p, i) => {
      const s = this.spawns[i];
      p.spawn(s.pos, s.heading);
      p.setCheckpoint(s.pos, s.heading, 0);
    });
  }

  respawn(p) {
    p.spawn(p.checkpoint.pos, p.checkpoint.heading);
    p.frozen = this.phase !== 'play';
    FX.ring(V3(p.pos.x, p.pos.y + 0.3, p.pos.z), '#ffffff', { size: 4, life: 0.4 });
  }

  update(dt) {
    this.t += dt;
    if (this.phase === 'intro' && this.t >= this.introTime) {
      this.phase = 'count';
      this.countT = 3;
      this.lastCount = 4;
      if (this.onCountdown) this.onCountdown();
    }
    if (this.phase === 'count') {
      this.countT -= dt;
      const n = Math.ceil(this.countT);
      if (n !== this.lastCount && n > 0) {
        this.lastCount = n;
        UI.banner(-1, String(n), { dur: 0.8 });
        Sound.play('beep');
      }
      if (this.countT <= 0) {
        this.phase = 'play';
        UI.banner(-1, 'ВПЕРЁД!', { cls: 'green', dur: 0.9 });
        Sound.play('go');
        for (const p of Game.players) p.frozen = false;
        if (this.onStart) this.onStart();
      }
    }
    if (this.phase === 'play') {
      this.playT += dt;
      this.tick(dt);
    }
    if (this.phase === 'end') this.endT += dt;
    if (this.autoRespawn && this.phase !== 'end') {
      for (const p of Game.players) if (p.dead && p.deadT > this.respawnDelay) this.respawn(p);
    }
    if (this.frame) this.frame(dt);
    for (let i = 0; i < 2; i++) this.drawHud(i);
  }

  tick() {}
  drawHud() {}

  finish(res) {
    if (this.phase === 'end') return;
    this.phase = 'end';
    this.endT = 0;
    this.result = res;
    for (const p of Game.players) p.frozen = true;
    const w = res.winner;
    const names = Game.players.map((p) => p.name);
    if (w === 0 || w === 1) {
      Store.data.wins[w]++;
      const g = (Store.data.games[this.id] = Store.data.games[this.id] || [0, 0]);
      g[w]++;
      Store.save();
      UI.updateScore();
      UI.banner(w, 'ПОБЕДА!', { cls: 'gold', dur: 0, sub: res.sub ? res.sub[0] : '' });
      UI.banner(1 - w, 'Поражение', { cls: 'red', dur: 0, sub: res.sub ? res.sub[1] : '' });
      const wp = Game.players[w];
      if (!wp.dead) { wp.avatar.cheer = true; FX.confetti(V3(wp.pos.x, wp.pos.y + 5, wp.pos.z)); }
      Sound.play('win');
    } else if (w === 'coop') {
      UI.banner(-1, res.title || 'ВЫ СПРАВИЛИСЬ!', { cls: 'green', dur: 0, sub: res.subAll || '' });
      for (const p of Game.players) { if (!p.dead) { p.avatar.cheer = true; FX.confetti(V3(p.pos.x, p.pos.y + 5, p.pos.z)); } }
      Sound.play('win');
    } else {
      UI.banner(-1, res.title || 'НИЧЬЯ', { cls: res.cls || '', dur: 0, sub: res.subAll || '' });
      Sound.play(res.sad ? 'lose' : 'checkpoint');
    }
    const head = w === 0 || w === 1 ? `🏆 Победа: <span style="color:${Game.players[w].color}">${esc(names[w])}</span>` : esc(res.title || 'Ничья');
    setTimeout(() => {
      if (Game.mode === this && this.phase === 'end') UI.showResults(head, res.lines || '');
    }, 2300);
  }

  dispose() {
    for (const p of Game.players) {
      p.avatar.cheer = false;
      p.avatar.setGlove(null);
      p.speedMul = 1;
      p.jumpMul = 1;
      p.gravMul = 1;
    }
    if (this.cleanup) this.cleanup();
    R.scene.remove(this.root);
    disposeTree(this.root);
    this.root = null;
    World.clear();
    FX.clearAll();
  }
}

// Сколько игр выиграл каждый в этой мини-игре.
function gameRecordLine(id) {
  const g = Store.data.games[id] || [0, 0];
  const [a, b] = Game.players.map((p) => esc(p.name));
  return `В этой игре: ${a} ${g[0]} : ${g[1]} ${b}`;
}
