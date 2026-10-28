// Арена «Зал Суда» ночью: плиточный тёмно-синий пол, колонны, звёздное небо, луна, туман, фонари.
import * as THREE from 'three';
import { canvasTex, glowTex } from './fx.js';
import { ARENA_HALF } from './data.js';

function floorTexture() {
  const t = canvasTex(512, 512, (g) => {
    const T = 128;
    for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) {
      const v = (Math.random() - 0.5) * 10 + ((r + c) % 2 ? 5 : -3);
      g.fillStyle = `rgb(${30 + v},${42 + v},${92 + v * 1.4})`;
      g.fillRect(c * T, r * T, T, T);
      // лёгкие разводы
      for (let k = 0; k < 6; k++) {
        g.fillStyle = `rgba(${Math.random() < 0.5 ? '120,150,255' : '0,0,20'},0.035)`;
        const s = 20 + Math.random() * 50;
        g.fillRect(c * T + Math.random() * (T - s), r * T + Math.random() * (T - s), s, s);
      }
      // фаска: светлый верх-лево, тёмный низ-право
      g.fillStyle = 'rgba(140,170,255,.16)'; g.fillRect(c * T, r * T, T, 3); g.fillRect(c * T, r * T, 3, T);
      g.fillStyle = 'rgba(0,0,15,.35)'; g.fillRect(c * T, r * T + T - 4, T, 4); g.fillRect(c * T + T - 4, r * T, 4, T);
    }
    g.fillStyle = '#0a0f2a';
    for (let i = 0; i <= 4; i++) { g.fillRect(i * T - 2, 0, 4, 512); g.fillRect(0, i * T - 2, 512, 4); }
  });
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = 4;
  return t;
}

function emblemTexture() {
  return canvasTex(512, 512, (g) => {
    const c = 256;
    g.strokeStyle = 'rgba(140,200,255,1)'; g.fillStyle = 'rgba(140,200,255,1)';
    g.lineWidth = 6; g.beginPath(); g.arc(c, c, 240, 0, Math.PI * 2); g.stroke();
    g.lineWidth = 3; g.beginPath(); g.arc(c, c, 222, 0, Math.PI * 2); g.stroke();
    g.lineWidth = 4; g.beginPath(); g.arc(c, c, 120, 0, Math.PI * 2); g.stroke();
    // руны по кругу
    g.font = '900 30px monospace'; g.textAlign = 'center'; g.textBaseline = 'middle';
    const R = '✦◆▲●✚◇▼○✧◈△◎';
    for (let i = 0; i < 24; i++) {
      const a = (i / 24) * Math.PI * 2;
      g.save(); g.translate(c + Math.cos(a) * 172, c + Math.sin(a) * 172); g.rotate(a + Math.PI / 2);
      g.fillText(R[i % R.length], 0, 0); g.restore();
    }
    // лучи и ромб в центре
    g.lineWidth = 3;
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      g.beginPath(); g.moveTo(c + Math.cos(a) * 125, c + Math.sin(a) * 125); g.lineTo(c + Math.cos(a) * 215, c + Math.sin(a) * 215); g.stroke();
    }
    g.beginPath(); g.moveTo(c, c - 80); g.lineTo(c + 60, c); g.lineTo(c, c + 80); g.lineTo(c - 60, c); g.closePath(); g.stroke();
    g.beginPath(); g.moveTo(c, c - 40); g.lineTo(c + 30, c); g.lineTo(c, c + 40); g.lineTo(c - 30, c); g.closePath(); g.fill();
  });
}

