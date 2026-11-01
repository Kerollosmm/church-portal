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
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { image: { source: 'inline', mediaId: 'm1' } }));
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
