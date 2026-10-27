'use strict';
// Шлёп-битва (как Slap Battles): летающий остров, перчатки, урон в процентах — чем больше, тем дальше летишь.

const POWERUPS = [
  { id: 'speed', icon: '⚡', color: '#ffd23f', name: 'Скорость!' },
  { id: 'mega', icon: '💪', color: '#ff9f1c', name: 'Мега-шлепок!' },
  { id: 'jump', icon: '🦘', color: '#7ed321', name: 'Супер-прыжок!' },
  { id: 'shield', icon: '🛡', color: '#5ab8ff', name: 'Щит!' },
  { id: 'heal', icon: '❤', color: '#ff4d6d', name: 'Урон сброшен!' },
];

new MiniGame({
  id: 'slap',
  title: 'Шлёп-битва',
  icon: '👋',
  color: '#e8458f',
  short: 'Сшиби друга с острова!',
  desc: 'Бей перчаткой и сталкивай с острова. Чем больше урон, тем дальше летит. Раунды до 3 побед.',
  rules: 'Шлёпай соперника и сбрось его с острова! Чем больше % урона — тем дальше полетит. До 3 побед.',
  ability: 'slap',
  music: 'slap',
  autoRespawn: false,
  killY: -16,
  spectate: true,
  camDist: 17,
  camPitch: 0.36,
  R0: 24,

  build() {
    this.theme = pick(['sunset', 'day']);
    setTheme(this.theme);
    const root = this.root;
    const top = cylPart(root, 0, -3, 0, this.R0, 3, { mat: 'grass', color: '#ffffff', seg: 64 });
    this.island = top;
    const cone = new THREE.Mesh(new THREE.ConeGeometry(this.R0, 22, 48), Mat.get('dirt', '#ffffff'));
    cone.rotation.x = Math.PI;
    cone.position.y = -14;
    cone.receiveShadow = true;
    root.add(cone);
    this.cone = cone;
    const edge = new THREE.Mesh(new THREE.TorusGeometry(this.R0, 0.25, 6, 64), new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false, transparent: true, opacity: 0.55 }));
    edge.rotation.x = Math.PI / 2;
    edge.position.y = 0.05;
    root.add(edge);
    this.edge = edge;
    Deco.tree(root, -9, 0, -10, 1.1);
    Deco.tree(root, 10, 0, 9, 0.95);
    Deco.rock(root, 7, 0, -9, 1.3);
    Deco.rock(root, -8, 0, 9, 1.1);
    Deco.flowers(root, 0, 0, -14, 8, 3);
    Deco.flowers(root, -14, 0, 3, 6, 2);
    // Центральный пьедестал
    cylPart(root, 0, 0, 0, 3.2, 0.8, { mat: 'stone', color: '#d9d4c8', seg: 24 });
    for (let i = 0; i < 9; i++) {
      const a = (i / 9) * TAU;
      Deco.islet(root, Math.cos(a) * rand(70, 130), rand(-40, 10), Math.sin(a) * rand(70, 130), rand(5, 11));
    }
    this.spawns = [{ pos: V3(-12, 0.1, 0), heading: Math.PI / 2 }, { pos: V3(12, 0.1, 0), heading: -Math.PI / 2 }];
    this.points = [0, 0];
    this.round = 1;
    this.pups = [];
    this.pupT = 5;
    this.shields = [null, null];
    this.roundOver = false;
    this.roundT = 0;
    this.radius = this.R0;
  },

  onCountdown() {
    Game.players.forEach((p, i) => {
      p.avatar.setGlove(i === 0 ? 'blue' : 'red');
      p.camYaw = p.heading + Math.PI;
    });
  },

  onStart() {
    this.pendingRound = null;
    this.roundOver = false;
    this.roundT = 0;
    this.fallT = [null, null];
  },

  newRound() {
    this.round++;
    this.roundOver = false;
    this.setRadius(this.R0);
    for (const u of this.pups) this.removePup(u);
    this.pups = [];
    this.pupT = 5;
    Game.players.forEach((p, i) => {
      p.spawn(this.spawns[i].pos, this.spawns[i].heading);
      p.frozen = true;
      p.dmg = 0;
      p.power = {};
      p.speedMul = 1;
      p.jumpMul = 1;
      this.setShield(p, false);
      p.avatar.setGlove(i === 0 ? 'blue' : 'red');
    });
    UI.banner(-1, 'Раунд ' + this.round, { dur: 1.2 });
    this.phase = 'count';
    this.countT = 3.6;
    this.lastCount = 4;
  },

  setRadius(r) {
    this.radius = r;
    this.island.col.r = r;
    const s = r / this.R0;
    this.island.mesh.scale.set(s, 1, s);
    this.cone.scale.set(s, 1, s);
    this.edge.scale.set(s, s, 1);
  },

  onHit(a, t, dx, dz) {
    if (t.power.shield) {
      t.power.shield = false;
      this.setShield(t, false);
      t.knock(dx, dz, 12, 10, 0.2);
      Sound.play('shield');
      FX.ring(V3(t.pos.x, t.pos.y + 2.5, t.pos.z), '#5ab8ff', { size: 6, life: 0.4 });
      FX.text(V3(t.pos.x, t.pos.y + 7, t.pos.z), 'БЛОК!', { color: '#8fd3ff' });
      return;
    }
    let mult = 1;
    if (a.power.mega) {
      mult = 1.85;
      a.power.mega = false;
      a.avatar.setGlove(a.idx === 0 ? 'blue' : 'red');
    }
    t.dmg += (12 + rand(0, 4)) * mult;
    const kb = (14 + t.dmg * 0.38) * mult;
    t.knock(dx, dz, kb, 12 + kb * 0.15, 0.25 + kb * 0.005);
    t.camShake = 0.3;
    a.camShake = 0.12;
    Sound.play('slap');
    const hp = V3(t.pos.x, t.pos.y + 3, t.pos.z);
    FX.burst(hp, 16 + Math.floor(mult * 8), { colors: ['#ffffff', '#ffe14a', '#ffb02e'], speed: 14, glow: true, grav: 0, life: 0.45, size: 0.35 });
    FX.ring(hp, '#ffffff', { size: 4 + kb * 0.05, life: 0.3 });
    FX.text(V3(t.pos.x, t.pos.y + 7, t.pos.z), mult > 1 ? 'МЕГА-ШЛЁП!' : pick(['ШЛЁП!', 'БАЦ!', 'ХЛОП!', 'ПАФ!']), { color: mult > 1 ? '#ffcc33' : '#ffffff' });
    UI.flash(t.idx);
  },

  setShield(p, on) {
    const i = p.idx;
    if (on && !this.shields[i]) {
      const m = new THREE.Mesh(new THREE.SphereGeometry(3.3, 24, 16), new THREE.MeshStandardMaterial({ color: 0x6fc3ff, transparent: true, opacity: 0.28, emissive: 0x3a8fff, emissiveIntensity: 0.4, depthWrite: false }));
      this.root.add(m);
      this.shields[i] = m;
    } else if (!on && this.shields[i]) {
      this.root.remove(this.shields[i]);
      this.shields[i].geometry.dispose();
      this.shields[i].material.dispose();
      this.shields[i] = null;
    }
  },

  spawnPup() {
    const type = pick(POWERUPS);
    const a = rand(0, TAU);
    const d = rand(3, Math.max(4, this.radius - 4));
    const g = new THREE.Group();
    const box = new THREE.Mesh(roundedBox(1.8, 1.8, 1.8, 0.35, 2), new THREE.MeshStandardMaterial({ color: type.color, emissive: type.color, emissiveIntensity: 0.45, roughness: 0.3 }));
    box.castShadow = true;
    g.add(box);
    const icon = textSprite(type.icon, { size: 64, height: 1.6, stroke: 'rgba(0,0,0,0.4)' });
    icon.position.y = 2.1;
    g.add(icon);
    g.position.set(Math.cos(a) * d, 2, Math.sin(a) * d);
    this.root.add(g);
    this.pups.push({ g, box, type, t: 0 });
    FX.burst(g.position, 14, { color: type.color, speed: 8, glow: true, grav: 0, life: 0.6, size: 0.3 });
  },

  removePup(u) {
    this.root.remove(u.g);
    disposeTree(u.g);
  },

  applyPup(p, type) {
    Sound.play('powerup');
    UI.toast(p.idx, type.icon + ' ' + type.name, type.color);
    if (type.id === 'speed') { p.power.speed = 8; p.speedMul = 1.45; }
    if (type.id === 'jump') { p.power.jump = 8; p.jumpMul = 1.35; }
    if (type.id === 'mega') { p.power.mega = true; p.avatar.setGlove('mega'); }
    if (type.id === 'shield') { p.power.shield = true; this.setShield(p, true); }
    if (type.id === 'heal') p.dmg = 0;
  },

  onDeath(p) {
    if (this.phase !== 'play' || this.roundOver) return;
    this.fallT[p.idx] = this.playT;
    if (!this.pendingRound) this.pendingRound = this.playT + 0.7;
  },

  endRound() {
    this.pendingRound = null;
    this.roundOver = true;
    const [d0, d1] = Game.players.map((p) => p.dead);
    let w = -1;
    if (d0 && !d1) w = 1;
    else if (d1 && !d0) w = 0;
    this.fallT = [null, null];
    if (w >= 0) {
      this.points[w]++;
      const wp = Game.players[w];
      if (this.points[w] >= 3) {
        this.finish({ winner: w, lines: `Счёт раундов ${this.points[0]} : ${this.points[1]}<br>${gameRecordLine(this.id)}`, sub: ['Король шлепков! 👑', 'Тебя отшлёпали...'] });
        return;
      }
      UI.banner(-1, `Раунд за ${wp.name}!`, { cls: 'small', dur: 2, sub: `${this.points[0]} : ${this.points[1]}` });
      Sound.play('checkpoint');
      wp.avatar.cheer = true;
    } else {
      UI.banner(-1, 'Оба упали!', { cls: 'small', dur: 2, sub: 'Раунд переигрывается' });
      this.round--;
    }
    this.nextRoundAt = this.playT + 2.6;
  },

  tick(dt) {
    this.roundT += dt;
    if (!this.roundOver && !this.pendingRound && Game.players.some((p) => p.dead)) this.pendingRound = this.playT + 0.7;
    if (this.pendingRound && this.playT >= this.pendingRound) this.endRound();
    if (this.roundOver) {
      if (this.nextRoundAt && this.playT >= this.nextRoundAt) {
        this.nextRoundAt = null;
        for (const p of Game.players) p.avatar.cheer = false;
        this.newRound();
      }
      return;
    }
    // Остров сжимается в затянувшемся раунде
    if (this.roundT > 40) {
      const r = Math.max(10, this.R0 - (this.roundT - 40) * 0.45);
      if (r < this.radius - 0.01) {
        if (Math.floor(this.radius) !== Math.floor(r)) {
          Sound.play('crumble', { gap: 0.2 });
          const a = rand(0, TAU);
          FX.burst(V3(Math.cos(a) * r, -0.5, Math.sin(a) * r), 10, { colors: ['#8a5a35', '#62b33f'], speed: 6, grav: 40, size: 0.6, life: 1.4 });
        }
        this.setRadius(r);
      }
    }
    // Бонусы
    this.pupT -= dt;
    if (this.pupT <= 0 && this.pups.length < 2) { this.spawnPup(); this.pupT = rand(6, 9); }
    for (let k = this.pups.length - 1; k >= 0; k--) {
      const u = this.pups[k];
      u.t += dt;
      u.box.rotation.y += dt * 2;
      u.box.rotation.x = Math.sin(u.t * 2) * 0.3;
      u.g.position.y = 2 + Math.sin(u.t * 3) * 0.3;
      if (Math.hypot(u.g.position.x, u.g.position.z) > this.radius - 1) { this.removePup(u); this.pups.splice(k, 1); continue; }
      for (const p of Game.players) {
        if (p.dead) continue;
        if (Math.hypot(p.pos.x - u.g.position.x, p.pos.z - u.g.position.z) < 2.4 && Math.abs(p.pos.y + 2 - u.g.position.y) < 3.5) {
          this.applyPup(p, u.type);
          this.removePup(u);
          this.pups.splice(k, 1);
          break;
        }
      }
    }
    for (const p of Game.players) {
      if (p.power.speed > 0) { p.power.speed -= dt; if (p.power.speed <= 0) p.speedMul = 1; else if (Math.random() < dt * 20) FX.emit({ x: p.pos.x, y: p.pos.y + 0.5, z: p.pos.z, vy: 1, life: 0.4, size: 0.25, color: '#ffd23f', glow: true, grav: 0 }); }
      if (p.power.jump > 0) { p.power.jump -= dt; if (p.power.jump <= 0) p.jumpMul = 1; }
    }
  },

  frame() {
    Game.players.forEach((p, i) => {
      const s = this.shields[i];
      if (s) { s.position.set(p.pos.x, p.pos.y + 2.6, p.pos.z); s.visible = !p.dead; }
    });
  },

  cleanup() {
    for (const p of Game.players) this.setShield(p, false);
  },

  drawHud(i) {
    const p = Game.players[i];
    const d = Math.round(p.dmg);
    const col = d < 40 ? '#ffffff' : d < 80 ? '#ffd23f' : d < 120 ? '#ff9f1c' : '#ff4d4d';
    const dots = (k) => '●'.repeat(this.points[k]) + '○'.repeat(Math.max(0, 3 - this.points[k]));
    const pw = [];
    if (p.power.speed > 0) pw.push('⚡');
    if (p.power.jump > 0) pw.push('🦘');
    if (p.power.mega) pw.push('💪');
    if (p.power.shield) pw.push('🛡');
    let html = `<div class="chip big" style="color:${col}">Урон ${d}%</div><div class="chip">Раунд ${this.round} · <span style="color:var(--p1)">${dots(0)}</span> <span style="color:var(--p2)">${dots(1)}</span></div>`;
    if (pw.length) html += `<div class="chip big">${pw.join(' ')}</div>`;
    if (this.roundT > 36 && this.phase === 'play' && !this.roundOver) html += `<div class="chip" style="color:#ffb02e">⚠ Остров уменьшается!</div>`;
    UI.hud(i, html);
  },
});
