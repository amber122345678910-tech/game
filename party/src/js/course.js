'use strict';
// Конструктор обби-трасс: секции в локальных координатах (вперёд / вправо / вверх), поворот на 90°.

const DIRS = [V3(0, 0, -1), V3(1, 0, 0), V3(0, 0, 1), V3(-1, 0, 0)];
const RAINBOW = ['#ff5964', '#ff9f1c', '#ffd23f', '#7ed957', '#2ec4b6', '#4cc9f0', '#7b6cff', '#ff70c8'];

class Course {
  constructor(root, o = {}) {
    this.root = root;
    this.ox = o.x || 0;
    this.oz = o.z || 0;
    this.f = 0;
    this.y = o.y || 0;
    this.wide = o.wide || 1;
    this.colorIdx = o.colorIdx || 0;
    this.cpIndex = 0;
    this.checkpoints = [];
    this.conveyorTex = [];
    this.setDir(o.dir || 0);
  }

  setDir(d) {
    this.dir = ((d % 4) + 4) % 4;
    this.fwd = DIRS[this.dir];
    this.right = V3(-this.fwd.z, 0, this.fwd.x);
  }

  // Повернуть трассу: текущая точка становится новым началом.
  turn(delta) {
    const p = this.world(0, this.y, this.f);
    this.ox = p.x;
    this.oz = p.z;
    this.f = 0;
    this.setDir(this.dir + delta);
  }

  heading() { return Math.atan2(this.fwd.x, this.fwd.z); }

  world(r, y, f) {
    return V3(this.ox + this.right.x * r + this.fwd.x * f, y, this.oz + this.right.z * r + this.fwd.z * f);
  }

  vec(dr, df) {
    return [this.right.x * dr + this.fwd.x * df, this.right.z * dr + this.fwd.z * df];
  }

  size(w, d) {
    return [Math.abs(this.right.x) * w + Math.abs(this.fwd.x) * d, Math.abs(this.right.z) * w + Math.abs(this.fwd.z) * d];
  }

  box(r, y, f, w, h, d, o = {}) {
    const p = this.world(r, y, f);
    const [sx, sz] = this.size(w, d);
    return part(this.root, p.x, p.y, p.z, sx, h, sz, o);
  }

  // Платформа, заданная верхней гранью.
  plat(r, f, top, w, d, o = {}) {
    const h = o.h || 1.2;
    return this.box(r, top - h / 2, f, w, h, d, o);
  }

  color() {
    const c = RAINBOW[this.colorIdx % RAINBOW.length];
    return c;
  }

  nextColor() { this.colorIdx++; }

  mover(fn) { World.addMover(fn); }

  // Площадка-чекпоинт с флагом и номером этапа.
  checkpoint(onTouch, label) {
    const w = 12 * this.wide;
    const d = 9;
    const top = this.y;
    const fc = this.f + d / 2;
    this.plat(0, fc, top, w, d, { color: '#dfe4ec', mat: 'smooth' });
    this.plat(0, fc, top + 0.25, 7, 4.5, { color: '#40d47e', mat: 'neon', h: 0.3, collide: false });
    const pole = this.world(w / 2 - 1.2, top + 3.5, fc - 2.5);
    part(this.root, pole.x, pole.y, pole.z, 0.35, 7, 0.35, { color: '#e6e6e6', mat: 'metal', collide: false });
    const flagP = this.world(w / 2 - 2.6, top + 6, fc - 2.5);
    const [fsx, fsz] = this.size(2.6, 0.12);
    part(this.root, flagP.x, flagP.y, flagP.z, fsx, 1.6, fsz, { color: '#40d47e', mat: 'smooth', collide: false });
    const index = ++this.cpIndex;
    const spawn = this.world(0, top + 0.1, fc);
    const heading = this.heading();
    const tp = this.world(0, top + 3, fc);
    const [tsx, tsz] = this.size(w, d);
    World.addTrigger(tp.x, tp.y, tp.z, tsx, 6, tsz, (pl) => onTouch(pl, index, spawn, heading));
    if (label !== false) {
      const s = textSprite(label || String(index), { color: '#ffffff', stroke: '#1b2033', size: 72, height: 3 });
      s.position.copy(this.world(0, top + 9, fc));
      this.root.add(s);
    }
    this.checkpoints.push({ index, spawn, heading });
    this.f += d;
    return { index, spawn, heading };
  }

