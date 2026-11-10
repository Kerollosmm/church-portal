// Web Push Client for Church Portal (ADR-060).
// Exposes window.churchPush with lazy modular Firebase JS loading from gstatic.

const DB_NAME = 'church_portal_push';
const DB_VERSION = 1;

export function isSupported(env = {}) {
  const win = env.window || (typeof window !== 'undefined' ? window : null);
  const nav = env.navigator || (typeof navigator !== 'undefined' ? navigator : null);
  if (!win || !nav) return false;
  return (
    'Notification' in win &&
    'serviceWorker' in nav &&
    'PushManager' in win
  );
}

export function openPushDb() {
  return new Promise((resolve) => {
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

let cachedMessaging = null;
let cachedSwReg = null;

export async function getFirebaseMessaging(firebaseConfig, customImport = null) {
  if (cachedMessaging) return { messaging: cachedMessaging, swRegistration: cachedSwReg };

  const importer = customImport || ((url) => import(url));
  const version =
    (typeof window !== 'undefined' && (window.firebase_core?.SDK_VERSION || window.flutterfire_web_sdk_version)) ||
    '13.1.0';

  const [appMod, msgMod] = await Promise.all([
    importer(`https://www.gstatic.com/firebasejs/${version}/firebase-app.js`),
    importer(`https://www.gstatic.com/firebasejs/${version}/firebase-messaging.js`),
  ]);

  const app =
    (appMod.getApps && appMod.getApps()[0]) ||
    appMod.initializeApp(firebaseConfig);

  const messaging = msgMod.getMessaging(app);

  let swRegistration = null;
  if (typeof navigator !== 'undefined' && 'serviceWorker' in navigator) {
    swRegistration = await navigator.serviceWorker.register('/firebase-messaging-sw.js', { scope: '/' });
    if (navigator.serviceWorker.ready) {
      await navigator.serviceWorker.ready;
    }
  }

  cachedMessaging = messaging;
  cachedSwReg = swRegistration;

  return { messaging, swRegistration, msgMod };
}

export async function enable({ vapidKey, firebaseConfig }, deps = {}) {
  const checkSupported = deps.isSupported || isSupported;
  if (!checkSupported()) return null;

  const requestPermission =
    deps.requestPermission || (() => Notification.requestPermission());
  const perm = await requestPermission();
  if (perm !== 'granted') return null;

  const { messaging, swRegistration, msgMod } = await getFirebaseMessaging(
    firebaseConfig,
    deps.customImport,
  );

  const getTokenFn = deps.getToken || msgMod.getToken;
  const token = await getTokenFn(messaging, {
    vapidKey,
    serviceWorkerRegistration: swRegistration,
  });

  return token || null;
}

export async function getToken({ vapidKey, firebaseConfig }, deps = {}) {
  const checkSupported = deps.isSupported || isSupported;
  if (!checkSupported()) return null;
  const currentPerm = deps.permission || (typeof Notification !== 'undefined' ? Notification.permission : 'default');
  if (currentPerm !== 'granted') return null;

  const { messaging, swRegistration, msgMod } = await getFirebaseMessaging(
    firebaseConfig,
    deps.customImport,
  );

  const getTokenFn = deps.getToken || msgMod.getToken;
  const token = await getTokenFn(messaging, {
    vapidKey,
    serviceWorkerRegistration: swRegistration,
  });

  return token || null;
}

export async function deleteToken({ firebaseConfig }, deps = {}) {
  const checkSupported = deps.isSupported || isSupported;
  if (!checkSupported()) return false;

  try {
    const { messaging, msgMod } = await getFirebaseMessaging(
      firebaseConfig,
      deps.customImport,
    );
    const delTokenFn = deps.deleteToken || msgMod.deleteToken;
    await delTokenFn(messaging);
    return true;
  } catch (_) {
    return false;
  }
}

export async function test(options = {}, deps = {}) {
  const checkSupported = deps.isSupported || isSupported;
  if (!checkSupported()) return false;
  const showNotif = deps.showNotification;
  if (showNotif) {
    return showNotif(options);
  }

  const reg =
    cachedSwReg ||
    (typeof navigator !== 'undefined' && 'serviceWorker' in navigator
      ? await navigator.serviceWorker.getRegistration('/')
      : null);
  if (!reg) return false;

  const title = options.title || 'اختبار الإشعارات';
  const body = options.body || 'هذا إشعار تجريبي من كنيسة القديسين مكسيموس ودوماديوس';
  const link = options.link || '/notifications';

  await reg.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/badge-72.png',
    tag: `test_${Date.now()}`,
    data: { link },
  });
  return true;
}

export async function inbox(dbOverride = null) {
  const db = dbOverride || (await openPushDb());
  if (!db) return [];

  return new Promise((resolve) => {
    try {
      const tx = db.transaction('inbox', 'readonly');
      const store = tx.objectStore('inbox');
      const idx = store.index('receivedAt');
      const items = [];
      const req = idx.openCursor(null, 'prev'); // Latest first
      req.onsuccess = (e) => {
        const cursor = e.target.result;
        if (cursor) {
          items.push(cursor.value);
          cursor.continue();
        } else {
          resolve(items);
        }
      };
      req.onerror = () => resolve([]);
    } catch (_) {
      resolve([]);
    }
  });
}

export async function clearInbox(dbOverride = null) {
  const db = dbOverride || (await openPushDb());
  if (!db) return false;

  return new Promise((resolve) => {
    try {
      const tx = db.transaction('inbox', 'readwrite');
      const store = tx.objectStore('inbox');
      store.clear();
      tx.oncomplete = () => resolve(true);
      tx.onerror = () => resolve(false);
    } catch (_) {
      resolve(false);
    }
  });
}

export async function setQuiet({ enabled, start, end, remindersRespectQuietHours }, dbOverride = null) {
  const db = dbOverride || (await openPushDb());
  if (!db) return false;

  return new Promise((resolve) => {
    try {
      const tx = db.transaction('settings', 'readwrite');
      const store = tx.objectStore('settings');
      store.put({
        key: 'quietHours',
        value: {
          enabled: Boolean(enabled),
          start: start || '23:00',
          end: end || '07:00',
          remindersRespectQuietHours: remindersRespectQuietHours !== false,
        },
      });
      tx.oncomplete = () => resolve(true);
      tx.onerror = () => resolve(false);
    } catch (_) {
      resolve(false);
    }
  });
}

export const churchPush = {
  isSupported,
  enable,
  getToken,
  deleteToken,
  test,
  inbox,
  clearInbox,
  setQuiet,
};

if (typeof window !== 'undefined') {
  window.churchPush = churchPush;
}
