/* ===== 02_nn.js ===== */
// Нейросеть Амиго: многослойный перцептрон, написанный с нуля.
// Вход — разреженный вектор признаков фразы (D чисел), скрытый слой из H нейронов (ReLU),
// выход — вероятности C тем (softmax). Обучение — обратное распространение ошибки и оптимизатор Adam.
class MLP {
  constructor(D, H, C, seed = 1) {
    this.D = D; this.H = H; this.C = C;
    const rnd = U.rng(seed);
    const gauss = () => { let u = 0, v = 0; while (u === 0) u = rnd(); v = rnd(); return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v); };
    // первый слой начинается с нулей: признаки, которых сеть не видела, ни на что не влияют
    this.W1 = new Float32Array(D * H);
    this.b1 = new Float32Array(H).fill(0.1);
    this.W2 = new Float32Array(H * C);
    const s2 = Math.sqrt(2 / H);
    for (let i = 0; i < this.W2.length; i++) this.W2[i] = gauss() * s2;
    this.b2 = new Float32Array(C);
    this.resetOptimizer();
  }
  get params() { return this.W1.length + this.b1.length + this.W2.length + this.b2.length; }
  // память оптимизатора создаётся только перед обучением, чтобы на телефоне не занимать лишние мегабайты
  resetOptimizer() { this.t = 0; this.m = null; this.v = null; }
  initOptimizer() {
    this.m = { W1: new Float32Array(this.W1.length), b1: new Float32Array(this.H), W2: new Float32Array(this.W2.length), b2: new Float32Array(this.C) };
    this.v = { W1: new Float32Array(this.W1.length), b1: new Float32Array(this.H), W2: new Float32Array(this.W2.length), b2: new Float32Array(this.C) };
  }
  // добавить новую тему (выход), например когда пользователь учит Амиго новому ответу
  addClass(seed = 7) {
    const { H, C } = this, rnd = U.rng(seed + C);
    const W2 = new Float32Array(H * (C + 1));
    for (let h = 0; h < H; h++) {
      for (let c = 0; c < C; c++) W2[h * (C + 1) + c] = this.W2[h * C + c];
      W2[h * (C + 1) + C] = (rnd() - 0.5) * 0.1;
    }
    const b2 = new Float32Array(C + 1); b2.set(this.b2); b2[C] = -1;
    this.W2 = W2; this.b2 = b2; this.C = C + 1;
    this.resetOptimizer();
    return C;
  }
  // прямой проход; возвращает скрытые активации и вероятности (буферы переиспользуются между вызовами)
  forward(x, drop = 0, rnd = null) {
    const { H, C, W1, W2 } = this;
    if (!this._f || this._f.p.length !== C || this._f.hid.length !== H) {
      this._f = { pre: new Float32Array(H), hid: new Float32Array(H), mask: new Uint8Array(H), p: new Float32Array(C) };
    }
    const { pre, hid, mask, p } = this._f;
    pre.set(this.b1);
    const xi = x.idx, xv = x.val;
    for (let k = 0; k < xi.length; k++) {
      const row = xi[k] * H, v = xv[k];
      for (let h = 0; h < H; h++) pre[h] += v * W1[row + h];
    }
    const keep = 1 - drop;
    for (let h = 0; h < H; h++) {
      let a = pre[h] > 0 ? pre[h] : 0;
      if (drop) { if (rnd() < drop) { a = 0; mask[h] = 0; } else { a /= keep; mask[h] = 1; } }
      hid[h] = a;
    }
    p.set(this.b2);
    for (let h = 0; h < H; h++) {
      const a = hid[h]; if (!a) continue;
      const row = h * C;
      for (let c = 0; c < C; c++) p[c] += a * W2[row + c];
    }
    let mx = -Infinity; for (let c = 0; c < C; c++) if (p[c] > mx) mx = p[c];
    let s = 0;
    for (let c = 0; c < C; c++) { p[c] = Math.exp(p[c] - mx); s += p[c]; }
    for (let c = 0; c < C; c++) p[c] /= s;
    return this._f;
  }
  predict(x) { return Float32Array.from(this.forward(x).p); }
  hidden(x) { return Float32Array.from(this.forward(x).hid); }

  // один шаг обучения на пачке примеров [{x, y}]; возвращает среднюю ошибку (кросс-энтропию)
  trainBatch(batch, opt, rnd) {
    const { D, H, C } = this;
    if (!this.m) this.initOptimizer();
    const eps = opt.smooth || 0, drop = opt.dropout || 0;
    let g = this._g;
    if (!g || g.C !== C || g.H !== H) {
      g = this._g = { C, H, W1: new Float32Array(D * H), rows: new Int32Array(D), seen: new Uint8Array(D),
        W2: new Float32Array(H * C), b2: new Float32Array(C), b1: new Float32Array(H), dz: new Float32Array(C), dh: new Float32Array(H) };
    }
    g.W2.fill(0); g.b2.fill(0); g.b1.fill(0);
    let nrows = 0, loss = 0, correct = 0;
    const off = eps / C, on = 1 - eps + off, W2 = this.W2, dz = g.dz, dh = g.dh;
    for (const ex of batch) {
      const f = this.forward(ex.x, drop, rnd), p = f.p;
      let arg = 0; for (let c = 1; c < C; c++) if (p[c] > p[arg]) arg = c;
      if (arg === ex.y) correct++;
      loss -= Math.log(p[ex.y] + 1e-9);
      for (let c = 0; c < C; c++) { dz[c] = p[c] - (c === ex.y ? on : off); g.b2[c] += dz[c]; }
      const scale = drop ? 1 / (1 - drop) : 1;
      for (let h = 0; h < H; h++) {
        const a = f.hid[h], row = h * C;
        let s = 0;
        if (a) for (let c = 0; c < C; c++) { s += W2[row + c] * dz[c]; g.W2[row + c] += a * dz[c]; }
        else for (let c = 0; c < C; c++) s += W2[row + c] * dz[c];
        // производная ReLU и dropout
        dh[h] = (f.pre[h] > 0 && (!drop || f.mask[h])) ? s * scale : 0;
        g.b1[h] += dh[h];
      }
      const xi = ex.x.idx, xv = ex.x.val;
      for (let k = 0; k < xi.length; k++) {
        const r = xi[k], v = xv[k], row = r * H;
        if (!g.seen[r]) { g.seen[r] = 1; g.rows[nrows++] = r; }
        for (let h = 0; h < H; h++) g.W1[row + h] += v * dh[h];
      }
    }
    const n = batch.length;
    this.t++;
    const lr = opt.lr * Math.sqrt(1 - Math.pow(0.999, this.t)) / (1 - Math.pow(0.9, this.t));
    const wd = opt.decay || 0;
    const adam = (w, m, v, gr, i0, len) => {
      for (let i = i0; i < i0 + len; i++) {
        const gi = gr[i] / n + wd * w[i];
        m[i] = 0.9 * m[i] + 0.1 * gi;
        v[i] = 0.999 * v[i] + 0.001 * gi * gi;
        w[i] -= lr * m[i] / (Math.sqrt(v[i]) + 1e-8);
      }
    };
    adam(this.W2, this.m.W2, this.v.W2, g.W2, 0, H * C);
    adam(this.b2, this.m.b2, this.v.b2, g.b2, 0, C);
    adam(this.b1, this.m.b1, this.v.b1, g.b1, 0, H);
    // «ленивый» Adam: обновляем только строки признаков, которые встретились в пачке
    for (let j = 0; j < nrows; j++) {
      const r = g.rows[j], row = r * H;
      adam(this.W1, this.m.W1, this.v.W1, g.W1, row, H);
      g.W1.fill(0, row, row + H); g.seen[r] = 0;
    }
    return { loss: loss / n, acc: correct / n };
  }

  // полное обучение; onEpoch получает {epoch, loss, acc}; tick — пауза, чтобы страница не зависала
  async train(examples, opt = {}) {
    const epochs = opt.epochs || 20, bs = opt.batch || 16, rnd = U.rng(opt.seed || 42);
    const lr0 = opt.lr || 0.01, lrMin = opt.lrMin || lr0 * 0.1;
    const history = [];
    const order = examples.slice();
    let steps = 0;
    for (let e = 0; e < epochs; e++) {
      U.shuffle(order, rnd);
      const lr = lrMin + (lr0 - lrMin) * 0.5 * (1 + Math.cos(Math.PI * e / epochs));
      let L = 0, A = 0, nb = 0;
      for (let i = 0; i < order.length; i += bs) {
        const r = this.trainBatch(order.slice(i, i + bs), { lr, smooth: opt.smooth, dropout: opt.dropout, decay: opt.decay }, rnd);
        L += r.loss; A += r.acc; nb++;
        if (opt.tick && ++steps % (opt.yieldEvery || 40) === 0) await opt.tick();
      }
      const rec = { epoch: e + 1, loss: L / nb, acc: A / nb };
      history.push(rec);
      if (opt.onEpoch) opt.onEpoch(rec);
    }
    return history;
  }

  // сжатие весов в 8-битные числа (по строкам), чтобы встроить обученную сеть в страницу
  static quant(w, rows, cols) {
    const q = new Int8Array(w.length), sc = new Float32Array(rows);
    for (let r = 0; r < rows; r++) {
      let mx = 0; for (let c = 0; c < cols; c++) mx = Math.max(mx, Math.abs(w[r * cols + c]));
      const s = mx / 127 || 1; sc[r] = s;
      for (let c = 0; c < cols; c++) q[r * cols + c] = Math.round(w[r * cols + c] / s);
    }
    return { q: U.b64enc(new Uint8Array(q.buffer)), s: U.b64enc(new Uint8Array(sc.buffer)) };
  }
  static dequant(o, rows, cols) {
    const qb = U.b64dec(o.q), sb = U.b64dec(o.s);
    const q = new Int8Array(qb.buffer, qb.byteOffset, qb.byteLength);
    const s = new Float32Array(sb.buffer.slice(sb.byteOffset, sb.byteOffset + sb.byteLength));
    const w = new Float32Array(rows * cols);
    for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) w[r * cols + c] = q[r * cols + c] * s[r];
    return w;
  }
  toJSON() {
    const f32 = a => U.b64enc(new Uint8Array(a.buffer.slice(0)));
    return { D: this.D, H: this.H, C: this.C, W1: MLP.quant(this.W1, this.D, this.H), b1: f32(this.b1), W2: MLP.quant(this.W2, this.H, this.C), b2: f32(this.b2) };
  }
  static fromJSON(j) {
    const net = new MLP(j.D, j.H, j.C);
    const f32 = s => { const b = U.b64dec(s); return new Float32Array(b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength)); };
    net.W1 = MLP.dequant(j.W1, j.D, j.H); net.b1 = f32(j.b1);
    net.W2 = MLP.dequant(j.W2, j.H, j.C); net.b2 = f32(j.b2);
    net.resetOptimizer();
    return net;
  }
}
