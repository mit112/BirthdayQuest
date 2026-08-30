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
const MEMBER = 'uid_member';
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
    await setDoc(doc(db, `events/${EVENT}/participants/${MEMBER}`), {
      name: 'Lee', avatarId: 'a4', mode: 'contributor', isHost: false, usedCode: 'C4',
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

  it('denies a non-host contributor deleting reward media', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), `events/${EVENT}/rewards/r1/gift.jpg`), IMG, {
        contentType: 'image/jpeg',
      });
    });
    const s = testEnv.authenticatedContext(MEMBER).storage();
    await assertFails(deleteObject(ref(s, `events/${EVENT}/rewards/r1/gift.jpg`)));
  });

  it('lets the host delete reward media', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), `events/${EVENT}/rewards/r1/gift.jpg`), IMG, {
        contentType: 'image/jpeg',
      });
    });
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertSucceeds(deleteObject(ref(s, `events/${EVENT}/rewards/r1/gift.jpg`)));
  });

  it('denies proof uploads that are not images', async () => {
    const s = testEnv.authenticatedContext(CELEBRANT).storage();
    await assertFails(
      uploadBytes(ref(s, `events/${EVENT}/proofs/c1/proof.mp4`), IMG, { contentType: 'video/mp4' })
    );
  });

  it('denies an SVG upload even though it matches image/.*', async () => {
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertFails(
      uploadBytes(ref(s, `events/${EVENT}/rewards/r1/gift.svg`), IMG, { contentType: 'image/svg+xml' })
    );
  });

  it('denies an SVG upload with a charset parameter (bare equality would miss this)', async () => {
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertFails(
      uploadBytes(ref(s, `events/${EVENT}/rewards/r1/gift2.svg`), IMG, {
        contentType: 'image/svg+xml; charset=utf-8',
      })
    );
  });

  it('denies an unsuffixed image/svg upload (bare equality would miss this)', async () => {
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertFails(
      uploadBytes(ref(s, `events/${EVENT}/rewards/r1/gift3.svg`), IMG, { contentType: 'image/svg' })
    );
  });

  // The proofs path applies the same SVG exclusion, and used to do so through an
  // independently maintained copy of the clause — deleting it failed zero tests. It is the
  // clause stopping a member uploading a script-bearing SVG as a challenge proof, which the
  // read rule then serves to every member. Both paths now share isSafeImage(); these pin the
  // proofs side of it so the two cannot silently drift apart again.
  it('denies an SVG proof upload even though it matches image/.*', async () => {
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertFails(
      uploadBytes(ref(s, `events/${EVENT}/proofs/c1/proof.svg`), IMG, {
        contentType: 'image/svg+xml',
      })
    );
  });

  it('denies an SVG proof upload with a charset parameter (bare equality would miss this)', async () => {
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertFails(
      uploadBytes(ref(s, `events/${EVENT}/proofs/c1/proof2.svg`), IMG, {
        contentType: 'image/svg+xml; charset=utf-8',
      })
    );
  });

  it('denies an unsuffixed image/svg proof upload (bare equality would miss this)', async () => {
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertFails(
      uploadBytes(ref(s, `events/${EVENT}/proofs/c1/proof3.svg`), IMG, {
        contentType: 'image/svg',
      })
    );
  });

  // Sanity: the svg exclusion pattern must not over-match legitimate image/video/audio types.
  it('still lets a member upload a PNG reward', async () => {
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertSucceeds(
      uploadBytes(ref(s, `events/${EVENT}/rewards/r1/gift.png`), IMG, { contentType: 'image/png' })
    );
  });

  it('still lets a member upload an MP4 reward', async () => {
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertSucceeds(
      uploadBytes(ref(s, `events/${EVENT}/rewards/r1/gift.mp4`), IMG, { contentType: 'video/mp4' })
    );
  });

  it('still lets a member upload an MP3 reward', async () => {
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertSucceeds(
      uploadBytes(ref(s, `events/${EVENT}/rewards/r1/gift.mp3`), IMG, { contentType: 'audio/mpeg' })
    );
  });

  // Positive coverage: every proofs assertion above is assertFails. A typo in the proofs match
  // block (wrong segment name, wrong depth) would route all of them to the catch-all deny and
  // leave the suite green while proof uploads 403 in production. Assert the happy paths too.
  it('lets a member upload a valid proof image', async () => {
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertSucceeds(
      uploadBytes(ref(s, `events/${EVENT}/proofs/c1/proof.jpg`), IMG, { contentType: 'image/jpeg' })
    );
  });

  it('lets the celebrant delete a proof object', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), `events/${EVENT}/proofs/c1/proof.jpg`), IMG, {
        contentType: 'image/jpeg',
      });
    });
    const s = testEnv.authenticatedContext(CELEBRANT).storage();
    await assertSucceeds(deleteObject(ref(s, `events/${EVENT}/proofs/c1/proof.jpg`)));
  });

  // The host now deletes proofs too, so deleting a challenge can reclaim its orphaned proof
  // object (the expiry sweep never reaches it, since it only iterates live challenges). This is
  // the mutation-proof for the `|| isHost` clause: drop it and this reddens. CONTRIBUTOR is the
  // host in this suite (isHost: true).
  it('lets the host delete a proof object', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), `events/${EVENT}/proofs/c1/proof.jpg`), IMG, {
        contentType: 'image/jpeg',
      });
    });
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertSucceeds(deleteObject(ref(s, `events/${EVENT}/proofs/c1/proof.jpg`)));
  });

  // The grant is celebrant-or-host, NOT any member — a plain contributor must still be refused,
  // or a member could destroy another's proof evidence. Guards against over-widening to isMember.
  it('denies a plain member deleting a proof object', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), `events/${EVENT}/proofs/c1/proof.jpg`), IMG, {
        contentType: 'image/jpeg',
      });
    });
    const s = testEnv.authenticatedContext(MEMBER).storage();
    await assertFails(deleteObject(ref(s, `events/${EVENT}/proofs/c1/proof.jpg`)));
  });

  it('lets a member read a proof object', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), `events/${EVENT}/proofs/c1/proof.jpg`), IMG, {
        contentType: 'image/jpeg',
      });
    });
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertSucceeds(getBytes(ref(s, `events/${EVENT}/proofs/c1/proof.jpg`)));
  });

  it('lets a member read a reward object', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), `events/${EVENT}/rewards/r1/gift.jpg`), IMG, {
        contentType: 'image/jpeg',
      });
    });
    const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
    await assertSucceeds(getBytes(ref(s, `events/${EVENT}/rewards/r1/gift.jpg`)));
  });

  // Overwrite-as-delete: on an overwrite request.resource != null (so the delete branch of the
  // ternary is skipped) and, before this fix, the create branch only checked isMember — meaning
  // ANY member could destroy a gift/proof in place, no delete call needed, before the celebrant
  // ever fetched it. resource is the EXISTING object and is null only on a genuine create.
  describe('overwrite is not delete', () => {
    it('denies a member overwriting an existing reward object', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await uploadBytes(ref(ctx.storage(), `events/${EVENT}/rewards/r1/gift.jpg`), IMG, {
          contentType: 'image/jpeg',
        });
      });
      const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
      await assertFails(
        uploadBytes(ref(s, `events/${EVENT}/rewards/r1/gift.jpg`), new Uint8Array([9]), {
          contentType: 'image/png',
        })
      );
    });

    it('denies a member overwriting an existing proof object', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await uploadBytes(ref(ctx.storage(), `events/${EVENT}/proofs/c1/proof.jpg`), IMG, {
          contentType: 'image/jpeg',
        });
      });
      const s = testEnv.authenticatedContext(CONTRIBUTOR).storage();
      await assertFails(
        uploadBytes(ref(s, `events/${EVENT}/proofs/c1/proof.jpg`), new Uint8Array([9]), {
          contentType: 'image/png',
        })
      );
    });

    it('denies the celebrant overwriting an existing reward object, but still allows delete', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await uploadBytes(ref(ctx.storage(), `events/${EVENT}/rewards/r1/gift.jpg`), IMG, {
          contentType: 'image/jpeg',
        });
      });
      const s = testEnv.authenticatedContext(CELEBRANT).storage();
      await assertFails(
        uploadBytes(ref(s, `events/${EVENT}/rewards/r1/gift.jpg`), new Uint8Array([9]), {
          contentType: 'image/png',
        })
      );
      await assertSucceeds(deleteObject(ref(s, `events/${EVENT}/rewards/r1/gift.jpg`)));
    });
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
