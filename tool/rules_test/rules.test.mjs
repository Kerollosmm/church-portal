// Firestore security-rules tests. Run inside the emulator:
//   cd tool/rules_test && npm ci && npm test
// (needs Java 11+ for the Firestore emulator).
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { after, before, beforeEach, describe, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  Timestamp, deleteDoc, doc, getDoc, getDocs, collection, increment, serverTimestamp, setDoc, updateDoc, writeBatch,
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

const sampleClinic = {
  specialty: 'dental', specialtyAr: 'الأسنان', specialtyEn: 'Dental',
  doctorName: 'طبيب الأسنان — يُعلن لاحقًا', degreeAr: '', degreeEn: '',
  days: [1, 3, 6], start: '16:00', end: '20:00', bookingPhone: '', whatsapp: '', active: true, sample: true,
};

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, 'admins', OWNER), { email: 'owner@x.test', role: 'owner' });
    await setDoc(doc(f, 'admins', EDITOR), { email: 'editor@x.test', role: 'editor' });
    await setDoc(doc(f, 'settings', 'church'), convert(seed.settings.church));
    await setDoc(doc(f, 'clinics', 'c1'), convert(sampleClinic));
    await setDoc(doc(f, 'clinics', 'legacy'), { ...convert(sampleClinic), legacyField: 'x' });
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
    const own = db(OWNER);
    for (const [col, docs] of Object.entries(seed)) {
      for (const [id, data] of Object.entries(docs)) {
        // settings only accepts its known ids, so those are written in place.
        const target = col === 'settings' ? id : `seedcheck-${id}`;
        const writer = (col === 'settings' && id === 'features') ? own : ed;
        try {
          await assertSucceeds(setDoc(doc(writer, col, target), convert(data)));
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

  test('soft delete with deletedAt: Timestamp allowed, undo with null allowed, bad type and non-admin denied', async () => {
    const ed = db(EDITOR);
    const pub = db(null);
    const stranger = db(STRANGER);
    const ref = doc(ed, 'clinics', 'c1');

    // 1. Soft-delete by setting deletedAt to a valid Timestamp succeeds
    await assertSucceeds(updateDoc(ref, { deletedAt: serverTimestamp() }));

    // 2. Undo soft-delete by clearing deletedAt to null succeeds
    await assertSucceeds(updateDoc(ref, { deletedAt: null }));

    // 3. Bad type for deletedAt (e.g. string or number) fails
    await assertFails(updateDoc(ref, { deletedAt: '2026-11-14' }));
    await assertFails(updateDoc(ref, { deletedAt: 12345678 }));

    // 4. Non-admin / visitor cannot write or clear deletedAt
    await assertFails(updateDoc(doc(pub, 'clinics', 'c1'), { deletedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(stranger, 'clinics', 'c1'), { deletedAt: serverTimestamp() }));

    // 5. Worst-case whole-doc rules budget check: whole document update with deletedAt
    const fullClinic = convert(sampleClinic);
    await assertSucceeds(setDoc(ref, { ...fullClinic, deletedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(ref, { ...fullClinic, deletedAt: null }));
  });

  test('owner can soft-delete, restore, and hard-delete a priest', async () => {
    const own = db(OWNER);
    const ref = doc(own, 'priests', 'p-owner-del');
    const stamp = { updatedAt: serverTimestamp(), updatedBy: `${OWNER}@x.test` };

    await assertSucceeds(setDoc(ref, { ...convert(seed.priests.bemwa), ...stamp }));
    await assertSucceeds(updateDoc(ref, { deletedAt: Timestamp.now(), ...stamp }));
    await assertSucceeds(updateDoc(ref, { deletedAt: null, ...stamp }));
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

describe('P1-12: admin active / expiresAt access control', () => {
  const futureTs = () => Timestamp.fromMillis(Date.now() + 86_400_000);
  const pastTs = () => Timestamp.fromMillis(Date.now() - 86_400_000);
  const setAdmin = (uid, data) => env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'admins', uid), data);
  });

  test('stopped editor (active: false) reads own admin doc, cannot write content or read contact_messages', async () => {
    await setAdmin(EDITOR, { email: 'editor@x.test', role: 'editor', active: false });
    const ed = db(EDITOR);
    await assertSucceeds(getDoc(doc(ed, 'admins', EDITOR)));
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { visible: false }));
    await assertFails(setDoc(doc(ed, 'clinics', 'new1'), {
      specialty: 'dental', specialtyAr: 'الأسنان', doctorName: 'د. مينا',
    }));
    await assertFails(deleteDoc(doc(ed, 'clinics', 'c1')));
    await assertFails(getDoc(doc(ed, 'contact_messages', 'm1')));
    await assertFails(getDocs(collection(ed, 'contact_messages')));
    await assertFails(updateDoc(doc(ed, 'contact_messages', 'm1'), { status: 'handled' }));
  });

  test('expired editor (expiresAt in the past) reads own admin doc, cannot write content or read contact_messages', async () => {
    await setAdmin(EDITOR, { email: 'editor@x.test', role: 'editor', active: true, expiresAt: pastTs() });
    const ed = db(EDITOR);
    await assertSucceeds(getDoc(doc(ed, 'admins', EDITOR)));
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { visible: false }));
    await assertFails(getDoc(doc(ed, 'contact_messages', 'm1')));
    await assertFails(getDocs(collection(ed, 'contact_messages')));
  });

  test('active editor with future expiresAt or expiresAt: null can write content and read contact_messages', async () => {
    await setAdmin(EDITOR, { email: 'editor@x.test', role: 'editor', active: true, expiresAt: futureTs() });
    const ed = db(EDITOR);
    await assertSucceeds(updateDoc(doc(ed, 'clinics', 'c1'), { visible: false }));
    await assertSucceeds(getDoc(doc(ed, 'contact_messages', 'm1')));
    await assertSucceeds(getDocs(collection(ed, 'contact_messages')));

    await setAdmin(EDITOR, { email: 'editor@x.test', role: 'editor', active: true, expiresAt: null });
    await assertSucceeds(updateDoc(doc(ed, 'clinics', 'c1'), { visible: true }));
    await assertSucceeds(getDocs(collection(ed, 'contact_messages')));
  });

  test('re-enabling (active: true, expiresAt: null) restores editor access', async () => {
    await setAdmin(EDITOR, { email: 'editor@x.test', role: 'editor', active: false, expiresAt: pastTs() });
    const ed = db(EDITOR);
    const own = db(OWNER);
    await assertFails(updateDoc(doc(ed, 'clinics', 'c1'), { visible: false }));

    await assertSucceeds(updateDoc(doc(own, 'admins', EDITOR), {
      active: true, expiresAt: null, updatedAt: serverTimestamp(), updatedBy: `${OWNER}@x.test`,
    }));
    await assertSucceeds(updateDoc(doc(ed, 'clinics', 'c1'), { visible: false }));
    await assertSucceeds(getDocs(collection(ed, 'contact_messages')));
  });

  test('stopped or expired owner cannot write settings/features or manage other admins', async () => {
    const own = db(OWNER);

    await setAdmin(OWNER, { email: 'owner@x.test', role: 'owner', active: false });
    await assertSucceeds(getDoc(doc(own, 'admins', OWNER)));
    await assertFails(getDocs(collection(own, 'admins')));
    await assertFails(setDoc(doc(own, 'settings', 'features'), { theme: 'navy' }));
    await assertFails(setDoc(doc(own, 'admins', 'new-uid'), { email: 'n@x.test', role: 'editor' }));
    await assertFails(updateDoc(doc(own, 'admins', EDITOR), { active: false }));
    await assertFails(deleteDoc(doc(own, 'admins', EDITOR)));

    await setAdmin(OWNER, { email: 'owner@x.test', role: 'owner', active: true, expiresAt: pastTs() });
    await assertSucceeds(getDoc(doc(own, 'admins', OWNER)));
    await assertFails(getDocs(collection(own, 'admins')));
    await assertFails(setDoc(doc(own, 'settings', 'features'), { theme: 'navy' }));
    await assertFails(setDoc(doc(own, 'admins', 'new-uid'), { email: 'n@x.test', role: 'editor' }));
    await assertFails(updateDoc(doc(own, 'admins', EDITOR), { active: false }));
    await assertFails(deleteDoc(doc(own, 'admins', EDITOR)));
  });

  test('editor cannot change active or expiresAt on any admin doc', async () => {
    const ed = db(EDITOR);
    await assertFails(updateDoc(doc(ed, 'admins', EDITOR), { active: false }));
    await assertFails(updateDoc(doc(ed, 'admins', EDITOR), { expiresAt: futureTs() }));
    await assertFails(setDoc(doc(ed, 'admins', EDITOR), { email: 'editor@x.test', role: 'editor', active: false }));
    await assertFails(updateDoc(doc(ed, 'admins', OWNER), { active: false }));
    await assertFails(setDoc(doc(ed, 'admins', 'other-uid'), {
      email: 'other@x.test', role: 'editor', active: true, expiresAt: null,
    }));
  });

  test('owner cannot set active: false or expiresAt on their own admins/OWNER doc', async () => {
    const own = db(OWNER);
    await assertFails(updateDoc(doc(own, 'admins', OWNER), { active: false }));
    await assertFails(updateDoc(doc(own, 'admins', OWNER), { active: true }));
    await assertFails(updateDoc(doc(own, 'admins', OWNER), { expiresAt: futureTs() }));
    await assertFails(updateDoc(doc(own, 'admins', OWNER), { expiresAt: null }));
    await assertFails(setDoc(doc(own, 'admins', OWNER), {
      email: 'owner@x.test', role: 'owner', active: false, expiresAt: pastTs(),
    }));
  });

  test('owner can set/update active and expiresAt on other admin docs; invalid types fail', async () => {
    const own = db(OWNER);
    const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${OWNER}@x.test` });

    // Create with active + timestamp expiresAt
    await assertSucceeds(setDoc(doc(own, 'admins', 'temp-ed'), {
      email: 'temp@x.test', role: 'editor', active: true, expiresAt: futureTs(), ...stamp(),
    }));
    // Update to paused (active: false) and clear expiresAt to null
    await assertSucceeds(updateDoc(doc(own, 'admins', 'temp-ed'), {
      active: false, expiresAt: null, ...stamp(),
    }));
    // Update existing editor doc with future expiresAt
    await assertSucceeds(updateDoc(doc(own, 'admins', EDITOR), {
      active: true, expiresAt: futureTs(), ...stamp(),
    }));

    // Invalid types fail
    await assertFails(setDoc(doc(own, 'admins', 'bad1'), {
      email: 'b1@x.test', role: 'editor', active: 'yes',
    }));
    await assertFails(setDoc(doc(own, 'admins', 'bad2'), {
      email: 'b2@x.test', role: 'editor', active: null,
    }));
    await assertFails(setDoc(doc(own, 'admins', 'bad3'), {
      email: 'b3@x.test', role: 'editor', expiresAt: '2030-01-01',
    }));
    await assertFails(updateDoc(doc(own, 'admins', EDITOR), { expiresAt: 123456789 }));
  });

  test('owners cannot have a non-null expiresAt; clearing legacy expiresAt or promoting with null is allowed', async () => {
    const own = db(OWNER);
    const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${OWNER}@x.test` });

    // Creating another owner with a non-null expiresAt is denied
    await assertFails(setDoc(doc(own, 'admins', 'other-owner'), {
      email: 'o2@x.test', role: 'owner', active: true, expiresAt: futureTs(), ...stamp(),
    }));
    // Creating another owner without expiresAt or with expiresAt: null is allowed
    await assertSucceeds(setDoc(doc(own, 'admins', 'other-owner'), {
      email: 'o2@x.test', role: 'owner', active: true, expiresAt: null, ...stamp(),
    }));
    // Updating another owner to set a non-null expiresAt is denied
    await assertFails(updateDoc(doc(own, 'admins', 'other-owner'), {
      expiresAt: futureTs(), ...stamp(),
    }));

    // Clearing a legacy expiresAt on an existing owner (expiresAt: null) is allowed
    await setAdmin('legacy-owner', {
      email: 'legacy@x.test', role: 'owner', active: true, expiresAt: futureTs(),
    });
    await assertSucceeds(updateDoc(doc(own, 'admins', 'legacy-owner'), {
      expiresAt: null, ...stamp(),
    }));

    // Promoting an editor who has expiresAt to owner without clearing expiresAt is denied
    await setAdmin('exp-editor', {
      email: 'exped@x.test', role: 'editor', active: true, expiresAt: futureTs(),
    });
    await assertFails(updateDoc(doc(own, 'admins', 'exp-editor'), {
      role: 'owner', ...stamp(),
    }));
    // Promoting that editor to owner while clearing expiresAt to null is allowed
    await assertSucceeds(updateDoc(doc(own, 'admins', 'exp-editor'), {
      role: 'owner', expiresAt: null, ...stamp(),
    }));
  });

  test('worst-case whole-document rules budget: active editor with future expiresAt saves full settings/features and saints', async () => {
    await setAdmin(EDITOR, { email: 'editor@x.test', role: 'editor', active: true, expiresAt: futureTs() });
    const ed = db(EDITOR);
    const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` });
    const featRef = doc(ed, 'settings', 'features');

    // 1. Full seeded settings/features create (contains owner-only errorReporting)
    await assertSucceeds(setDoc(doc(db(OWNER), 'settings', 'features'), {
      ...convert(seed.settings.features),
      updatedAt: serverTimestamp(),
      updatedBy: `${OWNER}@x.test`,
    }));

    // 2. Full legacy/toggle/today/live/dailyVerse/imageStyles/footer save
    await assertSucceeds(setDoc(featRef, {
      ...convert(seed.settings.features),
      heroTitleAr: 'أهلًا بكم',
      heroTitleEn: 'Welcome',
      heroSubtitleAr: 'كنيسة القديسين',
      heroSubtitleEn: 'Saints Church',
      bannerEnabled: true,
      bannerAr: 'إعلان',
      bannerEn: 'Notice',
      bannerLink: '/clinics',
      heroMotion: true,
      heroSeasonTint: true,
      heroShowAddress: false,
      aboutMilestones: true,
      copticStrip: 'all',
      dayStartMode: 'fixed',
      dayStartsAt: '05:00',
      topEvent: true,
      commemoration: true,
      topEventServices: true,
      liveEnabled: true,
      liveUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      liveLabelAr: 'بث مباشر للقداس',
      liveLabelEn: 'Live Liturgy',
      liveEndsAt: futureTs(),
      liveBadgeHideOnHome: false,
      weddingBookingOff: false,
      dailyVerse: { mode: 'daily', textAr: 'الرب نوري', refAr: 'مز ٢٧: ١', textEn: 'The Lord is my light', refEn: 'Ps 27:1' },
      imageStyles: { priests: 'avatar', saints: 'card', activities: 'banner' },
      ...stamp(),
    }));

    // 3. Full App & Push save (ADR-057/059) merged onto that stored full settings/features doc:
    //    first as EDITOR (without owner-only installAndroidUrl/installAndroidUrl32/pushVapidKey),
    //    then as OWNER with all owner-only install/push keys included.
    const editorAppPush = {
      installPrompt: true,
      installTitleAr: 'تطبيق الكنيسة',
      installTitleEn: 'Church App',
      installBodyAr: 'تابع القداسات والمواسم',
      installBodyEn: 'Follow liturgies and seasons',
      installApkVersion: '1.2.0',
      installApkBuild: 45,
      installApkSizeMb: 18.5,
      installApkSize32Mb: 17.2,
      installReshowDays: 30,
      installRemindDays: 3,
      push: true,
      pushTypes: ['announcements', 'verse_daily', 'katameros_daily', 'seasons', 'feasts', 'reminders'],
      reminderLeads: [0, 15, 60, 1440],
      reminderDefaultLead: 60,
      notifyTypes: [
        ['verse_daily', '07:00', '', 'آية اليوم', 'Verse of the Day', '{verse}', '{verse}'].join('\u001f'),
        ['seasons', '07:00', '3', 'المواسم', 'Seasons', '{season}', '{season}'].join('\u001f'),
      ],
      reminderSources: 'lit,mtg,day',
    };
    await assertSucceeds(setDoc(featRef, { ...editorAppPush, ...stamp() }, { merge: true }));
    await assertSucceeds(setDoc(doc(db(OWNER), 'settings', 'features'), {
      ...editorAppPush,
      installAndroidUrl: 'https://example.org/app.apk',
      installAndroidUrl32: '/app/older.apk',
      pushVapidKey: 'B'.repeat(88),
      updatedAt: serverTimestamp(),
      updatedBy: `${OWNER}@x.test`,
    }, { merge: true }));

    // Full saints document save (max lengths + split gallery & extraFields updates)
    const img = (i) => ({ source: 'inline', mediaId: `m${i}`, alt: 'a'.repeat(300), w: 800, h: 600 });
    const field = (i) => ({ titleAr: 'ع'.repeat(150), titleEn: 't'.repeat(150), valueAr: 'ق'.repeat(2000), valueEn: `${i}`.repeat(2000).slice(0, 2000) });
    const fullSaintScalars = {
      nameAr: 'الأنبا موسى الأسود',
      nameEn: 'St. Moses the Black',
      bioAr: 'س'.repeat(5000),
      bioEn: 'b'.repeat(5000),
      feastCopticAr: '٢٤ بؤونة',
      feastCopticEn: '24 Paona',
      feastGregorianAr: '١ يوليو',
      feastGregorian: '1 July',
      detailsEnabled: true,
      showDetailImages: true,
      showContacts: true,
      showSocials: true,
      detailsAr: 'ت'.repeat(10000),
      detailsEn: 'd'.repeat(10000),
      image: { source: 'url', url: 'https://img.example.org/cover.jpg', alt: 'cover', w: 800, h: 600 },
      contactPhone: '01012345678',
      whatsapp: '01012345678',
      whatsappUrl: 'https://whatsapp.com/channel/x',
      facebookUrl: 'https://facebook.com/x',
      youtubeUrl: 'https://youtube.com/@x',
      instagramUrl: 'https://instagram.com/x',
      externalUrl: 'https://forms.example.org/register',
      externalLabelAr: 'ن'.repeat(80),
      externalLabelEn: 'Register',
      contactNoteAr: 'م'.repeat(500),
      contactNoteEn: 'Call us',
      visible: true,
      sample: false,
      order: 1,
      gallery: [],
      extraFields: [],
      ...stamp(),
    };
    const saintRef = doc(ed, 'saints', 'worst-case-saint');
    await assertSucceeds(setDoc(saintRef, fullSaintScalars));
    await assertSucceeds(updateDoc(saintRef, { gallery: Array.from({ length: 8 }, (_, i) => img(i)), ...stamp() }));
    await assertSucceeds(updateDoc(saintRef, { extraFields: Array.from({ length: 15 }, (_, i) => field(i)), ...stamp() }));
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

describe('ADR-052: milestones on the About page (settings/features.aboutMilestones)', () => {
  test('admins switch it off and on; only a bool is accepted', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', aboutMilestones: false }));
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', aboutMilestones: true }));
    for (const v of ['off', 0, null, { on: false }]) {
      await assertFails(setDoc(ref, { aboutMilestones: v }), JSON.stringify(v));
    }
  });

  test('an untouched stored value does not block other edits', async () => {
    const ref = doc(db(EDITOR), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', aboutMilestones: false }));
    await assertSucceeds(setDoc(ref, { theme: 'goldenHour', aboutMilestones: false }));
  });

  test('visitors cannot change it', async () => {
    await assertFails(setDoc(doc(db(null), 'settings', 'features'), { aboutMilestones: false }));
  });
});

describe('ADR-034: error reporting switch (settings/features.errorReporting)', () => {
  test('owners switch error reports on and off; only a bool is accepted; editors are denied', async () => {
    const ref = doc(db(OWNER), 'settings', 'features');
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', errorReporting: false }));
    await assertSucceeds(setDoc(ref, { theme: 'burgundy', errorReporting: true }));
    await assertSucceeds(updateDoc(ref, { errorReporting: false }));
    for (const v of ['off', 0, null, { on: true }, [true]]) {
      await assertFails(setDoc(ref, { errorReporting: v }), JSON.stringify(v));
    }
    await assertFails(setDoc(doc(db(EDITOR), 'settings', 'features'), { errorReporting: true }));
    await assertFails(updateDoc(doc(db(EDITOR), 'settings', 'features'), { errorReporting: true }));
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

  test('categories: DocEditor + AdminRepository exact create payload, variants, admin roles, edit and soft-delete', async () => {
    const editorCreatePayload = (uid, overrides = {}) => ({
      nameAr: 'رحلات الشباب',
      introAr: '',
      icon: 'star',
      showInNav: true,
      visible: true,
      slug: 'rhlat-alshbab',
      nameEn: '',
      introEn: '',
      order: null,
      updatedAt: serverTimestamp(),
      updatedBy: `${uid}@x.test`,
      ...overrides,
    });

    // 1. Exact new-category create payload from DocEditor.save() + AdminRepository.save()
    //    (auto-generated doc id, imageStyle stripped on !_persisted, order: null).
    const ed = db(EDITOR);
    const createdRef = doc(collection(ed, 'categories'));
    await assertSucceeds(setDoc(createdRef, editorCreatePayload(EDITOR)));

    // 2. Variants: englishEnabled: false (empty '' or omitted optional keys), imageStyle: null / valid values,
    //    integer order (including bounds), multiline intros (up to 1500 chars), showInNav/visible: false.
    await assertSucceeds(setDoc(doc(collection(ed, 'categories')), editorCreatePayload(EDITOR, {
      slug: 'cat-img-null', imageStyle: null, order: 10, showInNav: false, visible: false,
    })));
    await assertSucceeds(setDoc(doc(collection(ed, 'categories')), editorCreatePayload(EDITOR, {
      slug: 'cat-multiline',
      introAr: 'السطر الأول\nالسطر الثاني\n' + 'أ'.repeat(1470),
      introEn: 'Line 1\nLine 2\n' + 'e'.repeat(1480),
      nameAr: 'أ'.repeat(120),
      nameEn: 'e'.repeat(120),
      imageStyle: 'card',
      order: -100000,
    })));
    await assertSucceeds(setDoc(doc(collection(ed, 'categories')), {
      nameAr: 'قسم مختصر',
      slug: 's'.repeat(60),
      visible: true,
      order: 100000,
      updatedAt: serverTimestamp(),
      updatedBy: `${EDITOR}@x.test`,
    }));

    // All 12 CategoryIcons are accepted.
    for (const icon of ['star', 'church', 'people', 'heart', 'book', 'music', 'medical', 'school', 'event', 'volunteer', 'donate', 'info']) {
      await assertSucceeds(setDoc(doc(ed, 'categories', `icon-${icon}`), editorCreatePayload(EDITOR, {
        slug: `cat-${icon}`, icon,
      })), icon);
    }

    // Invalid order bounds/types and mismatched updatedBy fail.
    await assertFails(setDoc(doc(ed, 'categories', 'bad-order-hi'), editorCreatePayload(EDITOR, { order: 100001 })));
    await assertFails(setDoc(doc(ed, 'categories', 'bad-order-str'), editorCreatePayload(EDITOR, { order: '10' })));
    await assertFails(setDoc(doc(ed, 'categories', 'bad-stamp'), editorCreatePayload(EDITOR, { updatedBy: 'wrong@x.test' })));

    // 3. Editor vs Owner with explicit active: true / missing active, and token without email (uid fallback).
    const own = db(OWNER);
    await assertSucceeds(setDoc(doc(collection(own, 'categories')), editorCreatePayload(OWNER, { slug: 'owner-missing-active' })));

    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, 'admins', EDITOR), { email: 'editor@x.test', role: 'editor', active: true, expiresAt: null });
      await setDoc(doc(f, 'admins', OWNER), { email: 'owner@x.test', role: 'owner', active: true });
      await setDoc(doc(f, 'admins', 'uid-only-admin'), { email: 'uid-only@x.test', role: 'editor', active: true });
    });
    await assertSucceeds(setDoc(doc(collection(ed, 'categories')), editorCreatePayload(EDITOR, { slug: 'editor-active-true' })));
    await assertSucceeds(setDoc(doc(collection(own, 'categories')), editorCreatePayload(OWNER, { slug: 'owner-active-true' })));

    const noEmailDb = env.authenticatedContext('uid-only-admin', {}).firestore();
    await assertSucceeds(setDoc(doc(collection(noEmailDb, 'categories')), {
      ...editorCreatePayload('uid-only-admin'),
      slug: 'uid-only-cat',
      updatedBy: 'uid-only-admin',
    }));

    // 4. Edit follow-up via mergeFields (as AdminRepository._merge sends), soft-delete, restore, and hard delete.
    await assertSucceeds(setDoc(createdRef, {
      introAr: 'سطر 1\nسطر 2',
      imageStyle: 'banner',
      order: 20,
      showInNav: false,
      visible: false,
      updatedAt: serverTimestamp(),
      updatedBy: `${EDITOR}@x.test`,
    }, { mergeFields: ['introAr', 'imageStyle', 'order', 'showInNav', 'visible', 'updatedAt', 'updatedBy'] }));
    await assertSucceeds(setDoc(createdRef, {
      deletedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      updatedBy: `${EDITOR}@x.test`,
    }, { mergeFields: ['deletedAt', 'updatedAt', 'updatedBy'] }));
    await assertSucceeds(setDoc(createdRef, {
      deletedAt: null,
      updatedAt: serverTimestamp(),
      updatedBy: `${EDITOR}@x.test`,
    }, { mergeFields: ['deletedAt', 'updatedAt', 'updatedBy'] }));
    await assertSucceeds(deleteDoc(createdRef));
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

  test('P1-18: pages placement, categoryId, featured validation and worst-case 20-blocks budget', async () => {
    const ed = db(EDITOR);
    const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` });

    // Valid placements and featured flags on create
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-link'), page({ placement: 'link', categoryId: '', featured: false })));
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-nav'), page({ slug: 'nav-page', placement: 'nav', showInNav: true, featured: true })));
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-sec'), page({
      slug: 'sec-page', placement: 'section', categoryId: 'youth_1-cat', featured: true,
    })));

    // Backward compatibility: legacy doc without placement/categoryId/featured, then partial updates
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-legacy'), page({ slug: 'legacy-page' })));
    await assertSucceeds(updateDoc(doc(ed, 'pages', 'p-legacy'), {
      placement: 'section', categoryId: 'k1', showInNav: false, featured: true, ...stamp(),
    }));
    await assertSucceeds(updateDoc(doc(ed, 'pages', 'p-legacy'), {
      placement: 'nav', categoryId: '', showInNav: true, featured: false, ...stamp(),
    }));
    await assertSucceeds(updateDoc(doc(ed, 'pages', 'p-legacy'), {
      blocks: [block({ textAr: 'تحديث' })], ...stamp(),
    }));

    // Worst-case 20-blocks create and update with placement, categoryId, featured, and stamps
    const types = ['heading', 'paragraph', 'image', 'button', 'link', 'donation'];
    const full = Array.from({ length: 20 }, (_, i) => block({
      type: types[i % 6],
      textAr: 'ن'.repeat(4000),
      textEn: 'e'.repeat(4000),
      url: types[i % 6] === 'image' ? 'https://example.org/' + 'p'.repeat(470) : (i % 2 ? '/page/x' : 'https://example.org/give'),
      account: 'a'.repeat(120), instapay: 'i'.repeat(80), wallet: '0'.repeat(30),
    }));
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-big-sec'), page({
      slug: 'big-sec', placement: 'section', categoryId: 'cat-1', featured: true, blocks: full, ...stamp(),
    })));
    await assertSucceeds(updateDoc(doc(ed, 'pages', 'p-big-sec'), { blocks: full, ...stamp() }));

    // Reject invalid placement, categoryId, and featured on create
    for (const bad of [
      { placement: 'home' },
      { placement: '' },
      { placement: null },
      { placement: 1 },
      { placement: 'section' },
      { placement: 'section', categoryId: '' },
      { placement: 'section', categoryId: 'a/b' },
      { placement: 'section', categoryId: null },
      { placement: 'section', categoryId: 'a'.repeat(129) },
      { placement: 'link', categoryId: 'a/b' },
      { categoryId: 'a b' },
      { categoryId: 123 },
      { featured: 1 },
      { featured: 'true' },
      { featured: null },
    ]) {
      await assertFails(setDoc(doc(ed, 'pages', 'p-bad'), page(bad)), JSON.stringify(bad));
    }

    // Reject invalid updates against stored state
    await assertFails(updateDoc(doc(ed, 'pages', 'p-link'), { placement: 'section' })); // missing categoryId
    await assertFails(updateDoc(doc(ed, 'pages', 'p-sec'), { categoryId: '' })); // clearing categoryId while section
    await assertFails(updateDoc(doc(ed, 'pages', 'p-link'), { placement: 'home' }));
    await assertFails(updateDoc(doc(ed, 'pages', 'p-link'), { featured: 1 }));
  });

  test('owner creates blank and donation-template custom pages, including categoryId: null with placement: link', async () => {
    const own = db(OWNER);
    const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${OWNER}@x.test` });

    // 1. Blank custom page (placement: 'link', categoryId: '', featured: false)
    await assertSucceeds(setDoc(doc(own, 'pages', 'p-blank'), {
      slug: 'blank-guide',
      titleAr: 'دليل الزائر',
      titleEn: '',
      subtitleAr: '',
      subtitleEn: '',
      placement: 'link',
      categoryId: '',
      showInNav: false,
      featured: false,
      visible: true,
      order: 10,
      ...stamp(),
    }));

    // 2. categoryId: null (emitted by DocEditor nullableChoice) with placement: 'link' succeeds;
    //    categoryId: null with placement: 'section' remains rejected.
    await assertSucceeds(setDoc(doc(own, 'pages', 'p-null-cat'), {
      slug: 'null-cat-link',
      titleAr: 'صفحة عامة',
      titleEn: '',
      subtitleAr: '',
      subtitleEn: '',
      placement: 'link',
      categoryId: null,
      showInNav: false,
      featured: false,
      visible: true,
      order: 20,
      ...stamp(),
    }));
    await assertFails(updateDoc(doc(own, 'pages', 'p-null-cat'), { placement: 'section', ...stamp() }));

    // 3. Donation-template page: DocEditor splitSavePayload sends base write (with categoryId: null)
    //    followed by a separate blocks chunk write via mergeFields.
    const donationRef = doc(own, 'pages', 'p-donation');
    await assertSucceeds(setDoc(donationRef, {
      slug: 'new-building-donations',
      titleAr: 'التبرعات والمساهمات',
      titleEn: 'Donations & contributions',
      subtitleAr: '',
      subtitleEn: '',
      placement: 'link',
      categoryId: null,
      showInNav: false,
      featured: false,
      visible: true,
      order: 0,
      ...stamp(),
    }));
    await assertSucceeds(setDoc(donationRef, {
      blocks: [
        block({
          type: 'paragraph',
          textAr: 'بيانات المساهمة والتبرع (للعرض فقط — لا يتم أي دفع عبر الموقع).',
          textEn: 'Donation and contribution details (display only — no payment is processed on this site).',
        }),
        block({ type: 'donation' }),
      ],
      ...stamp(),
    }, { mergeFields: ['blocks', 'updatedAt', 'updatedBy'] }));

    // 4. Phase 4 PR2: linking custom pages to built-in sections (builtin_activities, builtin_meetings)
    //    succeeds on create/update and public read, while placement: 'section' with '' or null fails.
    await assertSucceeds(setDoc(doc(own, 'pages', 'p-builtin-act'), {
      slug: 'choir-details',
      titleAr: 'تفاصيل الكورال',
      titleEn: 'Choir details',
      subtitleAr: '',
      subtitleEn: '',
      placement: 'section',
      categoryId: 'builtin_activities',
      showInNav: false,
      featured: false,
      visible: true,
      order: 10,
      ...stamp(),
    }));
    await assertSucceeds(updateDoc(doc(own, 'pages', 'p-builtin-act'), {
      categoryId: 'builtin_meetings',
      ...stamp(),
    }));
    await assertSucceeds(getDoc(doc(db(null), 'pages', 'p-builtin-act')));
    await assertFails(updateDoc(doc(own, 'pages', 'p-builtin-act'), { categoryId: '', ...stamp() }));
    await assertFails(updateDoc(doc(own, 'pages', 'p-builtin-act'), { categoryId: null, ...stamp() }));
  });

  test('pages: list blocks allow valid bullet/numbered/bilingual/20x200x20 worst-case and reject malformed ones', async () => {
    const ed = db(EDITOR);
    const listBlock = (extra = {}) => block({
      type: 'list',
      textAr: 'تجربة ١',
      textEn: '',
      url: '',
      account: 'bullet',
      instapay: '',
      wallet: '',
      ...extra,
    });

    // Allow: single-item bullet list with empty textEn and account: '' or 'bullet'
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-list-min'), page({
      slug: 'list-min',
      blocks: [
        listBlock({ account: '' }),
        listBlock({ account: 'bullet' }),
      ],
    })));

    // Allow: numbered list with multiple bilingual items and partial English
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-list-num'), page({
      slug: 'list-num',
      blocks: [
        listBlock({
          account: 'numbered',
          textAr: 'تجربة ١\u001eتجربة ٢\u001eتجربة ٣',
          textEn: 'Item 1\u001e\u001eItem 3',
        }),
      ],
    })));

    // Allow: boundary single block (20 AR items x 200 'أ' + 20 EN items x 200 'e')
    const maxAr = Array.from({ length: 20 }, () => 'أ'.repeat(200)).join('\u001e');
    const maxEn = Array.from({ length: 20 }, () => 'e'.repeat(200)).join('\u001e');
    const fullListBlock = listBlock({ textAr: maxAr, textEn: maxEn, account: 'numbered' });
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-list-max-one'), page({
      slug: 'list-max-one',
      blocks: [fullListBlock],
    })));

    // Allow: worst-case 20-block budget test (20 full list blocks in one write)
    const twentyFullListBlocks = Array.from({ length: 20 }, () => fullListBlock);
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-list-max-20'), page({
      slug: 'list-max-20',
      blocks: twentyFullListBlocks,
    })));
    await assertSucceeds(updateDoc(doc(ed, 'pages', 'p-list-max-20'), {
      blocks: twentyFullListBlocks,
    }));

    // Deny cases
    const twentyOneAr = Array.from({ length: 21 }, (_, i) => `تجربة ${i + 1}`).join('\u001e');
    const twentyOneEn = Array.from({ length: 21 }, (_, i) => `Item ${i + 1}`).join('\u001e');
    for (const [label, badBlock] of [
      ['0 items', 'list\u001f\u001f\u001f\u001fbullet\u001f\u001f'],
      ['whitespace-only first item', 'list\u001f   \u001f\u001f\u001fbullet\u001f\u001f'],
      ['whitespace-only second item', listBlock({ textAr: 'أ\u001e   ' })],
      ['21 AR items', listBlock({ textAr: twentyOneAr })],
      ['21 EN items', listBlock({ textAr: 'تجربة', textEn: twentyOneEn })],
      ['AR item > 200 chars', listBlock({ textAr: 'أ'.repeat(201) })],
      ['EN item > 200 chars', listBlock({ textAr: 'تجربة', textEn: 'e'.repeat(201) })],
      ['invalid style in account', listBlock({ account: 'roman' })],
      ['non-empty url', listBlock({ url: 'https://example.org' })],
      ['non-empty instapay', listBlock({ instapay: 'church@instapay' })],
      ['non-empty wallet', listBlock({ wallet: '01012345678' })],
      ['6 slots (too few)', 'list\u001fتجربة\u001f\u001f\u001fbullet\u001f'],
      ['8 slots (too many)', `${listBlock()}\u001fextra`],
      ['unknown type callout', block({ type: 'callout', textAr: 'تجربة' })],
      ['unknown type video', block({ type: 'video', textAr: 'تجربة' })],
    ]) {
      await assertFails(
        setDoc(doc(ed, 'pages', 'p-list-bad'), page({ slug: 'list-bad', blocks: [badBlock] })),
        label,
      );
    }
  });

  test('pages: details blocks allow valid AR/bilingual/intermediate/20x(200+3500)x2 worst-case and reject malformed ones', async () => {
    const ed = db(EDITOR);
    const detailsBlock = ({
      summaryAr = 'تجربة عنوان',
      bodyAr = 'تجربة تفاصيل',
      textAr = `${summaryAr}\u001e${bodyAr}`,
      textEn = '',
      url = '',
      account = '',
      instapay = '',
      wallet = '',
    } = {}) => block({
      type: 'details',
      textAr,
      textEn,
      url,
      account,
      instapay,
      wallet,
    });

    // Allow: minimal AR-only (textEn: '') + multiline bodyAr (newlines) + partial EN variants
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-details-min'), page({
      slug: 'details-min',
      blocks: [
        detailsBlock({ textEn: '' }),
        detailsBlock({ summaryAr: 'تفاصيل متعددة السطور', bodyAr: 'السطر الأول\nالسطر الثاني\nالسطر الثالث' }),
        detailsBlock({ textEn: 'Summary only\u001e' }),
        detailsBlock({ textEn: '\u001eBody only' }),
      ],
    })));

    // Allow: intermediate lengths (600, 1250, 2500 chars) proving zero RE2 500-char chunking gaps
    for (const len of [600, 1250, 2500]) {
      await assertSucceeds(setDoc(doc(ed, 'pages', `p-details-len-${len}`), page({
        slug: `details-len-${len}`,
        blocks: [
          detailsBlock({
            summaryAr: 'س'.repeat(100),
            bodyAr: 'ب'.repeat(len),
            textEn: `${'S'.repeat(100)}\u001e${'B'.repeat(len)}`,
          }),
        ],
      })));
    }

    // Allow: exact boundary single block (200 AR summary + 3500 AR body + 200 EN summary + 3500 EN body)
    const fullDetailsBlock = detailsBlock({
      summaryAr: 'أ'.repeat(200),
      bodyAr: 'ب'.repeat(3500),
      textEn: `${'S'.repeat(200)}\u001e${'E'.repeat(3500)}`,
    });
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-details-max-one'), page({
      slug: 'details-max-one',
      blocks: [fullDetailsBlock],
    })));

    // Allow: worst-case 20-block budget test (20 full AR+EN details blocks in one setDoc AND updateDoc)
    const twentyFullDetailsBlocks = Array.from({ length: 20 }, () => fullDetailsBlock);
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-details-max-20'), page({
      slug: 'details-max-20',
      blocks: twentyFullDetailsBlocks,
    })));
    await assertSucceeds(updateDoc(doc(ed, 'pages', 'p-details-max-20'), {
      blocks: twentyFullDetailsBlocks,
    }));

    // Verify 20 legacy blocks still pass under the 1,000-expression budget with the extra details branch
    const legacyTypes = ['heading', 'paragraph', 'image', 'button', 'link', 'donation'];
    const twentyLegacyBlocks = Array.from({ length: 20 }, (_, i) => block({
      type: legacyTypes[i % 6],
      textAr: 'ن'.repeat(4000),
      textEn: 'e'.repeat(4000),
      url: legacyTypes[i % 6] === 'image' ? 'https://example.org/' + 'p'.repeat(470) : 'https://example.org/give',
      account: 'a'.repeat(120),
      instapay: 'i'.repeat(80),
      wallet: '0'.repeat(30),
    }));
    await assertSucceeds(setDoc(doc(ed, 'pages', 'p-legacy-after-details'), page({
      slug: 'legacy-after-details',
      blocks: twentyLegacyBlocks,
    })));

    // Deny cases
    for (const [label, badBlock] of [
      ['empty summaryAr', detailsBlock({ textAr: '\u001eتفاصيل' })],
      ['whitespace-only summaryAr', detailsBlock({ textAr: '   \u001eتفاصيل' })],
      ['empty bodyAr', detailsBlock({ textAr: 'عنوان\u001e' })],
      ['whitespace-only bodyAr', detailsBlock({ textAr: 'عنوان\u001e   ' })],
      ['missing \\u001e in textAr', detailsBlock({ textAr: 'عنوان بدون فاصل' })],
      ['extra \\u001e in textAr', detailsBlock({ textAr: 'عنوان\u001eجزء ١\u001eجزء ٢' })],
      ['extra \\u001e in textEn', detailsBlock({ textEn: 'Summary\u001ePart 1\u001ePart 2' })],
      ['non-empty textEn missing \\u001e', detailsBlock({ textEn: 'SummaryOnlyEn' })],
      ['summaryAr > 200 chars', detailsBlock({ summaryAr: 'أ'.repeat(201) })],
      ['summaryEn > 200 chars', detailsBlock({ textEn: `${'S'.repeat(201)}\u001eBody` })],
      ['bodyAr > 3500 chars', detailsBlock({ bodyAr: 'ب'.repeat(3501) })],
      ['bodyEn > 3500 chars', detailsBlock({ textEn: `Summary\u001e${'E'.repeat(3501)}` })],
      ['non-empty url', detailsBlock({ url: 'https://example.org' })],
      ['non-empty account', detailsBlock({ account: 'bullet' })],
      ['non-empty instapay', detailsBlock({ instapay: 'church@instapay' })],
      ['non-empty wallet', detailsBlock({ wallet: '01012345678' })],
      ['6 slots (too few)', 'details\u001fعنوان\u001eتفاصيل\u001f\u001f\u001f\u001f'],
      ['8 slots (too many)', `${detailsBlock()}\u001fextra`],
    ]) {
      await assertFails(
        setDoc(doc(ed, 'pages', 'p-details-bad'), page({ slug: 'details-bad', blocks: [badBlock] })),
        label,
      );
    }
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
    await assertSucceeds(setDoc(doc(db(OWNER), 'settings', 'contact'), { categories: cats }));
    const pub = db(null);
    await assertSucceeds(send(pub, booking));
    await reset();
    await assertFails(send(pub, { ...anon, category: 'c4', kind: 'suggestion' }), 'c4 is switched off');
    await assertFails(send(pub, { ...general, category: 'c5' }), 'c5 does not exist');
    await assertSucceeds(send(pub, anon));
  });

  test('admins edit settings/contact; shapes are validated; 12 full categories fit in one write', async () => {
    const ref = doc(db(OWNER), 'settings', 'contact');
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

  test('admins soft-delete, restore (deletedAt: null), and hard-delete contact_messages; visitors denied', async () => {
    const ed = db(EDITOR);
    const pub = db(null);
    const stranger = db(STRANGER);
    const ref = doc(ed, 'contact_messages', 'm1');
    const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${EDITOR}@x.test` });

    // Soft-delete with Timestamp and restore with null (10-second Undo)
    await assertSucceeds(updateDoc(ref, { deletedAt: Timestamp.now(), ...stamp() }));
    await assertSucceeds(updateDoc(ref, { deletedAt: null, ...stamp() }));

    // Bad deletedAt type or modifying immutable message fields fails
    await assertFails(updateDoc(ref, { deletedAt: '2026-11-15', ...stamp() }));
    await assertFails(updateDoc(ref, { deletedAt: Timestamp.now(), message: 'tampered', ...stamp() }));

    // Public visitors and non-admins cannot read, soft-delete, restore, or hard-delete
    await assertFails(getDoc(doc(pub, 'contact_messages', 'm1')));
    await assertFails(updateDoc(doc(pub, 'contact_messages', 'm1'), { deletedAt: Timestamp.now() }));
    await assertFails(deleteDoc(doc(pub, 'contact_messages', 'm1')));
    await assertFails(updateDoc(doc(stranger, 'contact_messages', 'm1'), { deletedAt: Timestamp.now() }));
    await assertFails(deleteDoc(doc(stranger, 'contact_messages', 'm1')));

    // Admin hard-delete succeeds
    await assertSucceeds(deleteDoc(ref));
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
    const ref = doc(db(OWNER), 'settings', 'contact');
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
    const ref = doc(db(OWNER), 'settings', 'contact');
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
    const ref = doc(db(OWNER), 'settings', 'assistant');
    await assertSucceeds(setDoc(ref, full));
    await assertSucceeds(getDoc(doc(db(null), 'settings', 'assistant')));
    await assertSucceeds(setDoc(ref, { model: '', instructions: '', topics: '', maxChars: null, perMinute: null, perSession: null }));
    await assertSucceeds(setDoc(ref, { model: 'gemini-3.5-flash-lite', updatedAt: serverTimestamp(), updatedBy: `${OWNER}@x.test` }, { merge: true }));
    await assertSucceeds(updateDoc(ref, { maxChars: 50, perMinute: 1, perSession: 1 }));
  });

  test('model ids, lengths, number ranges and unknown keys are validated', async () => {
    const ref = doc(db(OWNER), 'settings', 'assistant');
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
    await assertSucceeds(setDoc(doc(db(OWNER), 'settings', 'assistant'), { model: '' }));
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
    const ref = doc(db(OWNER), 'settings', 'features');
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
    const ref = doc(db(OWNER), 'settings', 'features');
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
    const ref = doc(db(OWNER), 'settings', 'assistant');
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
      await assertSucceeds(setDoc(doc(db(OWNER), 'settings', 'features'), { seasonVerses: [[k, 'آية', ''].join('\u001f')] }), `${k} verse`);
      await assertSucceeds(setDoc(ref(), { seasonPreset: { ...preset, seasonKey: k } }, { merge: true }), `${k} preset`);
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
    const ownerRef = () => doc(db(OWNER), 'settings', 'features');
    const row = (k, en = 'Behold, the Lamb of God', er = 'John 1:29') => [k, 'هوذا حمل الله', 'يو 1: 29', en, er].join(S);
    await assertSucceeds(setDoc(ownerRef(), { seasonVerses: [row('holy_week'), ['pascha', 'المسيح قام', ''].join(S), row('pascha', '', '')] }));
    await assertSucceeds(updateDoc(ownerRef(), { seasonVerses: Array.from({ length: 40 },
      () => ['summer', 'آ'.repeat(500), 'ر'.repeat(60), 'e'.repeat(500), 'r'.repeat(60)].join(S)) }));
    for (const bad of [
      [row('holy_week', 'e'.repeat(501))], [row('holy_week', 'x', 'r'.repeat(61))], [row('holy_week') + S + 'x'],
      [['holy_week', 'آية', '', 'only English text'].join(S)],
    ]) {
      await assertFails(updateDoc(ownerRef(), { seasonVerses: bad }), JSON.stringify(bad).slice(0, 60));
    }
  });
});

