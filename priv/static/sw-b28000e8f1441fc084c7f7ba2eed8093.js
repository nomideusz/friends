// Service Worker for Friends PWA
const CACHE_NAME = 'friends-v1';
const STATIC_ASSETS = [
    '/',
    '/assets/app.css',
    '/assets/app.js',
    '/images/icon-192.png',
    '/images/icon-512.png'
];

// Install event - cache static assets
self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => {
            // Don't fail if some assets can't be cached
            return Promise.allSettled(
                STATIC_ASSETS.map(url =>
                    cache.add(url).catch(err => console.log('Cache skip:', url))
                )
            );
        })
    );
    // Activate immediately
    self.skipWaiting();
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((cacheNames) => {
            return Promise.all(
                cacheNames
                    .filter((name) => name !== CACHE_NAME)
                    .map((name) => caches.delete(name))
            );
        })
    );
    // Take control immediately
    self.clients.claim();
});

// Fetch event - network first, fallback to cache
self.addEventListener('fetch', (event) => {
    // Skip non-GET requests
    if (event.request.method !== 'GET') return;

    // Skip LiveView websocket connections
    if (event.request.url.includes('/live/websocket')) return;

    // Skip API requests and form submissions
    if (event.request.url.includes('/api/')) return;

    // For navigation requests (HTML pages), always try network first
    if (event.request.mode === 'navigate') {
        event.respondWith(
            fetch(event.request)
                .catch(() => caches.match('/'))
        );
        return;
    }

    // For static assets, try cache first then network
    if (event.request.url.includes('/assets/')) {
        event.respondWith(
            caches.match(event.request).then((cached) => {
                return cached || fetch(event.request).then((response) => {
                    // Cache the new response
                    if (response.ok) {
                        const clone = response.clone();
                        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
                    }
                    return response;
                });
            })
        );
        return;
    }

    // For everything else, network first
    event.respondWith(
        fetch(event.request).catch(() => caches.match(event.request))
    );
});

// Handle messages from the app
self.addEventListener('message', (event) => {
    if (event.data === 'skipWaiting') {
        self.skipWaiting();
    }
});
