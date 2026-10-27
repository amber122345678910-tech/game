'use strict';
// Цветные плитки (Block Party): назвали цвет — беги на него, остальные плитки проваливаются.

const BP_COLORS = [
  { n: 'КРАСНЫЙ', c: '#ff3b3b' }, { n: 'ОРАНЖЕВЫЙ', c: '#ff9f1c' }, { n: 'ЖЁЛТЫЙ', c: '#ffe14d' }, { n: 'ЗЕЛЁНЫЙ', c: '#3ddc84' },
  { n: 'ГОЛУБОЙ', c: '#3ec7ff' }, { n: 'СИНИЙ', c: '#3a5bff' }, { n: 'ФИОЛЕТОВЫЙ', c: '#a259ff' }, { n: 'РОЗОВЫЙ', c: '#ff5fbf' },
];

const BP_PATTERNS = {
  noise: (i, j, k) => Math.floor(Math.random() * k),
  stripes: (i, j, k, s) => Math.floor((s.dir ? i : j) / s.w) % k,
  diag: (i, j, k, s) => Math.floor((i + j * s.dir2) / s.w + 100) % k,
  rings: (i, j, k, s) => Math.floor(Math.hypot(i - s.cx, j - s.cy) / s.w) % k,
  checker: (i, j, k, s) => (Math.floor(i / s.w) + Math.floor(j / s.w) * 3) % k,
  blobs: (i, j, k, s) => {
    let best = 0;
    let bd = 1e9;
    s.seeds.forEach((p, q) => { const d = (p[0] - i) ** 2 + (p[1] - j) ** 2; if (d < bd) { bd = d; best = q; } });
    return s.seeds[best][2];
  },
  spiral: (i, j, k, s) => Math.floor(((Math.atan2(j - s.cx, i - s.cy) / TAU + 1) * k + Math.hypot(i - s.cx, j - s.cy) / s.w)) % k,
};