// ---------------------------------------------------------------------------
// ADR-051: new season keys (apostles, nayrouz, kiahk, great_lent), a season's
// feast-night replace dates, and the assistant's exceptional-season list.
describe('ADR-051: season keys, replaceDates, exceptional seasons', () => {
  const NEW = ['apostles', 'nayrouz', 'kiahk', 'great_lent'];
  const features = () => doc(db(EDITOR), 'settings', 'features');
  const start = Timestamp.fromDate(new Date('Mon 2027-06-21 12:00 AM EEST (UTC+03:00)'));
  const end = Timestamp.fromDate(new Date('Sun 2027-07-11 11:59 PM EEST (UTC+03:00)'));
  const preset = (k) => ({
    seasonId: 'ap', seasonKey: k, appliedAt: start, startsAt: start, endsAt: end,
    options: ['weddingOff', 'live'], previous: { seasonActive: false, weddingBookingOff: false, liveUrl: '', liveEndsAt: null },
  });

  test('the new keys on seasons, services, verses, theme map and preset; fast still works', async () => {
    const ed = db(EDITOR);
    for (const k of [...NEW, 'fast']) {
      await assertSucceeds(setDoc(doc(ed, 'seasons', k), { key: k, nameAr: 'موسم', active: true }), k);
      await assertSucceeds(setDoc(doc(ed, 'liturgies', `l-${k}`), { type: 'mass', nameAr: 'قداس', start: '07:00', seasonKey: k }), `${k} liturgy`);
      await assertSucceeds(setDoc(doc(db(OWNER), 'settings', 'features'), { seasonVerses: [[k, 'آية', ''].join('\u001f')] }), `${k} verse`);
      await assertSucceeds(setDoc(features(), { seasonPreset: preset(k) }, { merge: true }), `${k} preset`);
    }
    for (const bad of ['cross', 'lent', 'Apostles', 'great-lent']) {
      await assertFails(setDoc(doc(ed, 'seasons', 'x'), { key: bad, nameAr: 'موسم' }), bad);
      await assertFails(setDoc(doc(ed, 'liturgies', 'x'), { type: 'mass', nameAr: 'قداس', start: '07:00', seasonKey: bad }), bad);
    }
  });

  test('a full 13-key season theme map plus 12 schedule slots fit one write (expression budget)', async () => {
    await assertSucceeds(setDoc(features(), {
      theme: 'goldenHour',
      occasions: {
        auto: true, easter: true, resurrectionDays: 50, followSeason: true,
        schedule: Object.fromEntries(Array.from({ length: 12 }, (_, i) => [`r${i + 1}`, 'nativity|2026-12-25|2027-01-08'])),
        seasonThemes: { holy_week: 'holyWeek', pascha: 'resurrection', fast: 'fasting', marian: 'marian',
          epiphany: 'epiphany', nativity: 'nativity', revival_maximus: 'brown', revival_moses: 'none', summer: 'none',
          apostles: 'fasting', nayrouz: 'resurrection', kiahk: 'marian', great_lent: 'fasting' },
      },
    }));
    await assertFails(setDoc(features(), { occasions: { seasonThemes: { cross: 'resurrection' } } }));
    await assertFails(setDoc(features(), { occasions: { seasonThemes: { kiahk: 'violet' } } }));
  });

  test('replaceDates: up to 10 distinct YYYY-MM-DD strings', async () => {
    const ref = doc(db(EDITOR), 'seasons', 'ap');
    await assertSucceeds(setDoc(ref, { key: 'apostles', nameAr: 'صوم الرسل', replacesRegular: false, replaceDates: ['2027-07-12'] }));
    await assertSucceeds(updateDoc(ref, { replaceDates: Array.from({ length: 10 }, (_, i) => `2027-07-${String(i + 10)}`) }));
    await assertSucceeds(updateDoc(ref, { replaceDates: ['2028-02-29', '2000-02-29', '2027-01-31', '2027-12-31', '2027-06-30', '2027-02-28'] }));
    await assertSucceeds(updateDoc(ref, { replaceDates: [] }));
    await assertSucceeds(updateDoc(ref, { replaceDates: null }));
    for (const bad of [
      '2027-07-12', ['2027-7-12'], ['12/07/2027'], ['2027-07-12', '2027-07-12'], ['2027-13-01'], [20270712],
      ['2027-07-12,2027-07-13'], Array.from({ length: 11 }, (_, i) => `2027-08-${String(i + 10)}`), [''],
      // Impossible calendar dates (CodeRabbit on PR #44).
      ['2027-02-31'], ['2027-02-29'], ['2027-04-31'], ['2027-11-31'], ['2100-02-28'], ['2027-07-12', '2027-06-31'],
    ]) {
      await assertFails(updateDoc(ref, { replaceDates: bad }), JSON.stringify(bad).slice(0, 60));
    }
  });

  test('replaceDates with a full programme and image still fits (expression budget)', async () => {
    const ed = db(EDITOR);
    await assertSucceeds(setDoc(doc(ed, 'seasons', 'big'), {
      key: 'great_lent', nameAr: 'ص'.repeat(300), nameEn: 'n'.repeat(300), startsAt: start, endsAt: end, active: true,
      replacesRegular: false, replaceDates: Array.from({ length: 10 }, (_, i) => `2027-04-${String(i + 10)}`),
      speakerAr: 'م'.repeat(200), speakerEn: 's'.repeat(200), topicAr: 'و'.repeat(300), topicEn: 't'.repeat(300),
      choirAr: 'ك'.repeat(200), choirEn: 'c'.repeat(200), venue: 'main', audience: 'general',
      attachmentUrl: 'https://drive.google.com/' + 'x'.repeat(470), attachmentLabelAr: 'ك'.repeat(80), attachmentLabelEn: 'b'.repeat(80),
      image: { source: 'url', url: 'https://img.example.org/a.jpg', alt: 'a'.repeat(200), w: 1600, h: 900 },
      imageStyle: 'banner',
    }));
  });

  test('assistant exceptionalSeasons: a list of known season keys (empty = none)', async () => {
    const ref = doc(db(OWNER), 'settings', 'assistant');
    await assertSucceeds(setDoc(ref, { perDay: 3, perDaySeason: 6,
      exceptionalSeasons: ['holy_week', 'pascha', 'nativity', 'revival_maximus', 'revival_moses', 'great_lent', 'kiahk', 'marian'] }));
    await assertSucceeds(updateDoc(ref, { exceptionalSeasons: [] }));
    await assertSucceeds(updateDoc(ref, { exceptionalSeasons: ['holy_week', 'pascha', 'nativity', 'epiphany', 'marian', 'fast',
      'revival_maximus', 'revival_moses', 'summer', 'apostles', 'nayrouz', 'kiahk', 'great_lent'] }));
    await assertSucceeds(updateDoc(ref, { exceptionalSeasons: null }));
    for (const bad of ['holy_week', ['lent'], [5], Array.from({ length: 14 }, () => 'fast')]) {
      await assertFails(updateDoc(ref, { exceptionalSeasons: bad }), JSON.stringify(bad));
    }
    await assertFails(setDoc(doc(db(STRANGER), 'settings', 'assistant'), { exceptionalSeasons: [] }));
  });
});

