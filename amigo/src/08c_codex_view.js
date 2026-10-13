/* ===== 08c_codex_view.js ===== */
// Экран игр Кодекса: фон мира, герой, предметы, эффекты, звуки и счёт.
// Как и движок, это одна самостоятельная функция: её код Амиго кладёт в HTML-файл игры, когда показывает «полный код».
function codexViewModule(E) {
  'use strict';
  const W = E.W, H = E.H;
  const FONT = '"Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji","Twemoji Mozilla",sans-serif';
  const sprites = new Map();
  function sprite(emoji, r) {
    const size = Math.max(8, Math.round(r * 2.3)), key = emoji + '|' + size;
    let c = sprites.get(key);
    if (c) return c;
    c = document.createElement('canvas'); c.width = c.height = size * 2;
    const x = c.getContext('2d');
    x.font = Math.round(size * 1.55) + 'px ' + FONT; x.textAlign = 'center'; x.textBaseline = 'middle';
    x.fillText(emoji, size, size * 1.08);
    if (sprites.size > 300) sprites.clear();
    sprites.set(key, c);
    return c;
  }
  function emoji(ctx, e, x, y, r, rot) {
    const s = sprite(e, r), d = s.width / 2;
    if (rot) { ctx.save(); ctx.translate(x, y); ctx.rotate(rot); ctx.drawImage(s, -d / 2, -d / 2, d, d); ctx.restore(); }
    else ctx.drawImage(s, x - d / 2, y - d / 2, d, d);
  }
  function amigo(ctx, x, y, r, tilt) {
    ctx.save(); ctx.translate(x, y); ctx.rotate(tilt || 0);
    ctx.strokeStyle = '#10302D'; ctx.lineWidth = Math.max(1.5, r * 0.12); ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(0, -r * 0.92); ctx.lineTo(0, -r * 1.3); ctx.stroke();
    ctx.fillStyle = '#E2566E'; ctx.beginPath(); ctx.arc(0, -r * 1.36, r * 0.2, 0, 7); ctx.fill();
    ctx.fillStyle = '#F0B23C'; ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.fill();
    for (const s of [-1, 1]) {
      ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.ellipse(s * r * 0.38, -r * 0.08, r * 0.24, r * 0.3, 0, 0, 7); ctx.fill();
      ctx.fillStyle = '#10302D'; ctx.beginPath(); ctx.arc(s * r * 0.38 + r * 0.04, -r * 0.03, r * 0.13, 0, 7); ctx.fill();
    }
    ctx.beginPath(); ctx.arc(0, r * 0.22, r * 0.36, 0.15 * Math.PI, 0.85 * Math.PI); ctx.stroke();
    ctx.restore();
  }
  function rr(ctx, x, y, w, h, r) { r = Math.min(r, w / 2, h / 2); ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath(); }
  const COLORS = ['#FFD166', '#EF476F', '#06D6A0', '#4CC9F0', '#FFFFFF', '#F78C6B'];

  // ---------- звуки (маленький синтезатор) ----------
  function makeSound(getCtx) {
    let lastShoot = 0;
    const tone = (ac, f, t0, dur, type, vol, f2) => {
      const o = ac.createOscillator(), g = ac.createGain();
      o.type = type || 'sine'; o.frequency.setValueAtTime(f, t0); if (f2) o.frequency.exponentialRampToValueAtTime(f2, t0 + dur);
      g.gain.setValueAtTime(0.0001, t0); g.gain.exponentialRampToValueAtTime(vol || 0.18, t0 + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
      o.connect(g).connect(ac.destination); o.start(t0); o.stop(t0 + dur + 0.02);
    };
    return name => {
      const ac = getCtx && getCtx(); if (!ac || ac.state !== 'running') return;
      const t = ac.currentTime;
      try {
        if (name === 'collect') { tone(ac, 660, t, 0.08, 'sine', 0.15); tone(ac, 990, t + 0.06, 0.1, 'sine', 0.13); }
        else if (name === 'pop') tone(ac, 520, t, 0.07, 'triangle', 0.12, 220);
        else if (name === 'hit') { tone(ac, 220, t, 0.22, 'square', 0.12, 70); }
        else if (name === 'block') tone(ac, 900, t, 0.12, 'triangle', 0.1, 600);
        else if (name === 'power') [523, 659, 784, 1046].forEach((f, i) => tone(ac, f, t + i * 0.06, 0.1, 'sine', 0.13));
        else if (name === 'shoot') { if (t - lastShoot > 0.12) { lastShoot = t; tone(ac, 880, t, 0.06, 'square', 0.035, 440); } }
        else if (name === 'jump') tone(ac, 330, t, 0.14, 'sine', 0.12, 700);
        else if (name === 'level') [392, 523, 659, 784].forEach((f, i) => tone(ac, f, t + i * 0.09, 0.14, 'triangle', 0.14));
        else if (name === 'boss') { tone(ac, 110, t, 0.5, 'sawtooth', 0.1, 80); tone(ac, 82, t + 0.3, 0.6, 'sawtooth', 0.1, 60); }
        else if (name === 'win') [523, 659, 784, 1046, 1318].forEach((f, i) => tone(ac, f, t + i * 0.1, 0.18, 'triangle', 0.15));
        else if (name === 'lose') [392, 330, 262, 196].forEach((f, i) => tone(ac, f, t + i * 0.13, 0.2, 'triangle', 0.13));
      } catch (e) { /* без звука */ }
    };
  }

  // ---------- художник одной игры ----------
  function create(ctx, spec, o = {}) {
    const fx = spec.fx || {}, th = spec.theme || { bg: ['#7CC8F5', '#E6F6FF'], deco: 'clouds' }, dark = !!th.dark;
    const ink = dark ? '#FFFFFF' : '#13302C', soft = dark ? 'rgba(255,255,255,.75)' : 'rgba(19,48,44,.7)';
    const parts = [], texts = [], deco = [];
    let shake = 0, banner = null, time = 0;
    const play = makeSound(o.audio);
    const rnd = Math.random;
    for (let i = 0; i < 46; i++) deco.push({ x: rnd() * W, y: rnd() * H, r: 0.5 + rnd() * 2, s: 0.3 + rnd(), p: rnd() * 6 });
    const grad = ctx.createLinearGradient(0, 0, 0, H); grad.addColorStop(0, th.bg[0]); grad.addColorStop(1, th.bg[1]);
    function background(w) {
      ctx.fillStyle = grad; ctx.fillRect(0, 0, W, H);
      const move = fx.parallax ? 1 : 0, cam = w.camY || 0;
      const d = th.deco;
      if (d === 'stars' || d === 'night') {
        ctx.fillStyle = '#FFFFFF';
        for (const s of deco) { const y = ((s.y + time * 18 * s.s * move - cam * 0.3) % H + H) % H; ctx.globalAlpha = 0.35 + 0.45 * Math.sin(time * 2 + s.p) ** 2; ctx.beginPath(); ctx.arc(s.x, y, s.r, 0, 7); ctx.fill(); }
        ctx.globalAlpha = 1;
        if (d === 'night') { ctx.fillStyle = '#FFF3C4'; ctx.beginPath(); ctx.arc(W - 64, 88, 26, 0, 7); ctx.fill(); ctx.fillStyle = th.bg[0]; ctx.beginPath(); ctx.arc(W - 52, 80, 24, 0, 7); ctx.fill(); }
      } else if (d === 'bubbles') {
        ctx.strokeStyle = 'rgba(255,255,255,.45)'; ctx.lineWidth = 1.2;
        for (const s of deco) { const y = ((s.y - time * 30 * s.s * (move || 0.3)) % H + H) % H; ctx.beginPath(); ctx.arc(s.x + Math.sin(time + s.p) * 6, y, s.r * 2.2, 0, 7); ctx.stroke(); }
        ctx.fillStyle = 'rgba(255,255,255,.08)'; for (let i = 0; i < 4; i++) { ctx.beginPath(); ctx.moveTo(40 + i * 90, 0); ctx.lineTo(10 + i * 90, H); ctx.lineTo(60 + i * 90, H); ctx.lineTo(70 + i * 90, 0); ctx.fill(); }
      } else if (d === 'snow' || d === 'embers' || d === 'leaves') {
        ctx.fillStyle = d === 'snow' ? 'rgba(255,255,255,.9)' : d === 'embers' ? 'rgba(255,170,60,.85)' : 'rgba(40,110,40,.5)';
        const dir = d === 'embers' ? -1 : 1;
        for (const s of deco) { const y = ((s.y + dir * time * 40 * s.s * (move || 0.4)) % H + H) % H; ctx.beginPath(); ctx.arc(s.x + Math.sin(time * 1.5 + s.p) * 10, y, s.r * (d === 'leaves' ? 2 : 1.3), 0, 7); ctx.fill(); }
      } else if (d === 'clouds' || d === 'flowers') {
        ctx.fillStyle = 'rgba(255,255,255,.75)';
        for (let i = 0; i < 5; i++) { const x = ((i * 97 + time * 10 * move) % (W + 120)) - 60, y = 50 + (i * 71) % 220 - (cam * 0.2) % H; ctx.beginPath(); ctx.ellipse(x, ((y % H) + H) % H, 34, 13, 0, 0, 7); ctx.ellipse(x + 20, ((y % H) + H) % H - 8, 22, 12, 0, 0, 7); ctx.fill(); }
        if (d === 'flowers') { for (let i = 0; i < 12; i++) { ctx.fillStyle = COLORS[i % COLORS.length]; ctx.beginPath(); ctx.arc(14 + i * 31, H - 10 - (i % 3) * 5, 4, 0, 7); ctx.fill(); } }
      } else if (d === 'city') {
        ctx.fillStyle = 'rgba(30,40,70,.35)';
        for (let i = 0; i < 9; i++) { const bw = 34 + (i * 37) % 20, bh = 60 + (i * 53) % 110, x = i * 42 - 6; ctx.fillRect(x, H - bh, bw, bh); }
      } else if (d === 'dunes') {
        ctx.fillStyle = 'rgba(200,140,60,.35)';
        ctx.beginPath(); ctx.moveTo(0, H); for (let x = 0; x <= W; x += 10) ctx.lineTo(x, H - 50 - Math.sin(x / 60 + time * 0.2 * move) * 18); ctx.lineTo(W, H); ctx.fill();
        ctx.fillStyle = '#FFE08A'; ctx.beginPath(); ctx.arc(60, 80, 26, 0, 7); ctx.fill();
      } else if (d === 'bricks') {
        ctx.strokeStyle = 'rgba(0,0,0,.18)'; ctx.lineWidth = 1;
        const off = (-cam) % 24;
        for (let y = off; y < H; y += 24) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke(); for (let x = (Math.floor((y - off) / 24) % 2) * 24; x < W; x += 48) { ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x, y + 24); ctx.stroke(); } }
      } else if (d === 'sprinkles') {
        for (const s of deco) { ctx.fillStyle = COLORS[Math.floor(s.p) % COLORS.length]; ctx.save(); ctx.translate(s.x, ((s.y + time * 8 * move) % H + H) % H); ctx.rotate(s.p); ctx.fillRect(-4, -1.5, 8, 3); ctx.restore(); }
      }
      // дорога, земля
      if (spec.control === 'lanes') {
        ctx.fillStyle = 'rgba(40,44,52,.88)'; ctx.fillRect(W * 0.04, 0, W * 0.92, H);
        ctx.fillStyle = '#F5F5F5'; const off = (time * 260 * (0.6 + 0.4 * w.pace())) % 60;
        for (const lx of [W / 3, W * 2 / 3]) for (let y = -60 + off; y < H; y += 60) ctx.fillRect(lx - 3, y, 6, 30);
        ctx.fillStyle = '#FFD166'; ctx.fillRect(W * 0.04, 0, 5, H); ctx.fillRect(W * 0.96 - 5, 0, 5, H);
      }
      if (spec.control === 'runner') {
        const fy = w.floor, up = w.G < 0;
        ctx.fillStyle = dark ? 'rgba(255,255,255,.18)' : 'rgba(60,40,20,.28)';
        if (up) ctx.fillRect(0, 0, W, fy); else ctx.fillRect(0, fy, W, H - fy);
        ctx.fillStyle = dark ? 'rgba(255,255,255,.35)' : 'rgba(60,40,20,.45)';
        const off = (time * 180 * (0.6 + 0.4 * w.pace())) % 30;
        for (let x = -off; x < W; x += 30) ctx.fillRect(x, up ? fy - 6 : fy + 6, 14, 3);
      }
    }
    function thingEmoji(w, e) { return e.emoji || (w.s.things[e.tag] || {}).emoji || ''; }
    function drawEnt(w, e, cam) {
      const y = e.y - cam, def = w.s.things[e.tag] || {};
      if (e.hidden || y < -60 || y > H + 60) return;
      if (e.tag === 'platform') {
        const em = def.emoji;
        if (em && em !== '▬') { const n = Math.max(1, Math.round(e.w / 26)); for (let i = 0; i < n; i++) emoji(ctx, em, e.x - e.w / 2 + 13 + i * (e.w - 26) / Math.max(1, n - 1 || 1), y, 13); }
        else { ctx.fillStyle = e.moving ? '#F78C6B' : '#57B66A'; rr(ctx, e.x - e.w / 2, y - 6, e.w, 12, 6); ctx.fill(); ctx.fillStyle = 'rgba(0,0,0,.18)'; rr(ctx, e.x - e.w / 2, y + 2, e.w, 4, 2); ctx.fill(); }
        return;
      }
      let a = 1;
      if (e.life && e.t > e.life - 0.5) a = Math.max(0, (e.life - e.t) / 0.5);
      let r = e.r;
      if (w.s.control === 'tap' && e.t < 0.15) r *= e.t / 0.15;
      ctx.globalAlpha = a;
      if (e.tag === 'shot' && !thingEmoji(w, e)) { ctx.fillStyle = '#FFE066'; ctx.shadowColor = '#FFD166'; ctx.shadowBlur = fx.particles ? 10 : 0; ctx.beginPath(); ctx.ellipse(e.x, y, 3.5, 8, 0, 0, 7); ctx.fill(); ctx.shadowBlur = 0; }
      else if (e.tag === 'eshot' && !thingEmoji(w, e)) { ctx.fillStyle = '#FF5D73'; ctx.beginPath(); ctx.arc(e.x, y, 5.5, 0, 7); ctx.fill(); }
      else if (def.pipe && e.col) { ctx.fillStyle = '#3FAE5A'; ctx.fillRect(e.x - e.r, y - e.r * 0.98, e.r * 2, e.r * 1.96); ctx.fillStyle = 'rgba(255,255,255,.25)'; ctx.fillRect(e.x - e.r + 4, y - e.r, 5, e.r * 2); }
      else {
        if (e.tag === 'power') { ctx.fillStyle = 'rgba(255,255,255,.35)'; ctx.beginPath(); ctx.arc(e.x, y, r * (1.15 + 0.1 * Math.sin(time * 6)), 0, 7); ctx.fill(); }
        const em = thingEmoji(w, e);
        if (def.amigo) amigo(ctx, e.x, y, r * 0.85);
        else if (em) emoji(ctx, em, e.x, y, r, def.rot ? Math.PI / 2 : 0);
        else { ctx.fillStyle = COLORS[1]; ctx.beginPath(); ctx.arc(e.x, y, r * 0.8, 0, 7); ctx.fill(); }
        if (e.flash > 0) { ctx.globalAlpha = 0.5; ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(e.x, y, r, 0, 7); ctx.fill(); }
      }
      ctx.globalAlpha = 1;
      if (e === w.boss) {
        ctx.fillStyle = 'rgba(0,0,0,.35)'; rr(ctx, W * 0.2, 44, W * 0.6, 9, 4); ctx.fill();
        ctx.fillStyle = '#FF5D73'; rr(ctx, W * 0.2, 44, W * 0.6 * Math.max(0, e.hp / e.maxHp), 9, 4); ctx.fill();
        if (w.s.boss.mode !== 'fight') { ctx.fillStyle = ink; ctx.font = '600 11px sans-serif'; ctx.textAlign = 'center'; ctx.fillText('Продержись: ' + Math.ceil(w.bossT) + ' с', W / 2, 66); ctx.textAlign = 'left'; }
      }
    }
    function drawHero(w, cam) {
      const h = w.hero; if (!h) return;
      const y = h.y - cam;
      if (h.inv > 0 && Math.floor(time * 12) % 2) ctx.globalAlpha = 0.35;
      let tilt = 0;
      if (w.s.control === 'flappy') tilt = Math.max(-0.5, Math.min(0.8, h.vy / 600)) * (w.G || 1);
      const bob = w.s.control === 'runner' && h.onGround ? Math.abs(Math.sin(time * 14)) * 3 : 0;
      if (w.s.hero.amigo || !w.s.hero.emoji) amigo(ctx, h.x, y - bob, h.r * 0.9, tilt);
      else emoji(ctx, w.s.hero.emoji, h.x, y - bob, h.r, w.s.genre === 'racer' ? Math.PI / 2 : tilt);
      ctx.globalAlpha = 1;
      if (w.st.shield) { ctx.strokeStyle = 'rgba(120,200,255,.9)'; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(h.x, y, h.r * 1.35, 0, 7); ctx.stroke(); }
      if (w.st.magnet) { ctx.strokeStyle = 'rgba(255,90,120,.35)'; ctx.setLineDash([4, 6]); ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(h.x, y, 60 + Math.sin(time * 5) * 6, 0, 7); ctx.stroke(); ctx.setLineDash([]); }
    }
    function hud(w) {
      ctx.fillStyle = dark ? 'rgba(0,0,0,.28)' : 'rgba(255,255,255,.55)'; ctx.fillRect(0, 0, W, 34);
      ctx.fillStyle = ink; ctx.font = '700 17px system-ui, sans-serif'; ctx.textBaseline = 'middle';
      ctx.textAlign = 'left'; ctx.fillText((w.s.control === 'jumper' ? '↑ ' : '★ ') + w.score, 10, 18);
      ctx.textAlign = 'center'; ctx.font = '600 13px system-ui, sans-serif';
      ctx.fillText(w.s.timeLimit ? '⏱ ' + Math.max(0, Math.ceil(w.s.timeLimit - w.t)) + ' с' : (w.s.levelEvery || w.s.genre === 'topdown' ? 'Уровень ' + w.level : ''), W / 2, 18);
      ctx.textAlign = 'right';
      ctx.font = '15px ' + FONT;
      ctx.fillText(w.lives <= 5 ? '❤️'.repeat(Math.max(0, w.lives)) : '❤️×' + w.lives, W - 8, 18);
      const icons = Object.keys(w.st).filter(k => E.POWER[k] || k === 'freeze' || k === 'fast');
      if (icons.length) { ctx.textAlign = 'left'; ctx.font = '600 12px system-ui, sans-serif'; ctx.fillStyle = ink; let x = 10; for (const k of icons) { const s = (E.POWER[k] ? E.POWER[k].emoji : k === 'fast' ? '⚡' : '🧊') + ' ' + Math.ceil(w.st[k]); ctx.fillText(s, x, 46); x += 52; } }
      ctx.textBaseline = 'alphabetic'; ctx.textAlign = 'left';
    }
    function eat(w) {
      for (const f of w.fx) {
        if (f.k === 'sound') { if (fx.sound) play(f.s); }
        else if (f.k === 'burst') {
          const n = fx.particles ? (f.n || 10) : 0, big = f.big ? 2 : 1;
          for (let i = 0; i < n; i++) { const a = Math.random() * 6.28, v = (60 + Math.random() * 160) * big; parts.push({ x: f.x, y: f.y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, t: 0, life: 0.5 + Math.random() * 0.4, c: f.c === 'bad' ? '#FF7A59' : COLORS[i % COLORS.length], r: 2 + Math.random() * 3 }); }
          if (!fx.particles) parts.push({ x: f.x, y: f.y, ring: 1, t: 0, life: 0.25, c: '#FFFFFF', r: 10 });
        } else if (f.k === 'text') { if (fx.text) texts.push({ x: f.x, y: f.y, s: f.s, t: 0 }); }
        else if (f.k === 'shake') { if (fx.shake) shake = Math.max(shake, f.a || 6); }
        else if (f.k === 'banner') { if (fx.banner) banner = { s: f.s, t: 0 }; }
      }
      w.fx.length = 0;
    }
    function draw(w, dt) {
      time += dt; eat(w);
      ctx.save();
      if (shake > 0.3) { ctx.translate((Math.random() - 0.5) * shake, (Math.random() - 0.5) * shake); shake *= 0.86; } else shake = 0;
      background(w);
      const cam = w.camY || 0;
      for (const e of w.ents) if (!e.dead && e.tag === 'platform') drawEnt(w, e, cam);
      for (const e of w.ents) if (!e.dead && e.tag !== 'platform') drawEnt(w, e, cam);
      drawHero(w, cam);
      for (let i = parts.length - 1; i >= 0; i--) {
        const p = parts[i]; p.t += dt;
        if (p.t > p.life) { parts.splice(i, 1); continue; }
        const k = 1 - p.t / p.life; ctx.globalAlpha = k;
        if (p.ring) { ctx.strokeStyle = p.c; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(p.x, p.y - cam, p.r + 20 * (1 - k), 0, 7); ctx.stroke(); }
        else { p.x += p.vx * dt; p.y += p.vy * dt; p.vy += 300 * dt; ctx.fillStyle = p.c; ctx.beginPath(); ctx.arc(p.x, p.y - cam, p.r * k + 0.5, 0, 7); ctx.fill(); }
      }
      ctx.globalAlpha = 1;
      ctx.font = '800 16px system-ui, sans-serif'; ctx.textAlign = 'center';
      for (let i = texts.length - 1; i >= 0; i--) {
        const t = texts[i]; t.t += dt; if (t.t > 0.9) { texts.splice(i, 1); continue; }
        ctx.globalAlpha = 1 - t.t / 0.9; ctx.lineWidth = 3; ctx.strokeStyle = dark ? 'rgba(0,0,0,.6)' : 'rgba(255,255,255,.85)'; ctx.fillStyle = dark ? '#FFE066' : '#C2410C';
        const y = t.y - cam - t.t * 36; ctx.strokeText(t.s, t.x, y); ctx.fillText(t.s, t.x, y);
      }
      ctx.globalAlpha = 1; ctx.textAlign = 'left';
      if (w.s.world && w.s.world.gravity < 0 && w.s.control !== 'runner' && w.s.control !== 'flappy') { /* гравитация бывает только у бегалок и леталок */ }
      hud(w);
      if (banner) {
        banner.t += dt; const k = banner.t < 0.25 ? banner.t / 0.25 : banner.t > 1.4 ? Math.max(0, 1 - (banner.t - 1.4) / 0.4) : 1;
        if (banner.t > 1.8) banner = null;
        else { ctx.globalAlpha = k; ctx.fillStyle = dark ? 'rgba(0,0,0,.45)' : 'rgba(255,255,255,.7)'; rr(ctx, 30, H / 2 - 34, W - 60, 56, 16); ctx.fill(); ctx.fillStyle = ink; ctx.font = '800 24px system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.fillText(banner.s, W / 2, H / 2 + 2); ctx.textAlign = 'left'; ctx.globalAlpha = 1; }
      }
      ctx.restore();
    }
    return { draw, play };
  }

  // ---------- полный код игры одним HTML-файлом ----------
  function exportHtml(spec, sources) {
    const esc = s => String(s).replace(/</g, '\\u003c');
    return '<!doctype html>\n<html lang="ru">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width,initial-scale=1">\n<title>' + String(spec.title).replace(/[<&]/g, '') + '</title>\n' +
      '<style>html,body{margin:0;height:100%;background:#0d1715;display:grid;place-items:center;font-family:system-ui,sans-serif}canvas{max-width:100vw;max-height:100vh;width:auto;height:100vh;aspect-ratio:3/4;touch-action:none;border-radius:12px}</style>\n</head>\n<body>\n<canvas id="game" width="720" height="960"></canvas>\n<script>\n' +
      '// Игра «' + String(spec.title).replace(/[\r\n]/g, ' ') + '» — её запрограммировал Амиго в режиме Кодекс.\n' +
      '// Чертёж игры: что в ней есть и как всё работает.\nconst SPEC = ' + esc(JSON.stringify(spec, null, 1)) + ';\n\n' +
      sources.engine + '\n\n' + sources.view + '\n\n' + sources.main + '\n\ncodexStandaloneMain(SPEC);\n<\/script>\n</body>\n</html>\n';
  }
  return { create, sprite, amigo, exportHtml, makeSound };
}

