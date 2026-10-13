/* ===== 09_main.js ===== */
// Запуск: загружаем сохранённую память, собираем мозг из встроенной модели и включаем интерфейс.
(function main() {
  const saved = U.store.get(STORE_KEY, {}) || {};
  const brain = new Brain(AMIGO_MODEL, {
    profile: saved.profile, settings: saved.settings, customs: saved.customs,
    onSave: data => U.store.set(STORE_KEY, data),
  });
  const app = new App(brain);
  window.amigo = { brain, app };
  const go = () => app.start();
  // офлайн-режим и установка на телефон (в приложении для Android это не нужно — там всё уже внутри)
  if ('serviceWorker' in navigator && !window.AmigoAndroid && (location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1')) {
    window.addEventListener('load', () => { navigator.serviceWorker.register('sw.js').catch(() => { /* без офлайна */ }); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', go); else go();
})();
