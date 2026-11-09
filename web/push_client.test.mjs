// Unit tests for web/push_client.js
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  isSupported,
  enable,
  getToken,
  deleteToken,
  test as pushTest,
  inbox,
  clearInbox,
  setQuiet,
} from './push_client.js';

test('isSupported returns false in headless environment without window', () => {
  assert.equal(isSupported({ window: null, navigator: null }), false);
});

test('isSupported returns true when window, navigator and PushManager exist', () => {
  const fakeWin = { Notification: {}, PushManager: {} };
  const fakeNav = { serviceWorker: {} };
  assert.equal(isSupported({ window: fakeWin, navigator: fakeNav }), true);
});

test('enable requests permission and returns token when granted', async () => {
  const mockApp = { name: '[DEFAULT]' };
  const mockMessaging = { app: mockApp };

  const customImport = async (url) => {
    if (url.includes('firebase-app.js')) {
      return {
        getApps: () => [],
        initializeApp: () => mockApp,
      };
    }
    if (url.includes('firebase-messaging.js')) {
      return {
        getMessaging: () => mockMessaging,
        getToken: async () => 'mock_token_abc123',
        deleteToken: async () => true,
      };
    }
    throw new Error('Unknown module ' + url);
  };

  const token = await enable(
    { vapidKey: 'test-vapid', firebaseConfig: { apiKey: 'key' } },
    {
      isSupported: () => true,
      requestPermission: async () => 'granted',
      customImport,
      getToken: async () => 'mock_token_abc123',
    },
  );

  assert.equal(token, 'mock_token_abc123');

  // Test denied permission
  const deniedToken = await enable(
    { vapidKey: 'test-vapid', firebaseConfig: { apiKey: 'key' } },
    {
      isSupported: () => true,
      requestPermission: async () => 'denied',
      customImport,
    },
  );
  assert.equal(deniedToken, null);
});

test('getToken returns token only when permission is granted', async () => {
  const token = await getToken(
    { vapidKey: 'test-vapid', firebaseConfig: {} },
    {
      isSupported: () => true,
      permission: 'granted',
      getToken: async () => 'token_xyz',
      customImport: async () => ({
        getApps: () => [],
        initializeApp: () => ({}),
        getMessaging: () => ({}),
      }),
    },
  );
  assert.equal(token, 'token_xyz');

  const noToken = await getToken(
    { vapidKey: 'test-vapid', firebaseConfig: {} },
    {
      isSupported: () => true,
      permission: 'denied',
    },
  );
  assert.equal(noToken, null);
});

test('deleteToken deletes messaging token', async () => {
  let deleted = false;
  const result = await deleteToken(
    { firebaseConfig: {} },
    {
      isSupported: () => true,
      deleteToken: async () => {
        deleted = true;
      },
      customImport: async () => ({
        getApps: () => [],
        initializeApp: () => ({}),
        getMessaging: () => ({}),
      }),
    },
  );
  assert.equal(result, true);
  assert.equal(deleted, true);
});

test('test triggers test notification', async () => {
  let shownOpts = null;
  const res = await pushTest(
    { title: 'تجربة', body: 'نص' },
    {
      isSupported: () => true,
      showNotification: async (opts) => {
        shownOpts = opts;
        return true;
      },
    },
  );
  assert.equal(res, true);
  assert.equal(shownOpts.title, 'تجربة');
});

test('inbox, clearInbox, setQuiet interact with IndexedDB stores', async () => {
  const mockStorage = {
    inbox: [
      { nid: '1', title: 'الأول', receivedAt: '2026-11-09T10:00:00Z' },
      { nid: '2', title: 'الثاني', receivedAt: '2026-11-09T11:00:00Z' },
    ],
    settings: {},
  };

  const mockDb = {
    transaction: (storeName, mode) => {
      return {
        objectStore: (name) => {
          if (name === 'inbox') {
            return {
              index: () => ({
                openCursor: (range, direction) => {
                  let index = 0;
                  const sorted = [...mockStorage.inbox].sort((a, b) =>
                    direction === 'prev'
                      ? b.receivedAt.localeCompare(a.receivedAt)
                      : a.receivedAt.localeCompare(b.receivedAt),
                  );
                  const req = {
                    onsuccess: null,
                    onerror: null,
                  };
                  setTimeout(() => {
                    function advance() {
                      if (index < sorted.length) {
                        const cursor = {
                          value: sorted[index++],
                          continue: advance,
                        };
                        req.onsuccess({ target: { result: cursor } });
                      } else {
                        req.onsuccess({ target: { result: null } });
                      }
                    }
                    advance();
                  }, 1);
                  return req;
                },
              }),
              clear: () => {
                mockStorage.inbox = [];
              },
            };
          }
          if (name === 'settings') {
            return {
              put: (item) => {
                mockStorage.settings[item.key] = item.value;
              },
            };
          }
        },
        oncomplete: null,
        onerror: null,
      };
    },
  };

  // Test setQuiet
  const quietSet = await setQuiet(
    { enabled: true, start: '22:00', end: '08:00' },
    {
      transaction: () => {
        const tx = {
          objectStore: () => ({
            put: (item) => {
              mockStorage.settings[item.key] = item.value;
            },
          }),
          oncomplete: null,
        };
        setTimeout(() => tx.oncomplete?.(), 1);
        return tx;
      },
    },
  );
  assert.equal(quietSet, true);
  assert.deepEqual(mockStorage.settings.quietHours, {
    enabled: true,
    start: '22:00',
    end: '08:00',
  });

  // Test inbox retrieval
  const items = await inbox(mockDb);
  assert.equal(items.length, 2);
  assert.equal(items[0].nid, '2'); // Descending by receivedAt

  // Test clearInbox
  const cleared = await clearInbox({
    transaction: () => {
      const tx = {
        objectStore: () => ({
          clear: () => {
            mockStorage.inbox = [];
          },
        }),
        oncomplete: null,
      };
      setTimeout(() => tx.oncomplete?.(), 1);
      return tx;
    },
  });
  assert.equal(cleared, true);
  assert.equal(mockStorage.inbox.length, 0);
});
