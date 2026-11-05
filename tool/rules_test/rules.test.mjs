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
      'departedPriests', 'activities', 'alerts', 'contactInfo', 'socials', 'contactForm', 'assistant', 'media', 'dailyVerse'].map((k) => [k, true]));
    const full = {
      sections, homeOrder: ['banner', 'alerts', 'nextMass', 'quickContacts', 'milestones', 'directory', 'map'], homeHidden: ['map'],
      heroTitleAr: 'ع'.repeat(200), heroTitleEn: 'T', heroSubtitleAr: 'س'.repeat(300), heroSubtitleEn: 'S', bannerEnabled: true,
      bannerAr: 'ب'.repeat(500), bannerEn: 'B', bannerLink: '/mass-schedule', theme: 'navy',
      pageHeaders: Object.fromEntries(pages.map((p) => [p, header])),
      footer: { showPhones: false, showSocials: true, showQuickLinks: false, noteAr: 'م'.repeat(500), noteEn: 'n'.repeat(500) },
      dailyVerse: { mode: 'fixed', textAr: 'ع'.repeat(500), refAr: 'ي'.repeat(60) },
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

describe('ADR-050: liturgies.replacesDay and settings/features.heroSeasonTint', () => {
  test('a liturgy may carry replacesDay as a bool only', async () => {
    const ed = db(EDITOR);
    const base = { type: 'mass', nameAr: 'قداس العيد', date: Timestamp.fromDate(new Date('2027-08-22T00:00:00Z')),
      start: '10:00', end: '12:30', seasonKey: 'marian' };
    await assertSucceeds(setDoc(doc(ed, 'liturgies', 'feast'), { ...base, replacesDay: true }));
    await assertSucceeds(setDoc(doc(ed, 'liturgies', 'feast2'), base)); // absent = false
    await assertSucceeds(updateDoc(doc(ed, 'liturgies', 'feast'), { replacesDay: false }));
    for (const v of ['yes', 1, null, { on: true }]) {
      await assertFails(setDoc(doc(ed, 'liturgies', 'feast3'), { ...base, replacesDay: v }), JSON.stringify(v));
    }
    await assertFails(setDoc(doc(db(null), 'liturgies', 'feast4'), { ...base, replacesDay: true }));
  });

  test('heroSeasonTint is a bool; visitors cannot change it', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'marian', heroSeasonTint: false }));
    await assertSucceeds(setDoc(ref, { theme: 'marian', heroSeasonTint: true }));
    for (const v of ['off', 0, null, { on: true }]) {
      await assertFails(setDoc(ref, { heroSeasonTint: v }), JSON.stringify(v));
    }
    await assertFails(setDoc(doc(db(null), 'settings', 'features'), { heroSeasonTint: false }));
  });
});

describe('Hero address ribbon switch (settings/features.heroShowAddress)', () => {
  test('admins switch the address ribbon on and off; only a bool is accepted', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', heroShowAddress: true }));
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', heroShowAddress: false }));
    for (const v of ['on', 1, null, { on: true }]) {
      await assertFails(setDoc(ref, { heroShowAddress: v }), JSON.stringify(v));
    }
  });

  test('visitors cannot change it', async () => {
    await assertFails(setDoc(doc(db(null), 'settings', 'features'), { heroShowAddress: true }));
  });
});

describe('ADR-034: error reporting switch (settings/features.errorReporting)', () => {
  test('admins switch error reports on and off; only a bool is accepted', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', errorReporting: false }));
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', errorReporting: true }));
    await assertSucceeds(updateDoc(ref, { errorReporting: false }));
    for (const v of ['off', 0, null, { on: true }, [true]]) {
      await assertFails(setDoc(ref, { errorReporting: v }), JSON.stringify(v));
    }
  });

  test('visitors cannot change it', async () => {
    await assertFails(setDoc(doc(db(null), 'settings', 'features'), { errorReporting: false }));
    await assertFails(updateDoc(doc(db(null), 'settings', 'features'), { errorReporting: false }));
  });
});

describe('Verse of the day (settings/features.dailyVerse + sections.dailyVerse)', () => {
  test('admins switch it via its section, pick daily / fixed, and enter a fixed verse', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', sections: { dailyVerse: false }, dailyVerse: { mode: 'daily', textAr: '', refAr: '' } }));
    await assertSucceeds(setDoc(ref, { dailyVerse: { mode: 'fixed', textAr: 'ع'.repeat(500), refAr: 'ي'.repeat(60) } }));
    await assertSucceeds(setDoc(ref, { dailyVerse: {} }), 'missing keys = defaults');
    await assertSucceeds(setDoc(ref, { theme: 'navy' }), 'doc without dailyVerse still saves');
  });

  test('rejects bad shapes, modes, types and lengths', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    const ok = { mode: 'daily', textAr: '', refAr: '' };
    for (const v of [
      'daily', null, { ...ok, mode: 'weekly' }, { ...ok, enabled: true }, { ...ok, textAr: 5 }, { ...ok, refAr: null },
      { ...ok, textAr: 'x'.repeat(501) }, { ...ok, refAr: 'x'.repeat(61) }, { ...ok, textFr: 'hi' },
      { ...ok, textAr: 'a\u001fb' },
    ]) {
      await assertFails(setDoc(ref, { dailyVerse: v }), JSON.stringify(v).slice(0, 80));
    }
    await assertFails(setDoc(ref, { sections: { dailyVerse: 'on' } }));
  });

  test('visitors cannot change it', async () => {
    await assertFails(setDoc(doc(db(null), 'settings', 'features'), { dailyVerse: { mode: 'fixed' } }));
  });
});

describe('ADR-025: occasion themes (settings/features.theme + occasions)', () => {
  const ref = () => doc(db(EDITOR), 'settings', 'features');
  // primary|onPrimary|onPrimaryAccent|background|surface|surfaceAlt|ink|muted|goldText|script
  const fullCustom = '#C9C1B6|#15110F|#6E1C1C|#0D0B0A|#1B1816|#27221F|#EEE7DD|#BDB2A5|#D6B98C|#E88B7E';

  test('every preset is accepted; legacy burgundy still saves; unknown keys are not', async () => {
    for (const t of ['goldenHour', 'holyWeek', 'resurrection', 'nativity', 'epiphany', 'fasting', 'marian', 'navy',
      'green', 'brown', 'purple', 'burgundy']) {
      await assertSucceeds(setDoc(ref(), { theme: t }), t);
    }
    for (const t of ['neon', '', 5, null]) await assertFails(setDoc(ref(), { theme: t }), String(t));
  });

  test('automatic switching, Easter, schedule slots and colour edits', async () => {
    await assertSucceeds(setDoc(ref(), {
      theme: 'goldenHour',
      occasions: {
        auto: true, easter: true, resurrectionDays: 50,
        schedule: Object.fromEntries(Array.from({ length: 12 }, (_, i) =>
          [`r${i + 1}`, 'nativity|2026-12-25|2027-01-08'])),
      },
    }));
    await assertSucceeds(setDoc(ref(), {
      themeColors: Object.fromEntries(['goldenHour', 'holyWeek', 'resurrection', 'nativity', 'epiphany', 'fasting',
        'marian', 'navy', 'green', 'brown', 'purple'].map((k) => [k, fullCustom])),
    }), 'every preset edited in one write');
    await assertSucceeds(setDoc(ref(), { themeColors: { goldenHour: '#123456|||||||||', marian: '|||||||||' } }));
    await assertSucceeds(setDoc(ref(), { occasions: {} }), 'missing keys = defaults');
    await assertSucceeds(setDoc(ref(), { occasions: { auto: false, schedule: { r1: 'holyWeek|2027-04-25|2027-04-25' } } }));
    await assertSucceeds(setDoc(ref(), { theme: 'navy' }), 'doc without occasions still saves');
  });

  test('rejects bad switches, ranges, slots, presets and colours', async () => {
    const range = 'holyWeek|2027-04-25|2027-05-01';
    for (const o of [
      'auto', { auto: 'yes' }, { easter: 1 }, { resurrectionDays: 0 }, { resurrectionDays: 51 }, { resurrectionDays: 7.5 },
      { extra: true }, { schedule: [] }, { schedule: { r13: range } }, { schedule: { r1: 'neon|2027-04-25|2027-05-01' } },
      { schedule: { r1: 'holyWeek|2027-5-1|2027-05-01' } }, { schedule: { r1: 'holyWeek|2027-04-25|2027-04-24' } },
      { schedule: { r1: `${range}|x` } }, { schedule: { r1: 'holyWeek|2027-04-25' } },
      { schedule: { r1: 'holyWeek|2027-13-01|2027-05-01' } },
      { schedule: { r1: { theme: 'holyWeek', start: '2027-04-25', end: '2027-05-01' } } },
      { schedule: { r1: 20270501 } }, { custom: {} },
    ]) {
      await assertFails(setDoc(ref(), { occasions: o }), JSON.stringify(o).slice(0, 90));
    }
    for (const c of [
      [], { neon: '|||||||||' }, { holyWeek: 'red|||||||||' }, { holyWeek: '#12345|||||||||' },
      { holyWeek: '#1234567|||||||||' }, { holyWeek: '#123456||||||||' }, { holyWeek: '#123456||||||||||' },
      { holyWeek: { primary: '#123456' } }, { holyWeek: 5 },
    ]) {
      await assertFails(setDoc(ref(), { themeColors: c }), JSON.stringify(c).slice(0, 90));
    }
  });

  test('visitors cannot change it', async () => {
    await assertFails(setDoc(doc(db(null), 'settings', 'features'), { occasions: { auto: true } }));
    await assertFails(setDoc(doc(db(null), 'settings', 'features'), { themeColors: {} }));
  });
});

