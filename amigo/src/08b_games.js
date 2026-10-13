/* ===== 08b_games.js ===== */
// Игры прямо в чате: общий движок карточки и десять игр. Названия и подсказки — в 05c_gamelist.js.
const GameKit = (() => {
  const css = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
  function palette() {
    return { bg: css('--surface-2'), ink: css('--ink'), muted: css('--muted'), line: css('--line'), accent: css('--accent'), coral: css('--coral'),
      teal: css('--teal'), surface: css('--surface'), user: css('--user'), mono: css('--f-mono') || 'monospace', display: css('--f-display') || 'sans-serif' };
  }
  function canvas(stage, W, H) {
    const cv = document.createElement('canvas'), dpr = Math.min(2, window.devicePixelRatio || 1);
    cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
    cv.className = 'game-canvas'; cv.style.aspectRatio = W + ' / ' + H; cv.style.maxWidth = Math.round(W * 1.3) + 'px';
    const ctx = cv.getContext('2d'); ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    stage.appendChild(cv);
    return { cv, ctx, W, H };
  }
  function pos(cv, e, W, H) { const r = cv.getBoundingClientRect(); return { x: (e.clientX - r.left) / r.width * W, y: (e.clientY - r.top) / r.height * H }; }
  // свайпы и касания: cb('left' | 'right' | 'up' | 'down' | 'tap')
  function swipe(el, cb) {
    let sx = null, sy = 0;
    el.addEventListener('pointerdown', e => { if (e.target.closest('button')) return; sx = e.clientX; sy = e.clientY; });
    el.addEventListener('pointerup', e => {
      if (sx == null) return;
      const dx = e.clientX - sx, dy = e.clientY - sy; sx = null;
      if (Math.max(Math.abs(dx), Math.abs(dy)) < 22) return cb('tap');
      cb(Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 'right' : 'left') : (dy > 0 ? 'down' : 'up'));
    });
    el.addEventListener('pointercancel', () => { sx = null; });
  }
  const KEY = { ArrowUp: 'up', KeyW: 'up', ArrowDown: 'down', KeyS: 'down', ArrowLeft: 'left', KeyA: 'left', ArrowRight: 'right', KeyD: 'right',
    Space: 'action', Enter: 'action', KeyX: 'rotate', KeyZ: 'rotate', KeyE: 'second', ShiftLeft: 'second', ShiftRight: 'second' };
  function rr(ctx, x, y, w, h, r) {
    r = Math.min(r, w / 2, h / 2);
    ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  }
  const ri = n => Math.floor(Math.random() * n);
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  function el(tag, cls, parent) { const e = document.createElement(tag); if (cls) e.className = cls; if (parent) parent.appendChild(e); return e; }
  // мордочка Амиго — для «Летучего Амиго» и мяча
  function amigo(ctx, x, y, r, P, tilt) {
    ctx.save(); ctx.translate(x, y); ctx.rotate(tilt || 0);
    ctx.strokeStyle = P.ink; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(0, -r); ctx.lineTo(0, -r - 6); ctx.stroke();
    ctx.fillStyle = P.coral; ctx.beginPath(); ctx.arc(0, -r - 7, 3, 0, 7); ctx.fill();
    ctx.fillStyle = P.accent; ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.fill();
    for (const s of [-1, 1]) { ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.ellipse(s * r * 0.38, -r * 0.1, r * 0.24, r * 0.3, 0, 0, 7); ctx.fill(); ctx.fillStyle = '#10302D'; ctx.beginPath(); ctx.arc(s * r * 0.38 + 1, -r * 0.05, r * 0.13, 0, 7); ctx.fill(); }
    ctx.strokeStyle = '#10302D'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(0, r * 0.25, r * 0.35, 0.15 * Math.PI, 0.85 * Math.PI); ctx.stroke();
    ctx.restore();
  }
  return { palette, canvas, pos, swipe, KEY, rr, ri, clamp, el, amigo };
})();

