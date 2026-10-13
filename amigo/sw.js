// Служебный помощник (service worker) Амиго: сохраняет приложение на телефоне,
// чтобы оно открывалось и работало без интернета. Версию обновляет tools/build.js.
const VERSION = 'amigo-2.0-deb49947';
const FONTS = 'amigo-fonts'; // шрифты не меняются между версиями, их кэш не удаляем
const SHELL = ['index.html', 'manifest.webmanifest', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/maskable-512.png', 'icons/apple-touch-icon.png', 'icons/favicon-32.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL.map(u => new Request(u, { cache: 'reload' })))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION && k !== FONTS && k.startsWith('amigo-')).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
// уведомление по таймеру, когда Амиго свёрнут (на Android это работает только через service worker)
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window' }).then(list => list.length ? list[0].focus() : self.clients.openWindow('./')));
});
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // шрифты Google: берём из кэша, если уже скачаны
  if (/fonts\.(googleapis|gstatic)\.com$/.test(url.hostname)) {
    e.respondWith(caches.open(FONTS).then(async c => {
      const hit = await c.match(req); if (hit) return hit;
      try { const r = await fetch(req); if (r.ok || r.type === 'opaque') c.put(req, r.clone()); return r; } catch (err) { return new Response('', { status: 504 }); }
    }));
    return;
  }
  // Википедия, погода, Claude — только из сети, ничего не храним
  if (url.origin !== self.location.origin) return;
  const scope = new URL(self.registration.scope).pathname;
  const path = url.pathname.startsWith(scope) ? url.pathname.slice(scope.length) : null;
  // само приложение — это только «./» и «index.html»; остальные страницы (Amigo.apk, README и т. п.) не трогаем
  const isShell = path === '' || path === 'index.html';
  if (req.mode === 'navigate' && !isShell) return;
  if (!isShell && !SHELL.includes(path)) return;
  const key = isShell ? 'index.html' : path;
  // сразу из кэша, а в фоне скачиваем свежую версию для следующего запуска
  e.respondWith(caches.open(VERSION).then(async c => {
    const hit = await c.match(key);
    const fresh = fetch(req).then(r => {
      const html = /text\/html/.test(r.headers.get('content-type') || '');
      if (r.ok && (!isShell || html)) c.put(key, r.clone());
      return r;
    }).catch(() => null);
    if (hit) { e.waitUntil(fresh); return hit; }
    const r = await fresh;
    return r || new Response('Нет связи, а Амиго ещё не сохранён на устройстве. Открой его один раз с интернетом.', { status: 503, headers: { 'content-type': 'text/plain; charset=utf-8' } });
  }));
});