describe('ADR-026: hero video library (settings/features.heroVideos)', () => {
  const ref = () => doc(db(EDITOR), 'settings', 'features');
  const item = (id) => ({ name: 'غيوم', url: `https://www.youtube.com/watch?v=${id}` });

  test('admins add links, pick the active one, attach one per theme; nothing else is required', async () => {
    await assertSucceeds(setDoc(ref(), {
      heroVideos: {
        items: Object.fromEntries(Array.from({ length: 12 }, (_, i) => [`v${i + 1}`, item(`abcdefghij${String.fromCharCode(65 + i)}`)])),
        active: 'v2',
        byTheme: { holyWeek: 'v3', resurrection: 'v1' },
      },
    }));
    await assertSucceeds(setDoc(ref(), { heroVideos: { items: { v1: { name: 'x', url: 'https://youtu.be/dQw4w9WgXcQ' } }, active: '' } }));
    await assertSucceeds(setDoc(ref(), { heroVideos: { items: { v1: { name: 'ن'.repeat(80), url: 'https://youtu.be/a_b-c_d-e_f' } } } }));
    await assertSucceeds(setDoc(ref(), { heroVideos: {} }));
    await assertSucceeds(setDoc(ref(), { theme: 'navy' }), 'doc without heroVideos still saves');
  });

  test('only youtube.com / youtu.be video ids; known slots, themes and shapes', async () => {
    for (const v of [
      [], { items: [] }, { items: { v13: item('dQw4w9WgXcQ') } }, { items: { v1: { ...item('dQw4w9WgXcQ'), extra: 1 } } },
      { items: { v1: { name: '', url: 'https://youtu.be/dQw4w9WgXcQ' } } },
      { items: { v1: { name: 'x'.repeat(81), url: 'https://youtu.be/dQw4w9WgXcQ' } } },
      { items: { v1: { name: 'x', url: 'https://vimeo.com/123456789' } } },
      { items: { v1: { name: 'x', url: 'http://youtu.be/dQw4w9WgXcQ' } } },
      { items: { v1: { name: 'x', url: 'https://youtu.be/dQw4w9WgXc' } } },
      { items: { v1: { name: 'x', url: 'https://youtu.be/dQw4w9WgXcQ?t=5' } } },
      { items: { v1: { name: 'x', url: 'https://www.youtube.com.evil.com/watch?v=dQw4w9WgXcQ' } } },
      { items: { v1: { name: 'x', url: 'https://evil.com/?u=https://youtu.be/dQw4w9WgXcQ' } } },
      { items: { v1: { name: 'x', url: 'javascript:alert(1)' } } },
      { items: { v1: { name: 'a\u001fb', url: 'https://youtu.be/dQw4w9WgXcQ' } } },
      { items: { v1: { name: 'x', url: 5 } } },
      { active: 'v13' }, { active: 1 }, { byTheme: { neon: 'v1' } }, { byTheme: { holyWeek: 'v99' } }, { other: 1 },
    ]) {
      await assertFails(setDoc(ref(), { heroVideos: v }), JSON.stringify(v).slice(0, 90));
    }
  });

  test('visitors cannot change it', async () => {
    await assertFails(setDoc(doc(db(null), 'settings', 'features'), { heroVideos: { active: '' } }));
  });
});

