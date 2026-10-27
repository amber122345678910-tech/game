// Окно «Мир» в редакторе: изометрический вид как в Roblox Studio
const Viewport = (() => {
  function hexToRgb(r, g, b) {
    return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255)];
  }
  function shade(rgb, f) {
    const [r, g, b] = rgb;
    if (f >= 1) {
      const t = f - 1;
      return `rgb(${Math.round(r + (255 - r) * t)},${Math.round(g + (255 - g) * t)},${Math.round(b + (255 - b) * t)})`;
    }
    return `rgb(${Math.round(r * f)},${Math.round(g * f)},${Math.round(b * f)})`;
  }

  function create(canvas, opts) {
    const ctx = canvas.getContext("2d");
    let world = { parts: [], avatar: null, stats: [], clock: 14 };
    let zoom = 9;
    let cam = { x: 0, y: 0, z: 0 };
    let manual = false;
    let drawn = []; // для попадания пальцем: [{id, polys}]
    let ripple = null;
    let raf = 0;
    let dpr = 1;
    let W = 0;
    let H = 0;

    function resize() {
      dpr = Math.min(3, window.devicePixelRatio || 1);
      const r = canvas.getBoundingClientRect();
      W = Math.max(50, r.width);
      H = Math.max(50, r.height);
      canvas.width = Math.round(W * dpr);
      canvas.height = Math.round(H * dpr);
    }

    function proj(x, y, z) {
      const dx = x - cam.x;
      const dz = z - cam.z;
      const dy = y - cam.y;
      return [W / 2 + (dx - dz) * zoom * 0.866, H / 2 + (dx + dz) * zoom * 0.5 - dy * zoom];
    }

    function autoFit() {
      if (manual) return;
      let x0 = -4, x1 = 4, z0 = -4, z1 = 4, y1 = 2;
      for (const p of world.parts) {
        if (p.y < -50) continue;
        x0 = Math.min(x0, p.x - p.sx / 2);
        x1 = Math.max(x1, p.x + p.sx / 2);
        z0 = Math.min(z0, p.z - p.sz / 2);
        z1 = Math.max(z1, p.z + p.sz / 2);
        y1 = Math.max(y1, p.y + p.sy / 2);
      }
      const a = world.avatar;
      if (a && a.joined) {
        x0 = Math.min(x0, a.x - 2); x1 = Math.max(x1, a.x + 2);
        z0 = Math.min(z0, a.z - 2); z1 = Math.max(z1, a.z + 2);
        y1 = Math.max(y1, a.y + 2);
      }
      x0 = Math.max(x0, -120); x1 = Math.min(x1, 120); z0 = Math.max(z0, -120); z1 = Math.min(z1, 120); y1 = Math.min(y1, 120);
      const tx = (x0 + x1) / 2, tz = (z0 + z1) / 2, ty = y1 / 3;
      const spanW = ((x1 - x0) + (z1 - z0)) * 0.866 + 4;
      const spanH = ((x1 - x0) + (z1 - z0)) * 0.5 + y1 + 3;
      const tzoom = Math.max(2, Math.min(22, Math.min(W / spanW, (H - 20) / spanH)));
      cam.x += (tx - cam.x) * 0.15;
      cam.z += (tz - cam.z) * 0.15;
      cam.y += (ty - cam.y) * 0.15;
      zoom += (tzoom - zoom) * 0.15;
    }

    function sky() {
      const t = world.clock;
      const day = t >= 6.5 && t <= 17.5;
      const dusk = !day && ((t > 5 && t < 6.5) || (t > 17.5 && t < 19));
      const g = ctx.createLinearGradient(0, 0, 0, H);
      if (day) { g.addColorStop(0, "#5aa6e6"); g.addColorStop(1, "#bfe3ff"); }
      else if (dusk) { g.addColorStop(0, "#3d3a7a"); g.addColorStop(1, "#f29a6b"); }
      else { g.addColorStop(0, "#070a1f"); g.addColorStop(1, "#1c2350"); }
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, W, H);
      if (!day && !dusk) {
        ctx.fillStyle = "#fff";
        for (let i = 0; i < 40; i++) {
          const sx = (i * 97.3) % W, sy = (i * 53.7) % (H * 0.6);
          ctx.fillRect(sx, sy, 1.2, 1.2);
        }
      }
      return day ? 1 : dusk ? 0.8 : 0.55;
    }

    function poly(pts, fill, stroke) {
      ctx.beginPath();
      ctx.moveTo(pts[0][0], pts[0][1]);
      for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
      ctx.closePath();
      ctx.fillStyle = fill;
      ctx.fill();
      if (stroke) {
        ctx.strokeStyle = stroke;
        ctx.lineWidth = 0.6;
        ctx.stroke();
      }
    }

    function box(b, rgb, light, opts2 = {}) {
      const x0 = b.x - b.sx / 2, x1 = b.x + b.sx / 2;
      const y0 = b.y - b.sy / 2, y1 = b.y + b.sy / 2;
      const z0 = b.z - b.sz / 2, z1 = b.z + b.sz / 2;
      const top = [proj(x0, y1, z0), proj(x1, y1, z0), proj(x1, y1, z1), proj(x0, y1, z1)];
      const right = [proj(x1, y0, z0), proj(x1, y1, z0), proj(x1, y1, z1), proj(x1, y0, z1)];
      const front = [proj(x0, y0, z1), proj(x1, y0, z1), proj(x1, y1, z1), proj(x0, y1, z1)];
      const edge = opts2.neon ? null : "rgba(0,0,0,0.25)";
      const L = opts2.neon ? 1 : light;
      poly(front, shade(rgb, 0.85 * L), edge);
      poly(right, shade(rgb, 0.62 * L), edge);
      poly(top, opts2.neon ? shade(rgb, 1.25) : shade(rgb, Math.min(1.15, 1.05 * L)), edge);
      return [top, right, front];
    }

    function ball(b, rgb, light, neon) {
      const [cx, cy] = proj(b.x, b.y, b.z);
      const r = (Math.min(b.sx, b.sy, b.sz) / 2) * zoom * 1.05;
      const g = ctx.createRadialGradient(cx - r * 0.35, cy - r * 0.35, r * 0.1, cx, cy, r);
      g.addColorStop(0, shade(rgb, neon ? 1.4 : 1.2));
      g.addColorStop(1, shade(rgb, neon ? 1 : 0.55 * light));
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.fillStyle = g;
      ctx.fill();
      const pts = [];
      for (let i = 0; i < 8; i++) pts.push([cx + Math.cos((i / 8) * Math.PI * 2) * r, cy + Math.sin((i / 8) * Math.PI * 2) * r]);
      return [pts];
    }

    function drawAvatar(a, light) {
      if (!a || !a.joined) return;
      const s = (o) => box(o.b, o.c, light);
      if (a.dead) {
        const pieces = [
          { b: { x: a.x - 1.5, y: 0.5, z: a.z, sx: 2, sy: 1, sz: 1 }, c: [245, 205, 48] },
          { b: { x: a.x + 1, y: 0.5, z: a.z + 1, sx: 2, sy: 1, sz: 2 }, c: [13, 105, 172] },
          { b: { x: a.x, y: 0.5, z: a.z - 1.5, sx: 1, sy: 1, sz: 2 }, c: [75, 151, 75] },
        ];
        pieces.forEach(s);
        const [hx, hy] = proj(a.x, 3, a.z);
        ctx.fillStyle = "#fff";
        ctx.font = `600 ${Math.max(14, zoom * 1.6)}px "Handjet", monospace`;
        ctx.textAlign = "center";
        ctx.fillText("ОЙ! Возрождение...", hx, hy);
        return;
      }
      const y = a.y;
      const parts = [
        { b: { x: a.x - 0.5, y: y - 2, z: a.z, sx: 1, sy: 2, sz: 1 }, c: [75, 151, 75] },
        { b: { x: a.x + 0.5, y: y - 2, z: a.z, sx: 1, sy: 2, sz: 1 }, c: [75, 151, 75] },
        { b: { x: a.x, y: y, z: a.z, sx: 2, sy: 2, sz: 1 }, c: [13, 105, 172] },
        { b: { x: a.x - 1.5, y: y, z: a.z, sx: 1, sy: 2, sz: 1 }, c: [245, 205, 48] },
        { b: { x: a.x + 1.5, y: y, z: a.z, sx: 1, sy: 2, sz: 1 }, c: [245, 205, 48] },
        { b: { x: a.x, y: y + 1.6, z: a.z, sx: 1.2, sy: 1.2, sz: 1.2 }, c: [245, 205, 48] },
      ];
      parts.forEach(s);
      // лицо
      const [fx, fy] = proj(a.x, y + 1.6, a.z + 0.61);
      ctx.fillStyle = "#222";
      ctx.fillRect(fx - zoom * 0.3, fy - zoom * 0.15, Math.max(1, zoom * 0.12), Math.max(1, zoom * 0.12));
      ctx.fillRect(fx + zoom * 0.15, fy - zoom * 0.15, Math.max(1, zoom * 0.12), Math.max(1, zoom * 0.12));
      if (a.hp < a.maxHp) {
        const [bx, by] = proj(a.x, y + 3, a.z);
        const w = zoom * 3;
        ctx.fillStyle = "#300";
        ctx.fillRect(bx - w / 2, by, w, 4);
        ctx.fillStyle = "#3f3";
        ctx.fillRect(bx - w / 2, by, (w * a.hp) / a.maxHp, 4);
      }
    }

    function render() {
      if (!W) resize();
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      autoFit();
      const light = sky();
      // плита Baseplate
      const R = 48;
      const bp = [proj(-R, 0, -R), proj(R, 0, -R), proj(R, 0, R), proj(-R, 0, R)];
      poly(bp, shade([91, 93, 105], light));
      ctx.strokeStyle = `rgba(255,255,255,${0.07 * light})`;
      ctx.lineWidth = 1;
      for (let i = -R; i <= R; i += 4) {
        let p = proj(i, 0, -R), q = proj(i, 0, R);
        ctx.beginPath(); ctx.moveTo(p[0], p[1]); ctx.lineTo(q[0], q[1]); ctx.stroke();
        p = proj(-R, 0, i); q = proj(R, 0, i);
        ctx.beginPath(); ctx.moveTo(p[0], p[1]); ctx.lineTo(q[0], q[1]); ctx.stroke();
      }
      const items = world.parts.map((p) => ({ kind: "p", p, key: p.x + p.z + (p.y - p.sy / 2) * 0.02 }));
      if (world.avatar && world.avatar.joined) items.push({ kind: "a", key: world.avatar.x + world.avatar.z + 0.5 });
      items.sort((a, b) => a.key - b.key);
      drawn = [];
      for (const it of items) {
        if (it.kind === "a") { drawAvatar(world.avatar, light); continue; }
        const p = it.p;
        if (p.t >= 0.999) { drawn.push({ id: p.id, polys: [], p }); continue; }
        ctx.globalAlpha = 1 - p.t * 0.9;
        const rgb = hexToRgb(p.r, p.g, p.b);
        const neon = p.material === "Neon";
        if (neon || p.light) {
          ctx.shadowColor = `rgb(${rgb.join(",")})`;
          ctx.shadowBlur = Math.max(6, zoom * 1.5);
        }
        const polys = p.shape === "Ball" ? ball(p, rgb, light, neon) : box(p, rgb, light, { neon });
        ctx.shadowBlur = 0;
        if (p.material === "ForceField") {
          ctx.globalAlpha = 0.35;
          polys.forEach((pl) => poly(pl, "rgba(160,220,255,0.4)"));
        }
        ctx.globalAlpha = 1;
        if (p.click) {
          const [cx, cy] = proj(p.x, p.y + p.sy / 2 + 0.8, p.z);
          ctx.font = `${Math.max(11, zoom * 1.4)}px sans-serif`;
          ctx.textAlign = "center";
          ctx.fillText("👆", cx, cy);
        }
        drawn.push({ id: p.id, polys, p });
      }
      // таблица лидеров
      if (world.stats.length && world.avatar && world.avatar.joined) {
        ctx.font = '600 17px "Handjet", monospace';
        const rows = [opts.playerName(), ...world.stats.map((s) => `${s.name}: ${s.value}`)];
        const w = Math.max(...rows.map((r) => ctx.measureText(r).width)) + 16;
        ctx.fillStyle = "rgba(0,0,0,0.55)";
        ctx.fillRect(W - w - 6, 6, w, rows.length * 16 + 8);
        ctx.fillStyle = "#fff";
        ctx.textAlign = "left";
        rows.forEach((r, i) => {
          ctx.fillStyle = i === 0 ? "#ffd84a" : "#fff";
          ctx.fillText(r, W - w + 2, 22 + i * 16);
        });
      }
      if (ripple) {
        const age = (performance.now() - ripple.t) / 400;
        if (age > 1) ripple = null;
        else {
          ctx.strokeStyle = `rgba(255,255,255,${1 - age})`;
          ctx.lineWidth = 2;
          ctx.beginPath();
          ctx.arc(ripple.x, ripple.y, 6 + age * 18, 0, Math.PI * 2);
          ctx.stroke();
        }
      }
      ctx.fillStyle = "rgba(255,255,255,0.7)";
      ctx.font = '16px "Handjet", monospace';
      ctx.textAlign = "left";
      ctx.fillText(`Деталей: ${world.parts.length}`, 8, H - 8);
    }

    function inPoly(x, y, pts) {
      let inside = false;
      for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
        const [xi, yi] = pts[i], [xj, yj] = pts[j];
        if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
      }
      return inside;
    }
    function hit(x, y) {
      for (let i = drawn.length - 1; i >= 0; i--) {
        const d = drawn[i];
        for (const pl of d.polys) if (pl.length && inPoly(x, y, pl)) return d.p;
      }
      return null;
    }

    // жесты: тап — коснуться детали, протянуть — двигать камеру, щипок — масштаб
    const pts = new Map();
    let start = null;
    let pinch = null;
    function pos(e) {
      const r = canvas.getBoundingClientRect();
      return [e.clientX - r.left, e.clientY - r.top];
    }
    canvas.addEventListener("pointerdown", (e) => {
      canvas.setPointerCapture(e.pointerId);
      pts.set(e.pointerId, pos(e));
      if (pts.size === 1) start = { p: pos(e), cam: { ...cam }, moved: false };
      if (pts.size === 2) {
        const [a, b] = [...pts.values()];
        pinch = { d: Math.hypot(a[0] - b[0], a[1] - b[1]), zoom };
      }
    });
    canvas.addEventListener("pointermove", (e) => {
      if (!pts.has(e.pointerId)) return;
      pts.set(e.pointerId, pos(e));
      if (pts.size === 2 && pinch) {
        const [a, b] = [...pts.values()];
        const d = Math.hypot(a[0] - b[0], a[1] - b[1]);
        zoom = Math.max(1.5, Math.min(30, (pinch.zoom * d) / pinch.d));
        manual = true;
        if (start) start.moved = true;
        return;
      }
      if (!start) return;
      const [x, y] = pos(e);
      const dx = x - start.p[0], dy = y - start.p[1];
      if (Math.hypot(dx, dy) > 8) start.moved = true;
      if (start.moved) {
        manual = true;
        // обратная проекция сдвига экрана на плоскость y=0
        const a = dx / (zoom * 0.866), b = dy / (zoom * 0.5);
        cam.x = start.cam.x - (a + b) / 2;
        cam.z = start.cam.z - (b - a) / 2;
      }
    });
    function up(e) {
      if (!pts.has(e.pointerId)) return;
      pts.delete(e.pointerId);
      if (pts.size < 2) pinch = null;
      if (pts.size === 0 && start && !start.moved) {
        const [x, y] = pos(e);
        const p = hit(x, y);
        ripple = { x, y, t: performance.now() };
        if (p) opts.onTapPart(p);
      }
      if (pts.size === 0) start = null;
    }
    canvas.addEventListener("pointerup", up);
    canvas.addEventListener("pointercancel", up);

    function loop() {
      render();
      raf = requestAnimationFrame(loop);
    }

    return {
      setWorld(w) { world = w || world; },
      start() { resize(); cancelAnimationFrame(raf); loop(); },
      stop() { cancelAnimationFrame(raf); raf = 0; },
      resize,
      zoomIn() { zoom = Math.min(30, zoom * 1.3); manual = true; },
      zoomOut() { zoom = Math.max(1.5, zoom / 1.3); manual = true; },
      reset() { manual = false; },
    };
  }
  return { create };
})();