describe('P2-18R: owner-only writes for settings (contact, assistant, venues, audiences, seasonVerses)', () => {
  const S = '\u001f';
  const venueRow = (k, ar = 'القاعة', en = 'Hall') => [k, ar, en].join(S);
  const verseRow = (k = 'summer', ar = 'الرب نوري', r = 'مز ٢٧: ١', en = 'The Lord is my light', er = 'Ps 27:1') =>
    [k, ar, r, en, er].join(S);
  const validCategories = { c1: ['general', '1', '0', '10', 'استفسار عام', 'General inquiry', ''].join(S) };

  test('active non-owner editor cannot create or update settings/contact or settings/assistant', async () => {
    const ed = db(EDITOR);
    const own = db(OWNER);
    const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: `${uid}@x.test` });

    await assertFails(setDoc(doc(ed, 'settings', 'contact'), { categories: validCategories }));
    await assertFails(setDoc(doc(ed, 'settings', 'assistant'), { model: 'gemini-3.1-flash-lite' }));

    await assertSucceeds(setDoc(doc(own, 'settings', 'contact'), { categories: validCategories, ...stamp(OWNER) }));
    await assertSucceeds(setDoc(doc(own, 'settings', 'assistant'), { model: '', ...stamp(OWNER) }));

    await assertFails(updateDoc(doc(ed, 'settings', 'contact'), { categories: validCategories, ...stamp(EDITOR) }));
    await assertFails(updateDoc(doc(ed, 'settings', 'assistant'), { maxChars: 500, ...stamp(EDITOR) }));
  });

  test('active non-owner editor cannot change venues, audiences, or seasonVerses on settings/features', async () => {
    const ed = db(EDITOR);
    const own = db(OWNER);
    const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: `${uid}@x.test` });

    // Create attempts by editor
    await assertFails(setDoc(doc(ed, 'settings', 'features'), { venues: [venueRow('main')] }));
    await assertFails(setDoc(doc(ed, 'settings', 'features'), { audiences: [venueRow('youth')] }));
    await assertFails(setDoc(doc(ed, 'settings', 'features'), { seasonVerses: [verseRow()] }));

    // Seed stored settings/features with owner-only fields already populated
    await assertSucceeds(setDoc(doc(own, 'settings', 'features'), {
      ...convert(seed.settings.features),
      venues: [venueRow('main')],
      audiences: [venueRow('general')],
      seasonVerses: [verseRow()],
      ...stamp(OWNER),
    }));

    // Update attempts by editor changing any of the three keys are denied
    await assertFails(updateDoc(doc(ed, 'settings', 'features'), { venues: [], ...stamp(EDITOR) }));
    await assertFails(updateDoc(doc(ed, 'settings', 'features'), { audiences: [], ...stamp(EDITOR) }));
    await assertFails(updateDoc(doc(ed, 'settings', 'features'), { seasonVerses: [], ...stamp(EDITOR) }));
    await assertFails(setDoc(doc(ed, 'settings', 'features'), {
      venues: [venueRow('other')], liveEnabled: true, ...stamp(EDITOR),
    }, { merge: true }));
  });

  test('active non-owner editor can still save Today, live stream, and section switches when owner-only keys are untouched', async () => {
    const ed = db(EDITOR);
    const own = db(OWNER);
    const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: `${uid}@x.test` });

    await assertSucceeds(setDoc(doc(own, 'settings', 'features'), {
      ...convert(seed.settings.features),
      venues: [venueRow('main')],
      audiences: [venueRow('general')],
      seasonVerses: [verseRow()],
      ...stamp(OWNER),
    }));

    // Today & live stream update
    await assertSucceeds(updateDoc(doc(ed, 'settings', 'features'), {
      copticStrip: 'home',
      dayStartMode: 'fixed',
      dayStartsAt: '05:30',
      topEvent: true,
      commemoration: true,
      topEventServices: true,
      liveEnabled: true,
      liveUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      liveLabelAr: 'بث مباشر',
      liveLabelEn: 'Live',
      ...stamp(EDITOR),
    }));

    // Section switches update
    await assertSucceeds(updateDoc(doc(ed, 'settings', 'features'), {
      'sections.assistant': false,
      'sections.contactForm': true,
      ...stamp(EDITOR),
    }));
  });

  test('owner writes settings/contact, settings/assistant, and worst-case venues/audiences/seasonVerses under budget', async () => {
    const own = db(OWNER);
    const stamp = () => ({ updatedAt: serverTimestamp(), updatedBy: `${OWNER}@x.test` });

    await assertSucceeds(setDoc(doc(own, 'settings', 'contact'), { categories: validCategories, ...stamp() }));
    await assertSucceeds(setDoc(doc(own, 'settings', 'assistant'), {
      model: 'gemini-3.1-flash-lite', maxChars: 1000, perMinute: 20, perDay: 100, perDaySeason: 100, perSession: 200,
      ...stamp(),
    }));

    // Worst-case whole-doc save with 12 max-length venues, 12 max-length audiences, and 40 max-length seasonVerses
    await assertSucceeds(setDoc(doc(own, 'settings', 'features'), {
      ...convert(seed.settings.features),
      venues: Array.from({ length: 12 }, (_, i) => venueRow(`v${i}`, 'ق'.repeat(80), 'e'.repeat(80))),
      audiences: Array.from({ length: 12 }, (_, i) => venueRow(`a${i}`, 'ج'.repeat(80), 'g'.repeat(80))),
      seasonVerses: Array.from({ length: 40 }, () => verseRow('summer', 'آ'.repeat(500), 'ر'.repeat(60), 'e'.repeat(500), 'r'.repeat(60))),
      ...stamp(),
    }));
  });

  test('anonymous reads of settings/contact, settings/assistant, and settings/features still succeed', async () => {
    const own = db(OWNER);
    await assertSucceeds(setDoc(doc(own, 'settings', 'contact'), { categories: validCategories }));
    await assertSucceeds(setDoc(doc(own, 'settings', 'assistant'), { model: '' }));
    await assertSucceeds(setDoc(doc(own, 'settings', 'features'), convert(seed.settings.features)));

    const pub = db(null);
    await assertSucceeds(getDoc(doc(pub, 'settings', 'contact')));
    await assertSucceeds(getDoc(doc(pub, 'settings', 'assistant')));
    await assertSucceeds(getDoc(doc(pub, 'settings', 'features')));
  });
});