describe('ADR-023: image display style (imageStyle / settings/features.imageStyles)', () => {
  const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` });
  const priest = { name: 'أبونا', status: 'serving', visible: true, order: 10 };

  test('items accept avatar / card / banner, or no style (section default)', async () => {
    const ed = db(EDITOR);
    for (const v of ['avatar', 'card', 'banner']) {
      await assertSucceeds(setDoc(doc(ed, 'priests', `s-${v}`), { ...priest, imageStyle: v }));
    }
    await assertSucceeds(updateDoc(doc(ed, 'priests', 's-card'), { imageStyle: 'avatar', ...stamp() }));
    await assertSucceeds(updateDoc(doc(ed, 'priests', 's-card'), { imageStyle: null, ...stamp() })); // back to default
    await assertSucceeds(setDoc(doc(ed, 'saints', 'st'), { nameAr: 'x', imageStyle: 'card' }));
    await assertSucceeds(setDoc(doc(ed, 'milestones', 'ms'), { titleAr: 'x', imageStyle: 'banner' }));
    await assertSucceeds(setDoc(doc(ed, 'activities', 'ac'), { titleAr: 'x', imageStyle: 'card' }));
    await assertSucceeds(setDoc(doc(ed, 'alerts', 'al'), { titleAr: 'x', imageStyle: 'banner' }));
    await assertSucceeds(setDoc(doc(ed, 'seasons', 'se'), { key: 'pascha', nameAr: 'القيامة', imageStyle: 'card' }));
  });

  test('rejects unknown styles, non-strings and the field on collections without images', async () => {
    const ed = db(EDITOR);
    for (const v of ['circle', 'AVATAR', '', 1, true, { s: 'card' }]) {
      await assertFails(setDoc(doc(ed, 'priests', 'bad'), { ...priest, imageStyle: v }), JSON.stringify(v));
    }
    await assertFails(setDoc(doc(ed, 'liturgies', 'l1'),
      { type: 'liturgy', nameAr: 'قداس', weekday: 7, start: '07:00', end: '09:00', imageStyle: 'card' }));
  });

  test('admins set per-section defaults; only known sections and styles', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', imageStyles: { priests: 'avatar', saints: 'card', activities: 'banner' } }));
    await assertSucceeds(setDoc(ref, { imageStyles: {}, ...stamp() }, { merge: true }));
    for (const v of [{ priests: 'round' }, { liturgies: 'card' }, { priests: 1 }, 'card', ['card']]) {
      await assertFails(setDoc(ref, { imageStyles: v }, { merge: true }), JSON.stringify(v));
    }
  });

  test('visitors cannot change them', async () => {
    await assertFails(setDoc(doc(db(null), 'settings', 'features'), { imageStyles: { priests: 'card' } }));
    await assertFails(updateDoc(doc(db(null), 'priests', 'x'), { imageStyle: 'card' }));
  });
});

describe('ADR-027: custom categories, their items and custom pages', () => {
  const cat = (extra = {}) => ({
    slug: 'youth-trips', nameAr: 'رحلات الشباب', nameEn: 'Youth trips', introAr: 'مقدمة', introEn: '', icon: 'people',
    showInNav: true, visible: true, order: 10, ...extra,
  });
  const entry = (extra = {}) => ({
    categoryId: 'k1', titleAr: 'رحلة الإسكندرية', titleEn: '', descAr: 'وصف', descEn: '', contactPhone: '01012345678',
    externalUrl: '/page/donate', externalLabelAr: 'سجّل', externalLabelEn: '', visible: true, order: 10, sample: false, ...extra,
  });
  // A block is one string: the 7 fields joined by U+001F (PageBlock.encode).
  const block = (extra = {}) => {
    const b = { type: 'paragraph', textAr: 'نص', textEn: '', url: '', account: '', instapay: '', wallet: '', ...extra };
    return [b.type, b.textAr, b.textEn, b.url, b.account, b.instapay, b.wallet].join('\u001f');
  };
  const page = (extra = {}) => ({
    slug: 'new-building-donations', titleAr: 'التبرع لمبنى الخدمات', titleEn: 'Donations', subtitleAr: '', subtitleEn: '',
    showInNav: false, visible: true, order: 10, ...extra,
  });

  test('everyone reads; admins create, edit, hide and delete', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(setDoc(doc(ed, 'categories', 'k1'), cat()));
    await assertSucceeds(updateDoc(doc(ed, 'categories', 'k1'), { nameAr: 'رحلات', visible: false, imageStyle: 'banner' }));
    await assertSucceeds(setDoc(doc(ed, 'entries', 'e1'), entry({ image: { source: 'url', url: 'https://example.org/a.jpg', alt: '' } })));
    await assertSucceeds(updateDoc(doc(ed, 'entries', 'e1'), { visible: false }));
    await assertSucceeds(updateDoc(doc(ed, 'entries', 'e1'), { categoryId: 'other-cat' }));
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p1'), page({ image: { source: 'url', url: 'https://example.org/hero.jpg' } })));
    const pub = db(null);
    await assertSucceeds(getDocs(collection(pub, 'categories')));
    await assertSucceeds(getDocs(collection(pub, 'entries')));
    await assertSucceeds(getDocs(collection(pub, 'pages')));
    await assertFails(setDoc(doc(pub, 'categories', 'k2'), cat()));
    await assertFails(setDoc(doc(db(STRANGER), 'pages', 'p2'), page()));
    await assertFails(deleteDoc(doc(pub, 'entries', 'e1')));
    await assertSucceeds(deleteDoc(doc(ed, 'categories', 'k1')));
    await assertSucceeds(deleteDoc(doc(ed, 'pages', 'p1')));
  });

  test('categories: slug, name, icon and sizes are validated', async () => {
    const ed = db(EDITOR);
    for (const bad of [
      { slug: 'Youth' }, { slug: 'a b' }, { slug: '-x' }, { slug: 'x--y' }, { slug: 'a'.repeat(61) }, { slug: 5 },
      { nameAr: '' }, { nameAr: '   ' }, { nameAr: 'x'.repeat(121) }, { introAr: 'x'.repeat(1501) }, { icon: 'rocket' },
      { showInNav: 'yes' }, { imageStyle: 'huge' }, { extra: 1 }, { nameEn: null },
    ]) {
      await assertFails(setDoc(doc(ed, 'categories', 'kx'), cat(bad)), JSON.stringify(bad).slice(0, 60));
    }
    const noSlug = cat();
    delete noSlug.slug;
    await assertFails(setDoc(doc(ed, 'categories', 'kx'), noSlug));
  });

  test('items: category id, title, phone, link and sizes are validated', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(setDoc(doc(ed, 'entries', 'ok1'), entry({ externalUrl: 'https://example.org/x?y=1' })));
    await assertSucceeds(setDoc(doc(ed, 'entries', 'ok2'), entry({ externalUrl: '', contactPhone: '' })));
    for (const bad of [
      { categoryId: '' }, { categoryId: 'a/b' }, { categoryId: 3 }, { titleAr: '' }, { titleAr: 'x'.repeat(301) },
      { descAr: 'x'.repeat(2001) }, { contactPhone: 'call me' }, { externalUrl: 'javascript:alert(1)' },
      { externalUrl: '//evil.com' }, { externalUrl: 'https://' + 'a'.repeat(500) + '.com' }, { externalLabelAr: 'x'.repeat(81) },
      { stage: 'youth' },
    ]) {
      await assertFails(setDoc(doc(ed, 'entries', 'bad'), entry(bad)), JSON.stringify(bad).slice(0, 60));
    }
  });

  test('pages: 20 blocks of every type fit in one write; header and blocks are validated', async () => {
    const ed = db(EDITOR);
    const types = ['heading', 'paragraph', 'image', 'button', 'link', 'donation'];
    const full = Array.from({ length: 20 }, (_, i) => block({
      type: types[i % 6],
      textAr: 'ن'.repeat(4000),
      textEn: 'e'.repeat(4000),
      url: types[i % 6] === 'image' ? 'https://example.org/' + 'p'.repeat(470) : (i % 2 ? '/page/x' : 'https://example.org/give'),
      account: 'a'.repeat(120), instapay: 'i'.repeat(80), wallet: '0'.repeat(30),
    }));
    // Header and blocks in one create (the admin saves blocks on their own write).
    await assertSucceeds(setDoc(doc(ed, 'pages', 'big'), page({ blocks: full })));
    await assertSucceeds(updateDoc(doc(ed, 'pages', 'big'), { blocks: [block({ type: 'donation', account: 'CIB 100', instapay: 'church@instapay', wallet: '01012345678' })] }));
    await assertSucceeds(updateDoc(doc(ed, 'pages', 'big'), { showInNav: true }));
    await assertSucceeds(updateDoc(doc(ed, 'pages', 'big'), { blocks: [] }));
    for (const bad of [
      { slug: 'Bad Slug' }, { titleAr: '' }, { titleAr: 'x'.repeat(201) }, { subtitleAr: 'x'.repeat(301) }, { showInNav: 1 },
      { blocks: Array.from({ length: 21 }, () => block()) },
      { blocks: [block({ type: 'video' })] },
      { blocks: [{ type: 'paragraph', textAr: 'x' }] },
      { blocks: ['paragraph\u001fx'] },
      { blocks: [block() + '\u001fextra'] },
      { blocks: [block({ textAr: 'x'.repeat(4001) })] },
      { blocks: [block({ type: 'image', url: 'http://example.org/a.jpg' })] },
      { blocks: [block({ type: 'image', url: '/local.jpg' })] },
      { blocks: [block({ type: 'button', url: 'javascript:alert(1)' })] },
      { blocks: [block({ type: 'link', url: 'https://example.org/a b' })] },
      { blocks: [block({ type: 'donation', wallet: '0'.repeat(31) })] },
      { blocks: [5] },
      { other: 1 },
    ]) {
      await assertFails(setDoc(doc(ed, 'pages', 'bad'), page(bad)), JSON.stringify(bad).slice(0, 80));
    }
    await assertFails(updateDoc(doc(ed, 'pages', 'big'), { slug: 'UPPER' }));
    await assertFails(updateDoc(doc(ed, 'pages', 'big'), { blocks: [block({ type: 'nope' })] }));
  });

  test('the two custom-content section switches are known keys', async () => {
    await assertSucceeds(setDoc(doc(db(EDITOR), 'settings', 'features'), { sections: { customSections: false, customPages: true } }));
  });

  test('alerts link to a custom page, a section, a route or an external URL', async () => {
    const ed = db(EDITOR);
    for (const link of ['/page/new-building-donations', '/section/youth-trips', '/mass-schedule', 'https://example.org/x', '']) {
      await assertSucceeds(setDoc(doc(ed, 'alerts', `a-${link.length}`), { titleAr: 'تنويه', link, active: true }), link);
    }
    await assertFails(setDoc(doc(ed, 'alerts', 'a-bad'), { titleAr: 'تنويه', link: 'javascript:alert(1)' }));
  });
});

describe('ADR-028: contact categories, bookings and anonymous messages', () => {
  const send = (fs, msg) => {
    const batch = writeBatch(fs);
    const ref = doc(collection(fs, 'contact_messages'));
    batch.set(ref, { lang: 'ar', status: 'new', createdAt: serverTimestamp(), ...msg });
    batch.set(doc(fs, 'meta', 'contact_rate'), { lastAt: serverTimestamp(), lastMsgId: ref.id });
    return batch.commit();
  };
  const general = { category: 'c1', kind: 'general', name: 'Mina', phone: '01012345678', email: '', message: 'Hello there' };
  const booking = {
    category: 'c2', kind: 'booking', name: 'Mina', phone: '01012345678', email: '', message: 'نريد حجز القاعة',
    bookingType: 'wedding', preferredDate: '2027-02-14',
  };
  const anon = { category: 'c3', kind: 'complaint', anonymous: true, message: 'شكوى بدون اسم' };
  const reset = () => env.withSecurityRulesDisabled(async (ctx) => deleteDoc(doc(ctx.firestore(), 'meta', 'contact_rate')));
  // One string per slot (ContactCategory.encode): kind␟on␟anon␟order␟labelAr␟labelEn␟subtypes(␞-joined).
  const enc = (c) => [c.kind, c.on ? '1' : '0', c.anon ? '1' : '0', String(c.order), c.labelAr, c.labelEn,
    c.subtypes.join('\u001e')].join('\u001f');
  const raw = {
    c1: { labelAr: 'استفسار', labelEn: 'Inquiry', kind: 'general', on: true, anon: false, order: 10, subtypes: [] },
    c2: { labelAr: 'حجز قاعة', labelEn: '', kind: 'booking', on: true, anon: false, order: 20, subtypes: ['wedding|فرح|Wedding', 'condolence|عزاء|'] },
    c3: { labelAr: 'شكوى', labelEn: '', kind: 'complaint', on: true, anon: true, order: 30, subtypes: [] },
    c4: { labelAr: 'اقتراح', labelEn: '', kind: 'suggestion', on: false, anon: true, order: 40, subtypes: [] },
  };
  const cats = Object.fromEntries(Object.entries(raw).map(([k, v]) => [k, enc(v)]));

  test('code defaults (no settings/contact): general, booking and anonymous complaint go through', async () => {
    const pub = db(null);
    await assertSucceeds(send(pub, general));
    await reset();
    await assertSucceeds(send(pub, booking));
    await reset();
    await assertSucceeds(send(pub, { ...booking, preferredDate: '2028-02-29' }), 'leap day');
    await reset();
    await assertSucceeds(send(pub, anon));
    await reset();
    await assertSucceeds(send(pub, { ...anon, category: 'c4', kind: 'suggestion' }));
    await reset();
    // The legacy shape (no category) still works.
    await assertSucceeds(send(pub, { name: 'Mina', phone: '01012345678', email: '', message: 'Hello there' }));
  });

  test('anonymous messages never carry identity fields and only for anonymous-capable categories', async () => {
    const pub = db(null);
    for (const bad of [
      { ...anon, name: 'Mina' }, { ...anon, phone: '01012345678' }, { ...anon, email: '' }, { ...anon, phone: '' },
      { ...anon, category: 'c1', kind: 'general' }, { ...anon, category: 'c2', kind: 'booking' },
      { ...anon, kind: 'suggestion' }, { ...anon, anonymous: 'yes' }, { ...anon, preferredDate: '2027-01-01' },
      { message: 'no category', anonymous: true },
    ]) {
      await assertFails(send(pub, bad), JSON.stringify(bad).slice(0, 80));
    }
  });

  test('category values, bookings and sizes are validated', async () => {
    const pub = db(null);
    for (const bad of [
      { ...general, category: 'c13' }, { ...general, category: 'c9' }, { ...general, kind: 'booking' },
      { ...general, category: 1 }, { ...general, kind: undefined }, { ...general, preferredDate: '2027-01-01' },
      { ...booking, phone: '' }, { ...booking, phone: undefined, email: 'a@b.co' }, { ...booking, preferredDate: '14/02/2027' },
      { ...booking, preferredDate: undefined }, { ...booking, bookingType: 'Wedding Party' },
      { ...booking, preferredDate: '2027-02-31' }, { ...booking, preferredDate: '2027-04-31' },
      { ...booking, preferredDate: '2027-02-29' }, { ...booking, preferredDate: '1999-12-01' },
      { ...general, message: 'x'.repeat(1001) }, { ...general, name: 'x' }, { ...general, extra: 1 },
      { kind: 'general', name: 'Mina', phone: '01012345678', message: 'Hello there' },
    ]) {
      const m = Object.fromEntries(Object.entries(bad).filter(([, v]) => v !== undefined));
      await assertFails(send(pub, m), JSON.stringify(m).slice(0, 80));
    }
  });

  test('stored categories replace the defaults: switched-off and missing slots are refused', async () => {
    await assertSucceeds(setDoc(doc(db(EDITOR), 'settings', 'contact'), { categories: cats }));
    const pub = db(null);
    await assertSucceeds(send(pub, booking));
    await reset();
    await assertFails(send(pub, { ...anon, category: 'c4', kind: 'suggestion' }), 'c4 is switched off');
    await assertFails(send(pub, { ...general, category: 'c5' }), 'c5 does not exist');
    await assertSucceeds(send(pub, anon));
  });

  test('admins edit settings/contact; shapes are validated; 12 full categories fit in one write', async () => {
    const ref = doc(db(EDITOR), 'settings', 'contact');
    const many = Object.fromEntries(Array.from({ length: 12 }, (_, i) => [`c${i + 1}`, enc({
      labelAr: 'ن'.repeat(80), labelEn: 'e'.repeat(80), kind: 'booking', on: true, anon: false, order: i,
      subtypes: Array.from({ length: 8 }, (_, j) => `type${j}|${'ع'.repeat(60)}|${'e'.repeat(60)}`),
    })]));
    await assertSucceeds(setDoc(ref, { categories: many }));
    await assertSucceeds(setDoc(ref, { categories: cats }));
    for (const bad of [
      {}, { 'Bad-Id': cats.c1 }, { c_1: cats.c1 }, { ['c' + 'x'.repeat(16)]: cats.c1 },
      Object.fromEntries(Array.from({ length: 13 }, (_, i) => [`c${i + 1}`, cats.c1])),
      { c1: enc({ ...raw.c1, kind: 'spam' }) }, { c1: enc({ ...raw.c1, anon: true }) },
      { c1: enc({ ...raw.c1, labelAr: '' }) }, { c1: enc({ ...raw.c1, labelAr: ' ' }) }, { c1: enc({ ...raw.c1, labelAr: 'x'.repeat(81) }) },
      { c1: raw.c1 }, { c1: cats.c1 + '\u001fextra' }, { c1: enc({ ...raw.c1, order: 'x' }) },
      { c2: enc({ ...raw.c2, subtypes: ['Wedding|فرح|Wedding'] }) }, { c2: enc({ ...raw.c2, subtypes: ['wedding||Wedding'] }) },
      { c2: enc({ ...raw.c2, subtypes: ['wedding| |Wedding'] }) },
      { c2: enc({ ...raw.c2, subtypes: ['wedding|' + 'x'.repeat(61) + '|'] }) },
      { c2: enc({ ...raw.c2, subtypes: Array.from({ length: 9 }, (_, j) => `t${j}|x|`) }) },
    ]) {
      await assertFails(setDoc(ref, { categories: bad }), JSON.stringify(bad).slice(0, 80));
    }
    await assertFails(setDoc(ref, { categories: cats, other: 1 }));
    await assertFails(setDoc(doc(db(null), 'settings', 'contact'), { categories: cats }));
    await assertSucceeds(getDoc(doc(db(null), 'settings', 'contact')));
  });

  test('admins set booking status and internal notes only', async () => {
    const ed = db(EDITOR);
    const stamp = { updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` };
    for (const status of ['contacted', 'confirmed', 'declined', 'handled', 'new']) {
      await assertSucceeds(updateDoc(doc(ed, 'contact_messages', 'm1'), { status, ...stamp }), status);
    }
    await assertSucceeds(updateDoc(doc(ed, 'contact_messages', 'm1'), { adminNotes: 'اتصلنا به', ...stamp }));
    await assertFails(updateDoc(doc(ed, 'contact_messages', 'm1'), { adminNotes: 'x'.repeat(2001) }));
    await assertFails(updateDoc(doc(ed, 'contact_messages', 'm1'), { adminNotes: 5 }));
    await assertFails(updateDoc(doc(ed, 'contact_messages', 'm1'), { status: 'archived' }));
    await assertFails(updateDoc(doc(ed, 'contact_messages', 'm1'), { category: 'c2' }));
    await assertFails(updateDoc(doc(db(STRANGER), 'contact_messages', 'm1'), { adminNotes: 'x' }));
  });
});

