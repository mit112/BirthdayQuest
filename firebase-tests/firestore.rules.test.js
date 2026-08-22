import { readFileSync } from 'node:fs';
import { beforeAll, afterAll, beforeEach, describe, it, expect } from 'vitest';
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
    // No codes on the event document: it is member-readable, and an invite code is a bearer
    // secret. They live in events/{id}/private/codes, which only the host can read.
    await setDoc(doc(db, `events/${EVENT}`), {
      name: "Alex's 30th", occasionType: 'birthday', celebrantName: 'Alex',
      hostUid: HOST, occasionDate: new Date(), isOpen: true, createdAt: new Date(),
    });
    await setDoc(doc(db, `events/${EVENT}/private/codes`), {
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
    await setDoc(doc(db, `events/${EVENT}/challenges/c1`), {
      title: 'Sing', description: 'x', pointValue: 50, isSecret: false, isCompleted: false,
    });
    await setDoc(doc(db, `events/${EVENT}/timeline/t1`), {
      type: 'reward_unlocked', referenceId: 'r1', title: 'x', subtitle: 'y',
      badgeType: 'reward', badgeAsset: 'b', timestamp: new Date(),
    });
    await setDoc(doc(db, `events/${EVENT}/state/main`), {
      currentPoints: 100, totalPointsEarned: 100, totalPointsSpent: 0, updatedAt: new Date(),
    });

    // A completely unrelated stranger's occasion. Nobody from evt_1 belongs to it.
    await setDoc(doc(db, `events/${EVENT2}`), {
      name: "Someone else's wedding", occasionType: 'wedding', celebrantName: 'Kim',
      hostUid: HOST2, occasionDate: new Date(), isOpen: true, createdAt: new Date(),
    });
    await setDoc(doc(db, `events/${EVENT2}/private/codes`), {
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

  it('denies switching your own play mode to celebrant', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      mode: 'celebrant',
    }));
  });

  it('denies editing the timeline once written', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/timeline/t1`), { title: 'tampered' }));
  });
});

// Positive coverage for the three content collections. Every assertion about them used to be
// assertFails, which meant a one-character typo in `match /rewards/{rewardId}` routed the
// whole block to the catch-all deny, left the suite green, and 403'd the entire gift feature
// in production. Mutation-tested: renaming any of the three match blocks fails a test here.
describe('content collections are reachable', () => {
  beforeEach(seed);

  it('lets a member read a challenge', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(getDoc(doc(db, `events/${EVENT}/challenges/c1`)));
  });

  it('lets a member list challenges', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(getDocs(collection(db, `events/${EVENT}/challenges`)));
  });

  it('lets a member create a secret challenge', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(setDoc(doc(db, `events/${EVENT}/challenges/c2`), {
      title: 'Secret dare', description: 'x', pointValue: 50, isSecret: true,
      isCompleted: false, createdByUserId: GUEST,
    }));
  });

  it('lets a member complete a challenge', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/challenges/c1`), {
      isCompleted: true,
    }));
  });

  it('lets the host delete a challenge', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(deleteDoc(doc(db, `events/${EVENT}/challenges/c1`)));
  });

  it('lets a member read a reward', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(getDoc(doc(db, `events/${EVENT}/rewards/r1`)));
  });

  it('lets a member list rewards', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(getDocs(collection(db, `events/${EVENT}/rewards`)));
  });

  it('lets the host create a reward', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(setDoc(doc(db, `events/${EVENT}/rewards/r2`), {
      fromName: 'Sam', title: 'x', pointCost: 50, contentType: 'video',
      isUnlocked: false, sortOrder: 1, badgeIllustration: 'b', createdAt: new Date(),
      fetchedBy: [],
    }));
  });

  it('lets a member unlock a reward', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/rewards/r1`), {
      isUnlocked: true,
    }));
  });

  it('lets the host delete a reward', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(deleteDoc(doc(db, `events/${EVENT}/rewards/r1`)));
  });

  it('lets a member read the timeline', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(getDocs(collection(db, `events/${EVENT}/timeline`)));
  });

  it('lets a member append to the timeline', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(setDoc(doc(db, `events/${EVENT}/timeline/t2`), {
      type: 'challenge_completed', referenceId: 'c1', title: 'x', subtitle: 'y',
      badgeType: 'challenge', badgeAsset: 'b', timestamp: new Date(),
    }));
  });

  it('lets a member read and update the game state', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(getDoc(doc(db, `events/${EVENT}/state/main`)));
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/state/main`), {
      currentPoints: 150,
    }));
  });
});