  conveyorBelt(r, f, top, w, d, dr, df, speed) {
    const len = Math.hypot(dr, df);
    const [vx, vz] = this.vec((dr / len) * speed, (df / len) * speed);
    this.plat(r, f, top, w, d, { color: '#3a3d46', mat: 'smooth', conveyor: [vx, vz] });
    const tex = R.tex.conveyor.clone();
    tex.needsUpdate = true;
    const along = Math.abs(dr) > Math.abs(df) ? w : d;
    const across = Math.abs(dr) > Math.abs(df) ? d : w;
    tex.repeat.set(across / 2.5, along / 2.5);
    const plane = new THREE.Mesh(new THREE.PlaneGeometry(across, along), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.6 }));
    plane.rotation.x = -Math.PI / 2;
    const g = new THREE.Group();
    g.add(plane);
    g.position.copy(this.world(r, top + 0.02, f));
    g.rotation.y = Math.atan2(-vx, -vz);
    plane.receiveShadow = true;
    this.root.add(g);
    this.conveyorTex.push({ tex, speed: speed / 2.5 });
  }

  animate(dt) {
    for (const c of this.conveyorTex) c.tex.offset.y -= c.speed * dt;
  }
}

// ---------------------------------------------------------------------------
// Секции трассы. d — сложность 0..3. Каждая начинается от c.f на высоте c.y и сдвигает курсор.

