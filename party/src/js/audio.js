'use strict';
// Все звуки и музыка синтезируются WebAudio прямо в браузере — никаких файлов.

const Sound = {
  ctx: null,
  master: null,
  sfxBus: null,
  musicBus: null,
  noiseBuf: null,
  last: {},

  init() {
    if (this.ctx) {
      if (this.ctx.state === 'suspended') this.ctx.resume();
      return;
    }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    try { this.ctx = new AC(); } catch (e) { return; }
    const ctx = this.ctx;
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -14;
    comp.ratio.value = 4;
    this.master = ctx.createGain();
    this.master.gain.value = 0.9;
    this.master.connect(comp);
    comp.connect(ctx.destination);
    this.sfxBus = ctx.createGain();
    this.musicBus = ctx.createGain();
    this.musicDuck = ctx.createGain();
    this.sfxBus.connect(this.master);
    this.musicBus.connect(this.musicDuck);
    this.musicDuck.connect(this.master);
    const len = ctx.sampleRate;
    this.noiseBuf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = this.noiseBuf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    this.applyVolumes();
    if (Music.pending) Music.play(Music.pending);
  },

  applyVolumes() {
    if (!this.ctx) return;
    const s = Store.data.settings;
    this.sfxBus.gain.value = s.sfx;
    this.musicBus.gain.value = s.music * 0.55;
  },

  // Простой тон с огибающей и (необязательной) сменой высоты.
  tone(o) {
    const ctx = this.ctx;
    if (!ctx) return;
    const t = ctx.currentTime + (o.t || 0);
    const dur = o.dur || 0.15;
    const osc = ctx.createOscillator();
    osc.type = o.type || 'sine';
    osc.frequency.setValueAtTime(o.f, t);
    if (o.f2) osc.frequency.exponentialRampToValueAtTime(o.f2, t + (o.slide || dur));
    const g = ctx.createGain();
    const vol = o.vol == null ? 0.25 : o.vol;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + (o.attack || 0.006));
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    let node = osc;
    if (o.filter) {
      const f = ctx.createBiquadFilter();
      f.type = o.filter;
      f.frequency.value = o.ff || 1200;
      f.Q.value = o.q || 1;
      node.connect(f);
      node = f;
    }
    node.connect(g);
    g.connect(o.bus || this.sfxBus);
    osc.start(t);
    osc.stop(t + dur + 0.05);
  },

  noise(o) {
    const ctx = this.ctx;
    if (!ctx) return;
    const t = ctx.currentTime + (o.t || 0);
    const dur = o.dur || 0.2;
    const src = ctx.createBufferSource();
    src.buffer = this.noiseBuf;
    src.loop = true;
    const f = ctx.createBiquadFilter();
    f.type = o.filter || 'bandpass';
    f.frequency.setValueAtTime(o.f || 1000, t);
    if (o.f2) f.frequency.exponentialRampToValueAtTime(o.f2, t + dur);
    f.Q.value = o.q || 1;
    const g = ctx.createGain();
    const vol = o.vol == null ? 0.3 : o.vol;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + (o.attack || 0.005));
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(f);
    f.connect(g);
    g.connect(o.bus || this.sfxBus);
    src.start(t, Math.random() * 0.5);
    src.stop(t + dur + 0.05);
  },

  play(name, opt = {}) {
    if (!this.ctx) return;
    // Не даём одинаковым звукам наслаиваться в одну и ту же миллисекунду.
    const now = this.ctx.currentTime;
    if (this.last[name] && now - this.last[name] < (opt.gap || 0.03)) return;
    this.last[name] = now;
    const p = opt.pitch || 1;
    switch (name) {
      case 'jump':
        this.tone({ type: 'sine', f: 330 * p, f2: 620 * p, dur: 0.13, vol: 0.12 });
        this.noise({ f: 900, f2: 2200, dur: 0.1, vol: 0.05 });
        break;
      case 'land':
        this.noise({ filter: 'lowpass', f: 380, dur: 0.09, vol: 0.18 });
        break;
      case 'coin':
        this.tone({ type: 'square', f: 988, dur: 0.08, vol: 0.07 });
        this.tone({ type: 'square', f: 1319, t: 0.07, dur: 0.28, vol: 0.07 });
        break;
      case 'checkpoint':
        [523, 659, 784, 1047].forEach((f, i) => this.tone({ type: 'triangle', f, t: i * 0.07, dur: 0.22, vol: 0.16 }));
        break;
      case 'oof':
        this.tone({ type: 'sawtooth', f: 260 * p, f2: 150 * p, dur: 0.28, vol: 0.22, filter: 'bandpass', ff: 750, q: 2.2 });
        this.tone({ type: 'sawtooth', f: 262 * p, f2: 148 * p, dur: 0.26, vol: 0.12, filter: 'bandpass', ff: 1250, q: 3 });
        this.noise({ filter: 'lowpass', f: 300, dur: 0.15, vol: 0.12 });
        break;
      case 'slap':
        this.noise({ f: 2200, q: 0.8, dur: 0.16, vol: 0.55 });
        this.noise({ filter: 'highpass', f: 5000, dur: 0.05, vol: 0.4 });
        this.tone({ type: 'sine', f: 190, f2: 55, dur: 0.14, vol: 0.4 });
        break;
      case 'push':
        this.noise({ f: 1100, q: 0.9, dur: 0.12, vol: 0.3 });
        this.tone({ type: 'sine', f: 150, f2: 70, dur: 0.1, vol: 0.25 });
        break;
      case 'whoosh':
        this.noise({ f: 500, f2: 2200, q: 1.4, dur: 0.18, vol: 0.12 });
        break;
      case 'glass':
        this.noise({ filter: 'highpass', f: 2600, dur: 0.55, vol: 0.45 });
        for (let i = 0; i < 6; i++) this.tone({ type: 'sine', f: rand(2400, 6200), t: rand(0, 0.25), dur: rand(0.12, 0.4), vol: 0.06 });
        break;
      case 'beep':
        this.tone({ type: 'square', f: 660, dur: 0.16, vol: 0.09 });
        this.tone({ type: 'sine', f: 660, dur: 0.2, vol: 0.12 });
        break;
      case 'go':
        this.tone({ type: 'square', f: 988, dur: 0.45, vol: 0.09 });
        this.tone({ type: 'sine', f: 1976, dur: 0.45, vol: 0.08 });
        break;
      case 'win':
        [523, 659, 784, 1047, 1319].forEach((f, i) => this.tone({ type: 'triangle', f, t: i * 0.1, dur: 0.35, vol: 0.18 }));
        [523, 659, 784].forEach((f) => this.tone({ type: 'square', f: f * 2, t: 0.55, dur: 0.9, vol: 0.05 }));
        break;
      case 'lose':
        [392, 349, 311, 262].forEach((f, i) => this.tone({ type: 'triangle', f, t: i * 0.16, dur: 0.32, vol: 0.16 }));
        break;
      case 'boing':
        this.tone({ type: 'sine', f: 140, f2: 720, dur: 0.32, slide: 0.22, vol: 0.28 });
        this.tone({ type: 'triangle', f: 280, f2: 1100, dur: 0.22, vol: 0.06 });
        break;
      case 'powerup':
        [523, 659, 784, 988, 1175, 1568].forEach((f, i) => this.tone({ type: 'square', f, t: i * 0.045, dur: 0.12, vol: 0.06 }));
        break;
      case 'tick':
        this.tone({ type: 'square', f: 1250, dur: 0.035, vol: 0.05 });
        break;
      case 'drop':
        this.noise({ filter: 'lowpass', f: 260, f2: 80, dur: 0.8, vol: 0.4 });
        this.tone({ type: 'sine', f: 90, f2: 40, dur: 0.6, vol: 0.3 });
        break;
      case 'rise':
        this.tone({ type: 'sine', f: 120, f2: 300, dur: 0.6, vol: 0.12 });
        break;
      case 'siren':
        for (let i = 0; i < 3; i++) this.tone({ type: 'sawtooth', f: 520, f2: 880, t: i * 0.5, dur: 0.48, slide: 0.45, vol: 0.06, filter: 'lowpass', ff: 2400 });
        break;
      case 'sizzle':
        this.noise({ filter: 'highpass', f: 3500, dur: 0.5, vol: 0.18 });
        break;
      case 'portal':
        this.tone({ type: 'sine', f: 400, f2: 1300, dur: 0.6, vol: 0.12 });
        this.tone({ type: 'triangle', f: 600, f2: 1900, dur: 0.6, vol: 0.06 });
        break;
      case 'click':
        this.tone({ type: 'square', f: 880, dur: 0.04, vol: 0.05 });
        break;
      case 'select':
        this.tone({ type: 'triangle', f: 660, dur: 0.06, vol: 0.1 });
        this.tone({ type: 'triangle', f: 990, t: 0.05, dur: 0.1, vol: 0.1 });
        break;
      case 'chain':
        this.tone({ type: 'sine', f: 2500 * p, dur: 0.07, vol: 0.05 });
        this.tone({ type: 'sine', f: 3300 * p, t: 0.02, dur: 0.06, vol: 0.04 });
        break;
      case 'crumble':
        this.noise({ filter: 'lowpass', f: 600, dur: 0.35, vol: 0.25 });
        break;
      case 'shield':
        this.tone({ type: 'sine', f: 880, f2: 440, dur: 0.3, vol: 0.15 });
        this.tone({ type: 'triangle', f: 1320, f2: 660, dur: 0.3, vol: 0.08 });
        break;
      case 'splash':
        this.noise({ filter: 'lowpass', f: 1400, f2: 300, dur: 0.5, vol: 0.35 });
        break;
    }
  },
};

