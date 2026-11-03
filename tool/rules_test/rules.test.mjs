// Firestore security-rules tests. Run inside the emulator:
//   cd tool/rules_test && npm ci && npm test
// (needs Java 11+ for the Firestore emulator).
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { after, before, beforeEach, describe, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  Timestamp, deleteDoc, doc, getDoc, getDocs, collection, serverTimestamp, setDoc, updateDoc, writeBatch,
} from 'firebase/firestore';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const seed = JSON.parse(readFileSync(join(root, 'assets', 'seed', 'seed.json'), 'utf8'));
const DATE_FIELDS = new Set(['startsAt', 'endsAt', 'date', 'createdAt']);

function convert(obj) {
  if (Array.isArray(obj)) return obj.map(convert);
  if (obj && typeof obj === 'object') {
    return Object.fromEntries(Object.entries(obj).map(([k, v]) =>
      [k, DATE_FIELDS.has(k) && typeof v === 'string' && v ? Timestamp.fromDate(new Date(v)) : convert(v)]));
  }
  return obj;
}

let env;
const OWNER = 'owner-uid';
const EDITOR = 'editor-uid';
const STRANGER = 'stranger-uid';

const db = (uid) => (uid ? env.authenticatedContext(uid, { email: `${uid}@x.test` }) : env.unauthenticatedContext()).firestore();

const message = () => ({
  name: 'Mina', phone: '01012345678', email: '', message: 'Hello there', lang: 'ar', status: 'new',
  createdAt: serverTimestamp(),
});

/** A contact message batched with the throttle doc, as the app writes it. */
function contactBatch(fs, { rate } = {}) {
  const batch = writeBatch(fs);
  const msgRef = doc(collection(fs, 'contact_messages'));
  batch.set(msgRef, message());
  batch.set(doc(fs, 'meta', 'contact_rate'), rate ?? { lastAt: serverTimestamp(), lastMsgId: msgRef.id });
  return batch;
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-church-portal',
    firestore: { rules: readFileSync(join(root, 'firestore.rules'), 'utf8') },
  });
});

after(async () => env && env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, 'admins', OWNER), { email: 'owner@x.test', role: 'owner' });
    await setDoc(doc(f, 'admins', EDITOR), { email: 'editor@x.test', role: 'editor' });
    await setDoc(doc(f, 'settings', 'church'), convert(seed.settings.church));
    await setDoc(doc(f, 'clinics', 'c1'), convert(seed.clinics['dental-1']));
    await setDoc(doc(f, 'clinics', 'legacy'), { ...convert(seed.clinics['dental-1']), legacyField: 'x' });
    await setDoc(doc(f, 'contact_messages', 'm1'), {
      name: 'Mina', phone: '01012345678', email: '', message: 'Hello there', lang: 'ar', status: 'new',
      createdAt: Timestamp.now(),
    });
  });
});

describe('public', () => {
  test('reads content and settings, never writes', async () => {
    const pub = db(null);
    await assertSucceeds(getDoc(doc(pub, 'settings', 'church')));
    await assertSucceeds(getDoc(doc(pub, 'settings', 'features')));
    await assertSucceeds(getDocs(collection(pub, 'clinics')));
    await assertFails(setDoc(doc(pub, 'settings', 'features'), { theme: 'navy' }));
    await assertFails(updateDoc(doc(pub, 'clinics', 'c1'), { visible: false }));
    await assertFails(deleteDoc(doc(pub, 'clinics', 'c1')));
  });

  test('signed-in non-admin cannot write content', async () => {
    await assertFails(updateDoc(doc(db(STRANGER), 'clinics', 'c1'), { visible: false }));
    await assertFails(setDoc(doc(db(STRANGER), 'settings', 'features'), { theme: 'navy' }));
  });

  test('contact messages: public create with throttle, no reads', async () => {
    const pub = db(null);
    await assertSucceeds(contactBatch(pub).commit());
    await assertFails(getDoc(doc(pub, 'contact_messages', 'm1')));
    await assertFails(getDocs(collection(pub, 'contact_messages')));
  });
});