const GAMES = {
  // ---------- Змейка ----------
  snake(c) {
    const N = 17, S = 20, W = N * S, H = W, { ctx } = GameKit.canvas(c.stage, W, H);
    const speed = c.opts.speed || 1, wrap = !!c.opts.wrap, color = c.opts.color;
    const DIRS = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] };
    let s, dir, q, food, acc, delay, alive, P;
    function place() { do food = [GameKit.ri(N), GameKit.ri(N)]; while (s.some(p => p[0] === food[0] && p[1] === food[1])); }
    function die() { alive = false; g.draw(); c.over(U.pick(['Ой! Змейка врезалась 💥', 'Бам! Попробуй ещё раз 🐍'])); }
    function step() {
      if (q.length) dir = q.shift();
      let x = s[0][0] + dir[0], y = s[0][1] + dir[1];
      if (wrap) { x = (x + N) % N; y = (y + N) % N; } else if (x < 0 || y < 0 || x >= N || y >= N) return die();
      const eat = x === food[0] && y === food[1];
      if (!eat) s.pop();
      if (s.some(p => p[0] === x && p[1] === y)) return die();
      s.unshift([x, y]);
      if (eat) {
        c.score(c.points + 1); delay = Math.max(55, delay - 3);
        if (s.length >= N * N) { alive = false; return c.over('Ты заполнил всё поле! 🏆', 'win'); }
        place();
      }
    }
    const g = {
      realtime: true, pad: 'dpad',
      reset() { s = [[8, 8], [7, 8], [6, 8]]; dir = [1, 0]; q = []; acc = 0; delay = 150 / speed; alive = true; P = c.pal(); place(); c.score(0); c.info(wrap ? 'Стен нет: можно проходить насквозь' : 'Не врезайся в стены и в себя'); },
      input(a, down) {
        if (!down) return false;
        const v = DIRS[a]; if (!v) return false;
        const last = q.length ? q[q.length - 1] : dir;
        if ((v[0] === -last[0] && v[1] === -last[1]) || (v[0] === last[0] && v[1] === last[1])) return true;
        if (q.length < 3) q.push(v);
        return true;
      },
      _dbg: () => ({ s, food, alive }),
      update(dt) { if (!alive) return; acc += dt; while (acc >= delay && alive) { acc -= delay; step(); } },
      draw() {
        ctx.fillStyle = P.bg; ctx.fillRect(0, 0, W, H);
        ctx.fillStyle = P.line; ctx.globalAlpha = 0.35;
        for (let y = 0; y < N; y++) for (let x = (y % 2); x < N; x += 2) ctx.fillRect(x * S, y * S, S, S);
        ctx.globalAlpha = 1;
        // яблоко
        const fx = food[0] * S + S / 2, fy = food[1] * S + S / 2;
        ctx.fillStyle = P.coral; ctx.beginPath(); ctx.arc(fx, fy + 1, S * 0.38, 0, 7); ctx.fill();
        ctx.fillStyle = P.teal; ctx.beginPath(); ctx.ellipse(fx + 3, fy - S * 0.36, 4, 2, -0.6, 0, 7); ctx.fill();
        s.forEach((p, i) => {
          ctx.fillStyle = color === 'rainbow' ? `hsl(${(i * 23) % 360} 75% 52%)` : (color || P.teal);
          if (i === 0) ctx.globalAlpha = 1; else ctx.globalAlpha = Math.max(0.55, 1 - i * 0.02);
          GameKit.rr(ctx, p[0] * S + 1, p[1] * S + 1, S - 2, S - 2, i === 0 ? 7 : 5); ctx.fill();
        });
        ctx.globalAlpha = 1;
        const [hx, hy] = s[0], cx = hx * S + S / 2, cy = hy * S + S / 2;
        for (const k of [-1, 1]) {
          const ex = cx + dir[0] * 4 + dir[1] * k * 4, ey = cy + dir[1] * 4 + dir[0] * k * 4;
          ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(ex, ey, 3.2, 0, 7); ctx.fill();
          ctx.fillStyle = '#10302D'; ctx.beginPath(); ctx.arc(ex + dir[0] * 1.2, ey + dir[1] * 1.2, 1.6, 0, 7); ctx.fill();
        }
      },
    };
    GameKit.swipe(c.stage, d => { if (d !== 'tap') g.input(d, true); });
    return g;
  },

  // ---------- Тетрис ----------
  tetris(c) {
    const C = 10, R = 20, S = 18, SIDE = 92, W = C * S + SIDE, H = R * S, { ctx } = GameKit.canvas(c.stage, W, H);
    const SH = { I: [[1, 1, 1, 1]], O: [[1, 1], [1, 1]], T: [[0, 1, 0], [1, 1, 1]], S: [[0, 1, 1], [1, 1, 0]], Z: [[1, 1, 0], [0, 1, 1]], J: [[1, 0, 0], [1, 1, 1]], L: [[0, 0, 1], [1, 1, 1]] };
    const COL = { I: '#2AA7D8', O: '#E0B000', T: '#8E44AD', S: '#2E9D4E', Z: '#E53935', J: '#1E63D6', L: '#F07B16' };
    const speed = c.opts.speed || 1;
    let B, cur, next, bag, acc, lines, level, alive, P;
    const take = () => { if (!bag || !bag.length) bag = U.shuffle(Object.keys(SH)); return bag.pop(); };
    function hit(m, x, y) {
      for (let i = 0; i < m.length; i++) for (let j = 0; j < m[i].length; j++) if (m[i][j]) {
        const yy = y + i, xx = x + j;
        if (xx < 0 || xx >= C || yy >= R || (yy >= 0 && B[yy][xx])) return true;
      }
      return false;
    }
    function spawn() {
      const k = next || take(); next = take();
      cur = { k, m: SH[k].map(r => r.slice()), x: Math.floor((C - SH[k][0].length) / 2), y: 0 };
      if (hit(cur.m, cur.x, cur.y)) { alive = false; g.draw(); c.over(`Линий собрано: ${lines}`); }
    }
    const rot = m => m[0].map((_, i) => m.map(r => r[i]).reverse());
    function info() { c.info(`Линии: ${lines} · Уровень: ${level}`); }
    function lock() {
      cur.m.forEach((r, i) => r.forEach((v, j) => { if (v && cur.y + i >= 0) B[cur.y + i][cur.x + j] = COL[cur.k]; }));
      let n = 0;
      for (let y = R - 1; y >= 0; y--) if (B[y].every(Boolean)) { B.splice(y, 1); B.unshift(Array(C).fill(0)); n++; y++; }
      if (n) { lines += n; c.score(c.points + [0, 100, 300, 500, 800][n] * level); level = 1 + Math.floor(lines / 10); info(); }
      spawn();
    }
    function down() { if (!hit(cur.m, cur.x, cur.y + 1)) { cur.y++; return true; } lock(); return false; }
    function hard() { let n = 0; while (!hit(cur.m, cur.x, cur.y + 1)) { cur.y++; n++; } c.score(c.points + n * 2); lock(); acc = 0; }
    function rotate() { const m = rot(cur.m); for (const k of [0, -1, 1, -2, 2]) if (!hit(m, cur.x + k, cur.y)) { cur.m = m; cur.x += k; return; } }
    function cell(x, y, col, a) { ctx.globalAlpha = a == null ? 1 : a; ctx.fillStyle = col; GameKit.rr(ctx, x + 1, y + 1, S - 2, S - 2, 4); ctx.fill(); ctx.globalAlpha = 1; }
    const g = {
      realtime: true, pad: [['←', 'left', 1], ['⟳', 'up'], ['→', 'right', 1], ['↓', 'down', 1], ['⤓', 'action']],
      reset() { B = Array.from({ length: R }, () => Array(C).fill(0)); bag = null; next = null; lines = 0; level = 1; acc = 0; alive = true; P = c.pal(); c.score(0); info(); spawn(); },
      input(a, d) {
        if (!d || !alive) return false;
        if (a === 'left' || a === 'right') { const dx = a === 'left' ? -1 : 1; if (!hit(cur.m, cur.x + dx, cur.y)) cur.x += dx; }
        else if (a === 'up' || a === 'rotate') rotate();
        else if (a === 'down') { if (down()) c.score(c.points + 1); acc = 0; }
        else if (a === 'action') hard();
        else return false;
        g.draw(); return true;
      },
      update(dt) { if (!alive) return; acc += dt; const d = Math.max(70, 800 - (level - 1) * 70) / speed; while (acc >= d && alive) { acc -= d; down(); } },
      draw() {
        ctx.fillStyle = P.bg; ctx.fillRect(0, 0, W, H);
        ctx.fillStyle = P.surface; ctx.fillRect(0, 0, C * S, H);
        ctx.strokeStyle = P.line; ctx.lineWidth = 1; ctx.globalAlpha = 0.6;
        for (let x = 1; x < C; x++) { ctx.beginPath(); ctx.moveTo(x * S + 0.5, 0); ctx.lineTo(x * S + 0.5, H); ctx.stroke(); }
        ctx.globalAlpha = 1;
        for (let y = 0; y < R; y++) for (let x = 0; x < C; x++) if (B[y][x]) cell(x * S, y * S, B[y][x]);
        if (alive && cur) {
          let gy = cur.y; while (!hit(cur.m, cur.x, gy + 1)) gy++;
          cur.m.forEach((r, i) => r.forEach((v, j) => { if (v) cell((cur.x + j) * S, (gy + i) * S, COL[cur.k], 0.22); }));
          cur.m.forEach((r, i) => r.forEach((v, j) => { if (v && cur.y + i >= 0) cell((cur.x + j) * S, (cur.y + i) * S, COL[cur.k]); }));
        }
        const sx = C * S + 12;
        ctx.fillStyle = P.muted; ctx.font = `600 11px ${P.mono}`; ctx.textBaseline = 'top';
        ctx.fillText('ДАЛЬШЕ', sx, 10);
        if (next) SH[next].forEach((r, i) => r.forEach((v, j) => { if (v) { ctx.fillStyle = COL[next]; GameKit.rr(ctx, sx + j * 15, 30 + i * 15, 13, 13, 3); ctx.fill(); } }));
        ctx.fillStyle = P.muted; ctx.fillText('УРОВЕНЬ', sx, 84); ctx.fillStyle = P.ink; ctx.font = `700 20px ${P.mono}`; ctx.fillText(String(level), sx, 100);
        ctx.fillStyle = P.muted; ctx.font = `600 11px ${P.mono}`; ctx.fillText('ЛИНИИ', sx, 134); ctx.fillStyle = P.ink; ctx.font = `700 20px ${P.mono}`; ctx.fillText(String(lines), sx, 150);
      },
    };
    GameKit.swipe(c.stage, d => g.input(d === 'tap' ? 'up' : d === 'down' ? 'action' : d === 'up' ? 'up' : d, true));
    return g;
  },

  // ---------- 2048 ----------
  g2048(c) {
    const N = 4, box = GameKit.el('div', 'g2048', c.stage), cells = [];
    for (let i = 0; i < N * N; i++) cells.push(GameKit.el('div', 't', box));
    let G, alive, won;
    function add() { const e = []; G.forEach((v, i) => { if (!v) e.push(i); }); if (e.length) G[e[GameKit.ri(e.length)]] = Math.random() < 0.9 ? 2 : 4; }
    function render() {
      cells.forEach((d, i) => {
        const v = G[i];
        d.textContent = v || '';
        d.style.background = v ? `color-mix(in srgb, var(--accent) ${Math.min(100, Math.round(Math.log2(v) * 9))}%, var(--surface))` : '';
        d.style.color = v >= 64 ? 'var(--accent-ink)' : '';
        d.style.fontSize = v >= 1024 ? '1.1rem' : v >= 128 ? '1.35rem' : '1.7rem';
      });
    }
    function line(idx) {
      const vals = idx.map(i => G[i]).filter(Boolean), out = []; let gain = 0;
      for (let i = 0; i < vals.length; i++) { if (vals[i] === vals[i + 1]) { out.push(vals[i] * 2); gain += vals[i] * 2; i++; } else out.push(vals[i]); }
      while (out.length < N) out.push(0);
      let moved = false; idx.forEach((i, k) => { if (G[i] !== out[k]) moved = true; G[i] = out[k]; });
      return { moved, gain };
    }
    function canMove() {
      if (G.includes(0)) return true;
      for (let r = 0; r < N; r++) for (let q = 0; q < N; q++) { const v = G[r * N + q]; if ((q + 1 < N && G[r * N + q + 1] === v) || (r + 1 < N && G[(r + 1) * N + q] === v)) return true; }
      return false;
    }
    function move(d) {
      let moved = false, gain = 0;
      for (let k = 0; k < N; k++) {
        const idx = [];
        for (let j = 0; j < N; j++) idx.push(d === 'left' ? k * N + j : d === 'right' ? k * N + (N - 1 - j) : d === 'up' ? j * N + k : (N - 1 - j) * N + k);
        const r = line(idx); moved = moved || r.moved; gain += r.gain;
      }
      if (!moved) return;
      add(); c.score(c.points + gain); render();
      if (!won && G.includes(2048)) { won = true; c.toast('🎉 Ты собрал 2048! Можно играть дальше.'); }
      if (!canMove()) { alive = false; c.over(`Самая большая плитка: ${Math.max(...G)}`); }
    }
    const g = {
      realtime: false, pad: 'dpad',
      reset() { G = Array(N * N).fill(0); alive = true; won = false; add(); add(); c.score(0); c.info('Соединяй одинаковые числа'); render(); },
      input(a, d) { if (!d || !alive || !['up', 'down', 'left', 'right'].includes(a)) return false; move(a); return true; },
    };
    GameKit.swipe(c.stage, d => { if (d !== 'tap') g.input(d, true); });
    return g;
  },

  // ---------- Крестики-нолики ----------
  ttt(c) {
    const box = GameKit.el('div', 'ttt', c.stage), btns = [];
    const L = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]];
    const hard = (c.opts.speed || 1) > 1.2, easy = (c.opts.speed || 1) < 0.9;
    let B, turn, alive, round = 0, wins = 0, losses = 0, draws = 0, timer = 0;
    const line = b => { for (const l of L) if (b[l[0]] && b[l[0]] === b[l[1]] && b[l[0]] === b[l[2]]) return l; return null; };
    const winner = b => { const l = line(b); return l ? b[l[0]] : b.every(Boolean) ? 'draw' : null; };
    function minimax(b, me, depth) {
      const w = winner(b);
      if (w === 'O') return { s: 10 - depth }; if (w === 'X') return { s: depth - 10 }; if (w === 'draw') return { s: 0 };
      let best = { s: me ? -99 : 99, i: -1 };
      for (let i = 0; i < 9; i++) if (!b[i]) {
        b[i] = me ? 'O' : 'X'; const r = minimax(b, !me, depth + 1); b[i] = '';
        if (me ? r.s > best.s : r.s < best.s) best = { s: r.s, i };
      }
      return best;
    }
    function render() {
      const l = line(B);
      btns.forEach((b, i) => { b.textContent = B[i] === 'X' ? '✕' : B[i] === 'O' ? '◯' : ''; b.className = (B[i] === 'X' ? 'x' : B[i] === 'O' ? 'o' : '') + (l && l.includes(i) ? ' win' : ''); b.setAttribute('aria-label', B[i] ? (B[i] === 'X' ? 'крестик' : 'нолик') : 'пусто'); });
      c.info(`Ты ${wins} : ${losses} Амиго · ничьих ${draws}`);
    }
    function finish() {
      const w = winner(B); if (!w) return false;
      alive = false;
      if (w === 'X') { wins++; c.score(wins); c.over('Ты победил! 🎉', 'win'); }
      else if (w === 'O') { losses++; c.over('Амиго победил 😎 Попробуй ещё!', 'lose'); }
      else { draws++; c.over('Ничья 🤝', 'lose'); }
      render(); return true;
    }
    function amigoMove() {
      if (!alive) return;
      const empty = B.map((v, i) => v ? -1 : i).filter(i => i >= 0);
      const smart = hard || Math.random() < (easy ? 0.45 : 0.8);
      const i = smart ? minimax(B.slice(), true, 0).i : empty[GameKit.ri(empty.length)];
      B[i] = 'O'; turn = 'X'; render(); finish();
    }
    for (let i = 0; i < 9; i++) {
      const b = GameKit.el('button', '', box); b.type = 'button'; btns.push(b);
      b.addEventListener('click', () => {
        if (!alive || turn !== 'X' || B[i]) return;
        B[i] = 'X'; turn = 'O'; render();
        if (!finish()) timer = setTimeout(amigoMove, 380);
      });
    }
    return {
      realtime: false, scoreLabel: 'Победы',
      reset() {
        clearTimeout(timer); B = Array(9).fill(''); alive = true; round++;
        turn = round % 2 ? 'X' : 'O'; c.score(wins); render();
        if (turn === 'O') timer = setTimeout(amigoMove, 450);
      },
      input() { return false; },
      destroy() { clearTimeout(timer); },
    };
  },

  // ---------- Сапёр ----------
  mines(c) {
    const N = 9, M = 10, box = GameKit.el('div', 'mines', c.stage), btns = [];
    const tools = GameKit.el('div', 'game-tools', c.stage);
    const flagBtn = GameKit.el('button', 'chip', tools); flagBtn.type = 'button';
    let mine, open, flag, started, alive, t0, timer, flagMode = false, pressT = 0, longPressed = false;
    const nb = i => { const x = i % N, y = Math.floor(i / N), out = []; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const xx = x + dx, yy = y + dy; if ((dx || dy) && xx >= 0 && yy >= 0 && xx < N && yy < N) out.push(yy * N + xx); } return out; };
    const count = i => nb(i).filter(j => mine[j]).length;
    const secs = () => started ? Math.floor((Date.now() - t0) / 1000) : 0;
    function info() { c.info(`💣 ${M - flag.filter(Boolean).length} · ⏱ ${secs()} с`); }
    function setFlagMode(v) { flagMode = v; flagBtn.textContent = flagMode ? '🚩 Режим флажков: вкл' : '🚩 Режим флажков: выкл'; flagBtn.setAttribute('aria-pressed', v ? 'true' : 'false'); }
    function render(reveal) {
      btns.forEach((b, i) => {
        b.className = ''; b.textContent = '';
        if (open[i]) { b.classList.add('op'); const n = count(i); if (n) { b.textContent = n; b.dataset.n = n; } }
        else if (flag[i]) b.textContent = '🚩';
        if (reveal && mine[i]) { b.textContent = '💣'; if (open[i]) b.classList.add('boom'); }
      });
      info();
    }
    function start(first) {
      const ban = new Set([first, ...nb(first)]);
      let k = 0; while (k < M) { const i = GameKit.ri(N * N); if (!mine[i] && !ban.has(i)) { mine[i] = true; k++; } }
      started = true; t0 = Date.now(); timer = setInterval(info, 1000);
    }
    function reveal(i) {
      if (!alive || open[i] || flag[i]) return;
      if (!started) start(i);
      if (mine[i]) { open[i] = true; alive = false; clearInterval(timer); render(true); return c.over('Бум! 💥 Попробуй ещё раз', 'lose'); }
      const st = [i];
      while (st.length) { const j = st.pop(); if (open[j] || flag[j]) continue; open[j] = true; if (!count(j)) for (const k of nb(j)) if (!open[k] && !mine[k]) st.push(k); }
      render();
      if (open.filter(Boolean).length === N * N - M) { alive = false; clearInterval(timer); const s = secs(); c.score(s); render(true); c.over(`Победа за ${s} с! 🎉`, 'win'); }
    }
    function toggleFlag(i) { if (!alive || open[i]) return; flag[i] = !flag[i]; render(); }
    for (let i = 0; i < N * N; i++) {
      const b = GameKit.el('button', '', box); b.type = 'button'; btns.push(b);
      b.addEventListener('pointerdown', () => { longPressed = false; clearTimeout(pressT); pressT = setTimeout(() => { longPressed = true; toggleFlag(i); if (navigator.vibrate) navigator.vibrate(30); }, 430); });
      b.addEventListener('pointerup', () => clearTimeout(pressT));
      b.addEventListener('pointerleave', () => clearTimeout(pressT));
      b.addEventListener('click', () => { if (longPressed) { longPressed = false; return; } if (flagMode) toggleFlag(i); else reveal(i); });
      b.addEventListener('contextmenu', e => { e.preventDefault(); clearTimeout(pressT); if (!longPressed) toggleFlag(i); longPressed = false; });
    }
    flagBtn.addEventListener('click', () => setFlagMode(!flagMode));
    return {
      realtime: false, lowBetter: true, scoreLabel: 'Время',
      reset() { clearInterval(timer); mine = Array(N * N).fill(false); open = Array(N * N).fill(false); flag = Array(N * N).fill(false); started = false; alive = true; setFlagMode(false); c.score(0); render(); },
      input() { return false; },
      destroy() { clearInterval(timer); clearTimeout(pressT); },
    };
  },

  // ---------- Найди пару ----------
  memory(c) {
    const box = GameKit.el('div', 'memory', c.stage), btns = [];
    const EMO = ['🐶', '🐱', '🦊', '🐸', '🐵', '🐙', '🦄', '🐝', '🐼', '🦁', '🐧', '🐢'];
    let deck, up, done, moves, lock, timer = 0, alive;
    function render() { btns.forEach((b, i) => { const show = up.includes(i) || done[i]; b.textContent = show ? deck[i] : ''; b.className = done[i] ? 'done' : show ? 'up' : ''; b.setAttribute('aria-label', show ? deck[i] : 'закрытая карточка'); }); c.info(`Ходов: ${moves} · Найдено пар: ${done.filter(Boolean).length / 2} из 8`); }
    for (let i = 0; i < 16; i++) {
      const b = GameKit.el('button', '', box); b.type = 'button'; btns.push(b);
      b.addEventListener('click', () => {
        if (!alive || lock || done[i] || up.includes(i)) return;
        up.push(i); render();
        if (up.length < 2) return;
        moves++; c.score(moves);
        const [a, b2] = up;
        if (deck[a] === deck[b2]) {
          done[a] = done[b2] = true; up = []; render();
          if (done.every(Boolean)) { alive = false; c.over(`Все пары найдены за ${moves} ходов! 🎉`, 'win'); }
        } else { lock = true; timer = setTimeout(() => { up = []; lock = false; render(); }, 750); }
      });
    }
    return {
      realtime: false, lowBetter: true, scoreLabel: 'Ходы',
      reset() { clearTimeout(timer); const e = U.shuffle(EMO.slice()).slice(0, 8); deck = U.shuffle(e.concat(e)); up = []; done = Array(16).fill(false); moves = 0; lock = false; alive = true; c.score(0); render(); },
      input() { return false; },
      destroy() { clearTimeout(timer); },
    };
  },

  // ---------- Арканоид ----------
  breakout(c) {
    const W = 320, H = 400, { cv, ctx } = GameKit.canvas(c.stage, W, H), speed = c.opts.speed || 1;
    const COLS = 8, ROWS = 5, BW = (W - 20) / COLS, BH = 16;
    let pad, ball, bricks, lives, level, held, alive, P;
    function build() {
      const cols = [P.coral, '#F07B16', P.accent, '#2E9D4E', P.teal, '#1E63D6'];
      bricks = [];
      for (let r = 0; r < ROWS + Math.min(3, level - 1); r++) for (let q = 0; q < COLS; q++) bricks.push({ x: 10 + q * BW + 2, y: 44 + r * (BH + 5), w: BW - 4, h: BH, col: cols[r % cols.length], on: true });
    }
    function serve() { ball = { x: pad.x, y: pad.y - 12, vx: 0, vy: 0, r: 6, stuck: true }; }
    function launch() { if (!ball.stuck) return; const v = (0.24 + 0.025 * level) * speed, a = -Math.PI / 2 + (Math.random() - 0.5) * 0.8; ball.vx = Math.cos(a) * v; ball.vy = Math.sin(a) * v; ball.stuck = false; }
    function info() { c.info('❤️'.repeat(Math.max(0, lives)) + ` · Уровень ${level}`); }
    const g = {
      realtime: true, pad: [['◀', 'left', 1], ['🚀', 'action'], ['▶', 'right', 1]],
      reset() { P = c.pal(); pad = { x: W / 2, y: H - 22, w: 72, h: 10 }; held = {}; lives = 3; level = 1; alive = true; build(); serve(); c.score(0); info(); },
      input(a, d) { if (a === 'left' || a === 'right') { held[a] = d; return true; } if ((a === 'action' || a === 'up') && d) { launch(); return true; } return false; },
      update(dt) {
        if (!alive) return;
        if (held.left) pad.x -= 0.42 * dt; if (held.right) pad.x += 0.42 * dt;
        pad.x = GameKit.clamp(pad.x, pad.w / 2, W - pad.w / 2);
        if (ball.stuck) { ball.x = pad.x; ball.y = pad.y - 12; return; }
        const steps = Math.ceil(dt / 6);
        for (let s = 0; s < steps; s++) {
          const st = dt / steps;
          ball.x += ball.vx * st; ball.y += ball.vy * st;
          if (ball.x < ball.r) { ball.x = ball.r; ball.vx = Math.abs(ball.vx); }
          if (ball.x > W - ball.r) { ball.x = W - ball.r; ball.vx = -Math.abs(ball.vx); }
          if (ball.y < ball.r) { ball.y = ball.r; ball.vy = Math.abs(ball.vy); }
          if (ball.vy > 0 && ball.y + ball.r >= pad.y - pad.h / 2 && ball.y - ball.r <= pad.y + pad.h / 2 && Math.abs(ball.x - pad.x) <= pad.w / 2 + ball.r) {
            const k = GameKit.clamp((ball.x - pad.x) / (pad.w / 2), -1, 1), v = Math.hypot(ball.vx, ball.vy), a = -Math.PI / 2 + k * 1.05;
            ball.vx = Math.cos(a) * v; ball.vy = Math.sin(a) * v; ball.y = pad.y - pad.h / 2 - ball.r;
          }
          for (const b of bricks) if (b.on && ball.x + ball.r > b.x && ball.x - ball.r < b.x + b.w && ball.y + ball.r > b.y && ball.y - ball.r < b.y + b.h) {
            b.on = false; c.score(c.points + 10);
            const ox = Math.min(ball.x + ball.r - b.x, b.x + b.w - ball.x + ball.r), oy = Math.min(ball.y + ball.r - b.y, b.y + b.h - ball.y + ball.r);
            if (ox < oy) ball.vx = -ball.vx; else ball.vy = -ball.vy;
            break;
          }
          if (ball.y > H + 20) {
            lives--; info();
            if (lives <= 0) { alive = false; g.draw(); return c.over(`Ты дошёл до уровня ${level}`); }
            serve(); return;
          }
        }
        if (bricks.every(b => !b.on)) { level++; build(); serve(); info(); c.toast(`Уровень ${level}! 🚀`); }
      },
      draw() {
        ctx.fillStyle = P.bg; ctx.fillRect(0, 0, W, H);
        for (const b of bricks) if (b.on) { ctx.fillStyle = b.col; GameKit.rr(ctx, b.x, b.y, b.w, b.h, 4); ctx.fill(); }
        ctx.fillStyle = P.user; GameKit.rr(ctx, pad.x - pad.w / 2, pad.y - pad.h / 2, pad.w, pad.h, 5); ctx.fill();
        ctx.fillStyle = P.accent; ctx.beginPath(); ctx.arc(ball.x, ball.y, ball.r, 0, 7); ctx.fill();
        ctx.strokeStyle = P.ink; ctx.lineWidth = 1.5; ctx.stroke();
        if (ball.stuck && alive) { ctx.fillStyle = P.muted; ctx.font = `13px ${P.mono}`; ctx.textAlign = 'center'; ctx.fillText('Нажми, чтобы запустить мяч', W / 2, H / 2 + 40); ctx.textAlign = 'left'; }
      },
    };
    const follow = e => { if (!alive) return; pad.x = GameKit.clamp(GameKit.pos(cv, e, W, H).x, pad.w / 2, W - pad.w / 2); };
    cv.addEventListener('pointermove', follow);
    cv.addEventListener('pointerdown', e => { follow(e); launch(); });
    return g;
  },

  // ---------- Понг ----------
  pong(c) {
    const W = 320, H = 420, { cv, ctx } = GameKit.canvas(c.stage, W, H), speed = c.opts.speed || 1, WIN = 7;
    let me, ai, ball, you, amigo, held, alive, wait, P;
    function serve(dir) { ball = { x: W / 2, y: H / 2, vx: (Math.random() - 0.5) * 0.24 * speed, vy: dir * 0.22 * speed, r: 7 }; wait = 700; }
    function info() { c.info(`Ты ${you} : ${amigo} Амиго · до ${WIN} очков`); }
    function hitPaddle(p, down) {
      const k = GameKit.clamp((ball.x - p.x) / (p.w / 2), -1, 1), v = Math.min(0.62 * speed, Math.hypot(ball.vx, ball.vy) * 1.06), a = k * 1.0;
      ball.vx = Math.sin(a) * v; ball.vy = (down ? 1 : -1) * Math.cos(a) * v;
    }
    const g = {
      realtime: true, pad: [['◀', 'left', 1], ['▶', 'right', 1]],
      reset() { P = c.pal(); me = { x: W / 2, y: H - 20, w: 70, h: 10 }; ai = { x: W / 2, y: 20, w: 70, h: 10 }; you = 0; amigo = 0; held = {}; alive = true; serve(1); c.score(0); info(); },
      input(a, d) { if (a === 'left' || a === 'right') { held[a] = d; return true; } return false; },
      update(dt) {
        if (!alive) return;
        if (held.left) me.x -= 0.45 * dt; if (held.right) me.x += 0.45 * dt;
        me.x = GameKit.clamp(me.x, me.w / 2, W - me.w / 2);
        const target = ball.vy < 0 ? ball.x : W / 2, mv = 0.2 * speed * dt;
        ai.x += GameKit.clamp(target - ai.x, -mv, mv); ai.x = GameKit.clamp(ai.x, ai.w / 2, W - ai.w / 2);
        if (wait > 0) { wait -= dt; return; }
        const steps = Math.ceil(dt / 6);
        for (let s = 0; s < steps; s++) {
          const st = dt / steps; ball.x += ball.vx * st; ball.y += ball.vy * st;
          if (ball.x < ball.r || ball.x > W - ball.r) { ball.vx = -ball.vx; ball.x = GameKit.clamp(ball.x, ball.r, W - ball.r); }
          if (ball.vy > 0 && ball.y + ball.r >= me.y - me.h / 2 && ball.y < me.y + me.h && Math.abs(ball.x - me.x) <= me.w / 2 + ball.r) { hitPaddle(me, false); ball.y = me.y - me.h / 2 - ball.r; }
          if (ball.vy < 0 && ball.y - ball.r <= ai.y + ai.h / 2 && ball.y > ai.y - ai.h && Math.abs(ball.x - ai.x) <= ai.w / 2 + ball.r) { hitPaddle(ai, true); ball.y = ai.y + ai.h / 2 + ball.r; }
          if (ball.y > H + 15) { amigo++; info(); return end() || serve(1); }
          if (ball.y < -15) { you++; c.score(you); info(); return end() || serve(-1); }
        }
      },
      draw() {
        ctx.fillStyle = P.bg; ctx.fillRect(0, 0, W, H);
        ctx.strokeStyle = P.line; ctx.setLineDash([8, 8]); ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(0, H / 2); ctx.lineTo(W, H / 2); ctx.stroke(); ctx.setLineDash([]);
        ctx.fillStyle = P.muted; ctx.font = `700 28px ${P.mono}`; ctx.textAlign = 'center';
        ctx.fillText(String(amigo), W / 2, H / 2 - 24); ctx.fillText(String(you), W / 2, H / 2 + 46); ctx.textAlign = 'left';
        ctx.fillStyle = P.accent; GameKit.rr(ctx, ai.x - ai.w / 2, ai.y - ai.h / 2, ai.w, ai.h, 5); ctx.fill();
        ctx.fillStyle = P.user; GameKit.rr(ctx, me.x - me.w / 2, me.y - me.h / 2, me.w, me.h, 5); ctx.fill();
        ctx.fillStyle = P.coral; ctx.beginPath(); ctx.arc(ball.x, ball.y, ball.r, 0, 7); ctx.fill();
      },
    };
    function end() {
      if (you < WIN && amigo < WIN) return false;
      alive = false; g.draw();
      c.over(you > amigo ? `Ты победил ${you}:${amigo}! 🏆` : `Амиго победил ${amigo}:${you} 😎`, you > amigo ? 'win' : 'lose');
      return true;
    }
    const follow = e => { if (alive) me.x = GameKit.clamp(GameKit.pos(cv, e, W, H).x, me.w / 2, W - me.w / 2); };
    cv.addEventListener('pointermove', follow); cv.addEventListener('pointerdown', follow);
    return g;
  },

  // ---------- Летучий Амиго ----------
  flappy(c) {
    const W = 320, H = 420, GROUND = H - 24, { cv, ctx } = GameKit.canvas(c.stage, W, H), speed = c.opts.speed || 1;
    const GAP = speed > 1.2 ? 118 : speed < 0.9 ? 160 : 138, PW = 52, VX = 0.13 * speed;
    let bird, pipes, ready, alive, t, P;
    function addPipe(x) { pipes.push({ x, gy: 70 + Math.random() * (GROUND - 140 - GAP), passed: false }); }
    const g = {
      realtime: true,
      reset() { P = c.pal(); bird = { x: 80, y: H / 2 - 30, vy: 0, r: 14 }; pipes = []; addPipe(W + 40); addPipe(W + 40 + 190); ready = true; alive = true; t = 0; c.score(0); c.info('Нажимай, чтобы взлетать'); },
      input(a, d) { if (!d || !alive) return false; if (a === 'action' || a === 'up') { bird.vy = -0.4; ready = false; return true; } return false; },
      update(dt) {
        if (!alive) return;
        t += dt;
        if (ready) { bird.y = H / 2 - 30 + Math.sin(t / 250) * 6; return; }
        bird.vy += 0.0013 * dt; bird.y += bird.vy * dt;
        for (const p of pipes) {
          p.x -= VX * dt;
          if (!p.passed && p.x + PW < bird.x - bird.r) { p.passed = true; c.score(c.points + 1); }
          const inX = bird.x + bird.r - 3 > p.x && bird.x - bird.r + 3 < p.x + PW;
          if (inX && (bird.y - bird.r + 3 < p.gy || bird.y + bird.r - 3 > p.gy + GAP)) return die();
        }
        if (pipes[0].x + PW < -10) pipes.shift();
        if (pipes[pipes.length - 1].x < W - 190) addPipe(pipes[pipes.length - 1].x + 190);
        if (bird.y + bird.r > GROUND || bird.y - bird.r < 0) return die();
      },
      draw() {
        ctx.fillStyle = P.bg; ctx.fillRect(0, 0, W, H);
        ctx.fillStyle = P.surface; ctx.globalAlpha = 0.7;
        for (let i = 0; i < 4; i++) { const x = ((i * 110 - t * 0.02) % (W + 80) + W + 80) % (W + 80) - 40; ctx.beginPath(); ctx.ellipse(x, 60 + i * 37 % 90, 34, 14, 0, 0, 7); ctx.fill(); }
        ctx.globalAlpha = 1;
        for (const p of pipes) {
          ctx.fillStyle = P.teal;
          GameKit.rr(ctx, p.x, -10, PW, p.gy + 10, 6); ctx.fill(); GameKit.rr(ctx, p.x, p.gy + GAP, PW, GROUND - p.gy - GAP + 10, 6); ctx.fill();
          ctx.fillStyle = P.ink; ctx.globalAlpha = 0.18; ctx.fillRect(p.x - 3, p.gy - 14, PW + 6, 14); ctx.fillRect(p.x - 3, p.gy + GAP, PW + 6, 14); ctx.globalAlpha = 1;
        }
        ctx.fillStyle = P.accent; ctx.fillRect(0, GROUND, W, H - GROUND);
        ctx.fillStyle = P.ink; ctx.globalAlpha = 0.2; for (let x = -((t * VX) % 20); x < W; x += 20) ctx.fillRect(x, GROUND, 10, 4); ctx.globalAlpha = 1;
        GameKit.amigo(ctx, bird.x, bird.y, bird.r, P, GameKit.clamp(bird.vy * 1.2, -0.5, 0.9));
        if (ready && alive) { ctx.fillStyle = P.ink; ctx.font = `600 14px ${P.mono}`; ctx.textAlign = 'center'; ctx.fillText('Нажми, чтобы взлететь!', W / 2, H / 2 + 40); ctx.textAlign = 'left'; }
        ctx.fillStyle = P.ink; ctx.font = `700 30px ${P.mono}`; ctx.textAlign = 'center'; ctx.fillText(String(c.points), W / 2, 44); ctx.textAlign = 'left';
      },
    };
    function die() { alive = false; g.draw(); c.over(U.pick(['Ой! Амиго врезался 🙈', 'Бум! Ещё попытка? 🐤'])); }
    cv.addEventListener('pointerdown', e => { e.preventDefault(); g.input('action', true); });
    return g;
  },

  // ---------- Звездопад ----------
  catcher(c) {
    const W = 320, H = 420, { cv, ctx } = GameKit.canvas(c.stage, W, H), speed = c.opts.speed || 1;
    const sky = [...Array(40)].map(() => [Math.random() * W, Math.random() * H, Math.random() * 1.5 + 0.4]);
    let bas, items, lives, held, alive, spawnT, t, P;
    function info() { c.info('❤️'.repeat(Math.max(0, lives)) + ' · лови ⭐, не лови ☄️'); }
    const g = {
      realtime: true, pad: [['◀', 'left', 1], ['▶', 'right', 1]],
      reset() { P = c.pal(); bas = { x: W / 2, y: H - 30, w: 66 }; items = []; lives = 3; held = {}; alive = true; spawnT = 0; t = 0; c.score(0); info(); },
      input(a, d) { if (a === 'left' || a === 'right') { held[a] = d; return true; } return false; },
      update(dt) {
        if (!alive) return;
        t += dt;
        if (held.left) bas.x -= 0.42 * dt; if (held.right) bas.x += 0.42 * dt;
        bas.x = GameKit.clamp(bas.x, bas.w / 2, W - bas.w / 2);
        const lvl = 1 + c.points / 15;
        spawnT -= dt;
        if (spawnT <= 0) {
          spawnT = Math.max(260, 900 - c.points * 12) / speed;
          const r = Math.random(), kind = r < 0.68 ? 'star' : r < 0.95 ? 'rock' : 'heart';
          items.push({ x: 20 + Math.random() * (W - 40), y: -20, vy: (0.1 + Math.random() * 0.06) * lvl * speed, kind, rot: Math.random() * 6 });
        }
        for (const it of items) {
          it.y += it.vy * dt; it.rot += dt * 0.003;
          if (!it.gone && it.y > bas.y - 14 && it.y < bas.y + 10 && Math.abs(it.x - bas.x) < bas.w / 2 + 6) {
            it.gone = true;
            if (it.kind === 'star') c.score(c.points + 1);
            else if (it.kind === 'heart') { lives = Math.min(5, lives + 1); info(); }
            else { lives--; info(); if (lives <= 0) { alive = false; g.draw(); return c.over('Метеорит! ☄️ Игра окончена'); } }
          }
        }
        items = items.filter(it => !it.gone && it.y < H + 30);
      },
      draw() {
        const gr = ctx.createLinearGradient(0, 0, 0, H); gr.addColorStop(0, '#0E1B3D'); gr.addColorStop(1, '#253A6E');
        ctx.fillStyle = gr; ctx.fillRect(0, 0, W, H);
        ctx.fillStyle = '#FFFFFF';
        for (const [x, y, r] of sky) { ctx.globalAlpha = 0.4 + 0.4 * Math.sin(t / 400 + x); ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill(); }
        ctx.globalAlpha = 1;
        ctx.font = '26px serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        for (const it of items) ctx.fillText(it.kind === 'star' ? '⭐' : it.kind === 'heart' ? '💖' : '☄️', it.x, it.y);
        ctx.fillStyle = P.accent; ctx.beginPath();
        ctx.moveTo(bas.x - bas.w / 2, bas.y - 8); ctx.lineTo(bas.x + bas.w / 2, bas.y - 8); ctx.lineTo(bas.x + bas.w / 2 - 10, bas.y + 14); ctx.lineTo(bas.x - bas.w / 2 + 10, bas.y + 14); ctx.closePath(); ctx.fill();
        ctx.strokeStyle = '#2B1A00'; ctx.lineWidth = 2; ctx.stroke();
        ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
      },
    };
    const follow = e => { if (alive) bas.x = GameKit.clamp(GameKit.pos(cv, e, W, H).x, bas.w / 2, W - bas.w / 2); };
    cv.addEventListener('pointermove', follow); cv.addEventListener('pointerdown', follow);
    return g;
  },
};

