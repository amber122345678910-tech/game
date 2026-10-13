// Служебный помощник (service worker) Амиго: сохраняет приложение на телефоне,
// чтобы оно открывалось и работало без интернета. Версию обновляет tools/build.js.
const VERSION = 'amigo-2.0-ccb2c4a5';
const SHELL = ['./', 'index.html', 'manifest.webmanifest', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/maskable-512.png', 'icons/apple-touch-icon.png', 'icons/favicon-32.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL.map(u => new Request(u, { cache: 'reload' })))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION && k.startsWith('amigo-')).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // шрифты Google: берём из кэша, если уже скачаны
  if (/fonts\.(googleapis|gstatic)\.com$/.test(url.hostname)) {
    e.respondWith(caches.open(VERSION + '-fonts').then(async c => {
      const hit = await c.match(req); if (hit) return hit;
      try { const r = await fetch(req); if (r.ok || r.type === 'opaque') c.put(req, r.clone()); return r; } catch (err) { return new Response('', { status: 504 }); }
    }));
    return;
  }
  // Википедия, погода, Claude — только из сети, ничего не храним
  if (url.origin !== self.location.origin) return;
  // само приложение: сразу из кэша, а в фоне скачиваем свежую версию для следующего запуска
  e.respondWith(caches.open(VERSION).then(async c => {
    const key = req.mode === 'navigate' ? 'index.html' : req;
    const hit = await c.match(key, { ignoreSearch: true });
    const fresh = fetch(req).then(r => { if (r.ok) c.put(key, r.clone()); return r; }).catch(() => null);
    if (hit) { e.waitUntil(fresh); return hit; }
    const r = await fresh;
    return r || new Response('Нет связи, а Амиго ещё не сохранён на устройстве. Открой его один раз с интернетом.', { status: 503, headers: { 'content-type': 'text/plain; charset=utf-8' } });
  }));
});
