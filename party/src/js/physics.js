'use strict';
// Простая физика как у Роблокса: персонаж — коробка, мир — коробки и цилиндры, все без поворота.

class BoxCol {
  constructor(cx, cy, cz, sx, sy, sz, props) {
    this.c = new THREE.Vector3(cx, cy, cz);
    this.hs = new THREE.Vector3(sx / 2, sy / 2, sz / 2);
    this.min = new THREE.Vector3();
    this.max = new THREE.Vector3();
    this.delta = new THREE.Vector3();
    this.solid = true;
    this.active = true;
    this.kind = 'box';
    if (props) Object.assign(this, props);
    this.refresh();
  }
  refresh() {
    this.min.subVectors(this.c, this.hs);
    this.max.addVectors(this.c, this.hs);
  }
  setPos(x, y, z) {
    this.delta.x += x - this.c.x;
    this.delta.y += y - this.c.y;
    this.delta.z += z - this.c.z;
    this.c.set(x, y, z);
    this.refresh();
    if (this.mesh) this.mesh.position.set(x, y, z);
  }
  setSize(sx, sy, sz) {
    this.hs.set(sx / 2, sy / 2, sz / 2);
    this.refresh();
  }
}

class CylCol {
  constructor(x, z, r, y0, y1, props) {
    this.x = x;
    this.z = z;
    this.r = r;
    this.y0 = y0;
    this.y1 = y1;
    this.solid = true;
    this.active = true;
    this.kind = 'cyl';
    this.delta = new THREE.Vector3();
    if (props) Object.assign(this, props);
  }
}

const World = {
  boxes: [],
  cyls: [],
  triggers: [],
  movers: [],
  hazards: [],
  dynamic: [],
  time: 0,
  killY: -60,

  clear() {
    this.boxes.length = 0;
    this.cyls.length = 0;
    this.triggers.length = 0;
    this.movers.length = 0;
    this.hazards.length = 0;
    this.dynamic.length = 0;
    this.time = 0;
    this.killY = -60;
  },

  addBox(cx, cy, cz, sx, sy, sz, props) {
    const b = new BoxCol(cx, cy, cz, sx, sy, sz, props);
    this.boxes.push(b);
    return b;
  },

  addCyl(x, z, r, y0, y1, props) {
    const c = new CylCol(x, z, r, y0, y1, props);
    this.cyls.push(c);
    return c;
  },

  // Невидимая зона: callback(player) пока игрок внутри.
  addTrigger(cx, cy, cz, sx, sy, sz, fn, props) {
    const t = new BoxCol(cx, cy, cz, sx, sy, sz, props);
    t.solid = false;
    t.fn = fn;
    this.triggers.push(t);
    return t;
  },

  addMover(fn) { this.movers.push(fn); },
  addHazard(h) { this.hazards.push(h); return h; },

  remove(list, item) {
    const i = list.indexOf(item);
    if (i >= 0) list.splice(i, 1);
  },

  step(dt) {
    this.time += dt;
    for (const b of this.boxes) if (b.delta.x || b.delta.y || b.delta.z) b.delta.set(0, 0, 0);
    for (const m of this.movers) m(this.time, dt);
  },

  // Луч против коробок (для камеры). Возвращает расстояние до первого пересечения.
  raycast(o, d, maxDist, filter) {
    let best = maxDist;
    const inv = [1 / (d.x || 1e-9), 1 / (d.y || 1e-9), 1 / (d.z || 1e-9)];
    for (const b of this.boxes) {
      if (!b.active || !b.solid || b.noCam) continue;
      if (filter && !filter(b)) continue;
      let t0 = 0;
      let t1 = best;
      let ok = true;
      for (let a = 0; a < 3 && ok; a++) {
        const key = a === 0 ? 'x' : a === 1 ? 'y' : 'z';
        let tn = (b.min[key] - o[key]) * inv[a];
        let tf = (b.max[key] - o[key]) * inv[a];
        if (tn > tf) { const tmp = tn; tn = tf; tf = tmp; }
        if (tn > t0) t0 = tn;
        if (tf < t1) t1 = tf;
        if (t0 > t1) ok = false;
      }
      if (ok && t0 < best && t0 > 0) best = t0;
    }
    return best;
  },

  // Самая высокая поверхность под точкой (для теней-кружков и спавна).
  groundAt(x, z, fromY) {
    let best = -Infinity;
    for (const b of this.boxes) {
      if (!b.active || !b.solid) continue;
      if (x < b.min.x || x > b.max.x || z < b.min.z || z > b.max.z) continue;
      if (b.max.y <= fromY + 0.01 && b.max.y > best) best = b.max.y;
    }
    for (const c of this.cyls) {
      if (!c.active || !c.solid) continue;
      if ((x - c.x) ** 2 + (z - c.z) ** 2 > c.r * c.r) continue;
      if (c.y1 <= fromY + 0.01 && c.y1 > best) best = c.y1;
    }
    return best;
  },
};
