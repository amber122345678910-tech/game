'use strict';
// Игрок: физика движения (как Humanoid в Роблоксе), камера своей половины экрана, смерть-«ауч», шлепки.

const PHYS = { G: 150, JUMP: 46, WALK: 16, STEP: 1.25, TERM: 140, CLIMB: 13 };
const EMPTY_INPUT = { mx: 0, mz: 0, cam: 0, camY: 0, jump: false, jumpP: false, action: false, actionP: false };

class Player {
  constructor(idx) {
    this.idx = idx;
    this.color = idx === 0 ? '#3ea6ff' : '#ff5fa8';
    this.name = Store.data.names[idx] || 'Игрок ' + (idx + 1);
    this.skin = Store.data.skins[idx] || defaultSkin(idx);
    this.avatar = new Avatar(this.skin);
    R.scene.add(this.avatar.root);
    this.nameTag = null;
    this.makeNameTag();
    this.pos = V3();
    this.vel = V3();
    this.r = 1;
    this.h = 5;
    this.heading = 0;
    this.grounded = false;
    this.groundCol = null;
    this.coyote = 0;
    this.jumpBuf = 0;
    this.climbT = 0;
    this.stun = 0;
    this.dead = false;
    this.deadT = 0;
    this.deathPos = V3();
    this.frozen = false;
    this.speedMul = 1;
    this.jumpMul = 1;
    this.gravMul = 1;
    this.wishLen = 0;
    this.inp = EMPTY_INPUT;
    this.cam = new THREE.PerspectiveCamera(68, 1, 0.1, 2600);
    this.camYaw = 0;
    this.camPitch = 0.3;
    this.camDist = 15;
    this.camCur = 15;
    this.camTarget = V3();
    this.camManualT = 0;
    this.camShake = 0;
    this.camMode = 'follow';
    this.autoCam = true;
    this.checkpoint = { pos: V3(), heading: 0, index: 0 };
    this.trail = new Trail(this.skin.trail);
    this.box = { min: V3(), max: V3(), solid: true, active: true, isPlayer: true, owner: this, delta: V3() };
    this.ability = null;
    this.cool = 0;
    this.pendingHit = -1;
    this.actionQueued = false;
    this.power = {};
    this.dmg = 0;
    this.score = 0;
    this.pendingKill = false;
    this.aspect = 1;
  }

  makeNameTag() {
    if (this.nameTag) {
      R.scene.remove(this.nameTag);
      this.nameTag.material.map.dispose();
      this.nameTag.material.dispose();
    }
    this.nameTag = textSprite(this.name, { color: '#ffffff', stroke: shade(this.color, -0.55), size: 56, height: 1.0 });
    R.scene.add(this.nameTag);
  }

  setName(n) {
    this.name = n;
    this.makeNameTag();
  }

  setSkin(skin) {
    this.skin = { ...skin };
    this.avatar.setSkin(this.skin);
    if (this.trail.type !== skin.trail) {
      this.trail.dispose();
      this.trail = new Trail(skin.trail);
    }
  }

  setInput(s) {
    this.inp = s || EMPTY_INPUT;
    if (this.inp.jumpP) this.jumpBuf = 0.15;
    else if (this.inp.jump && this.jumpBuf < 0.03) this.jumpBuf = 0.03;
    if (this.inp.actionP) this.actionQueued = true;
  }

  spawn(pos, heading = 0) {
    this.pos.copy(pos);
    this.vel.set(0, 0, 0);
    this.heading = heading;
    this.camYaw = heading + Math.PI;
    this.camTarget.set(pos.x, pos.y + 4.2, pos.z);
    this.camCur = this.camDist;
    this.grounded = false;
    this.groundCol = null;
    this.stun = 0;
    this.climbT = 0;
    this.dead = false;
    this.deadT = 0;
    this.pendingKill = false;
    this.pendingHit = -1;
    this.avatar.root.visible = true;
    this.avatar.slapT = -1;
    this.avatar.pushT = -1;
    this.updateBox();
  }