// Карточка игры в чате: заголовок, счёт, рекорд, поле, экранные кнопки и экран «начать / пауза / конец».
const BEST_KEY = 'amigo.best.v1';
class GameCard {
  constructor(app, spec) {
    this.app = app; this.spec = spec;
    this.el = GameKit.el('div', 'game-card');
    this.el.tabIndex = -1;
    if (spec.kind === 'custom') this.buildCustom(); else this.buildBuiltin();
  }
  top(icon, title) {
    const bar = GameKit.el('div', 'game-top', this.el);
    const t = GameKit.el('span', 'game-title', bar); t.textContent = icon + ' ' + title;
    this.scoreEl = GameKit.el('span', 'game-score', bar);
    this.bestEl = GameKit.el('span', 'game-best', bar);
    return bar;
  }
  btn(bar, label, title, fn) { const b = GameKit.el('button', 'game-btn', bar); b.type = 'button'; b.textContent = label; b.title = title; b.setAttribute('aria-label', title); b.addEventListener('click', fn); return b; }
  overlayBox() {
    this.ov = GameKit.el('div', 'game-overlay', this.stage);
    this.ovText = GameKit.el('p', '', this.ov);
    this.ovBtn = GameKit.el('button', 'btn primary', this.ov); this.ovBtn.type = 'button';
    this.ovBtn.addEventListener('click', () => this.ovAction());
  }
  overlay(text, btn, action) { this.ovText.textContent = text; this.ovBtn.textContent = btn; this.ovAction = action; this.ov.hidden = false; }