describe('P2-27b: englishEnabled owner-only switch on settings/features', () => {
  test('owner can toggle englishEnabled; editor cannot create or change it, and non-bool is rejected', async () => {
    const ed = db(EDITOR);
    const own = db(OWNER);
    const refOwn = doc(own, 'settings', 'features');
    const refEd = doc(ed, 'settings', 'features');
    const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: `${uid}@x.test` });

    // Non-owner editor cannot create with englishEnabled set
    await assertFails(setDoc(refEd, { ...convert(seed.settings.features), englishEnabled: false }));

    // Owner creates with englishEnabled: false and toggles back to true
    await assertSucceeds(setDoc(refOwn, { ...convert(seed.settings.features), englishEnabled: false, ...stamp(OWNER) }));
    await assertSucceeds(updateDoc(refOwn, { englishEnabled: true, ...stamp(OWNER) }));
    await assertSucceeds(updateDoc(refOwn, { englishEnabled: false, ...stamp(OWNER) }));

    // Non-bool rejected even for owner
    for (const bad of ['no', 0, null, []]) {
      await assertFails(updateDoc(refOwn, { englishEnabled: bad, ...stamp(OWNER) }));
    }

    // Non-owner editor cannot change englishEnabled (alone or bundled with other valid keys)
    await assertFails(updateDoc(refEd, { englishEnabled: true, ...stamp(EDITOR) }));
    await assertFails(setDoc(refEd, { englishEnabled: true, liveEnabled: true, ...stamp(EDITOR) }, { merge: true }));

    // Non-owner editor can still save other settings when englishEnabled is omitted from mergeFields
    await assertSucceeds(setDoc(refEd, { liveEnabled: true, ...stamp(EDITOR) }, {
      mergeFields: ['liveEnabled', 'updatedAt', 'updatedBy'],
    }));
  });

  test('owner toggles englishEnabled on a full existing FeaturesScreen document; editor denied', async () => {
    const ed = db(EDITOR);
    const own = db(OWNER);
    const refOwn = doc(own, 'settings', 'features');
    const refEd = doc(ed, 'settings', 'features');
    const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: `${uid}@x.test` });

    // Seed a full existing settings/features document (seed + extra fields)
    const fullExisting = {
      ...convert(seed.settings.features),
      heroMotion: true,
      heroSeasonTint: true,
      heroShowAddress: false,
      aboutMilestones: true,
      occasions: { auto: false, easter: true, resurrectionDays: 7, schedule: {}, followSeason: true },
      themeColors: {},
      installPrompt: false,
      push: false,
      englishEnabled: true,
    };
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'settings', 'features'), fullExisting);
    });

    // Payload matching FeaturesScreen / featuresSaveWrites base write
    const basePayload = (englishEnabled, uid) => ({
      sections: fullExisting.sections,
      homeOrder: fullExisting.homeOrder,
      homeHidden: fullExisting.homeHidden,
      heroTitleAr: fullExisting.heroTitleAr,
      heroTitleEn: fullExisting.heroTitleEn,
      heroSubtitleAr: fullExisting.heroSubtitleAr,
      heroSubtitleEn: fullExisting.heroSubtitleEn,
      bannerEnabled: fullExisting.bannerEnabled,
      bannerAr: fullExisting.bannerAr,
      bannerEn: fullExisting.bannerEn,
      bannerLink: fullExisting.bannerLink,
      theme: fullExisting.theme,
      footer: fullExisting.footer,
      heroMotion: true,
      heroSeasonTint: true,
      heroShowAddress: false,
      aboutMilestones: true,
      errorReporting: true,
      englishEnabled,
      ...stamp(uid),
    });

    const offPayload = basePayload(false, OWNER);
    await assertSucceeds(setDoc(refOwn, offPayload, { mergeFields: Object.keys(offPayload) }));

    const onPayload = basePayload(true, OWNER);
    await assertSucceeds(setDoc(refOwn, onPayload, { mergeFields: Object.keys(onPayload) }));

    // Editor cannot toggle englishEnabled even with the full FeaturesScreen payload
    const edOffPayload = basePayload(false, EDITOR);
    await assertFails(setDoc(refEd, edOffPayload, { mergeFields: Object.keys(edOffPayload) }));
  });
});

