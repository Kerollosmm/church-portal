// Service Worker for Church Portal Web Push Notifications (ADR-060).
// Plain service worker with zero external runtime dependencies.
// Scope: /firebase-cloud-messaging-push-scope (or site-wide when registered).

const DB_NAME = 'church_portal_push';
const DB_VERSION = 1;
const INBOX_LIMIT = 30;

function sanitizeLink(raw) {
  if (!raw || typeof raw !== 'string') return '/';
  const trimmed = raw.trim();
  if (!trimmed.startsWith('/') || trimmed.startsWith('//')) return '/';
  if (/[\x00-\x1f\x7f<>"'\s]/.test(trimmed)) return '/';
  return trimmed;
}

function isForbiddenWebType(type) {
  return type === 'verse_daily' || type === 'katameros_daily' || type === 'feasts';
}

function isWithinQuietHours(nowDate, quiet) {
  if (!quiet || !quiet.enabled) return false;
  const start = quiet.start || '23:00';
  const end = quiet.end || '07:00';

  const [sh, sm] = start.split(':').map((x) => parseInt(x, 10));
  const [eh, em] = end.split(':').map((x) => parseInt(x, 10));

  const curMinutes = nowDate.getHours() * 60 + nowDate.getMinutes();
  const startMinutes = sh * 60 + sm;
  const endMinutes = eh * 60 + em;

  if (startMinutes <= endMinutes) {
    return curMinutes >= startMinutes && curMinutes < endMinutes;
  }
  // Overnight quiet hours (e.g. 23:00 to 07:00)
  return curMinutes >= startMinutes || curMinutes < endMinutes;
}

function openPushDb() {
  return new Promise((resolve, reject) => {
    if (typeof indexedDB === 'undefined') {
      resolve(null);
      return;
    }
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = (e) => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains('inbox')) {
        const inboxStore = db.createObjectStore('inbox', { keyPath: 'nid' });
        inboxStore.createIndex('receivedAt', 'receivedAt', { unique: false });
      }
      if (!db.objectStoreNames.contains('settings')) {
        db.createObjectStore('settings', { keyPath: 'key' });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => resolve(null);
  });
}

async function getQuietSettings(db) {
  if (!db) return null;
  return new Promise((resolve) => {
    try {
      const tx = db.transaction('settings', 'readonly');
      const store = tx.objectStore('settings');
      const req = store.get('quietHours');
      req.onsuccess = () => resolve(req.result?.value || null);
      req.onerror = () => resolve(null);
    } catch (_) {
      resolve(null);
    }
  });
}

async function appendInboxItem(db, item) {
  if (!db || !item?.nid) return;
  return new Promise((resolve) => {
    try {
      const tx = db.transaction('inbox', 'readwrite');
      const store = tx.objectStore('inbox');
      store.put(item);

      // Prune older than INBOX_LIMIT
      const idx = store.index('receivedAt');
      const countReq = idx.count();
      countReq.onsuccess = () => {
        const total = countReq.result;
        if (total > INBOX_LIMIT) {
          const deleteCount = total - INBOX_LIMIT;
          let deleted = 0;
          idx.openCursor().onsuccess = (e) => {
            const cursor = e.target.result;
            if (cursor && deleted < deleteCount) {
              cursor.delete();
              deleted++;
              cursor.continue();
            }
          };
        }
      };

      tx.oncomplete = () => resolve();
      tx.onerror = () => resolve();
    } catch (_) {
      resolve();
    }
  });
}

async function hasSeenNid(db, nid) {
  if (!db || !nid) return false;
  return new Promise((resolve) => {
    try {
      const tx = db.transaction('inbox', 'readonly');
      const store = tx.objectStore('inbox');
      const req = store.get(nid);
      req.onsuccess = () => resolve(Boolean(req.result));
      req.onerror = () => resolve(false);
    } catch (_) {
      resolve(false);
    }
  });
}

async function handlePushEvent(event, selfRef = self) {
  let payload = null;
  try {
    payload = event.data ? event.data.json() : null;
  } catch (_) {
    try {
      payload = event.data ? { data: { body: event.data.text() } } : null;
    } catch (_) {}
  }

  const data = payload?.data || payload || {};
  const rawType = (data.type || '').trim();
  const isForbidden = isForbiddenWebType(rawType);

  const lang = data.lang === 'en' ? 'en' : 'ar';
  const rawNid = data.nid || `n_${Date.now()}`;
  const link = sanitizeLink(data.link);

  let title = '';
  let body = '';

  if (isForbidden || (!data.title && !data.body)) {
    title = lang === 'en' ? 'Church Update' : 'تحديث من الكنيسة';
    body = lang === 'en' ? 'Tap to view new updates' : 'اضغط للاطلاع على التحديثات';
  } else {
    title = data.title || (lang === 'en' ? 'Church Notification' : 'إشعار من الكنيسة');
    body = data.body || '';
  }

  // Open DB for quiet hours and inbox
  const db = await openPushDb();
  const quiet = await getQuietSettings(db);
  const now = new Date();
  let isQuiet = isWithinQuietHours(now, quiet);
  const isReminder = rawType === 'reminder' || rawType.startsWith('web_rem_') || Boolean(data.occurrence);
  if (isQuiet && isReminder && quiet?.remindersRespectQuietHours === false) {
    isQuiet = false;
  }

  const isDuplicate = await hasSeenNid(db, rawNid);

  // Web notification options
  const notifOptions = {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/badge-72.png',
    dir: lang === 'ar' ? 'rtl' : 'ltr',
    lang,
    tag: rawNid,
    renotify: !isDuplicate,
    silent: isQuiet,
    data: {
      nid: rawNid,
      link,
    },
  };

  // Always show visible notification (iOS WebKit compliance)
  await selfRef.registration.showNotification(title, notifOptions);

  // Append to inbox if not duplicate
  if (!isDuplicate) {
    await appendInboxItem(db, {
      nid: rawNid,
      title,
      body,
      link,
      receivedAt: now.toISOString(),
    });
  }

  // Notify any open window clients
  try {
    const clientsList = await selfRef.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    for (const client of clientsList) {
      client.postMessage({
        type: 'received',
        nid: rawNid,
        title,
        body,
        link,
      });
    }
  } catch (_) {}

  // BroadcastChannel message if available
  try {
    if (typeof BroadcastChannel !== 'undefined') {
      const bc = new BroadcastChannel('church_portal_push');
      bc.postMessage({ type: 'received', nid: rawNid });
      bc.close();
    }
  } catch (_) {}
}

async function handleNotificationClick(event, selfRef = self) {
  event.notification.close();
  const link = sanitizeLink(event.notification?.data?.link);

  try {
    const clientsList = await selfRef.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });

    // Check if an existing window client belongs to our origin
    for (const client of clientsList) {
      if ('focus' in client) {
        await client.focus();
        client.postMessage({ type: 'open', link });
        return;
      }
    }

    if (selfRef.clients && 'openWindow' in selfRef.clients) {
      await selfRef.clients.openWindow(link);
    }
  } catch (_) {
    if (selfRef.clients && 'openWindow' in selfRef.clients) {
      await selfRef.clients.openWindow(link);
    }
  }
}

// Service worker event listeners (when running inside ServiceWorkerGlobalScope)
if (typeof self !== 'undefined' && 'addEventListener' in self) {
  self.addEventListener('push', (event) => {
    event.waitUntil(handlePushEvent(event, self));
  });

  self.addEventListener('notificationclick', (event) => {
    event.waitUntil(handleNotificationClick(event, self));
  });
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    sanitizeLink,
    isForbiddenWebType,
    isWithinQuietHours,
    openPushDb,
    getQuietSettings,
    appendInboxItem,
    hasSeenNid,
    handlePushEvent,
    handleNotificationClick,
  };
}
if (typeof self !== 'undefined') {
  self.sanitizeLink = sanitizeLink;
  self.isForbiddenWebType = isForbiddenWebType;
  self.isWithinQuietHours = isWithinQuietHours;
  self.handlePushEvent = handlePushEvent;
  self.handleNotificationClick = handleNotificationClick;
}
