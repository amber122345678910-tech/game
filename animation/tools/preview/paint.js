// Draws Paint element lists (see src/Cutscene/Paint.luau) on a 2D canvas the
// way Roblox draws the matching Frames: rotation about the center (clockwise),
// UICorner radius (-1 = pill), UIGradient (multiplied color, combined
// transparency; rotation 0 = left->right, 90 = top->bottom).
(function (root) {
  function css(c, a) {
    return `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a})`;
  }
  function sampleNum(seq, t) {
    if (!seq || !seq.length) return 0;
    if (t <= seq[0][0]) return seq[0][1];
    for (let i = 1; i < seq.length; i++) {
      if (t <= seq[i][0]) {
        const [t0, v0] = seq[i - 1], [t1, v1] = seq[i];
        const f = t1 > t0 ? (t - t0) / (t1 - t0) : 0;
        return v0 + (v1 - v0) * f;
      }
    }
    return seq[seq.length - 1][1];
  }
  function sampleCol(seq, t) {
    if (!seq || !seq.length) return [1, 1, 1];
    if (t <= seq[0][0]) return seq[0][1];
    for (let i = 1; i < seq.length; i++) {
      if (t <= seq[i][0]) {
        const [t0, c0] = seq[i - 1], [t1, c1] = seq[i];
        const f = t1 > t0 ? (t - t0) / (t1 - t0) : 0;
        return [c0[0] + (c1[0] - c0[0]) * f, c0[1] + (c1[1] - c0[1]) * f, c0[2] + (c1[2] - c0[2]) * f];
      }
    }
    return seq[seq.length - 1][1];
  }
  function drawElems(ctx, elems, opts) {
    opts = opts || {};
    const skipGroups = opts.hide || null;
    for (const e of elems) {
      if (skipGroups && e.grp && skipGroups[e.grp]) continue;
      const alpha = 1 - e.a;
      if (alpha <= 0.001) continue;
      ctx.save();
      ctx.translate(e.x, e.y);
      if (e.rot) ctx.rotate((e.rot * Math.PI) / 180);
      const w = e.w, h = e.h;
      const m = Math.min(w, h) / 2;
      const r = e.r < 0 ? m : Math.min(e.r, m);
      if (e.g) {
        const rot = ((e.g.rot % 360) + 360) % 360;
        let x0 = -w / 2, y0 = 0, x1 = w / 2, y1 = 0;
        if (rot === 90) { x0 = 0; y0 = -h / 2; x1 = 0; y1 = h / 2; }
        else if (rot === 180) { x0 = w / 2; x1 = -w / 2; }
        else if (rot === 270) { x0 = 0; y0 = h / 2; x1 = 0; y1 = -h / 2; }
        const grad = ctx.createLinearGradient(x0, y0, x1, y1);
        // merge keypoint times of both sequences
        const times = new Set([0, 1]);
        (e.g.c || []).forEach(k => times.add(k[0]));
        (e.g.t || []).forEach(k => times.add(k[0]));
        [...times].sort((a, b) => a - b).forEach(t => {
          const gc = sampleCol(e.g.c, t);
          const gt = e.g.t ? sampleNum(e.g.t, t) : 0;
          grad.addColorStop(Math.min(1, Math.max(0, t)), css([e.c[0] * gc[0], e.c[1] * gc[1], e.c[2] * gc[2]], alpha * (1 - gt)));
        });
        ctx.fillStyle = grad;
      } else {
        ctx.fillStyle = css(e.c, alpha);
      }
      ctx.beginPath();
      if (r > 0.01) ctx.roundRect(-w / 2, -h / 2, w, h, r);
      else ctx.rect(-w / 2, -h / 2, w, h);
      ctx.fill();
      ctx.restore();
    }
  }
  root.RbxPaint = { drawElems, css, sampleNum, sampleCol };
})(typeof window !== 'undefined' ? window : globalThis);