// запуск игры в отдельном файле (используется в выгруженном коде игры)
function codexStandaloneMain(spec) {
  const E = codexEngineModule(), V = codexViewModule(E);
  const cv = document.getElementById('game'), ctx = cv.getContext('2d');
  ctx.setTransform(cv.width / E.W, 0, 0, cv.height / E.H, 0, 0);
  let ac = null;
  const view = V.create(ctx, spec, { audio: () => ac });
  let world = new E.World(spec), state = 'start', last = performance.now();
  const inp = { pointer: { active: false, x: 0, y: 0 }, taps: [] };
  const KEY = { ArrowUp: 'up', KeyW: 'up', ArrowDown: 'down', KeyS: 'down', ArrowLeft: 'left', KeyA: 'left', ArrowRight: 'right', KeyD: 'right', Space: 'action', Enter: 'action', KeyE: 'second', ShiftLeft: 'second' };
  function begin() { if (!ac) { try { ac = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { ac = null; } } if (ac && ac.state === 'suspended') ac.resume(); if (state !== 'play') { world = new E.World(spec); state = 'play'; } }
  addEventListener('keydown', e => { const a = KEY[e.code]; if (!a) return; e.preventDefault(); if (state !== 'play') { if (a === 'action') begin(); return; } inp[a] = true; });
  addEventListener('keyup', e => { const a = KEY[e.code]; if (a) inp[a] = false; });
  const pos = e => { const r = cv.getBoundingClientRect(); return { x: (e.clientX - r.left) / r.width * E.W, y: (e.clientY - r.top) / r.height * E.H }; };
  cv.addEventListener('pointerdown', e => { e.preventDefault(); if (state !== 'play') return begin(); const p = pos(e); inp.pointer = { active: true, x: p.x, y: p.y }; inp.tap = true; inp.taps.push(p); });
  cv.addEventListener('pointermove', e => { const p = pos(e); if (inp.pointer.active || e.pointerType === 'mouse') inp.pointer = { active: inp.pointer.active || e.pointerType === 'mouse', x: p.x, y: p.y }; });
  addEventListener('pointerup', e => { inp.tap = false; if (e.pointerType !== 'mouse') inp.pointer.active = false; });
  function screen(title, sub) {
    ctx.fillStyle = 'rgba(0,0,0,.55)'; ctx.fillRect(0, 0, E.W, E.H);
    ctx.fillStyle = '#fff'; ctx.textAlign = 'center'; ctx.font = '800 26px system-ui, sans-serif'; ctx.fillText(title, E.W / 2, E.H / 2 - 30);
    ctx.font = '15px system-ui, sans-serif'; String(sub).split('\n').forEach((l, i) => ctx.fillText(l, E.W / 2, E.H / 2 + 6 + i * 22)); ctx.textAlign = 'left';
  }
  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    if (state === 'play') { world.update(dt, inp); inp.taps = []; if (world.over) state = 'over'; }
    view.draw(world, dt);
    if (state === 'start') screen(spec.title, (spec.help || '') + '\n\nНажми, чтобы начать');
    if (state === 'over') screen(world.over.win ? 'Победа! 🏆' : 'Игра окончена', 'Очки: ' + world.score + '\nНажми, чтобы сыграть ещё');
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}
const CodexView = codexViewModule(CodexEngine);

// Игра Кодекса внутри карточки чата (та же карточка, что у встроенных игр)
GAMES.codex = function (c) {
  const spec = c.opts, E = CodexEngine;
  const { cv, ctx } = GameKit.canvas(c.stage, E.W, E.H);
  const view = CodexView.create(ctx, spec, { audio: () => c.audio && c.audio() });
  const inp = { pointer: { active: false, x: E.W / 2, y: E.H / 2 }, taps: [] };
  let world = null, lastDt = 0.016, infoT = 0;
  const pos = e => GameKit.pos(cv, e, E.W, E.H);
  cv.addEventListener('pointerdown', e => { const p = pos(e); inp.pointer = { active: true, x: p.x, y: p.y }; inp.tap = true; inp.taps.push(p); try { cv.setPointerCapture(e.pointerId); } catch (er) { /* нет захвата */ } });
  cv.addEventListener('pointermove', e => { const p = pos(e); if (inp.pointer.active || e.pointerType === 'mouse') inp.pointer = { active: true, x: p.x, y: p.y }; });
  const up = e => { inp.tap = false; if (e.pointerType !== 'mouse') inp.pointer.active = false; };
  cv.addEventListener('pointerup', up); cv.addEventListener('pointercancel', up);
  cv.addEventListener('pointerleave', e => { if (e.pointerType === 'mouse') inp.pointer.active = false; });
  const second = (spec.abilities || []).filter(a => a.button === 'second' || a.button === 'down').map(a => [a.label || '⚡', a.button]);
  const pads = {
    horizontal: [['◀', 'left', 1], ['▶', 'right', 1]], jumper: [['◀', 'left', 1], ['▶', 'right', 1]], lanes: [['◀', 'left'], ['▶', 'right']],
    runner: [['⤒ Прыжок', 'action']], flappy: [['⤒ Вверх', 'action']], free: 'dpad', topdown: 'dpad', tap: null,
  };
  let pad = pads[spec.control];
  if (second.length) pad = (pad === 'dpad' ? [['▲', 'up'], ['◀', 'left'], ['▼', 'down'], ['▶', 'right']] : (pad || [])).concat(second);
  function info() {
    const w = world, bits = [];
    if (w.s.levelEvery || w.s.genre === 'topdown') bits.push('Уровень ' + w.level);
    if (w.maxCombo >= 6) bits.push('лучшее комбо ' + w.maxCombo);
    c.info(bits.length ? bits.join(' · ') : spec.help);
  }
  return {
    realtime: true, pad, scoreLabel: spec.control === 'jumper' ? 'Высота' : 'Очки',
    reset() { world = new E.World(spec); inp.taps = []; c.score(0); c.info(spec.help); view.draw(world, 0); },
    input(a, down) { if (!['left', 'right', 'up', 'down', 'action', 'second'].includes(a)) return false; inp[a] = down; return true; },
    update(dt) {
      lastDt = dt / 1000;
      world.update(lastDt, inp); inp.taps = [];
      if (world.score !== c.points) c.score(world.score);
      infoT -= lastDt; if (infoT <= 0) { infoT = 0.5; info(); }
      if (world.over) { const o = world.over; view.draw(world, lastDt); c.over(o.text || (o.win ? 'Победа! 🏆' : U.pick(['Игра окончена!', 'Ой! Попробуй ещё раз'])), o.win ? 'win' : undefined); }
    },
    draw() { if (world) view.draw(world, lastDt); },
    world: () => world,
  };
};