describe('admin content', () => {
  test('every seed document passes validation', async () => {
    const ed = db(EDITOR);
    for (const [col, docs] of Object.entries(seed)) {
      for (const [id, data] of Object.entries(docs)) {
        // settings only accepts its known ids, so those are written in place.
        const target = col === 'settings' ? id : `seedcheck-${id}`;
        try {
          await assertSucceeds(setDoc(doc(ed, col, target), convert(data)));
        } catch (e) {
          throw new Error(`${col}/${id} rejected: ${e.message}`);
        }
      }
    }
  });

  test('create, hide, reorder and delete a clinic', async () => {
    const ed = db(EDITOR);
    const ref = doc(ed, 'clinics', 'new1');
    await assertSucceeds(setDoc(ref, {
      specialty: 'dental', specialtyAr: 'الأسنان', specialtyEn: 'Dental', doctorName: 'د. مينا', days: [1, 3],
      start: '16:00', end: '20:00', bookingPhone: '01012345678', whatsapp: '', active: true, sample: false,
      visible: true, order: 10, updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test`,
    }));
    await assertSucceeds(updateDoc(ref, { visible: false, updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` }));
    await assertSucceeds(updateDoc(ref, { order: 20 }));
    await assertSucceeds(deleteDoc(ref));
  });

  test('rejects unknown keys, bad types and bad times', async () => {
    const ed = db(EDITOR);
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { hacked: true }));
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { visible: 'no' }));
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { order: '1' }));
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { start: '25:00' }));
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { doctorName: '' }));
    await assertFails(setDoc(doc(ed, 'priests', 'p'), { name: 'x', status: 'retired' }));
    await assertFails(setDoc(doc(ed, 'unknowncol', 'x'), { a: 1 }));
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { days: ['Monday'] }));
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { days: [99] }));
    await assertSucceeds(updateDoc(doc(ed, 'clinics', 'c1'), { days: [1, 7] }));
  });

  test('edit stamps must be now and by the signed-in admin', async () => {
    const ed = db(EDITOR);
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { visible: false, updatedBy: 'owner@x.test' }));
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { visible: false, updatedAt: Timestamp.fromDate(new Date('2020-01-01')) }));
    await assertSucceeds(updateDoc(doc(ed, 'clinics', 'c1'), { visible: false, updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` }));
    // A later edit that leaves the stamp untouched is fine too.
    await assertSucceeds(updateDoc(doc(ed, 'clinics', 'c1'), { order: 5 }));
  });

  test('legacy fields do not block an edit', async () => {
    await assertSucceeds(updateDoc(doc(db(EDITOR), 'clinics', 'legacy'), { visible: false }));
  });

  test('church info: valid edit passes, bad coordinates fail', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(updateDoc(doc(ed, 'settings', 'church'), {
      bishopAr: 'نيافة الأنبا بافلي', instagram: 'https://www.instagram.com/x', updatedAt: serverTimestamp(),
      updatedBy: `${EDITOR}@x.test`,
    }));
    await assertFails(updateDoc(doc(ed, 'settings', 'church'), { lat: 200 }));
    await assertFails(updateDoc(doc(ed, 'settings', 'church'), { nameAr: '' }));
    await assertFails(setDoc(doc(ed, 'settings', 'other'), { a: 1 }));
    await assertFails(deleteDoc(doc(ed, 'settings', 'church')));
  });
});

describe('feature toggles', () => {
  const valid = {
    sections: { clinics: false, schedule: true },
    homeOrder: ['map', 'banner', 'alerts', 'nextMass', 'quickContacts', 'milestones', 'directory'],
    homeHidden: ['milestones'],
    heroTitleAr: 'أهلًا', heroTitleEn: '', heroSubtitleAr: '', heroSubtitleEn: '',
    bannerEnabled: true, bannerAr: 'إعلان', bannerEn: 'Notice', bannerLink: '/clinics', theme: 'navy',
  };

  test('admins save valid settings', async () => {
    await assertSucceeds(setDoc(doc(db(EDITOR), 'settings', 'features'), { ...valid, updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` }));
    await assertSucceeds(setDoc(doc(db(EDITOR), 'settings', 'features'), { ...valid, bannerLink: 'https://www.facebook.com/x?y=1' }));
    await assertSucceeds(setDoc(doc(db(EDITOR), 'settings', 'features'), { ...valid, bannerLink: '' }));
    await assertSucceeds(setDoc(doc(db(OWNER), 'settings', 'features'), valid));
  });

  test('rejects invalid shapes', async () => {
    const ed = db(EDITOR);
    const ref = doc(ed, 'settings', 'features');
    await assertFails(setDoc(ref, { ...valid, theme: 'neon' }));
    await assertFails(setDoc(ref, { ...valid, sections: { clinics: 'off' } }));
    await assertFails(setDoc(ref, { ...valid, sections: { unknownSection: true } }));
    await assertFails(setDoc(ref, { ...valid, homeOrder: ['hero'] }));
    await assertFails(setDoc(ref, { ...valid, extra: 1 }));
    await assertFails(setDoc(ref, { ...valid, bannerAr: 'x'.repeat(501) }));
    await assertFails(setDoc(ref, { ...valid, bannerLink: 'not a link' }));
    await assertFails(setDoc(ref, { ...valid, bannerLink: 'javascript:alert(1)' }));
    await assertFails(setDoc(ref, { ...valid, bannerLink: '//evil.example' }));
  });

  test('uppercase scheme bannerLink is accepted (same as alert links)', async () => {
    await assertSucceeds(setDoc(doc(db(EDITOR), 'settings', 'features'), { ...valid, bannerLink: 'HTTPS://example.org/post' }));
  });

  test('an untouched legacy key does not block a merge update', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'settings', 'features'), { ...valid, legacyField: 'x' });
    });
    await assertSucceeds(setDoc(doc(db(EDITOR), 'settings', 'features'),
      { theme: 'green', updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` }, { merge: true }));
    await assertFails(setDoc(doc(db(EDITOR), 'settings', 'features'), { extra: 1 }, { merge: true }));
  });
});

describe('optional images', () => {
  const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` });
  const priest = { name: 'أبونا', status: 'serving', visible: true, order: 10 };

  test('content docs accept an optional url / inline image, or none', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(setDoc(doc(ed, 'priests', 'p1'), priest));
    await assertSucceeds(setDoc(doc(ed, 'priests', 'p2'), {
      ...priest, image: { source: 'url', url: 'https://img.example.org/p.jpg', alt: 'Fr. X', w: 800, h: 600 },
    }));
    await assertSucceeds(updateDoc(doc(ed, 'priests', 'p2'), { image: { source: 'inline', mediaId: 'Ab_12-x', w: 800, h: 600 }, ...stamp() }));
    await assertSucceeds(updateDoc(doc(ed, 'priests', 'p2'), { image: null })); // removed
    for (const col of ['saints', 'milestones', 'activities', 'alerts']) {
      const base = col === 'saints' ? { nameAr: 'x' } : { titleAr: 'x' };
      await assertSucceeds(setDoc(doc(ed, col, 'img'), { ...base, image: { source: 'inline', mediaId: 'm1' } }));
    }
    await assertSucceeds(setDoc(doc(ed, 'seasons', 'img'), { key: 'pascha', nameAr: 'القيامة', image: { source: 'url', url: 'https://x.org/a.webp' } }));
  });

  test('rejects malformed image maps and images on other collections', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(setDoc(doc(ed, 'priests', 'p1'), priest));
    const bad = [
      'https://x.org/a.jpg',
      { source: 'ftp', url: 'https://x.org/a.jpg' },
      { source: 'url', url: 'http://x.org/a.jpg' },
      { source: 'url', url: 'https://x.org/a b.jpg' },
      { source: 'url', url: 'https://localhost/a.jpg' },
      { source: 'url', url: 'https://x.org/' + 'a'.repeat(500) },
      { source: 'inline' },
      { source: 'inline', mediaId: 'a/b' },
      { source: 'inline', mediaId: 'm1', extra: 1 },
      { source: 'inline', mediaId: 'm1', w: 0 },
      { source: 'inline', mediaId: 'm1', alt: 'x'.repeat(301) },
    ];
    for (const image of bad) {
      await assertFails(updateDoc(doc(ed, 'priests', 'p1'), { image }));
    }
    // Liturgies never take an image (clinics, meetings and facilities do since PR #11).
    await assertFails(setDoc(doc(ed, 'liturgies', 'l1'), { nameAr: 'x', start: '07:00', image: { source: 'inline', mediaId: 'm1' } }));
    await assertSucceeds(updateDoc(doc(ed, 'clinics', 'c1'), { image: { source: 'inline', mediaId: 'm1' } }));
  });

  test('media: public read, admin-only validated writes', async () => {
    const ed = db(EDITOR);
    const media = (extra = {}) => ({
      dataBase64: 'AAAA', contentType: 'image/webp', w: 800, h: 600, bytes: 3,
      createdAt: serverTimestamp(), createdBy: `${EDITOR}@x.test`, ...extra,
    });
    await assertSucceeds(setDoc(doc(ed, 'media', 'm1'), media()));
    await assertSucceeds(getDoc(doc(db(null), 'media', 'm1')));
    await assertFails(setDoc(doc(db(null), 'media', 'm2'), media()));
    await assertFails(setDoc(doc(db(STRANGER), 'media', 'm2'), media({ createdBy: `${STRANGER}@x.test` })));
    await assertFails(setDoc(doc(ed, 'media', 'm2'), media({ contentType: 'image/gif' })));
    await assertFails(setDoc(doc(ed, 'media', 'm2'), media({ contentType: 'text/html' })));
    await assertFails(setDoc(doc(ed, 'media', 'm2'), media({ dataBase64: 'A'.repeat(950001) })));
    await assertFails(setDoc(doc(ed, 'media', 'm2'), media({ dataBase64: '' })));
    await assertFails(setDoc(doc(ed, 'media', 'm2'), media({ bytes: 700001 })));
    await assertFails(setDoc(doc(ed, 'media', 'm2'), media({ createdBy: 'owner@x.test' })));
    await assertFails(setDoc(doc(ed, 'media', 'm2'), media({ createdAt: Timestamp.fromDate(new Date('2020-01-01')) })));
    await assertFails(setDoc(doc(ed, 'media', 'm2'), media({ url: 'https://x.org' })));
    const { dataBase64, ...noData } = media();
    await assertFails(setDoc(doc(ed, 'media', 'm2'), noData));
    await assertSucceeds(setDoc(doc(ed, 'media', 'big'), media({ dataBase64: 'A'.repeat(950000) })));
    await assertFails(deleteDoc(doc(db(null), 'media', 'm1')));
    await assertSucceeds(deleteDoc(doc(ed, 'media', 'm1')));
  });

  test('the images switch is a valid section key', async () => {
    await assertSucceeds(setDoc(doc(db(EDITOR), 'settings', 'features'), { sections: { media: false } }));
  });
});