new MiniGame({
  id: 'blocks',
  title: 'Цветные плитки',
  icon: '🎨',
  color: '#7b6cff',
  short: 'Успей на нужный цвет!',
  desc: 'Назовут цвет — беги на плитку этого цвета, остальные провалятся. Кто упадёт — проиграл.',
  rules: 'Беги на плитку названного цвета! Остальные провалятся. Можно толкаться: F / ⁄',
  ability: 'push',
  theme: 'disco',
  music: 'blocks',
  autoRespawn: false,
  killY: -14,
  camDist: 17,
  camPitch: 0.45,
  N: 12,
  T: 4,

  build() {
    const root = this.root;
    const N = this.N;
    const T = this.T;
    const half = (N * T) / 2;
    this.tileMats = BP_COLORS.map((c) => {
      const side = new THREE.MeshStandardMaterial({ color: c.c, emissive: c.c, emissiveIntensity: 0.25, roughness: 0.4 });
      const top = new THREE.MeshStandardMaterial({ color: c.c, map: R.tex.stud, normalMap: R.tex.studN, emissive: c.c, emissiveIntensity: 0.32, roughness: 0.35 });
      return [side, side, top, side, side, side];
    });
    this.tiles = [];
    for (let i = 0; i < N; i++) {
      for (let j = 0; j < N; j++) {
        const x = -half + T / 2 + i * T;
        const z = -half + T / 2 + j * T;
        const pl = part(root, x, -0.6, z, T, 1.2, T, { color: '#ffffff' });
        pl.mesh.material = this.tileMats[0];
        this.tiles.push({ i, j, pl, base: V3(x, -0.6, z), color: 0, state: 'up', v: 0, y: -0.6 });
      }
    }
    // Борта по краю, чтобы не свалиться с площадки сбоку
    const rail = Mat.get('glass', '#cfe7ff');
    for (const [x, z, sx, sz] of [[0, -half - 0.5, N * T + 2, 1], [0, half + 0.5, N * T + 2, 1], [-half - 0.5, 0, 1, N * T], [half + 0.5, 0, 1, N * T]]) {
      const m = new THREE.Mesh(boxGeo(sx, 1.6, sz), rail);
      m.position.set(x, 0.8, z);
      root.add(m);
      World.addBox(x, 6, z, sx, 14, sz, { noCam: true });
      part(root, x, -0.9, z, sx, 1.8, sz, { mat: 'neon', color: '#ff5fbf', collide: false });
    }
    // Диско-шар, колонки, экраны
    const ball = new THREE.Mesh(new THREE.IcosahedronGeometry(3.2, 2), new THREE.MeshStandardMaterial({ color: 0xdddddd, metalness: 1, roughness: 0.12, flatShading: true }));
    ball.position.set(0, 26, 0);
    root.add(ball);
    this.ball = ball;
    part(root, 0, 34, 0, 0.2, 13, 0.2, { color: '#aaaaaa', collide: false });
    this.beams = [];
    for (let k = 0; k < 6; k++) {
      const geo = new THREE.ConeGeometry(4, 40, 16, 1, true);
      geo.translate(0, -20, 0);
      const m = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color: BP_COLORS[k].c, transparent: true, opacity: 0.12, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide, toneMapped: false }));
      m.position.set(0, 26, 0);
      root.add(m);
      this.beams.push(m);
    }
    this.screens = [];
    for (const [x, z, ry] of [[0, -half - 14, 0], [0, half + 14, Math.PI], [-half - 14, 0, Math.PI / 2], [half + 14, 0, -Math.PI / 2]]) {
      const frame = new THREE.Mesh(boxGeo(19, 11, 1), Mat.get('smooth', '#1b1b26'));
      frame.position.set(x, 12, z);
      frame.rotation.y = ry;
      root.add(frame);
      const scr = new THREE.Mesh(new THREE.PlaneGeometry(17.5, 9.5), new THREE.MeshBasicMaterial({ color: 0x222233, toneMapped: false }));
      scr.position.set(x + Math.sin(ry) * 0.55, 12, z + Math.cos(ry) * 0.55);
      scr.rotation.y = ry;
      root.add(scr);
      this.screens.push(scr);
      for (const s of [-1, 1]) {
        const sp = new THREE.Mesh(boxGeo(4, 8, 4), Mat.get('smooth', '#22222c'));
        sp.position.set(x + Math.cos(ry) * s * 13, 4, z - Math.sin(ry) * s * 13);
        root.add(sp);
        const cone = new THREE.Mesh(new THREE.CylinderGeometry(1.4, 1.4, 0.3, 20), Mat.get('neon', BP_COLORS[(k2(x, z) + s + 8) % 8].c));
        cone.rotation.x = Math.PI / 2;
        cone.rotation.z = ry;
        cone.position.set(sp.position.x + Math.sin(ry) * 2.05, 5, sp.position.z + Math.cos(ry) * 2.05);
        root.add(cone);
      }
    }
    function k2(x, z) { return Math.abs(Math.round(x + z)) % 8; }
    // Пол глубоко внизу
    part(root, 0, -40, 0, 140, 2, 140, { mat: 'neon', color: '#2a1450', collide: false });
    this.spawns = [{ pos: V3(-6, 0.1, 8), heading: Math.PI }, { pos: V3(6, 0.1, 8), heading: Math.PI }];
    this.round = 0;
    this.st = 'wait';
    this.stT = 0;
    this.target = -1;
    this.applyPattern(true);
    this.setScreens(null);
  },

  setScreens(ci) {
    for (const s of this.screens) s.material.color.set(ci == null ? '#222233' : BP_COLORS[ci].c);
  },

  applyPattern(instant) {
    const k = Math.min(BP_COLORS.length, 4 + Math.floor(this.round / 2));
    const pal = shuffle(BP_COLORS.map((_, q) => q)).slice(0, k);
    const name = pick(Object.keys(BP_PATTERNS));
    const s = {
      dir: chance(0.5), w: randi(1, 3), dir2: pick([-1, 1]), cx: rand(2, this.N - 3), cy: rand(2, this.N - 3),
      seeds: Array.from({ length: randi(7, 12) }, () => [rand(0, this.N), rand(0, this.N), randi(0, k - 1)]),
    };
    for (const t of this.tiles) {
      const ci = pal[BP_PATTERNS[name](t.i, t.j, k, s) % k];
      t.color = ci;
      t.pl.mesh.material = this.tileMats[ci];
      if (instant) {
        t.state = 'up';
        t.pl.col.active = true;
        t.pl.mesh.position.copy(t.base);
      }
    }
  },

  pickTarget() {
    const counts = {};
    for (const t of this.tiles) counts[t.color] = (counts[t.color] || 0) + 1;
    const ok = Object.keys(counts).filter((c) => counts[c] >= 5).map(Number);
    return pick(ok.length ? ok : Object.keys(counts).map(Number));
  },

  onStart() {
    this.st = 'dance';
    this.stT = 2.5;
  },

  onDeath(p) {
    p.out = true;
  },

  tick(dt) {
    this.stT -= dt;
    if (this.st === 'dance' && this.stT <= 0) {
      this.round++;
      this.target = this.pickTarget();
      this.callTime = Math.max(1.35, 4.4 - this.round * 0.26);
      this.st = 'call';
      this.stT = this.callTime;
      this.lastTick = 99;
      const c = BP_COLORS[this.target];
      UI.banner(-1, c.n + '!', { dur: 1.2, cls: 'small' });
      for (const h of UI.halves) h.banner.style.color = c.c;
      this.setScreens(this.target);
      Sound.play('beep');
      Music.duck(true);
    } else if (this.st === 'call') {
      const n = Math.ceil(this.stT * 2);
      if (n !== this.lastTick) { this.lastTick = n; Sound.play('tick'); }
      if (this.stT <= 0) {
        this.st = 'drop';
        this.stT = 2.6;
        for (const t of this.tiles) {
          if (t.color !== this.target) { t.state = 'fall'; t.v = 0; t.pl.col.active = false; }
        }
        Sound.play('drop');
        for (const h of UI.halves) h.banner.style.color = '';
      }
    } else if (this.st === 'drop' && this.stT <= 0) {
      const out = Game.players.map((p) => p.dead || p.pos.y < -3);
      if (out[0] || out[1]) {
        for (const p of Game.players) if (!p.dead && p.pos.y < -3) p.die('fall');
        const lines = `Продержались раундов: ${this.round}<br>${gameRecordLine(this.id)}`;
        if (out[0] && out[1]) this.finish({ winner: -1, title: 'Оба упали — ничья!', lines });
        else this.finish({ winner: out[0] ? 1 : 0, lines, sub: ['Ты устоял!', 'Пол ушёл из-под ног...'] });
        return;
      }
      this.st = 'restore';
      this.stT = 1.2;
      this.applyPattern(false);
      for (const t of this.tiles) if (t.state === 'fall' || t.state === 'down') { t.state = 'rise'; t.pl.mesh.position.y = t.base.y - 24; }
      this.setScreens(null);
      Sound.play('rise');
      Music.duck(false);
    } else if (this.st === 'restore' && this.stT <= 0) {
      for (const t of this.tiles) { t.state = 'up'; t.pl.col.active = true; t.pl.mesh.position.copy(t.base); }
      this.st = 'dance';
      this.stT = Math.max(1.0, 2.2 - this.round * 0.08);
    }
  },

  frame(dt) {
    for (const t of this.tiles) {
      const m = t.pl.mesh;
      if (t.state === 'fall') {
        t.v += 50 * dt;
        m.position.y -= t.v * dt;
        if (m.position.y < -30) t.state = 'down';
      } else if (t.state === 'rise') {
        m.position.y = damp(m.position.y, t.base.y, 7, dt);
      } else if (t.state === 'up' && this.st === 'call' && t.color === this.target) {
        m.position.y = t.base.y + Math.abs(Math.sin(this.t * 8)) * 0.15;
      } else if (t.state === 'up' && m.position.y !== t.base.y) m.position.y = t.base.y;
    }
    if (this.ball) {
      this.ball.rotation.y += dt * 0.6;
      this.beams.forEach((b, k) => {
        const a = this.t * 0.7 + (k / this.beams.length) * TAU;
        b.rotation.set(Math.sin(a) * 0.55, 0, Math.cos(a * 1.3) * 0.55);
      });
    }
  },

  cleanup() {
    Music.duck(false);
    for (const h of UI.halves) h.banner.style.color = '';
    for (const mats of this.tileMats || []) { mats[0].dispose(); mats[2].dispose(); }
    for (const p of Game.players) p.out = false;
  },

  drawHud(i) {
    let html = `<div class="chip big">Раунд ${Math.max(1, this.round)}</div>`;
    if (this.st === 'call' && this.target >= 0) {
      const c = BP_COLORS[this.target];
      const pct = clamp(this.stT / this.callTime, 0, 1) * 100;
      html += `<div class="chip big"><span class="sw" style="background:${c.c}"></span>${c.n}</div>`;
      UI.progress(i, `<div class="timerbar"><div class="fill" style="width:${pct.toFixed(0)}%;background:${c.c}"></div></div>`);
    } else UI.progress(i, '');
    if (this.st === 'drop') html += '<div class="chip">Держись!</div>';
    UI.hud(i, html);
  },
});
