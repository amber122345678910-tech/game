'use strict';
// Связаны вместе (как Chained Together): двоих сковывает цепь, вместе лезете к небесам. Кооператив.

new MiniGame({
  id: 'chained',
  title: 'Связаны вместе',
  icon: '⛓',
  color: '#7ed957',
  coop: true,
  short: 'Лезьте к небу вдвоём!',
  desc: 'Вас сковали цепью! Держите друг друга, вытягивайте напарника и забирайтесь к небесам.',
  rules: 'Вы скованы цепью! Если друг сорвался — оттащи его назад. Костры — общие чекпоинты.',
  music: 'chained',
  theme: 'day',
  autoRespawn: false,
  killY: -400,
  camDist: 18,
  camPitch: 0.42,
  L: 12,
  COUNT: 12,

  recordText(rec) {
    return rec.time ? `пройдено за ${fmtTime(rec.time)}` : `рекорд ${Math.round(rec.height || 0)} м`;
  },

  build() {
    const root = this.root;
    part(root, 0, -1.5, 0, 60, 3, 60, { mat: 'grass', color: '#ffffff' });
    for (let i = 0; i < 12; i++) {
      const a = (i / 12) * TAU;
      Deco.tree(root, Math.cos(a) * 24, 0, 6 + Math.sin(a) * 20, rand(0.9, 1.3), { pine: chance(0.4) });
    }
    Deco.flowers(root, -8, 0, 12, 10, 4);
    Deco.flowers(root, 9, 0, 16, 8, 3);
    for (let i = 0; i < 10; i++) Deco.islet(root, rand(-200, 260), rand(-20, 140), rand(-260, 60), rand(6, 12));
    this.fires = [];
    this.addFire(V3(0, 0, 4));

    const c = new Course(root, { dir: 0, y: 0, z: -30, wide: 1.45, colorIdx: randi(0, 7) });
    this.course = c;
    const onCp = (p, index, spawn, heading) => this.reachFire(index, spawn, heading);
    const list = pickSections('chained', this.COUNT);
    list.forEach((k, i) => {
      c.nextColor();
      SECTIONS[k](c, Math.min(2, Math.floor(i / 4)));
      const rise = ['trampolines', 'truss', 'stairs'].includes(k) ? 0 : 3;
      for (let s = 0; s < rise; s++) {
        c.y += 2.3;
        c.plat(0, c.f + 2.6, c.y, 9 * c.wide, 3.2, { color: s % 2 ? c.color() : shade(c.color(), 0.25) });
        c.f += 4.2;
      }
      c.f += 2;
      const cp = c.checkpoint(onCp, false);
      const fireAt = c.world(c.wide * 12 / 2 - 2.5, cp.spawn.y, -0.5 + c.f - 4.5);
      this.addFire(fireAt);
      if (i < list.length - 1) {
        c.f -= 4.5;
        c.turn(i % 2 ? -1 : 1);
        c.f += 6 * c.wide;
      }
    });
    // Небеса
    const top = c.y;
    const ff = c.f + 12;
    c.plat(0, ff, top, 26, 22, { mat: 'smooth', color: '#fff7dc' });
    const gold = '#ffcc33';
    for (const s of [-1, 1]) c.box(s * 6, top + 7, ff - 8, 1.6, 14, 1.6, { mat: 'gold', color: gold });
    c.box(0, top + 14.5, ff - 8, 14, 1.4, 1.6, { mat: 'gold', color: gold, collide: false });
    const sign = signMesh(root, [{ text: '☁ НЕБЕСА ☁', size: 100, color: '#7a5a00' }], 0, 0, 0, 13, 3, { bg: '#fff3c4', border: gold });
    sign.position.copy(c.world(0, top + 17.5, ff - 8));
    sign.rotation.y = c.heading() + Math.PI;
    for (let i = 0; i < 12; i++) {
      const p = c.world(rand(-18, 18), top - rand(1, 4), ff + rand(-16, 16));
      const cl = new THREE.Mesh(new THREE.IcosahedronGeometry(rand(3, 6), 1), R.cloudMat);
      cl.position.copy(p);
      cl.scale.y = 0.6;
      root.add(cl);
    }
    const fp = c.world(0, top + 3, ff);
    const [fsx, fsz] = c.size(26, 22);
    World.addTrigger(fp.x, fp.y, fp.z, fsx, 6, fsz, () => { if (this.phase === 'play') this.win(); });
    this.topY = top;

    // Цепь
    this.links = [];
    const geo = new THREE.TorusGeometry(0.3, 0.085, 6, 12);
    const mat = new THREE.MeshStandardMaterial({ color: 0xb8bec8, metalness: 0.9, roughness: 0.3 });
    for (let i = 0; i < 18; i++) {
      const m = new THREE.Mesh(geo, mat);
      m.castShadow = true;
      root.add(m);
      this.links.push(m);
    }
    this.cuffs = Game.players.map(() => {
      const m = new THREE.Mesh(new THREE.TorusGeometry(0.62, 0.14, 8, 18), mat);
      m.rotation.x = Math.PI / 2;
      root.add(m);
      return m;
    });

    this.spawns = [{ pos: V3(-3, 0.1, -8), heading: Math.PI }, { pos: V3(3, 0.1, -8), heading: Math.PI }];
    this.team = { pos: V3(0, 0.1, -8), heading: Math.PI, index: 0 };
    this.respawnAt = null;
    this.maxH = 0;
    this.heaven = false;
    this.clinkT = 0;
  },

  addFire(pos) {
    const root = this.root;
    const logMat = Mat.get('wood', '#7a4a2a');
    for (const r of [0.5, -0.5]) {
      const log = new THREE.Mesh(new THREE.CylinderGeometry(0.25, 0.25, 2.2, 8), logMat);
      log.rotation.set(Math.PI / 2, r, 0);
      log.position.set(pos.x, pos.y + 0.3, pos.z);
      root.add(log);
    }
    const flame = new THREE.Mesh(new THREE.ConeGeometry(0.6, 1.6, 8), new THREE.MeshBasicMaterial({ color: 0xffa531, toneMapped: false }));
    flame.position.set(pos.x, pos.y + 1.2, pos.z);
    root.add(flame);
    this.fires.push({ pos: pos.clone(), flame });
  },

  reachFire(index, spawn, heading) {
    if (index <= this.team.index) return;
    this.team = { pos: spawn.clone(), heading, index };
    Sound.play('checkpoint');
    UI.toast(-1, `🔥 Костёр ${index}/${this.COUNT}!`, '#ffcf6b');
    FX.ring(V3(spawn.x, spawn.y + 0.4, spawn.z), '#ffb02e', { size: 8, life: 0.6 });
    if (!this.heaven && index >= this.COUNT - 3) {
      this.heaven = true;
      setTheme('heaven');
    }
  },

  spawnTeam() {
    const t = this.team;
    const right = V3(-Math.cos(t.heading), 0, Math.sin(t.heading));
    Game.players.forEach((p, i) => {
      const pos = t.pos.clone().addScaledVector(right, i === 0 ? -2.5 : 2.5);
      p.spawn(pos, t.heading);
      p.frozen = this.phase !== 'play';
      FX.ring(V3(pos.x, pos.y + 0.3, pos.z), '#ffffff', { size: 4, life: 0.4 });
    });
  },

  spawnPlayers() {
    this.spawnTeam();
  },

  onDeath() {
    if (!this.respawnAt) this.respawnAt = this.playT + 1.7;
  },

  win() {
    const time = this.playT;
    const rec = (Store.data.records.chained = Store.data.records.chained || {});
    const best = !rec.time || time < rec.time;
    if (best) rec.time = time;
    rec.height = Math.max(rec.height || 0, this.topY);
    Store.save();
    this.finish({ winner: 'coop', title: 'ВЫ ДОБРАЛИСЬ ДО НЕБЕС!', subAll: 'Командная работа! 💚', lines: `Время: ${fmtTime(time)}${best ? ' — новый рекорд!' : ` (рекорд ${fmtTime(rec.time)})`}` });
  },

  // Цепь: если расстояние больше длины — тянем обоих; стоящий на земле «тяжелее».
  fixed() {
    const [a, b] = Game.players;
    if (a.dead || b.dead || this.phase === 'end') return;
    const dx = b.pos.x - a.pos.x;
    const dy = b.pos.y - a.pos.y;
    const dz = b.pos.z - a.pos.z;
    const dist = Math.hypot(dx, dy, dz);
    if (dist <= this.L) return;
    const nx = dx / dist;
    const ny = dy / dist;
    const nz = dz / dist;
    const ex = dist - this.L;
    let wa = 0.5;
    if (a.grounded && !b.grounded) wa = 0.22;
    else if (b.grounded && !a.grounded) wa = 0.78;
    const wb = 1 - wa;
    a.pos.x += nx * ex * wa; a.pos.y += ny * ex * wa; a.pos.z += nz * ex * wa;
    b.pos.x -= nx * ex * wb; b.pos.y -= ny * ex * wb; b.pos.z -= nz * ex * wb;
    const rv = (b.vel.x - a.vel.x) * nx + (b.vel.y - a.vel.y) * ny + (b.vel.z - a.vel.z) * nz;
    if (rv > 0) {
      a.vel.x += nx * rv * wa; a.vel.y += ny * rv * wa; a.vel.z += nz * rv * wa;
      b.vel.x -= nx * rv * wb; b.vel.y -= ny * rv * wb; b.vel.z -= nz * rv * wb;
    }
    a.pushOut();
    b.pushOut();
    if (ex > 0.5 && this.clinkT <= 0) { Sound.play('chain', { pitch: rand(0.9, 1.1) }); this.clinkT = 0.35; }
  },

  tick(dt) {
    this.clinkT -= dt;
    const [a, b] = Game.players;
    for (const p of Game.players) {
      if (!p.dead && p.pos.y < this.team.pos.y - 34) p.die('fall');
    }
    if (this.respawnAt && this.playT >= this.respawnAt) {
      this.respawnAt = null;
      for (const p of Game.players) if (!p.dead) FX.burst(V3(p.pos.x, p.pos.y + 2.5, p.pos.z), 16, { color: '#ffffff', speed: 8, glow: true, grav: 0, life: 0.5, size: 0.3 });
      this.spawnTeam();
    }
    if (!a.dead && !b.dead) {
      const h = Math.min(a.pos.y, b.pos.y);
      if (h > this.maxH) this.maxH = h;
    }
  },

  frame(dt) {
    const [a, b] = Game.players;
    const show = !a.dead && !b.dead;
    const A = V3(a.pos.x, a.pos.y + 2.4, a.pos.z);
    const B = V3(b.pos.x, b.pos.y + 2.4, b.pos.z);
    const dist = A.distanceTo(B);
    const sag = Math.min(2.2, Math.max(0, this.L - dist) * 0.4);
    const mid = A.clone().add(B).multiplyScalar(0.5);
    mid.y -= sag * 2;
    const n = this.links.length;
    const q = new THREE.Quaternion();
    const x = V3(1, 0, 0);
    for (let i = 0; i < n; i++) {
      const t = (i + 0.5) / n;
      const u = 1 - t;
      const p = V3(u * u * A.x + 2 * u * t * mid.x + t * t * B.x, u * u * A.y + 2 * u * t * mid.y + t * t * B.y, u * u * A.z + 2 * u * t * mid.z + t * t * B.z);
      const tan = V3(2 * u * (mid.x - A.x) + 2 * t * (B.x - mid.x), 2 * u * (mid.y - A.y) + 2 * t * (B.y - mid.y), 2 * u * (mid.z - A.z) + 2 * t * (B.z - mid.z)).normalize();
      const m = this.links[i];
      m.visible = show;
      m.position.copy(p);
      q.setFromUnitVectors(x, tan);
      m.quaternion.copy(q);
      if (i % 2) m.rotateX(Math.PI / 2);
      m.scale.set(Math.max(0.6, Math.min(1.6, dist / n / 0.42)), 1, 1);
    }
    Game.players.forEach((p, i) => {
      const cf = this.cuffs[i];
      cf.visible = !p.dead;
      cf.position.set(p.pos.x, p.pos.y + 2.4, p.pos.z);
      cf.scale.set(1.75, 1, 1.25);
      cf.rotation.z = 0;
      cf.rotation.y = p.heading;
    });
    for (const f of this.fires) {
      f.flame.scale.set(1 + Math.sin(this.t * 13 + f.pos.x) * 0.12, 1 + Math.sin(this.t * 9 + f.pos.z) * 0.18, 1);
      if (Math.random() < dt * 6) FX.emit({ x: f.pos.x + rand(-0.4, 0.4), y: f.pos.y + 1.2, z: f.pos.z + rand(-0.4, 0.4), vy: rand(2, 4), life: 0.8, size: rand(0.15, 0.3), color: pick(['#ffb02e', '#ff6a1a', '#ffe14a']), glow: true, grav: -2 });
    }
    if (this.course) this.course.animate(dt);
  },

  cleanup() {
    const rec = (Store.data.records.chained = Store.data.records.chained || {});
    if (this.maxH > (rec.height || 0)) { rec.height = this.maxH; Store.save(); }
  },

  drawHud(i) {
    const rec = Store.data.records.chained || {};
    const h = Math.max(0, Math.round(Math.min(Game.players[0].pos.y, Game.players[1].pos.y)));
    UI.hud(i, `<div class="chip big">⛰ ${h} м</div><div class="chip">🔥 Костёр ${this.team.index}/${this.COUNT}<small>рекорд высоты: ${Math.round(Math.max(rec.height || 0, this.maxH))} м</small></div><div class="chip">⏱ ${fmtTime(this.playT)}</div>`);
    const pct = clamp(Math.min(Game.players[0].pos.y, Game.players[1].pos.y) / Math.max(1, this.topY), 0, 1) * 100;
    UI.progress(i, `<div class="bar"><div class="fill" style="width:${pct.toFixed(1)}%;background:linear-gradient(90deg,#7ed957,#ffe08a)"></div></div>`);
  },
});