describe('PR #19: stable contact category ids (never re-label old messages)', () => {
  const enc = (c) => [c.kind, c.on ? '1' : '0', c.anon ? '1' : '0', String(c.order), c.labelAr, c.labelEn,
    (c.subtypes || []).join('\u001e')].join('\u001f');
  const send = (fs, msg) => {
    const batch = writeBatch(fs);
    const ref = doc(collection(fs, 'contact_messages'));
    batch.set(ref, { lang: 'ar', status: 'new', createdAt: serverTimestamp(), ...msg });
    batch.set(doc(fs, 'meta', 'contact_rate'), { lastAt: serverTimestamp(), lastMsgId: ref.id });
    return batch.commit();
  };
  const reset = () => env.withSecurityRulesDisabled(async (ctx) => deleteDoc(doc(ctx.firestore(), 'meta', 'contact_rate')));
  const general = (category) => ({ category, kind: 'general', name: 'Mina', phone: '01012345678', email: '', message: 'Hello there' });
  const c1 = enc({ kind: 'general', on: true, anon: false, order: 10, labelAr: 'استفسار', labelEn: '' });
  const visit = enc({ kind: 'general', on: true, anon: false, order: 20, labelAr: 'زيارة منزلية', labelEn: 'Home visit' });
  const prayer = enc({ kind: 'general', on: true, anon: false, order: 30, labelAr: 'طلب صلاة', labelEn: 'Prayer request' });

  test('random ids save and receive messages; a deleted id is refused, its replacement has a new id', async () => {
    const ref = doc(db(EDITOR), 'settings', 'contact');
    await assertSucceeds(setDoc(ref, { categories: { c1, ck3j9x2ab7q: visit } }));
    const pub = db(null);
    await assertSucceeds(send(pub, general('ck3j9x2ab7q')));
    await reset();
    // The admin deletes "Home visit" and adds "Prayer request": a fresh id.
    await assertSucceeds(setDoc(ref, { categories: { c1, cz81mq0w4re: prayer } }));
    await assertFails(send(pub, general('ck3j9x2ab7q')), 'the deleted category is gone');
    await assertSucceeds(send(pub, general('cz81mq0w4re')));
    await reset();
    await assertFails(send(pub, general('C1')), 'malformed id');
    await assertFails(send(pub, general('c' + 'a'.repeat(16))), 'too long');
  });

  test('12 full categories with random ids fit in one write; an edit validates only what changed', async () => {
    const ref = doc(db(EDITOR), 'settings', 'contact');
    const full = (i) => enc({
      labelAr: 'ن'.repeat(80), labelEn: 'e'.repeat(80), kind: 'booking', on: true, anon: false, order: i,
      subtypes: Array.from({ length: 8 }, (_, j) => `type${j}|${'ع'.repeat(60)}|${'e'.repeat(60)}`),
    });
    const ids = Array.from({ length: 12 }, (_, i) => `c${(1e9 + i * 7919).toString(36)}x${i}`);
    const many = Object.fromEntries(ids.map((id, i) => [id, full(i)]));
    await assertSucceeds(setDoc(ref, { categories: many }));
    await assertSucceeds(setDoc(ref, { categories: { ...many, [ids[3]]: visit } }));
    await assertFails(setDoc(ref, { categories: { ...many, [ids[3]]: 'nonsense' } }));
    await assertFails(setDoc(ref, { categories: { ...many, cextra13: visit } }), '13 categories');
  });
});