describe('contact inbox', () => {
  test('admins read, mark handled and delete', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(getDocs(collection(ed, 'contact_messages')));
    await assertSucceeds(updateDoc(doc(ed, 'contact_messages', 'm1'), { status: 'handled', updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` }));
    await assertFails(updateDoc(doc(ed, 'contact_messages', 'm1'), { message: 'edited' }));
    await assertFails(updateDoc(doc(ed, 'contact_messages', 'm1'), { status: 'spam' }));
    await assertSucceeds(deleteDoc(doc(ed, 'contact_messages', 'm1')));
  });

  test('non-admins cannot read or change messages', async () => {
    await assertFails(getDoc(doc(db(STRANGER), 'contact_messages', 'm1')));
    await assertFails(updateDoc(doc(db(STRANGER), 'contact_messages', 'm1'), { status: 'handled' }));
  });
});

describe('admins', () => {
  test('owner manages other admins', async () => {
    const own = db(OWNER);
    await assertSucceeds(getDocs(collection(own, 'admins')));
    await assertSucceeds(setDoc(doc(own, 'admins', 'new-uid'), { email: 'n@x.test', role: 'editor' }));
    await assertSucceeds(setDoc(doc(own, 'admins', EDITOR), { email: 'editor@x.test', role: 'owner' }));
    await assertFails(setDoc(doc(own, 'admins', 'bad'), { email: 'n@x.test', role: 'god' }));
    await assertSucceeds(deleteDoc(doc(own, 'admins', 'new-uid')));
  });

  test('admins rule accepts stamped updatedAt and updatedBy fields', async () => {
    const own = db(OWNER);
    await assertSucceeds(setDoc(doc(own, 'admins', 'stamped-uid'), {
      email: 'stamped@x.test', role: 'editor', updatedAt: serverTimestamp(), updatedBy: `${OWNER}@x.test`,
    }));
    let snap;
    await env.withSecurityRulesDisabled(async (ctx) => { snap = await getDoc(doc(ctx.firestore(), 'admins', 'stamped-uid')); });
    if (snap.get('updatedBy') !== `${OWNER}@x.test` || !snap.get('updatedAt')) throw new Error('admin doc not stamped');
  });

  test('owner cannot change or remove themselves', async () => {
    const own = db(OWNER);
    await assertFails(setDoc(doc(own, 'admins', OWNER), { email: 'owner@x.test', role: 'editor' }));
    await assertFails(deleteDoc(doc(own, 'admins', OWNER)));
  });

  test('editors read only their own admin doc and manage nobody', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(getDoc(doc(ed, 'admins', EDITOR)));
    await assertFails(getDoc(doc(ed, 'admins', OWNER)));
    await assertFails(getDocs(collection(ed, 'admins')));
    await assertFails(setDoc(doc(ed, 'admins', 'x'), { email: 'x@x.test', role: 'editor' }));
    await assertFails(setDoc(doc(ed, 'admins', EDITOR), { email: 'editor@x.test', role: 'owner' }));
  });
});

describe('SEC-01: contact throttle cannot be pinged on its own', () => {
  test('standalone writes to meta/contact_rate are rejected', async () => {
    const pub = db(null);
    const rate = doc(pub, 'meta', 'contact_rate');
    await assertFails(setDoc(rate, { lastAt: serverTimestamp() }));
    await assertFails(setDoc(rate, { lastAt: serverTimestamp(), lastMsgId: 'NoSuchMessage1234567' }));
    // An existing message cannot be reused as the proof.
    await assertFails(setDoc(rate, { lastAt: serverTimestamp(), lastMsgId: 'm1' }));
    await assertFails(setDoc(rate, { lastAt: serverTimestamp(), lastMsgId: 'm1m1m1m1m1m1' }));
    await assertFails(setDoc(rate, { lastAt: serverTimestamp(), lastMsgId: 'x', extra: 1 }));
  });

  test('a message alone, or naming another message, is rejected', async () => {
    const pub = db(null);
    await assertFails(setDoc(doc(collection(pub, 'contact_messages')), message()));
    await assertFails(contactBatch(pub, { rate: { lastAt: serverTimestamp() } }).commit());
    await assertFails(contactBatch(pub, { rate: { lastAt: serverTimestamp(), lastMsgId: 'SomeOtherMessageId00' } }).commit());
    await assertFails(contactBatch(pub, {
      rate: { lastAt: Timestamp.fromDate(new Date('2020-01-01')), lastMsgId: 'x'.repeat(20) },
    }).commit());
    // lastMsgId must look like a document id (10-64 chars).
    const batch = writeBatch(pub);
    batch.set(doc(pub, 'contact_messages', 'short'), message());
    batch.set(doc(pub, 'meta', 'contact_rate'), { lastAt: serverTimestamp(), lastMsgId: 'short' });
    await assertFails(batch.commit());
  });

  test('a second submission within 10 s is throttled', async () => {
    const pub = db(null);
    await assertSucceeds(contactBatch(pub).commit());
    await assertFails(contactBatch(pub).commit());
  });

  test('a submission 5 s after the last one is still throttled', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'meta', 'contact_rate'), {
        lastAt: Timestamp.fromMillis(Date.now() - 5000), lastMsgId: 'OldMessageId00000000',
      });
    });
    await assertFails(contactBatch(db(null)).commit());
  });

  test('a standalone rate write cannot replay an existing message', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, 'contact_messages', 'ExistingMsg0000001'), { ...message(), createdAt: Timestamp.now() });
      await setDoc(doc(f, 'meta', 'contact_rate'), {
        lastAt: Timestamp.fromMillis(Date.now() - 11000), lastMsgId: 'OldMessageId00000000',
      });
    });
    await assertFails(setDoc(doc(db(null), 'meta', 'contact_rate'), {
      lastAt: serverTimestamp(), lastMsgId: 'ExistingMsg0000001',
    }));
  });

  test('the throttle opens again after 10 s', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'meta', 'contact_rate'), {
        lastAt: Timestamp.fromMillis(Date.now() - 11000), lastMsgId: 'OldMessageId00000000',
      });
    });
    await assertSucceeds(contactBatch(db(null)).commit());
  });
});

describe('SEC-02: media can be fetched by id but not listed publicly', () => {
  test('public get, admin-only list', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'media', 'm1'), {
        dataBase64: 'AAAA', contentType: 'image/webp', createdAt: Timestamp.now(), createdBy: 'x',
      });
    });
    await assertSucceeds(getDoc(doc(db(null), 'media', 'm1')));
    await assertFails(getDocs(collection(db(null), 'media')));
    await assertFails(getDocs(collection(db(STRANGER), 'media')));
    await assertSucceeds(getDocs(collection(db(EDITOR), 'media')));
  });
});

describe('SEC-03: admin docs carry valid edit stamps', () => {
  test('owner writes must stamp now and as themselves', async () => {
    const own = db(OWNER);
    await assertSucceeds(setDoc(doc(own, 'admins', 'a1'), {
      email: 'a1@x.test', role: 'editor', updatedAt: serverTimestamp(), updatedBy: `${OWNER}@x.test`,
    }));
    await assertFails(setDoc(doc(own, 'admins', 'a2'), {
      email: 'a2@x.test', role: 'editor', updatedAt: serverTimestamp(), updatedBy: 'someone@else.test',
    }));
    await assertFails(setDoc(doc(own, 'admins', 'a3'), {
      email: 'a3@x.test', role: 'editor', updatedAt: Timestamp.fromDate(new Date('2020-01-01')),
    }));
    await assertFails(setDoc(doc(own, 'admins', 'a4'), { email: 'a4@x.test', role: 'editor', updatedBy: 42 }));
  });
});

describe('SEC-04: season flag, coordinates flag and safe links', () => {
  const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` });

  test('Season.replacesRegular is an optional bool', async () => {
    const ed = db(EDITOR);
    const season = { key: 'revival_moses', nameAr: 'نهضة', active: true };
    await assertSucceeds(setDoc(doc(ed, 'seasons', 's1'), season)); // absent = replaces
    await assertSucceeds(setDoc(doc(ed, 'seasons', 's2'), { ...season, replacesRegular: false }));
    await assertSucceeds(updateDoc(doc(ed, 'seasons', 's2'), { replacesRegular: true, ...stamp() }));
    await assertFails(updateDoc(doc(ed, 'seasons', 's2'), { replacesRegular: 'no' }));
    await assertFails(setDoc(doc(ed, 'seasons', 's3'), { ...season, replacesRegular: 1 }));
  });

  test('settings/church: coordinatesApproximate is a bool and social links are http(s)', async () => {
    const ed = db(EDITOR);
    const ref = doc(ed, 'settings', 'church');
    await assertSucceeds(updateDoc(ref, { coordinatesApproximate: true }));
    await assertFails(updateDoc(ref, { coordinatesApproximate: 'yes' }));
    await assertSucceeds(updateDoc(ref, { facebook: '' }));
    for (const k of ['facebook', 'youtube', 'instagram', 'whatsappChannel']) {
      await assertSucceeds(updateDoc(ref, { [k]: 'https://example.org/page' }));
      await assertSucceeds(updateDoc(ref, { [k]: 'HTTPS://Example.org/Page' })); // scheme case-insensitive
      await assertFails(updateDoc(ref, { [k]: 'javascript:alert(1)' }), k);
      await assertFails(updateDoc(ref, { [k]: '/relative' }), k);
    }
  });

  test('alert links: http(s) URL or in-app path only', async () => {
    const ed = db(EDITOR);
    const alert = { titleAr: 'تنويه', active: true };
    await assertSucceeds(setDoc(doc(ed, 'alerts', 'a1'), { ...alert, link: '/mass-schedule' }));
    await assertSucceeds(setDoc(doc(ed, 'alerts', 'a2'), { ...alert, link: 'https://www.facebook.com/x' }));
    await assertSucceeds(setDoc(doc(ed, 'alerts', 'a3'), { ...alert, link: '' }));
    await assertSucceeds(setDoc(doc(ed, 'alerts', 'a4'), { ...alert, link: 'Http://example.org/x' }));
    for (const link of ['javascript:alert(1)', 'data:text/html,x', '//evil.example', 'not a link']) {
      await assertFails(setDoc(doc(ed, 'alerts', 'bad'), { ...alert, link }), link);
    }
  });

  test('activity and meeting links: http(s) URLs only', async () => {
    const ed = db(EDITOR);
    const activity = { titleAr: 'نشاط', category: 'choir' };
    await assertSucceeds(setDoc(doc(ed, 'activities', 'a1'), { ...activity, link: 'https://www.youtube.com/@x' }));
    await assertFails(setDoc(doc(ed, 'activities', 'a2'), { ...activity, link: 'javascript:alert(1)' }));
    await assertFails(setDoc(doc(ed, 'activities', 'a3'), { ...activity, link: '/clinics' }));
    const meeting = { stage: 'youth', nameAr: 'اجتماع' };
    await assertSucceeds(setDoc(doc(ed, 'meetings', 'm1'), {
      ...meeting, facebookUrl: 'https://www.facebook.com/MaximousYouth', whatsappUrl: 'https://chat.whatsapp.com/abc',
    }));
    await assertFails(setDoc(doc(ed, 'meetings', 'm2'), { ...meeting, facebookUrl: 'javascript:alert(1)' }));
    await assertFails(setDoc(doc(ed, 'meetings', 'm3'), { ...meeting, whatsappUrl: 'vbscript:x' }));
  });
});

// ---------------------------------------------------------------------------
// PR #11: optional item detail pages (7 collections) + page headers & footer.
describe('PR #11: item detail pages', () => {
  const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` });
  const base = {
    meetings: { stage: 'youth', nameAr: 'اجتماع', facebookUrl: 'https://facebook.com/m', whatsappUrl: 'https://chat.whatsapp.com/m' },
    activities: { titleAr: 'كورال', contactPhone: '01012345678', link: 'https://fb.example.org/choir' },
    clinics: { specialty: 'dental', specialtyAr: 'الأسنان', doctorName: 'د. مينا', bookingPhone: '0123', whatsapp: '010' },
    facilities: { nameAr: 'الحضانة', phone: '0123' },
    priests: { name: 'أبونا', status: 'serving' },
    milestones: { titleAr: 'زيارة' },
    saints: { nameAr: 'الأنبا موسى' },
  };
  const COLS = Object.keys(base);
  const img = (i) => ({ source: 'inline', mediaId: `m${i}`, alt: 'a'.repeat(300), w: 800, h: 600 });
  const field = (i) => ({ titleAr: 'ع'.repeat(150), titleEn: 't'.repeat(150), valueAr: 'ق'.repeat(2000), valueEn: `${i}`.repeat(2000).slice(0, 2000) });
  const row = (r) => ({ titleAr: '', titleEn: '', valueAr: '', valueEn: '', ...r });
  const common = {
    detailsEnabled: true, showDetailImages: false, showContacts: true, showSocials: false,
    detailsAr: 'ت'.repeat(10000), detailsEn: 'd'.repeat(10000),
    gallery: Array.from({ length: 8 }, (_, i) => img(i)),
    extraFields: Array.from({ length: 15 }, (_, i) => field(i)),
    whatsapp: '01012345678', whatsappUrl: 'https://whatsapp.com/channel/x', facebookUrl: 'https://facebook.com/x',
    youtubeUrl: 'https://youtube.com/@x', instagramUrl: 'https://instagram.com/x',
    externalLabelAr: 'ن'.repeat(80), externalLabelEn: 'Register', contactNoteAr: 'م'.repeat(500), contactNoteEn: 'Call us',
  };
  // Collection-specific keys: the phone / link fields a collection lacks.
  const extra = (col) => ({
    ...(['clinics', 'facilities'].includes(col) ? {} : { contactPhone: '01012345678' }),
    ...(col === 'activities' ? {} : { externalUrl: 'https://forms.example.org/register' }),
    image: { source: 'url', url: 'https://img.example.org/cover.jpg', alt: 'cover' },
  });

  // Firestore evaluates at most 1,000 expressions per request. These are the
  // heaviest writes the admin form makes: a create carrying every field, then
  // the full gallery and the full extraFields list (each in its own update).
  test('worst case (max lengths, 8 photos, 15 fields) passes on all 7 collections', async () => {
    const ed = db(EDITOR);
    const { gallery, extraFields, ...scalars } = common;
    for (const col of COLS) {
      try {
        const ref = doc(ed, col, 'full');
        await assertSucceeds(setDoc(ref, {
          ...base[col], ...scalars, ...extra(col), gallery: [], extraFields: [], visible: true, sample: true, order: 1, ...stamp(),
        }));
        await assertSucceeds(updateDoc(ref, { gallery, ...stamp() }));
        await assertSucceeds(updateDoc(ref, { extraFields, ...stamp() }));
        // A list saved together with the detail text / toggles.
        await assertSucceeds(updateDoc(ref, { gallery: gallery.slice(1), detailsEnabled: false, detailsAr: 'ت'.repeat(10000), ...stamp() }));
        await assertSucceeds(updateDoc(ref, { extraFields: extraFields.slice(1), showContacts: false, contactNoteEn: 'x'.repeat(500), ...stamp() }));
        // ...and ordinary edits of that worst-case doc.
        await assertSucceeds(updateDoc(ref, { detailsEn: 'short', youtubeUrl: 'https://youtube.com/@y', ...stamp() }));
        await assertSucceeds(updateDoc(ref, { visible: false, order: 2, ...stamp() }));
      } catch (e) {
        throw new Error(`${col}: ${e.message}`);
      }
    }
  });

  test('every detail field is optional; cleared values are accepted', async () => {
    const ed = db(EDITOR);
    for (const col of COLS) {
      await assertSucceeds(setDoc(doc(ed, col, 'plain'), base[col]));
      // The admin form writes '' for cleared text and null for a removed image / list.
      await assertSucceeds(updateDoc(doc(ed, col, 'plain'), {
        detailsAr: '', detailsEn: '', gallery: null, extraFields: null, image: null, whatsappUrl: '', youtubeUrl: '',
        instagramUrl: '', facebookUrl: '', externalLabelAr: '', externalLabelEn: '', contactNoteAr: '', contactNoteEn: '',
        whatsapp: '', ...(col === 'activities' ? {} : { externalUrl: '' }),
        ...(['clinics', 'facilities'].includes(col) ? {} : { contactPhone: '' }),
      }));
      await assertSucceeds(updateDoc(doc(ed, col, 'plain'), { gallery: [], extraFields: [] }));
      // Shared keys a collection already had keep accepting null (legacy docs).
      if (col === 'meetings') await assertSucceeds(updateDoc(doc(ed, col, 'plain'), { facebookUrl: null, whatsappUrl: null }));
      if (col === 'clinics') await assertSucceeds(updateDoc(doc(ed, col, 'plain'), { whatsapp: null }));
      if (col === 'activities') await assertSucceeds(updateDoc(doc(ed, col, 'plain'), { contactPhone: null }));
    }
  });

  test('stored lists are re-validated only when they change (expression budget)', async () => {
    // A legacy / out-of-band list is not re-checked by an unrelated edit, but
    // replacing it must be valid.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'saints', 'old'), { ...base.saints, gallery: [{ source: 'url', url: 'http://x.org/a.jpg' }] });
    });
    const ed = db(EDITOR);
    await assertSucceeds(updateDoc(doc(ed, 'saints', 'old'), { nameEn: 'St Moses', ...stamp() }));
    await assertFails(updateDoc(doc(ed, 'saints', 'old'), { gallery: [{ source: 'url', url: 'http://x.org/b.jpg' }] }));
    await assertSucceeds(updateDoc(doc(ed, 'saints', 'old'), { gallery: [img(1)] }));
  });

  test('cover image: clinics, meetings and facilities now accept image + gallery', async () => {
    const ed = db(EDITOR);
    for (const col of ['clinics', 'meetings', 'facilities']) {
      await assertSucceeds(setDoc(doc(ed, col, 'i'), {
        ...base[col], image: { source: 'inline', mediaId: 'cover1' }, gallery: [{ source: 'url', url: 'https://x.org/a.jpg' }],
      }));
      await assertFails(updateDoc(doc(ed, col, 'i'), { image: { source: 'url', url: 'http://x.org/a.jpg' } }));
    }
  });

  test('gallery: list of valid images, at most 8', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(setDoc(doc(ed, 'saints', 's'), base.saints));
    const bad = [
      'not a list',
      { a: 1 },
      Array.from({ length: 9 }, (_, i) => img(i)),
      [{ source: 'url', url: 'http://x.org/a.jpg' }],
      [{ source: 'url', url: 'javascript:alert(1)' }],
      [img(0), { source: 'inline', mediaId: 'bad id!' }],
      [img(0), img(1), img(2), img(3), img(4), img(5), img(6), { source: 'inline', mediaId: 'a/b' }],
      [{ source: 'inline', mediaId: 'm1', extra: 1 }],
      ['https://x.org/a.jpg'],
    ];
    for (const gallery of bad) {
      await assertFails(updateDoc(doc(ed, 'saints', 's'), { gallery }), JSON.stringify(gallery).slice(0, 80));
    }
    await assertSucceeds(updateDoc(doc(ed, 'saints', 's'), { gallery: [img(0), { source: 'storage', url: 'https://x.org/b.png' }] }));
  });

  test('extraFields: up to 15 titled rows with known keys and bounded text', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(setDoc(doc(ed, 'meetings', 'm'), base.meetings));
    const ok = row({ titleAr: 'المكان', valueAr: 'القاعة' });
    const bad = [
      'x',
      [ok, 'row'],
      Array.from({ length: 16 }, () => ok),
      [row({ valueAr: 'بدون عنوان' })],
      [row({ titleAr: '   ', titleEn: '\n', valueAr: 'x' })],
      [{ titleAr: 'المكان', valueAr: 'القاعة' }], // the form always writes all four keys
      [row({ titleAr: ' x', valueAr: 'x' })], // titles are trimmed by the form
      [{ ...ok, valueEn: 'x'.repeat(2001) }],
      [{ ...ok, titleEn: 'x'.repeat(151) }],
      [{ ...ok, valueAr: ['x'] }],
      [...Array.from({ length: 14 }, () => ok), { ...ok, valueAr: 'x'.repeat(2001) }],
    ];
    for (const extraFields of bad) {
      await assertFails(updateDoc(doc(ed, 'meetings', 'm'), { extraFields }), JSON.stringify(extraFields).slice(0, 80));
    }
    await assertSucceeds(updateDoc(doc(ed, 'meetings', 'm'), { extraFields: [ok, row({ titleEn: 'Age' })] }));
    await assertSucceeds(updateDoc(doc(ed, 'meetings', 'm'), { extraFields: Array.from({ length: 15 }, (_, i) => field(i)) }));
  });

  test('links are http(s) only; toggles are bools; text is bounded', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(setDoc(doc(ed, 'priests', 'p'), base.priests));
    const ref = doc(ed, 'priests', 'p');
    for (const k of ['youtubeUrl', 'instagramUrl', 'externalUrl', 'facebookUrl', 'whatsappUrl']) {
      await assertFails(updateDoc(ref, { [k]: 'javascript:alert(1)' }), k);
      await assertFails(updateDoc(ref, { [k]: 'not a link' }), k);
      await assertFails(updateDoc(ref, { [k]: `https://x.org/${'a'.repeat(500)}` }), k);
      await assertSucceeds(updateDoc(ref, { [k]: 'HTTPS://x.org/page' }));
    }
    for (const k of ['detailsEnabled', 'showDetailImages', 'showContacts', 'showSocials']) {
      await assertFails(updateDoc(ref, { [k]: 'yes' }), k);
      await assertFails(updateDoc(ref, { [k]: null }), k);
    }
    const tooLong = {
      detailsAr: 10001, detailsEn: 10001, whatsapp: 21, contactPhone: 21, externalLabelAr: 81, externalLabelEn: 81,
      contactNoteAr: 501, contactNoteEn: 501,
    };
    for (const [k, n] of Object.entries(tooLong)) {
      await assertFails(updateDoc(ref, { [k]: 'x'.repeat(n) }), k);
    }
    await assertFails(updateDoc(ref, { detailsAr: 5 }));
    await assertFails(updateDoc(ref, { youtubeUrl: 7 }));
    await assertFails(updateDoc(ref, { contactNoteAr: ['x'] }));
  });

  // Codex P2 / CodeRabbit (PR #11): the joined-string validators must not turn a number
  // (or a bool / list) into text, accept the text 'null' for a null field, or
  // take numbers as strings.
  test('text fields reject non-strings; weekday, year and image w/h reject strings', async () => {
    const ed = db(EDITOR);
    for (const col of COLS) await assertSucceeds(setDoc(doc(ed, col, 't'), base[col]));
    const bad = {
      meetings: [{ nameEn: 5 }, { hallAr: true }, { notes: ['x'] }, { start: 700 }, { facebookUrl: 1 }, { weekday: '5' },
        { weekday: 'null' }, { contactPhone: 123 }, { contactPhone: true }, { whatsappUrl: 'null' }, { facebookUrl: 'null' },
        { externalUrl: 'null' }, { whatsapp: 123 }],
      activities: [{ contactPhone: 123 }, { titleEn: 5 }, { descAr: 1 }, { link: 2 }, { category: false }],
      clinics: [{ bookingPhone: 123 }, { whatsapp: 123 }, { specialtyEn: 5 }, { degreeAr: 1 }],
      facilities: [{ phone: 123 }, { nameEn: 5 }, { hoursAr: 9 }, { type: 1 }],
      priests: [{ nameEn: 5 }, { bioAr: 1 }, { ordinationDate: 1990 }, { rank: 'null' }, { status: 'null' }, { status: 5 },
        { rank: '' }, { externalUrl: 'null' }],
      milestones: [{ titleEn: 5 }, { year: '2000' }, { year: 'null' }, { icon: 3 }, { contactPhone: 123 }],
      saints: [{ nameEn: 5 }, { feastGregorian: 7 }, { bioEn: {} }],
    };
    for (const [col, list] of Object.entries(bad)) {
      for (const patch of list) {
        await assertFails(updateDoc(doc(ed, col, 't'), patch), `${col} ${JSON.stringify(patch)}`);
        await assertFails(setDoc(doc(ed, col, 'n'), { ...base[col], ...patch }), `create ${col} ${JSON.stringify(patch)}`);
      }
    }
    for (const w of [{ w: '800' }, { h: '600' }, { w: 'null' }]) {
      await assertFails(updateDoc(doc(ed, 'saints', 't'), { image: { source: 'inline', mediaId: 'm1', ...w } }), JSON.stringify(w));
    }
    // The same fields with the right types (or null / absent) still pass.
    await assertSucceeds(updateDoc(doc(ed, 'meetings', 't'), { nameEn: 'Youth', weekday: 5, start: '19:00', notes: null }));
    await assertSucceeds(updateDoc(doc(ed, 'meetings', 't'), { weekday: null, hallAr: null }));
    await assertSucceeds(updateDoc(doc(ed, 'activities', 't'), { contactPhone: '0123', titleEn: null }));
    await assertSucceeds(updateDoc(doc(ed, 'facilities', 't'), { phone: '0123', hoursAr: '' }));
    await assertSucceeds(updateDoc(doc(ed, 'clinics', 't'), { bookingPhone: null, whatsapp: '' }));
    await assertSucceeds(updateDoc(doc(ed, 'priests', 't'), { rank: 'hegumen', status: null, ordinationDate: '1990-01-01' }));
    await assertSucceeds(updateDoc(doc(ed, 'milestones', 't'), { year: 2000, icon: null }));
    await assertSucceeds(updateDoc(doc(ed, 'milestones', 't'), { year: null }));
    await assertSucceeds(updateDoc(doc(ed, 'saints', 't'), { image: { source: 'inline', mediaId: 'm1', w: 800, h: null } }));
  });

  test('no duplicate inputs: clinics/facilities have no contactPhone, activities no externalUrl', async () => {
    const ed = db(EDITOR);
    await assertFails(setDoc(doc(ed, 'clinics', 'x'), { ...base.clinics, contactPhone: '0123' }));
    await assertFails(setDoc(doc(ed, 'facilities', 'x'), { ...base.facilities, contactPhone: '0123' }));
    await assertFails(setDoc(doc(ed, 'activities', 'x'), { ...base.activities, externalUrl: 'https://x.org' }));
    await assertFails(setDoc(doc(ed, 'activities', 'x'), { ...base.activities, link: 'javascript:alert(1)' }));
  });

  test('liturgies, seasons and alerts take no detail fields', async () => {
    const ed = db(EDITOR);
    const docs = {
      liturgies: { nameAr: 'قداس', start: '07:00' },
      seasons: { key: 'pascha', nameAr: 'القيامة' },
      alerts: { titleAr: 'تنويه' },
    };
    for (const [col, d] of Object.entries(docs)) {
      await assertSucceeds(setDoc(doc(ed, col, 'ok'), d));
      for (const k of ['detailsEnabled', 'gallery', 'extraFields', 'youtubeUrl']) {
        const v = k === 'detailsEnabled' ? true : k === 'youtubeUrl' ? 'https://youtube.com/x' : [];
        await assertFails(setDoc(doc(ed, col, 'bad'), { ...d, [k]: v }), `${col}.${k}`);
      }
    }
  });

  test('a content doc may carry up to 80 keys (legacy + detail fields)', async () => {
    const legacy = Object.fromEntries(Array.from({ length: 40 }, (_, i) => [`legacy${i}`, 'x']));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'priests', 'wide'), { ...base.priests, ...legacy });
    });
    const ed = db(EDITOR);
    // 2 + 40 legacy + 20 detail keys + image + stamps < 80.
    await assertSucceeds(updateDoc(doc(ed, 'priests', 'wide'), { ...common, gallery: [], extraFields: [], ...extra('priests'), ...stamp() }));
    const more = Object.fromEntries(Array.from({ length: 30 }, (_, i) => [`more${i}`, 'x']));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'priests', 'wider'), { ...base.priests, ...legacy, ...more });
    });
    await assertFails(updateDoc(doc(ed, 'priests', 'wider'), { ...common, gallery: [], extraFields: [], ...extra('priests') }));
  });
});

