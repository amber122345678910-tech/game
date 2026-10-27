'use strict';
// Пол — это лава: волны лавы поднимаются всё выше. Собирай монеты, залезай повыше, толкай друга вниз.

new MiniGame({
  id: 'lava',
  title: 'Пол — это лава!',
  icon: '🌋',
  color: '#ff5a1f',
  short: 'Залезь повыше!',
  desc: 'Лава поднимается волнами, каждая выше прошлой. Собирай монеты и прячься наверху. 5 волн — у кого больше очков, тот победил.',
  rules: 'Лава идёт волнами! Монетка +1, пережил волну +5. Толкаться можно: F / ⁄',
  ability: 'push',
  theme: 'sunset',
  music: 'lava',
  autoRespawn: false,
  killY: -30,
  spectate: true,
  camDist: 17,
  camPitch: 0.4,
  WAVES: 5,
  LEVELS: [3.6, 7.6, 11.4, 15.6, 20.2],

  build() {
    const root = this.root;
    const S = 92;
    part(root, 0, -1.5, 0, S, 3, S, { mat: 'grass', color: '#ffffff' });
    // Дорожки
    part(root, 0, 0.03, 0, 6, 0.06, S - 4, { mat: 'stone', color: '#c9c3b5', collide: false });
    part(root, 0, 0.04, 6, S - 4, 0.06, 6, { mat: 'stone', color: '#c9c3b5', collide: false });
    // Ограда (невидимые стены повыше)
    const half = S / 2;
    for (const [x, z, sx, sz] of [[0, -half, S, 1], [0, half, S, 1], [-half, 0, 1, S], [half, 0, 1, S]]) {
      part(root, x, 0.9, z, sx, 1.8, sz, { mat: 'wood', color: '#f2e6d0' });
      World.addBox(x, 20, z, sx, 40, sz, { noCam: true });
    }

    // Дом с лестницей
    part(root, -24, 4.5, -22, 16, 9, 14, { mat: 'brick', color: '#e7b9a0' });
    part(root, -24, 9.4, -22, 16.6, 0.8, 14.6, { mat: 'smooth', color: '#8a3b2e' });
    for (let k = 0; k < 4; k++) {
      const h = 2.4 * (k + 1);
      part(root, -14, h / 2, -16.5 - k * 3, 4, h, 3, { mat: 'wood', color: k % 2 ? '#b07a4a' : '#c98e58' });
    }
    // Высокий дом с фермой
    part(root, 22, 7, -22, 12, 14, 12, { mat: 'wood', color: '#d9a36a' });
    part(root, 22, 14.4, -22, 12.6, 0.8, 12.6, { mat: 'smooth', color: '#3a5b8a' });
    part(root, 22, 7, -15.5, 3, 14, 1, { mat: 'truss', color: '#c0c6d0', climb: true });
    // Башня со спиралью
    part(root, 0, 12, -20, 6, 24, 6, { mat: 'stone', color: '#d0cbc2' });
    part(root, 0, 24.4, -20, 7, 0.8, 7, { mat: 'smooth', color: '#ffcc33' });
    for (let k = 0; k < 7; k++) {
      const a = (k / 4) * TAU + Math.PI / 2;
      part(root, Math.cos(a) * 5.8, 3 + k * 3 - 0.5, -20 + Math.sin(a) * 5.8, 4.2, 1, 4.2, { color: RAINBOW[k % RAINBOW.length] });
    }
    part(root, 0, 28, -20, 0.3, 7, 0.3, { mat: 'metal', color: '#dddddd', collide: false });
    part(root, 1.4, 30.4, -20, 2.6, 1.6, 0.1, { mat: 'smooth', color: '#ff5a1f', collide: false });
    // Детская площадка
    part(root, -24, 6.4, 20, 10, 0.8, 10, { mat: 'wood', color: '#e0a060' });
    for (const [dx, dz] of [[-4.5, -4.5], [4.5, -4.5], [-4.5, 4.5], [4.5, 4.5]]) part(root, -24 + dx, 3, 20 + dz, 0.8, 6, 0.8, { mat: 'metal', color: '#ff6fb5' });
    part(root, -24, 3.3, 14.6, 3, 6.6, 1, { mat: 'truss', color: '#c0c6d0', climb: true });
    for (let k = 0; k < 4; k++) part(root, -17.5 + k * 2.6, 5.4 - k * 1.4, 20, 2.6, 0.6, 4, { color: '#ffd23f' });
    // Деревья с кроной, на которую можно залезть
    for (const [x, z] of [[24, 16], [10, 30], [-6, 32], [34, 2]]) {
      part(root, x, 5, z, 2, 10, 2, { mat: 'wood', color: '#8a5a35' });
      part(root, x, 11.5, z, 9, 3, 9, { mat: 'smooth', color: pick(['#4caf50', '#5cbf4a', '#3e9d42']) });
      part(root, x + 5.1, 6.5, z, 1, 13, 2.2, { mat: 'truss', color: '#a0a6b0', climb: true });
    }
    // Машинки
    for (const [x, z, col] of [[12, 12, '#e63e3e'], [-8, 18, '#2463eb'], [30, -6, '#ffd23f']]) {
      part(root, x, 1.4, z, 8, 2.4, 4, { color: col, mat: 'smooth' });
      part(root, x - 0.5, 3.6, z, 4.5, 2, 3.6, { color: shade(col, 0.4), mat: 'smooth' });
      for (const [wx, wz] of [[-2.6, -2.1], [2.6, -2.1], [-2.6, 2.1], [2.6, 2.1]]) {
        const w = new THREE.Mesh(new THREE.CylinderGeometry(0.8, 0.8, 0.6, 14), Mat.get('smooth', '#222228'));
        w.rotation.x = Math.PI / 2;
        w.position.set(x + wx, 0.8, z + wz);
        root.add(w);
      }
    }
    // Ящики
    for (const [x, z, n] of [[12, -4, 3], [15, -4, 2], [12, -7, 1], [-10, -2, 2], [-33, 4, 3], [-33, 7, 1]]) {
      for (let k = 0; k < n; k++) part(root, x, 1.5 + k * 3, z, 3, 3, 3, { mat: 'wood', color: '#c98e58' });
    }
    // Батуты
    for (const [x, z] of [[-6, -2], [8, 20], [-30, -6]]) {
      cylPart(root, x, 0, z, 2.6, 0.5, { mat: 'smooth', color: '#2b2f3a' });
      cylPart(root, x, 0.5, z, 2.2, 0.25, { mat: 'glow', color: '#7ed321', bounce: 82 });
    }
    // Парящие платформы
    part(root, -6, 19, 4, 5, 1, 5, { color: '#7b6cff' });
    part(root, -12, 22, 9, 4, 1, 4, { color: '#ff70c8' });
    const mv = part(root, 8, 17, -20, 5, 1, 5, { color: '#2ec4b6', props: { moving: true } });
    World.addMover((t) => mv.col.setPos(10 + Math.sin(t * 0.7) * 4, 17, -20));

    // Лава
    this.lavaY = -1.6;
    this.lava = part(root, 0, this.lavaY - 1, 0, 300, 2, 300, { mat: 'lava', kill: true, props: { moving: true }, cast: false });
    this.lava.mesh.receiveShadow = false;
    this.spawns = [{ pos: V3(-5, 0.1, 10), heading: Math.PI }, { pos: V3(5, 0.1, 10), heading: Math.PI }];
    this.wave = 0;
    this.st = 'wait';
    this.stT = 0;
    this.coins = [];
    this.survived = [0, 0];
    this.coinsGot = [0, 0];
    this.wasAlive = [true, true];
  },

  setLava(y) {
    this.lavaY = y;
    this.lava.col.setPos(0, y - 1, 0);
  },

  spawnCoins(n) {
    for (let k = 0; k < n; k++) {
      let x = 0;
      let z = 0;
      let y = -Infinity;
      for (let tries = 0; tries < 12 && y === -Infinity; tries++) {
        x = rand(-42, 42);
        z = rand(-42, 42);
        y = World.groundAt(x, z, 40);
        if (y < -0.5 || y > 30) y = -Infinity;
      }
      if (y === -Infinity) continue;
      const g = new THREE.Mesh(new THREE.CylinderGeometry(0.8, 0.8, 0.2, 20), Mat.get('gold', '#ffcc33'));
      g.rotation.x = Math.PI / 2;
      g.position.set(x, y + 1.6, z);
      g.castShadow = true;
      this.root.add(g);
      this.coins.push({ m: g, y: y + 1.6 });
    }
  },

  removeCoin(k) {
    const c = this.coins[k];
    this.root.remove(c.m);
    c.m.geometry.dispose();
    this.coins.splice(k, 1);
  },

  onStart() {
    this.nextWave();
  },

  nextWave() {
    this.wave++;
    this.st = 'calm';
    this.stT = this.wave === 1 ? 9 : 7;
    this.level = this.LEVELS[this.wave - 1] + rand(-0.4, 0.4);
    Game.players.forEach((p, i) => {
      if (p.dead) {
        p.spawn(this.spawns[i].pos, this.spawns[i].heading);
        p.frozen = false;
      }
    });
    this.wasAlive = [true, true];
    this.spawnCoins(10 + this.wave * 2);
    UI.banner(-1, `Волна ${this.wave}/${this.WAVES}`, { cls: 'small', dur: 1.6, sub: 'Собирай монеты и ищи, куда залезть!' });
    Music.duck(false);
  },

  onDeath(p) {
    this.wasAlive[p.idx] = false;
    UI.vignette(p.idx, false);
    Sound.play('sizzle');
    FX.burst(V3(p.deathPos.x, this.lavaY + 0.5, p.deathPos.z), 24, { colors: ['#ffb02e', '#ff6a1a', '#ffe14a'], speed: 10, glow: true, grav: 20, lift: 6, life: 0.8, size: 0.35 });
  },

  tick(dt) {
    this.stT -= dt;
    if (this.st === 'calm' && this.stT <= 0) {
      this.st = 'rise';
      this.stT = 7;
      this.from = this.lavaY;
      Sound.play('siren');
      UI.banner(-1, 'ЛАВА ИДЁТ!', { cls: 'red', dur: 1.5 });
      setTheme('lava');
    } else if (this.st === 'rise') {
      const k = 1 - clamp(this.stT / 7, 0, 1);
      this.setLava(lerp(this.from, this.level, smooth01(k)));
      if (this.stT <= 0) { this.st = 'hold'; this.stT = 5; }
    } else if (this.st === 'hold' && this.stT <= 0) {
      this.st = 'drain';
      this.stT = 3.5;
      this.from = this.lavaY;
    } else if (this.st === 'drain') {
      const k = 1 - clamp(this.stT / 3.5, 0, 1);
      this.setLava(lerp(this.from, -1.6, smooth01(k)));
      if (this.stT <= 0) {
        Game.players.forEach((p, i) => {
          if (!p.dead && this.wasAlive[i]) {
            this.survived[i]++;
            p.score += 5;
            UI.toast(i, '+5 — пережил волну!', '#7dffb0');
            FX.text(V3(p.pos.x, p.pos.y + 7, p.pos.z), '+5', { color: '#7dffb0' });
          }
        });
        Sound.play('checkpoint');
        setTheme('sunset');
        if (this.wave >= this.WAVES) this.end();
        else this.nextWave();
        return;
      }
    }
    // Монеты
    for (let k = this.coins.length - 1; k >= 0; k--) {
      const c = this.coins[k];
      c.m.rotation.z += dt * 3;
      c.m.position.y = c.y + Math.sin(this.t * 3 + k) * 0.25;
      if (this.lavaY > c.y - 1) { FX.burst(c.m.position, 6, { color: '#ffcc33', speed: 4, glow: true, grav: 0, life: 0.4, size: 0.2 }); this.removeCoin(k); continue; }
      for (const p of Game.players) {
        if (p.dead) continue;
        if (Math.hypot(p.pos.x - c.m.position.x, p.pos.z - c.m.position.z) < 2 && c.m.position.y > p.pos.y - 0.5 && c.m.position.y < p.pos.y + 5.5) {
          p.score += 1;
          this.coinsGot[p.idx]++;
          Sound.play('coin', { gap: 0.05 });
          FX.burst(c.m.position, 10, { color: '#ffd84d', speed: 6, glow: true, grav: 0, life: 0.5, size: 0.25 });
          this.removeCoin(k);
          break;
        }
      }
    }
    for (const p of Game.players) {
      UI.vignette(p.idx, !p.dead && (this.st === 'rise' || this.st === 'hold') && p.pos.y - this.lavaY < 3);
      if (!p.dead && (this.st === 'rise' || this.st === 'hold') && Math.random() < dt * 10) {
        FX.emit({ x: p.pos.x + rand(-14, 14), y: this.lavaY + 0.2, z: p.pos.z + rand(-14, 14), vy: rand(3, 7), life: 1, size: rand(0.15, 0.3), color: pick(['#ffb02e', '#ff6a1a']), glow: true, grav: 4 });
      }
    }
  },

  end() {
    const [a, b] = Game.players.map((p) => p.score);
    const P = Game.players;
    const lines = `Очки: ${esc(P[0].name)} ${a} (монет ${this.coinsGot[0]}, волн ${this.survived[0]}) · ${esc(P[1].name)} ${b} (монет ${this.coinsGot[1]}, волн ${this.survived[1]})<br>${gameRecordLine(this.id)}`;
    if (a === b) this.finish({ winner: -1, title: 'Ничья по очкам!', lines });
    else this.finish({ winner: a > b ? 0 : 1, lines, sub: ['Король лавы! 🔥', 'Горячо было...'] });
  },

  cleanup() {
    for (let i = 0; i < 2; i++) UI.vignette(i, false);
    Music.duck(false);
  },

  drawHud(i) {
    const p = Game.players[i];
    const o = Game.other(p);
    const phase = this.st === 'calm' ? `Лава через ${Math.ceil(Math.max(0, this.stT))} с — собирай монеты!`
      : this.st === 'rise' ? '🔥 ЛАВА ПОДНИМАЕТСЯ!' : this.st === 'hold' ? `Держись! ${Math.ceil(Math.max(0, this.stT))} с` : this.st === 'drain' ? 'Лава уходит…' : '';
    let html = `<div class="chip big">🪙 ${p.score}</div><div class="chip">Волна ${Math.max(1, this.wave)}/${this.WAVES} · ${esc(o.name)}: ${o.score}</div>`;
    if (phase) html += `<div class="chip" style="${this.st === 'rise' || this.st === 'hold' ? 'color:#ffb02e' : ''}">${phase}</div>`;
    if (p.dead && this.phase === 'play') html += '<div class="chip" style="color:#ff6a6a">Сгорел! Вернёшься в следующей волне</div>';
    UI.hud(i, html);
  },
});