describe('install banner and push settings (ADR-057)', () => {
  const featuresRef = (uid = EDITOR) => doc(db(uid), 'settings', 'features');
  const validEditorInstallAndPush = {
    installPrompt: true,
    installTitleAr: 'تطبيق الكنيسة على هاتفك',
    installTitleEn: 'Church app on your phone',
    installBodyAr: 'تابع القداسات والصلوات والمواسم وتلقّ التنبيهات بسهولة من هاتفك.',
    installBodyEn: 'Follow liturgies, prayers and seasons with easy updates on your phone.',
    installApkVersion: '1.1.0',
    installApkBuild: 42,
    installApkSizeMb: 18.4,
    installApkSize32Mb: 17.9,
    installReshowDays: 30,
    installRemindDays: 3,
    push: true,
    pushTypes: ['announcements', 'verse_daily', 'katameros_daily', 'seasons', 'feasts', 'reminders'],
    reminderLeads: [0, 15, 60, 1440],
    reminderDefaultLead: 60,
  };
  const validInstallAndPush = {
    ...validEditorInstallAndPush,
    installAndroidUrl: 'https://example.com/app.apk',
    installAndroidUrl32: '/app/android/older.apk',
    pushVapidKey: 'BKAGkFj27-exampleVapidKey890123456789012345678901234567890123456789012345678901234567890',
  };

  test('owner can save full valid install and push settings; editor can save non-owner fields', async () => {
    await assertSucceeds(setDoc(featuresRef(OWNER), validInstallAndPush, { merge: true }));
    await assertSucceeds(setDoc(featuresRef(EDITOR), validEditorInstallAndPush, { merge: true }));
  });

  test('stranger cannot write install or push settings', async () => {
    await assertFails(setDoc(doc(db(STRANGER), 'settings', 'features'), validInstallAndPush, { merge: true }));
  });

  test('rejects invalid install fields', async () => {
    const ownerBadCases = [
      { installAndroidUrl: 'javascript:alert(1)' },
      { installAndroidUrl32: '//evil.com/phish' },
    ];
    for (const bad of ownerBadCases) {
      await assertFails(setDoc(featuresRef(OWNER), bad, { merge: true }), JSON.stringify(bad));
    }
    const badCases = [
      { installApkVersion: '1.x' },
      { installApkBuild: -1 },
      { installApkBuild: 1000000 },
      { installApkSizeMb: 500 },
      { installApkSize32Mb: -1 },
      { installReshowDays: 400 },
      { installRemindDays: 0 },
      { installRemindDays: 61 },
    ];
    for (const bad of badCases) {
      await assertFails(setDoc(featuresRef(), bad, { merge: true }), JSON.stringify(bad));
    }
  });

  test('rejects invalid push fields', async () => {
    const ownerBadCases = [
      { pushVapidKey: 'with spaces in the middle 8901234567890123456789012345678901234567890123456789012345678901234567890' },
      { pushVapidKey: 'too-short' },
    ];
    for (const bad of ownerBadCases) {
      await assertFails(setDoc(featuresRef(OWNER), bad, { merge: true }), JSON.stringify(bad));
    }
    const badCases = [
      { pushTypes: ['announcements', 'occasions'] }, // retired occasions type
      { pushTypes: ['announcements', 'announcements'] }, // duplicate type
      { pushTypes: ['announcements', 'unknown_type'] },
      { reminderLeads: [7] }, // not in allowed set
      { reminderLeads: [0, 15, 60, 120, 180] }, // more than 4 items
      { reminderLeads: [15, 15] }, // duplicate lead
      { reminderDefaultLead: 99 }, // not in reminderLeads
    ];
    for (const bad of badCases) {
      await assertFails(setDoc(featuresRef(), bad, { merge: true }), JSON.stringify(bad));
    }
  });

  test('pageHeaders allows notifications page override and handles all 9 pages at max lengths', async () => {
    const pageHeader = () => ({
      titleAr: 'ت'.repeat(200),
      titleEn: 't'.repeat(200),
      subtitleAr: 'س'.repeat(300),
      subtitleEn: 's'.repeat(300),
      introAr: 'م'.repeat(1500),
      introEn: 'i'.repeat(1500),
    });

    const allNineHeaders = {
      about: pageHeader(),
      schedule: pageHeader(),
      education: pageHeader(),
      activities: pageHeader(),
      clinics: pageHeader(),
      services: pageHeader(),
      contact: pageHeader(),
      ask: pageHeader(),
      notifications: pageHeader(),
    };

    // Incremental update of notifications only
    await assertSucceeds(setDoc(featuresRef(), {
      pageHeaders: { notifications: pageHeader() },
    }, { merge: true }));

    // Unrelated update (e.g. heroMotion) still succeeds
    await assertSucceeds(setDoc(featuresRef(), {
      heroMotion: false,
    }, { merge: true }));
  });

  test('fresh create of settings/features with all 9 page headers at max lengths (expression cap)', async () => {
    const pageHeader = () => ({
      titleAr: 'ت'.repeat(200), titleEn: 't'.repeat(200),
      subtitleAr: 'س'.repeat(300), subtitleEn: 's'.repeat(300),
      introAr: 'م'.repeat(1500), introEn: 'i'.repeat(1500),
    });
    const keys = ['about', 'schedule', 'education', 'activities', 'clinics', 'services', 'contact', 'ask', 'notifications'];
    // No earlier write in this test: the document does not exist yet (create).
    await assertSucceeds(setDoc(featuresRef(), {
      pageHeaders: Object.fromEntries(keys.map((k) => [k, pageHeader()])),
      heroMotion: true,
    }));
  });

  test('whole-document saves: worst-case page headers next to stored ADR-057 fields, and the App screen save next to stored headers', async () => {
    const pageHeader = (t = 't') => ({
      titleAr: 'ت'.repeat(200), titleEn: t.repeat(200),
      subtitleAr: 'س'.repeat(300), subtitleEn: 's'.repeat(300),
      introAr: 'م'.repeat(1500), introEn: 'i'.repeat(1500),
    });
    const keys = ['about', 'schedule', 'education', 'activities', 'clinics', 'services', 'contact', 'ask', 'notifications'];
    const headers = (t) => Object.fromEntries(keys.map((k) => [k, pageHeader(t)]));
    const stamp = (uid = EDITOR) => ({ updatedAt: serverTimestamp(), updatedBy: `${uid}@x.test` });
    // Owner seeds full ADR-057 fields at once.
    await assertSucceeds(setDoc(featuresRef(OWNER), { ...validInstallAndPush, ...stamp(OWNER) }));
    // Page-headers screen on that document: all 9 headers rewritten at max
    // length, the ADR-057 fields unchanged (they cost nothing then).
    await assertSucceeds(setDoc(featuresRef(), { pageHeaders: headers('a'), ...stamp() }, { merge: true }));
    await assertSucceeds(setDoc(featuresRef(), { pageHeaders: headers('b'), ...stamp() }, { merge: true }));
    // Editor App & notifications save (excluding owner-only keys) with worst-case headers stored and unchanged.
    await assertSucceeds(setDoc(featuresRef(), { ...validEditorInstallAndPush, installApkBuild: 43, reminderDefaultLead: 15, ...stamp() }, { merge: true }));
  });

  test('reminderDefaultLead may be cleared to null; unknown keys still rejected next to ADR-057 keys', async () => {
    await assertSucceeds(setDoc(featuresRef(), validEditorInstallAndPush, { merge: true }));
    await assertSucceeds(setDoc(featuresRef(), { reminderDefaultLead: null }, { merge: true }));
    await assertFails(setDoc(featuresRef(), { installPrompt: true, bogusKey: 1 }, { merge: true }));
    await assertFails(setDoc(featuresRef(), { pushTypes: 'announcements' }, { merge: true }));
    await assertFails(setDoc(featuresRef(), { reminderLeads: null }, { merge: true }));
  });
});