// The content/gameplay split. Before this, `challenges` and `rewards` were the only
// collections in the file with no field validation at all: any member could rewrite any
// challenge's point value or any gift's price. Both directions are asserted for every
// clause, because a deny-all baseline passes every assertFails for the wrong reason.
describe('content is author-scoped, gameplay is member-scoped', () => {
  beforeEach(seed);

  // Gives GUEST a challenge they actually authored, so the author branch has something
  // to match against. Written with rules disabled: the point is to test editing, not
  // creating.
  async function seedGuestChallenge() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `events/${EVENT}/challenges/c_guest`), {
        title: 'Guest dare', description: 'x', pointValue: 30, isSecret: true,
        isCompleted: false, isDelivered: false, createdByUserId: GUEST,
        createdAt: new Date(),
      });
    });
  }

  it('lets the author edit their own challenge content', async () => {
    await joinAsContributor(GUEST);
    await seedGuestChallenge();
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/challenges/c_guest`), {
      title: 'A better dare', pointValue: 40,
    }));
  });

  it('denies a member editing a challenge they did not author', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    // c1 is seeded with no createdByUserId at all, so nobody is its author.
    await assertFails(updateDoc(doc(db, `events/${EVENT}/challenges/c1`), {
      pointValue: 9999,
    }));
  });

  it('lets the host edit any challenge content', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/challenges/c1`), {
      title: 'Host rewrote this', pointValue: 75,
    }));
  });

  it('still lets any member complete a challenge they did not author', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/challenges/c1`), {
      isCompleted: true, completedAt: new Date(), proofText: 'done',
    }));
  });

  it('denies smuggling a content field inside a gameplay write', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/challenges/c1`), {
      isCompleted: true, pointValue: 9999,
    }));
  });

  it('denies reassigning a challenge\'s author', async () => {
    await joinAsContributor(GUEST);
    await seedGuestChallenge();
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/challenges/c_guest`), {
      createdByUserId: HOST,
    }));
  });

  it('denies flipping a challenge\'s secrecy after the fact', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/challenges/c1`), {
      isSecret: true,
    }));
  });

  it('denies creating a challenge in someone else\'s name', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/challenges/c3`), {
      title: 'Framed', description: 'x', pointValue: 10, isSecret: true,
      isCompleted: false, isDelivered: false, createdByUserId: HOST,
      createdAt: new Date(),
    }));
  });

  it('denies a member creating a NON-secret challenge', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/challenges/c4`), {
      title: 'Not my job', description: 'x', pointValue: 10, isSecret: false,
      isCompleted: false, isDelivered: false, createdByUserId: GUEST,
      createdAt: new Date(),
    }));
  });

  it('lets the host create a non-secret challenge', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(setDoc(doc(db, `events/${EVENT}/challenges/c5`), {
      title: 'Sing in public', description: 'Somewhere busy', pointValue: 50,
      difficulty: 'medium', category: 'social', illustrationAsset: 'music.mic',
      isSecret: false, isCompleted: false, isDelivered: true,
      createdByUserId: HOST, createdAt: new Date(),
    }));
  });

  it('denies a challenge with an empty title', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/challenges/c6`), {
      title: '', description: 'x', pointValue: 10, isSecret: false,
      isCompleted: false, isDelivered: true, createdByUserId: HOST,
      createdAt: new Date(),
    }));
  });

  it('denies a challenge with an absurd point value', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/challenges/c7`), {
      title: 'Cheat', description: 'x', pointValue: 999999, isSecret: false,
      isCompleted: false, isDelivered: true, createdByUserId: HOST,
      createdAt: new Date(),
    }));
  });

  // The remaining five create-validation clauses. Each payload is legal in every respect
  // except the one clause under test, and each wrong value is chosen so that deleting that
  // clause lets the write through rather than erroring: a list still answers size(), and a
  // double still answers >=. A string-typed near-miss would deny either way and prove nothing.
  it('denies a challenge with an over-long title', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/challenges/c8`), {
      title: 'x'.repeat(121), description: 'x', pointValue: 10, isSecret: false,
      isCompleted: false, isDelivered: true, createdByUserId: HOST,
      createdAt: new Date(),
    }));
  });

  it('denies a challenge whose description is not a string', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/challenges/c9`), {
      title: 'Typed wrong', description: ['x'], pointValue: 10, isSecret: false,
      isCompleted: false, isDelivered: true, createdByUserId: HOST,
      createdAt: new Date(),
    }));
  });

  it('denies a challenge with an over-long description', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/challenges/c10`), {
      title: 'Wordy', description: 'x'.repeat(2001), pointValue: 10, isSecret: false,
      isCompleted: false, isDelivered: true, createdByUserId: HOST,
      createdAt: new Date(),
    }));
  });

  it('denies a challenge with a fractional point value', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/challenges/c11`), {
      title: 'Half a point', description: 'x', pointValue: 10.5, isSecret: false,
      isCompleted: false, isDelivered: true, createdByUserId: HOST,
      createdAt: new Date(),
    }));
  });

  it('denies a challenge with a negative point value', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/challenges/c12`), {
      title: 'Debt', description: 'x', pointValue: -5, isSecret: false,
      isCompleted: false, isDelivered: true, createdByUserId: HOST,
      createdAt: new Date(),
    }));
  });

  async function seedGuestGift() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `events/${EVENT}/rewards/r_guest`), {
        fromUserId: GUEST, fromName: 'Jordan', title: 'A letter', teaser: 'Open me',
        pointCost: 40, contentType: 'text', contentText: 'Dear Alex...',
        isUnlocked: false, sortOrder: 2, badgeIllustration: 'envelope.fill',
        createdAt: new Date(), fetchedBy: [],
      });
    });
  }

  it('lets a member create the gift that is from them', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(setDoc(doc(db, `events/${EVENT}/rewards/r_new`), {
      fromUserId: GUEST, fromName: 'Jordan', title: 'A letter', teaser: 'Open me',
      pointCost: 0, contentType: 'text', contentText: 'Dear Alex...',
      isUnlocked: false, sortOrder: 0, badgeIllustration: 'envelope.fill',
      createdAt: new Date(), fetchedBy: [],
    }));
  });

  it('denies a member creating a gift in someone else\'s name', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/rewards/r_forged`), {
      fromUserId: CELEBRANT, fromName: 'Alex', title: 'Not mine', teaser: 't',
      pointCost: 0, contentType: 'text', contentText: 'x',
      isUnlocked: false, sortOrder: 0, badgeIllustration: 'b',
      createdAt: new Date(), fetchedBy: [],
    }));
  });

  // Create just widened from host-only to any member, so membership is now the only thing
  // standing between a stranger and the gift list. The test this replaces asserted a
  // contributor could not create at all; nothing else asserts a non-member cannot.
  it('denies a non-member creating a gift, even in their own name', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/rewards/r_stranger`), {
      fromUserId: OUTSIDER, fromName: 'Nobody', title: 'Uninvited', teaser: 't',
      pointCost: 0, contentType: 'text', contentText: 'x',
      isUnlocked: false, sortOrder: 0, badgeIllustration: 'b',
      createdAt: new Date(), fetchedBy: [],
    }));
  });

  it('lets the author edit their own gift\'s text', async () => {
    await joinAsContributor(GUEST);
    await seedGuestGift();
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/rewards/r_guest`), {
      contentText: 'Dear Alex, actually...', title: 'A better letter',
    }));
  });

  it('denies the author repricing their own gift', async () => {
    await joinAsContributor(GUEST);
    await seedGuestGift();
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/rewards/r_guest`), {
      pointCost: 1,
    }));
  });

  it('lets the host reprice and reorder any gift', async () => {
    await joinAsContributor(GUEST);
    await seedGuestGift();
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/rewards/r_guest`), {
      pointCost: 120, sortOrder: 5,
    }));
  });

  it('denies a member editing a gift they did not write', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    // r1 is seeded with no fromUserId, so nobody is its author.
    await assertFails(updateDoc(doc(db, `events/${EVENT}/rewards/r1`), {
      contentText: 'tampered',
    }));
  });

  it('still lets any member unlock a gift', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/rewards/r1`), {
      isUnlocked: true, unlockedAt: new Date(),
    }));
  });

  it('still lets any member record a fetch, for the media purge', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/rewards/r1`), {
      fetchedBy: [GUEST],
    }));
  });

  it('denies smuggling a price change inside an unlock', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/rewards/r1`), {
      isUnlocked: true, pointCost: 0,
    }));
  });

  it('denies reassigning a gift\'s author', async () => {
    await joinAsContributor(GUEST);
    await seedGuestGift();
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/rewards/r_guest`), {
      fromUserId: HOST,
    }));
  });

  it('denies a gift with an unknown content type', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/rewards/r_bad`), {
      fromUserId: GUEST, fromName: 'Jordan', title: 'x', teaser: 't',
      pointCost: 0, contentType: 'executable', contentText: 'x',
      isUnlocked: false, sortOrder: 0, badgeIllustration: 'b',
      createdAt: new Date(), fetchedBy: [],
    }));
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

  it("denies the host of one event reading another event's invite codes", async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT2}/private/codes`)));
  });
});

