import { readFileSync } from 'node:fs';
import { beforeAll, afterAll, beforeEach, describe, it } from 'vitest';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, collection, setDoc, updateDoc, getDoc, getDocs, deleteDoc, writeBatch,
} from 'firebase/firestore';

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
const EVENT2 = 'evt_2';
const HOST = 'uid_host';
const HOST2 = 'uid_host_2';
const GUEST = 'uid_guest';
const OUTSIDER = 'uid_outsider';
const CELEBRANT = 'uid_celebrant';
const CODE = 'ABCD2345';
const CELEB_CODE = 'EFGH6789';
const CODE2 = 'RSTU2345';

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

    // A completely unrelated stranger's occasion. Nobody from evt_1 belongs to it.
    await setDoc(doc(db, `events/${EVENT2}`), {
      name: "Someone else's wedding", occasionType: 'wedding', celebrantName: 'Kim',
      hostUid: HOST2, occasionDate: new Date(), isOpen: true, createdAt: new Date(),
      contributorCode: CODE2, celebrantCode: 'VWXY6789',
    });
    await setDoc(doc(db, `events/${EVENT2}/participants/${HOST2}`), {
      name: 'Pat', avatarId: 'a4', mode: 'contributor', isHost: true, usedCode: CODE2,
    });
    await setDoc(doc(db, `events/${EVENT2}/rewards/r9`), {
      fromName: 'Pat', title: 'A private gift', pointCost: 50, contentType: 'video',
      isUnlocked: false, sortOrder: 0, badgeIllustration: 'b', createdAt: new Date(),
      fetchedBy: [],
    });
    await setDoc(doc(db, `inviteCodes/${CODE2}`), { eventId: EVENT2, kind: 'contributor' });
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

  it('lets a joiner self-register by presenting a valid code', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Jordan', avatarId: 'a2', mode: 'contributor', isHost: false, usedCode: CODE,
    }));
  });

  it('lets the celebrant self-register with the celebrant code', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Alex', avatarId: 'a2', mode: 'celebrant', isHost: false, usedCode: CELEB_CODE,
    }));
  });

  it('denies self-registering with a bogus code', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Jordan', avatarId: 'a2', mode: 'contributor', isHost: false, usedCode: 'WRONG123',
    }));
  });

  it('denies claiming celebrant with the contributor code', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Jordan', avatarId: 'a2', mode: 'celebrant', isHost: false, usedCode: CODE,
    }));
  });

  it('denies joining a closed occasion with a valid code', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), `events/${EVENT}`), { isOpen: false });
    });
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Jordan', avatarId: 'a2', mode: 'contributor', isHost: false, usedCode: CODE,
    }));
  });

  it('denies creating a participant document for someone else', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${OUTSIDER}`), {
      name: 'X', avatarId: 'a2', mode: 'contributor', isHost: false, usedCode: CODE,
    }));
  });

  it('denies self-promotion to host', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Jordan', avatarId: 'a2', mode: 'contributor', isHost: true, usedCode: CODE,
    }));
  });

  it('denies a non-host creating a reward', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
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

// The architectural claim the whole subcollection layout rests on: belonging to one occasion
// buys you nothing in anybody else's. Note these use a genuine member of evt_1, not a user
// who belongs to no event at all.
describe('cross-event isolation', () => {
  beforeEach(seed);

  it("denies a member of one event reading another event", async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT2}`)));
  });

  it("denies a member of one event reading another event's rewards", async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT2}/rewards/r9`)));
  });

  it("denies a member of one event writing into another event", async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT2}/challenges/c1`), {
      title: 'injected', description: 'x', pointValue: 50, isSecret: false,
    }));
  });

  it("denies a member of one event reading another event's participants", async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT2}/participants/${HOST2}`)));
  });
});

// inviteCodes has exactly one job: guarantee code uniqueness and let a client turn a code it
// already holds into an eventId. Resolution is a single-document get; enumeration is not.
describe('invite code resolution', () => {
  beforeEach(seed);

  it('lets a signed-in client resolve one code it already holds', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(getDoc(doc(db, `inviteCodes/${CODE}`)));
  });

  it('denies enumerating the invite code collection', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(getDocs(collection(db, 'inviteCodes')));
  });

  it('denies an unauthenticated code lookup', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `inviteCodes/${CODE}`)));
  });

  it('lets the host revoke a code', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(deleteDoc(doc(db, `inviteCodes/${CODE}`)));
  });

  it('denies a non-host revoking a code', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(deleteDoc(doc(db, `inviteCodes/${CODE}`)));
  });

  it('denies the celebrant revoking their own code', async () => {
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertFails(deleteDoc(doc(db, `inviteCodes/${CELEB_CODE}`)));
  });
});

// Codes are authorised against the event document, which only the host can write. Minting an
// inviteCodes doc is deliberately open (Task 7 mints codes before the event exists), so a
// forged one must buy nothing. The invite deep link publishes the eventId in plaintext, so
// assume every contributor knows it.
describe('forged invite codes buy nothing', () => {
  beforeEach(seed);

  it('denies claiming celebrant via a self-minted invite code document', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(setDoc(doc(db, 'inviteCodes/FORGED99'), {
      eventId: EVENT, kind: 'celebrant',
    }));
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${OUTSIDER}`), {
      name: 'Mallory', avatarId: 'a5', mode: 'celebrant', isHost: false, usedCode: 'FORGED99',
    }));
  });

  it('denies joining at all via a self-minted invite code document', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await setDoc(doc(db, 'inviteCodes/FORGED98'), { eventId: EVENT, kind: 'contributor' });
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${OUTSIDER}`), {
      name: 'Mallory', avatarId: 'a5', mode: 'contributor', isHost: false, usedCode: 'FORGED98',
    }));
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

// hostUid is the root of authority: participant-create, state-create and membership-create all
// resolve it. A host who could rewrite it could mint a second host.
describe('hostUid is immutable', () => {
  beforeEach(seed);

  it('lets the host edit the occasion', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}`), { name: 'Renamed' }));
  });

  it('denies the host reassigning hostUid', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}`), { hostUid: OUTSIDER }));
  });

  it('denies the host reassigning hostUid alongside a legitimate edit', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}`), {
      name: 'Renamed', hostUid: OUTSIDER,
    }));
  });
});