const SECTIONS = {
  steps(c, d) {
    let f = c.f;
    let y = c.y;
    let r = 0;
    const n = 6 + Math.min(d, 2);
    const col = c.color();
    for (let i = 0; i < n; i++) {
      const D = Math.max(2.6, rand(3.6, 4.8) - d * 0.35) * (c.wide > 1 ? 1.4 : 1);
      const gap = rand(3, 4.2 + d * 0.6);
      y += rand(-0.4, 1.5);
      r = clamp(r + rand(-3.5, 3.5), -5, 5);
      c.plat(r, f + gap + D / 2, y, D, D, { color: i % 2 ? shade(col, -0.15) : col });
      f += gap + D;
    }
    c.f = f + 2;
    c.y = y;
  },

  beams(c, d, lava = true) {
    const L = 26 + d * 4;
    const bw = Math.max(1.2, 2.2 - d * 0.35) * c.wide;
    const col = c.color();
    if (lava) c.box(0, c.y - 3.2, c.f + L / 2 + 1, 20 * c.wide, 0.8, L + 4, { mat: 'lava', kill: true });
    let f = c.f;
    let r = 0;
    const end = c.f + L;
    while (f < end - 4) {
      const seg = Math.min(rand(6, 9), end - f);
      c.plat(r, f + seg / 2, c.y, bw, seg, { color: col, h: 0.8 });
      f += seg;
      if (f >= end - 4) break;
      const nr = pick([-6, -3, 0, 3, 6].filter((v) => Math.abs(v - r) >= 3)) * c.wide;
      c.plat((r + nr) / 2, f - bw / 2, c.y, Math.abs(nr - r) + bw, bw, { color: shade(col, -0.12), h: 0.8 });
      r = nr;
    }
    if (r !== 0) c.plat(r / 2, f - bw / 2, c.y, Math.abs(r) + bw, bw, { color: shade(col, -0.12), h: 0.8 });
    c.plat(0, f + 1, c.y, bw, 2, { color: col, h: 0.8 });
    c.f = f + 2;
  },

  tightrope(c, d) { SECTIONS.beams(c, d + 1, false); },

  movers(c, d) {
    let f = c.f;
    const n = 3 + (d > 1 ? 1 : 0);
    const col = c.color();
    const size = 5.5 * (c.wide > 1 ? 1.3 : 1);
    for (let i = 0; i < n; i++) {
      const gap = 3.2;
      const fc = f + gap + size / 2;
      const kind = i % 3;
      const A = kind === 1 ? 3 : 5 + d * 0.6;
      const w = 1.1 + d * 0.25;
      const ph = i * 1.7;
      const y = c.y + (kind === 1 ? 1 : 0);
      const pl = c.plat(0, fc, y, size, size, { color: i % 2 ? shade(col, -0.15) : col, props: { moving: true } });
      const cy = pl.col.c.y;
      c.mover((t) => {
        const off = Math.sin(t * w + ph) * A;
        if (kind === 1) {
          const p = c.world(0, cy + off, fc);
          pl.col.setPos(p.x, p.y, p.z);
        } else {
          const p = c.world(off, cy, fc);
          pl.col.setPos(p.x, p.y, p.z);
        }
      });
      f = fc + size / 2;
    }
    c.f = f + 3;
  },

  spinner(c, d) {
    const S = 18 * (c.wide > 1 ? 1.25 : 1);
    const fc = c.f + S / 2 + 1;
    c.plat(0, fc, c.y, S, S + 2, { color: c.color() });
    const center = c.world(0, c.y, fc);
    cylPart(c.root, center.x, c.y, center.z, 1.2, 2.6, { color: '#2b2f3a', mat: 'metal' });
    const cross = d >= 2;
    const len = S - 1.5;
    const barY = c.y + 1.35;
    const bars = [];
    for (let k = 0; k < (cross ? 2 : 1); k++) {
      const m = new THREE.Mesh(boxGeo(len, 0.9, 0.9), Mat.get('neon', '#ff2d55'));
      m.position.set(center.x, barY, center.z);
      c.root.add(m);
      bars.push(m);
    }
    const w = 1.5 + d * 0.3;
    let ang = 0;
    c.mover((t) => {
      ang = t * w;
      bars.forEach((b, k) => { b.rotation.y = -(ang + k * Math.PI / 2); });
    });
    World.addHazard({
      test(p) {
        if (p.pos.y > barY + 0.45 || p.pos.y + p.h < barY - 0.45) return false;
        const vx = p.pos.x - center.x;
        const vz = p.pos.z - center.z;
        for (let k = 0; k < bars.length; k++) {
          const a = ang + k * Math.PI / 2;
          const ux = Math.cos(a);
          const uz = Math.sin(a);
          const pr = clamp(vx * ux + vz * uz, -len / 2, len / 2);
          if (Math.hypot(vx - ux * pr, vz - uz * pr) < 0.45 + p.r * 0.8) return true;
        }
        return false;
      },
    });
    c.f = fc + S / 2 + 1;
  },

  falling(c, d) {
    const rows = 5;
    const cols = c.wide > 1 ? 4 : 3;
    const T = 4 * (c.wide > 1 ? 1.15 : 1);
    const gap = 1.2;
    const col = c.color();
    const tiles = [];
    for (let i = 0; i < rows; i++) {
      for (let j = 0; j < cols; j++) {
        const r = (j - (cols - 1) / 2) * (T + gap);
        const f = c.f + 2 + i * (T + gap) + T / 2;
        const pl = c.plat(r, f, c.y, T, T, { color: (i + j) % 2 ? col : shade(col, 0.3) });
        const tile = { pl, base: pl.col.c.clone(), state: 0, t: 0 };
        pl.col.onStand = () => { if (tile.state === 0) { tile.state = 1; tile.t = 0.45 - d * 0.06; } };
        tiles.push(tile);
      }
    }
    c.mover((t, dt) => {
      for (const tile of tiles) {
        if (tile.state === 0) continue;
        tile.t -= dt;
        const m = tile.pl.mesh;
        if (tile.state === 1) {
          m.position.set(tile.base.x + rand(-0.12, 0.12), tile.base.y, tile.base.z + rand(-0.12, 0.12));
          if (tile.t <= 0) { tile.state = 2; tile.t = 3.2; tile.v = 0; tile.pl.col.active = false; Sound.play('crumble', { gap: 0.1 }); }
        } else if (tile.state === 2) {
          tile.v += 60 * dt;
          m.position.y -= tile.v * dt;
          if (tile.t <= 0) { tile.state = 0; tile.pl.col.active = true; m.position.copy(tile.base); }
        }
      }
    });
    c.f += 2 + rows * (T + gap) + 1;
  },

  trampolines(c, d) {
    let f = c.f;
    const col = c.color();
    const hops = 1 + (d > 1 ? 1 : 0);
    for (let k = 0; k < hops; k++) {
      c.plat(0, f + 3, c.y, 9 * c.wide, 6, { color: col });
      c.plat(0, f + 3, c.y + 0.35, 4.5, 3.5, { color: '#7ed321', mat: 'glow', h: 0.4, bounce: 88 });
      const rise = 13;
      c.plat(0, f + 15, c.y + rise, 9 * c.wide, 8, { color: shade(col, -0.15) });
      c.y += rise;
      f += 19;
    }
    c.f = f;
  },

  truss(c, d) {
    const H = 12 + d * 1.5;
    const W = 10 * c.wide;
    c.plat(0, c.f + 4, c.y, W, 8, { color: c.color() });
    c.box(0, c.y + H / 2, c.f + 9.5, W, H, 3, { color: '#c8b8a6', mat: 'brick' });
    const tw = c.wide > 1 ? 6 : 4;
    c.box(0, c.y + H / 2, c.f + 7.5, tw, H, 1, { color: '#c0c6d0', mat: 'truss', climb: true });
    c.plat(0, c.f + 14, c.y + H, W, 6, { color: shade(c.color(), -0.15) });
    c.y += H;
    c.f += 17;
  },

  conveyors(c, d) {
    const sp = 9 + d * 2;
    const w = 5 * c.wide;
    let f = c.f;
    c.conveyorBelt(0, f + 7, c.y, w, 14, 0, -1, sp);
    f += 14;
    c.plat(0, f + 1.5, c.y, w + 2, 3, { color: c.color() });
    f += 3;
    c.conveyorBelt(0, f + 6, c.y, w, 12, pick([-1, 1]), 0, sp * 0.8);
    c.box(0, c.y - 3.5, f + 6, w + 14, 0.8, 12, { mat: 'lava', kill: true });
    f += 12;
    c.plat(0, f + 1.5, c.y, w + 2, 3, { color: c.color() });
    f += 3;
    c.conveyorBelt(0, f + 7, c.y, w, 14, 0, -1, sp * 1.2);
    c.f = f + 14 + 1;
  },

  sweepers(c, d) {
    const L = 32;
    const W = 7 * c.wide;
    c.plat(0, c.f + L / 2, c.y, W, L, { color: c.color() });
    const n = 4;
    for (let i = 0; i < n; i++) {
      const f = c.f + 5 + i * 7;
      const blk = c.box(0, c.y + 1.6, f, 3.5, 3.2, 1.6, { mat: 'neon', color: '#ff2d55', kill: true, props: { moving: true } });
      const w = 1.4 + d * 0.3 + i * 0.15;
      const ph = i * 1.3;
      const amp = W / 2 + 1.5;
      const cy = c.y + 1.6;
      c.mover((t) => {
        const p = c.world(Math.sin(t * w + ph) * amp, cy, f);
        blk.col.setPos(p.x, p.y, p.z);
      });
    }
    c.f += L;
  },

  pillars(c, d) {
    let f = c.f;
    let y = c.y;
    const col = c.color();
    const n = 6;
    for (let i = 0; i < n; i++) {
      f += rand(4.5, 5.5 + d * 0.4);
      y += rand(0.6, 1.6);
      const r = (i % 2 ? 1 : -1) * rand(1, 3.5) * c.wide;
      const rad = Math.max(1.1, 1.6 - d * 0.15) * (c.wide > 1 ? 1.5 : 1);
      const p = c.world(r, 0, f);
      cylPart(c.root, p.x, y - 24, p.z, rad, 24, { color: i % 2 ? col : shade(col, -0.2) });
      f += rad;
    }
    c.y = y;
    c.f = f + 4;
  },

  blink(c, d) {
    let f = c.f;
    const col = c.color();
    const solidMat = Mat.get('plastic', col);
    const ghostMat = Mat.get('glass', col);
    const plats = [];
    const n = 6;
    for (let i = 0; i < n; i++) {
      const gap = 3;
      const S = 4.5 * (c.wide > 1 ? 1.3 : 1);
      const fc = f + gap + S / 2;
      const pl = c.plat((i % 2 ? 1.5 : -1.5) * c.wide, fc, c.y, S, S, { color: col });
      plats.push({ pl, set: i % 2 });
      f = fc + S / 2;
    }
    const period = 2.2 - d * 0.2;
    c.mover((t) => {
      const phase = Math.floor(t / period) % 2;
      const local = t % period;
      for (const p of plats) {
        const on = p.set === phase;
        const warn = on && local > period - 0.55 && Math.floor(local * 12) % 2 === 0;
        p.pl.col.active = on;
        p.pl.mesh.material = on && !warn ? solidMat : ghostMat;
      }
    });
    c.f = f + 3;
  },

  ice(c, d) {
    const L = 26;
    const W = 12 * c.wide;
    c.plat(0, c.f + L / 2, c.y, W, L, { color: '#bfe9ff', mat: 'ice', ice: true });
    for (let i = 0; i < 5 + d; i++) {
      c.box(rand(-W / 2 + 2, W / 2 - 2), c.y + 1, c.f + 4 + i * (L - 6) / (5 + d), 2, 2, 2, { mat: 'neon', color: '#ff2d55', kill: true });
    }
    c.f += L;
  },

  stairs(c, d) {
    let f = c.f;
    let y = c.y;
    const col = c.color();
    for (let i = 0; i < 7; i++) {
      y += 2.4;
      f += 3.4;
      const r = Math.sin(i * 1.3) * 3 * c.wide;
      c.plat(r, f, y, 4 * c.wide, 3, { color: i % 2 ? col : shade(col, 0.25) });
      f += 1.5;
    }
    c.y = y;
    c.f = f + 2;
  },
};

const SECTION_POOL = {
  obby: [['steps', 3], ['beams', 3], ['movers', 3], ['spinner', 2], ['falling', 2], ['trampolines', 2], ['truss', 2], ['conveyors', 2], ['sweepers', 2], ['pillars', 2], ['blink', 2], ['ice', 1], ['tightrope', 1], ['stairs', 1]],
  chained: [['steps', 3], ['beams', 2], ['movers', 2], ['falling', 2], ['trampolines', 2], ['truss', 3], ['pillars', 2], ['blink', 1], ['stairs', 3], ['sweepers', 1], ['spinner', 1], ['conveyors', 1]],
};

function pickSections(pool, n) {
  const list = SECTION_POOL[pool];
  const out = [];
  let last = null;
  for (let i = 0; i < n; i++) {
    let total = 0;
    const cand = list.filter(([k]) => k !== last && out.filter((x) => x === k).length < 2);
    for (const [, w] of cand) total += w;
    let r = Math.random() * total;
    let chosen = cand[0][0];
    for (const [k, w] of cand) { r -= w; if (r <= 0) { chosen = k; break; } }
    out.push(chosen);
    last = chosen;
  }
  return out;
}