// ---------------------------------------------------------------------------
// ADR-059: Notifications manager, Cloudflare Worker FCM sender & DayEvent IDs
// ---------------------------------------------------------------------------

describe('ADR-059: settings/notifications (notification manager & FCM sender)', () => {
  const notifRef = (uid = EDITOR) => doc(db(uid), 'settings', 'notifications');
  const validRow = (id = 'r1', eventKey = 'lit-123') =>
    [id, '2026-11-10T10:00:00Z', 'all', 'عظة الأحد', 'Sunday Sermon', 'تفاصيل العظة', 'Sermon details', '/', eventKey].join('\u001f');

  test('anonymous read denied; admin read allowed', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'settings', 'notifications'), { schedule: [] });
    });
    await assertFails(getDoc(doc(db(null), 'settings', 'notifications')));
    await assertFails(getDoc(doc(db(STRANGER), 'settings', 'notifications')));
    await assertSucceeds(getDoc(notifRef(EDITOR)));
    await assertSucceeds(getDoc(notifRef(OWNER)));
  });

  test('admin create/update schedule allowed with valid eventKeys (lit-, meeting-, day-, season-, or empty)', async () => {
    const rows = [
      validRow('r1', 'lit-123'),
      validRow('r2', 'meeting-youth'),
      validRow('r3', 'day-hash10char'),
      validRow('r4', 'season-coptic-new-year'),
      validRow('r5', ''),
    ];
    await assertSucceeds(setDoc(notifRef(EDITOR), { schedule: rows }));
    await assertSucceeds(updateDoc(notifRef(EDITOR), { schedule: [validRow('r1', 'lit-456')] }));
    await assertSucceeds(updateDoc(notifRef(EDITOR), { schedule: [] }));
  });

  test('client writes to server-only fields denied', async () => {
    await assertFails(setDoc(notifRef(EDITOR), { status: { r1: { state: 'ok' } } }, { merge: true }));
    await assertFails(setDoc(notifRef(EDITOR), { reminderPlan: ['p1'] }, { merge: true }));
    await assertFails(setDoc(notifRef(EDITOR), { remindersSent: ['s1'] }, { merge: true }));
    await assertFails(setDoc(notifRef(EDITOR), { health: { cronStatus: 'healthy' } }, { merge: true }));
    await assertFails(setDoc(notifRef(OWNER), { status: { r1: { state: 'ok' } } }, { merge: true }));
  });

  test('sentLog: clearing allowed for owner only, appending denied for all', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'settings', 'notifications'), {
        schedule: [],
        sentLog: ['log1\u001f2026-11-08T10:00:00Z\u001fall\u001fTitle\u001fTitle\u001f/\u001fok\u001fok'],
      });
    });
    // Non-owner (editor) cannot clear sentLog
    await assertFails(updateDoc(notifRef(EDITOR), { sentLog: [] }));
    // Owner can clear sentLog to empty list
    await assertSucceeds(updateDoc(notifRef(OWNER), { sentLog: [] }));
    // Neither owner nor editor can append or write non-empty sentLog
    await assertFails(updateDoc(notifRef(OWNER), { sentLog: ['item1'] }));
    await assertFails(updateDoc(notifRef(EDITOR), { sentLog: ['item1'] }));
  });

  test('schedule row limit: max 20 rows, 21 rows rejected', async () => {
    const twenty = Array.from({ length: 20 }, (_, i) => validRow(`r${i}`, 'lit-1'));
    await assertSucceeds(setDoc(notifRef(EDITOR), { schedule: twenty }));
    const twentyOne = Array.from({ length: 21 }, (_, i) => validRow(`r${i}`, 'lit-1'));
    await assertFails(setDoc(notifRef(EDITOR), { schedule: twentyOne }));
  });

  test('invalid links and targets rejected in schedule rows', async () => {
    const badLink = ['r1', '2026-11-10T10:00:00Z', 'all', 'Title', 'Title', 'Body', 'Body', 'https://evil.com', 'lit-1'].join('\u001f');
    const badTarget = ['r1', '2026-11-10T10:00:00Z', 'ios', 'Title', 'Title', 'Body', 'Body', '/', 'lit-1'].join('\u001f');
    const badKey = ['r1', '2026-11-10T10:00:00Z', 'all', 'Title', 'Title', 'Body', 'Body', '/', 'unknown-123'].join('\u001f');
    await assertFails(setDoc(notifRef(EDITOR), { schedule: [badLink] }));
    await assertFails(setDoc(notifRef(EDITOR), { schedule: [badTarget] }));
    await assertFails(setDoc(notifRef(EDITOR), { schedule: [badKey] }));
  });
});

