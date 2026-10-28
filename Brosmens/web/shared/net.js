// Онлайн с другом без своего сервера: прямое соединение телефонов (WebRTC через PeerJS).
// Один создаёт комнату (хост), второй входит по 4-символьному коду. Найти друг друга помогает
// бесплатный публичный сервер PeerJS; сами данные игры идут напрямую между телефонами.
// Лучше всего работает в одном Wi-Fi; через мобильный интернет иногда не соединяется (NAT).
//
// const room = await hostRoom(code, 'jjs')          // хост: ждёт гостя
// const room = await joinRoom(code, 'jjs')          // гость: подключается (с повторами)
// room.send('state', {...})  room.on('input', (data) => ...)  room.onPeer((peer) => ...)  room.onLeave(fn)
// netParams() — читает ?net=host|guest&room=CODE из адреса страницы (так игры узнают, что это онлайн)
import { getProfile } from './profile.js';

const PREFIX = 'brosmens-v1-';
const ICE = { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }, { urls: 'stun:stun1.l.google.com:19302' }] };
// В тестах можно указать свой сервер: ?peerhost=localhost&peerport=9000
const params = new URLSearchParams(location.search);
const SERVER = params.get('peerhost')
  ? { host: params.get('peerhost'), port: +params.get('peerport') || 9000, path: '/', secure: false }
  : {};

let PeerCls = null;
async function loadPeer() {
  if (!PeerCls) ({ Peer: PeerCls } = await import('../vendor/peerjs.mjs'));
  return PeerCls;
}

const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // без похожих 0/O, 1/I
export function makeCode() {
  let s = '';
  for (let i = 0; i < 4; i++) s += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
  return s;
}

export function netParams() {
  const mode = params.get('net');
  const code = (params.get('room') || '').toUpperCase();
  return mode && code ? { mode, code } : null;
}

// Ссылка на страницу с параметрами онлайна (сохраняет тестовый сервер, если задан)
export function netQuery(mode, code) {
  const q = new URLSearchParams({ net: mode, room: code });
  if (params.get('peerhost')) { q.set('peerhost', params.get('peerhost')); q.set('peerport', params.get('peerport') || '9000'); }
  return '?' + q.toString();
}

const hostId = (code, scope) => `${PREFIX}${code}-${scope}`.toLowerCase();

function makeRoom(peer, isHost) {
  const handlers = {};
  const joinFns = [], leaveFns = [];
  const conns = new Set();
  const room = {
    isHost,
    peers: new Map(), // conn.peer -> профиль {name, skin}
    ping: 0,
    send(type, data) {
      const msg = { t: type, d: data };
      for (const c of conns) if (c.open) c.send(msg);
    },
    sendTo(peerId, type, data) {
      for (const c of conns) if (c.peer === peerId && c.open) c.send({ t: type, d: data });
    },
    on(type, fn) { (handlers[type] ||= []).push(fn); },
    onPeer(fn) { joinFns.push(fn); for (const [id, p] of room.peers) fn({ id, ...p }); },
    onLeave(fn) { leaveFns.push(fn); },
    connected: () => [...conns].some((c) => c.open),
    close() { for (const c of conns) c.close(); peer.destroy(); },
  };
  room._attach = (conn) => {
    conns.add(conn);
    const hello = () => conn.send({ t: '_hello', d: { name: getProfile().name, skin: getProfile().skin } });
    if (conn.open) hello(); else conn.on('open', hello);
    conn.on('data', (msg) => {
      if (!msg || typeof msg !== 'object') return;
      if (msg.t === '_hello') {
        const first = !room.peers.has(conn.peer);
        room.peers.set(conn.peer, msg.d);
        if (first) joinFns.forEach((f) => f({ id: conn.peer, ...msg.d }));
        return;
      }
      if (msg.t === '_ping') return conn.send({ t: '_pong', d: msg.d });
      if (msg.t === '_pong') { room.ping = Math.round(performance.now() - msg.d); return; }
      (handlers[msg.t] || []).forEach((f) => f(msg.d, conn.peer));
    });
    const gone = () => {
      if (!conns.delete(conn)) return;
      const p = room.peers.get(conn.peer);
      room.peers.delete(conn.peer);
      leaveFns.forEach((f) => f({ id: conn.peer, ...(p || {}) }));
    };
    conn.on('close', gone);
    conn.on('error', gone);
  };
  // пинг раз в 2 с — для индикатора связи
  const pingT = setInterval(() => {
    if (peer.destroyed) return clearInterval(pingT);
    for (const c of conns) if (c.open) c.send({ t: '_ping', d: performance.now() });
  }, 2000);
  return room;
}

// Хост: регистрирует id комнаты и принимает гостей
export async function hostRoom(code, scope) {
  const Peer = await loadPeer();
  return new Promise((resolve, reject) => {
    const peer = new Peer(hostId(code, scope), { ...SERVER, config: ICE, debug: 0 });
    const room = makeRoom(peer, true);
    let done = false;
    peer.on('open', () => { done = true; resolve(room); });
    peer.on('connection', (conn) => room._attach(conn));
    peer.on('error', (e) => {
      if (!done) { done = true; peer.destroy(); reject(e); }
    });
    // если сервер отвалился (телефон уснул) — переподключаемся с тем же id
    peer.on('disconnected', () => { if (!peer.destroyed) setTimeout(() => peer.reconnect(), 1000); });
  });
}

// Гость: подключается к хосту; повторяет попытки, пока хост не появится (переход между страницами)
export async function joinRoom(code, scope, { timeoutMs = 30000 } = {}) {
  const Peer = await loadPeer();
  const peer = await new Promise((resolve, reject) => {
    const p = new Peer({ ...SERVER, config: ICE, debug: 0 });
    p.on('open', () => resolve(p));
    p.on('error', reject);
  });
  const room = makeRoom(peer, false);
  const target = hostId(code, scope);
  const started = performance.now();
  for (;;) {
    const ok = await new Promise((resolve) => {
      const conn = peer.connect(target, { reliable: true, serialization: 'json' });
      const fail = () => resolve(false);
      const t = setTimeout(() => { conn.close(); fail(); }, 6000);
      conn.on('open', () => { clearTimeout(t); room._attach(conn); resolve(true); });
      conn.on('error', () => { clearTimeout(t); fail(); });
      peer.once('error', () => { clearTimeout(t); fail(); });
    });
    if (ok) return room;
    if (performance.now() - started > timeoutMs) { peer.destroy(); throw new Error('Не удалось подключиться к комнате'); }
    await new Promise((r) => setTimeout(r, 1500));
  }
}
