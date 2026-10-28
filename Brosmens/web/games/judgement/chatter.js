// Живой сервер: очередь реплик ботов на весь сервер (строка каждые 4–8 с, события — вне очереди),
// перепалки «токсик → ответ», реакции на смерть/«MISS» игрока, Клод всегда дружелюбный,
// часть реплик пишет ИИ (aiBotLine). Плюс «пузыри» над головами как в роблоксе (белая плашка ~4 с, не больше 3).
import * as THREE from 'three';
import { pick, rand, typingDelay } from '../../shared/bots.js';
import { aiBotLine, aiEnabled } from '../../shared/ai.js';
import { LINES, CLAUDE } from './lines.js';

const P = new THREE.Vector3();
const MKEY = { start: 'm_start', kill: 'm_kill', dodge: 'm_dodge', force: 'm_force', blue: 'm_blue', low: 'm_low', win: 'm_win', lose: 'm_lose', idle: 'm_idle' };

// опечатки — по символам (Array.from), чтобы не разрезать эмодзи пополам
function typoize(s0) {
  const s = Array.from(s0);
  if (s.length < 6 || Math.random() > 0.22) return s0;
  const i = Math.floor(rand(1, s.length - 2)), r = Math.random();
  if (/\p{Extended_Pictographic}/u.test(s[i] + s[i + 1])) return s0;
  if (r < 0.4) [s[i], s[i + 1]] = [s[i + 1], s[i]];
  else if (r < 0.75) s.splice(i, 1);
  else if (!/\p{Extended_Pictographic}/u.test(s[s.length - 1])) s.push(s[s.length - 1]);
  return s.join('');
}