  setCheckpoint(pos, heading, index = 0) {
    this.checkpoint.pos.copy(pos);
    this.checkpoint.heading = heading;
    this.checkpoint.index = index;
  }

  updateBox() {
    const p = this.pos;
    this.box.min.set(p.x - this.r, p.y, p.z - this.r);
    this.box.max.set(p.x + this.r, p.y + this.h, p.z + this.r);
    this.box.active = !this.dead;
  }

  ovBox(b, eps) {
    const p = this.pos;
    return p.x - this.r < b.max.x - eps && p.x + this.r > b.min.x + eps
      && p.y < b.max.y - eps && p.y + this.h > b.min.y + eps
      && p.z - this.r < b.max.z - eps && p.z + this.r > b.min.z + eps;
  }

  anyOverlap() {
    for (const b of World.boxes) if (b.active && b.solid && this.ovBox(b, 0.002)) return true;
    for (const b of World.dynamic) if (b.owner !== this && b.active && this.ovBox(b, 0.002)) return true;
    const p = this.pos;
    for (const c of World.cyls) {
      if (!c.active || !c.solid) continue;
      if (p.y < c.y1 - 0.002 && p.y + this.h > c.y0 + 0.002 && Math.hypot(p.x - c.x, p.z - c.z) < c.r + this.r) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- физика

  step(dt) {
    if (this.dead) return;
    const inp = this.inp;
    const gc = this.groundCol;
    if (gc && gc.active !== false && gc.delta) this.pos.add(gc.delta);
    if (this.grounded && gc && gc.conveyor) {
      this.pos.x += gc.conveyor[0] * dt;
      this.pos.z += gc.conveyor[1] * dt;
    }

    const canMove = !this.frozen && this.stun <= 0;
    let wx = 0;
    let wz = 0;
    if (canMove) {
      const s = Math.sin(this.camYaw);
      const c = Math.cos(this.camYaw);
      wx = inp.mx * c - inp.mz * s;
      wz = -inp.mx * s - inp.mz * c;
    }
    this.wishLen = Math.hypot(wx, wz);
    const speed = PHYS.WALK * this.speedMul;
    let accel;
    if (this.stun > 0) accel = this.grounded ? 38 : 2;
    else if (this.grounded) accel = gc && gc.ice ? 16 : 150;
    else accel = 85;
    let dvx = wx * speed - this.vel.x;
    let dvz = wz * speed - this.vel.z;
    const dl = Math.hypot(dvx, dvz);
    const maxd = accel * dt;
    if (dl > maxd) { dvx *= maxd / dl; dvz *= maxd / dl; }
    this.vel.x += dvx;
    this.vel.z += dvz;

    if (this.jumpBuf > 0) this.jumpBuf -= dt;
    if (canMove && this.jumpBuf > 0 && (this.grounded || this.coyote > 0 || this.climbT > 0)) {
      this.vel.y = PHYS.JUMP * this.jumpMul;
      if (this.climbT > 0 && this.wishLen < 0.1) { this.vel.x = -Math.sin(this.heading) * 14; this.vel.z = -Math.cos(this.heading) * 14; }
      this.grounded = false;
      this.groundCol = null;
      this.coyote = 0;
      this.jumpBuf = 0;
      this.climbT = 0;
      Sound.play('jump', { pitch: this.idx ? 1.12 : 1 });
    }

    if (this.climbT > 0) {
      this.climbT -= dt;
      this.vel.y = PHYS.CLIMB;
    } else {
      this.vel.y -= PHYS.G * this.gravMul * dt;
      if (this.vel.y < -PHYS.TERM) this.vel.y = -PHYS.TERM;
    }

    const wasGrounded = this.grounded;
    const fallSpeed = this.vel.y;
    this.moveAxis(0, this.vel.x * dt, wasGrounded);
    this.moveAxis(2, this.vel.z * dt, wasGrounded);
    this.grounded = false;
    this.groundCol = null;
    this.moveAxis(1, this.vel.y * dt, wasGrounded);
    if (this.grounded) {
      this.coyote = 0.1;
      if (!wasGrounded && fallSpeed < -30) Sound.play('land', { gap: 0.15 });
      const g = this.groundCol;
      if (g && g.bounce) {
        this.vel.y = g.bounce;
        this.grounded = false;
        this.groundCol = null;
        Sound.play('boing', { gap: 0.2 });
        FX.ring(V3(this.pos.x, this.pos.y + 0.2, this.pos.z), '#9cff57', { size: 4, life: 0.4 });
      } else if (g && g.onStand) g.onStand(this, g);
    } else this.coyote -= dt;

    if (canMove && this.wishLen > 0.1) this.heading = dampAngle(this.heading, Math.atan2(wx, wz), 18, dt);
    if (this.stun > 0) this.stun -= dt;
    if (this.cool > 0) this.cool -= dt;
    if (this.pendingHit >= 0) {
      this.pendingHit -= dt;
      if (this.pendingHit < 0) this.doHit();
    }

    for (const t of World.triggers) if (t.active && this.ovBox(t, 0)) t.fn(this, t);
    for (const h of World.hazards) if (h.test(this)) { if (h.hit) h.hit(this); else this.pendingKill = true; }
    if (this.pendingKill) {
      this.pendingKill = false;
      this.die('kill');
      return;
    }
    if (this.pos.y < World.killY) this.die('fall');
    this.updateBox();
  }

  moveAxis(a, d, wasGrounded) {
    if (d === 0) return;
    const key = a === 0 ? 'x' : a === 1 ? 'y' : 'z';
    this.pos[key] += d;
    for (const b of World.boxes) {
      if (!b.active || !b.solid || !this.ovBox(b, 0.001)) continue;
      this.resolveBox(b, a, key, d, wasGrounded, false);
    }
    for (const b of World.dynamic) {
      if (b.owner === this || !b.active || !this.ovBox(b, 0.001)) continue;
      this.resolveBox(b, a, key, d, wasGrounded, true);
    }
    for (const c of World.cyls) {
      if (!c.active || !c.solid) continue;
      this.resolveCyl(c, a, d, wasGrounded);
    }
  }

  resolveBox(b, a, key, d, wasGrounded, isPlayer) {
    if (b.kill) this.pendingKill = true;
    if (a === 1) {
      if (d < 0) {
        this.pos.y = b.max.y;
        if (this.vel.y < 0) this.vel.y = 0;
        this.grounded = true;
        this.groundCol = b;
      } else {
        this.pos.y = b.min.y - this.h;
        if (this.vel.y > 0) this.vel.y = 0;
      }
      return;
    }
    if (isPlayer) {
      // Толкаем другого игрока: он сдвигается, мы упираемся.
      const o = b.owner;
      if (!o.dead && !o.frozen) {
        o.moveAxis(a, d * 0.55, o.grounded);
        o.updateBox();
        if (!this.ovBox(b, 0.001)) return;
      }
    }
    const rise = b.max.y - this.pos.y;
    if (wasGrounded && rise > 0 && rise <= PHYS.STEP && !b.kill && !isPlayer && !b.climb) {
      const oy = this.pos.y;
      this.pos.y = b.max.y + 0.001;
      if (!this.anyOverlap()) return;
      this.pos.y = oy;
    }
    if (b.climb && this.wishLen > 0.1) this.climbT = 0.12;
    if (d > 0) this.pos[key] = b.min[key] - this.r - 0.0005;
    else this.pos[key] = b.max[key] + this.r + 0.0005;
    if (Math.sign(this.vel[key]) === Math.sign(d)) this.vel[key] = 0;
  }

  resolveCyl(c, a, d, wasGrounded) {
    const p = this.pos;
    if (!(p.y < c.y1 - 0.001 && p.y + this.h > c.y0 + 0.001)) return;
    const dx = p.x - c.x;
    const dz = p.z - c.z;
    const dist = Math.hypot(dx, dz);
    if (a === 1) {
      if (dist > c.r + this.r * 0.6) return;
      if (c.kill) this.pendingKill = true;
      if (d < 0) {
        p.y = c.y1;
        if (this.vel.y < 0) this.vel.y = 0;
        this.grounded = true;
        this.groundCol = c;
      } else {
        p.y = c.y0 - this.h;
        if (this.vel.y > 0) this.vel.y = 0;
      }
      return;
    }
    const rr = c.r + this.r;
    if (dist >= rr) return;
    const rise = c.y1 - p.y;
    if (wasGrounded && rise > 0 && rise <= PHYS.STEP && !c.kill) {
      const oy = p.y;
      p.y = c.y1 + 0.001;
      if (!this.anyOverlap()) return;
      p.y = oy;
    }
    if (c.kill) this.pendingKill = true;
    const nx = dist > 1e-6 ? dx / dist : 1;
    const nz = dist > 1e-6 ? dz / dist : 0;
    p.x = c.x + nx * (rr + 0.0005);
    p.z = c.z + nz * (rr + 0.0005);
  }

  // Движущаяся платформа въехала в игрока — выталкиваем по кратчайшей оси.
  depenetrate() {
    if (this.dead) return;
    const p = this.pos;
    for (const b of World.boxes) {
      if (!b.active || !b.solid || !b.moving || !this.ovBox(b, 0.01)) continue;
      const pen = [
        [b.max.x - (p.x - this.r), 'x', 1], [(p.x + this.r) - b.min.x, 'x', -1],
        [b.max.y - p.y, 'y', 1], [(p.y + this.h) - b.min.y, 'y', -1],
        [b.max.z - (p.z - this.r), 'z', 1], [(p.z + this.r) - b.min.z, 'z', -1],
      ];
      pen.sort((u, v) => u[0] - v[0]);
      const [amt, k, s] = pen[0];
      p[k] += s * (amt + 0.001);
      if (k === 'y' && s > 0) { this.grounded = true; this.groundCol = b; if (this.vel.y < 0) this.vel.y = 0; }
      if (b.kill) this.pendingKill = true;
    }
  }

  // Выталкивание после того, как игрока сдвинули снаружи (например, цепью).
  pushOut() {
    if (this.dead) return;
    const p = this.pos;
    for (const b of World.boxes) {
      if (!b.active || !b.solid || !this.ovBox(b, 0.01)) continue;
      const pen = [
        [b.max.x - (p.x - this.r), 'x', 1], [(p.x + this.r) - b.min.x, 'x', -1],
        [b.max.y - p.y, 'y', 1], [(p.y + this.h) - b.min.y, 'y', -1],
        [b.max.z - (p.z - this.r), 'z', 1], [(p.z + this.r) - b.min.z, 'z', -1],
      ];
      pen.sort((u, v) => u[0] - v[0]);
      const [amt, k, s] = pen[0];
      p[k] += s * (amt + 0.001);
      if (k === 'y' && s > 0) {
        this.grounded = true;
        this.groundCol = b;
        if (this.vel.y < 0) this.vel.y = 0;
      } else if (Math.sign(this.vel[k]) === -s) this.vel[k] = 0;
      if (b.kill) this.pendingKill = true;
    }
    for (const c of World.cyls) {
      if (!c.active || !c.solid) continue;
      if (!(p.y < c.y1 - 0.01 && p.y + this.h > c.y0 + 0.01)) continue;
      const dx = p.x - c.x;
      const dz = p.z - c.z;
      const dist = Math.hypot(dx, dz);
      const rr = c.r + this.r;
      if (dist >= rr) continue;
      const up = c.y1 - p.y;
      if (up < rr - dist && dist < c.r + this.r * 0.6) {
        p.y = c.y1;
        this.grounded = true;
        this.groundCol = c;
        if (this.vel.y < 0) this.vel.y = 0;
      } else {
        const nx = dist > 1e-6 ? dx / dist : 1;
        const nz = dist > 1e-6 ? dz / dist : 0;
        p.x = c.x + nx * (rr + 0.001);
        p.z = c.z + nz * (rr + 0.001);
      }
      if (c.kill) this.pendingKill = true;
    }
    this.updateBox();
  }

  knock(dx, dz, h, v, stun) {
    const l = Math.hypot(dx, dz) || 1;
    this.vel.x = (dx / l) * h;
    this.vel.z = (dz / l) * h;
    this.vel.y = v;
    this.grounded = false;
    this.groundCol = null;
    this.coyote = 0;
    this.stun = stun;
  }

  // ---------------------------------------------------------------- действия

  tryAction() {
    if (!this.ability || this.cool > 0 || this.dead || this.frozen) return;
    if (this.ability === 'slap') {
      this.cool = 0.55;
      this.avatar.slapT = 0;
      this.pendingHit = 0.11;
    } else {
      this.cool = 0.9;
      this.avatar.pushT = 0;
      this.pendingHit = 0.08;
    }
    Sound.play('whoosh');
  }

  doHit() {
    const o = Game.other(this);
    if (!o || o.dead || this.dead) return;
    const dx = o.pos.x - this.pos.x;
    const dz = o.pos.z - this.pos.z;
    const dy = o.pos.y - this.pos.y;
    const dist = Math.hypot(dx, dz);
    const range = this.ability === 'slap' ? 7 : 5.8;
    if (dist > range || Math.abs(dy) > 4.5) return;
    const fx = Math.sin(this.heading);
    const fz = Math.cos(this.heading);
    const dot = (dx * fx + dz * fz) / (dist || 1);
    if (dist > 1.6 && dot < 0.3) return;
    if (Game.mode && Game.mode.onHit) Game.mode.onHit(this, o, dx, dz);
    else {
      o.knock(dx, dz, 30, 16, 0.4);
      Sound.play('push');
      FX.burst(V3(o.pos.x, o.pos.y + 3, o.pos.z), 10, { color: '#ffffff', speed: 8, glow: true, grav: 0, life: 0.4, size: 0.3 });
    }
  }

  // ---------------------------------------------------------------- смерть

  die(reason) {
    if (this.dead) return;
    this.dead = true;
    this.deadT = 0;
    this.deathPos.copy(this.pos);
    this.box.active = false;
    for (const m of this.avatar.pieces()) {
      const v = V3(rand(-12, 12) + this.vel.x * 0.3, rand(8, 22), rand(-12, 12) + this.vel.z * 0.3);
      FX.addDebris(m, v, V3(rand(-9, 9), rand(-9, 9), rand(-9, 9)));
    }
    this.avatar.root.visible = false;
    this.camShake = 0.4;
    Sound.play('oof', { pitch: this.idx ? 1.18 : 1 });
    if (Game.mode && Game.mode.onDeath) Game.mode.onDeath(this, reason);
  }

  // ---------------------------------------------------------------- кадр

  update(dt) {
    if (this.actionQueued) {
      this.actionQueued = false;
      this.tryAction();
    }
    if (this.dead) this.deadT += dt;
    const sp = Math.hypot(this.vel.x, this.vel.z);
    this.avatar.root.position.copy(this.pos);
    this.avatar.root.rotation.y = this.heading;
    this.avatar.animate(dt, { speed: sp, grounded: this.grounded || this.coyote > 0.06, vy: this.vel.y, climbing: this.climbT > 0 });
    const waist = V3(this.pos.x, this.pos.y + 2.6, this.pos.z);
    this.trail.update(dt, waist, sp > 3 && !this.dead, !this.dead && this.avatar.root.visible);
    if (this.avatar.jet && !this.grounded && !this.dead && Math.random() < dt * 40) {
      const bx = -Math.sin(this.heading) * 0.9;
      const bz = -Math.cos(this.heading) * 0.9;
      FX.emit({ x: this.pos.x + bx + rand(-0.4, 0.4), y: this.pos.y + 1.9, z: this.pos.z + bz + rand(-0.4, 0.4), vy: -rand(6, 10), life: 0.35, size: rand(0.3, 0.5), color: pick(['#ffb02e', '#ff6a1a', '#ffe14a']), glow: true, grav: 0 });
    }
    const headTop = this.skin.hat !== 'none' ? 7.0 : 6.3;
    this.nameTag.position.set(this.pos.x, this.pos.y + headTop, this.pos.z);
    this.nameTag.visible = !this.dead && this.avatar.root.visible;
  }

  updateCamera(dt, aspect) {
    const inp = this.inp;
    const cam = this.cam;
    if (this.camMode === 'mirror') {
      const f = V3(Math.sin(this.mirrorHeading), 0, Math.cos(this.mirrorHeading));
      const right = V3(f.z, 0, -f.x);
      const c = V3(this.pos.x, this.pos.y + 2.7, this.pos.z);
      cam.position.copy(c).addScaledVector(f, 10.5).add(V3(0, 1.2, 0));
      const look = c.clone().addScaledVector(right, this.idx === 0 ? -2.6 : 2.6);
      cam.lookAt(look);
    } else if (this.camMode === 'fixed') {
      cam.position.copy(this.fixedCam.pos);
      cam.lookAt(this.fixedCam.look);
    } else {
      if (inp.cam) {
        this.camYaw -= inp.cam * 2.6 * dt;
        this.camManualT = 1.4;
      }
      if (inp.camY) this.camPitch = clamp(this.camPitch + inp.camY * 1.5 * dt, -0.15, 1.2);
      this.camManualT -= dt;
      const sp = Math.hypot(this.vel.x, this.vel.z);
      if (this.autoCam && this.camManualT <= 0 && sp > 2 && !this.dead && this.stun <= 0) {
        const diff = angDiff(this.camYaw, this.heading + Math.PI);
        if (Math.abs(diff) < 2.5) this.camYaw += diff * (1 - Math.exp(-1.5 * Math.min(1, sp / 16) * dt));
      }
      let tp = this.dead ? this.deathPos : this.pos;
      if (this.dead && this.deadT > 1.2 && Game.mode && Game.mode.spectate) {
        const o = Game.other(this);
        if (!o.dead) tp = o.pos;
      }
      const ty = tp.y + 4.2;
      if (Math.hypot(this.camTarget.x - tp.x, this.camTarget.y - ty, this.camTarget.z - tp.z) > 40) this.camTarget.set(tp.x, ty, tp.z);
      this.camTarget.x = damp(this.camTarget.x, tp.x, 22, dt);
      this.camTarget.z = damp(this.camTarget.z, tp.z, 22, dt);
      this.camTarget.y = damp(this.camTarget.y, ty, 9, dt);
      const cp = Math.cos(this.camPitch);
      const dir = V3(Math.sin(this.camYaw) * cp, Math.sin(this.camPitch), Math.cos(this.camYaw) * cp);
      const hit = World.raycast(this.camTarget, dir, this.camDist + 0.6);
      const want = Math.max(2.2, Math.min(this.camDist, hit - 0.6));
      this.camCur = want < this.camCur ? want : damp(this.camCur, want, 3, dt);
      cam.position.copy(this.camTarget).addScaledVector(dir, this.camCur);
      cam.lookAt(this.camTarget);
    }
    if (this.camShake > 0) {
      this.camShake = Math.max(0, this.camShake - dt);
      const s = this.camShake * 1.4;
      cam.position.x += rand(-s, s);
      cam.position.y += rand(-s, s);
      cam.position.z += rand(-s, s);
    }
    if (Math.abs(this.aspect - aspect) > 1e-4) {
      this.aspect = aspect;
      cam.aspect = aspect;
      cam.updateProjectionMatrix();
    }
  }

  dispose() {
    this.avatar.dispose();
    this.trail.dispose();
    R.scene.remove(this.nameTag);
  }
}