// THE fix. An invite code is a bearer secret: whoever holds the celebrant code can claim
// celebrant, and the celebrant can delete every gift in Storage. The contributor link is
// designed to be reusable and broadly shared, so "every member" is "every recipient of a
// group-chat link". Codes therefore cannot live anywhere a member can read.
describe('invite codes are host-only', () => {
  beforeEach(seed);

  it('lets the host read the invite codes', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(getDoc(doc(db, `events/${EVENT}/private/codes`)));
  });

  it('denies a contributor reading the invite codes', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT}/private/codes`)));
  });

  it('denies the celebrant reading the invite codes', async () => {
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT}/private/codes`)));
  });

  it('denies a non-member reading the invite codes', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT}/private/codes`)));
  });

  it('denies a member enumerating the private subcollection', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(getDocs(collection(db, `events/${EVENT}/private`)));
  });

  it('carries no codes on the member-readable event document', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    const snap = await getDoc(doc(db, `events/${EVENT}`));
    expect(snap.data().contributorCode).toBeUndefined();
    expect(snap.data().celebrantCode).toBeUndefined();
  });

  it('denies a member writing the invite codes', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/private/codes`), {
      contributorCode: 'MINE2345',
    }));
  });

  it('lets the host rotate the invite codes', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/private/codes`), {
      contributorCode: 'NEWC2345',
    }));
  });

  it('denies deleting the codes document outright', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(deleteDoc(doc(db, `events/${EVENT}/private/codes`)));
  });

  it('denies squatting a second document in the private subcollection', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/private/notcodes`), { x: 1 }));
  });

  // Pins the `docId == 'codes'` clause on update, which the create rule alone cannot: an
  // update only fires on a document that exists, and only 'codes' can be created. Seeded
  // out of band so the clause is testable rather than merely plausible.
  it('denies writing any other document in the private subcollection', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `events/${EVENT}/private/notcodes`), { x: 1 });
    });
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/private/notcodes`), { x: 2 }));
  });

  // The enabling fact this whole design rests on. Rules-internal get() is PRIVILEGED: it is
  // not itself subject to these rules. So the participant-create rule can compare the
  // presented code against a document the joiner is explicitly denied read access to. If
  // that were false, the fix would be impossible and this test would fail.
  it('authorises a join against a document the joiner cannot read', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT}/private/codes`)));
    await assertSucceeds(setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Jordan', avatarId: 'a2', mode: 'contributor', isHost: false, usedCode: CODE,
    }));
  });
});

