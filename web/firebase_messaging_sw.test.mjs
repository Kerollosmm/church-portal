// Unit tests for Firebase Messaging Service Worker (web/firebase-messaging-sw.js)
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const {
  sanitizeLink,
  isForbiddenWebType,
  isWithinQuietHours,
  handlePushEvent,
  handleNotificationClick,
} = require('./firebase-messaging-sw.js');

test('sanitizeLink rejects non-relative or dangerous paths', () => {
  assert.equal(sanitizeLink(''), '/');
  assert.equal(sanitizeLink(null), '/');
  assert.equal(sanitizeLink('https://evil.com'), '/');
  assert.equal(sanitizeLink('//evil.com'), '/');
  assert.equal(sanitizeLink('javascript:alert(1)'), '/');
  assert.equal(sanitizeLink('/valid/path'), '/valid/path');
  assert.equal(sanitizeLink('/valid/path?ref=1#hash'), '/valid/path?ref=1#hash');
  assert.equal(sanitizeLink('/with<tag>'), '/');
  assert.equal(sanitizeLink('/with\x00null'), '/');
  assert.equal(sanitizeLink('/with space'), '/');
});

test('isForbiddenWebType detects forbidden high-frequency types', () => {
  assert.equal(isForbiddenWebType('verse_daily'), true);
  assert.equal(isForbiddenWebType('katameros_daily'), true);
  assert.equal(isForbiddenWebType('feasts'), true);
  assert.equal(isForbiddenWebType('announcements'), false);
  assert.equal(isForbiddenWebType('seasons'), false);
  assert.equal(isForbiddenWebType('reminders'), false);
});

test('isWithinQuietHours correctly detects day vs overnight windows', () => {
  const quietOff = { enabled: false, start: '23:00', end: '07:00' };
  assert.equal(isWithinQuietHours(new Date(2026, 10, 9, 23, 30), quietOff), false);

  const quietOvernight = { enabled: true, start: '23:00', end: '07:00' };
  // 23:30 -> in quiet hours
  assert.equal(isWithinQuietHours(new Date(2026, 10, 9, 23, 30), quietOvernight), true);
  // 03:00 -> in quiet hours
  assert.equal(isWithinQuietHours(new Date(2026, 10, 9, 3, 0), quietOvernight), true);
  // 06:59 -> in quiet hours
  assert.equal(isWithinQuietHours(new Date(2026, 10, 9, 6, 59), quietOvernight), true);
  // 07:00 -> outside quiet hours
  assert.equal(isWithinQuietHours(new Date(2026, 10, 9, 7, 0), quietOvernight), false);
  // 12:00 -> outside quiet hours
  assert.equal(isWithinQuietHours(new Date(2026, 10, 9, 12, 0), quietOvernight), false);

  const quietDaytime = { enabled: true, start: '13:00', end: '15:00' };
  assert.equal(isWithinQuietHours(new Date(2026, 10, 9, 14, 0), quietDaytime), true);
  assert.equal(isWithinQuietHours(new Date(2026, 10, 9, 16, 0), quietDaytime), false);
});

test('handlePushEvent always shows visible notification (iOS WebKit requirement)', async () => {
  const shown = [];
  const postedMessages = [];

  const mockSelf = {
    registration: {
      showNotification: async (title, options) => {
        shown.push({ title, options });
      },
    },
    clients: {
      matchAll: async () => [
        {
          postMessage: (msg) => postedMessages.push(msg),
        },
      ],
    },
  };

  const pushEvent = {
    data: {
      json: () => ({
        data: {
          nid: 'msg_101',
          title: 'قداس باكر',
          body: 'يبدأ القداس بعد قليل',
          link: '/schedule',
          lang: 'ar',
          type: 'announcements',
        },
      }),
    },
  };

  await handlePushEvent(pushEvent, mockSelf);

  assert.equal(shown.length, 1);
  assert.equal(shown[0].title, 'قداس باكر');
  assert.equal(shown[0].options.body, 'يبدأ القداس بعد قليل');
  assert.equal(shown[0].options.tag, 'msg_101');
  assert.equal(shown[0].options.renotify, true);
  assert.equal(shown[0].options.data.link, '/schedule');
  assert.equal(postedMessages.length, 1);
  assert.equal(postedMessages[0].nid, 'msg_101');
});

test('handlePushEvent falls back to generic update on forbidden web type', async () => {
  const shown = [];
  const mockSelf = {
    registration: {
      showNotification: async (title, options) => {
        shown.push({ title, options });
      },
    },
    clients: {
      matchAll: async () => [],
    },
  };

  const pushEvent = {
    data: {
      json: () => ({
        data: {
          nid: 'msg_forbidden',
          title: 'آية اليوم',
          body: 'سريّة',
          link: '/verse',
          lang: 'ar',
          type: 'verse_daily', // Forbidden on web push!
        },
      }),
    },
  };

  await handlePushEvent(pushEvent, mockSelf);

  assert.equal(shown.length, 1);
  assert.equal(shown[0].title, 'تحديث من الكنيسة');
  assert.equal(shown[0].options.body, 'اضغط للاطلاع على التحديثات');
});

test('handleNotificationClick closes notification and focuses/opens window', async () => {
  let closed = false;
  let focused = false;
  const posted = [];

  const mockEvent = {
    notification: {
      close: () => {
        closed = true;
      },
      data: {
        link: '/schedule',
      },
    },
  };

  const mockSelf = {
    clients: {
      matchAll: async () => [
        {
          focus: async () => {
            focused = true;
          },
          postMessage: (msg) => {
            posted.push(msg);
          },
        },
      ],
      openWindow: async () => {},
    },
  };

  await handleNotificationClick(mockEvent, mockSelf);

  assert.equal(closed, true);
  assert.equal(focused, true);
  assert.equal(posted.length, 1);
  assert.equal(posted[0].type, 'open');
  assert.equal(posted[0].link, '/schedule');
});

test('handlePushEvent treats plural type "reminders" as reminder for quiet-hours bypass', async () => {
  // Mock indexedDB minimal read-only quietHours store so handlePushEvent reads remindersRespectQuietHours=false
  const prevIndexedDb = globalThis.indexedDB;
  globalThis.indexedDB = {
    open: () => {
      const req = { onupgradeneeded: null, onsuccess: null, onerror: null };
      setTimeout(() => {
        req.onsuccess?.({
          target: {},
        });
      }, 0);
      req.result = {
        transaction: () => ({
          objectStore: () => ({
            get: () => {
              const gReq = { onsuccess: null, onerror: null, result: { value: { enabled: true, start: '00:00', end: '23:59', remindersRespectQuietHours: false } } };
              setTimeout(() => gReq.onsuccess?.(), 0);
              return gReq;
            },
            put: () => {},
            index: () => ({ count: () => ({ onsuccess: null }) }),
          }),
          oncomplete: null,
          onerror: null,
        }),
      };
      return req;
    },
  };

  try {
    const shown = [];
    const mockSelf = {
      registration: {
        showNotification: async (title, options) => shown.push({ title, options }),
      },
      clients: { matchAll: async () => [] },
    };

    const pushEvent = {
      data: {
        json: () => ({
          data: {
            nid: 'rem_plural_1',
            title: 'تذكير بالقداس',
            body: 'يبدأ بعد ساعة',
            link: '/mass-schedule',
            lang: 'ar',
            type: 'reminders',
          },
        }),
      },
    };

    await handlePushEvent(pushEvent, mockSelf);

    assert.equal(shown.length, 1);
    assert.equal(shown[0].options.silent, false);
  } finally {
    globalThis.indexedDB = prevIndexedDb;
  }
});