describe('PR #55: writes exactly as the admin notifications screen makes them', () => {
  const notifRef = (uid = EDITOR) => doc(db(uid), 'settings', 'notifications');
  const featRef = (uid = EDITOR) => doc(db(uid), 'settings', 'features');
  const S = '\u001f';
  const stamp = (uid = EDITOR) => ({ updatedAt: serverTimestamp(), updatedBy: `${uid}@x.test` });
  // ScheduledNotification.toRow(): id, whole-second UTC, targets, ar/en texts, link, eventKey.
  const adminRow = (id, at = '2026-11-10T07:00:00Z') =>
    [id, at, 'all', 'نهضة السيدة العذراء الليلة', '', 'تبدأ الساعة ٧ مساءً\nبالكنيسة الكبيرة', '', '/church-education/youth', 'meeting-youth'].join(S);

  test('first save creates settings/notifications (doc absent) with the admin stamp', async () => {
    await assertSucceeds(setDoc(notifRef(), { schedule: [adminRow('ab12cd34')], ...stamp() }, { merge: true }));
  });

  test('editing the schedule next to sender-owned status/sentLog/health succeeds', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'settings', 'notifications'), {
        schedule: [adminRow('ab12cd34')],
        status: { ab12cd34: { state: 'ok' } },
        sentLog: [['ab12cd34', '2026-11-10T07:07:00.000Z', 'ok', 'x', 'cron'].join(S)],
        health: { lastRunAt: '2026-11-10T07:07:00.000Z' },
      });
    });
    await assertSucceeds(setDoc(notifRef(), { schedule: [adminRow('ab12cd34'), adminRow('ef56gh78')], ...stamp() }, { merge: true }));
    await assertSucceeds(setDoc(notifRef(), { schedule: [adminRow('ef56gh78')], ...stamp() }, { merge: true }));
  });

  test('a send time with milliseconds (old client format) or an empty Arabic body is rejected', async () => {
    await assertFails(setDoc(notifRef(), { schedule: [adminRow('ab12cd34', '2026-11-10T07:00:00.000Z')] }, { merge: true }));
    const noBody = ['ab12cd34', '2026-11-10T07:00:00Z', 'all', 'عنوان', '', '', '', '/', ''].join(S);
    await assertFails(setDoc(notifRef(), { schedule: [noBody] }, { merge: true }));
  });

  test('settings save from the notifications tab (all keys, one seasons template) succeeds', async () => {
    await assertSucceeds(setDoc(featRef(), {
      push: false,
      pushTypes: ['announcements', 'seasons', 'reminders'],
      reminderLeads: [0, 15, 60, 1440],
      reminderDefaultLead: 60,
      reminderSources: 'lit,mtg',
      notifyTypes: [['seasons', '08:30', '2', 'موسم كنسي: {season}', 'Church Season: {season}', 'يبدأ {season} بعد {days} أيام', 'Season of {season} begins in {days} days'].join(S)],
      ...stamp(),
    }, { merge: true }));
    await assertSucceeds(setDoc(doc(db(OWNER), 'settings', 'features'), {
      push: false,
      pushVapidKey: '',
      pushTypes: ['announcements', 'seasons', 'reminders'],
      reminderLeads: [0, 15, 60, 1440],
      reminderDefaultLead: 60,
      reminderSources: 'lit,mtg',
      notifyTypes: [['seasons', '08:30', '2', 'موسم كنسي: {season}', 'Church Season: {season}', 'يبدأ {season} بعد {days} أيام', 'Season of {season} begins in {days} days'].join(S)],
      updatedAt: serverTimestamp(),
      updatedBy: `${OWNER}@x.test`,
    }, { merge: true }));
    // Every type customised at once (6 rows), each at max lengths.
    const types = ['announcements', 'verse_daily', 'katameros_daily', 'seasons', 'feasts', 'reminders'];
    await assertSucceeds(setDoc(featRef(), {
      notifyTypes: types.map((t) => [t, t === 'announcements' || t === 'reminders' ? '' : '07:00', t === 'seasons' ? '7' : '', 'ع'.repeat(120), 'e'.repeat(120), 'ن'.repeat(300), 'b'.repeat(300)].join(S)),
      ...stamp(),
    }, { merge: true }));
  });
});

describe('ADR-059: settings/features notifyTypes & reminderSources', () => {
  const featRef = (uid = EDITOR) => doc(db(uid), 'settings', 'features');
  const S = '\u001f';
  const validInstallAndPush = {
    installPrompt: true,
    installTitleAr: 'تطبيق الكنيسة على هاتفك',
    installTitleEn: 'Church app on your phone',
    installBodyAr: 'تابع القداسات والصلوات والمواسم وتلقّ التنبيهات بسهولة من هاتفك.',
    installBodyEn: 'Follow liturgies, prayers and seasons with easy updates on your phone.',
    installAndroidUrl: 'https://example.com/app.apk',
    installAndroidUrl32: '/app/android/older.apk',
    installApkVersion: '1.1.0',
    installApkBuild: 42,
    installApkSizeMb: 18.4,
    installApkSize32Mb: 17.9,
    installReshowDays: 30,
    installRemindDays: 3,
    push: true,
    pushVapidKey: 'BKAGkFj27-exampleVapidKey890123456789012345678901234567890123456789012345678901234567890',
    pushTypes: ['announcements', 'verse_daily', 'katameros_daily', 'seasons', 'feasts', 'reminders'],
    reminderLeads: [0, 15, 60, 1440],
    reminderDefaultLead: 60,
  };

  test('valid notifyTypes and reminderSources are accepted', async () => {
    const validNotifyTypes = [
      ['verse_daily', '07:00', '', 'آية اليوم', 'Verse of the Day', '{verse}', '{verse}'].join(S),
      ['katameros_daily', '06:30', '', 'قراءات اليوم', 'Daily Katameros', '{reading}', '{reading}'].join(S),
      ['seasons', '07:00', '3', 'المواسم الكنسية', 'Church Seasons', '{season}', '{season}'].join(S),
      ['feasts', '07:30', '', 'أعياد ومناسبات', 'Feasts & Occasions', '{feast}', '{feast}'].join(S),
      ['announcements', '20:00', '', 'تنبيه هام', 'Announcement', '{event}', '{event}'].join(S),
      ['reminders', '', '', 'تذكير بموعد', 'Reminder', '{event}', '{event}'].join(S),
    ];

    await assertSucceeds(setDoc(featRef(), {
      notifyTypes: validNotifyTypes,
      reminderSources: 'lit,mtg,day',
    }, { merge: true }));

    await assertSucceeds(setDoc(featRef(), { reminderSources: '' }, { merge: true }));
    await assertSucceeds(setDoc(featRef(), { reminderSources: 'lit' }, { merge: true }));
    await assertSucceeds(setDoc(featRef(), { reminderSources: 'lit,mtg' }, { merge: true }));
    await assertSucceeds(setDoc(featRef(), { notifyTypes: [] }, { merge: true }));
  });

  test('invalid notifyTypes and reminderSources are rejected', async () => {
    // Bad type id
    await assertFails(setDoc(featRef(), {
      notifyTypes: [['bad_type', '07:00', '', 'Title', 'Title', 'Body', 'Body'].join(S)],
    }, { merge: true }));

    // Bad time
    await assertFails(setDoc(featRef(), {
      notifyTypes: [['verse_daily', '25:00', '', 'Title', 'Title', 'Body', 'Body'].join(S)],
    }, { merge: true }));

    // Bad daysBefore (> 14)
    await assertFails(setDoc(featRef(), {
      notifyTypes: [['seasons', '07:00', '15', 'Title', 'Title', 'Body', 'Body'].join(S)],
    }, { merge: true }));

    // More than 6 rows
    const sevenRows = Array.from({ length: 7 }, () =>
      ['verse_daily', '07:00', '', 'Title', 'Title', 'Body', 'Body'].join(S)
    );
    await assertFails(setDoc(featRef(), { notifyTypes: sevenRows }, { merge: true }));

    // Invalid reminderSources
    await assertFails(setDoc(featRef(), { reminderSources: 'invalid' }, { merge: true }));
    await assertFails(setDoc(featRef(), { reminderSources: 'lit,lit' }, { merge: true }));
    await assertFails(setDoc(featRef(), { reminderSources: 'lit,mtg,day,extra' }, { merge: true }));
  });

  test('expression budget: whole-doc save with notifyTypes, reminderSources, install and push fields', async () => {
    const stamp = (uid = OWNER) => ({ updatedAt: serverTimestamp(), updatedBy: `${uid}@x.test` });
    const fullPayload = {
      ...validInstallAndPush,
      notifyTypes: [
        ['verse_daily', '07:00', '', 'آية اليوم', 'Verse of the Day', '{verse}', '{verse}'].join(S),
        ['seasons', '07:00', '3', 'المواسم', 'Seasons', '{season}', '{season}'].join(S),
      ],
      reminderSources: 'lit,mtg,day',
      ...stamp(OWNER),
    };
    await assertSucceeds(setDoc(featRef(OWNER), fullPayload, { merge: true }));
    const { installAndroidUrl, installAndroidUrl32, pushVapidKey, ...editorPayload } = fullPayload;
    await assertSucceeds(setDoc(featRef(EDITOR), { ...editorPayload, ...stamp(EDITOR) }, { merge: true }));
  });
});

describe('ADR-059: validDayEvent 17th field (DayEvent.id)', () => {
  const featRef = (uid = EDITOR) => doc(db(uid), 'settings', 'features');
  const S = '\u001f';

  // Base 13 fields (ADR-039 / ADR-040)
  const base13 = [
    '2026-11-04', '', '19:00', '21:00', 'عنوان اليوم', 'Title En',
    'متكلم', 'Speaker', 'موضوع', 'Topic', 'ملاحظة', 'Note', '/',
  ];

  test('13 fields (legacy without pdf/labels/id) is accepted', async () => {
    await assertSucceeds(setDoc(featRef(), {
      dayEvents: [base13.join(S)],
    }, { merge: true }));
  });

  test('16 fields (with pdf and labels, without id) is accepted', async () => {
    const ev16 = [...base13, 'https://example.com/guide.pdf', 'labelAr', 'labelEn'];
    await assertSucceeds(setDoc(featRef(), {
      dayEvents: [ev16.join(S)],
    }, { merge: true }));
  });

  test('17 fields with 8-char random ID or 10-char SHA-1 hex ID is accepted', async () => {
    const ev17Random = [...base13, 'https://example.com/guide.pdf', 'labelAr', 'labelEn', 'a1b2c3d4'];
    const ev17Sha1 = [...base13, 'https://example.com/guide.pdf', 'labelAr', 'labelEn', '1234567890'];
    const ev17EmptyId = [...base13, 'https://example.com/guide.pdf', 'labelAr', 'labelEn', ''];

    await assertSucceeds(setDoc(featRef(), {
      dayEvents: [ev17Random.join(S), ev17Sha1.join(S), ev17EmptyId.join(S)],
    }, { merge: true }));
  });

  test('invalid 17th field is rejected', async () => {
    // Uppercase rejected
    const badUpper = [...base13, '', '', '', 'ABCDEFGH'];
    await assertFails(setDoc(featRef(), { dayEvents: [badUpper.join(S)] }, { merge: true }));

    // 7 characters rejected (< 8)
    const badShort = [...base13, '', '', '', 'abcdefg'];
    await assertFails(setDoc(featRef(), { dayEvents: [badShort.join(S)] }, { merge: true }));

    // 11 characters rejected (> 10)
    const badLong = [...base13, '', '', '', 'abcdefghijk'];
    await assertFails(setDoc(featRef(), { dayEvents: [badLong.join(S)] }, { merge: true }));

    // Non-alphanumeric rejected
    const badSymbols = [...base13, '', '', '', 'abc-defg'];
    await assertFails(setDoc(featRef(), { dayEvents: [badSymbols.join(S)] }, { merge: true }));
  });
});