// Second harvest door, same secret. Every participant document carries `usedCode`, the code
// its owner presented — so a member-readable roster leaks the celebrant code out of the
// celebrant's own row. The roster is host-only functionality, so read is host-or-self.
describe('the roster is host-only', () => {
  beforeEach(seed);

  it('lets the host list the roster', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(getDocs(collection(db, `events/${EVENT}/participants`)));
  });

  it('lets the host read one participant', async () => {
    const db = testEnv.authenticatedContext(HOST).firestore();
    await assertSucceeds(getDoc(doc(db, `events/${EVENT}/participants/${CELEBRANT}`)));
  });

  it('lets a member read their own participant document', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(getDoc(doc(db, `events/${EVENT}/participants/${GUEST}`)));
  });

  it('denies a contributor listing the roster', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(getDocs(collection(db, `events/${EVENT}/participants`)));
  });

  it("denies a contributor reading the celebrant's row, which carries their invite code", async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT}/participants/${CELEBRANT}`)));
  });

  it('denies a non-member reading any participant', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, `events/${EVENT}/participants/${HOST}`)));
  });
});

// inviteCodes has exactly one job: guarantee code uniqueness and let a client turn a code it
// already holds into an eventId. Resolution is a single-document get; enumeration is not.
// Authorisation never flows through here.
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

// Codes are authorised against events/{id}/private/codes, which only the host can write.
// Minting an inviteCodes doc is deliberately open (codes are minted before the event exists),
// so a forged one must buy nothing. The invite deep link publishes the eventId in plaintext,
// so assume every contributor knows it.
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
// writes the host participant, the codes document, the state doc, and the membership index.
// Firestore evaluates every write in a batch against COMMITTED state, so nothing in that
// batch may depend on the participant document the same batch is creating. Codes, state and
// membership creation are therefore gated on the event's hostUid, not on membership.
describe('two-phase occasion creation', () => {
  beforeEach(seed);

  it('allows creating an event you host', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(setDoc(doc(db, 'events/evt_new'), {
      name: 'A party', occasionType: 'birthday', celebrantName: 'Kim',
      hostUid: GUEST, occasionDate: new Date(), isOpen: true, createdAt: new Date(),
    }));
  });

  it('denies creating an event owned by someone else', async () => {
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, 'events/evt_new'), {
      name: 'A party', occasionType: 'birthday', celebrantName: 'Kim',
      hostUid: OUTSIDER, occasionDate: new Date(), isOpen: true, createdAt: new Date(),
    }));
  });

  it('lets the host commit phase two as one batch against a bare event document', async () => {
    // Phase 1 committed the event and nothing else — no participant document, no codes.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), `events/${EVENT}/participants/${HOST}`));
      await deleteDoc(doc(ctx.firestore(), `events/${EVENT}/private/codes`));
      await deleteDoc(doc(ctx.firestore(), `events/${EVENT}/state/main`));
    });

    const db = testEnv.authenticatedContext(HOST).firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, `events/${EVENT}/participants/${HOST}`), {
      name: 'Sam', avatarId: 'a1', mode: 'contributor', isHost: true, usedCode: CODE,
    });
    batch.set(doc(db, `events/${EVENT}/private/codes`), {
      contributorCode: CODE, celebrantCode: CELEB_CODE,
    });
    batch.set(doc(db, `events/${EVENT}/state/main`), {
      totalPoints: 0, completedChallengeIds: [], unlockedRewardIds: [], updatedAt: new Date(),
    });
    batch.set(doc(db, `memberships/${HOST}/events/${EVENT}`), {
      role: 'contributor', isHost: true, joinedAt: new Date(),
    });
    await assertSucceeds(batch.commit());
  });

  it('denies a signed-in non-host creating the codes document', async () => {
    // Join first: joining resolves the codes document, so it has to still exist for that.
    await joinAsContributor(GUEST);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), `events/${EVENT}/private/codes`));
    });
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/private/codes`), {
      contributorCode: 'MINE2345', celebrantCode: 'MINE6789',
    }));
  });

  it('denies a signed-in non-host creating the state document', async () => {
    await joinAsContributor(GUEST);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), `events/${EVENT}/state/main`));
    });
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
      role: 'contributor', isHost: false, joinedAt: new Date(),
    }));
  });

  // Rejoin after removal. The client writes this row with setData unconditionally, which is
  // an UPDATE whenever the row already exists — and it does for anyone the host removed and
  // then re-invited, because no rule lets the host delete the mirror. `allow update: if
  // false` therefore bricked rejoin: the participant create succeeded, this write threw raw
  // permission-denied, and the user was told their invite was invalid while already being a
  // member in Firestore.
  it('lets the owner rewrite their own membership row when rejoining', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(setDoc(doc(db, `memberships/${GUEST}/events/${EVENT}`), {
      role: 'contributor', isHost: false, joinedAt: new Date(),
    }));
    // Second write, same path: this is the update that used to be denied.
    await assertSucceeds(setDoc(doc(db, `memberships/${GUEST}/events/${EVENT}`), {
      role: 'contributor', isHost: false, joinedAt: new Date(),
    }));
  });

  it("denies another user updating an existing membership row", async () => {
    await joinAsContributor(GUEST);
    const guestDb = testEnv.authenticatedContext(GUEST).firestore();
    await setDoc(doc(guestDb, `memberships/${GUEST}/events/${EVENT}`), {
      role: 'contributor', isHost: false, joinedAt: new Date(),
    });

    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(updateDoc(doc(db, `memberships/${GUEST}/events/${EVENT}`), {
      isHost: true,
    }));
  });
});