describe('ADR-029: assistant settings (settings/assistant)', () => {
  const full = {
    model: 'gemini-3.1-flash-lite',
    instructions: 'i'.repeat(4000),
    topics: 't'.repeat(2000),
    refusalAr: 'ع'.repeat(500), refusalEn: 'r'.repeat(500),
    welcomeAr: 'أ'.repeat(500), welcomeEn: 'w'.repeat(500),
    suggestionsAr: 'س'.repeat(300), suggestionsEn: 's'.repeat(300),
    faithReplyAr: 'م'.repeat(300), faithReplyEn: 'm'.repeat(300), mentionUnconfirmed: true, showSuggestions: true,
    sourceDomains: 'st-takla.org, example.org', perDay: 100,
    maxChars: 1000, perMinute: 20, perSession: 200,
  };

  test('everyone reads; admins save every field at its maximum, blanks and nulls (= defaults)', async () => {
    const ref = doc(db(EDITOR), 'settings', 'assistant');
    await assertSucceeds(setDoc(ref, full));
    await assertSucceeds(getDoc(doc(db(null), 'settings', 'assistant')));
    await assertSucceeds(setDoc(ref, { model: '', instructions: '', topics: '', maxChars: null, perMinute: null, perSession: null }));
    await assertSucceeds(setDoc(ref, { model: 'gemini-3.5-flash-lite', updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` }, { merge: true }));
    await assertSucceeds(updateDoc(ref, { maxChars: 50, perMinute: 1, perSession: 1 }));
  });

  test('model ids, lengths, number ranges and unknown keys are validated', async () => {
    const ref = doc(db(EDITOR), 'settings', 'assistant');
    for (const bad of [
      { model: 'gpt-4o' }, { model: 'Gemini-3' }, { model: 'gemini 3' }, { model: 'gemini-' }, { model: 'gemma-3-27b' },
      { model: 'gemini-' + 'a'.repeat(60) }, { model: 3 }, { model: null },
      { instructions: 'x'.repeat(4001) }, { topics: 'x'.repeat(2001) }, { refusalAr: 'x'.repeat(501) },
      { welcomeEn: 'x'.repeat(501) }, { suggestionsEn: 'x'.repeat(301) }, { refusalEn: 5 },
      { faithReplyAr: 'x'.repeat(301) }, { faithReplyEn: 7 }, { mentionUnconfirmed: 'yes' }, { showSuggestions: 1 },
      { sourceDomains: 'St-Takla.org' }, { sourceDomains: 'a.org/<script>' }, { sourceDomains: 'a'.repeat(301) },
      { perDay: 0 }, { perDay: 101 }, { perDay: '3' },
      { maxChars: 49 }, { maxChars: 1001 }, { maxChars: 300.5 }, { perMinute: 0 }, { perMinute: 21 },
      { perSession: 201 }, { perSession: '5' }, { enabled: true }, { updatedBy: 'someone@else.test' },
    ]) {
      await assertFails(setDoc(ref, bad), JSON.stringify(bad).slice(0, 80));
    }
  });

  test('the admin switches: sections.assistant (field-path update) and church assistantEnabled', async () => {
    await env.withSecurityRulesDisabled(async (ctx) =>
      setDoc(doc(ctx.firestore(), 'settings', 'features'), convert(seed.settings.features)));
    const ed = db(EDITOR);
    const stamp = { updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` };
    await assertSucceeds(updateDoc(doc(ed, 'settings', 'features'), { 'sections.assistant': false, ...stamp }));
    await assertSucceeds(updateDoc(doc(ed, 'settings', 'features'), { 'sections.assistant': true, ...stamp }));
    await assertFails(updateDoc(doc(ed, 'settings', 'features'), { 'sections.assistant': 'yes', ...stamp }));
    await assertSucceeds(setDoc(doc(ed, 'settings', 'church'), { assistantEnabled: true, ...stamp }, { merge: true }));
    await assertFails(updateDoc(doc(db(null), 'settings', 'features'), { 'sections.assistant': false }));
  });

  test('visitors and non-admins cannot change it; it can never be deleted', async () => {
    await assertFails(setDoc(doc(db(null), 'settings', 'assistant'), { model: 'gemini-3.1-flash-lite' }));
    await assertFails(setDoc(doc(db(STRANGER), 'settings', 'assistant'), { model: 'gemini-3.1-flash-lite' }));
    await assertSucceeds(setDoc(doc(db(EDITOR), 'settings', 'assistant'), { model: '' }));
    await assertFails(deleteDoc(doc(db(OWNER), 'settings', 'assistant')));
  });
});

describe('ADR-039 / ADR-040: today layer in settings/features (strip, day start, top event, live, events)', () => {
  const S = '\u001f';
  const ev = (o = {}) => {
    const v = { date: '2026-11-04', endDate: '', start: '19:00', end: '21:00', titleAr: 'الليلة الرابعة من نهضة الشفعاء',
      titleEn: 'Fourth night', speakerAr: '', speakerEn: '', topicAr: '', topicEn: '', noteAr: '', noteEn: '', link: '', ...o };
    return ['date', 'endDate', 'start', 'end', 'titleAr', 'titleEn', 'speakerAr', 'speakerEn', 'topicAr', 'topicEn',
      'noteAr', 'noteEn', 'link'].map((k) => v[k]).join(S);
  };

  test('admins set the strip, day start and top-event switches; wrong values are rejected', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', copticStrip: 'home', dayStartMode: 'sunset', dayStartsAt: '18:30',
      topEvent: false, commemoration: true }));
    await assertSucceeds(updateDoc(ref, { dayStartMode: 'fixed', dayStartsAt: '' }));
    for (const bad of [{ copticStrip: 'top' }, { dayStartMode: 'noon' }, { dayStartsAt: '24:00' }, { dayStartsAt: 18 },
      { topEvent: 'yes' }, { commemoration: 1 }]) {
      await assertFails(updateDoc(ref, bad), JSON.stringify(bad));
    }
  });

  test('live banner: bool switch, http(s) link, short labels, optional switch-off time', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', liveEnabled: true, liveUrl: 'https://www.youtube.com/live/abc',
      liveLabelAr: 'بث مباشر الآن من الكنيسة', liveLabelEn: '', liveEndsAt: Timestamp.fromDate(new Date('2026-11-04T20:00:00Z')) }));
    await assertSucceeds(updateDoc(ref, { liveEnabled: false, liveEndsAt: null, liveUrl: '' }));
    // ADR-044: hide the top-bar badge on Home while the banner shows (bool, default on).
    await assertSucceeds(updateDoc(ref, { liveBadgeHideOnHome: false }));
    await assertSucceeds(updateDoc(ref, { liveBadgeHideOnHome: true, liveEnabled: true }));
    for (const bad of [{ liveEnabled: 'on' }, { liveUrl: 'javascript:alert(1)' }, { liveUrl: 'ftp://x.y/z' },
      { liveLabelAr: 'x'.repeat(121) }, { liveEndsAt: '2026-11-04' }, { liveBadgeHideOnHome: 'yes' },
      { liveBadgeHideOnHome: 1 }]) {
      await assertFails(updateDoc(ref, bad), JSON.stringify(bad).slice(0, 60));
    }
  });

  test('church events: up to 20 encoded strings, each validated', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', dayEvents: [ev(), ev({ date: '2026-11-05', start: '', end: '',
      titleAr: 'بصخة ليلة الخميس', link: '/mass-schedule', speakerAr: 'نيافة الأنبا', endDate: '2026-11-06' })] }));
    await assertSucceeds(updateDoc(ref, { dayEvents: Array.from({ length: 20 }, () => ev({ link: 'https://fb.com/x' })) }));
    await assertSucceeds(updateDoc(ref, { dayEvents: [] }));
    // Same-day and later end dates; 20 events with end dates stay within the expression budget.
    await assertSucceeds(updateDoc(ref, { dayEvents: [ev({ endDate: '2026-11-04' }), ev({ date: '2026-12-31', endDate: '2027-01-01' })] }));
    await assertSucceeds(updateDoc(ref, { dayEvents: Array.from({ length: 20 }, () => ev({ endDate: '2026-11-30', link: 'https://fb.com/x' })) }));
    // The whole «اليوم والبث المباشر» form as the editor saves it (splitSavePayload, ADR-044):
    // every other Today key in one write (the badge switch included), then 20 events with end dates.
    const todayKeys = { copticStrip: 'home', dayStartMode: 'sunset', dayStartsAt: '18:30', topEvent: false,
      commemoration: false, liveEnabled: true, liveUrl: 'https://www.youtube.com/live/abc', liveLabelAr: 'x'.repeat(120),
      liveLabelEn: 'y'.repeat(120), liveEndsAt: Timestamp.fromDate(new Date('2026-11-04T20:00:00Z')), liveBadgeHideOnHome: false };
    const fullEvents = Array.from({ length: 20 }, () => ev({ endDate: '2026-12-30', link: 'https://fb.com/y' }));
    // Stamped like AdminRepository.saveDoc (updatedAt = request time, updatedBy = the admin's email): the production shape.
    const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` });
    await assertSucceeds(updateDoc(ref, { ...todayKeys, ...stamp() }));
    await assertSucceeds(updateDoc(ref, { dayEvents: fullEvents, ...stamp() }));
    // Why the editor splits: 20 events plus another changed Today key in one write exceed the 1,000 expressions.
    await assertFails(updateDoc(ref, { liveEnabled: false, ...stamp(),
      dayEvents: fullEvents.map((e) => e.replace('2026-12-30', '2026-12-29')) }));
    for (const bad of [
      [ev({ titleAr: '' })], [ev({ date: '4-11-2026' })], [ev({ start: '7pm' })], [ev({ link: 'javascript:x' })],
      [ev({ noteAr: 'x'.repeat(501) })], [ev() + S + 'extra'], [5], Array.from({ length: 21 }, () => ev()),
      [ev({ date: '2026-13-01' })], [ev({ date: '2026-00-10' })], [ev({ date: '2026-11-32' })], [ev({ endDate: '2026-11-00' })],
    ]) {
      await assertFails(updateDoc(ref, { dayEvents: bad }), JSON.stringify(bad).slice(0, 60));
    }
  });

  test('visitors cannot change any of it', async () => {
    await assertFails(updateDoc(doc(db(null), 'settings', 'features'), { liveEnabled: true }));
    await assertFails(setDoc(doc(db(null), 'settings', 'features'), { dayEvents: [ev()] }));
  });
});

// ---------------------------------------------------------------------------
// ADR-041: programme details on liturgies, meetings and seasons; venue /
// audience lists in settings/features.
describe('ADR-041: programme details (speaker, topic, choir, venue, audience, Drive PDF link)', () => {
  const S = '\u001f';
  const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` });
  const full = {
    speakerAr: 'م'.repeat(200), speakerEn: 's'.repeat(200), topicAr: 'ع'.repeat(300), topicEn: 't'.repeat(300),
    choirAr: 'ك'.repeat(200), choirEn: 'c'.repeat(200), venue: 'lower_hall-2', audience: 'youth',
    attachmentUrl: 'https://drive.google.com/file/d/1AbC_dEf/view?usp=sharing', attachmentLabelAr: 'ك'.repeat(80),
    attachmentLabelEn: 'Booklet',
  };
  const base = {
    liturgies: { type: 'other', nameAr: 'بصخة ليلة الثلاثاء', start: '19:00', weekday: 1, seasonKey: 'holy_week' },
    meetings: { stage: 'youth', nameAr: 'اجتماع الشباب' },
    seasons: { key: 'holy_week', nameAr: 'أسبوع الآلام', replacesRegular: true },
  };

  test('every programme key on the three collections, worst case lengths', async () => {
    const ed = db(EDITOR);
    for (const [col, b] of Object.entries(base)) {
      await assertSucceeds(setDoc(doc(ed, col, 'p'), { ...b, ...full, ...stamp() }), col);
      await assertSucceeds(updateDoc(doc(ed, col, 'p'), { venue: null, audience: '', attachmentUrl: '', speakerAr: 'أبونا', ...stamp() }), col);
      await assertSucceeds(updateDoc(doc(ed, col, 'p'), { topicAr: 'التوبة' }), col);
    }
  });

  test('a meeting with a full detail page also takes the programme fields (expression budget)', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(setDoc(doc(ed, 'meetings', 'big'), {
      ...base.meetings, ...full, weekday: 5, start: '19:00', end: '21:00', hallAr: 'ق'.repeat(300), notes: 'ن'.repeat(300),
      detailsEnabled: true, detailsAr: 'ت'.repeat(10000), detailsEn: 'd'.repeat(10000), whatsapp: '01012345678',
      facebookUrl: 'https://facebook.com/x', whatsappUrl: 'https://chat.whatsapp.com/x', contactPhone: '01012345678',
      externalUrl: 'https://forms.example.org/r', image: { source: 'url', url: 'https://img.example.org/c.jpg', alt: 'c' },
      visible: true, sample: false, order: 1, ...stamp(),
    }));
  });

  test('bad values are rejected', async () => {
    const ed = db(EDITOR);
    for (const [col, b] of Object.entries(base)) {
      await assertSucceeds(setDoc(doc(ed, col, 'q'), b));
      for (const bad of [
        { attachmentUrl: 'http://drive.google.com/x' }, { attachmentUrl: 'javascript:alert(1)' },
        { attachmentUrl: 'https://drive google.com/x' }, { venue: 'Lower Hall' }, { audience: 'x'.repeat(31) },
        { speakerAr: 'م'.repeat(201) }, { topicEn: 't'.repeat(301) }, { choirAr: 5 }, { attachmentLabelAr: 'x'.repeat(81) },
        { speakerAr: `a${S}b` }, { venue: true },
        { attachmentUrl: 'https://drive.google.com/file/d/a\tb' }, { attachmentUrl: 'https://drive.google.com/x\ny' },
        { attachmentUrl: 'https://drive.google.com/' + 'x'.repeat(476) },
      ]) {
        await assertFails(updateDoc(doc(ed, col, 'q'), bad), `${col} ${JSON.stringify(bad).slice(0, 60)}`);
      }
    }
  });

  test('a 500-character Drive link (the form maximum) is accepted', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(setDoc(doc(ed, 'seasons', 'long'), { ...base.seasons, ...stamp() }));
    const url = 'https://drive.google.com/' + 'x'.repeat(475);
    await assertSucceeds(updateDoc(doc(ed, 'seasons', 'long'), { attachmentUrl: url, ...stamp() }));
  });

  test('visitors cannot write programme details', async () => {
    await assertFails(setDoc(doc(db(null), 'liturgies', 'v'), { ...base.liturgies, speakerAr: 'x' }));
  });

  test('venues / audiences: up to 12 encoded rows each', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    const row = (k, ar = 'القاعة', en = '') => [k, ar, en].join(S);
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', venues: [row('main', 'الكنيسة الكبرى', 'Main church'), row('lower')],
      audiences: [row('general', 'عام', 'Everyone')] }));
    await assertSucceeds(updateDoc(ref, { venues: Array.from({ length: 12 }, (_, i) => row(`v${i}`, 'ق'.repeat(80), 'e'.repeat(80))) }));
    await assertSucceeds(updateDoc(ref, { venues: [], audiences: null }));
    for (const bad of [
      [row('Main')], [row('main', '')], [row('main') + S + 'x'], ['main'], [5], [row('a'.repeat(31))],
      [row('main', 'ق'.repeat(81))], Array.from({ length: 13 }, (_, i) => row(`v${i}`)), 'main',
    ]) {
      await assertFails(updateDoc(ref, { venues: bad }), JSON.stringify(bad).slice(0, 60));
      await assertFails(updateDoc(ref, { audiences: bad }), JSON.stringify(bad).slice(0, 60));
    }
    await assertFails(updateDoc(doc(db(null), 'settings', 'features'), { venues: [row('x')] }));
  });
});

