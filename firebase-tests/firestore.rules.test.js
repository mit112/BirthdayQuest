import { readFileSync } from 'node:fs';
import { beforeAll, afterAll, beforeEach, describe, it } from 'vitest';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, writeBatch } from 'firebase/firestore';

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'birthdayquest-test',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

const EVENT = 'evt_1';
const HOST = 'uid_host';
const GUEST = 'uid_guest';
const OUTSIDER = 'uid_outsider';
const CELEBRANT = 'uid_celebrant';
const CODE = 'ABCD2345';
const CELEB_CODE = 'EFGH6789';

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `events/${EVENT}`), {
      name: "Alex's 30th", occasionType: 'birthday', celebrantName: 'Alex',
      hostUid: HOST, occasionDate: new Date(), isOpen: true, createdAt: new Date(),
      contributorCode: CODE, celebrantCode: CELEB_CODE,
    });
    await setDoc(doc(db, `events/${EVENT}/participants/${HOST}`), {
      name: 'Sam', avatarId: 'a1', mode: 'contributor', isHost: true, usedCode: CODE,
    });
    await setDoc(doc(db, `events/${EVENT}/participants/${CELEBRANT}`), {
      name: 'Alex', avatarId: 'a3', mode: 'celebrant', isHost: false, usedCode: CELEB_CODE,
    });
    await setDoc(doc(db, `inviteCodes/${CODE}`), { eventId: EVENT, kind: 'contributor' });
    await setDoc(doc(db, `inviteCodes/${CELEB_CODE}`), { eventId: EVENT, kind: 'celebrant' });
    await setDoc(doc(db, `events/${EVENT}/rewards/r1`), {
      fromName: 'Sam', title: 'A message', pointCost: 50, contentType: 'video',
      isUnlocked: false, sortOrder: 0, badgeIllustration: 'b', createdAt: new Date(),
      fetchedBy: [],
    });
  });
}

// Registers uid as an ordinary contributor, through the rules, the way a joiner would.
async function joinAsContributor(uid) {
  const db = testEnv.authenticatedContext(uid).firestore();
  await setDoc(doc(db, `events/${EVENT}/participants/${uid}`), {
    name: 'Jordan', avatarId: 'a2', mode: 'contributor', isHost: false, usedCode: CODE,
  });
}

describe('event scoping', () => {
  beforeEach(seed);

  it('lets a member read the event', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(getDoc(doc(db, `events/${EVENT}`)));
  });

  it('denies a non-member reading the event', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT}`)));
  });

  it('denies a non-member reading rewards', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT}/rewards/r1`)));
  });

  it('denies an unauthenticated read', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT}`)));
  });

  it('denies reading the invite code lookup', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(getDoc(doc(db, `inviteCodes/${CODE}`)));
  });

  it('lets a joiner self-register by presenting a valid code', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Jordan', avatarId: 'a2', mode: 'contributor', isHost: false, usedCode: CODE,
    }));
  });

  it('denies self-registering with a bogus code', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Jordan', avatarId: 'a2', mode: 'contributor', isHost: false, usedCode: 'WRONG123',
    }));
  });

  it('denies creating a participant document for someone else', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${OUTSIDER}`), {
      name: 'X', avatarId: 'a2', mode: 'contributor', isHost: false, usedCode: CODE,
    }));
  });

  it('denies self-promotion to host', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Jordan', avatarId: 'a2', mode: 'contributor', isHost: false, usedCode: CODE,
    });
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Jordan', avatarId: 'a2', mode: 'contributor', isHost: true, usedCode: CODE,
    }));
  });

  it('denies a non-host creating a reward', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Jordan', avatarId: 'a2', mode: 'contributor', isHost: false, usedCode: CODE,
    });
    await assertFails(setDoc(doc(db, `events/${EVENT}/rewards/r2`), {
      fromName: 'Jordan', title: 'x', pointCost: 50, contentType: 'video',
      isUnlocked: false, sortOrder: 1, badgeIllustration: 'b', createdAt: new Date(),
      fetchedBy: [],
    }));
  });

  it('denies editing the timeline once written', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `events/${EVENT}/timeline/t1`), {
        type: 'reward_unlocked', referenceId: 'r1', title: 'x', subtitle: 'y',
        badgeType: 'reward', badgeAsset: 'b', timestamp: new Date(),
      });
    });
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/timeline/t1`), { title: 'tampered' }));
  });
});

// Occasion creation is two-phase: the event document commits alone, then a single batch
// writes the host participant, the state doc, and the membership index. Firestore evaluates
// every write in a batch against COMMITTED state, so nothing in that batch may depend on the
// participant document the same batch is creating. State and membership creation are
// therefore gated on the event's hostUid, not on membership.
describe('two-phase occasion creation', () => {
  beforeEach(seed);

  it('allows creating an event you host', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(setDoc(doc(db, 'events/evt_new'), {
      name: 'A party', occasionType: 'birthday', celebrantName: 'Kim',
      hostUid: GUEST, occasionDate: new Date(), isOpen: true, createdAt: new Date(),
      contributorCode: 'IJKL2345', celebrantCode: 'MNPQ6789',
    }));
  });

  it('denies creating an event owned by someone else', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, 'events/evt_new'), {
      name: 'A party', occasionType: 'birthday', celebrantName: 'Kim',
      hostUid: OUTSIDER, occasionDate: new Date(), isOpen: true, createdAt: new Date(),
      contributorCode: 'IJKL2345', celebrantCode: 'MNPQ6789',
    }));
  });

  it('lets the host commit phase two as one batch against a bare event document', async () => {
    // Phase 1 committed the event and nothing else — no participant document yet.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), `events/${EVENT}/participants/${HOST}`));
    });

    const db = testEnv.authenticatedContext(HOST).firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, `events/${EVENT}/participants/${HOST}`), {
      name: 'Sam', avatarId: 'a1', mode: 'contributor', isHost: true, usedCode: CODE,
    });
    batch.set(doc(db, `events/${EVENT}/state/main`), {
      totalPoints: 0, completedChallengeIds: [], unlockedRewardIds: [], updatedAt: new Date(),
    });
    batch.set(doc(db, `memberships/${HOST}/events/${EVENT}`), {
      eventId: EVENT, name: "Alex's 30th", occasionType: 'birthday', joinedAt: new Date(),
    });
    await assertSucceeds(batch.commit());
  });

  it('denies a signed-in non-host creating the state document', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/state/main`), {
      totalPoints: 0, completedChallengeIds: [], unlockedRewardIds: [], updatedAt: new Date(),
    }));
  });
});

describe('membership index', () => {
  beforeEach(seed);

  it('lets the owner read their own membership index', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(getDoc(doc(db, `memberships/${HOST}/events/${EVENT}`)));
  });

  it("denies reading another user's membership index", async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, `memberships/${HOST}/events/${EVENT}`)));
  });

  it("denies writing into another user's membership index", async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(doc(db, `memberships/${HOST}/events/${EVENT}`), {
      eventId: EVENT, name: 'injected', occasionType: 'birthday', joinedAt: new Date(),
    }));
  });
});

// The celebrant code is single-use: the claimer consumes it, so a leaked link cannot be
// replayed by a second person.
describe('single-use celebrant code', () => {
  beforeEach(seed);

  it('lets the celebrant consume their own code', async () => {
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertSucceeds(deleteDoc(doc(db, `inviteCodes/${CELEB_CODE}`)));
  });

  it('denies a contributor consuming the celebrant code', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(deleteDoc(doc(db, `inviteCodes/${CELEB_CODE}`)));
  });
});
