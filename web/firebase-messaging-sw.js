// Firebase Cloud Messaging Service Worker (scaffold for ADR-057, fully implemented in PR D).
// Runs in its own scope and never handles fetch events for pages or assets.
self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});
