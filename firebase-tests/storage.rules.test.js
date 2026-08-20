import { readFileSync } from 'node:fs';
import { beforeAll, afterAll, beforeEach, describe, it } from 'vitest';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

const EVENT = 'evt_1';
const EVENT2 = 'evt_2';
const CELEBRANT = 'uid_celebrant';
const CONTRIBUTOR = 'uid_contributor';
const OUTSIDER = 'uid_outsider';
const EVENT2_MEMBER = 'uid_event2_member';
const IMG = new Uint8Array([1, 2, 3]);

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'birthdayquest-test',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
    storage: { rules: readFileSync('../storage.rules', 'utf8'), host: '127.0.0.1', port: 9199 },
  });
});

afterAll(async () => { await testEnv.cleanup(); });

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `events/${EVENT}/participants/${CELEBRANT}`), {
      name: 'Alex', avatarId: 'a1', mode: 'celebrant', isHost: false, usedCode: 'C1',
    });
    await setDoc(doc(db, `events/${EVENT}/participants/${CONTRIBUTOR}`), {
      name: 'Sam', avatarId: 'a2', mode: 'contributor', isHost: true, usedCode: 'C2',
    });

    // A second, unrelated occasion. A member of evt_1 must not reach its media.
    await setDoc(doc(db, `events/${EVENT2}/participants/${EVENT2_MEMBER}`), {
      name: 'Pat', avatarId: 'a3', mode: 'contributor', isHost: true, usedCode: 'C3',
    });
  });
});

describe('storage membership gate', () => {
  it('lets a member upload reward media with a content type', async () => {
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertSucceeds(
      uploadBytes(ref(s, `events/${EVENT}/rewards/r1/gift.jpg`), IMG, { contentType: 'image/jpeg' })
    );
  });

  it('denies an upload with no usable content type', async () => {
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertFails(
      uploadBytes(ref(s, `events/${EVENT}/rewards/r1/gift.bin`), IMG, {
        contentType: 'application/octet-stream',
      })
    );
  });

  it('denies a non-member uploading', async () => {
    const s = testEnv.authenticatedContext(OUTSIDER).storage();
    await assertFails(
      uploadBytes(ref(s, `events/${EVENT}/rewards/r1/gift.jpg`), IMG, { contentType: 'image/jpeg' })
    );
  });

  it('denies a non-member reading reward media', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), `events/${EVENT}/rewards/r1/gift.jpg`), IMG, {
        contentType: 'image/jpeg',
      });
    });
    const s = testEnv.authenticatedContext(OUTSIDER).storage();
    await assertFails(getBytes(ref(s, `events/${EVENT}/rewards/r1/gift.jpg`)));
  });

  it('lets the celebrant delete reward media after fetching it', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), `events/${EVENT}/rewards/r1/gift.jpg`), IMG, {
        contentType: 'image/jpeg',
      });
    });
    const s = testEnv.authenticatedContext(CELEBRANT).storage();
    await assertSucceeds(deleteObject(ref(s, `events/${EVENT}/rewards/r1/gift.jpg`)));
  });

  it('denies a contributor deleting reward media', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), `events/${EVENT}/rewards/r1/gift.jpg`), IMG, {
        contentType: 'image/jpeg',
      });
    });
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertFails(deleteObject(ref(s, `events/${EVENT}/rewards/r1/gift.jpg`)));
  });

  it('denies proof uploads that are not images', async () => {
    const s = testEnv.authenticatedContext(CELEBRANT).storage();
    await assertFails(
      uploadBytes(ref(s, `events/${EVENT}/proofs/c1/proof.mp4`), IMG, { contentType: 'video/mp4' })
    );
  });

  // Cross-event isolation: the whole point of cross-service rules is that membership in one
  // event buys nothing in another. A non-member (tested above) is the easy case; a legitimate
  // member of a DIFFERENT event is the case the architecture actually rests on.
  describe('cross-event media isolation', () => {
    it('denies a member of evt_1 reading evt_2 reward media', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await uploadBytes(ref(ctx.storage(), `events/${EVENT2}/rewards/r9/gift.jpg`), IMG, {
          contentType: 'image/jpeg',
        });
      });
      const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
      await assertFails(getBytes(ref(s, `events/${EVENT2}/rewards/r9/gift.jpg`)));
    });

    it('denies a member of evt_1 uploading to evt_2 reward media', async () => {
      const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
      await assertFails(
        uploadBytes(ref(s, `events/${EVENT2}/rewards/r9/gift.jpg`), IMG, { contentType: 'image/jpeg' })
      );
    });

    it('denies a member of evt_1 uploading to evt_2 proofs', async () => {
      const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
      await assertFails(
        uploadBytes(ref(s, `events/${EVENT2}/proofs/c1/proof.jpg`), IMG, { contentType: 'image/jpeg' })
      );
    });
  });
});