describe('ADR-042: season preset, season verses, wedding switch, assistant season limit', () => {
  const S = '\u001f';
  const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` });
  const end = Timestamp.fromDate(new Date('2027-05-01T22:00:00Z'));
  const preset = {
    seasonId: 'hw', seasonKey: 'holy_week', appliedAt: Timestamp.fromDate(new Date('2027-04-20T10:00:00Z')), endsAt: end,
    options: ['replaceRegular', 'hideMeetings', 'hideClinics', 'heroMotionOff', 'weddingOff', 'live', 'pdf'],
    previous: {
      seasonActive: false, replacesRegular: false, meetings: true, clinics: true, heroMotion: true, weddingBookingOff: false,
      liveUrl: 'https://youtube.com/' + 'x'.repeat(480), liveEndsAt: null, attachmentUrl: 'https://drive.google.com/' + 'x'.repeat(575),
      attachmentLabelAr: 'ك'.repeat(80), attachmentLabelEn: 'b'.repeat(80),
    },
  };

  test('apply and restore as ONE batch of settings/features + the season', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(setDoc(doc(ed, 'seasons', 'hw'), { key: 'holy_week', nameAr: 'أسبوع الآلام', endsAt: end, active: false }));
    const apply = writeBatch(ed);
    apply.set(doc(ed, 'settings', 'features'), {
      sections: { meetings: false, clinics: false, schedule: true }, heroMotion: false, weddingBookingOff: true,
      liveUrl: 'https://youtube.com/live/abc', liveEndsAt: end, seasonPreset: preset, ...stamp(),
    }, { merge: true });
    apply.set(doc(ed, 'seasons', 'hw'), {
      active: true, replacesRegular: true, attachmentUrl: 'https://drive.google.com/file/d/x/view',
      attachmentLabelAr: 'كتيب البصخة', attachmentLabelEn: '', ...stamp(),
    }, { merge: true });
    await assertSucceeds(apply.commit());
    const restore = writeBatch(ed);
    restore.set(doc(ed, 'settings', 'features'), {
      seasonPreset: null, sections: { meetings: true, clinics: true, schedule: true }, heroMotion: true,
      weddingBookingOff: false, liveUrl: '', liveEndsAt: null, ...stamp(),
    }, { merge: true });
    restore.set(doc(ed, 'seasons', 'hw'), { active: false, replacesRegular: false, attachmentUrl: '', ...stamp() }, { merge: true });
    await assertSucceeds(restore.commit());
  });

  test('a bad preset is refused', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'burgundy' }));
    for (const bad of [
      { ...preset, seasonId: 'a/b' }, { ...preset, seasonKey: 'lent' }, { ...preset, options: ['nuke'] },
      { ...preset, options: [...preset.options, 'live'] }, { ...preset, endsAt: '2027-05-01' }, { ...preset, extra: 1 },
      { ...preset, previous: { ...preset.previous, meetings: 'yes' } }, { ...preset, previous: { ...preset.previous, evil: 1 } },
      { ...preset, previous: { ...preset.previous, liveUrl: 'x'.repeat(501) } },
      { ...preset, previous: { ...preset.previous, attachmentLabelAr: 'x'.repeat(81) } },
      { ...preset, previous: { ...preset.previous, liveEndsAt: 'tomorrow' } }, 'hw',
    ]) {
      await assertFails(updateDoc(ref, { seasonPreset: bad }), JSON.stringify(bad).slice(0, 80));
    }
    for (const bad of ['yes', 1]) await assertFails(updateDoc(ref, { weddingBookingOff: bad }));
    await assertFails(updateDoc(doc(db(null), 'settings', 'features'), { seasonPreset: null }));
    await assertFails(updateDoc(doc(db(null), 'settings', 'features'), { weddingBookingOff: true }));
  });

  test('season verses: up to 40 encoded rows of a known season', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    const row = (k, t = 'هوذا حمل الله', r = 'يو 1: 29') => [k, t, r].join(S);
    await assertSucceeds(setDoc(ref, { seasonVerses: [row('holy_week'), row('pascha', 'المسيح قام', '')] }));
    await assertSucceeds(updateDoc(ref, { seasonVerses: Array.from({ length: 40 }, () => row('summer', 'آ'.repeat(500), 'ر'.repeat(60))) }));
    await assertSucceeds(updateDoc(ref, { seasonVerses: [] }));
    await assertSucceeds(updateDoc(ref, { seasonVerses: null }));
    for (const bad of [
      [row('lent')], [row('holy_week', '')], [row('holy_week', 'آ'.repeat(501))], [row('holy_week', 'x', 'ر'.repeat(61))],
      [row('holy_week') + S + 'x'], ['holy_week'], [5], Array.from({ length: 41 }, () => row('summer')), 'x',
    ]) {
      await assertFails(updateDoc(ref, { seasonVerses: bad }), JSON.stringify(bad).slice(0, 60));
    }
  });

  test('assistant perDaySeason 1..100', async () => {
    const ref = doc(db(EDITOR), 'settings', 'assistant');
    await assertSucceeds(setDoc(ref, { perDay: 3, perDaySeason: 6 }));
    await assertSucceeds(updateDoc(ref, { perDaySeason: 100 }));
    await assertSucceeds(updateDoc(ref, { perDaySeason: null }));
    for (const bad of [0, 101, '6', 6.5]) await assertFails(updateDoc(ref, { perDaySeason: bad }), String(bad));
  });
});

describe('ADR-043: season-following theme, season theme map, preset theme item, new season keys', () => {
  const ref = () => doc(db(EDITOR), 'settings', 'features');
  const start = Timestamp.fromDate(new Date('2027-04-24T00:00:00+02:00'));
  const end = Timestamp.fromDate(new Date('2027-05-02T00:00:00+02:00'));
  const preset = {
    seasonId: 'hw', seasonKey: 'holy_week', appliedAt: start, startsAt: start, endsAt: end,
    options: ['replaceRegular', 'hideMeetings', 'hideClinics', 'heroMotionOff', 'weddingOff', 'live', 'pdf', 'theme'],
    previous: { seasonActive: false, heroMotion: true, theme: 'burgundy' },
  };

  test('followSeason and the season theme map are accepted', async () => {
    await assertSucceeds(setDoc(ref(), {
      theme: 'goldenHour',
      occasions: {
        auto: false, easter: true, resurrectionDays: 7, schedule: {}, followSeason: true,
        seasonThemes: { holy_week: 'holyWeek', pascha: 'none', fast: 'fasting', marian: 'marian', epiphany: 'epiphany',
          nativity: 'nativity', revival_maximus: 'brown', revival_moses: 'none', summer: 'none' },
      },
    }));
    await assertSucceeds(updateDoc(ref(), { occasions: { followSeason: false, seasonThemes: {} } }));
  });

  test('twelve new slots and a full season theme map fit one write (expression budget)', async () => {
    await assertSucceeds(setDoc(ref(), {
      theme: 'goldenHour',
      occasions: {
        auto: true, easter: true, resurrectionDays: 50, followSeason: true,
        schedule: Object.fromEntries(Array.from({ length: 12 }, (_, i) => [`r${i + 1}`, 'nativity|2026-12-25|2027-01-08'])),
        seasonThemes: { holy_week: 'holyWeek', pascha: 'resurrection', fast: 'fasting', marian: 'marian',
          epiphany: 'epiphany', nativity: 'nativity', revival_maximus: 'brown', revival_moses: 'none', summer: 'none' },
      },
    }));
  });

  test('bad switches and maps are refused', async () => {
    for (const o of [
      { followSeason: 'yes' }, { seasonThemes: [] }, { seasonThemes: { lent: 'fasting' } },
      { seasonThemes: { holy_week: 'violet' } }, { seasonThemes: { holy_week: 5 } }, { seasonThemes: 'holyWeek' },
      { seasonThemes: { holy_week: '' } }, { seasonThemes: { holy_week: 'holyWeek,none', pascha: 'none' } },
      { seasonThemes: { holy_week: 'holyWeek,' } }, { schedule: { r1: '' } },
      { schedule: { r1: 'holyWeek|2027-04-25|2027-05-01,holyWeek|2027-04-25|2027-05-01' } },
    ]) {
      await assertFails(setDoc(ref(), { occasions: o }), JSON.stringify(o).slice(0, 80));
    }
  });

  test('the preset may set the theme (8 options, previous theme, season start)', async () => {
    await assertSucceeds(setDoc(ref(), { theme: 'holyWeek', seasonPreset: preset }));
    await assertSucceeds(updateDoc(ref(), { theme: 'burgundy', seasonPreset: null }), 'restore');
    for (const bad of [
      { ...preset, options: [...preset.options, 'theme'] },
      { ...preset, options: ['theme', 'theme'] },
      { ...preset, previous: { ...preset.previous, theme: 'neon' } },
      { ...preset, previous: { ...preset.previous, theme: 5 } },
      { ...preset, startsAt: '2027-04-24' },
    ]) {
      await assertFails(updateDoc(ref(), { seasonPreset: bad }), JSON.stringify(bad).slice(0, 80));
    }
  });

  test('new season keys: epiphany, marian, fast (seasons, services, verses, preset)', async () => {
    const ed = db(EDITOR);
    for (const k of ['epiphany', 'marian', 'fast']) {
      await assertSucceeds(setDoc(doc(ed, 'seasons', k), { key: k, nameAr: 'موسم', active: true }), k);
      await assertSucceeds(setDoc(ref(), { seasonVerses: [[k, 'آية', ''].join('\u001f')] }), `${k} verse`);
      await assertSucceeds(setDoc(ref(), { seasonPreset: { ...preset, seasonKey: k } }), `${k} preset`);
    }
    await assertFails(setDoc(doc(ed, 'seasons', 'lent'), { key: 'lent', nameAr: 'موسم', active: true }));
  });
});

// ---------------------------------------------------------------------------
// ADR-045: top-event fallback switch and a church event's own PDF button
// (three optional trailing fields of the encoded event string).
describe('ADR-045: topEventServices switch, day-event attachment', () => {
  const S = '\u001f';
  const base = ['2026-11-05', '', '18:30', '21:30', 'الليلة الرابعة', '', 'أبونا', '', 'الرجاء', '', '', '', ''];
  const ev = (url = 'https://drive.google.com/file/d/x/view', ar = 'تحميل برنامج النهضة (PDF)', en = '') =>
    [...base, url, ar, en].join(S);
  const ref = () => doc(db(EDITOR), 'settings', 'features');
  const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` });

  test('topEventServices is an optional bool', async () => {
    await assertSucceeds(setDoc(ref(), { theme: 'burgundy', topEventServices: false }));
    await assertSucceeds(updateDoc(ref(), { topEventServices: true, topEvent: true, commemoration: false }));
    for (const bad of [{ topEventServices: 'yes' }, { topEventServices: 1 }]) {
      await assertFails(updateDoc(ref(), bad), JSON.stringify(bad));
    }
  });

  test('events with an https PDF and labels; the 13-field form stays valid', async () => {
    await assertSucceeds(setDoc(ref(), { theme: 'burgundy', dayEvents: [ev(), base.join(S), ev('', '', '')] }));
    // 20 events carrying a PDF and both labels fit one write (expression budget), stamped like the editor.
    await assertSucceeds(updateDoc(ref(), { dayEvents: Array.from({ length: 20 }, () => ev(undefined, 'x'.repeat(80), 'y'.repeat(80))),
      ...stamp() }));
    // Every field at its maximum (about 4,000 characters, a 499-character PDF link) fits the row cap (CodeRabbit on PR #38).
    const full = ['2026-11-05', '2026-11-06', '18:30', '21:30', ...Array(6).fill('x'.repeat(300)), 'n'.repeat(500), 'n'.repeat(500),
      'https://fb.com/' + 'p'.repeat(485), 'https://' + 'h'.repeat(100) + '.' + 'c'.repeat(100) + '/' + 'p'.repeat(289), 'a'.repeat(80), 'b'.repeat(80)].join(S);
    await assertSucceeds(updateDoc(ref(), { dayEvents: [full], ...stamp() }));
    for (const bad of [
      [ev('http://drive.google.com/x')], [ev('javascript:alert(1)')], [ev('/mass-schedule')], [ev(undefined, 'x'.repeat(81))],
      [ev() + S + 'extra'], [[...base, 'https://drive.google.com/x'].join(S)],
      // Whitespace inside the PDF link (the app would drop it) and a link longer than the editor's 500 characters.
      [ev('https://drive.google.com/a\tb')], [ev('https://drive.google.com/a\nb')], [ev('https://drive.google.com/' + 'p'.repeat(480))],
    ]) {
      await assertFails(updateDoc(ref(), { dayEvents: bad }), JSON.stringify(bad).slice(0, 80));
    }
  });
});