describe('ADR-060: Web push rules (push_queue, meta/push_rate, meta/push_topics, meta/push_plan)', () => {
  const getUtcDay = (d = new Date()) =>
    d.getUTCFullYear() * 10000 + (d.getUTCMonth() + 1) * 100 + d.getUTCDate();

  const resetRate = () =>
    env.withSecurityRulesDisabled(async (ctx) =>
      deleteDoc(doc(ctx.firestore(), 'meta', 'push_rate'))
    );

  const seedRate = (data) =>
    env.withSecurityRulesDisabled(async (ctx) =>
      setDoc(doc(ctx.firestore(), 'meta', 'push_rate'), data)
    );

  const seedMeta = (metaDoc, data) =>
    env.withSecurityRulesDisabled(async (ctx) =>
      setDoc(doc(ctx.firestore(), 'meta', metaDoc), data)
    );

  let queueSeq = 0;
  function pushBatch(fs, { queueData, rateData, queueId } = {}) {
    queueSeq++;
    const qid = queueId ?? `queueDoc${String(queueSeq).padStart(4, '0')}${Date.now()}`;
    const batch = writeBatch(fs);
    const qRef = doc(fs, 'push_queue', qid);
    const rate = {
      lastAt: serverTimestamp(),
      lastId: qid,
      day: getUtcDay(),
      count: 1,
      ...rateData,
    };
    // Ensure lastId matches qid unless explicitly overridden for failure tests
    if (!rateData?.lastId) {
      rate.lastId = qid;
    }
    const defaultQueue = {
      token: 'A'.repeat(120),
      want: ['web_announcements_ar', 'web_seasons_ar'],
      createdAt: serverTimestamp(),
    };
    batch.set(qRef, queueData ?? defaultQueue);
    batch.set(doc(fs, 'meta', 'push_rate'), rate, { merge: true });
    return { batch, qRef };
  }

  test('valid opt-in batch with recurring and once-off topics succeeds', async () => {
    await resetRate();
    const pub = db(null);
    const max30Topics = Array.from({ length: 30 }, (_, i) =>
      `web_rem_lit-${'x'.repeat(40)}_60_ar`
    ).join(',');

    const { batch } = pushBatch(pub, {
      queueData: {
        token: 'token_' + 'b'.repeat(120),
        want: ['web_announcements_ar', 'web_seasons_ar'],
        rem: 'web_rem_lit-sun1_60_ar,web_rem_day-5d16df6bbc_20261115_15_ar',
        drop: 'web_rem_season-pascha_1440_ar',
        createdAt: serverTimestamp(),
      },
    });
    await assertSucceeds(batch.commit());

    // 30 max-length topics under size <= 2600
    await resetRate();
    const { batch: b30 } = pushBatch(pub, {
      queueId: 'queueDocMax30Topics1234',
      queueData: {
        token: 'token_' + 'c'.repeat(120),
        want: ['web_announcements_en'],
        rem: max30Topics,
        createdAt: serverTimestamp(),
      },
    });
    await assertSucceeds(b30.commit());

    // want: [] unsubscribe-all succeeds
    await resetRate();
    const { batch: bUnsub } = pushBatch(pub, {
      queueId: 'queueDocUnsub12345678',
      queueData: {
        token: 'token_' + 'd'.repeat(120),
        want: [],
        rem: '',
        drop: 'web_rem_lit-sun1_60_ar',
        createdAt: serverTimestamp(),
      },
    });
    await assertSucceeds(bUnsub.commit());
  });

  test('standalone push_queue or standalone meta/push_rate is denied', async () => {
    await resetRate();
    const pub = db(null);

    // Standalone push_queue without meta/push_rate
    await assertFails(setDoc(doc(pub, 'push_queue', 'alone1234567890'), {
      token: 'A'.repeat(120),
      want: ['web_announcements_ar'],
      createdAt: serverTimestamp(),
    }));

    // Standalone meta/push_rate without creating push_queue doc
    await assertFails(setDoc(doc(pub, 'meta', 'push_rate'), {
      lastAt: serverTimestamp(),
      lastId: 'nonexistent12345678',
      day: getUtcDay(),
      count: 1,
    }));
  });

  test('throttle spacing: write within 3 seconds is denied', async () => {
    await resetRate();
    const pub = db(null);

    // Seed a rate doc whose lastAt is recent (less than 3 seconds ago)
    await seedRate({
      lastAt: serverTimestamp(),
      lastId: 'prev1234567890',
      day: getUtcDay(),
      count: 1,
    });

    const { batch } = pushBatch(pub, {
      rateData: {
        lastAt: serverTimestamp(),
        day: getUtcDay(),
        count: 2,
      },
    });
    await assertFails(batch.commit());
  });

  test('daily cap: count == 1001 is denied', async () => {
    await resetRate();
    const pub = db(null);

    const pastDate = new Date(Date.now() - 5000);
    await seedRate({
      lastAt: Timestamp.fromDate(pastDate),
      lastId: 'prev1234567890',
      day: getUtcDay(),
      count: 1000,
    });

    const { batch } = pushBatch(pub, {
      rateData: {
        lastAt: serverTimestamp(),
        day: getUtcDay(),
        count: 1001,
      },
    });
    await assertFails(batch.commit());
  });

  test('increment(1) on same UTC day is allowed without reading meta/push_rate', async () => {
    await resetRate();
    const pub = db(null);

    const pastDate = new Date(Date.now() - 5000);
    await seedRate({
      lastAt: Timestamp.fromDate(pastDate),
      lastId: 'prev1234567890',
      day: getUtcDay(),
      count: 5,
    });

    const { batch } = pushBatch(pub, {
      rateData: {
        lastAt: serverTimestamp(),
        day: getUtcDay(),
        count: increment(1),
      },
    });
    await assertSucceeds(batch.commit());
  });

  test('UTC day rollover: increment(1) denied, literal count: 1 allowed', async () => {
    await resetRate();
    const pub = db(null);

    const yesterdayUtcInt = 20261108; // yesterday
    const todayUtcInt = getUtcDay(); // today
    const pastDate = new Date(Date.now() - 5000);

    await seedRate({
      lastAt: Timestamp.fromDate(pastDate),
      lastId: 'prev1234567890',
      day: yesterdayUtcInt,
      count: 42,
    });

    // increment(1) yields 43 != 1 on a new day -> denied
    const { batch: bInc } = pushBatch(pub, {
      rateData: {
        lastAt: serverTimestamp(),
        day: todayUtcInt,
        count: increment(1),
      },
    });
    await assertFails(bInc.commit());

    // count: 2 on a new day -> denied
    const { batch: bCount2 } = pushBatch(pub, {
      rateData: {
        lastAt: serverTimestamp(),
        day: todayUtcInt,
        count: 2,
      },
    });
    await assertFails(bCount2.commit());

    // wrong day integer -> denied
    const { batch: bWrongDay } = pushBatch(pub, {
      rateData: {
        lastAt: serverTimestamp(),
        day: 20261101,
        count: 1,
      },
    });
    await assertFails(bWrongDay.commit());

    // literal count: 1 on a new day -> allowed
    const { batch: bCount1 } = pushBatch(pub, {
      rateData: {
        lastAt: serverTimestamp(),
        day: todayUtcInt,
        count: 1,
      },
    });
    await assertSucceeds(bCount1.commit());
  });

  test('invalid topics, tokens, and leads are denied', async () => {
    await resetRate();
    const pub = db(null);

    // Malformed token
    const { batch: bBadToken } = pushBatch(pub, {
      queueData: {
        token: 'short',
        want: ['web_announcements_ar'],
        createdAt: serverTimestamp(),
      },
    });
    await assertFails(bBadToken.commit());

    // Local-owned or illegal want topic
    const { batch: bVerse } = pushBatch(pub, {
      queueData: {
        token: 'A'.repeat(120),
        want: ['web_verse_daily_ar'],
        createdAt: serverTimestamp(),
      },
    });
    await assertFails(bVerse.commit());

    const { batch: bAppTopic } = pushBatch(pub, {
      queueData: {
        token: 'A'.repeat(120),
        want: ['app_announcements_ar'],
        createdAt: serverTimestamp(),
      },
    });
    await assertFails(bAppTopic.commit());

    // Uppercase in rem
    const { batch: bUpper } = pushBatch(pub, {
      queueData: {
        token: 'A'.repeat(120),
        want: ['web_announcements_ar'],
        rem: 'web_rem_lit-SUN1_60_ar',
        createdAt: serverTimestamp(),
      },
    });
    await assertFails(bUpper.commit());

    // Suffix > 40 characters
    const { batch: bLongSuffix } = pushBatch(pub, {
      queueData: {
        token: 'A'.repeat(120),
        want: ['web_announcements_ar'],
        rem: `web_rem_lit-${'a'.repeat(41)}_60_ar`,
        createdAt: serverTimestamp(),
      },
    });
    await assertFails(bLongSuffix.commit());

    // Invalid lead (7 minutes)
    const { batch: bBadLead } = pushBatch(pub, {
      queueData: {
        token: 'A'.repeat(120),
        want: ['web_announcements_ar'],
        rem: 'web_rem_lit-sun1_7_ar',
        createdAt: serverTimestamp(),
      },
    });
    await assertFails(bBadLead.commit());

    // 31st topic in rem
    const rem31 = Array.from({ length: 31 }, (_, i) => `web_rem_lit-${i}_60_ar`).join(',');
    const { batch: b31 } = pushBatch(pub, {
      queueData: {
        token: 'A'.repeat(120),
        want: ['web_announcements_ar'],
        rem: rem31,
        createdAt: serverTimestamp(),
      },
    });
    await assertFails(b31.commit());
  });

  test('visitor cannot read, update, or delete push_queue or meta/push_rate', async () => {
    const pub = db(null);
    await assertFails(getDoc(doc(pub, 'push_queue', 'anyDoc')));
    await assertFails(getDocs(collection(pub, 'push_queue')));
    await assertFails(updateDoc(doc(pub, 'push_queue', 'anyDoc'), { token: 'new' }));
    await assertFails(deleteDoc(doc(pub, 'push_queue', 'anyDoc')));

    await assertFails(getDoc(doc(pub, 'meta', 'push_rate')));
    await assertFails(deleteDoc(doc(pub, 'meta', 'push_rate')));
  });

  test('admin can read meta/push_topics & meta/push_plan; visitors cannot; admin writes denied', async () => {
    await seedMeta('push_topics', { topics: { 'web_rem_lit-1_60_ar': true } });
    await seedMeta('push_plan', { reminderPlan: [] });

    // Admin read allowed
    await assertSucceeds(getDoc(doc(db(EDITOR), 'meta', 'push_topics')));
    await assertSucceeds(getDoc(doc(db(OWNER), 'meta', 'push_plan')));

    // Visitor read denied
    await assertFails(getDoc(doc(db(null), 'meta', 'push_topics')));
    await assertFails(getDoc(doc(db(null), 'meta', 'push_plan')));

    // Admin write denied
    await assertFails(setDoc(doc(db(EDITOR), 'meta', 'push_topics'), { topics: {} }));
    await assertFails(setDoc(doc(db(OWNER), 'meta', 'push_plan'), { reminderPlan: [] }));
    await assertFails(deleteDoc(doc(db(OWNER), 'meta', 'push_topics')));
  });

  test('explicit read-denial: both visitors AND admins denied get on meta/push_rate and meta/contact_rate', async () => {
    // Unauthenticated visitor
    await assertFails(getDoc(doc(db(null), 'meta', 'push_rate')));
    await assertFails(getDoc(doc(db(null), 'meta', 'contact_rate')));

    // Editor admin
    await assertFails(getDoc(doc(db(EDITOR), 'meta', 'push_rate')));
    await assertFails(getDoc(doc(db(EDITOR), 'meta', 'contact_rate')));

    // Owner admin
    await assertFails(getDoc(doc(db(OWNER), 'meta', 'push_rate')));
    await assertFails(getDoc(doc(db(OWNER), 'meta', 'contact_rate')));
  });
});


