/* ===== 05d_codex_engine.js ===== */
// Движок Кодекса: на нём работают все игры, которые программирует сам Амиго.
// Игра — это «чертёж» (spec): герой, предметы, правила появления, правила касаний, события и умения.
// Движок не знает ничего про экран: рисует его 08c_codex_view.js. Поэтому Амиго может «прогнать» игру
// без картинки и проверить её роботом-игроком (режим Ультра).
// Модуль — одна функция: так его код можно целиком положить в отдельный HTML-файл игры.
function codexEngineModule() {
  'use strict';
  const W = 360, H = 480, R0 = 17;
  function rng(seed) {
    let t = seed >>> 0;
    return () => { t = (t + 0x6D2B79F5) >>> 0; let r = Math.imul(t ^ (t >>> 15), 1 | t); r ^= r + Math.imul(r ^ (r >>> 7), 61 | r); return ((r ^ (r >>> 14)) >>> 0) / 4294967296; };
  }
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const POWER = {
    shield: { emoji: '🛡️', name: 'Щит', time: 6 }, magnet: { emoji: '🧲', name: 'Магнит', time: 7 }, slow: { emoji: '⏳', name: 'Замедление', time: 5 },
    double: { emoji: '💫', name: 'Двойные очки', time: 8 }, heart: { emoji: '❤️', name: '+1 жизнь' }, bomb: { emoji: '💥', name: 'Бабах!' },
  };
  const MOVES = ['still', 'fall', 'rise', 'left', 'right', 'zigzag', 'sine', 'chase', 'flee', 'wander', 'bounce', 'aim', 'hover'];
  const FROMS = ['top', 'bottom', 'left', 'right', 'edges', 'random', 'ground', 'air', 'lane', 'column', 'hero', 'platform'];
  const EFFECTS = ['score', 'damage', 'heal', 'remove_a', 'remove_b', 'hit_b', 'shield', 'slow', 'fast', 'magnet', 'double', 'freeze', 'grow', 'shrink',
    'clear', 'teleport_a', 'teleport_b', 'spawn', 'bounce_a', 'jump_a', 'level_up', 'win', 'lose', 'burst', 'shake', 'sound', 'text', 'combo_reset', 'power'];
  const ROLE_BAD = { bad: 1, bad2: 1, boss: 1, eshot: 1 };
  const GameKitClamp = (v, a, b) => (v < a ? a : v > b ? b : v);

  class World {
    constructor(spec, o = {}) {
      this.s = spec; this.headless = !!o.headless;
      this.seed = o.seed == null ? (Math.random() * 1e9) | 0 : o.seed;
      this.reset();
    }
    reset() {
      const s = this.s;
      this.rnd = rng(this.seed);
      this.t = 0; this.score = 0; this.lives = s.lives || 3; this.level = 1; this.combo = 0; this.maxCombo = 0; this.caught = 0; this.missed = 0;
      this.ents = []; this.fx = []; this.st = {}; this.over = null; this.camY = 0; this.climb = 0; this.boss = null; this.bossT = 0;
      this.spT = (s.spawns || []).map(sp => (sp.startAfter || 0) + sp.every * 0.4);
      this.evT = (s.events || []).map(e => e.every || 0); this.done = {};
      this.cd = {}; this.powT = s.powerEvery || 0; this.lane = 1; this.prevIn = {}; this.jumps = 0; this.platTop = H;
      this.G = (s.world && s.world.gravity) || 1;
      this.floor = this.G > 0 ? H - 64 : 64;
      const c = s.control;
      if (c === 'tap') this.hero = null;
      else {
        const r = R0 * ((s.hero && s.hero.size) || 1.15);
        const pos = { horizontal: [W / 2, H - 58], lanes: [W / 2, H - 76], runner: [80, this.floor - this.G * r], flappy: [92, H / 2], jumper: [W / 2, H - 150], free: [W / 2, H / 2], topdown: [W / 2, H / 2] }[c] || [W / 2, H / 2];
        this.hero = { tag: 'hero', x: pos[0], y: pos[1], vx: 0, vy: 0, r, t: 0, inv: 0, face: 1, onGround: c === 'runner' };
      }
      if (c === 'jumper') this.initPlatforms();
      if (c === 'topdown') this.fillArena(true);
    }
    // ---------- служебное ----------
    thing(tag) { return (this.s.things && this.s.things[tag]) || {}; }
    pace() { return (this.s.pace || 1) * (1 + 0.08 * (this.level - 1)) * Math.min(2, 1 + this.t / (this.s.ramp || 110)); }
    spd(e) { const slow = this.st.slow && ROLE_BAD[e.tag] ? 0.45 : 1; return 105 * (e.sp || 1) * (0.6 + 0.4 * this.pace()) * slow; }
    emit(f) { if (!this.headless) this.fx.push(f); }
    add(tag, x, y, extra) {
      const d = this.thing(tag);
      const e = Object.assign({ tag, x, y, vx: 0, vy: 0, r: R0 * (d.size || 1), t: 0, life: d.life || 0, hp: d.hp || 1, maxHp: d.hp || 1, move: d.move || 'still', sp: d.speed || 1,
        emoji: d.emoji, ph: this.rnd() * 6.28, x0: x, dir: this.rnd() < 0.5 ? -1 : 1 }, extra || {});
      if (e.move === 'aim' && this.hero) { const dx = this.hero.x - x, dy = this.hero.y - y, l = Math.hypot(dx, dy) || 1; e.ax = dx / l; e.ay = dy / l; }
      if (e.move === 'bounce' || e.move === 'wander') { const a = this.rnd() * 6.28; e.ax = Math.cos(a); e.ay = Math.sin(a); }
      this.ents.push(e);
      return e;
    }
    count(tag) { let n = 0; for (const e of this.ents) if (e.tag === tag && !e.dead) n++; return n; }
    safeSpot(minD = 110) {
      for (let i = 0; i < 30; i++) {
        const x = 30 + this.rnd() * (W - 60), y = this.camY + 70 + this.rnd() * (H - 140);
        if (!this.hero || Math.hypot(x - this.hero.x, y - this.hero.y) > minD) return [x, y];
      }
      return [30 + this.rnd() * (W - 60), this.camY + 70 + this.rnd() * (H - 140)];
    }
    // ---------- появление предметов ----------
    spawnOne(sp) {
      const d = this.thing(sp.tag), r = R0 * (d.size || 1), from = sp.from || 'top';
      const rx = () => r + 6 + this.rnd() * (W - 2 * r - 12);
      if (from === 'top') return this.add(sp.tag, rx(), this.camY - r - 4);
      if (from === 'bottom') return this.add(sp.tag, rx(), this.camY + H + r);
      if (from === 'left') return this.add(sp.tag, -r, this.camY + 60 + this.rnd() * (H - 120));
      if (from === 'right') return this.add(sp.tag, W + r, this.camY + 60 + this.rnd() * (H - 120));
      if (from === 'edges') {
        const k = Math.floor(this.rnd() * 4), p = this.rnd();
        const xy = k === 0 ? [p * W, -r] : k === 1 ? [W + r, p * H] : k === 2 ? [p * W, H + r] : [-r, p * H];
        return this.add(sp.tag, xy[0], xy[1]);
      }
      if (from === 'random' || from === 'platform') { const [x, y] = this.safeSpot(from === 'random' && this.s.control === 'tap' ? 0 : 90); return this.add(sp.tag, x, y); }
      if (from === 'hero' && this.hero) return this.add(sp.tag, this.hero.x, this.hero.y);
      if (from === 'ground') return this.add(sp.tag, W + r, this.floor - this.G * r);
      if (from === 'air') return this.add(sp.tag, W + r, this.floor - this.G * (r + 55 + this.rnd() * 85));
      if (from === 'lane') { const lx = [W * 0.2, W * 0.5, W * 0.8][Math.floor(this.rnd() * 3)]; return this.add(sp.tag, lx, -r); }
      if (from === 'column') {
        const gap = sp.gap || 150, gy = 70 + this.rnd() * (H - 140 - gap), step = r * 1.9, x = W + r + 4;
        for (let y = r; y < gy - r * 0.6; y += step) this.add(sp.tag, x, y, { col: 1 });
        for (let y = H - r; y > gy + gap + r * 0.6; y -= step) this.add(sp.tag, x, y, { col: 1 });
        this.add('gate', x, gy + gap / 2, { r: 8, move: 'left', sp: d.speed || 1.4, hidden: true });
        if (sp.withGood && this.thing(sp.withGood).emoji && this.rnd() < 0.6) this.add(sp.withGood, x + 4, gy + gap / 2, { move: 'left', sp: d.speed || 1.4 });
        return null;
      }
      return this.add(sp.tag, rx(), -r);
    }
    // ---------- эффекты ----------
    addScore(n, x, y) {
      let k = this.st.double ? 2 : 1;
      if (this.s.fx && this.s.fx.combo && n > 0) { this.combo++; this.maxCombo = Math.max(this.maxCombo, this.combo); k *= 1 + Math.min(4, Math.floor(this.combo / 6)); if (this.combo % 6 === 0) this.emit({ k: 'text', x, y: y - 26, s: 'Комбо ×' + (1 + Math.min(4, Math.floor(this.combo / 6))) + '!' }); }
      this.score += Math.round(n * k);
      if (n > 0) this.emit({ k: 'text', x, y, s: '+' + Math.round(n * k) });
    }
    damage(n) {
      const h = this.hero;
      if (h && (h.inv > 0 || this.st.shield)) { if (this.st.shield) this.emit({ k: 'sound', s: 'block' }); return false; }
      this.lives -= n; this.combo = 0;
      if (h) h.inv = 1.3;
      this.emit({ k: 'shake', a: 9 }); this.emit({ k: 'sound', s: 'hit' });
      if (this.lives <= 0) this.end(false);
      return true;
    }
    end(win, text) { if (!this.over) { this.over = { win, text }; this.emit({ k: 'sound', s: win ? 'win' : 'lose' }); } }
    levelUp() {
      this.level++;
      this.emit({ k: 'banner', s: 'Уровень ' + this.level + '!' }); this.emit({ k: 'sound', s: 'level' });
      const g = this.s.goal && this.s.goal.level;
      const b = this.s.boss;
      if (b && b.on && this.level % (b.every || 3) === 0) this.startBoss();
      else if (g && this.level > g) this.end(true, 'Ты прошёл все уровни! 🏆');
      if (this.s.control === 'topdown') this.fillArena(false);
    }
    startBoss() {
      if (this.boss && !this.boss.dead) return;
      const b = this.s.boss, fight = b.mode === 'fight';
      this.boss = this.add('boss', W / 2, this.camY - 50, { r: R0 * 2.6, hp: Math.round((b.hp || 12) * (1 + 0.35 * (this.level / (b.every || 3) - 1))), move: fight ? 'hover' : 'chase', sp: fight ? 1 : 0.42, emoji: b.emoji });
      this.boss.maxHp = this.boss.hp;
      this.bossT = fight ? 0 : 16;
      this.emit({ k: 'banner', s: fight ? 'Босс! Победи его!' : 'Босс! Продержись!' }); this.emit({ k: 'sound', s: 'boss' });
    }
    bossDone(won) {
      if (!this.boss) return;
      this.emit({ k: 'burst', x: this.boss.x, y: this.boss.y, n: 40, big: 1 });
      this.boss.dead = true; this.boss = null;
      this.addScore(25 + 5 * this.level, W / 2, this.camY + H / 2);
      this.emit({ k: 'banner', s: won ? 'Босс побеждён!' : 'Ты продержался!' }); this.emit({ k: 'sound', s: 'win' });
      const g = this.s.goal && this.s.goal.level;
      if (g && this.level >= g) this.end(true, 'Ты победил финального босса! 🏆');
    }
    givePower(type, x, y) {
      const p = POWER[type]; if (!p) return;
      if (type === 'heart') this.lives = Math.min(6, this.lives + 1);
      else if (type === 'bomb') this.clearBad();
      else this.st[type] = p.time;
      this.emit({ k: 'text', x, y: y - 20, s: p.emoji + ' ' + p.name }); this.emit({ k: 'sound', s: 'power' });
    }
    clearBad() {
      for (const e of this.ents) if (!e.dead && ROLE_BAD[e.tag] && e.tag !== 'boss') { e.dead = true; this.emit({ k: 'burst', x: e.x, y: e.y }); }
      this.emit({ k: 'shake', a: 6 });
    }
    apply(list, a, b) {
      for (const raw of list || []) {
        const i = String(raw).indexOf(':'), name = i < 0 ? raw : raw.slice(0, i), arg = i < 0 ? '' : raw.slice(i + 1), n = parseFloat(arg) || 0;
        const x = b ? b.x : a ? a.x : W / 2, y = b ? b.y : a ? a.y : H / 2;
        switch (name) {
          case 'score': this.addScore(n || 1, x, y); if (b && b.tag !== 'gate') this.caught++; break;
          case 'damage': this.damage(n || 1); break;
          case 'heal': this.lives = Math.min(6, this.lives + (n || 1)); this.emit({ k: 'text', x, y, s: '❤️' }); break;
          case 'remove_a': if (a && a !== this.hero) a.dead = true; break;
          case 'remove_b': if (b && b !== this.hero) b.dead = true; break;
          case 'hit_b':
            if (b) { b.hp -= n || 1; b.flash = 0.12; if (b.hp <= 0 && !b.dead) { b.dead = true; this.emit({ k: 'burst', x: b.x, y: b.y }); if (b === this.boss) this.bossDone(true); else this.addScore(this.thing(b.tag).points || 1, b.x, b.y); } }
            break;
          case 'shield': case 'slow': case 'fast': case 'magnet': case 'double': case 'freeze': case 'grow': case 'shrink':
            this.st[name] = n || 5; break;
          case 'power': this.givePower(b && b.ptype || arg, x, y); break;
          case 'clear': for (const e of this.ents) if (!e.dead && e.tag === arg) { e.dead = true; this.emit({ k: 'burst', x: e.x, y: e.y }); } break;
          case 'teleport_a': if (a) { const p = this.safeSpot(); a.x = p[0]; a.y = p[1]; this.emit({ k: 'burst', x: a.x, y: a.y }); } break;
          case 'teleport_b': if (b) { const p = this.safeSpot(); b.x = p[0]; b.y = p[1]; } break;
          case 'spawn': if (this.s.things && this.s.things[arg]) this.add(arg, x, y); break;
          case 'bounce_a': if (a) { a.vy = -Math.abs(a.vy || 300); a.ay = -Math.abs(a.ay || 1); } break;
          case 'jump_a': if (a) a.vy = -620 * this.G; break;
          case 'level_up': this.levelUp(); break;
          case 'win': this.end(true, arg || 'Победа! 🏆'); break;
          case 'lose': this.end(false, arg || ''); break;
          case 'burst': this.emit({ k: 'burst', x, y, c: arg }); break;
          case 'shake': this.emit({ k: 'shake', a: n || 6 }); break;
          case 'sound': this.emit({ k: 'sound', s: arg || 'collect' }); break;
          case 'text': this.emit({ k: 'text', x, y, s: arg }); break;
          case 'combo_reset': this.combo = 0; break;
        }
      }
    }
    // ---------- шаг игры ----------
    update(dt, inp) {
      if (this.over) return;
      dt = Math.min(dt, 0.05);
      inp = inp || {};
      const s = this.s;
      this.t += dt;
      for (const k in this.st) { this.st[k] -= dt; if (this.st[k] <= 0) delete this.st[k]; }
      if (this.hero) { this.hero.t += dt; if (this.hero.inv > 0) this.hero.inv -= dt; }
      this.control(dt, inp);
      this.abilities(dt, inp);
      // правила появления
      const rate = this.pace() * (this.boss ? 0.45 : 1);
      (s.spawns || []).forEach((sp, i) => {
        if (sp.from === 'column' && this.s.control !== 'flappy') return;
        this.spT[i] -= dt * (sp.scale === false ? 1 : rate);
        if (this.spT[i] <= 0) {
          this.spT[i] += sp.every * (0.75 + this.rnd() * 0.5);
          if (sp.max && this.count(sp.tag) >= sp.max) return;
          if (sp.chance && this.rnd() > sp.chance) return;
          for (let k = 0; k < (sp.count || 1); k++) this.spawnOne(sp);
        }
      });
      if (s.powers && s.powers.length && s.powerEvery) {
        this.powT -= dt;
        if (this.powT <= 0) {
          this.powT = s.powerEvery * (0.8 + this.rnd() * 0.4);
          const type = s.powers[Math.floor(this.rnd() * s.powers.length)];
          const from = { horizontal: 'top', lanes: 'lane', runner: 'air', flappy: 'right', jumper: 'random', tap: 'random' }[s.control] || 'random';
          const e = this.spawnOne({ tag: 'power', from });
          if (e) { e.ptype = type; e.emoji = POWER[type].emoji; e.move = { horizontal: 'fall', lanes: 'fall', runner: 'left', flappy: 'left' }[s.control] || 'still'; e.life = e.move === 'still' ? 7 : 0; e.sp = s.control === 'runner' || s.control === 'flappy' ? 1.5 : s.control === 'lanes' ? 2 : 0.9; }
        }
      }
      // события
      (s.events || []).forEach((ev, i) => {
        if (ev.every) { this.evT[i] -= dt; if (this.evT[i] <= 0) { this.evT[i] += ev.every; this.apply(ev.do); } return; }
        if (ev.once !== false && this.done[i]) return;
        const hit = (ev.at_score != null && this.score >= ev.at_score) || (ev.at_time != null && this.t >= ev.at_time) || (ev.at_level != null && this.level >= ev.at_level) ||
          (ev.none_left && this.count(ev.none_left) === 0 && this.t > 0.5);
        if (hit) { this.done[i] = true; this.apply(ev.do); }
      });
      // уровни
      if (s.levelEvery && !this.boss && this.score >= this.level * s.levelEvery * (1 + 0.15 * (this.level - 1))) this.levelUp();
      if (this.boss && this.bossT > 0) { this.bossT -= dt; if (this.bossT <= 0) this.bossDone(false); }
      if (this.boss && this.s.boss && this.s.boss.mode === 'fight') {
        this.boss.shootT = (this.boss.shootT || 1.2) - dt;
        if (this.boss.shootT <= 0 && this.s.things.eshot) { this.boss.shootT = Math.max(0.5, 1.3 - this.level * 0.04); this.add('eshot', this.boss.x, this.boss.y + this.boss.r * 0.6, { move: 'aim' }); }
      } else if (this.boss) {
        this.boss.dropT = (this.boss.dropT || 1) - dt;
        if (this.boss.dropT <= 0 && this.s.things.bad) { this.boss.dropT = 1.4; const e = this.add('bad', this.boss.x, this.boss.y, { move: this.s.control === 'horizontal' ? 'fall' : 'aim' }); e.sp = (e.sp || 1) * 1.1; }
      }
      if (s.timeLimit && this.t >= s.timeLimit) this.end(true, 'Время вышло! ⏱');
      this.moveAll(dt);
      this.collide(inp);
      if (s.control === 'topdown' && this.thing('good').emoji && this.t > 0.5 && !this.over && this.count('good') === 0) this.levelUp();
      // уборка
      const top = this.camY - 110, bot = this.camY + H + 90;
      for (const e of this.ents) {
        e.t += dt;
        if (e.flash) e.flash -= dt;
        if (e.life && e.t > e.life) { e.dead = true; if (s.control === 'tap' && this.thing(e.tag).role === 'good') { this.combo = 0; this.missed++; } }
        if (s.control === 'jumper' ? e.y > bot : (e.y > bot || e.y < top || e.x < -90 || e.x > W + 90)) {
          if (!e.dead && this.thing(e.tag).role === 'good' && !e.col) { this.missed++; if (s.control === 'horizontal' || s.control === 'lanes') this.combo = 0; }
          e.dead = true;
        }
      }
      if (this.ents.length > 40 && this.ents.some(e => e.dead)) this.ents = this.ents.filter(e => !e.dead);
    }
    moveAll(dt) {
      const h = this.hero, frozen = this.st.freeze;
      for (const e of this.ents) {
        if (e.dead || e.tag === 'platform') continue;
        if (frozen && ROLE_BAD[e.tag] && e.tag !== 'boss') continue;
        const v = this.spd(e);
        switch (e.move) {
          case 'fall': e.vx = 0; e.vy = v; break;
          case 'rise': e.vx = 0; e.vy = -v; break;
          case 'left': e.vx = -v * 1.25; e.vy = 0; break;
          case 'right': e.vx = v; e.vy = 0; break;
          case 'zigzag': e.vy = v * 0.85; e.vx = e.dir * v * 0.7; if ((e.x < e.r && e.dir < 0) || (e.x > W - e.r && e.dir > 0) || (e.t % 1.1 < dt)) e.dir = -e.dir; break;
          case 'sine': e.vy = v * 0.9; e.vx = Math.cos(e.t * 2.4 + e.ph) * 95; break;
          case 'chase': case 'flee': if (h) { const dx = h.x - e.x, dy = h.y - e.y, l = Math.hypot(dx, dy) || 1, k = e.move === 'chase' ? 1 : -1; e.vx = k * dx / l * v; e.vy = k * dy / l * v; } break;
          case 'aim': e.vx = (e.ax || 0) * v * 1.25; e.vy = (e.ay != null ? e.ay : 1) * v * 1.25; break;
          case 'wander':
            e.wt = (e.wt || 0) - dt; if (e.wt <= 0) { e.wt = 1 + this.rnd() * 1.4; const a = this.rnd() * 6.28; e.ax = Math.cos(a); e.ay = Math.sin(a); }
          // falls through
          case 'bounce':
            e.vx = (e.ax || 0) * v * 0.9; e.vy = (e.ay || 0) * v * 0.9;
            if ((e.x < e.r && e.ax < 0) || (e.x > W - e.r && e.ax > 0)) e.ax = -e.ax;
            if ((e.y < this.camY + e.r + 30 && e.ay < 0) || (e.y > this.camY + H - e.r && e.ay > 0)) e.ay = -e.ay;
            break;
          case 'hover': e.vx = 0; e.vy = 0; e.x = W / 2 + Math.sin(e.t * 0.9) * W * 0.32; e.y += ((this.camY + 92) - e.y) * Math.min(1, dt * 2); break;
          default: e.vx = 0; e.vy = 0;
        }
        if (this.st.magnet && h && this.thing(e.tag).role === 'good') {
          const dx = h.x - e.x, dy = h.y - e.y, l = Math.hypot(dx, dy);
          if (l < 170 && l > 1) { e.vx += dx / l * 260; e.vy += dy / l * 260; }
        }
        e.x += e.vx * dt; e.y += e.vy * dt;
        if (this.s.world && this.s.world.wrap && (e.move === 'bounce' || e.move === 'wander' || e.move === 'chase')) { if (e.x < -e.r) e.x = W + e.r; if (e.x > W + e.r) e.x = -e.r; }
      }
    }
    // ---------- управление героем ----------
    control(dt, inp) {
      const h = this.hero, c = this.s.control, wrap = this.s.world && this.s.world.wrap;
      const fast = this.st.fast ? 1.45 : 1;
      if (h) {
        const sz = this.st.grow ? 1.45 : this.st.shrink ? 0.6 : 1;
        h.r = R0 * ((this.s.hero && this.s.hero.size) || 1.15) * sz;
      }
      const pressed = k => inp[k] && !this.prevIn[k];
      if (c === 'horizontal' || c === 'jumper') {
        let vx = 0;
        if (inp.pointer && inp.pointer.active) { const dx = inp.pointer.x - h.x; vx = clamp(dx * 9, -420, 420); }
        else vx = ((inp.right ? 1 : 0) - (inp.left ? 1 : 0)) * 270;
        h.vx = vx * fast; h.x += h.vx * dt;
        if (Math.abs(h.vx) > 20) h.face = h.vx > 0 ? 1 : -1;
        if (c === 'jumper' || wrap) { if (h.x < -h.r) h.x = W + h.r; if (h.x > W + h.r) h.x = -h.r; }
        else h.x = clamp(h.x, h.r, W - h.r);
        if (c === 'jumper') this.jumperStep(dt);
      } else if (c === 'free' || c === 'topdown') {
        let vx = 0, vy = 0;
        if (inp.pointer && inp.pointer.active) { const dx = inp.pointer.x - h.x, dy = inp.pointer.y - h.y, l = Math.hypot(dx, dy); if (l > 4) { const s = Math.min(290, l * 7); vx = dx / l * s; vy = dy / l * s; } }
        else { vx = ((inp.right ? 1 : 0) - (inp.left ? 1 : 0)) * 250; vy = ((inp.down ? 1 : 0) - (inp.up ? 1 : 0)) * 250; if (vx && vy) { vx *= 0.71; vy *= 0.71; } }
        h.vx = vx * fast; h.vy = vy * fast; h.x += h.vx * dt; h.y += h.vy * dt;
        if (Math.abs(h.vx) > 20) h.face = h.vx > 0 ? 1 : -1;
        if (wrap) { if (h.x < -h.r) h.x = W + h.r; if (h.x > W + h.r) h.x = -h.r; if (h.y < 40 - h.r) h.y = H + h.r; if (h.y > H + h.r) h.y = 40 - h.r; }
        else { h.x = clamp(h.x, h.r, W - h.r); h.y = clamp(h.y, 44 + h.r, H - h.r); }
      } else if (c === 'runner') {
        const jumpBtn = pressed('action') || pressed('up') || (inp.tap && !this.prevIn.tap);
        const maxJ = (this.s.world && this.s.world.jumps) || 1;
        if (jumpBtn && (h.onGround || this.jumps < maxJ)) { h.vy = -640 * this.G; h.onGround = false; this.jumps++; this.emit({ k: 'sound', s: 'jump' }); }
        h.vy += 1900 * this.G * dt; h.y += h.vy * dt;
        const rest = this.floor - this.G * h.r;
        if ((this.G > 0 && h.y >= rest) || (this.G < 0 && h.y <= rest)) { h.y = rest; h.vy = 0; h.onGround = true; this.jumps = 0; }
      } else if (c === 'flappy') {
        if (pressed('action') || pressed('up') || (inp.tap && !this.prevIn.tap)) { h.vy = -420 * this.G; this.emit({ k: 'sound', s: 'jump' }); }
        h.vy += 1450 * this.G * dt; h.y += h.vy * dt;
        if (h.y < h.r + 2 || h.y > H - h.r - 2) { h.y = clamp(h.y, h.r + 2, H - h.r - 2); h.vy = 0; if (this.damage(1)) { h.y = H / 2; } }
      } else if (c === 'lanes') {
        if (pressed('left')) this.lane = Math.max(0, this.lane - 1);
        if (pressed('right')) this.lane = Math.min(2, this.lane + 1);
        if (inp.pointer && inp.pointer.active) this.lane = inp.pointer.x < W / 3 ? 0 : inp.pointer.x > W * 2 / 3 ? 2 : 1;
        const tx = [W * 0.2, W * 0.5, W * 0.8][this.lane];
        h.x += (tx - h.x) * Math.min(1, dt * 14 * fast);
      }
      this.prevIn = { action: inp.action, up: inp.up, left: inp.left, right: inp.right, down: inp.down, tap: inp.tap };
    }
    abilities(dt, inp) {
      for (const ab of this.s.abilities || []) {
        const key = ab.button || 'action';
        this.cd[ab.do + key] = (this.cd[ab.do + key] || 0) - dt;
        const want = ab.auto || inp[key] || (key === 'action' && inp.tap && this.s.control !== 'runner' && this.s.control !== 'flappy' && !ab.noTap);
        if (!want || this.cd[ab.do + key] > 0 || !this.hero) continue;
        if (ab.do === 'jump' && this.s.control === 'runner') continue;
        this.cd[ab.do + key] = (ab.cooldown || 0.3) / (this.st.fast ? 1.4 : 1);
        const h = this.hero;
        if (ab.do === 'shoot') {
          const tag = ab.spawn || 'shot';
          if (!this.thing(tag).emoji && tag !== 'shot') continue;
          const right = this.s.control === 'runner' || this.s.control === 'flappy';
          this.add(tag, h.x + (right ? h.r : 0), h.y - (right ? 0 : h.r), { move: right ? 'right' : 'rise', sp: 4.2 });
          if (this.st.double && !right) { this.add(tag, h.x - 12, h.y - h.r, { move: 'rise', sp: 4.2 }); this.add(tag, h.x + 12, h.y - h.r, { move: 'rise', sp: 4.2 }); }
          this.emit({ k: 'sound', s: 'shoot' });
        } else if (ab.do === 'place' && ab.spawn) { this.add(ab.spawn, h.x, h.y + (this.s.control === 'horizontal' ? -h.r : 0)); this.emit({ k: 'sound', s: 'power' }); }
        else if (ab.do === 'dash') { h.x = clamp(h.x + h.face * 90, h.r, W - h.r); h.inv = Math.max(h.inv, 0.35); this.emit({ k: 'burst', x: h.x, y: h.y }); }
        else if (ab.do === 'bomb') this.clearBad();
        else if (ab.do === 'shield') this.st.shield = 2.5;
        else if (ab.do === 'jump' && this.s.control === 'jumper') h.vy = -720;
      }
    }
    // ---------- «прыгалка» вверх ----------
    initPlatforms() {
      this.add('platform', W / 2, H - 100, { w: 90 });
      this.platTop = H - 100;
      while (this.platTop > -H) this.nextPlatform();
    }
    nextPlatform() {
      const gap = 62 + this.rnd() * 26 + Math.min(30, this.level * 3);
      this.platTop -= gap;
      const x = 50 + this.rnd() * (W - 100);
      this.add('platform', x, this.platTop, { w: 64 + this.rnd() * 24, moving: this.level > 2 && this.rnd() < 0.25 });
      if (this.thing('good').emoji && this.rnd() < 0.35) this.add('good', x, this.platTop - 34);
      if (this.thing('bad').emoji && this.t > 3 && this.rnd() < 0.08 + this.level * 0.02) this.add('bad', 40 + this.rnd() * (W - 80), this.platTop - 50, { move: 'wander', sp: 0.5 });
    }
    jumperStep(dt) {
      const h = this.hero;
      h.vy += 1500 * dt; h.y += h.vy * dt;
      if (h.vy > 0) for (const p of this.ents) {
        if (p.tag !== 'platform' || p.dead) continue;
        if (Math.abs(h.x - p.x) < p.w / 2 + h.r * 0.5 && h.y + h.r >= p.y - 4 && h.y + h.r <= p.y + 10 + h.vy * dt) { h.vy = -720; this.emit({ k: 'sound', s: 'jump' }); break; }
      }
      for (const p of this.ents) if (p.tag === 'platform' && p.moving) { p.x += Math.sin(this.t * 1.6 + p.ph) * 60 * dt; }
      const line = this.camY + H * 0.42;
      if (h.y < line) { this.camY -= line - h.y; }
      const climbed = Math.floor((H - 150 - h.y) / 10);
      if (climbed > this.climb) { this.addScoreQuiet(climbed - this.climb); this.climb = climbed; }
      while (this.platTop > this.camY - 120) this.nextPlatform();
      if (h.y - h.r > this.camY + H) {
        if (this.damage(1) || this.lives > 0) {
          let best = null; for (const p of this.ents) if (p.tag === 'platform' && p.y > this.camY + H * 0.5 && p.y < this.camY + H - 20 && (!best || p.y < best.y)) best = p;
          if (best) { h.x = best.x; h.y = best.y - h.r - 4; } else { h.y = this.camY + H - 60; }
          h.vy = -720; h.inv = Math.max(h.inv, 1.5);
          if (!best) this.add('platform', h.x, h.y + h.r + 6, { w: 90 });
        }
      }
    }
    addScoreQuiet(n) { this.score += n * (this.st.double ? 2 : 1); }
    arena() { return 6 + this.level * 2; }
    fillArena(first) {
      if (!this.thing('good').emoji) return;
      for (let i = 0; i < this.arena(); i++) { const p = this.safeSpot(70); this.add('good', p[0], p[1]); }
      const nb = Math.min(6, 1 + this.level), have = this.count('bad');
      if (this.thing('bad').emoji) for (let i = have; i < nb; i++) { const p = this.safeSpot(170); this.add('bad', p[0], p[1]); }
      if (!first) { this.emit({ k: 'text', x: W / 2, y: H / 2, s: 'Новые ' + (this.thing('good').name || 'предметы') + '!' }); }
    }
    // ---------- столкновения ----------
    collide(inp) {
      const h = this.hero, taps = (inp.taps || []).map(p => ({ x: p.x, y: p.y + this.camY, r: 24, tap: 1 }));
      for (const rule of this.s.touch || []) {
        const A = rule.a === 'hero' ? (h ? [h] : []) : rule.a === 'tap' ? taps.filter(p => !p.used) : this.ents.filter(e => !e.dead && e.tag === rule.a);
        if (!A.length) continue;
        const bt = Array.isArray(rule.b) ? rule.b : [rule.b];
        for (const a of A) {
          for (const b of this.ents) {
            if (b.dead || b === a || bt.indexOf(b.tag) < 0) continue;
            const k = a === h && ROLE_BAD[b.tag] ? 0.72 : 0.9;
            const dx = a.x - b.x, dy = a.y - b.y, rr = (a.r + b.r) * k;
            if (dx * dx + dy * dy < rr * rr) {
              this.apply(rule.do, a, b);
              if (a.tap) { a.used = true; break; }
              if (a.dead) break;
            }
          }
        }
      }
      if (h) for (const b of this.ents) {
        if (b.dead || b.tag !== 'power') continue;
        const dx = h.x - b.x, dy = h.y - b.y, rr = (h.r + b.r) * 0.95;
        if (dx * dx + dy * dy < rr * rr) { b.dead = true; this.givePower(b.ptype, b.x, b.y); this.emit({ k: 'burst', x: b.x, y: b.y }); }
      }
      if (!h) for (const p of taps) for (const b of this.ents) {
        if (p.used || b.dead || b.tag !== 'power') continue;
        if (Math.hypot(p.x - b.x, p.y - b.y) < b.r + 24) { b.dead = true; p.used = true; this.givePower(b.ptype, b.x, b.y); }
      }
    }
  }

  // ---------- робот-игрок для проверки игр ----------
  function botInput(w, mem) {
    const h = w.hero, s = w.s, c = s.control, inp = { left: false, right: false, up: false, down: false, action: false, tap: false, pointer: null, taps: [] };
    const role = e => (w.thing(e.tag).role || (e.tag === 'power' ? 'good' : ROLE_BAD[e.tag] ? 'bad' : ''));
    mem.react = (mem.react || 0) - 1 / 30;
    if (c === 'horizontal' && (s.abilities || []).some(a => a.do === 'shoot')) {
      let target = W / 2, low = -1e9;
      for (const e of w.ents) if (!e.dead && (e.tag === 'bad' || e.tag === 'bad2' || e.tag === 'boss') && e.y < h.y - 90 && e.y > low) { low = e.y; target = e.x; }
      for (const e of w.ents) if (!e.dead && role(e) === 'bad' && e.y > h.y - 120 && e.y < h.y + 10 && Math.abs(e.x - h.x) < 50) target = e.x > h.x ? e.x - 90 : e.x + 90;
      if (mem.react <= 0) { mem.react = 0.12; mem.tx = target + (w.rnd() - 0.5) * 14; }
      inp.pointer = { active: true, x: GameKitClamp(mem.tx, h.r, W - h.r), y: h.y };
      inp.action = true;
    } else if (c === 'horizontal') {
      let target = W / 2, best = 1e9;
      for (const e of w.ents) if (!e.dead && role(e) === 'good' && e.y < h.y && e.y > h.y - 340) { const tt = (h.y - e.y) / Math.max(40, e.vy || 100), need = Math.abs(e.x - h.x) / 300; if (need < tt + 0.15 && tt < best) { best = tt; target = e.x; } }
      for (const e of w.ents) if (!e.dead && role(e) === 'bad' && e.y < h.y + 10 && e.y > h.y - 190) { const nx = e.x + (e.vx || 0) * (h.y - e.y) / Math.max(60, e.vy || 100); if (Math.abs(nx - target) < 50 || Math.abs(nx - h.x) < 50) target = nx > h.x ? Math.max(h.r, nx - 90) : Math.min(W - h.r, nx + 90); }
      // не идти сквозь то, что пролетает на уровне героя
      for (const e of w.ents) if (!e.dead && role(e) === 'bad' && e.y > h.y - 70 && e.y < h.y + 45) { const lo = Math.min(h.x, target) - 40, hi = Math.max(h.x, target) + 40; if (e.x > lo && e.x < hi) target = Math.abs(e.x - h.x) < 45 ? (e.x > h.x ? e.x - 75 : e.x + 75) : h.x; }
      if (mem.react <= 0) { mem.react = 0.12; mem.tx = target + (w.rnd() - 0.5) * 18; }
      inp.pointer = { active: true, x: mem.tx == null ? target : mem.tx, y: h.y };
      inp.action = true;
    } else if (c === 'free' || c === 'topdown') {
      let fx = 0, fy = 0;
      for (const e of w.ents) {
        if (e.dead) continue;
        const dx = e.x - h.x, dy = e.y - h.y, d = Math.hypot(dx, dy) || 1, r = role(e);
        if (r === 'good') { fx += dx / d / (d * 0.02 + 1); fy += dy / d / (d * 0.02 + 1); }
        else if (r === 'bad' && d < 120) { fx -= dx / d * 4 * (120 - d) / 120; fy -= dy / d * 4 * (120 - d) / 120; }
      }
      fx += (W / 2 - h.x) * 0.0015; fy += (H / 2 - h.y) * 0.0015;
      if (mem.react <= 0) { mem.react = 0.1; mem.v = [fx, fy]; }
      const v = mem.v || [0, 0], l = Math.hypot(v[0], v[1]) || 1;
      inp.pointer = { active: true, x: h.x + v[0] / l * 60, y: h.y + v[1] / l * 60 };
    } else if (c === 'runner') {
      let air = false;
      for (const e of w.ents) if (!e.dead && role(e) === 'bad' && e.x > h.x - 20 && e.x - h.x < 170 && Math.abs(e.y - h.y) >= 50) air = true;
      for (const e of w.ents) if (!e.dead && role(e) === 'bad' && e.x > h.x && e.x - h.x < 70 + w.pace() * 30 && Math.abs(e.y - h.y) < 50) inp.action = true;
      if (air && h.onGround && !inp.action) inp.action = false;
      if (inp.action && w.rnd() < 0.08) inp.action = false;
    } else if (c === 'flappy') {
      let gate = null;
      for (const e of w.ents) if (e.tag === 'gate' && !e.dead && e.x > h.x - 20 && (!gate || e.x < gate.x)) gate = e;
      const ty = gate ? gate.y + 12 : H / 2;
      if (h.y > ty && h.vy > -60) inp.action = !mem.flap;
      mem.flap = inp.action;
    } else if (c === 'jumper') {
      let best = null;
      for (const p of w.ents) if (p.tag === 'platform' && !p.dead && p.y < h.y + 40 && p.y > h.y - 160 && (!best || Math.abs(p.x - h.x) < Math.abs(best.x - h.x))) best = p;
      if (h.vy > 0) { best = null; for (const p of w.ents) if (p.tag === 'platform' && p.y > h.y && p.y < h.y + 220 && (!best || p.y < best.y)) best = p; }
      inp.pointer = { active: true, x: best ? best.x : W / 2, y: h.y };
    } else if (c === 'lanes') {
      const lx = [W * 0.2, W * 0.5, W * 0.8], danger = [0, 0, 0];
      for (const e of w.ents) if (!e.dead && e.y < h.y + 20 && e.y > h.y - 260) { const ln = lx.reduce((bi, x, i) => Math.abs(x - e.x) < Math.abs(lx[bi] - e.x) ? i : bi, 0), r = role(e); danger[ln] += r === 'bad' ? 10 + (260 - (h.y - e.y)) / 10 : r === 'good' ? -3 : 0; }
      let bestL = w.lane; for (let i = 0; i < 3; i++) if (danger[i] + Math.abs(i - w.lane) * 1.5 < danger[bestL] + (bestL === w.lane ? 0 : 1.5)) bestL = i;
      if (mem.react <= 0) { mem.react = 0.15; mem.lane = bestL; }
      inp.pointer = { active: true, x: lx[mem.lane == null ? 1 : mem.lane], y: h.y };
    } else if (c === 'tap') {
      mem.seen = mem.seen || new Map();
      for (const e of w.ents) if (!e.dead && (role(e) === 'good' || e.tag === 'power')) { if (!mem.seen.has(e)) mem.seen.set(e, w.t + 0.4 + w.rnd() * 0.5); }
      for (const [e, at] of mem.seen) { if (e.dead) { mem.seen.delete(e); continue; } if (w.t >= at && w.rnd() < 0.85) { inp.taps.push({ x: e.x + (w.rnd() - 0.5) * 16, y: e.y - w.camY }); mem.seen.delete(e); break; } }
    }
    return inp;
  }
  // прогон игры роботом без экрана
  function playtest(spec, o = {}) {
    const runs = [], seconds = o.seconds || 150, seeds = o.seeds || [11, 22, 33];
    for (const seed of seeds) {
      const w = new World(spec, { headless: true, seed }), mem = {};
      const dt = 1 / 30;
      while (!w.over && w.t < seconds) w.update(dt, botInput(w, mem));
      runs.push({ time: Math.round(w.t), score: w.score, level: w.level, win: !!(w.over && w.over.win), caught: w.caught, missed: w.missed });
    }
    const med = k => { const a = runs.map(r => r[k]).sort((x, y) => x - y); return a[Math.floor(a.length / 2)]; };
    return { runs, time: med('time'), score: med('score'), level: med('level'), wins: runs.filter(r => r.win).length };
  }
  return { W, H, R0, World, POWER, MOVES, FROMS, EFFECTS, botInput, playtest, rng };
}
const CodexEngine = codexEngineModule();
