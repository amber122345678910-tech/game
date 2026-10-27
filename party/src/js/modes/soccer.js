'use strict';
// Футбол огромным мячом (как Super League Soccer / Kick Off): кто первым забьёт 5 голов.

new MiniGame({
  id: 'soccer',
  title: 'Футбол',
  icon: '⚽',
  color: '#20b866',
  short: 'Забей гол другу!',
  desc: 'Огромный мяч и двое ворот. Толкай мяч, пинай и забивай! До 5 голов или 3 минут.',
  rules: 'Подбеги к мячу и пни: F / ⁄. Можно вести мяч и бить головой в прыжке. До 5 голов!',
  ability: 'kick',
  theme: 'day',
  music: 'soccer',
  autoRespawn: true,
  respawnDelay: 1.2,
  killY: -30,
  camDist: 18,
  camPitch: 0.42,
  FX: 36,
  FZ: 23,
  GW: 7.5,
  GH: 8,
  BR: 2.3,
  TIME: 180,
  GOALS: 5,

  build() {
    const root = this.root;
    const FX2 = this.FX;
    const FZ2 = this.FZ;
    // Поле в полоску
    for (let i = 0; i < 12; i++) {
      const w = (FX2 * 2) / 12;
      part(root, -FX2 + w / 2 + i * w, -0.5, 0, w, 1, FZ2 * 2, { mat: 'grass', color: i % 2 ? '#ffffff' : '#d8f0c8', collide: false });
    }
    World.addBox(0, -0.5, 0, FX2 * 2 + 30, 1, FZ2 * 2 + 30, {});
    part(root, 0, -0.6, 0, FX2 * 2 + 30, 1, FZ2 * 2 + 30, { mat: 'grass', color: '#9fd68a', collide: false });
    const line = (x, z, sx, sz) => part(root, x, 0.03, z, sx, 0.06, sz, { mat: 'smooth', color: '#ffffff', collide: false, cast: false });
    line(0, 0, 0.4, FZ2 * 2);
    line(0, -FZ2, FX2 * 2, 0.4);
    line(0, FZ2, FX2 * 2, 0.4);
    for (const s of [-1, 1]) {
      line(s * FX2, 0, 0.4, FZ2 * 2);
      line(s * (FX2 - 8), 0, 0.4, 24);
      line(s * (FX2 - 4), -12, 8, 0.4);
      line(s * (FX2 - 4), 12, 8, 0.4);
    }
    const ring = new THREE.Mesh(new THREE.RingGeometry(7.6, 8, 48), new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.6 }));
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.05;
    root.add(ring);
    // Борта: прозрачные стенки и невидимые стены повыше
    const glass = Mat.get('glass', '#d8f0ff');
    const wall = (x, z, sx, sz) => {
      const m = new THREE.Mesh(boxGeo(sx, 3, sz), glass);
      m.position.set(x, 1.5, z);
      root.add(m);
      World.addBox(x, 10, z, sx, 20, sz, { noCam: true, ballWall: true });
      part(root, x, 0.3, z, sx, 0.6, sz, { mat: 'smooth', color: '#2b2f3a', collide: false });
    };
    wall(0, -FZ2 - 0.5, FX2 * 2 + 2, 1);
    wall(0, FZ2 + 0.5, FX2 * 2 + 2, 1);
    const side = (FZ2 - this.GW) / 2;
    for (const s of [-1, 1]) {
      wall(s * (FX2 + 0.5), -(this.GW + side), 1, side * 2);
      wall(s * (FX2 + 0.5), this.GW + side, 1, side * 2);
      this.buildGoal(s);
    }
    // Трибуны со зрителями
    for (const s of [-1, 1]) {
      for (let r = 0; r < 4; r++) {
        const top = 1.6 * (r + 1);
        part(root, 0, top / 2, s * (FZ2 + 4 + r * 2.4), FX2 * 2 + 10, top, 2.4, { mat: 'smooth', color: r % 2 ? '#3a4060' : '#454c70', collide: false });
      }
    }
    this.crowd = [];
    const crowdCols = ['#ff5964', '#3ea6ff', '#ffd23f', '#7ed957', '#ff70c8', '#ffffff', '#ff9f1c'];
    const cg = new THREE.BoxGeometry(1.1, 1.6, 1.1);
    for (const s of [-1, 1]) {
      for (let r = 0; r < 4; r++) {
        for (let i = 0; i < 26; i++) {
          if (Math.random() < 0.25) continue;
          const m = new THREE.Mesh(cg, Mat.get('smooth', pick(crowdCols)));
          m.position.set(-FX2 - 2 + i * 3 + rand(-0.4, 0.4), 1.6 * (r + 1) + 0.8, s * (FZ2 + 4 + r * 2.4));
          root.add(m);
          this.crowd.push({ m, base: m.position.y, ph: rand(0, TAU) });
        }
      }
    }
    for (const [x, z] of [[-FX2 - 6, -FZ2 - 6], [FX2 + 6, -FZ2 - 6], [-FX2 - 6, FZ2 + 6], [FX2 + 6, FZ2 + 6]]) {
      part(root, x, 14, z, 1.2, 28, 1.2, { mat: 'metal', color: '#3a3f55', collide: false });
      part(root, x, 28.5, z, 5, 2.5, 2, { mat: 'neon', color: '#fff6d8', collide: false });
    }
    for (let i = 0; i < 6; i++) Deco.tree(root, rand(-80, 80), 0, pick([-1, 1]) * rand(48, 70), rand(1, 1.6), { collide: false, pine: chance(0.5) });
    // Табло
    this.board = new THREE.Mesh(new THREE.PlaneGeometry(16, 6), new THREE.MeshBasicMaterial({ toneMapped: false }));
    this.board.position.set(0, 16, -FZ2 - 14);
    root.add(this.board);
    const back = new THREE.Mesh(boxGeo(17, 7, 0.8), Mat.get('smooth', '#1b2033'));
    back.position.set(0, 16, -FZ2 - 14.5);
    root.add(back);
    // Мяч
    const tex = canvasTex(256, 128, (g, w, h) => {
      g.fillStyle = '#ffffff';
      g.fillRect(0, 0, w, h);
      g.fillStyle = '#1d1d24';
      for (let k = 0; k < 14; k++) {
        const x = (k % 7) * (w / 7) + (Math.floor(k / 7) % 2 ? w / 14 : 0);
        const y = Math.floor(k / 7) * (h / 2) + h / 4;
        g.beginPath();
        for (let q = 0; q < 5; q++) { const a = (q / 5) * TAU - Math.PI / 2; g.lineTo(x + Math.cos(a) * 13, y + Math.sin(a) * 13); }
        g.fill();
      }
    }, { repeat: false });
    this.ball = new THREE.Mesh(new THREE.SphereGeometry(this.BR, 32, 20), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.4 }));
    this.ball.castShadow = true;
    root.add(this.ball);
    this.bp = V3(0, this.BR, 0);
    this.bv = V3();
    this.score = [0, 0];
    this.endAt = null;
    this.lastSec = -1;
    this.lastTouch = -1;
    this.freezeT = 0;
    this.spawns = [{ pos: V3(-12, 0.1, 0), heading: Math.PI / 2 }, { pos: V3(12, 0.1, 0), heading: -Math.PI / 2 }];
    this.refreshBoard();
  },

  buildGoal(s) {
    const root = this.root;
    const x0 = s * this.FX;
    const depth = 6;
    const post = Mat.get('smooth', '#ffffff');
    const tc = s < 0 ? '#3ea6ff' : '#ff5fa8';
    for (const z of [-this.GW, this.GW]) {
      const m = new THREE.Mesh(new THREE.CylinderGeometry(0.4, 0.4, this.GH, 12), post);
      m.position.set(x0, this.GH / 2, z);
      m.castShadow = true;
      root.add(m);
      World.addCyl(x0, z, 0.45, 0, this.GH, {});
    }
    const bar = new THREE.Mesh(new THREE.CylinderGeometry(0.4, 0.4, this.GW * 2, 12), post);
    bar.rotation.x = Math.PI / 2;
    bar.position.set(x0, this.GH, 0);
    root.add(bar);
    const net = new THREE.MeshStandardMaterial({ color: tc, transparent: true, opacity: 0.35, side: THREE.DoubleSide, roughness: 0.8 });
    const back = new THREE.Mesh(new THREE.PlaneGeometry(this.GW * 2, this.GH), net);
    back.position.set(x0 + s * depth, this.GH / 2, 0);
    back.rotation.y = Math.PI / 2;
    root.add(back);
    for (const z of [-this.GW, this.GW]) {
      const sd = new THREE.Mesh(new THREE.PlaneGeometry(depth, this.GH), net);
      sd.position.set(x0 + (s * depth) / 2, this.GH / 2, z);
      root.add(sd);
    }
    const top = new THREE.Mesh(new THREE.PlaneGeometry(depth, this.GW * 2), net);
    top.rotation.x = Math.PI / 2;
    top.position.set(x0 + (s * depth) / 2, this.GH, 0);
    root.add(top);
    // Стенки ворот для игроков
    World.addBox(x0 + s * (depth + 0.5), this.GH / 2, 0, 1, this.GH, this.GW * 2 + 1, { noCam: true });
    World.addBox(x0 + (s * depth) / 2, this.GH / 2, -this.GW - 0.5, depth, this.GH, 1, { noCam: true });
    World.addBox(x0 + (s * depth) / 2, this.GH / 2, this.GW + 0.5, depth, this.GH, 1, { noCam: true });
    World.addBox(x0 + (s * depth) / 2, this.GH + 0.5, 0, depth, 1, this.GW * 2, { noCam: true });
    part(root, x0 + (s * depth) / 2, 0.04, 0, depth, 0.08, this.GW * 2, { mat: 'neon', color: tc, collide: false, cast: false });
  },

  refreshBoard() {
    const P = Game.players;
    const old = this.board.material.map;
    this.board.material.map = signTexture([
      { text: `${P[0].name}  ${this.score[0]} : ${this.score[1]}  ${P[1].name}`, size: 92 },
      { text: `⏱ ${fmtTime(Math.max(0, this.TIME - (this.playT || 0)))}`, size: 64, color: '#ffd23f' },
    ], { w: 1024, h: 384, bg: '#1b2033', border: '#20b866' });
    this.board.material.needsUpdate = true;
    if (old) old.dispose();
  },

  resetKickoff() {
    this.bp.set(0, this.BR + 3, 0);
    this.bv.set(0, 0, 0);
    Game.players.forEach((p, i) => {
      p.spawn(this.spawns[i].pos, this.spawns[i].heading);
      p.setCheckpoint(this.spawns[i].pos, this.spawns[i].heading);
    });
  },

  onCountdown() {
    for (const p of Game.players) p.camYaw = p.heading + Math.PI;
  },

  // Удар по мячу.
  onAction(p) {
    const dx = this.bp.x - p.pos.x;
    const dz = this.bp.z - p.pos.z;
    const dy = this.bp.y - (p.pos.y + 2.5);
    const dist = Math.hypot(dx, dz);
    if (dist > 6.2 || Math.abs(dy) > 5) return;
    const fx = Math.sin(p.heading);
    const fz = Math.cos(p.heading);
    if ((dx * fx + dz * fz) / (dist || 1) < 0.1 && dist > 3) return;
    const kx = dist > 0.01 ? dx / dist : fx;
    const kz = dist > 0.01 ? dz / dist : fz;
    const dirx = lerp(kx, fx, 0.6);
    const dirz = lerp(kz, fz, 0.6);
    const l = Math.hypot(dirx, dirz) || 1;
    this.bv.set((dirx / l) * 46 + p.vel.x * 0.3, 16 + (p.grounded ? 0 : 6), (dirz / l) * 46 + p.vel.z * 0.3);
    this.lastTouch = p.idx;
    Sound.play('slap', { gap: 0.05 });
    FX.ring(this.bp.clone(), '#ffffff', { size: 4, life: 0.3 });
    FX.burst(this.bp.clone(), 10, { color: '#ffffff', speed: 8, glow: true, grav: 0, life: 0.35, size: 0.3 });
  },

  fixed(dt) {
    if (this.phase !== 'play' || this.freezeT > 0) {
      this.ballPhysics(dt, false);
      return;
    }
    this.ballPhysics(dt, true);
  },

  ballPhysics(dt, live) {
    const r = this.BR;
    const b = this.bp;
    const v = this.bv;
    v.y -= 80 * dt;
    v.multiplyScalar(Math.exp(-0.15 * dt));
    b.addScaledVector(v, dt);
    if (b.y < r) {
      b.y = r;
      if (v.y < 0) v.y = Math.abs(v.y) > 4 ? -v.y * 0.55 : 0;
      const fr = Math.exp(-1.1 * dt);
      v.x *= fr;
      v.z *= fr;
    }
    const inGoalMouth = Math.abs(b.z) < this.GW - r * 0.3 && b.y < this.GH - r * 0.3;
    // Боковые борта
    if (Math.abs(b.z) > this.FZ - r) {
      b.z = Math.sign(b.z) * (this.FZ - r);
      v.z = -v.z * 0.7;
    }
    // Торцы и ворота
    const ax = Math.abs(b.x);
    if (ax > this.FX - r && !inGoalMouth && ax < this.FX + 1) {
      b.x = Math.sign(b.x) * (this.FX - r);
      v.x = -v.x * 0.7;
    }
    if (ax > this.FX) {
      const s = Math.sign(b.x);
      if (Math.abs(b.z) > this.GW - r) { b.z = Math.sign(b.z) * (this.GW - r); v.z = -v.z * 0.4; }
      if (b.y > this.GH - r) { b.y = this.GH - r; v.y = -Math.abs(v.y) * 0.4; }
      if (ax > this.FX + 6 - r) { b.x = s * (this.FX + 6 - r); v.x = -v.x * 0.3; }
      if (live && ax > this.FX + r * 0.9) this.goal(s > 0 ? 0 : 1);
    }
    // Штанги
    for (const sx of [-1, 1]) {
      for (const pz of [-this.GW, this.GW]) {
        const dx = b.x - sx * this.FX;
        const dz = b.z - pz;
        const d = Math.hypot(dx, dz);
        if (d < r + 0.4 && b.y < this.GH + 0.4) {
          const nx = dx / (d || 1);
          const nz = dz / (d || 1);
          b.x = sx * this.FX + nx * (r + 0.4);
          b.z = pz + nz * (r + 0.4);
          const vn = v.x * nx + v.z * nz;
          if (vn < 0) { v.x -= nx * vn * 1.7; v.z -= nz * vn * 1.7; }
        }
      }
    }
    // Игроки толкают мяч
    for (const p of Game.players) {
      if (p.dead) continue;
      const cx = clamp(b.x, p.pos.x - p.r, p.pos.x + p.r);
      const cy = clamp(b.y, p.pos.y, p.pos.y + p.h);
      const cz = clamp(b.z, p.pos.z - p.r, p.pos.z + p.r);
      let dx = b.x - cx;
      let dy = b.y - cy;
      let dz = b.z - cz;
      let d = Math.hypot(dx, dy, dz);
      if (d >= r) continue;
      if (d < 1e-4) { dx = b.x - p.pos.x; dz = b.z - p.pos.z; dy = 0; d = Math.hypot(dx, dz) || 1; }
      const nx = dx / d;
      const ny = dy / d;
      const nz = dz / d;
      b.set(cx + nx * r, cy + ny * r, cz + nz * r);
      if (b.y < r) b.y = r;
      const rv = (v.x - p.vel.x) * nx + (v.y - p.vel.y) * ny + (v.z - p.vel.z) * nz;
      if (rv < 0) {
        v.x -= nx * rv * 1.45;
        v.y -= ny * rv * 1.45;
        v.z -= nz * rv * 1.45;
        if (ny > 0.5 && !p.grounded) v.y += 6;
        this.lastTouch = p.idx;
        if (-rv > 12) Sound.play('push', { gap: 0.1 });
      }
    }
  },

  goal(team) {
    if (this.freezeT > 0) return;
    this.score[team]++;
    this.freezeT = 2.6;
    const P = Game.players;
    const s = team === 0 ? 1 : -1;
    FX.confetti(V3(s * (this.FX + 3), this.GH, 0), 140);
    Sound.play('win');
    const own = this.lastTouch !== -1 && this.lastTouch !== team;
    UI.banner(-1, 'ГОЛ!', { cls: team === 0 ? 'gold' : 'gold', dur: 2, sub: `${P[team].name} забивает${own ? ' (автогол!)' : ''} · ${this.score[0]} : ${this.score[1]}` });
    P[team].avatar.cheer = true;
    this.refreshBoard();
    if (this.score[team] >= this.GOALS) this.endAt = this.playT + 1.2;
  },

  end() {
    const [a, b] = this.score;
    const lines = `Счёт ${a} : ${b}<br>${gameRecordLine(this.id)}`;
    if (a === b) this.finish({ winner: -1, title: `Ничья ${a} : ${b}`, lines });
    else this.finish({ winner: a > b ? 0 : 1, lines, sub: ['Чемпион! ⚽', 'Реванш?'] });
  },

  tick(dt) {
    if (this.freezeT > 0) {
      this.freezeT -= dt;
      if (this.freezeT <= 0 && this.phase === 'play') {
        for (const p of Game.players) p.avatar.cheer = false;
        this.resetKickoff();
      }
    }
    if (Math.floor(this.playT) !== this.lastSec) {
      this.lastSec = Math.floor(this.playT);
      this.refreshBoard();
    }
    if (this.endAt && this.playT >= this.endAt) this.end();
    else if (this.playT >= this.TIME && this.freezeT <= 0) this.end();
  },

  // Камера смотрит на мяч, если игрок сам её не крутит.
  camFocus() { return this.bp; },

  frame(dt) {
    if (!this.ball) return;
    this.ball.position.copy(this.bp);
    const sp = Math.hypot(this.bv.x, this.bv.z);
    if (sp > 0.05) {
      const axis = V3(this.bv.z, 0, -this.bv.x).normalize();
      this.ball.rotateOnWorldAxis(axis, (sp / this.BR) * dt);
    }
    for (const c of this.crowd) c.m.position.y = c.base + Math.max(0, Math.sin(this.t * (this.freezeT > 0 ? 14 : 3) + c.ph)) * (this.freezeT > 0 ? 0.9 : 0.25);
  },

  drawHud(i) {
    const P = Game.players;
    const left = Math.max(0, this.TIME - this.playT);
    UI.hud(i, `<div class="chip big"><span style="color:var(--p1)">${this.score[0]}</span> : <span style="color:var(--p2)">${this.score[1]}</span></div><div class="chip">⏱ ${fmtTime(left)}<small>до ${this.GOALS} голов · ты бьёшь в ${i === 0 ? 'правые' : 'левые'} ворота</small></div>`);
    void P;
  },
});
