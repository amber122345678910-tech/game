'use strict';
// Лобби: остров с порталами в мини-игры. Встаньте вдвоём на круг портала — начнётся отсчёт.

const PORTAL_VS = `
varying vec2 vUv;
void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`;
const PORTAL_FS = `
uniform float time; uniform vec3 colA; uniform vec3 colB; varying vec2 vUv;
void main() {
  vec2 p = vUv * 2.0 - 1.0;
  float r = length(p);
  float a = atan(p.y, p.x);
  float s = sin(a * 4.0 + r * 9.0 - time * 3.5);
  float s2 = sin(a * -2.0 + r * 5.0 + time * 2.0);
  vec3 c = mix(colA, colB, s * 0.5 + 0.5) + (1.0 - r) * 0.55 + s2 * 0.08;
  float alpha = smoothstep(1.0, 0.82, r) * 0.92;
  gl_FragColor = vec4(c, alpha);
}`;

const Lobby = {
  id: 'lobby',
  title: 'Лобби',
  theme: 'day',

  enter() {
    World.clear();
    World.killY = -40;
    this.root = new THREE.Group();
    R.scene.add(this.root);
    setTheme('day');
    R.water.visible = true;
    R.water.position.y = -3;
    this.portals = [];
    this.count = null;
    this.t = 0;
    this.padLock = [false, false];
    this.build();
    for (const p of Game.players) {
      p.ability = 'push';
      p.frozen = false;
      p.camMode = 'follow';
      p.camDist = 16;
      p.camPitch = 0.32;
      p.speedMul = 1;
      p.jumpMul = 1;
      p.avatar.cheer = false;
      p.avatar.setGlove(null);
    }
    Game.players.forEach((p, i) => p.spawn(this.spawnPos(i), Math.PI));
    UI.clearHud();
    for (let i = 0; i < 2; i++) UI.hint(i, this.hintFor(i));
    Music.play('lobby');
    this.refreshBoard();
  },

  hintFor(i) {
    return i === 0 ? '<kbd>WASD</kbd> бег · <kbd>Пробел</kbd> прыжок · <kbd>F</kbd> толкнуть · <kbd>R</kbd> ❤ · <kbd>Esc</kbd> меню'
      : '<kbd>Стрелки</kbd> бег · <kbd>Enter</kbd> прыжок · <kbd>/</kbd> толкнуть · <kbd>\'</kbd> ❤ · <kbd>Esc</kbd> меню';
  },

  spawnPos(i) { return V3(i === 0 ? -4 : 4, 0.4, 12); },

  build() {
    const root = this.root;
    // Остров: пляж + трава
    part(root, 0, -2, 0, 150, 3, 150, { mat: 'sand', color: '#ffffff' });
    part(root, 0, -1.5, 0, 128, 3, 128, { mat: 'grass', color: '#ffffff' });
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * TAU + 0.2;
      Deco.rock(root, Math.cos(a) * 73, -0.5, Math.sin(a) * 73, rand(1.2, 2.2), false);
    }
    // Площадь
    cylPart(root, 0, 0, 6, 17, 0.3, { mat: 'stone', color: '#e9e3d6', seg: 48 });
    for (let i = 0; i < 2; i++) {
      const sp = this.spawnPos(i);
      part(root, sp.x, 0.35, sp.z, 5, 0.1, 5, { mat: 'neon', color: i ? '#ff5fa8' : '#3ea6ff', collide: false });
      part(root, sp.x, 0.2, sp.z, 6, 0.3, 6, { mat: 'smooth', color: '#5b6275' });
    }
    // Фонтан
    cylPart(root, 0, 0.3, -6, 5, 1.4, { mat: 'stone', color: '#d9d4c8' });
    const water = new THREE.Mesh(new THREE.CylinderGeometry(4.4, 4.4, 0.2, 32), new THREE.MeshStandardMaterial({ color: 0x4fb6ff, roughness: 0.1, transparent: true, opacity: 0.85 }));
    water.position.set(0, 1.62, -6);
    root.add(water);
    cylPart(root, 0, 1.7, -6, 0.8, 3.2, { mat: 'stone', color: '#d9d4c8' });
    cylPart(root, 0, 4.9, -6, 2.2, 0.5, { mat: 'stone', color: '#d9d4c8', collide: false });
    this.fountainPos = V3(0, 5.5, -6);

    // Порталы
    const angles = [-75, -50, -25, 0, 25, 50, 75];
    GAME_ORDER.forEach((id, k) => this.buildPortal(MODES[id], (angles[k] * Math.PI) / 180, 46));

    // Гардероб
    this.buildWardrobe(V3(0, 0, 34));

    // Табло
    const board = new THREE.Mesh(new THREE.PlaneGeometry(22, 14), new THREE.MeshBasicMaterial({ toneMapped: false }));
    board.position.set(-30, 10, 26);
    board.rotation.y = Math.PI * 0.72;
    root.add(board);
    this.board = board;
    const bp = board.position;
    const back = new THREE.Mesh(boxGeo(23.5, 15.5, 0.8), Mat.get('smooth', '#2b3150'));
    back.position.set(bp.x - Math.sin(board.rotation.y) * 0.45, 10, bp.z - Math.cos(board.rotation.y) * 0.45);
    back.rotation.y = board.rotation.y;
    back.castShadow = true;
    root.add(back);
    for (const sx of [-8, 8]) {
      const lx = bp.x + Math.cos(board.rotation.y) * sx;
      const lz = bp.z - Math.sin(board.rotation.y) * sx;
      cylPart(root, lx, 0, lz, 0.6, 3, { mat: 'metal', color: '#3a3f55' });
    }

    // Батут и вышка
    cylPart(root, 16, 0, 14, 3.5, 0.6, { mat: 'smooth', color: '#2b2f3a' });
    cylPart(root, 16, 0.6, 14, 3.1, 0.3, { mat: 'glow', color: '#7ed321', bounce: 95 });
    const tx = 30;
    const tz = 14;
    for (const [dx, dz] of [[-3, -3], [3, -3], [-3, 3], [3, 3]]) part(root, tx + dx, 8, tz + dz, 1, 16, 1, { mat: 'wood', color: '#b07a4a' });
    part(root, tx, 16.5, tz, 8, 1, 8, { mat: 'wood', color: '#c98e58' });
    part(root, tx, 17.5, tz + 4, 8, 1.6, 0.4, { mat: 'wood', color: '#b07a4a' });
    part(root, tx + 4, 17.5, tz, 0.4, 1.6, 8, { mat: 'wood', color: '#b07a4a' });
    part(root, tx - 3.2, 8.2, tz - 4.6, 2.4, 16.4, 1, { mat: 'truss', color: '#c0c6d0', climb: true });
    signMesh(root, [{ text: '🧗 Вышка', size: 90 }], tx, 20.2, tz - 4.2, 7, 2.2, { bg: '#1b2033' });

    // Парящие ступеньки к вышке
    const steps = [[18, 2.5, 24], [22, 5, 27], [26, 7.5, 28], [31, 10, 27], [35, 12.5, 24], [36, 15, 19]];
    steps.forEach(([x, y, z], i) => part(root, x, y, z, 3.5, 1, 3.5, { color: RAINBOW[i % RAINBOW.length] }));

    // Декор
    const avoid = [];
    for (const pt of this.portals) avoid.push(pt.pos);
    avoid.push(V3(0, 0, 34), V3(-30, 0, 26), V3(30, 0, 14), V3(16, 0, 14));
    let placed = 0;
    for (let tries = 0; placed < 34 && tries < 400; tries++) {
      const a = rand(0, TAU);
      const d = rand(24, 62);
      const x = Math.cos(a) * d;
      const z = Math.sin(a) * d;
      if (avoid.some((v) => Math.hypot(v.x - x, v.z - z) < 11)) continue;
      if (d < 30 && z > -2 && z < 20) continue;
      Deco.tree(root, x, 0, z, rand(0.85, 1.35), { pine: chance(0.25) });
      if (chance(0.5)) Deco.flowers(root, x + rand(-4, 4), 0, z + rand(-4, 4), randi(4, 8), 2);
      placed++;
    }
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * TAU + Math.PI / 8;
      Deco.lamp(root, Math.cos(a) * 19.5, 0, 6 + Math.sin(a) * 19.5);
    }
    for (let i = 0; i < 6; i++) Deco.islet(root, Math.cos(i * 1.1) * rand(160, 240), rand(25, 60), Math.sin(i * 1.1) * rand(160, 240), rand(6, 12));
  },

  buildPortal(mode, a, dist) {
    const root = this.root;
    const pos = V3(Math.sin(a) * dist, 0, -Math.cos(a) * dist);
    const n = V3(-pos.x, 0, -pos.z).normalize();
    const t = V3(-n.z, 0, n.x);
    const facing = Math.atan2(n.x, n.z);
    cylPart(root, pos.x, 0, pos.z, 5, 0.45, { mat: 'smooth', color: '#f4f4f4', seg: 40 });
    cylPart(root, pos.x, 0, pos.z, 5.4, 0.3, { mat: 'neon', color: mode.color, collide: false, seg: 40 });
    const ring = new THREE.Mesh(new THREE.TorusGeometry(4.3, 0.18, 8, 48), new THREE.MeshBasicMaterial({ color: mode.color, toneMapped: false }));
    ring.rotation.x = Math.PI / 2;
    ring.position.set(pos.x, 0.52, pos.z);
    root.add(ring);

    const archC = pos.clone().addScaledVector(n, -5.5);
    const pillarMat = Mat.get('plastic', shade(mode.color, -0.25));
    for (const s of [-1, 1]) {
      const pp = archC.clone().addScaledVector(t, s * 6.3);
      const m = new THREE.Mesh(boxGeo(2.4, 14, 2.4), pillarMat);
      m.position.set(pp.x, 7, pp.z);
      m.rotation.y = facing;
      m.castShadow = true;
      m.receiveShadow = true;
      root.add(m);
      World.addCyl(pp.x, pp.z, 1.4, 0, 14, {});
    }
    const beam = new THREE.Mesh(boxGeo(15, 2.4, 2.6), Mat.get('plastic', mode.color));
    beam.position.set(archC.x, 15, archC.z);
    beam.rotation.y = facing;
    beam.castShadow = true;
    root.add(beam);
    const uni = { time: { value: 0 }, colA: { value: new THREE.Color(mode.color) }, colB: { value: new THREE.Color(shade(mode.color, 0.6)) } };
    const swirl = new THREE.Mesh(new THREE.PlaneGeometry(10.2, 13.6), new THREE.ShaderMaterial({ uniforms: uni, vertexShader: PORTAL_VS, fragmentShader: PORTAL_FS, transparent: true, side: THREE.DoubleSide, depthWrite: false }));
    swirl.position.set(archC.x, 7, archC.z);
    swirl.rotation.y = facing;
    root.add(swirl);
    const sign = signMesh(root, [{ text: mode.icon + ' ' + mode.title, size: 92 }, { text: mode.short, size: 50, color: '#cfd6ea', weight: 700 }], archC.x, 19.6, archC.z, 17, 5.4, { bg: '#1b2033', border: mode.color, texH: 324 });
    sign.rotation.y = facing;
    sign.position.addScaledVector(n, 0.2);
    const tag = mode.coop ? 'ВМЕСТЕ' : '1 НА 1';
    const tagMesh = signMesh(root, [{ text: tag, size: 64 }], 0, 0, 0, 5, 1.6, { bg: mode.coop ? '#16a34a' : '#e8458f', texH: 328 });
    tagMesh.position.set(archC.x, 16.5, archC.z).addScaledVector(n, 1.4);
    tagMesh.rotation.y = facing;
    this.portals.push({ id: mode.id, mode, pos, uni, n });
  },

  buildWardrobe(c) {
    const root = this.root;
    cylPart(root, c.x, 0, c.z, 6, 0.4, { mat: 'smooth', color: '#ffd1e6', seg: 40 });
    cylPart(root, c.x, 0, c.z, 6.3, 0.25, { mat: 'neon', color: '#ff6fb5', collide: false, seg: 40 });
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * TAU + Math.PI / 6;
      if (i === 4) continue;
      cylPart(root, c.x + Math.cos(a) * 5.6, 0.4, c.z + Math.sin(a) * 5.6, 0.45, 9, { mat: 'smooth', color: '#ffffff' });
    }
    const roof = new THREE.Mesh(new THREE.ConeGeometry(8, 4, 6), Mat.get('smooth', '#ff6fb5'));
    roof.position.set(c.x, 11.4, c.z);
    roof.rotation.y = Math.PI / 6;
    roof.castShadow = true;
    root.add(roof);
    const mirror = new THREE.Mesh(new THREE.PlaneGeometry(4, 7), new THREE.MeshStandardMaterial({ color: 0xcfe8ff, metalness: 1, roughness: 0.05 }));
    mirror.position.set(c.x, 4.4, c.z + 5);
    mirror.rotation.y = Math.PI;
    root.add(mirror);
    signMesh(root, [{ text: '👕 ГАРДЕРОБ', size: 96 }], c.x, 10.4, c.z - 6.2, 9, 2.6, { bg: '#1b2033', border: '#ff6fb5', rotY: Math.PI });
    this.wardrobe = c;
  },

  refreshBoard() {
    if (!this.board) return;
    const [a, b] = Store.data.wins;
    const P = Game.players;
    const lines = [
      { text: '🏆 СЧЁТ', size: 92, color: '#ffcc33' },
      { text: `${P[0].name}  ${a} : ${b}  ${P[1].name}`, size: 76 },
    ];
    for (const id of GAME_ORDER) {
      const m = MODES[id];
      if (m.coop) {
        const rec = Store.data.records[id];
        lines.push({ text: `${m.icon} ${m.title}: ${rec ? m.recordText(rec) : 'ещё не играли'}`, size: 44, color: '#cfd6ea', weight: 700, gap: 1.35 });
      } else {
        const g = Store.data.games[id] || [0, 0];
        lines.push({ text: `${m.icon} ${m.title}: ${g[0]} : ${g[1]}`, size: 44, color: '#cfd6ea', weight: 700, gap: 1.35 });
      }
    }
    const old = this.board.material.map;
    this.board.material.map = signTexture(lines, { w: 1024, h: 652, top: 92, bg: '#1b2033', border: '#ffcc33', radius: 30 });
    this.board.material.needsUpdate = true;
    if (old) old.dispose();
  },

  onStand(p) {
    for (const pt of this.portals) {
      if (Math.hypot(p.pos.x - pt.pos.x, p.pos.z - pt.pos.z) < 4.6 && p.pos.y < 2 && p.pos.y > -0.5) return pt;
    }
    return null;
  },

  update(dt) {
    this.t += dt;
    for (const pt of this.portals) pt.uni.time.value = this.t;
    const P = Game.players;
    // Вода — плюх и обратно на спавн
    P.forEach((p, i) => {
      if (!p.dead && p.pos.y < -2.4) {
        Sound.play('splash');
        FX.burst(V3(p.pos.x, -2.6, p.pos.z), 30, { colors: ['#bfe9ff', '#ffffff', '#5ab8ff'], speed: 10, up: 1.6, lift: 10, grav: 40, size: 0.35, life: 1 });
        p.spawn(this.spawnPos(i), Math.PI);
      }
      if (p.dead && p.deadT > 1.4) p.spawn(this.spawnPos(i), Math.PI);
    });
    // Фонтан
    if (Math.random() < dt * 40) FX.emit({ x: this.fountainPos.x + rand(-0.3, 0.3), y: this.fountainPos.y, z: this.fountainPos.z + rand(-0.3, 0.3), vx: rand(-2.5, 2.5), vy: rand(10, 14), vz: rand(-2.5, 2.5), life: 1.1, size: rand(0.18, 0.3), color: pick(['#bfe9ff', '#ffffff', '#8fd3ff']), grav: 26 });
    // Искры над порталами
    for (const pt of this.portals) {
      if (Math.random() < dt * 8) {
        const a = rand(0, TAU);
        FX.emit({ x: pt.pos.x + Math.cos(a) * 4.3, y: 0.6, z: pt.pos.z + Math.sin(a) * 4.3, vy: rand(2, 5), life: 1.4, size: rand(0.15, 0.3), color: pt.mode.color, glow: true, grav: -1 });
      }
    }

    // Гардероб
    P.forEach((p, i) => {
      if (UI.editorOpen(i) || p.dead) return;
      const inW = Math.hypot(p.pos.x - this.wardrobe.x, p.pos.z - this.wardrobe.z) < 5 && p.pos.y < 2;
      if (inW && !this.padLock[i]) {
        this.padLock[i] = true;
        Game.openEditor(i, false);
      }
      if (!inW) this.padLock[i] = false;
    });

    // Порталы
    const on = P.map((p, i) => (p.dead || UI.editorOpen(i) ? null : this.onStand(p)));
    if (on[0] && on[1] && on[0] === on[1]) {
      if (!this.count || this.count.pt !== on[0]) {
        this.count = { pt: on[0], t: 3.99, last: 5 };
        Sound.play('portal');
      }
      this.count.t -= dt;
      const n = Math.ceil(this.count.t);
      if (n !== this.count.last && n >= 1) {
        this.count.last = n;
        if (n <= 3) { UI.banner(-1, String(n), { dur: 0.8 }); Sound.play('beep'); }
      }
      if (this.count.t <= 0) {
        const id = this.count.pt.id;
        this.count = null;
        Game.startMode(id);
        return;
      }
    } else if (this.count) {
      this.count = null;
      UI.clearBanner(-1);
    }
    for (let i = 0; i < 2; i++) {
      const me = on[i];
      const other = on[1 - i];
      const op = P[1 - i];
      let html = '';
      if (me && other === me) html = `<b>${me.mode.icon} ${esc(me.mode.title)}</b> — начинаем!`;
      else if (me) html = `<b>${me.mode.icon} ${esc(me.mode.title)}</b><br><span style="font-weight:600;font-size:14px">${esc(me.mode.desc)}</span><br>Ждём ${esc(op.name)} на этом круге… (1/2)`;
      else if (other) html = `${esc(op.name)} ждёт тебя в портале <b>${other.mode.icon} ${esc(other.mode.title)}</b>!`;
      UI.prompt(i, html);
      UI.hud(i, `<div class="chip big">🏝 Лобби</div><div class="chip">Встаньте вдвоём в круг портала<small>Esc — меню и быстрый выбор игры</small></div>`);
    }
  },

  dispose() {
    R.scene.remove(this.root);
    disposeTree(this.root);
    this.board = null;
    World.clear();
    FX.clearAll();
  },
};
