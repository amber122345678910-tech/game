'use strict';
// Стеклянный мост: в каждой паре одна панель прочная, другая разбивается. Кто первым перейдёт — победил.

new MiniGame({
  id: 'glass',
  title: 'Стеклянный мост',
  icon: '🌉',
  color: '#2ec4b6',
  short: 'Угадай прочное стекло!',
  desc: 'В каждой паре одна панель хрупкая. Упадёшь — начнёшь сначала, но разбитое стекло подскажет дорогу.',
  rules: 'Прыгай по стеклу! В каждой паре одна панель разбивается. Можно толкаться: F / ⁄',
  ability: 'push',
  theme: 'night',
  music: 'glass',
  killY: 18,
  respawnDelay: 1.5,
  camDist: 14,
  camPitch: 0.38,
  H: 40,
  ROWS: 16,
  GAP: 6.5,
  TIME: 150,

  build() {
    const root = this.root;
    const H = this.H;
    // Старт
    part(root, 0, H - 1.5, 7, 22, 3, 14, { mat: 'smooth', color: '#e0457b' });
    part(root, 0, H - 4, 7, 20, 2, 12, { mat: 'neon', color: '#ff7ab0', collide: false });
    for (const [x, z] of [[-10, 1], [10, 1], [-10, 13], [10, 13]]) part(root, x, H / 2 - 1.5, z, 2, H - 3, 2, { mat: 'smooth', color: '#2a2f45' });
    this.gate = part(root, 0, H + 4, -0.2, 22, 8, 0.6, { mat: 'glass', color: '#bfe9ff' });
    signMesh(root, [{ text: '○ △ □', size: 120, color: '#ff7ab0' }], 0, H + 10.5, 1, 10, 3, { bg: '#14141f', border: '#ff7ab0' });

    // Панели
    this.rows = [];
    const steel = Mat.get('metal', '#9aa3ad');
    const len = this.ROWS * this.GAP + 6;
    const z0 = -4;
    for (const x of [-5, 0, 5]) {
      const m = new THREE.Mesh(boxGeo(0.5, 0.5, len), steel);
      m.position.set(x, H - 0.75, z0 - len / 2 + 3);
      m.castShadow = true;
      root.add(m);
    }
    for (let k = 0; k < this.ROWS; k++) {
      const z = z0 - 3 - k * this.GAP;
      const strong = randi(0, 1);
      const row = { z, panels: [] };
      const cross = new THREE.Mesh(boxGeo(10.5, 0.4, 0.4), steel);
      cross.position.set(0, H - 0.75, z + this.GAP / 2);
      root.add(cross);
      for (let s = 0; s < 2; s++) {
        const x = s === 0 ? -2.6 : 2.6;
        const pl = part(root, x, H - 0.2, z, 4.2, 0.4, 4.2, { mat: 'glass', color: '#9fe7ff', solid: true, noCam: true });
        pl.mesh.castShadow = false;
        const edge = new THREE.Mesh(new THREE.EdgesGeometry(new THREE.BoxGeometry(4.2, 0.4, 4.2)), new THREE.LineBasicMaterial({ color: 0xbff4ff, transparent: true, opacity: 0.7 }));
        edge.position.copy(pl.mesh.position);
        root.add(edge);
        const panel = { pl, edge, fake: s !== strong, broken: false, row: k };
        if (panel.fake) pl.col.onStand = (p) => this.breakPanel(panel, p);
        row.panels.push(panel);
      }
      this.rows.push(row);
    }
    // Финиш
    const zEnd = z0 - 3 - (this.ROWS - 1) * this.GAP - this.GAP / 2 - 7;
    this.zEnd = zEnd;
    part(root, 0, H - 1.5, zEnd, 22, 3, 14, { mat: 'smooth', color: '#1fae9a' });
    part(root, 0, H + 0.05, zEnd - 1, 10, 0.1, 6, { mat: 'checker', color: '#ffffff', collide: false });
    for (const [x, z] of [[-10, zEnd - 6], [10, zEnd - 6], [-10, zEnd + 6], [10, zEnd + 6]]) part(root, x, H / 2 - 1.5, z, 2, H - 3, 2, { mat: 'smooth', color: '#2a2f45' });
    const fs = signMesh(root, [{ text: '🏆 ФИНИШ', size: 110 }], 0, H + 9, zEnd - 6, 12, 3.2, { bg: '#14141f', border: '#2ec4b6' });
    fs.rotation.y = 0;
    World.addTrigger(0, H + 2, zEnd - 1, 20, 4, 10, (p) => { if (this.phase === 'play' && !p.dead) this.win(p); });

    // Земля внизу: тёмная арена с неоновыми линиями
    part(root, 0, -1, zEnd / 2, 120, 2, -zEnd + 140, { mat: 'smooth', color: '#151522', collide: false });
    for (let i = -3; i <= 3; i++) part(root, i * 14, 0.05, zEnd / 2, 0.6, 0.1, -zEnd + 120, { mat: 'neon', color: i % 2 ? '#ff7ab0' : '#2ec4b6', collide: false });
    this.lights = [];
    for (let i = 0; i < 6; i++) {
      const geo = new THREE.ConeGeometry(7, 60, 20, 1, true);
      geo.translate(0, -30, 0);
      const m = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color: i % 2 ? 0xff7ab0 : 0x7af0ff, transparent: true, opacity: 0.08, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide, toneMapped: false }));
      m.position.set(i % 2 ? 30 : -30, 70, zEnd * (i / 5));
      root.add(m);
      this.lights.push(m);
    }
    this.spawns = [{ pos: V3(-4, H + 0.1, 8), heading: Math.PI }, { pos: V3(4, H + 0.1, 8), heading: Math.PI }];
    this.falls = [0, 0];
    this.best = [0, 0];
  },

  breakPanel(panel, p) {
    if (panel.broken) return;
    panel.broken = true;
    panel.pl.col.active = false;
    panel.pl.mesh.visible = false;
    panel.edge.visible = false;
    const c = panel.pl.mesh.position;
    Sound.play('glass');
    for (let i = 0; i < 40; i++) {
      FX.emit({ x: c.x + rand(-2, 2), y: c.y, z: c.z + rand(-2, 2), vx: rand(-4, 4), vy: rand(-4, 6), vz: rand(-4, 4), life: rand(1.2, 2), size: rand(0.2, 0.55), color: pick(['#bff4ff', '#9fe7ff', '#e6fbff']), grav: 45 });
    }
    this.falls[p.idx]++;
    UI.toast(-1, `💥 ${p.name} провалился!`, '#9fe7ff');
  },

  onStart() {
    this.gate.col.active = false;
    this.gate.mesh.visible = false;
    Sound.play('glass');
  },

  rowOf(p) {
    let best = 0;
    this.rows.forEach((r, k) => { if (p.pos.z <= r.z + 2.2 && p.pos.y > this.H - 2) best = k + 1; });
    return best;
  },

  win(p) {
    const lines = `Время: ${fmtTime(this.playT)} · провалов: ${esc(Game.players[0].name)} ${this.falls[0]}, ${esc(Game.players[1].name)} ${this.falls[1]}<br>${gameRecordLine(this.id)}`;
    this.finish({ winner: p.idx, lines, sub: ['Ты перешёл мост!', 'Стекло подвело...'] });
  },

  tick() {
    Game.players.forEach((p, i) => { if (!p.dead) this.best[i] = Math.max(this.best[i], this.rowOf(p)); });
    if (this.playT >= this.TIME) {
      const [a, b] = this.best;
      const lines = `Время вышло! Дальше всех: ряд ${a} и ряд ${b}<br>${gameRecordLine(this.id)}`;
      if (a === b) this.finish({ winner: -1, title: 'Время вышло — ничья!', lines });
      else this.finish({ winner: a > b ? 0 : 1, lines, sub: ['Ты прошёл дальше!', 'Чуть-чуть не хватило...'] });
    }
  },

  frame(dt) {
    if (!this.lights) return;
    this.lights.forEach((l, i) => { l.rotation.z = Math.sin(this.t * 0.5 + i) * 0.35; l.rotation.x = Math.cos(this.t * 0.4 + i) * 0.25; });
  },

  drawHud(i) {
    const p = Game.players[i];
    const o = Game.other(p);
    const left = Math.max(0, this.TIME - this.playT);
    UI.hud(i, `<div class="chip big">Ряд ${this.rowOf(p)}/${this.ROWS}</div><div class="chip" style="${left < 20 ? 'color:#ff6a6a' : ''}">⏱ ${fmtTime(left)}</div>`);
    const a = (this.rowOf(p) / this.ROWS) * 100;
    const b = (this.rowOf(o) / this.ROWS) * 100;
    UI.progress(i, `<div class="bar"><div class="fill" style="width:${Math.max(a, b)}%"></div><div class="mk p${o.idx}" style="left:${b}%"></div><div class="mk p${p.idx} me" style="left:${a}%"></div></div>`);
  },
});
