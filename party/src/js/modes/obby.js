'use strict';
// Обби-гонка в духе Tower of Hell: каждый раз новая трасса из случайных секций.

new MiniGame({
  id: 'obby',
  title: 'Обби-гонка',
  icon: '🏁',
  color: '#ff9f1c',
  short: 'Кто первый до финиша?',
  desc: 'Паркур-гонка: лава, вертушки, батуты, исчезающие плиты. Кто первым добежит до финиша — победил!',
  rules: 'Беги и прыгай! Флажки — чекпоинты. Кто первым коснётся финиша — победил.',
  music: 'obby',
  water: true,
  waterY: -70,
  killY: -200,
  camDist: 15,

  build() {
    this.theme = pick(['day', 'sunset', 'day']);
    setTheme(this.theme);
    const c = new Course(this.root, { dir: 0, y: 0, colorIdx: randi(0, 7) });
    this.course = c;
    c.plat(0, -5, 0, 16, 14, { color: '#5b6275', mat: 'smooth' });
    for (const s of [-1, 1]) c.plat(s * 3.5, -6, 0.15, 4, 4, { mat: 'neon', color: s < 0 ? '#3ea6ff' : '#ff5fa8', h: 0.2, collide: false });
    this.gate = c.box(0, 4, 1.6, 16, 8, 0.6, { mat: 'glass', color: '#bfe9ff' });
    signMesh(this.root, [{ text: '🏁 СТАРТ', size: 110 }], 0, 10.5, -1.6, 10, 2.8, { bg: '#1b2033', border: '#ff9f1c' });
    c.f = 2;
    const onCp = (p, index, spawn, heading) => {
      if (index <= p.checkpoint.index || p.dead) return;
      p.setCheckpoint(spawn, heading, index);
      Sound.play('checkpoint');
      FX.ring(V3(spawn.x, spawn.y + 0.4, spawn.z), '#40d47e', { size: 7, life: 0.6 });
      FX.burst(V3(spawn.x, spawn.y + 2, spawn.z), 24, { colors: ['#40d47e', '#ffffff', '#b8ffcf'], speed: 10, glow: true, grav: 6, life: 0.9, size: 0.3 });
      UI.toast(p.idx, `Этап ${index}/${this.total}!`, '#7dffb0');
    };
    const list = pickSections('obby', 8);
    this.total = list.length;
    list.forEach((k, i) => {
      c.nextColor();
      SECTIONS[k](c, Math.min(3, Math.floor(i / 2.4)));
      if (i < list.length - 1) c.checkpoint(onCp);
    });
    this.total = c.cpIndex;
    // Финиш
    const ff = c.f + 9;
    c.plat(0, ff, c.y, 20, 16, { mat: 'checker', color: '#ffffff' });
    const top = c.y;
    const gold = '#ffcc33';
    for (const s of [-1, 1]) c.box(s * 8, top + 6, ff - 4, 2, 12, 2, { mat: 'gold', color: gold });
    c.box(0, top + 12.5, ff - 4, 18, 2, 2, { mat: 'gold', color: gold, collide: false });
    const sign = signMesh(this.root, [{ text: '🏆 ФИНИШ', size: 110 }], 0, 0, 0, 12, 3.2, { bg: '#1b2033', border: gold });
    sign.position.copy(c.world(0, top + 15.4, ff - 4));
    const cup = new THREE.Mesh(new THREE.LatheGeometry([V3(0, 0), V3(1.2, 0), V3(0.4, 0.4), V3(0.3, 1.6), V3(1.4, 2.4), V3(1.7, 4.2), V3(1.5, 4.2), V3(1.2, 2.8), V3(0, 2.6)].map((v) => new THREE.Vector2(v.x, v.y)), 24), Mat.get('gold', gold));
    cup.position.copy(c.world(0, top, ff + 3));
    cup.castShadow = true;
    this.root.add(cup);
    this.cup = cup;
    const fp = c.world(0, top + 3, ff);
    World.addTrigger(fp.x, fp.y, fp.z, 20, 6, 16, (p) => {
      if (this.phase === 'play' && !p.dead) this.win(p);
    });
    this.finishF = ff - 8;
    // Декор вокруг трассы
    for (let i = 0; i < 9; i++) {
      const side = i % 2 ? 1 : -1;
      Deco.islet(this.root, side * rand(45, 90), rand(-30, 20), -i * (this.finishF / 9) - rand(0, 20), rand(6, 12));
    }
    this.spawns = [{ pos: V3(-3.5, 0.1, 6), heading: Math.PI }, { pos: V3(3.5, 0.1, 6), heading: Math.PI }];
  },

  onStart() {
    this.gate.col.active = false;
    this.gate.mesh.visible = false;
    Sound.play('glass');
  },

  win(p) {
    const o = Game.other(p);
    const lines = `Время: ${fmtTime(this.playT)} · ${esc(o.name)} на этапе ${o.checkpoint.index}/${this.total}<br>${gameRecordLine(this.id)}`;
    this.finish({ winner: p.idx, lines, sub: ['Ты добежал первым!', 'В следующий раз повезёт!'] });
  },

  tick() {
    for (const p of Game.players) {
      if (!p.dead && p.pos.y < p.checkpoint.pos.y - 32) p.die('fall');
    }
  },

  frame(dt) {
    if (this.course) this.course.animate(dt);
    if (this.cup) this.cup.rotation.y += dt;
  },

  progressOf(p) {
    return clamp(-p.pos.z / this.finishF, 0, 1);
  },

  drawHud(i) {
    const p = Game.players[i];
    const o = Game.other(p);
    UI.hud(i, `<div class="chip big">Этап ${p.checkpoint.index}/${this.total}</div><div class="chip">⏱ ${fmtTime(this.playT)}</div>`);
    const a = this.progressOf(p) * 100;
    const b = this.progressOf(o) * 100;
    UI.progress(i, `<div class="bar"><div class="fill" style="width:${Math.max(a, b).toFixed(1)}%"></div><div class="mk p${o.idx}" style="left:${b.toFixed(1)}%"></div><div class="mk p${p.idx} me" style="left:${a.toFixed(1)}%"></div></div>`);
  },
});