export function buildWorld(scene) {
  scene.background = new THREE.Color(0x03050f);
  scene.fog = new THREE.Fog(0x0b1440, 55, 175);

  const hemi = new THREE.HemisphereLight(0x9fb4ff, 0x141a3a, 1.35); scene.add(hemi);
  const amb = new THREE.AmbientLight(0x4a5aa8, 0.65); scene.add(amb);
  const moon = new THREE.DirectionalLight(0xd8e4ff, 1.7); moon.position.set(-40, 80, -30); scene.add(moon);
  const rim = new THREE.DirectionalLight(0x6fa8ff, 0.6); rim.position.set(40, 30, 60); scene.add(rim);
  const baseI = [hemi.intensity, amb.intensity, moon.intensity, rim.intensity];

  // пол
  const ft = floorTexture(); ft.repeat.set(220 / 16, 220 / 16);
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(220, 220), new THREE.MeshLambertMaterial({ map: ft }));
  floor.rotation.x = -Math.PI / 2; scene.add(floor);

  // эмблема в центре
  const emblem = new THREE.Mesh(new THREE.PlaneGeometry(30, 30), new THREE.MeshBasicMaterial({
    map: emblemTexture(), transparent: true, opacity: 0.22, depthWrite: false, blending: THREE.AdditiveBlending, color: 0x7fb4ff,
  }));
  emblem.rotation.x = -Math.PI / 2; emblem.position.y = 0.03; emblem.renderOrder = 1; scene.add(emblem);

  // бортик арены
  const H = ARENA_HALF + 1.2;
  const wallMat = new THREE.MeshLambertMaterial({ color: 0x223070 });
  const trimMat = new THREE.MeshBasicMaterial({ color: 0x4f8cff, transparent: true, opacity: 0.55 });
  for (let i = 0; i < 4; i++) {
    const along = i < 2;
    const w = new THREE.Mesh(new THREE.BoxGeometry(along ? H * 2 + 2 : 1.4, 1.3, along ? 1.4 : H * 2 + 2), wallMat);
    const s = i % 2 ? 1 : -1;
    w.position.set(along ? 0 : s * H, 0.65, along ? s * H : 0); scene.add(w);
    const t = new THREE.Mesh(new THREE.BoxGeometry(along ? H * 2 + 2 : 0.3, 0.12, along ? 0.3 : H * 2 + 2), trimMat);
    t.position.set(along ? 0 : s * (H - 0.75), 1.32, along ? s * (H - 0.75) : 0); scene.add(t);
  }

  // колонны (инстансы)
  const P = ARENA_HALF + 6, step = 10;
  const spots = [];
  for (let x = -P; x <= P + 0.1; x += step) { spots.push([x, -P], [x, P]); }
  for (let z = -P + step; z <= P - step + 0.1; z += step) { spots.push([-P, z], [P, z]); }
  const pillarMat = new THREE.MeshLambertMaterial({ color: 0x2c3a7c });
  const capMat = new THREE.MeshLambertMaterial({ color: 0x3e4f9c });
  const mkInst = (geo, mat, y) => {
    const im = new THREE.InstancedMesh(geo, mat, spots.length);
    const m = new THREE.Matrix4();
    spots.forEach(([x, z], i) => { m.makeTranslation(x, y, z); im.setMatrixAt(i, m); });
    scene.add(im); return im;
  };
  mkInst(new THREE.BoxGeometry(2.6, 20, 2.6), pillarMat, 10);
  mkInst(new THREE.BoxGeometry(3.8, 1.4, 3.8), capMat, 0.7);
  mkInst(new THREE.BoxGeometry(4, 1.2, 4), capMat, 20.4);
  mkInst(new THREE.BoxGeometry(3.2, 0.5, 3.2), capMat, 1.65);
  // перекрытия наверху
  for (let i = 0; i < 4; i++) {
    const along = i < 2, s = i % 2 ? 1 : -1;
    const b = new THREE.Mesh(new THREE.BoxGeometry(along ? P * 2 + 4 : 3.4, 2, along ? 3.4 : P * 2 + 4), capMat);
    b.position.set(along ? 0 : s * P, 22, along ? s * P : 0); scene.add(b);
  }

  // фонари на колоннах (инстансы + одно облако свечений)
  const lampSpots = [];
  spots.forEach(([x, z], i) => {
    if (i % 2) return;
    const dx = Math.sign(-x) * (Math.abs(x) > P - 1 ? 1 : 0), dz = Math.sign(-z) * (Math.abs(z) > P - 1 ? 1 : 0);
    lampSpots.push([x + dx * 1.9, 9, z + dz * 1.9]);
  });
  const lamps = new THREE.InstancedMesh(new THREE.BoxGeometry(0.9, 1.3, 0.9), new THREE.MeshBasicMaterial({ color: 0xbfe6ff }), lampSpots.length);
  const lm = new THREE.Matrix4();
  lampSpots.forEach(([x, y, z], i) => { lm.makeTranslation(x, y, z); lamps.setMatrixAt(i, lm); });
  scene.add(lamps);
  const lgGeo = new THREE.BufferGeometry(); lgGeo.setAttribute('position', new THREE.Float32BufferAttribute(lampSpots.flat(), 3));
  const lampGlow = new THREE.Points(lgGeo, new THREE.PointsMaterial({ map: glowTex(), color: 0x6fc4ff, size: 7, sizeAttenuation: true, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
  scene.add(lampGlow);
  const lanterns = [{ s: lampGlow }];

  // небо
  const sky = new THREE.Mesh(new THREE.SphereGeometry(450, 32, 16), new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: { top: { value: new THREE.Color(0x02030a) }, mid: { value: new THREE.Color(0x0a1338) }, bot: { value: new THREE.Color(0x16245e) } },
    vertexShader: 'varying vec3 vP; void main(){ vP=normalize(position); gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0); }',
    fragmentShader: 'uniform vec3 top; uniform vec3 mid; uniform vec3 bot; varying vec3 vP; void main(){ float h=vP.y; vec3 c = h>0.12 ? mix(mid, top, smoothstep(0.12,0.75,h)) : mix(bot, mid, smoothstep(-0.05,0.12,h)); gl_FragColor=vec4(c,1.0); }',
  }));
  sky.renderOrder = -10; scene.add(sky);

  const mkStars = (n, size, op) => {
    const pos = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) {
      const u = Math.random() * Math.PI * 2, v = Math.random() * 0.85 + 0.08;
      const r = 400, y = Math.sin(v * Math.PI / 2) * r, rr = Math.cos(v * Math.PI / 2) * r;
      pos[i * 3] = Math.cos(u) * rr; pos[i * 3 + 1] = y; pos[i * 3 + 2] = Math.sin(u) * rr;
    }
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    const p = new THREE.Points(g, new THREE.PointsMaterial({ size, sizeAttenuation: false, color: 0xffffff, transparent: true, opacity: op, fog: false, depthWrite: false }));
    p.renderOrder = -9; scene.add(p); return p;
  };
  mkStars(1400, 1.5, 0.75);
  const bright = mkStars(160, 2.6, 1);

  const moonTex = canvasTex(128, 128, (g) => {
    const gr = g.createRadialGradient(64, 64, 10, 64, 64, 64);
    gr.addColorStop(0, 'rgba(230,240,255,1)'); gr.addColorStop(0.32, 'rgba(220,232,255,1)'); gr.addColorStop(0.36, 'rgba(150,180,255,.35)'); gr.addColorStop(1, 'rgba(80,110,255,0)');
    g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
    g.fillStyle = 'rgba(160,175,215,.5)';
    [[54, 52, 7], [74, 70, 5], [60, 78, 4], [76, 50, 3]].forEach(([x, y, r]) => { g.beginPath(); g.arc(x, y, r, 0, 7); g.fill(); });
  });
  const moonS = new THREE.Sprite(new THREE.SpriteMaterial({ map: moonTex, transparent: true, depthWrite: false, fog: false }));
  moonS.position.set(-150, 170, -300); moonS.scale.setScalar(90); moonS.renderOrder = -8; scene.add(moonS);

  // парящие пылинки
  const motes = 120, mp = new Float32Array(motes * 3), mph = [];
  for (let i = 0; i < motes; i++) { mp[i * 3] = (Math.random() - 0.5) * 90; mp[i * 3 + 1] = Math.random() * 14 + 0.5; mp[i * 3 + 2] = (Math.random() - 0.5) * 90; mph.push(Math.random() * 10); }
  const mg = new THREE.BufferGeometry(); const mattr = new THREE.BufferAttribute(mp, 3); mg.setAttribute('position', mattr);
  const mpts = new THREE.Points(mg, new THREE.PointsMaterial({ size: 0.25, color: 0x9cc8ff, transparent: true, opacity: 0.7, depthWrite: false, blending: THREE.AdditiveBlending }));
  scene.add(mpts);

  let dark = 0, darkT = 0;
  const fogBase = scene.fog.color.clone(), fogDark = new THREE.Color(0x020310);
  const fogFar0 = scene.fog.far;
  return {
    floor,
    setDark(k) { darkT = k; },
    setQuality(level) {
      mpts.visible = level >= 4;
      for (const l of lanterns) l.s.visible = level >= 3;
      bright.visible = level >= 3;
      scene.fog.far = fogFar0 + (level - 6) * 8;
    },
    update(t, dt) {
      lampGlow.material.size = 7 + Math.sin(t * 3) * 0.4 + Math.sin(t * 11) * 0.15;
      bright.material.opacity = 0.75 + Math.sin(t * 1.7) * 0.25;
      emblem.material.opacity = 0.18 + Math.sin(t * 1.2) * 0.05 + dark * 0.25;
      for (let i = 0; i < motes; i++) {
        mp[i * 3 + 1] += dt * 0.5; mp[i * 3] += Math.sin(t * 0.5 + mph[i]) * dt * 0.4;
        if (mp[i * 3 + 1] > 15) mp[i * 3 + 1] = 0.3;
      }
      mattr.needsUpdate = true;
      if (Math.abs(dark - darkT) > 0.002) {
        dark += (darkT - dark) * Math.min(1, dt * 3);
        const k = 1 - dark * 0.55;
        hemi.intensity = baseI[0] * k; amb.intensity = baseI[1] * k; moon.intensity = baseI[2] * k; rim.intensity = baseI[3] * (1 + dark);
        scene.fog.color.copy(fogBase).lerp(fogDark, dark);
        emblem.material.color.setHex(dark > 0.5 ? 0xffe066 : 0x7fb4ff);
      }
    },
  };
}
