// onAI: офлайн для веб-версии (iPhone, «На экран Домой»).
// Всё, что приложение скачало при запуске, ложится в кэш, и суфлёр открывается
// без интернета. CI подставляет коммит вместо __BUILD__: новая сборка — новый кэш.
// Предыдущий кэш держим как запасной: если обновление не успело скачаться,
// суфлёр без сети откроется в прошлой версии.
const CACHE = 'suflyor-__BUILD__';

self.addEventListener('install', (event) => {
  self.skipWaiting();
  // Страница и то, что браузер берёт до запуска приложения
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll([
    self.registration.scope, 'manifest.json', 'favicon.png',
    'icons/Icon-192.png', 'icons/apple-touch-icon.png',
  ])));
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const older = (await caches.keys()).filter((key) => key !== CACHE);
    for (const key of older.slice(0, -1)) await caches.delete(key);
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) {
    return;
  }
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(request, { ignoreSearch: true });
    if (cached) return cached;
    try {
      const response = await fetch(request);
      if (response.status === 200) cache.put(request, response.clone());
      return response;
    } catch (error) {
      const previous = await caches.match(request, { ignoreSearch: true });
      if (previous) return previous;
      throw error;
    }
  })());
});