// ---------------------------------------------------------------------------
// Музыка: маленький секвенсор. У каждой игры своя мелодия-петля.

const SONGS = {
  lobby: { bpm: 100, prog: [[60, 'M7'], [57, 'm7'], [65, 'M7'], [67, 'M']], bass: 'x.....x...x.....', kick: 'x.......x.......', snare: '....x.......x...', hat: '..x...x...x...x.', arp: [0, 2, 1, 3, 2, 1], arpWave: 'triangle', lead: 'triangle', seed: 3, pad: true },
  obby: { bpm: 136, prog: [[62, 'm'], [58, 'M'], [60, 'M'], [57, 'm']], bass: 'x.x...x.x.x...x.', kick: 'x...x...x...x...', snare: '....x.......x...', hat: 'x.x.x.x.x.x.x.x.', arp: [0, 1, 2, 3], arpWave: 'square', lead: 'square', seed: 7 },
  slap: { bpm: 146, prog: [[57, 'm'], [57, 'm'], [53, 'M'], [55, 'M']], bass: 'x..x..x.x..x..x.', kick: 'x..x..x...x.....', snare: '....x.......x..x', hat: 'xxx.xxx.xxx.xxx.', arp: [0, 2, 1, 2], arpWave: 'sawtooth', lead: 'square', seed: 11 },
  blocks: { bpm: 124, prog: [[60, 'M'], [64, 'm'], [57, 'm'], [65, 'M']], bass: 'x.x.x.x.x.x.x.x.', kick: 'x...x...x...x...', snare: '....x.......x...', hat: '..x...x...x...x.', arp: [0, 1, 2, 3, 2, 1], arpWave: 'square', lead: 'triangle', seed: 21 },
  glass: { bpm: 92, prog: [[57, 'm'], [53, 'M'], [52, 'M'], [57, 'm']], bass: 'x.......x.......', kick: 'x.......x..x....', snare: '........x.......', hat: 'x...x...x...x...', arp: [0, 1, 2, 1], arpWave: 'triangle', lead: 'sine', seed: 5, pad: true },
  chained: { bpm: 112, prog: [[55, 'M'], [52, 'm'], [60, 'M'], [62, 'M']], bass: 'x...x.x.x...x.x.', kick: 'x.......x.x.....', snare: '....x.......x...', hat: '..x...x...x...xx', arp: [0, 1, 2, 3, 2, 1, 2, 1], arpWave: 'triangle', lead: 'square', seed: 13, pad: true },
  lava: { bpm: 140, prog: [[52, 'm'], [52, 'm'], [48, 'M'], [50, 'M']], bass: 'xx.xx.xx.xx.x.x.', kick: 'x...x...x...x...', snare: '....x.......x...', hat: 'x.xxx.xxx.xxx.xx', arp: [0, 1, 2, 1], arpWave: 'sawtooth', lead: 'square', seed: 17 },
};