export function createChatter(G, chat) {
  const queue = [];
  const clock = () => performance.now() / 1000;
  let nextAt = 0, lastSaid = -99, lastBot = null, streak = [], lastStreakAt = -99, epoch = 0;
  const said = new Map(); // ключ события → когда последний раз говорили (чтобы не повторяться)

  // ---------- пузыри над головой ----------
  const layer = document.createElement('div'); layer.className = 'jd-bubbles'; document.body.appendChild(layer);
  const bubbles = [];
  let lastLog = null;
  function bubble(f, text) {
    for (let i = bubbles.length - 1; i >= 0; i--) if (bubbles[i].f === f) { bubbles[i].el.remove(); bubbles.splice(i, 1); }
    while (bubbles.length >= 3) bubbles.shift().el.remove();
    const el = document.createElement('div'); el.className = 'jd-bubble'; el.textContent = text.length > 90 ? text.slice(0, 88) + '…' : text;
    layer.appendChild(el);
    bubbles.push({ f, el, t0: clock() });
  }
  function updateBubbles() {
    const log = chat.log;
    if (log.length && log[log.length - 1] !== lastLog) {
      let i = log.length - 1;
      while (i > 0 && log[i - 1] !== lastLog) i--;
      if (lastLog === null) i = log.length - 1;
      for (; i < log.length; i++) {
        const e = log[i], f = G.fighters.find((x) => x.name === e.name) || (G.state === 'lobby' ? G.lobby?.actorByName(e.name) : null);
        // в катсцене Судья «говорит» в диалоговом окне — пузырь над его головой не нужен
        if (f && !(f.team === 'monster' && (G.state === 'intro' || G.state === 'outro' || G.state === 'end'))) bubble(f, e.text);
      }
      lastLog = log[log.length - 1];
    }
    const t = clock(), cam = G.camera, W = innerWidth, H = innerHeight;
    for (let i = bubbles.length - 1; i >= 0; i--) {
      const b = bubbles[i], age = t - b.t0, f = b.f;
      const gone = f.lobby ? G.state !== 'lobby' : !G.fighters.includes(f);
      if (age > 4 || !f.model.root.visible || gone) { b.el.remove(); bubbles.splice(i, 1); continue; }
      P.set(f.pos.x, f.pos.y + f.model.barY + 0.4, f.pos.z).project(cam);
      if (P.z > 1 || Math.abs(P.x) > 1.2 || P.y > 1.3 || P.y < -1.2) { b.el.style.display = 'none'; continue; }
      b.el.style.display = 'block';
      const x = (P.x * 0.5 + 0.5) * W, y = Math.max(H * 0.2 + 46, (-P.y * 0.5 + 0.5) * H - 30); // не залезаем на таймер
      b.el.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px) translate(-50%,-100%)`;
      b.el.style.opacity = age > 3.6 ? ((4 - age) / 0.4).toFixed(2) : '1';
    }
  }

  // ---------- выбор реплики ----------
  const isMonsterBot = (bot) => G.monster && G.monster.bot === bot;
  function line(bot, ev, vars = {}) {
    let arr, toxic = false;
    if (bot.id === 'claude') {
      const pack = CLAUDE[G.playerSide === 'monster' && G.state !== 'lobby' ? 'vs' : 'team'];
      arr = pack[ev] || LINES[ev]?.nice || pack.idle;
    } else {
      const key = isMonsterBot(bot) ? MKEY[ev] || 'm_idle' : ev;
      const L = LINES[key] || LINES.idle;
      toxic = Math.random() < (bot.toxic ?? 0.4) * 0.85;
      arr = toxic ? L.toxic : L.nice;
    }
    let s = pick(arr).replace('{t}', vars.t || 'бро').replace('{n}', vars.n ?? '');
    if (bot.id !== 'claude') {
      if (isMonsterBot(bot)) s = s.toLowerCase();
      else { if (bot.typo) s = typoize(s); if (Math.random() < 0.08 && s.length < 24) s = s.toUpperCase(); }
    }
    return { text: s, toxic };
  }

  function push(ev, bot, o = {}) {
    if (!bot) return;
    const t = clock();
    queue.push({ ev, bot, prio: o.prio ?? 1, until: t + (o.ttl ?? 6), notBefore: t + (o.delay ?? 0), vars: o.vars || {}, eventText: o.eventText || '', epoch });
    if (queue.length > 10) { queue.sort((a, b) => b.prio - a.prio); queue.length = 10; }
  }

  function speak(item) {
    const bot = item.bot, ep = epoch;
    lastSaid = clock(); nextAt = lastSaid + rand(4, 8); lastBot = bot;
    const out = (text, toxic) => {
      if (!text) return;
      const d = typingDelay(text);
      setTimeout(() => { if (ep === epoch || G.state === 'lobby' || G.state === 'end' || G.state === 'outro') chat.say(bot.name, text); }, d);
      // перепалка: на токсичную реплику кто-то огрызается
      if (toxic && Math.random() < 0.55) {
        const target = item.vars.tb && item.vars.tb !== bot ? item.vars.tb : pick(G.botProfiles.filter((b) => b !== bot && !isMonsterBot(b)));
        if (target) push('reply', target, { prio: 3, ttl: 10, delay: d / 1000 + rand(1.2, 2.8), vars: { t: bot.name } });
      }
    };
    const useAI = item.eventText && aiEnabled() && Math.random() < 0.3;
    if (useAI) {
      const et = bot.id === 'claude' && G.playerSide === 'monster' ? item.eventText + ' (твой друг-игрок сейчас играет за монстра-Судью, а ты — против него, шути по-дружески)' : item.eventText;
      aiBotLine(bot, et, { chatLog: chat.log }).then((t) => { if (t) out(t, false); else { const l = line(bot, item.ev, item.vars); out(l.text, l.toxic); } });
    } else { const l = line(bot, item.ev, item.vars); out(l.text, l.toxic); }
  }

  const someLobbyBot = () => pick(G.botProfiles.filter((b) => b.id !== 'claude'));
  const getName = () => G.lobby?.me?.name || 'бро';
  const humanBots = (alive = true) => G.humans.filter((h) => h.bot && (!alive || !h.dead)).map((h) => h.bot);
  const someHumanBot = (excl = null, alive = true) => pick(humanBots(alive).filter((b) => b !== excl && b.id !== 'claude')) || pick(humanBots(alive).filter((b) => b !== excl));
  const claude = () => G.botProfiles.find((b) => b.id === 'claude');
  const once = (key, gap) => { const t = clock(); if (t - (said.get(key) ?? -99) < gap) return false; said.set(key, t); return true; };
  const chance = (p) => Math.random() < p;

  return {
    reset() { queue.length = 0; epoch++; nextAt = clock() + 3; streak = []; said.clear(); for (const b of bubbles) b.el.remove(); bubbles.length = 0; lastLog = chat.log[chat.log.length - 1] ?? null; },
    // игровые события → реплики
    event(type, d = {}) {
      const mb = G.monster?.bot, pl = G.player, side = G.playerSide;
      if (type === 'lobby') {
        // лобби: следующий Судья хвастается, остальные обсуждают; после раунда — «гг» уже в очереди
        if (d.judge && chance(0.6)) push('lobbyJudge', d.judge, { prio: 2, delay: d.back ? 5 : 2.5, ttl: 10, eventText: 'ты следующий монстр-Судья в Судном дне, раунд начнётся через полминуты' });
        else if (d.meJudge && chance(0.7)) push('lobbyMeJudge', chance(0.4) ? claude() : someLobbyBot(), { prio: 2, delay: d.back ? 5 : 2.5, ttl: 10, vars: { t: getName() }, eventText: 'твой друг-игрок будет следующим монстром-Судьёй' });
        if (!d.back && chance(0.5)) push('lobby', claude(), { prio: 1, delay: 7, ttl: 10 });
        nextAt = Math.max(nextAt, clock() + 3);
        return;
      }
      if (type === 'start') {
        push('start', someHumanBot(), { prio: 2, delay: 1.0, ttl: 8, eventText: `начался раунд Судного дня, монстр-Судья — ${G.monster.name}` });
        if (mb) push('start', mb, { prio: 2, delay: 3.5, ttl: 10, eventText: 'ты играешь за монстра-Судью против команды людей, раунд начался' });
        else push('start', claude(), { prio: 2, delay: 3.5, ttl: 10, eventText: 'раунд начался' });
        if (side === 'human' && chance(0.6)) push('start', claude(), { prio: 1, delay: 6, ttl: 10 });
      } else if (type === 'dodge') {
        const t = clock();
        streak = streak.filter((x) => t - x < 5); streak.push(t);
        const left = d.left, src = d.src;
        if (left === 0) push('lastDodge', side === 'human' && chance(0.4) ? claude() : someHumanBot(), { prio: 3, ttl: 4, eventText: 'у монстра-Судьи кончились уклонения, следующий удар его убьёт — добивайте!' });
        else if ([10, 5, 3].includes(left) && once('dg' + left, 1)) push('dodges', someHumanBot(), { prio: 1, ttl: 5, vars: { n: left } });
        else if (streak.length >= 3 && t - lastStreakAt > 14) { lastStreakAt = t; push('missStreak', someHumanBot(src?.bot), { prio: 2, ttl: 4 }); }
        else if (src?.isPlayer && chance(0.3)) push('playerMiss', side === 'human' && chance(0.35) ? claude() : someHumanBot(), { prio: 1, ttl: 4, vars: { t: src.name } });
        else if (src?.bot && chance(0.1)) push('selfMiss', src.bot, { prio: 1, ttl: 3 });
        if (mb && chance(left <= 3 ? 0.4 : 0.07)) push(left <= 3 ? 'low' : 'dodge', mb, { prio: 1, ttl: 4, delay: 0.6 });
        if (side === 'monster' && src?.bot?.id === 'claude' && chance(0.15)) push('kill', claude(), { prio: 1, ttl: 4 });
      } else if (type === 'nearmiss') {
        if (d.h.bot && chance(0.45) && once('nm', 6)) push('nearMiss', d.h.bot, { prio: 1, ttl: 3 });
      } else if (type === 'force') {
        const fl = G.humans.filter((h) => h.bot && !h.dead);
        if (fl.length && chance(0.75)) push('force', pick(fl).bot, { prio: 2, ttl: 4, delay: 0.3, eventText: 'монстр-Судья отбросил всю команду «Отталкиванием»' });
        if (chance(0.5)) push('forceAfter', side === 'human' && chance(0.3) ? claude() : someHumanBot(), { prio: 1, ttl: 6, delay: 2.2 });
        if (mb && chance(0.3)) push('force', mb, { prio: 1, ttl: 4, delay: 1.2 });
        if (side === 'monster' && chance(0.3)) push('force', claude(), { prio: 1, ttl: 4, delay: 1.6 });
      } else if (type === 'blue') {
        push('blue', side === 'human' && chance(0.3) ? claude() : someHumanBot(), { prio: 3, ttl: 4, delay: 0.4, eventText: 'монстр-Судья начал «Синюю атаку»: голубые стены — стоять, белые — прыгать' });
        if (mb && chance(0.6)) push('blue', mb, { prio: 2, ttl: 5, delay: 1.8 });
      } else if (type === 'hurt') {
        const h = d.h, t = clock();
        if (h.dead) return;
        if (h.bot && h.hp / h.maxHp < 0.25 && t - h.lowAt > 22 && chance(0.5)) { h.lowAt = t; push('lowhp', h.bot, { prio: 1, ttl: 4, vars: { n: Math.max(1, Math.ceil(h.hp)) }, eventText: 'у тебя мало HP, Судья тебя почти убил' }); }
        else if (h.isPlayer && side === 'human' && h.hp / h.maxHp < 0.3 && t - h.lowAt > 22) { h.lowAt = t; push('lowhp', claude(), { prio: 2, ttl: 4 }); }
        if (h.bot && d.cause === 'синяя атака' && chance(0.3) && once('bh', 8)) push('blueHit', h.bot, { prio: 1, ttl: 3 });
      } else if (type === 'pie') {
        if (d.f.bot && chance(0.35)) push('pie', d.f.bot, { prio: 1, ttl: 4 });
        else if (chance(0.25) && once('po', 15)) push('pieOther', someHumanBot(d.f.bot), { prio: 1, ttl: 4 });
      } else if (type === 'potion') {
        if (d.f.bot && chance(0.3)) push('potion', d.f.bot, { prio: 1, ttl: 4 });
      } else if (type === 'secondlife') {
        if (d.h.bot && chance(0.75)) push('secondLife', d.h.bot, { prio: 2, ttl: 4, delay: 0.5 });
      } else if (type === 'reload') {
        if (d.f.bot && chance(0.15)) push('reload', d.f.bot, { prio: 1, ttl: 3 });
      } else if (type === 'kill') {
        const h = d.h;
        if (h.bot && chance(0.75)) push('death', h.bot, { prio: 2, ttl: 5, delay: 0.6, eventText: `тебя (человека) убил монстр-Судья ${G.monster.name} атакой «${d.cause}» в игре Судный День` });
        if (h.isPlayer) {
          push('playerDeath', someHumanBot(), { prio: 3, ttl: 6, delay: 1.2, vars: { t: h.name } });
          if (side === 'human') push('playerDeath', claude(), { prio: 3, ttl: 8, delay: 3.2, vars: { t: h.name } });
        } else if (chance(0.35)) push('otherDeath', someHumanBot(h.bot), { prio: 1, ttl: 5, delay: 2, vars: { t: h.name } });
        if (mb && chance(0.6)) push('kill', mb, { prio: 2, ttl: 5, delay: 1.5, vars: { t: h.name }, eventText: `ты (монстр-Судья) убил игрока ${h.name}` });
        if (side === 'monster' && h.bot?.id === 'claude') push('death', claude(), { prio: 3, ttl: 6, delay: 0.8 });
      } else if (type === 'end') {
        const humansWon = d.winner === 'humans', time = d.why === 'time';
        const hb = someHumanBot(null, false);
        push(humansWon ? (time ? 'timeWin' : 'win') : 'lose', hb, { prio: 3, ttl: 8, delay: 0.5, vars: { t: G.monster.name }, eventText: humansWon ? 'люди победили Судью' : 'Судья победил людей' });
        const hb2 = someHumanBot(hb, false);
        if (hb2 && chance(0.7)) push(humansWon ? (time ? 'timeWin' : 'win') : 'lose', hb2, { prio: 3, ttl: 10, delay: 1.5, vars: { t: G.monster.name } });
        if (mb) push(humansWon ? 'lose' : 'win', mb, { prio: 3, ttl: 10, delay: 2.5, eventText: humansWon ? 'тебя, монстра, победили люди' : 'ты, монстр, победил людей' });
        const cw = side === 'monster' ? (humansWon ? (time ? 'timeWin' : 'win') : 'lose') : humansWon ? (time ? 'timeWin' : 'win') : 'lose';
        push(cw, claude(), { prio: 3, ttl: 12, delay: 3.5 });
      }
    },
    update() {
      updateBubbles();
      const t = clock();
      for (let i = queue.length - 1; i >= 0; i--) if (queue[i].until < t || queue[i].epoch !== epoch) queue.splice(i, 1);
      let best = null;
      for (const it of queue) if (it.notBefore <= t && (!best || it.prio > best.prio)) best = it;
      const gap = t - lastSaid;
      if (best && (t >= nextAt || (best.prio >= 2 && gap >= 2.2) || (best.prio >= 3 && gap >= 1.2))) {
        queue.splice(queue.indexOf(best), 1);
        speak(best);
        return;
      }
      // в лобби болтают реже (раз в 6–12 с): кто следующий Судья, души, зелья, пироги
      if (!best && t >= nextAt && G.state === 'lobby') {
        const bot = pick(G.botProfiles.filter((b) => b !== lastBot));
        if (bot) { speak({ ev: 'lobby', bot, vars: { t: pick(G.botProfiles.filter((b) => b !== bot))?.name || 'бро' }, eventText: 'вы в лобби Судного дня (отель с фонтаном) ждёте следующий раунд' }); nextAt = clock() + rand(6, 12); }
        return;
      }
      // пауза затянулась — кто-то пишет просто так (гарантия: строка каждые 4–8 с)
      if (!best && t >= nextAt && G.state === 'fight') {
        // кто пишет «просто так»: болтливые чаще, живые чаще мёртвых
        const pool = G.botProfiles.filter((b) => b !== lastBot);
        let sum = 0; for (const b of pool) sum += (b.chatty ?? 0.6) * (b.dead ? 0.35 : 1);
        let r = Math.random() * sum, bot = pool[0];
        for (const b of pool) { r -= (b.chatty ?? 0.6) * (b.dead ? 0.35 : 1); if (r <= 0) { bot = b; break; } }
        if (!bot) return;
        const toxicBot = !isMonsterBot(bot) && bot.id !== 'claude' && (bot.toxic ?? 0) > 0.5;
        if (toxicBot && chance(0.3)) {
          // подкол: в другого бота (тот ответит) или в игрока
          const others = G.fighters.filter((f) => f.team === 'human' && f.bot !== bot && !f.dead);
          const tf = pick(others);
          if (tf) { speak({ ev: 'taunt', bot, vars: { t: tf.name, tb: tf.bot }, eventText: '' }); return; }
        }
        speak({ ev: 'idle', bot, vars: { n: isMonsterBot(bot) || bot.id !== 'claude' ? Math.ceil(G.roundLeft) : G.monster?.dodges }, eventText: `идёт раунд Судного дня, осталось ${Math.ceil(G.roundLeft)} секунд, у Судьи осталось ${G.monster?.dodges} уклонений из 15` });
      }
    },
  };
}