// hostUid is the root of authority: participant-create, codes-create, state-create and
// membership-create all resolve it. A host who could rewrite it could mint a second host.
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

  it('denies a non-host member editing the event document at all', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}`), { name: 'Hijacked' }));
  });

  it('denies the celebrant editing the event document', async () => {
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}`), { isOpen: false }));
  });
});

// The celebrant code is single-use, and the claim is consumed on the codes document — the one
// write a non-host member is allowed to make there. Note the celebrant can UPDATE that
// document but cannot READ it: diff() is evaluated server-side.
describe('single-use celebrant code', () => {
  beforeEach(seed);

  it('lets the celebrant consume the code by clearing it', async () => {
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/private/codes`), {
      celebrantCode: '',
    }));
  });

  // The client retries this on every occasion open, because it cannot read the document to
  // find out whether the first attempt landed. Re-clearing an already-empty code produces an
  // empty diff, which hasOnly() accepts — so the retry is a permitted no-op rather than a
  // permission-denied the client would log as a failure forever.
  it('lets the celebrant re-clear an already-consumed code', async () => {
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/private/codes`), {
      celebrantCode: '',
    }));
    await assertSucceeds(updateDoc(doc(db, `events/${EVENT}/private/codes`), {
      celebrantCode: '',
    }));
  });

  it('denies a contributor clearing the celebrant code', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/private/codes`), {
      celebrantCode: '',
    }));
  });

  it('denies a non-member clearing the celebrant code', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/private/codes`), {
      celebrantCode: '',
    }));
  });

  it('denies the celebrant editing the contributor code under cover of consuming theirs', async () => {
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/private/codes`), {
      celebrantCode: '', contributorCode: 'MINE2345',
    }));
  });

  // The celebrant branch is scoped to the 'codes' document too, not just the host branch.
  // Unreachable while only 'codes' can be created, but "unreachable today" is exactly the
  // assumption this whole change exists to stop trusting — so it is pinned rather than
  // reasoned about. Seeded out of band, since the create rule refuses to make the decoy.
  it('denies the celebrant clearing a celebrantCode on any other private document', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `events/${EVENT}/private/decoy`), {
        celebrantCode: CELEB_CODE,
      });
    });
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/private/decoy`), {
      celebrantCode: '',
    }));
  });

  it('denies the celebrant rewriting the code to a value of their choosing', async () => {
    const db = testEnv.authenticatedContext(CELEBRANT).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/private/codes`), {
      celebrantCode: 'MINE2345',
    }));
  });

  it('denies a second claim once the code is consumed', async () => {
    const celebrantDb = testEnv.authenticatedContext(CELEBRANT).firestore();
    await updateDoc(doc(celebrantDb, `events/${EVENT}/private/codes`), { celebrantCode: '' });

    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${OUTSIDER}`), {
      name: 'Mallory', avatarId: 'a5', mode: 'celebrant', isHost: false, usedCode: CELEB_CODE,
    }));
  });

  it('denies claiming celebrant with an empty code once consumed', async () => {
    const celebrantDb = testEnv.authenticatedContext(CELEBRANT).firestore();
    await updateDoc(doc(celebrantDb, `events/${EVENT}/private/codes`), { celebrantCode: '' });

    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${OUTSIDER}`), {
      name: 'Mallory', avatarId: 'a5', mode: 'celebrant', isHost: false, usedCode: '',
    }));
  });
});

// The privilege-escalation chain this whole change exists to break, replayed step by step.
// Originally: a contributor read the celebrant code off the event document, handed it to a
// fresh anonymous uid, and that impostor claimed celebrant — from where the Storage rules let
// it delete every gift and every proof photo, and clear the code so the real celebrant's
// single-use link was dead. The contributor link is meant to be reusable and broadly shared,
// so "a contributor" is "anyone in the group chat".
describe('privilege escalation chain is broken', () => {
  beforeEach(seed);

  it('step 1: a member reading the event obtains no code', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    const snap = await getDoc(doc(db, `events/${EVENT}`));
    expect(snap.exists()).toBe(true);
    expect(snap.data().celebrantCode).toBeUndefined();
    expect(snap.data().contributorCode).toBeUndefined();
    await assertFails(getDoc(doc(db, `events/${EVENT}/private/codes`)));
    await assertFails(getDoc(doc(db, `events/${EVENT}/participants/${CELEBRANT}`)));
  });

  it('step 2: a member cannot promote their own row to celebrant', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      mode: 'celebrant',
    }));
  });

  it('step 3: a fresh uid guessing the celebrant code cannot claim celebrant', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${OUTSIDER}`), {
      name: 'Mallory', avatarId: 'a5', mode: 'celebrant', isHost: false, usedCode: 'GUESS234',
    }));
  });

  it('step 4: a member who is not the celebrant cannot become one to reach the media', async () => {
    // Storage's isCelebrant() reads participants/{uid}.mode, and mode is immutable after
    // create (step 2) and only settable to 'celebrant' with the celebrant code (step 3).
    // So the media-delete privilege is unreachable without the code itself.
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    const own = await getDoc(doc(db, `events/${EVENT}/participants/${GUEST}`));
    expect(own.data().mode).toBe('contributor');
    await assertFails(setDoc(doc(db, `events/${EVENT}/participants/${GUEST}`), {
      name: 'Jordan', avatarId: 'a2', mode: 'celebrant', isHost: false, usedCode: CELEB_CODE,
    }));
  });

  it("step 5: a member cannot clear the celebrant code and kill the real celebrant's link", async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertFails(updateDoc(doc(db, `events/${EVENT}/private/codes`), {
      celebrantCode: '',
    }));
    await assertFails(updateDoc(doc(db, `events/${EVENT}`), { celebrantCode: '' }));
  });
});