// PR #12: the admin editors' real write sequence. DocEditor saves an item in
// up to three writes (splitSavePayload): everything else first (a create
// carries every field, the empty lists included), then the gallery, then the
// extraFields; AdminRepository merges updates with mergeFields (written map
// fields are replaced, not deep-merged).
describe('PR #12: admin editor save paths', () => {
  const by = `${EDITOR}@x.test`;
  const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: by });
  const merge = (ref, data) => { const d = { ...data, ...stamp() }; return setDoc(ref, d, { mergeFields: Object.keys(d) }); };
  const own = {
    meetings: { stage: 'youth', nameAr: 'اجتماع', nameEn: 'Youth', weekday: 5, start: '19:00', end: '21:00', hallAr: 'ق', hallEn: 'h', notes: 'n' },
    activities: { category: 'choir', titleAr: 'كورال', titleEn: 'Choir', descAr: 'و'.repeat(2000), descEn: 'd', scheduleAr: 's', scheduleEn: 's', ageRange: '8-12' },
    clinics: { specialty: 'dental', specialtyAr: 'الأسنان', specialtyEn: 'Dental', doctorName: 'د. مينا', degreeAr: 'أ', degreeEn: 'b', days: [1, 3, 5], start: '16:00', end: '20:00', active: true },
    facilities: { type: 'nursery', nameAr: 'الحضانة', nameEn: 'Nursery', descAr: 'و'.repeat(2000), descEn: 'd', hoursAr: 'h', hoursEn: 'h' },
    priests: { name: 'أبونا', nameEn: 'Fr', rank: 'priest', ordinationDate: '2001-03', hegumenDate: '', status: 'serving', departedDate: '', bioAr: 'ن'.repeat(5000), bioEn: 'b' },
    milestones: { titleAr: 'زيارة', titleEn: 'Visit', descAr: 'و'.repeat(2000), descEn: 'd', year: 1990, icon: 'pope' },
    saints: { nameAr: 'الأنبا موسى', nameEn: 'St Moses', bioAr: 'س'.repeat(5000), bioEn: 'b', feastCopticAr: 'f', feastCopticEn: 'f', feastGregorianAr: 'g', feastGregorian: 'g' },
  };
  // Every detail key the admin schema writes for a new item (DocEditor.collect).
  const detail = (col) => ({
    detailsEnabled: true, detailsAr: 'ت'.repeat(10000), detailsEn: 'd'.repeat(10000),
    image: { source: 'inline', mediaId: 'cover1', alt: 'a'.repeat(300), w: 800, h: 600 }, showDetailImages: true,
    showContacts: true, showSocials: true,
    [col === 'clinics' ? 'bookingPhone' : col === 'facilities' ? 'phone' : 'contactPhone']: '01012345678',
    whatsapp: '01012345678', whatsappUrl: 'https://chat.whatsapp.com/x', facebookUrl: 'https://facebook.com/x',
    youtubeUrl: 'https://youtube.com/@x', instagramUrl: 'https://instagram.com/x',
    [col === 'activities' ? 'link' : 'externalUrl']: 'https://forms.example.org/register',
    externalLabelAr: 'ن'.repeat(80), externalLabelEn: 'e'.repeat(80), contactNoteAr: 'م'.repeat(500), contactNoteEn: 'n'.repeat(500),
    order: 10, visible: true, ...(['milestones', 'saints'].includes(col) ? {} : { sample: true }),
  });
  const gallery = Array.from({ length: 8 }, (_, i) => ({ source: 'inline', mediaId: `g${i}`, alt: 'a'.repeat(300), w: 800, h: 600 }));
  const extraFields = Array.from({ length: 15 }, () => ({ titleAr: 'ع'.repeat(150), titleEn: 't'.repeat(150), valueAr: 'ق'.repeat(2000), valueEn: 'v'.repeat(2000) }));

  test('new item at maximum size: create, then the gallery, then the extra fields (all 7 collections)', async () => {
    const ed = db(EDITOR);
    for (const col of Object.keys(own)) {
      try {
        const ref = doc(ed, col, 'new');
        await assertSucceeds(setDoc(ref, { ...own[col], ...detail(col), gallery: [], extraFields: [], ...stamp() }));
        await assertSucceeds(merge(ref, { gallery }));
        await assertSucceeds(merge(ref, { extraFields }));
      } catch (e) {
        throw new Error(`${col}: ${e.message}`);
      }
    }
  });

  test('editing every field at once still fits when the lists go in their own writes', async () => {
    const ed = db(EDITOR);
    for (const col of Object.keys(own)) {
      try {
        const ref = doc(ed, col, 'edit');
        await env.withSecurityRulesDisabled(async (ctx) => {
          await setDoc(doc(ctx.firestore(), col, 'edit'), { ...own[col], ...detail(col), gallery, extraFields });
        });
        // Base write: every scalar changed, the cover image replaced (a map
        // field: mergeFields replaces it, so the old mediaId does not linger).
        // Free-text fields (names, descriptions, labels, notes): last char edited.
        const text = /(Ar|En|^name|^notes|^doctorName|^ageRange|^feastGregorian)$/;
        const changed = Object.fromEntries(Object.entries({ ...own[col], ...detail(col) }).map(([k, v]) =>
          [k, typeof v === 'string' && text.test(k) ? `${v.slice(0, -1)}x` : v]));
        await assertSucceeds(merge(ref, { ...changed, detailsEnabled: false, showContacts: false, image: { source: 'url', url: 'https://img.example.org/new.jpg' } }));
        let after;
        await env.withSecurityRulesDisabled(async (ctx) => { after = (await getDoc(doc(ctx.firestore(), col, 'edit'))).data(); });
        if ('mediaId' in after.image) throw new Error('image map was deep-merged');
        await assertSucceeds(merge(ref, { gallery: [...gallery].reverse() }));
        await assertSucceeds(merge(ref, { extraFields: extraFields.slice(1) }));
      } catch (e) {
        throw new Error(`${col}: ${e.message}`);
      }
    }
  });

  // FeaturesScreen saves FeatureSettings.toMap(): every key, all 8 pages.
  test('features editor: whole-document save at maximum size, then a reset page disappears', async () => {
    const header = { titleAr: 'ع'.repeat(200), titleEn: 't'.repeat(200), subtitleAr: 'س'.repeat(300), subtitleEn: 's'.repeat(300), introAr: 'م'.repeat(1500), introEn: 'i'.repeat(1500) };
    const pages = ['about', 'schedule', 'education', 'activities', 'clinics', 'services', 'contact', 'ask'];
    const sections = Object.fromEntries(['schedule', 'meetings', 'clinics', 'services', 'history', 'milestones', 'saints', 'priests',
      'departedPriests', 'activities', 'alerts', 'contactInfo', 'socials', 'contactForm', 'assistant', 'media'].map((k) => [k, true]));
    const full = {
      sections, homeOrder: ['banner', 'alerts', 'nextMass', 'quickContacts', 'milestones', 'directory', 'map'], homeHidden: ['map'],
      heroTitleAr: 'ع'.repeat(200), heroTitleEn: 'T', heroSubtitleAr: 'س'.repeat(300), heroSubtitleEn: 'S', bannerEnabled: true,
      bannerAr: 'ب'.repeat(500), bannerEn: 'B', bannerLink: '/mass-schedule', theme: 'navy',
      pageHeaders: Object.fromEntries(pages.map((p) => [p, header])),
      footer: { showPhones: false, showSocials: true, showQuickLinks: false, noteAr: 'م'.repeat(500), noteEn: 'n'.repeat(500) },
    };
    const ref = doc(db(EDITOR), 'settings', 'features');
    // featuresSaveWrites: everything else first, then pageHeaders on its own
    // (the whole document plus 8 changed pages in one write exceeds the budget).
    const { pageHeaders, ...base } = full;
    await assertFails(merge(ref, full));
    // First save (no document yet), and the first save over the seeded doc.
    await assertSucceeds(merge(ref, base));
    await assertSucceeds(merge(ref, { pageHeaders }));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'settings', 'features'), { ...convert(seed.settings.features), legacyField: 'x' });
    });
    await assertSucceeds(merge(ref, base));
    await assertSucceeds(merge(ref, { pageHeaders }));
    const { ask, ...rest } = pageHeaders;
    await assertSucceeds(merge(ref, { ...base, theme: 'green' }));
    await assertSucceeds(merge(ref, { pageHeaders: rest }));
    let stored;
    await env.withSecurityRulesDisabled(async (ctx) => { stored = (await getDoc(doc(ctx.firestore(), 'settings', 'features'))).data(); });
    if ('ask' in stored.pageHeaders) throw new Error('reset page header was kept (deep merge)');
    if (stored.legacyField !== 'x') throw new Error('untouched legacy key was dropped');
  });

  test('why the editor splits: both full lists in one write exceed the expression budget', async () => {
    const ref = doc(db(EDITOR), 'saints', 'both');
    await assertSucceeds(setDoc(ref, { ...own.saints, gallery: [], extraFields: [] }));
    await assertFails(merge(ref, { gallery, extraFields }));
  });
});

