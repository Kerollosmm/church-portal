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
    const batch = writeBatch(pub);
    batch.set(doc(collection(pub, 'contact_messages')), {
      name: 'Mina', phone: '01012345678', email: '', message: 'Hello there', lang: 'ar', status: 'new',
      createdAt: serverTimestamp(),
    });
    batch.set(doc(pub, 'meta', 'contact_rate'), { lastAt: serverTimestamp() });
    await assertSucceeds(batch.commit());
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
