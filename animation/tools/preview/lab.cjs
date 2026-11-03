// Face lab: renders the painted close-up panels (facelab.json) next to a
// reference frame.  node lab.cjs <facelab.json> <reference.png|-> <out.png> [scale]
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

(async () => {
  const [jsonPath, refPath, outPath, scaleArg] = process.argv.slice(2);
  const data = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
  const scale = parseFloat(scaleArg || '1');
  const ref = refPath && refPath !== '-' ? 'data:image/png;base64,' + fs.readFileSync(refPath).toString('base64') : null;
  const paintSrc = fs.readFileSync(path.join(__dirname, 'paint.js'), 'utf8');
  const FW = 1113, FH = 626;
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: Math.ceil(FW * scale * (ref ? 2 : 1)) + 10, height: Math.ceil(FH * scale) } });
  await page.setContent('<html><body style="margin:0;background:#000"><canvas id="c"></canvas></body></html>');
  await page.addScriptTag({ content: paintSrc });
  await page.evaluate(async ({ data, ref, scale, FW, FH }) => {
    const c = document.getElementById('c');
    c.width = Math.ceil(FW * scale * (ref ? 2 : 1)) + (ref ? 10 : 0);
    c.height = Math.ceil(FH * scale);
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#000'; ctx.fillRect(0, 0, c.width, c.height);
    // sky stand-in
    ctx.save();
    ctx.scale(scale, scale);
    const g1 = ctx.createLinearGradient(0, 0, 0, 301);
    g1.addColorStop(0, '#7A8FCB'); g1.addColorStop(1, '#4C629D');
    ctx.fillStyle = g1; ctx.fillRect(0, 0, FW, 301);
    const g2 = ctx.createLinearGradient(0, 301, 0, FH);
    g2.addColorStop(0, '#4A5C90'); g2.addColorStop(1, '#3E5080');
    ctx.fillStyle = g2; ctx.fillRect(0, 301, FW, FH - 301);
    for (const p of data.panels) {
      ctx.save();
      ctx.beginPath();
      if (p.name === 'yuta') ctx.rect(0, 0, FW, 301); else ctx.rect(0, 301, FW, FH - 301);
      ctx.clip();
      ctx.translate(p.x0 + 16.5, p.y0);
      RbxPaint.drawElems(ctx, p.elems);
      ctx.restore();
    }
    ctx.fillStyle = '#030106';
    ctx.fillRect(0, 295.5, FW, 11);
    ctx.restore();
    if (ref) {
      const img = new Image();
      img.src = ref;
      await img.decode();
      ctx.drawImage(img, FW * scale + 10 + 16.5 * scale, 0, 1080 * scale, 626 * scale);
    }
  }, { data, ref, scale, FW, FH });
  const buf = await (await page.$('#c')).screenshot();
  fs.writeFileSync(outPath, buf);
  await browser.close();
})();