describe('PR #11: page headers & footer (settings/features)', () => {
  const footer = { showPhones: true, showSocials: false, showQuickLinks: true, noteAr: 'م'.repeat(500), noteEn: 'Note' };
  const header = { titleAr: 'ع'.repeat(200), titleEn: 'T', subtitleAr: 'س'.repeat(300), subtitleEn: '', introAr: 'م'.repeat(1500), introEn: 'Intro' };
  const pages = ['about', 'schedule', 'education', 'activities', 'clinics', 'services', 'contact', 'ask'];
  const all = Object.fromEntries(pages.map((p) => [p, header]));
  const empty = { titleAr: '', titleEn: '', subtitleAr: '', subtitleEn: '', introAr: '', introEn: '' };

  test('admins save page headers and footer (worst case: all 8 pages, max lengths)', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'navy', pageHeaders: {}, footer: { showPhones: true, showSocials: true, showQuickLinks: true, noteAr: '', noteEn: '' } }));
    await assertSucceeds(setDoc(ref, { sections: { media: true }, pageHeaders: all, footer, updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` }));
    await assertSucceeds(setDoc(ref, { pageHeaders: { clinics: { ...empty, titleAr: 'عياداتنا' } }, footer: {} }));
    // Editing one page (whole-document save, as the admin form does) and removing another.
    await assertSucceeds(setDoc(ref, { pageHeaders: all, footer }));
    await assertSucceeds(setDoc(ref, { pageHeaders: { ...all, about: { ...header, titleEn: 'About us' } }, footer }));
    const { ask, ...withoutAsk } = all;
    await assertSucceeds(setDoc(ref, { pageHeaders: withoutAsk, footer }));
  });

  test('rejects invalid footer shapes', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    const bad = [
      'x', [], { ...footer, extra: true }, { showPhones: 'yes' }, { showSocials: null }, { showQuickLinks: 1 },
      { noteAr: 'x'.repeat(501) }, { noteEn: 5 },
    ];
    for (const f of bad) {
      await assertFails(setDoc(ref, { footer: f }), JSON.stringify(f).slice(0, 60));
    }
  });

  test('rejects invalid pageHeaders shapes', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    const bad = [
      'x', ['about'], { home: header }, { about: 'x' }, { about: { ...header, link: 'https://x.org' } },
      { about: { ...empty, titleEn: 'x'.repeat(201) } }, { schedule: { ...empty, subtitleAr: 'x'.repeat(301) } },
      { ask: { ...empty, introEn: 'x'.repeat(1501) } }, { contact: { ...empty, titleAr: ['x'] } },
      { about: { titleAr: 'partial' } }, { ...all, ask: { ...empty, introAr: 'x'.repeat(1501) } },
    ];
    for (const h of bad) {
      await assertFails(setDoc(ref, { pageHeaders: h }), JSON.stringify(h).slice(0, 60));
    }
  });

  test('legacy keys still merge; the seed features doc (with the new maps) is valid', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'settings', 'features'), { ...convert(seed.settings.features), legacyField: 'x' });
    });
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { footer: { ...footer, showPhones: false }, ...{ updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` } }, { merge: true }));
    await assertSucceeds(setDoc(ref, { pageHeaders: { about: { ...empty, titleEn: 'About us' } } }, { merge: true }));
    await assertFails(setDoc(ref, { pageHeaders: { bogus: {} } }, { merge: true }));
    const f = seed.settings.features;
    if (!('pageHeaders' in f) || !('footer' in f)) throw new Error('seed settings/features lacks pageHeaders/footer');
  });
});

describe('ADR-022: hero motion & video switch (settings/features.heroMotion)', () => {
  test('admins switch hero motion off and on; only a bool is accepted', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', heroMotion: false }));
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', heroMotion: true }));
    for (const v of ['off', 0, null, { on: true }]) {
      await assertFails(setDoc(ref, { heroMotion: v }), JSON.stringify(v));
    }
  });

  test('visitors cannot change it', async () => {
    await assertFails(setDoc(doc(db(null), 'settings', 'features'), { heroMotion: false }));
  });
});