const CHORD = { M: [0, 4, 7, 12], m: [0, 3, 7, 12], M7: [0, 4, 7, 11], m7: [0, 3, 7, 10] };

function midiHz(m) { return 440 * Math.pow(2, (m - 69) / 12); }

function makeRng(seed) {
  let s = seed * 9301 + 49297;
  return () => { s = (s * 9301 + 49297) % 233280; return s / 233280; };
}

const Music = {
  name: null,
  pending: null,
  song: null,
  step: 0,
  next: 0,
  timer: null,
  melody: null,

  play(name) {
    this.pending = name;
    if (!Sound.ctx) return;
    if (this.name === name && this.timer) return;
    this.stop();
    this.name = name;
    this.song = SONGS[name] || SONGS.lobby;
    this.melody = this.makeMelody(this.song);
    this.step = 0;
    this.next = Sound.ctx.currentTime + 0.12;
    this.duck(false);
    this.timer = setInterval(() => this.tick(), 25);
  },

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    this.name = null;
  },

  duck(on) {
    if (!Sound.ctx) return;
    const g = Sound.musicDuck.gain;
    const t = Sound.ctx.currentTime;
    g.cancelScheduledValues(t);
    g.setTargetAtTime(on ? 0.0001 : 1, t, on ? 0.05 : 0.15);
  },

  // Мелодия из нот аккорда: два такта, детерминированно по seed.
  makeMelody(song) {
    const rng = makeRng(song.seed);
    const out = [];
    for (let i = 0; i < 32; i++) {
      const strong = i % 4 === 0;
      if (rng() < (strong ? 0.75 : 0.28)) out.push({ deg: Math.floor(rng() * 4), len: strong && rng() < 0.5 ? 2 : 1 });
      else out.push(null);
    }
    return out;
  },

  tick() {
    const ctx = Sound.ctx;
    if (!ctx || !this.song) return;
    const spb = 60 / this.song.bpm / 4;
    while (this.next < ctx.currentTime + 0.16) {
      this.playStep(this.step, this.next, spb);
      this.step++;
      this.next += spb;
    }
  },

  playStep(s, t, spb) {
    const song = this.song;
    const bus = Sound.musicBus;
    const i = s % 16;
    const bar = Math.floor(s / 16) % song.prog.length;
    const [root, q] = song.prog[bar];
    const tones = CHORD[q];
    const at = t - Sound.ctx.currentTime;
    const on = (pat) => pat[i] === 'x';

    if (on(song.kick)) Sound.tone({ type: 'sine', f: 150, f2: 42, dur: 0.16, slide: 0.12, vol: 0.5, t: at, bus });
    if (on(song.snare)) {
      Sound.noise({ f: 1800, q: 0.7, dur: 0.12, vol: 0.18, t: at, bus });
      Sound.tone({ type: 'triangle', f: 210, f2: 160, dur: 0.07, vol: 0.12, t: at, bus });
    }
    if (on(song.hat)) Sound.noise({ filter: 'highpass', f: 7500, dur: 0.035, vol: 0.06, t: at, bus });
    if (on(song.bass)) Sound.tone({ type: 'triangle', f: midiHz(root - 24), dur: spb * 1.8, vol: 0.32, t: at, bus });
    if (on(song.bass)) Sound.tone({ type: 'sawtooth', f: midiHz(root - 24), dur: spb * 1.2, vol: 0.05, t: at, bus, filter: 'lowpass', ff: 500 });

    const arpStep = song.arp[s % song.arp.length];
    if (i % 2 === 0 || song.bpm < 110) {
      Sound.tone({ type: song.arpWave, f: midiHz(root + tones[arpStep % tones.length]), dur: spb * 0.9, vol: song.arpWave === 'triangle' ? 0.06 : 0.026, t: at, bus, filter: 'lowpass', ff: 2600 });
    }
    if (song.pad && i === 0) {
      for (const k of tones.slice(0, 3)) Sound.tone({ type: 'sine', f: midiHz(root - 12 + k), dur: spb * 15, attack: 0.2, vol: 0.05, t: at, bus });
    }
    const m = this.melody[s % 32];
    if (m && Math.floor(s / 32) % 2 === 1) {
      Sound.tone({ type: song.lead, f: midiHz(root + 12 + tones[m.deg]), dur: spb * m.len * 1.6, vol: song.lead === 'square' ? 0.035 : 0.07, t: at, bus, filter: 'lowpass', ff: 3200 });
    }
  },
};