describe('ADR-047: English text for the fixed verse and the season verses', () => {
  const S = '\u001f';
  const ref = () => doc(db(EDITOR), 'settings', 'features');

  test('fixed verse: optional textEn / refEn, same limits as Arabic; old shape still valid', async () => {
    await assertSucceeds(setDoc(ref(), { dailyVerse: { mode: 'fixed', textAr: 'ع', refAr: 'يو 3: 16', textEn: 'For God so loved', refEn: 'John 3:16' } }));
    await assertSucceeds(setDoc(ref(), { dailyVerse: { mode: 'fixed', textAr: 'ع'.repeat(500), refAr: 'ي'.repeat(60),
      textEn: 'e'.repeat(500), refEn: 'r'.repeat(60) } }));
    await assertSucceeds(setDoc(ref(), { dailyVerse: { mode: 'fixed', textAr: 'ع', refAr: '' } }), 'no English keys');
    const ok = { mode: 'fixed', textAr: 'ع', refAr: '' };
    for (const v of [
      { ...ok, textEn: 'e'.repeat(501) }, { ...ok, refEn: 'r'.repeat(61) }, { ...ok, textEn: 5 }, { ...ok, refEn: null },
      { ...ok, textEn: 'a\u001fb' },
    ]) {
      await assertFails(setDoc(ref(), { dailyVerse: v }), JSON.stringify(v).slice(0, 80));
    }
  });

  test('season verses: rows with or without the ␟textEn␟refEn tail; 40 full rows fit', async () => {
    const row = (k, en = 'Behold, the Lamb of God', er = 'John 1:29') => [k, 'هوذا حمل الله', 'يو 1: 29', en, er].join(S);
    await assertSucceeds(setDoc(ref(), { seasonVerses: [row('holy_week'), ['pascha', 'المسيح قام', ''].join(S), row('pascha', '', '')] }));
    await assertSucceeds(updateDoc(ref(), { seasonVerses: Array.from({ length: 40 },
      () => ['summer', 'آ'.repeat(500), 'ر'.repeat(60), 'e'.repeat(500), 'r'.repeat(60)].join(S)) }));
    for (const bad of [
      [row('holy_week', 'e'.repeat(501))], [row('holy_week', 'x', 'r'.repeat(61))], [row('holy_week') + S + 'x'],
      [['holy_week', 'آية', '', 'only English text'].join(S)],
    ]) {
      await assertFails(updateDoc(ref(), { seasonVerses: bad }), JSON.stringify(bad).slice(0, 60));
    }
  });
});