// The celebrant code is single-use, and the claim is consumed on the event document — the one
// place only the host can otherwise write. Clearing the field is the only write a non-host
// member is allowed to make to the event.
describe('single-use celebrant code', () => {
  beforeEach(seed);

  it('lets the celebrant consume the code by clearing it', async () => {
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}`), { celebrantCode: '' }));
  });

  it('denies a contributor clearing the celebrant code', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}`), { celebrantCode: '' }));
  });

  it('denies a non-member clearing the celebrant code', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}`), { celebrantCode: '' }));
  });

  it('denies the celebrant editing any other field', async () => {
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}`), { name: 'Hijacked' }));
  });

  it('denies the celebrant closing the occasion under cover of consuming the code', async () => {
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}`), {
      celebrantCode: '', isOpen: false,
    }));
  });

  it('denies the celebrant rewriting the code to a value of their choosing', async () => {
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}`), { celebrantCode: 'MINE2345' }));
  });

  it('denies a second claim once the code is consumed', async () => {
    const celebrantDb = testEnv.authenticatedContext(CELEBRANT).firestore();
    await updateDoc(doc(celebrantDb, `events/${EVENT}`), { celebrantCode: '' });

    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${OUTSIDER}`), {
      name: 'Mallory', avatarId: 'a5', mode: 'celebrant', isHost: false, usedCode: CELEB_CODE,
    }));
  });

  it('denies claiming celebrant with an empty code once consumed', async () => {
    const celebrantDb = testEnv.authenticatedContext(CELEBRANT).firestore();
    await updateDoc(doc(celebrantDb, `events/${EVENT}`), { celebrantCode: '' });

    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${OUTSIDER}`), {
      name: 'Mallory', avatarId: 'a5', mode: 'celebrant', isHost: false, usedCode: '',
    }));
  });
});