  // ---------- встроенная игра ----------
  buildBuiltin() {
    const key = this.spec.key, codex = key === 'codex', spec = this.spec.opts || {};
    const info = codex ? { title: spec.title || 'Игра', icon: spec.icon || '🎮', help: spec.help || '' } : GAME_LIST[key];
    this.title = info.title;
    this.bestKey = codex ? 'codex:' + spec.id : key;
    const bar = this.top(info.icon, info.title);
    this.pauseBtn = this.btn(bar, '⏸', 'Пауза', () => (this.running ? this.pause() : this.play()));
    this.btn(bar, '↻', 'Начать заново', () => this.restart());
    if (codex) this.btn(bar, '</>', 'Показать код игры', () => this.app.showCode(spec));
    if (document.fullscreenEnabled) this.btn(bar, '⛶', 'На весь экран', () => this.fullscreen());
    this.stage = GameKit.el('div', 'game-stage', this.el);
    this.stage.tabIndex = 0;
    this.stage.setAttribute('aria-label', 'Игровое поле: ' + info.title);
    this.infoEl = GameKit.el('div', 'game-info', this.el);
    const card = this;
    this.points = 0;
    const api = {
      stage: this.stage, opts: this.spec.opts || {},
      get points() { return card.points; },
      score: n => { card.points = n; card.showScore(); },
      info: t => { card.infoEl.textContent = t; },
      pal: GameKit.palette,
      over: (text, res) => card.over(text, res),
      toast: t => card.app.toast(t),
      audio: () => card.app.audio,
    };
    this.game = GAMES[key](api);
    this.label = this.game.scoreLabel || 'Очки';
    this.overlayBox();
    this.buildPad(this.game.pad);
    this.game.reset();
    if (this.game.draw) this.game.draw();
    this.showScore();
    if (this.game.realtime) this.overlay(info.help, '▶ Играть', () => this.play());
    else { this.ov.hidden = true; this.state = 'play'; }
    this.pauseBtn.hidden = !this.game.realtime;
    this.el.addEventListener('keydown', e => this.key(e, true));
    this.el.addEventListener('keyup', e => this.key(e, false));
    this.el.addEventListener('focusout', e => { if (!this.el.contains(e.relatedTarget)) this.pause(); });
    this.stage.addEventListener('pointerdown', () => { this.app.activeGame = this; });
  }
  buildPad(pad) {
    if (!pad) return;
    const box = GameKit.el('div', 'game-pad' + (pad === 'dpad' ? ' dpad' : ''), this.el);
    const keys = pad === 'dpad' ? [['▲', 'up'], ['◀', 'left'], ['▼', 'down'], ['▶', 'right']] : pad;
    for (const [label, act, repeat] of keys) {
      const b = GameKit.el('button', 'pad-' + act, box); b.type = 'button'; b.textContent = label; b.setAttribute('aria-label', act);
      let rep = 0, del = 0;
      const stop = () => { clearTimeout(del); clearInterval(rep); this.game.input(act, false); };
      b.addEventListener('pointerdown', e => {
        e.preventDefault();
        if (this.game.realtime && !this.running && this.state !== 'over') this.play();
        this.game.input(act, true);
        if (repeat && (act === 'left' || act === 'right' || act === 'down') && !['breakout', 'pong', 'catcher'].includes(this.spec.key)) del = setTimeout(() => { rep = setInterval(() => this.game.input(act, true), 75); }, 220);
      });
      for (const ev of ['pointerup', 'pointerleave', 'pointercancel']) b.addEventListener(ev, stop);
    }
  }
  showScore() {
    const best = (U.store.get(BEST_KEY, {}) || {})[this.bestKey];
    this.scoreEl.textContent = `${this.label}: ${this.points}`;
    this.bestEl.textContent = best != null ? `🏆 ${best}` : '';
    this.bestEl.title = 'Рекорд';
  }
  key(e, down) {
    if (e.target && e.target.tagName === 'TEXTAREA') return;
    if (down && (e.code === 'KeyP' || e.code === 'Escape') && this.game.realtime) { e.preventDefault(); return this.running ? this.pause() : this.state === 'pause' && this.play(); }
    const a = GameKit.KEY[e.code]; if (!a) return;
    if (!this.ov.hidden) { if (down && a === 'action') { e.preventDefault(); this.ovAction(); } return; }
    if (this.game.input(a, down, e)) e.preventDefault();
  }
  play() {
    if (this.app.unlockAudio) this.app.unlockAudio();
    if (this.app.activeGame && this.app.activeGame !== this) this.app.activeGame.pause();
    this.app.activeGame = this;
    if (this.state === 'over') { this.game.reset(); }
    this.state = 'play';
    this.stage.focus({ preventScroll: true });
    this.ov.hidden = true;
    if (!this.game.realtime) return;
    this.running = true; this.pauseBtn.textContent = '⏸'; this.pauseBtn.title = 'Пауза';
    let last = performance.now();
    const f = now => {
      if (!this.running) return;
      const dt = Math.min(40, now - last); last = now;
      this.game.update(dt);
      if (this.running || this.state === 'over') this.game.draw();
      if (this.running) this.raf = requestAnimationFrame(f);
    };
    this.raf = requestAnimationFrame(f);
  }
  pause() {
    if (!this.running) return;
    this.running = false; cancelAnimationFrame(this.raf);
    this.state = 'pause'; this.pauseBtn.textContent = '▶'; this.pauseBtn.title = 'Продолжить';
    this.overlay('Пауза', '▶ Продолжить', () => this.play());
  }
  over(text, res) {
    this.running = false; cancelAnimationFrame(this.raf);
    this.state = 'over';
    const all = U.store.get(BEST_KEY, {}) || {}, prev = all[this.bestKey], low = !!this.game.lowBetter;
    const counts = res !== 'lose' && this.points > 0;
    const record = counts && (prev == null || (low ? this.points < prev : this.points > prev));
    if (record) { all[this.bestKey] = this.points; U.store.set(BEST_KEY, all); }
    this.showScore();
    const lines = [text || 'Игра окончена!'];
    if (res !== 'lose' && !(low && res !== 'win')) lines.push(`${this.label}: ${this.points}`);
    if (record && prev != null) lines.push('🏆 Новый рекорд!');
    this.overlay(lines.join('\n'), '↻ Ещё раз', () => this.restart());
    if (record && prev != null) this.app.gameRecord(this.title, this.points, this.label);
  }
  restart() {
    this.running = false; cancelAnimationFrame(this.raf);
    this.state = 'over';
    if (this.game.realtime) this.play();
    else { this.game.reset(); this.state = 'play'; this.ov.hidden = true; }
  }
  fullscreen() {
    try { if (document.fullscreenElement) document.exitFullscreen(); else this.el.requestFullscreen().then(() => this.stage.focus()).catch(() => this.app.toast('Полный экран здесь недоступен')); }
    catch (e) { this.app.toast('Полный экран здесь недоступен'); }
  }
  destroy() { this.running = false; cancelAnimationFrame(this.raf); if (this.game && this.game.destroy) this.game.destroy(); }
  focus() { try { if (!this.ov.hidden) this.ovBtn.focus({ preventScroll: true }); else this.stage.focus({ preventScroll: true }); } catch (e) { /* нет фокуса */ } }

  // ---------- старая игра от супер-мозга (теперь игры пишет сам Амиго) ----------
  buildCustom() {
    this.title = this.spec.title || 'Игра';
    this.top('🎮', this.title);
    this.scoreEl.textContent = '';
    this.stage = GameKit.el('div', 'game-stage', this.el);
    this.overlayBox();
    this.overlay('Эту игру когда-то писал супер-мозг. Теперь игры программирую я сам, в режиме Кодекс! Опиши её снова, и я сделаю.', 'Понятно', () => { this.ov.hidden = true; });
    this.stage.style.minHeight = '180px';
  }
}
