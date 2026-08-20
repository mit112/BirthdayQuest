# Event Scoping and Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Any user can create an occasion, invite friends who self-register on their own devices, and run it in complete isolation from every other occasion in the app.

**Architecture:** All event data moves under `events/{eventId}` subcollections so cross-event access is impossible by path rather than by query discipline. Identity becomes a Firebase anonymous uid (upgradeable to Sign in with Apple), replacing the device-locked character claim. Security rules carry all enforcement — there are no Cloud Functions — so rules are developed test-first against the Firebase emulator.

**Tech Stack:** Swift 5 / SwiftUI, iOS 26.0 target, Firebase (Auth, Firestore, Storage), `@firebase/rules-unit-testing` + vitest for rules tests, Swift Testing / XCTest for app tests.

**Spec:** `docs/superpowers/specs/2026-08-20-multi-tenant-occasions-design.md` (commit `436302c`)

## Global Constraints

- Deployment target iOS 26.0; Swift 5 language mode. Source root `BirthdayQuest/BirthdayQuest/`.
- Value types (struct/enum) over classes. `async`/`await`, never GCD.
- `OSLog` `Logger` only — never `print()`. Subsystem `com.example.birthdayquest`.
- Never reference `FirestoreService.shared` outside a DI default argument. Inject `GameBackend`.
- Views must not touch the backend. ViewModels are `@MainActor final class`.
- All UI tokens come from the `BQDesign` namespace. No hardcoded colors, spacing, or fonts.
- Firestore timestamps: `Timestamp(date: Date())`. Never `FieldValue.serverTimestamp()` — it breaks `Codable`.
- `GameState` is parsed by manual dictionary parsing with `NSNumber?.intValue`, never `Codable` (Int64/NSNumber mismatch).
- Every commit must be SwiftLint-clean per `.swiftlint.yml`.
- No AI attribution in commit messages, branches, or tags. No `Co-Authored-By` trailers.
- Build: `xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- App tests: same command with `test` instead of `build`.
- Rules tests: `cd firebase-tests && npm test` (requires `firebase emulators:exec`).

## Deviations from the spec

Two changes discovered while planning. Both are improvements; both are implemented as written here rather than as the spec describes.

1. **`events/{eventId}.celebrantUid` is removed.** The spec listed it alongside `participants/{uid}.mode == .celebrant`, which is two sources of truth for one fact. The celebrant is derived by querying participants. `celebrantName` stays, because the host needs a display name before the celebrant has joined.

2. **Occasion creation is two-phase, not one atomic batch.** The spec implied a single `WriteBatch`. That cannot work: Firestore evaluates rules for each write in a batch against *committed* state, so a rule using `get()` on the event document cannot see an event created in the same batch. Phase 1 creates the event document alone; phase 2 batches the host participant, both invite codes, and `state/main`. A phase-2 failure leaves an orphan event document that no client can read (membership check fails), so it is invisible and harmless. The client retries phase 2.

## File Structure

**New Swift files**
- `Models/Occasion.swift` — `Occasion`, `OccasionType`
- `Models/Participant.swift` — `Participant`, `ParticipantMode`
- `Services/AuthService.swift` — anonymous sign-in, Apple linking; `AuthProviding` protocol
- `Services/AppSession.swift` — auth state, occasion list, root routing
- `Services/EventSession.swift` — one occasion's scope and listeners
- `Views/Occasions/OccasionListView.swift` — "My Occasions"
- `Views/Occasions/CreateOccasionView.swift`
- `Views/Occasions/JoinOccasionView.swift` — code entry, name, avatar pick
- `Views/Occasions/EventContainerView.swift` — routes on `mode`

**New test files**
- `firebase-tests/package.json`, `firebase-tests/vitest.config.js`
- `firebase-tests/firestore.rules.test.js`
- `firebase-tests/storage.rules.test.js`

**Modified**
- `firestore.rules`, `storage.rules`, `firebase.json`, `.github/workflows/ci.yml`
- `AppConstants.swift` — paths and invite-code alphabet; `CharacterID` deleted
- `Services/GameBackend.swift` — `eventId` on every method; `Result` completions
- `Services/FirestoreService.swift` — event-scoped paths
- `Services/SessionManager.swift` — deleted, replaced by `AppSession` + `EventSession`
- `Models/Reward.swift` — `fetchedBy`; `defaultPointCost` deleted
- `ContentView.swift`, `BirthdayQuestApp.swift`
- `Views/Components/AvatarView.swift` — bundled avatars, DiceBear removed
- `BirthdayQuestTests/MockGameBackend.swift`, `BirthdayQuestTests/ViewModelTests.swift`

**Deleted**
- `Services/DataSeeder.swift` — global seeding is replaced by per-event creation
- `ViewModels/CharacterSelectViewModel.swift` — PIN override and claim flow

---

### Task 1: Emulator test harness, with current rules pinned as broken

Establishes the rules test suite and locks in the audit's finding that today's rules make the seeder impossible. This test documents the bug, then Task 2 replaces the rules and the test is rewritten to assert the new contract.

**Files:**
- Create: `firebase-tests/package.json`
- Create: `firebase-tests/vitest.config.js`
- Create: `firebase-tests/firestore.rules.test.js`
- Modify: `firebase.json`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: nothing
- Produces: `npm test` in `firebase-tests/` runs rules tests against the emulator. Later tasks add cases to `firestore.rules.test.js` and `storage.rules.test.js`.

- [ ] **Step 1: Create the test package**

`firebase-tests/package.json`:

```json
{
  "name": "birthdayquest-rules-tests",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "firebase emulators:exec --only firestore,storage --project birthdayquest-test 'vitest run'"
  },
  "devDependencies": {
    "@firebase/rules-unit-testing": "^4.0.1",
    "firebase": "^11.0.0",
    "vitest": "^2.1.0"
  }
}
```

`firebase-tests/vitest.config.js`:

```js
export default {
  test: {
    environment: 'node',
    testTimeout: 20000,
    hookTimeout: 20000,
  },
};
```

- [ ] **Step 2: Add emulator configuration**

Replace `firebase.json` with:

```json
{
  "firestore": { "rules": "firestore.rules" },
  "storage": { "rules": "storage.rules" },
  "emulators": {
    "firestore": { "port": 8080 },
    "storage": { "port": 9199 },
    "ui": { "enabled": false }
  }
}
```

- [ ] **Step 3: Write the test that documents the seeder bug**

`firebase-tests/firestore.rules.test.js`:

```js
import { readFileSync } from 'node:fs';
import { beforeAll, afterAll, beforeEach, describe, it } from 'vitest';
import {
  initializeTestEnvironment,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';

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

describe('current rules (pre-migration)', () => {
  it('denies creating a user document, which is what DataSeeder.seedUsers does', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(db, 'users/alex'), { name: 'Alex', role: 'birthday_boy' })
    );
  });
});
```

- [ ] **Step 4: Run it and confirm it passes**

```bash
cd firebase-tests && npm install && npm test
```

Expected: PASS. The assertion is `assertFails`, so a pass means the rules really do deny the write the seeder performs — reproducing the audit finding rather than a hypothetical.

- [ ] **Step 5: Add the emulator job to CI**

Append to the `jobs:` block of `.github/workflows/ci.yml`:

```yaml
  rules-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - run: npm install -g firebase-tools
      - run: npm install
        working-directory: firebase-tests
      - run: npm test
        working-directory: firebase-tests
```

- [ ] **Step 6: Commit**

```bash
git add firebase-tests firebase.json .github/workflows/ci.yml
git commit -m "Add Firebase emulator rules test harness

Pins the current rules' denial of DataSeeder writes as a test, so the
migration to event-scoped rules has a failing baseline to replace."
```

---

### Task 2: Event-scoped Firestore rules

Replaces the entire rules file. This is the security boundary — with no Cloud Functions, these rules are the only thing separating strangers' occasions.

**Files:**
- Modify: `firestore.rules` (full replacement)
- Modify: `firebase-tests/firestore.rules.test.js`

**Interfaces:**
- Consumes: the harness from Task 1
- Produces: the collection paths every later task writes to — `events/{eventId}`, `events/{eventId}/participants/{uid}`, `.../challenges`, `.../rewards`, `.../timeline`, `.../state/main`, `memberships/{uid}/events/{eventId}`, `inviteCodes/{CODE}`. Participant documents require a `usedCode` field on create.

- [ ] **Step 1: Write the failing tests for the new contract**

Replace the `describe` block in `firebase-tests/firestore.rules.test.js` with this, keeping the imports and hooks from Task 1 and adding `assertSucceeds`, `getDoc`, and `setLogLevel` to the imports:

```js
const EVENT = 'evt_1';
const HOST = 'uid_host';
const GUEST = 'uid_guest';
const OUTSIDER = 'uid_outsider';
const CODE = 'ABCD2345';

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `events/${EVENT}`), {
      name: "Alex's 30th", occasionType: 'birthday', celebrantName: 'Alex',
      hostUid: HOST, occasionDate: new Date(), isOpen: true, createdAt: new Date(),
      contributorCode: CODE, celebrantCode: 'EFGH6789',
    });
    await setDoc(doc(db, `events/${EVENT}/participants/${HOST}`), {
      name: 'Sam', avatarId: 'a1', mode: 'contributor', isHost: true, usedCode: CODE,
    });
    await setDoc(doc(db, `inviteCodes/${CODE}`), { eventId: EVENT, kind: 'contributor' });
    await setDoc(doc(db, `events/${EVENT}/rewards/r1`), {
      fromName: 'Sam', title: 'A message', pointCost: 50, contentType: 'video',
      isUnlocked: false, sortOrder: 0, badgeIllustration: 'b', createdAt: new Date(),
      fetchedBy: [],
    });
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
```

- [ ] **Step 2: Run and confirm they fail**

```bash
cd firebase-tests && npm test
```

Expected: the new cases FAIL. Under the current rules `events/**` matches nothing and falls to the catch-all deny, so every `assertSucceeds` case fails.

- [ ] **Step 3: Replace the rules**

`firestore.rules`:

```
rules_version = '2';

// BirthdayQuest Firestore rules.
//
// There are no Cloud Functions. These rules are the entire enforcement layer, so every
// change here needs a corresponding case in firebase-tests/firestore.rules.test.js.
//
// Isolation is by path: all event content lives under events/{eventId}, and membership is
// a document at events/{eventId}/participants/{uid}. A client cannot express a query that
// reaches another occasion's data, because the path does not exist for them.

service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() {
      return request.auth != null;
    }

    function participantPath(eventId) {
      return /databases/$(database)/documents/events/$(eventId)/participants/$(request.auth.uid);
    }

    function isMember(eventId) {
      return signedIn() && exists(participantPath(eventId));
    }

    function isHost(eventId) {
      return isMember(eventId) && get(participantPath(eventId)).data.isHost == true;
    }

    // Invite codes are opaque. Clients never read this collection, so codes cannot be
    // enumerated; rules-internal get() still resolves them during a join.
    match /inviteCodes/{code} {
      allow read: if false;
      allow create: if signedIn()
                    && request.resource.data.keys().hasOnly(['eventId', 'kind'])
                    && request.resource.data.eventId is string
                    && request.resource.data.kind in ['contributor', 'celebrant'];
      allow update: if false;
      allow delete: if isHost(resource.data.eventId);
    }

    // A user's own index of the occasions they belong to.
    match /memberships/{uid}/events/{eventId} {
      allow read: if signedIn() && request.auth.uid == uid;
      allow create: if signedIn() && request.auth.uid == uid && isMember(eventId);
      allow update: if false;
      allow delete: if signedIn() && request.auth.uid == uid;
    }

    match /events/{eventId} {
      allow read: if isMember(eventId);
      allow create: if signedIn() && request.resource.data.hostUid == request.auth.uid;
      allow update: if isHost(eventId);
      allow delete: if false;

      // Self-registration. Two legitimate paths, and nothing else:
      //   1. the host bootstrapping their own participant doc right after creating the event
      //   2. an invited joiner presenting a code that resolves to THIS event
      // Rules for batched writes evaluate against committed state, which is why occasion
      // creation is two-phase — see the plan's "Deviations from the spec".
      match /participants/{uid} {
        allow read: if isMember(eventId);

        allow create: if signedIn() && request.auth.uid == uid && (
          (
            request.resource.data.isHost == true
            && get(/databases/$(database)/documents/events/$(eventId)).data.hostUid == request.auth.uid
          ) || (
            request.resource.data.isHost == false
            && get(/databases/$(database)/documents/inviteCodes/$(request.resource.data.usedCode)).data.eventId == eventId
            && get(/databases/$(database)/documents/inviteCodes/$(request.resource.data.usedCode)).data.kind == request.resource.data.mode
          )
        );

        // You may rename yourself or change your avatar. You may not grant yourself host,
        // nor switch play mode.
        allow update: if signedIn() && request.auth.uid == uid
                      && request.resource.data.isHost == resource.data.isHost
                      && request.resource.data.mode == resource.data.mode;

        allow delete: if isHost(eventId);
      }

      match /challenges/{challengeId} {
        allow read: if isMember(eventId);
        allow create: if isMember(eventId);
        allow update: if isMember(eventId);
        allow delete: if isHost(eventId);
      }

      match /rewards/{rewardId} {
        allow read: if isMember(eventId);
        allow create: if isHost(eventId);
        allow update: if isMember(eventId);
        allow delete: if isHost(eventId);
      }

      // Append-only by design.
      match /timeline/{timelineId} {
        allow read: if isMember(eventId);
        allow create: if isMember(eventId);
        allow update, delete: if false;
      }

      match /state/{stateId} {
        allow read: if isMember(eventId);
        allow create: if isHost(eventId) && stateId == 'main';
        allow update: if isMember(eventId);
        allow delete: if false;
      }
    }

    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

- [ ] **Step 4: Run and confirm they pass**

```bash
cd firebase-tests && npm test
```

Expected: all cases PASS. If `denies reading the invite code lookup` fails, check that no `allow read` was left on `inviteCodes`.

- [ ] **Step 5: Commit**

```bash
git add firestore.rules firebase-tests/firestore.rules.test.js
git commit -m "Scope Firestore rules to events/{eventId}

Isolation is enforced by path plus a participants membership document.
Invite codes are unreadable so they cannot be enumerated; joiners present
a code that rules resolve internally. Self-promotion to host and play-mode
switching are both denied on update."
```

---

### Task 3: Storage rules with cross-service membership

Media gating moves from world-readable to per-event membership, checked against Firestore from Storage rules. Also fixes the audit's `contentType` finding by requiring an explicit content type that the Swift upload must now send.

**Files:**
- Modify: `storage.rules` (full replacement)
- Create: `firebase-tests/storage.rules.test.js`

**Interfaces:**
- Consumes: `events/{eventId}/participants/{uid}` from Task 2
- Produces: Storage paths `events/{eventId}/rewards/{rewardId}/{fileName}` and `events/{eventId}/proofs/{challengeId}/{fileName}`. Uploads must set `contentType`. Deletes are permitted only for the celebrant.

- [ ] **Step 1: Write the failing tests**

`firebase-tests/storage.rules.test.js`:

```js
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
const CELEBRANT = 'uid_celebrant';
const CONTRIBUTOR = 'uid_contributor';
const OUTSIDER = 'uid_outsider';
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
});
```

- [ ] **Step 2: Run and confirm they fail**

```bash
cd firebase-tests && npm test
```

Expected: FAIL. The current rules only match `rewards/{rewardId}/{fileName}` and `proofs/{challengeId}/{fileName}` with no event prefix, so all these paths hit the catch-all deny.

- [ ] **Step 3: Replace the rules**

`storage.rules`:

```
rules_version = '2';

// BirthdayQuest Storage rules.
//
// Media is gated on Firestore membership via cross-service rules. Cross-service evaluation
// allows two unique Firestore document lookups per request; repeat lookups of the same
// document are cached and free, so isMember and isCelebrant together cost one read.
//
// eventId is part of the object path specifically so these rules can extract it.

service firebase.storage {
  match /b/{bucket}/o {

    function participantPath(eventId) {
      return /databases/(default)/documents/events/$(eventId)/participants/$(request.auth.uid);
    }

    function isMember(eventId) {
      return request.auth != null && firestore.exists(participantPath(eventId));
    }

    function isCelebrant(eventId) {
      return isMember(eventId)
             && firestore.get(participantPath(eventId)).data.mode == 'celebrant';
    }

    function isPlayableMedia() {
      return request.resource.contentType.matches('video/.*')
             || request.resource.contentType.matches('audio/.*')
             || request.resource.contentType.matches('image/.*');
    }

    // Reward media. Written by contributors, read by members, deleted by the celebrant
    // once downloaded — that client-side delete is what keeps storage bounded.
    match /events/{eventId}/rewards/{rewardId}/{fileName} {
      allow read: if isMember(eventId);
      allow write: if request.resource == null
                     ? isCelebrant(eventId)
                     : isMember(eventId)
                       && request.resource.size < 200 * 1024 * 1024
                       && isPlayableMedia();
    }

    // Challenge proof photos. Images only, 10 MB cap.
    match /events/{eventId}/proofs/{challengeId}/{fileName} {
      allow read: if isMember(eventId);
      allow write: if request.resource == null
                     ? isCelebrant(eventId)
                     : isMember(eventId)
                       && request.resource.size < 10 * 1024 * 1024
                       && request.resource.contentType.matches('image/.*');
    }

    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

- [ ] **Step 4: Run and confirm they pass**

```bash
cd firebase-tests && npm test
```

Expected: PASS. Note `request.resource == null` is how a delete is distinguished — Storage rules have no separate `delete` verb, only `read` and `write`.

- [ ] **Step 5: Commit**

```bash
git add storage.rules firebase-tests/storage.rules.test.js
git commit -m "Gate Storage media on event membership

Reward and proof objects move under events/{eventId}/ so cross-service
rules can resolve membership from Firestore. Uploads must declare a usable
content type, and only the celebrant may delete — the mechanism that keeps
media transit bounded."
```

---

### Task 4: Occasion and Participant models

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/Models/Occasion.swift`
- Create: `BirthdayQuest/BirthdayQuest/Models/Participant.swift`
- Modify: `BirthdayQuest/BirthdayQuest/Models/Reward.swift`
- Test: `BirthdayQuest/BirthdayQuestTests/ModelTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `Occasion`, `OccasionType`, `Participant`, `ParticipantMode`, and `Reward.fetchedBy: [String]`. Task 7 uses these in `GameBackend`; Tasks 10–12 use them in sessions and views.

- [ ] **Step 1: Write the failing test**

`BirthdayQuest/BirthdayQuestTests/ModelTests.swift`:

```swift
import Testing
import Foundation
@testable import BirthdayQuest

@Suite("Occasion model")
struct OccasionModelTests {

    @Test("every occasion type has display copy and a default challenge noun")
    func occasionTypeCopy() {
        for type in OccasionType.allCases {
            #expect(!type.displayName.isEmpty)
            #expect(!type.celebrantLabel.isEmpty)
        }
    }

    @Test("participant mode round-trips through its raw value")
    func participantModeRawValues() {
        #expect(ParticipantMode(rawValue: "contributor") == .contributor)
        #expect(ParticipantMode(rawValue: "celebrant") == .celebrant)
        #expect(ParticipantMode(rawValue: "host") == nil)
    }

    @Test("a reward with no fetchers decodes to an empty array")
    func rewardFetchedByDefaults() throws {
        let json = """
        {"fromName":"Sam","title":"A message","pointCost":50,"contentType":"video",
         "isUnlocked":false,"sortOrder":0,"badgeIllustration":"b",
         "createdAt":0}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let reward = try decoder.decode(Reward.self, from: json)
        #expect(reward.fetchedBy.isEmpty)
    }
}
```

- [ ] **Step 2: Run and confirm it fails**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | /usr/bin/grep -E 'error:|Testing failed'
```

Expected: compile errors — `OccasionType`, `ParticipantMode`, and `Reward.fetchedBy` do not exist.

- [ ] **Step 3: Create the models**

`Models/Occasion.swift`:

```swift
import Foundation
import FirebaseFirestore

// MARK: - Occasion Type

enum OccasionType: String, Codable, CaseIterable {
    case birthday
    case anniversary
    case graduation
    case farewell
    case bachelor

    var displayName: String {
        switch self {
        case .birthday:    return "Birthday"
        case .anniversary: return "Anniversary"
        case .graduation:  return "Graduation"
        case .farewell:    return "Farewell"
        case .bachelor:    return "Bachelor/ette"
        }
    }

    /// What the app calls the person being celebrated. Replaces the hardcoded, gendered
    /// "Birthday Boy" copy that the audit found scattered through the views.
    var celebrantLabel: String {
        switch self {
        case .birthday:    return "Birthday Star"
        case .anniversary: return "Happy Couple"
        case .graduation:  return "Graduate"
        case .farewell:    return "Guest of Honour"
        case .bachelor:    return "Guest of Honour"
        }
    }
}

// MARK: - Occasion

/// One celebration. The tenant boundary: all challenges, rewards, timeline entries and
/// game state live in subcollections of this document.
struct Occasion: Identifiable, Codable {
    @DocumentID var id: String?
    let name: String
    let occasionType: OccasionType
    let celebrantName: String
    let hostUid: String
    /// Sorting, reminders, and the media-purge backstop. Deliberately gates nothing.
    let occasionDate: Date
    var isOpen: Bool
    let createdAt: Date
    /// The two invite codes, stored here because `inviteCodes` is deny-all read — the host
    /// must be able to reshare their link, and members can read the event document.
    let contributorCode: String
    let celebrantCode: String

    var contributorLink: URL? {
        URL(string: "birthdayquest://join?e=\(id ?? "")&c=\(contributorCode)")
    }

    var celebrantLink: URL? {
        URL(string: "birthdayquest://join?e=\(id ?? "")&c=\(celebrantCode)")
    }

    enum CodingKeys: String, CodingKey {
        case id, name, occasionType, celebrantName, hostUid
        case occasionDate, isOpen, createdAt, contributorCode, celebrantCode
    }
}
```

`Models/Participant.swift`:

```swift
import Foundation
import FirebaseFirestore

// MARK: - Participant Mode

/// How a participant plays. Orthogonal to `isHost`, which is a permission — this is why
/// a host can also be the celebrant.
enum ParticipantMode: String, Codable, CaseIterable {
    case contributor
    case celebrant
}

// MARK: - Participant

/// Membership in one occasion. The document ID is the Firebase uid, which is what makes
/// impersonation structurally impossible: rules only permit writing your own document.
struct Participant: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var avatarId: String
    let mode: ParticipantMode
    let isHost: Bool
    /// The invite code presented at join. Rules read this to validate the join; it is never
    /// displayed. The host's own document carries the contributor code.
    let usedCode: String

    var isCelebrant: Bool { mode == .celebrant }

    enum CodingKeys: String, CodingKey {
        case id, name, avatarId, mode, isHost, usedCode
    }
}
```

- [ ] **Step 4: Add `fetchedBy` and delete the dead cost table**

In `Models/Reward.swift`, delete the `defaultPointCost` computed property (lines 21–29) — it is unreferenced and contradicts the seeded values, claiming audio costs 75 where the seeder charges 50.

Then add the field and a decoding default. Replace the struct body's `let createdAt: Date` line and `CodingKeys` with:

```swift
    let createdAt: Date
    /// uids that have downloaded and locally persisted this reward's media. When every
    /// recipient appears here, the Storage object is deleted by the celebrant's device.
    var fetchedBy: [String]

    enum CodingKeys: String, CodingKey {
        case id, fromUserId, fromName, title, teaser
        case pointCost, contentType, contentUrl, contentUrls, contentText
        case isUnlocked, unlockedAt, sortOrder, badgeIllustration, createdAt, fetchedBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        fromUserId = try c.decodeIfPresent(String.self, forKey: .fromUserId)
        fromName = try c.decode(String.self, forKey: .fromName)
        title = try c.decode(String.self, forKey: .title)
        teaser = try c.decodeIfPresent(String.self, forKey: .teaser)
        pointCost = try c.decode(Int.self, forKey: .pointCost)
        contentType = try c.decode(RewardContentType.self, forKey: .contentType)
        contentUrl = try c.decodeIfPresent(String.self, forKey: .contentUrl)
        contentUrls = try c.decodeIfPresent([String].self, forKey: .contentUrls)
        contentText = try c.decodeIfPresent(String.self, forKey: .contentText)
        isUnlocked = try c.decode(Bool.self, forKey: .isUnlocked)
        unlockedAt = try c.decodeIfPresent(Date.self, forKey: .unlockedAt)
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        badgeIllustration = try c.decode(String.self, forKey: .badgeIllustration)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        fetchedBy = try c.decodeIfPresent([String].self, forKey: .fetchedBy) ?? []
    }
```

The explicit initializer exists only so `fetchedBy` tolerates documents written before the field existed. Without it, decoding a legacy reward throws.

- [ ] **Step 5: Run and confirm the tests pass**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | /usr/bin/tail -20
```

Expected: PASS. If `rewardFetchedByDefaults` fails, the `decodeIfPresent ?? []` fallback is missing.

- [ ] **Step 6: Commit**

```bash
git add BirthdayQuest/BirthdayQuest/Models BirthdayQuest/BirthdayQuestTests/ModelTests.swift
git commit -m "Add Occasion and Participant models

Participant separates mode (how you play) from isHost (what you may do),
so a host can also be the celebrant. OccasionType carries the celebrant
label that replaces hardcoded gendered copy.

Also adds Reward.fetchedBy for media purge tracking and deletes the dead
defaultPointCost table, which contradicted the seeded costs."
```

---

### Task 5: Rewrite AppConstants

Deletes the five hardcoded character identities and the birthday-specific constants, replacing them with subcollection path names and the invite-code alphabet.

**Files:**
- Modify: `BirthdayQuest/BirthdayQuest/AppConstants.swift` (full replacement)
- Test: `BirthdayQuest/BirthdayQuestTests/InviteCodeTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `Collections.events`, `.participants`, `.challenges`, `.rewards`, `.timeline`, `.state`, `.stateDoc`, `.memberships`, `.inviteCodes`; and `InviteCode.generate() -> String`, `InviteCode.length`, `InviteCode.alphabet`.

- [ ] **Step 1: Write the failing test**

`BirthdayQuest/BirthdayQuestTests/InviteCodeTests.swift`:

```swift
import Testing
@testable import BirthdayQuest

@Suite("Invite codes")
struct InviteCodeTests {

    @Test("generated codes are the declared length")
    func length() {
        #expect(InviteCode.generate().count == InviteCode.length)
    }

    @Test("codes avoid characters that are misread aloud")
    func unambiguousAlphabet() {
        let banned: Set<Character> = ["I", "O", "0", "1"]
        #expect(InviteCode.alphabet.allSatisfy { !banned.contains($0) })
        #expect(InviteCode.alphabet.count == 32)
    }

    @Test("codes are drawn only from the alphabet")
    func drawsFromAlphabet() {
        let allowed = Set(InviteCode.alphabet)
        for _ in 0..<200 {
            #expect(InviteCode.generate().allSatisfy { allowed.contains($0) })
        }
    }

    @Test("codes do not repeat in a small sample")
    func collisionResistance() {
        let codes = Set((0..<500).map { _ in InviteCode.generate() })
        #expect(codes.count == 500)
    }
}
```

- [ ] **Step 2: Run and confirm it fails**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | /usr/bin/grep -E 'error:'
```

Expected: `cannot find 'InviteCode' in scope`.

- [ ] **Step 3: Replace AppConstants**

`AppConstants.swift`:

```swift
import Foundation

// MARK: - Firestore Paths

/// Collection and document names. All event content is a subcollection of
/// `events/{eventId}`, which is what makes cross-occasion access impossible to express.
enum Collections {
    static let events = "events"
    static let memberships = "memberships"
    static let inviteCodes = "inviteCodes"

    // Subcollections of an event document
    static let participants = "participants"
    static let challenges = "challenges"
    static let rewards = "rewards"
    static let timeline = "timeline"
    static let state = "state"
    static let stateDoc = "main"
}

// MARK: - Invite Codes

enum InviteCode {
    /// 32 symbols, excluding I, O, 0 and 1 because codes get read aloud and typed by hand.
    /// 32^8 is roughly 2^40 combinations, and each guess costs a denied write.
    static let alphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 8

    static func generate() -> String {
        String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}

// MARK: - Storage Paths

enum StoragePaths {
    static func rewardMedia(eventId: String, rewardId: String, fileName: String) -> String {
        "\(Collections.events)/\(eventId)/\(Collections.rewards)/\(rewardId)/\(fileName)"
    }

    static func proof(eventId: String, challengeId: String, fileName: String) -> String {
        "\(Collections.events)/\(eventId)/proofs/\(challengeId)/\(fileName)"
    }
}
```

- [ ] **Step 4: Run and confirm the tests pass**

The app will not compile yet — `CharacterID` is referenced by `DataSeeder`, `SessionManager`, `AdminViewModel`, `AvatarView`, and `SecretChallengeHomeView`. Those are removed in Tasks 7, 12, 13 and 14. To keep this task independently verifiable, run only the new test file:

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/InviteCodeTests test 2>&1 | /usr/bin/tail -20
```

Expected: PASS once the referencing files are stubbed. If the build still fails on `CharacterID`, proceed to Step 5 — the compile break is expected and closes in Task 7.

- [ ] **Step 5: Commit**

```bash
git add BirthdayQuest/BirthdayQuest/AppConstants.swift BirthdayQuest/BirthdayQuestTests/InviteCodeTests.swift
git commit -m "Replace character constants with event paths and invite codes

Deletes CharacterID, whose five hardcoded identities were the root of the
single-occasion design. Adds subcollection path names and an 8-character
code alphabet that omits I, O, 0 and 1 for spoken legibility."
```

---

### Task 6: Listener completions carry Result

Fixes the audit bug where a listener error returns early without calling its completion handler, leaving `isLoading` true forever and producing an infinite shimmer with no error and no retry. This becomes critical once membership can be revoked, because permission-denied turns into an expected event.

**Files:**
- Modify: `BirthdayQuest/BirthdayQuest/Services/GameBackend.swift`
- Modify: `BirthdayQuest/BirthdayQuest/Services/FirestoreService.swift:36-90,168-180,278-300`
- Modify: `BirthdayQuest/BirthdayQuestTests/MockGameBackend.swift`
- Modify: `BirthdayQuest/BirthdayQuest/ViewModels/RewardsViewModel.swift:53-60`
- Modify: `BirthdayQuest/BirthdayQuest/ViewModels/ChallengesViewModel.swift:57`
- Modify: `BirthdayQuest/BirthdayQuest/ViewModels/TimelineViewModel.swift:53`
- Modify: `BirthdayQuest/BirthdayQuest/ViewModels/SecretChallengeViewModel.swift:71`
- Test: `BirthdayQuest/BirthdayQuestTests/ViewModelTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: listener signatures become `completion: @escaping (Result<[T], Error>) -> Void`. `MockGameBackend` gains `var listenerFailure: Error?` so tests can inject a failure.

- [ ] **Step 1: Write the failing test**

Add to `BirthdayQuest/BirthdayQuestTests/ViewModelTests.swift`:

```swift
@Test("a rewards listener failure clears loading and surfaces an error")
@MainActor
func rewardsListenerFailureStopsLoading() async {
    let mock = MockGameBackend()
    mock.listenerFailure = NSError(
        domain: "FIRFirestoreErrorDomain", code: 7,
        userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
    )
    let vm = RewardsViewModel(service: mock)

    vm.startListening()
    await Task.yield()

    #expect(vm.isLoading == false)
    #expect(vm.errorMessage != nil)
}
```

- [ ] **Step 2: Run and confirm it fails**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/ViewModelTests test 2>&1 | /usr/bin/grep -E 'error:|failed'
```

Expected: compile error — `listenerFailure` does not exist on `MockGameBackend`.

- [ ] **Step 3: Change the protocol**

In `Services/GameBackend.swift`, replace the four listener declarations:

```swift
    func listenToUsers(completion: @escaping (Result<[BQUser], Error>) -> Void)
    func listenToRewards(completion: @escaping (Result<[Reward], Error>) -> Void)
    func listenToChallenges(
        listenerKey: String,
        completion: @escaping (Result<[Challenge], Error>) -> Void
    )
    func listenToTimeline(completion: @escaping (Result<[TimelineEvent], Error>) -> Void)
    func listenToGameState(completion: @escaping (Result<GameState, Error>) -> Void)
```

and update the convenience extension:

```swift
extension GameBackend {
    func listenToChallenges(completion: @escaping (Result<[Challenge], Error>) -> Void) {
        listenToChallenges(listenerKey: "challenges", completion: completion)
    }
}
```

Note `listenToGameState` changes from `(GameState?) -> Void` to `Result<GameState, Error>`. The optional was doing double duty as "no data yet" and "failed", which is exactly the ambiguity this fixes.

- [ ] **Step 4: Fix the service's error paths**

In `Services/FirestoreService.swift`, every listener currently looks like:

```swift
            guard let docs = snapshot?.documents else {
                self.logger.error("Users listener error: \(error?.localizedDescription ?? "unknown")")
                return
            }
```

Replace each with the pattern below, substituting the collection name in the log message:

```swift
            if let error {
                self.logger.error("Users listener error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let docs = snapshot?.documents else {
                completion(.success([]))
                return
            }
```

Then wrap each existing success call site as `completion(.success(items))`. Apply to all five listeners: users, rewards, challenges, timeline, and game state.

- [ ] **Step 5: Add failure injection to the mock**

In `BirthdayQuestTests/MockGameBackend.swift`, add the property and route every listener through it:

```swift
    /// When set, every listener reports this failure instead of data. Lets tests exercise
    /// the permission-denied path that the real backend produces when membership is revoked.
    var listenerFailure: Error?
```

Then in each `listenTo…` implementation, begin with:

```swift
        if let listenerFailure {
            completion(.failure(listenerFailure))
            return
        }
```

- [ ] **Step 6: Handle failure in the view models**

In each of the four view models, the listener callback becomes:

```swift
        service.listenToRewards { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let rewards):
                    self.rewards = rewards
                case .failure(let error):
                    self.errorMessage = "Couldn't load gifts. Pull to retry."
                    self.logger.error("Rewards listener: \(error.localizedDescription)")
                }
            }
        }
```

Adapt the property name and copy per view model: `ChallengesViewModel` sets `challenges` and "Couldn't load challenges."; `TimelineViewModel` sets `events` and "Couldn't load the timeline."; `SecretChallengeViewModel` sets its dare and "Couldn't load your dare.". `isLoading = false` must be set on **both** branches — that is the actual bug.

- [ ] **Step 7: Run and confirm the tests pass**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/ViewModelTests test 2>&1 | /usr/bin/tail -20
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add BirthdayQuest/BirthdayQuest/Services BirthdayQuest/BirthdayQuest/ViewModels BirthdayQuest/BirthdayQuestTests
git commit -m "Surface listener errors instead of hanging on the skeleton

Listener completions now carry Result. Previously an error returned early
without calling the completion handler, so isLoading stayed true and the
view shimmered forever with no error and no retry. Permission-denied
becomes an expected event once membership can be revoked, so this path
has to be real."
```

---

## Note on Tasks 7–12: the migration window

Tasks 1–6 each leave the app compiling. Tasks 7–12 do not, and pretending otherwise would
mislead whoever executes this. Deleting `BQUser`, `UserRole` and `CharacterID` breaks
`ProfileView`, `AvatarView`, `CharacterCardView`, `SecretChallengeHomeView` and
`AdminViewModel` simultaneously, and there is no ordering that avoids it short of keeping
dead compatibility shims that would then need their own removal task.

So for Tasks 7 through 12 the gate is:

1. The task's own unit tests pass via `-only-testing:`.
2. `cd firebase-tests && npm test` stays green.
3. `git diff --stat` matches the task's declared file list.

**Task 13 restores a compiling, launchable app**, and its gate is a clean full build plus a
manual two-device check. Do not start Task 7 without intending to reach Task 13.

---

### Task 7: Scope GameBackend and FirestoreService to an event

The mechanical heart of the migration. Every backend method gains an `eventId`, all paths
move under `events/{eventId}`, and the character-claiming surface is deleted outright.

**Files:**
- Modify: `BirthdayQuest/BirthdayQuest/Services/GameBackend.swift` (full replacement)
- Modify: `BirthdayQuest/BirthdayQuest/Services/FirestoreService.swift`
- Modify: `BirthdayQuest/BirthdayQuestTests/MockGameBackend.swift`
- Delete: `BirthdayQuest/BirthdayQuest/Services/DataSeeder.swift`
- Delete: `BirthdayQuest/BirthdayQuest/Models/User.swift`

**Interfaces:**
- Consumes: `Occasion`, `Participant` (Task 4); `Collections`, `StoragePaths` (Task 5); `Result` listeners (Task 6)
- Produces: the full `GameBackend` surface below. Tasks 9–12 call it exclusively.

- [ ] **Step 1: Replace the protocol**

`Services/GameBackend.swift`:

```swift
import Foundation

/// The backend surface the app depends on.
///
/// Every method is scoped to an `eventId` because every document lives under
/// `events/{eventId}`. That parameter is not ceremony — it is the tenant boundary, and
/// omitting it is not expressible.
///
/// The atomic transaction bodies still live inside `FirestoreService`
/// (`unlockRewardAtomically`, `completeChallengeAtomically`, `adminForceUnlockReward`), so
/// `MockGameBackend` replaces that logic rather than verifying it. The emulator suite in
/// `firebase-tests/` is what actually tests it.
protocol GameBackend: AnyObject {

    // MARK: Listener Management

    func removeListener(forKey key: String)
    func removeAllListeners()

    // MARK: Occasions

    /// Two-phase by necessity: rules for batched writes evaluate against committed state,
    /// so the event document must exist before its participant document can be validated.
    /// Returns the new event id.
    func createOccasion(
        name: String,
        occasionType: OccasionType,
        celebrantName: String,
        occasionDate: Date,
        hostName: String,
        hostAvatarId: String
    ) async throws -> String

    /// Self-registers the caller into an occasion and mirrors the membership.
    ///
    /// Takes `eventId` *and* `code` because `inviteCodes` is deny-all read: a client cannot
    /// resolve one from the other, which is what prevents codes being enumerated. The host
    /// shares both in one deep link. `mode` must match the code's kind or the rules reject
    /// the write.
    func joinOccasion(
        eventId: String,
        code: String,
        name: String,
        avatarId: String,
        mode: ParticipantMode
    ) async throws

    func fetchMyOccasions() async throws -> [Occasion]
    func fetchOccasion(eventId: String) async throws -> Occasion?
    func fetchParticipants(eventId: String) async throws -> [Participant]
    func fetchMyParticipant(eventId: String) async throws -> Participant?
    func setOccasionOpen(eventId: String, isOpen: Bool) async throws

    // MARK: Rewards

    func listenToRewards(eventId: String, completion: @escaping (Result<[Reward], Error>) -> Void)
    func fetchReward(eventId: String, rewardId: String) async throws -> Reward?
    func unlockRewardAtomically(
        eventId: String,
        rewardId: String,
        pointCost: Int,
        timelineEvent: TimelineEvent
    ) async throws

    // MARK: Challenges

    func listenToChallenges(
        eventId: String,
        listenerKey: String,
        completion: @escaping (Result<[Challenge], Error>) -> Void
    )
    func fetchChallenge(eventId: String, challengeId: String) async throws -> Challenge?
    func completeChallengeAtomically(
        eventId: String,
        challengeId: String,
        pointValue: Int,
        isSecret: Bool,
        proofUrl: String?,
        proofType: String?,
        proofText: String?,
        timelineEvent: TimelineEvent
    ) async throws
    func createSecretChallenge(eventId: String, challenge: Challenge) async throws -> String
    func updateSecretChallenge(
        eventId: String,
        challengeId: String,
        data: [String: Any]
    ) async throws

    // MARK: Timeline

    func listenToTimeline(
        eventId: String,
        completion: @escaping (Result<[TimelineEvent], Error>) -> Void
    )
    func addTimelineEvent(eventId: String, event: TimelineEvent) async throws

    // MARK: Game State

    func listenToGameState(eventId: String, completion: @escaping (Result<GameState, Error>) -> Void)
    func updateGameState(eventId: String, fields: [String: Any]) async throws
    func earnPoints(eventId: String, amount: Int) async throws
    func spendPoints(eventId: String, amount: Int) async throws
    func checkFinalBadge(eventId: String) async throws
    func incrementSecretChallengesCompleted(eventId: String) async throws

    // MARK: Storage

    /// `contentType` is required, not optional. The Storage rules demand a usable content
    /// type, and `putData` does not infer one from the path — omitting it was the audit's
    /// suspected cause of every proof upload failing with 403.
    func uploadProofData(
        eventId: String,
        challengeId: String,
        data: Data,
        contentType: String
    ) async throws -> String

    // MARK: Admin

    func adminForceUnlockReward(
        eventId: String,
        rewardId: String,
        pointCost: Int,
        deductPoints: Bool,
        timelineEvent: TimelineEvent
    ) async throws
}

extension GameBackend {
    func listenToChallenges(
        eventId: String,
        completion: @escaping (Result<[Challenge], Error>) -> Void
    ) {
        listenToChallenges(eventId: eventId, listenerKey: "challenges", completion: completion)
    }
}
```

`listenToUsers`, `claimCharacter`, `fetchUser`, `unclaimCharacter`, `unlockReward` and
`completeChallenge` are all deleted. The first four belong to the character-claim model
being removed; the last two were non-atomic legacy paths superseded by their `Atomically`
counterparts.

- [ ] **Step 2: Add path helpers to FirestoreService**

At the top of `Services/FirestoreService.swift`, add:

```swift
    // MARK: - Path Helpers

    private func eventRef(_ eventId: String) -> DocumentReference {
        db.collection(Collections.events).document(eventId)
    }

    private func challengesRef(_ eventId: String) -> CollectionReference {
        eventRef(eventId).collection(Collections.challenges)
    }

    private func rewardsRef(_ eventId: String) -> CollectionReference {
        eventRef(eventId).collection(Collections.rewards)
    }

    private func timelineRef(_ eventId: String) -> CollectionReference {
        eventRef(eventId).collection(Collections.timeline)
    }

    private func participantsRef(_ eventId: String) -> CollectionReference {
        eventRef(eventId).collection(Collections.participants)
    }

    private func stateRef(_ eventId: String) -> DocumentReference {
        eventRef(eventId).collection(Collections.state).document(Collections.stateDoc)
    }
```

Then replace every existing collection reference throughout the file:

| Old | New |
|---|---|
| `db.collection(Collections.challenges)` | `challengesRef(eventId)` |
| `db.collection(Collections.rewards)` | `rewardsRef(eventId)` |
| `db.collection(Collections.timelineEvents)` | `timelineRef(eventId)` |
| `db.collection(Collections.gameState).document(Collections.gameStateDoc)` | `stateRef(eventId)` |
| `db.collection(Collections.users)` | deleted with the character model |

The three transaction bodies (`unlockRewardAtomically`, `completeChallengeAtomically`,
`adminForceUnlockReward`) change **only** in which references they resolve. Do not alter
their logic — the balance re-check and the idempotency guard are the parts the emulator
tests will verify, and they are correct today.

- [ ] **Step 3: Implement occasion creation, two-phase**

Add to `FirestoreService`:

```swift
    func createOccasion(
        name: String,
        occasionType: OccasionType,
        celebrantName: String,
        occasionDate: Date,
        hostName: String,
        hostAvatarId: String
    ) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw BackendError.notSignedIn }

        // The document reference assigns an id locally without writing anything, which
        // lets the codes be minted against the event before the event exists.
        let eventRef = db.collection(Collections.events).document()
        let eventId = eventRef.documentID

        // Codes first. Reserving one only requires being signed in, not the event existing.
        let contributorCode = try await reserveCode(eventId: eventId, kind: "contributor")
        let celebrantCode = try await reserveCode(eventId: eventId, kind: "celebrant")

        // Phase 1: the event document, written once and complete. Rules validating the
        // host's participant document call get() on this event, and a batched write cannot
        // see its own siblings — so it must be committed before phase 2.
        try await eventRef.setData([
            "name": name,
            "occasionType": occasionType.rawValue,
            "celebrantName": celebrantName,
            "hostUid": uid,
            "occasionDate": Timestamp(date: occasionDate),
            "isOpen": true,
            "createdAt": Timestamp(date: Date()),
            "contributorCode": contributorCode,
            "celebrantCode": celebrantCode
        ])

        // Phase 2: host participant, initial game state, membership mirror. If this fails
        // the event document is orphaned — unreadable by every client, because the
        // membership check finds no participant — so it is invisible rather than corrupt.
        let batch = db.batch()
        batch.setData([
            "name": hostName,
            "avatarId": hostAvatarId,
            "mode": ParticipantMode.contributor.rawValue,
            "isHost": true,
            "usedCode": contributorCode
        ], forDocument: participantsRef(eventId).document(uid))

        batch.setData([
            "birthdayBoyId": "",
            "totalPointsEarned": 0, "totalPointsSpent": 0, "currentPoints": 0,
            "challengesCompleted": 0, "totalChallenges": 0,
            "secretChallengesFound": 0, "secretChallengesCompleted": 0,
            "rewardsUnlocked": 0, "totalRewards": 0,
            "allRewardsUnlocked": false, "finalBadgeUnlocked": false,
            "currentDay": 1,
            "gameStartedAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ], forDocument: stateRef(eventId))

        batch.setData([
            "role": ParticipantMode.contributor.rawValue,
            "isHost": true,
            "joinedAt": Timestamp(date: Date())
        ], forDocument: membershipRef(uid: uid, eventId: eventId))

        try await batch.commit()
        logger.info("Created occasion \(eventId)")
        return eventId
    }

    /// Claims an unused code. `allow create` in Firestore only fires when the document does
    /// not exist, so a collision surfaces as permission-denied and we simply try again.
    private func reserveCode(eventId: String, kind: String) async throws -> String {
        for _ in 0..<8 {
            let code = InviteCode.generate()
            do {
                try await db.collection(Collections.inviteCodes).document(code)
                    .setData(["eventId": eventId, "kind": kind])
                return code
            } catch {
                continue
            }
        }
        throw BackendError.couldNotReserveCode
    }

    private func membershipRef(uid: String, eventId: String) -> DocumentReference {
        db.collection(Collections.memberships).document(uid)
            .collection(Collections.events).document(eventId)
    }
```

- [ ] **Step 4: Implement joining**

The joiner cannot read `inviteCodes` — the collection is deny-all so codes cannot be
enumerated — which means the client cannot look up an event id from a code alone. The host
therefore shares **both** together, as a deep link:

```
birthdayquest://join?e=<eventId>&c=<CODE>
```

The joiner asserts the code in their own participant document and the rules resolve it
internally via `get()`. An invalid or mismatched code surfaces as permission-denied.

This is why the Step 1 signature takes `eventId`, `code` and `mode` together and returns
nothing — the caller already holds the id. Implementation:

```swift
    func joinOccasion(
        eventId: String,
        code: String,
        name: String,
        avatarId: String,
        mode: ParticipantMode
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw BackendError.notSignedIn }
        let normalized = code.uppercased().trimmingCharacters(in: .whitespaces)

        do {
            try await participantsRef(eventId).document(uid).setData([
                "name": name,
                "avatarId": avatarId,
                "mode": mode.rawValue,
                "isHost": false,
                "usedCode": normalized
            ])
        } catch let error as NSError
                    where error.domain == FirestoreErrorDomain
                    && error.code == FirestoreErrorCode.permissionDenied.rawValue {
            // The rules rejected the code, or its kind did not match the requested mode.
            // Both are user-facing input errors, not faults.
            throw BackendError.invalidCode
        }

        try await membershipRef(uid: uid, eventId: eventId).setData([
            "role": mode.rawValue,
            "isHost": false,
            "joinedAt": Timestamp(date: Date())
        ])

        logger.info("Joined occasion \(eventId)")
    }
```

Note the `mode` parameter: a contributor code and a celebrant code are different documents
with different `kind` values, and the rule requires `kind == mode`. Passing the wrong mode
for a code is therefore rejected rather than silently granting the wrong role. The deep
link carries the code; `JoinOccasionView` derives `mode` by letting the user pick, and a
mismatch produces `invalidCode`.

- [ ] **Step 5: Fix the upload content type**

Replace `uploadProofData`:

```swift
    func uploadProofData(
        eventId: String,
        challengeId: String,
        data: Data,
        contentType: String
    ) async throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        let path = StoragePaths.proof(
            eventId: eventId, challengeId: challengeId, fileName: fileName
        )
        let ref = Storage.storage().reference().child(path)

        // Required. putData does not infer a content type from the path, so without this
        // the object uploads as application/octet-stream and the Storage rule requiring
        // image/* rejects it.
        let metadata = StorageMetadata()
        metadata.contentType = contentType

        _ = try await ref.putDataAsync(data, metadata: metadata)
        return try await ref.downloadURL().absoluteString
    }
```

- [ ] **Step 6: Add the error type and delete the seeder**

```swift
enum BackendError: LocalizedError {
    case notSignedIn
    case invalidCode
    case couldNotReserveCode

    var errorDescription: String? {
        switch self {
        case .notSignedIn:        return "You're not signed in yet."
        case .invalidCode:        return "That invite code doesn't match this occasion."
        case .couldNotReserveCode: return "Couldn't create an invite code. Try again."
        }
    }
}
```

```bash
git rm BirthdayQuest/BirthdayQuest/Services/DataSeeder.swift
git rm BirthdayQuest/BirthdayQuest/Models/User.swift
```

Global seeding is gone. An occasion's content is created by its host, under rules that
permit exactly that — which is why the audit's rules-versus-seeder contradiction cannot
recur.

- [ ] **Step 7: Update the mock to match**

Mirror every signature change in `BirthdayQuestTests/MockGameBackend.swift`, adding:

```swift
    var createdOccasions: [(name: String, type: OccasionType)] = []
    var joinedOccasions: [(eventId: String, code: String)] = []
    var stubOccasions: [Occasion] = []
    var stubParticipants: [Participant] = []

    func createOccasion(
        name: String, occasionType: OccasionType, celebrantName: String,
        occasionDate: Date, hostName: String, hostAvatarId: String
    ) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        createdOccasions.append((name, occasionType))
        return "evt_mock"
    }

    func joinOccasion(
        eventId: String, code: String, name: String, avatarId: String, mode: ParticipantMode
    ) async throws {
        if let errorToThrow { throw errorToThrow }
        joinedOccasions.append((eventId, code))
    }

    func fetchMyOccasions() async throws -> [Occasion] { stubOccasions }
    func fetchParticipants(eventId: String) async throws -> [Participant] { stubParticipants }
```

- [ ] **Step 8: Verify**

```bash
cd firebase-tests && npm test
cd .. && git diff --stat
```

Expected: rules tests green; diff limited to the declared files. The app does not compile —
see the migration-window note.

- [ ] **Step 9: Commit**

```bash
git add -A BirthdayQuest/BirthdayQuest/Services BirthdayQuest/BirthdayQuest/Models BirthdayQuest/BirthdayQuestTests
git commit -m "Scope every backend call to an event

All paths move under events/{eventId}. Character claiming, BQUser and the
global DataSeeder are deleted; an occasion's content is now created by its
host under rules that permit exactly that, so the rules-versus-seeder
contradiction cannot recur.

Occasion creation is two-phase because batched writes are evaluated
against committed state. Proof uploads now send an explicit contentType,
without which the Storage rule requiring image/* rejects them."
```

---

### Task 8: AuthService

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/Services/AuthService.swift`
- Create: `BirthdayQuest/BirthdayQuestTests/MockAuthProviding.swift`
- Modify: `BirthdayQuest/BirthdayQuest/BirthdayQuestApp.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `AuthProviding` with `currentUid`, `isAnonymous`, `signInAnonymouslyIfNeeded() async throws -> String`, `signInWithApple(idToken:nonce:) async throws`, and `AuthService.randomNonce() -> String`. Task 9 injects it into `AppSession`.

- [ ] **Step 1: Write the failing test**

`BirthdayQuest/BirthdayQuestTests/AuthTests.swift`:

```swift
import Testing
@testable import BirthdayQuest

@Suite("Auth")
struct AuthTests {

    @Test("nonces are unique and long enough to resist replay")
    func nonceQuality() {
        let nonces = Set((0..<200).map { _ in AuthService.randomNonce() })
        #expect(nonces.count == 200)
        #expect(AuthService.randomNonce().count >= 32)
    }

    @Test("anonymous sign-in is skipped when a uid already exists")
    func reusesExistingUid() async throws {
        let mock = MockAuthProviding()
        mock.currentUid = "uid_existing"
        let uid = try await mock.signInAnonymouslyIfNeeded()
        #expect(uid == "uid_existing")
        #expect(mock.anonymousSignInCount == 0)
    }
}
```

- [ ] **Step 2: Run and confirm it fails**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/AuthTests test 2>&1 | /usr/bin/grep -E 'error:'
```

Expected: `cannot find 'AuthService' in scope`.

- [ ] **Step 3: Implement**

`Services/AuthService.swift`:

```swift
import Foundation
import FirebaseAuth
import CryptoKit
import OSLog

protocol AuthProviding: AnyObject {
    var currentUid: String? { get }
    var isAnonymous: Bool { get }
    func signInAnonymouslyIfNeeded() async throws -> String
    func signInWithApple(idToken: String, nonce: String) async throws
}

final class AuthService: AuthProviding {

    static let shared = AuthService()
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Auth")

    private init() {}

    var currentUid: String? { Auth.auth().currentUser?.uid }
    var isAnonymous: Bool { Auth.auth().currentUser?.isAnonymous ?? true }

    func signInAnonymouslyIfNeeded() async throws -> String {
        if let uid = currentUid { return uid }
        let result = try await Auth.auth().signInAnonymously()
        logger.info("Signed in anonymously")
        return result.user.uid
    }

    /// Links Apple to the current anonymous account, preserving its uid and all data.
    ///
    /// If the Apple ID already owns an account, linking fails with `credentialAlreadyInUse`
    /// — and that case *is* the recovery path we want: the user is returning on a new
    /// device, so we adopt the existing account and discard the throwaway anonymous uid.
    func signInWithApple(idToken: String, nonce: String) async throws {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken, rawNonce: nonce, fullName: nil
        )

        guard let user = Auth.auth().currentUser else {
            _ = try await Auth.auth().signIn(with: credential)
            return
        }

        do {
            _ = try await user.link(with: credential)
            logger.info("Linked anonymous account to Apple")
        } catch let error as NSError
                    where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
            logger.info("Apple ID already has an account — adopting it")
            _ = try await Auth.auth().signIn(with: credential)
        }
    }

    /// Raw nonce for Sign in with Apple. Apple receives its SHA-256; Firebase receives this.
    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).compactMap { _ in charset.randomElement() })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
```

`BirthdayQuestTests/MockAuthProviding.swift`:

```swift
import Foundation
@testable import BirthdayQuest

final class MockAuthProviding: AuthProviding {
    var currentUid: String?
    var isAnonymous = true
    var anonymousSignInCount = 0
    var appleSignIns: [(idToken: String, nonce: String)] = []
    var errorToThrow: Error?

    func signInAnonymouslyIfNeeded() async throws -> String {
        if let errorToThrow { throw errorToThrow }
        if let currentUid { return currentUid }
        anonymousSignInCount += 1
        let uid = "uid_anon_\(anonymousSignInCount)"
        currentUid = uid
        return uid
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        if let errorToThrow { throw errorToThrow }
        appleSignIns.append((idToken, nonce))
        isAnonymous = false
        currentUid = "uid_apple"
    }
}
```

- [ ] **Step 4: Run and confirm it passes**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/AuthTests test 2>&1 | /usr/bin/tail -20
```

Expected: PASS.

- [ ] **Step 5: Enable the capability**

In Xcode, add the **Sign in with Apple** capability to the BirthdayQuest target. In the
Firebase console, enable both the **Anonymous** and **Apple** sign-in providers.

- [ ] **Step 6: Commit**

```bash
git add BirthdayQuest/BirthdayQuest/Services/AuthService.swift BirthdayQuest/BirthdayQuestTests
git commit -m "Add anonymous auth with Apple linking

A server-verified uid replaces the client-generated deviceId, which is
what makes participant documents unforgeable. credentialAlreadyInUse is
treated as the recovery path rather than an error: a returning user on a
new device adopts their existing account."
```

---

### Task 9: AppSession

Replaces the auth-and-routing half of the deleted `SessionManager`. Knows about the signed-in
user and their occasions; knows nothing about any single occasion's contents.

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/Services/AppSession.swift`
- Test: `BirthdayQuest/BirthdayQuestTests/AppSessionTests.swift`

**Interfaces:**
- Consumes: `GameBackend.fetchMyOccasions()` (Task 7), `AuthProviding` (Task 8)
- Produces: `AppSession` with `@Published rootState: RootState`, `@Published occasions: [Occasion]`, `@Published isAnonymous: Bool`, `bootstrap() async`, `refreshOccasions() async`, `shouldPromptAppleLink: Bool`. Task 13 injects it as an `@EnvironmentObject`.

- [ ] **Step 1: Write the failing test**

`BirthdayQuest/BirthdayQuestTests/AppSessionTests.swift`:

```swift
import Testing
import Foundation
@testable import BirthdayQuest

@Suite("AppSession")
@MainActor
struct AppSessionTests {

    private func occasion(_ id: String) -> Occasion {
        Occasion(
            id: id, name: "Alex's 30th", occasionType: .birthday, celebrantName: "Alex",
            hostUid: "uid_host", occasionDate: Date(), isOpen: true, createdAt: Date(),
            contributorCode: "ABCD2345", celebrantCode: "EFGH6789"
        )
    }

    @Test("a signed-in user with no occasions lands on the empty state")
    func emptyState() async {
        let backend = MockGameBackend()
        let auth = MockAuthProviding()
        let session = AppSession(service: backend, auth: auth)

        await session.bootstrap()

        #expect(session.rootState == .empty)
        #expect(auth.anonymousSignInCount == 1)
    }

    @Test("a user with occasions lands on the list")
    func occasionList() async {
        let backend = MockGameBackend()
        backend.stubOccasions = [occasion("evt_1"), occasion("evt_2")]
        let session = AppSession(service: backend, auth: MockAuthProviding())

        await session.bootstrap()

        #expect(session.rootState == .occasions)
        #expect(session.occasions.count == 2)
    }

    @Test("a failed bootstrap surfaces an error rather than hanging on the splash")
    func bootstrapFailure() async {
        let auth = MockAuthProviding()
        auth.errorToThrow = NSError(domain: "test", code: 1)
        let session = AppSession(service: MockGameBackend(), auth: auth)

        await session.bootstrap()

        #expect(session.rootState != .launching)
        #expect(session.errorMessage != nil)
    }

    @Test("the Apple link prompt appears on the second occasion, not the first")
    func linkPromptTiming() async {
        let backend = MockGameBackend()
        let session = AppSession(service: backend, auth: MockAuthProviding())

        backend.stubOccasions = [occasion("evt_1")]
        await session.bootstrap()
        #expect(session.shouldPromptAppleLink == false)

        backend.stubOccasions = [occasion("evt_1"), occasion("evt_2")]
        await session.refreshOccasions()
        #expect(session.shouldPromptAppleLink == true)
    }
}
```

- [ ] **Step 2: Run and confirm it fails**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/AppSessionTests test 2>&1 | /usr/bin/grep -E 'error:'
```

Expected: `cannot find 'AppSession' in scope`.

- [ ] **Step 3: Implement**

`Services/AppSession.swift`:

```swift
import Foundation
import SwiftUI
import OSLog

@MainActor
final class AppSession: ObservableObject {

    enum RootState: Equatable {
        case launching
        case empty
        case occasions
    }

    @Published var rootState: RootState = .launching
    @Published var occasions: [Occasion] = []
    @Published var isAnonymous = true
    @Published var errorMessage: String?

    /// Friction arrives only once there is something to lose: a user with more than one
    /// occasion, or any host, has accumulated history worth recovering after a reinstall.
    var shouldPromptAppleLink: Bool {
        isAnonymous && occasions.count > 1
    }

    private let service: GameBackend
    private let auth: AuthProviding
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "AppSession")

    init(service: GameBackend = FirestoreService.shared, auth: AuthProviding = AuthService.shared) {
        self.service = service
        self.auth = auth
    }

    func bootstrap() async {
        do {
            _ = try await auth.signInAnonymouslyIfNeeded()
            isAnonymous = auth.isAnonymous
            await loadOccasions()
        } catch {
            logger.error("Bootstrap failed: \(error.localizedDescription)")
            errorMessage = "Couldn't reach BirthdayQuest. Check your connection and try again."
            // Never leave the user on the splash screen — that was the old bootstrap's
            // failure mode, an indefinite pulse with no explanation.
            rootState = .empty
        }
    }

    func refreshOccasions() async {
        await loadOccasions()
    }

    private func loadOccasions() async {
        do {
            let fetched = try await service.fetchMyOccasions()
            occasions = fetched.sorted { $0.occasionDate > $1.occasionDate }
            rootState = fetched.isEmpty ? .empty : .occasions
        } catch {
            logger.error("Loading occasions failed: \(error.localizedDescription)")
            errorMessage = "Couldn't load your occasions."
            rootState = occasions.isEmpty ? .empty : .occasions
        }
    }

    func linkApple(idToken: String, nonce: String) async {
        do {
            try await auth.signInWithApple(idToken: idToken, nonce: nonce)
            isAnonymous = auth.isAnonymous
            await loadOccasions()
        } catch {
            logger.error("Apple link failed: \(error.localizedDescription)")
            errorMessage = "Couldn't save your account. You can try again from Profile."
        }
    }
}
```

- [ ] **Step 4: Run and confirm it passes**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/AppSessionTests test 2>&1 | /usr/bin/tail -20
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BirthdayQuest/BirthdayQuest/Services/AppSession.swift BirthdayQuest/BirthdayQuestTests/AppSessionTests.swift
git commit -m "Add AppSession for auth state and the occasion list

Replaces the auth half of SessionManager. A failed bootstrap now lands on
a usable empty state with an error rather than pulsing on the splash
screen indefinitely."
```

---

### Task 10: Neutral avatars, DiceBear removed

`AvatarView` switches on five hardcoded names and otherwise calls `api.dicebear.com` live.
With arbitrary user names every render becomes an undisclosed third-party request carrying
a display name — a privacy-manifest problem and a network dependency on a render path.

**Files:**
- Rename: `Assets.xcassets/avatar-{alex,sam,jordan,riley,morgan}.imageset` → `avatar-0{1..5}.imageset`
- Modify: `BirthdayQuest/BirthdayQuest/Views/Components/AvatarView.swift` (full replacement)
- Create: `BirthdayQuest/BirthdayQuest/Models/AvatarCatalog.swift`
- Test: `BirthdayQuest/BirthdayQuestTests/AvatarCatalogTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `AvatarCatalog.all: [String]`, `AvatarCatalog.assetName(for:) -> String`, `AvatarCatalog.fallback: String`; and `AvatarView(avatarId: String, size: CGFloat, showsCrown: Bool)`.

- [ ] **Step 1: Rename the assets**

```bash
cd BirthdayQuest/BirthdayQuest/Assets.xcassets
for pair in "alex 01" "sam 02" "jordan 03" "riley 04" "morgan 05"; do
  set -- $pair
  git mv "avatar-$1.imageset" "avatar-$2.imageset"
done
cd -
```

Then edit each renamed folder's `Contents.json` so the `filename` entries still point at the
image files inside — renaming the folder does not rename the PNGs, and a mismatch renders
blank.

Five avatars is thin for an occasion with a dozen guests. Duplicates are permitted:
participants are distinguished by name, and expanding the art set is a design task in
subsystem #4, not a blocker here.

- [ ] **Step 2: Write the failing test**

`BirthdayQuest/BirthdayQuestTests/AvatarCatalogTests.swift`:

```swift
import Testing
@testable import BirthdayQuest

@Suite("Avatar catalog")
struct AvatarCatalogTests {

    @Test("every catalog id maps to a bundled asset name")
    func assetNames() {
        for id in AvatarCatalog.all {
            #expect(AvatarCatalog.assetName(for: id).hasPrefix("avatar-"))
        }
    }

    @Test("an unknown id falls back to a bundled asset, never a network call")
    func unknownIdFallsBack() {
        let name = AvatarCatalog.assetName(for: "not-a-real-avatar")
        #expect(AvatarCatalog.all.contains { AvatarCatalog.assetName(for: $0) == name })
    }

    @Test("the catalog is not empty and has no duplicates")
    func catalogShape() {
        #expect(!AvatarCatalog.all.isEmpty)
        #expect(Set(AvatarCatalog.all).count == AvatarCatalog.all.count)
    }
}
```

- [ ] **Step 3: Implement the catalog**

`Models/AvatarCatalog.swift`:

```swift
import Foundation

/// The bundled avatar set. Everything renders from the asset catalog — there is no network
/// path, which is deliberate: the previous implementation sent every unrecognised display
/// name to a third-party image API on each render.
enum AvatarCatalog {
    static let all: [String] = ["01", "02", "03", "04", "05"]

    static let fallback = "01"

    static func assetName(for avatarId: String) -> String {
        let id = all.contains(avatarId) ? avatarId : fallback
        return "avatar-\(id)"
    }
}
```

- [ ] **Step 4: Replace AvatarView**

`Views/Components/AvatarView.swift`:

```swift
import SwiftUI

/// Renders a participant's avatar from the bundled catalog.
///
/// Takes an `avatarId`, not a name. The old implementation keyed off `name`, which meant
/// renaming anyone silently changed their face and any unknown name triggered a live HTTP
/// request to api.dicebear.com carrying that name.
struct AvatarView: View {

    let avatarId: String
    var size: CGFloat = 64
    var showsCrown: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(AvatarCatalog.assetName(for: avatarId))
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(
                        BQDesign.Colors.cardBackground,
                        lineWidth: size > 48 ? 3 : 2
                    )
                )

            if showsCrown {
                Text("👑")
                    .font(.system(size: size * 0.32))
                    .offset(x: size * 0.06, y: -size * 0.10)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: BQDesign.Spacing.md) {
        ForEach(AvatarCatalog.all, id: \.self) { id in
            AvatarView(avatarId: id, size: 64, showsCrown: id == AvatarCatalog.all.first)
        }
    }
    .padding()
    .background(BQDesign.Colors.background)
}
```

- [ ] **Step 5: Run and confirm the tests pass**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/AvatarCatalogTests test 2>&1 | /usr/bin/tail -20
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A BirthdayQuest/BirthdayQuest/Assets.xcassets BirthdayQuest/BirthdayQuest/Views/Components/AvatarView.swift BirthdayQuest/BirthdayQuest/Models/AvatarCatalog.swift BirthdayQuest/BirthdayQuestTests/AvatarCatalogTests.swift
git commit -m "Render avatars from the bundle instead of DiceBear

AvatarView keyed off name and fell through to a live api.dicebear.com
request for anything outside the original five characters, leaking a
display name to a third party on every render. It now takes an avatarId
and resolves entirely from the asset catalog, which also finally gives
the long-unused avatarId field a purpose."
```

---

### Task 11: Create an occasion

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/ViewModels/CreateOccasionViewModel.swift`
- Create: `BirthdayQuest/BirthdayQuest/Views/Occasions/CreateOccasionView.swift`
- Test: `BirthdayQuest/BirthdayQuestTests/CreateOccasionTests.swift`

**Interfaces:**
- Consumes: `GameBackend.createOccasion(...)` and `.inviteCodes(eventId:)` (Task 7); `AvatarCatalog` (Task 10)
- Produces: `CreateOccasionViewModel` with `@Published name/celebrantName/occasionType/occasionDate/hostName/hostAvatarId`, `canSubmit: Bool`, `create() async -> String?`.

- [ ] **Step 1: Write the failing test**

`BirthdayQuest/BirthdayQuestTests/CreateOccasionTests.swift`:

```swift
import Testing
import Foundation
@testable import BirthdayQuest

@Suite("Create occasion")
@MainActor
struct CreateOccasionTests {

    @Test("submission is blocked until the required fields are filled")
    func validation() {
        let vm = CreateOccasionViewModel(service: MockGameBackend())
        #expect(vm.canSubmit == false)

        vm.name = "Alex's 30th"
        #expect(vm.canSubmit == false)

        vm.celebrantName = "Alex"
        vm.hostName = "Sam"
        #expect(vm.canSubmit == true)
    }

    @Test("whitespace-only input does not count as filled")
    func rejectsWhitespace() {
        let vm = CreateOccasionViewModel(service: MockGameBackend())
        vm.name = "   "
        vm.celebrantName = "Alex"
        vm.hostName = "Sam"
        #expect(vm.canSubmit == false)
    }

    @Test("creating passes the chosen occasion type through to the backend")
    func passesTypeThrough() async {
        let mock = MockGameBackend()
        let vm = CreateOccasionViewModel(service: mock)
        vm.name = "Priya's farewell"
        vm.celebrantName = "Priya"
        vm.hostName = "Sam"
        vm.occasionType = .farewell

        let eventId = await vm.create()

        #expect(eventId == "evt_mock")
        #expect(mock.createdOccasions.first?.type == .farewell)
    }

    @Test("a backend failure surfaces a message and no event id")
    func failureSurfaces() async {
        let mock = MockGameBackend()
        mock.errorToThrow = NSError(domain: "test", code: 1)
        let vm = CreateOccasionViewModel(service: mock)
        vm.name = "X"; vm.celebrantName = "Y"; vm.hostName = "Z"

        let eventId = await vm.create()

        #expect(eventId == nil)
        #expect(vm.errorMessage != nil)
        #expect(vm.isSubmitting == false)
    }
}
```

- [ ] **Step 2: Run and confirm it fails**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/CreateOccasionTests test 2>&1 | /usr/bin/grep -E 'error:'
```

Expected: `cannot find 'CreateOccasionViewModel' in scope`. `MockGameBackend` already declares `var errorToThrow: Error?` (`MockGameBackend.swift:44`); make sure `createOccasion` and `joinOccasion` both honour it.

- [ ] **Step 3: Implement the view model**

`ViewModels/CreateOccasionViewModel.swift`:

```swift
import Foundation
import OSLog

@MainActor
final class CreateOccasionViewModel: ObservableObject {

    @Published var name = ""
    @Published var celebrantName = ""
    @Published var occasionType: OccasionType = .birthday
    @Published var occasionDate = Date()
    @Published var hostName = ""
    @Published var hostAvatarId = AvatarCatalog.fallback

    @Published var isSubmitting = false
    @Published var errorMessage: String?

    private let service: GameBackend
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "CreateOccasion")

    init(service: GameBackend = FirestoreService.shared) {
        self.service = service
    }

    var canSubmit: Bool {
        !isSubmitting
            && !name.trimmed.isEmpty
            && !celebrantName.trimmed.isEmpty
            && !hostName.trimmed.isEmpty
    }

    /// Returns the new event id, or nil if creation failed.
    func create() async -> String? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            return try await service.createOccasion(
                name: name.trimmed,
                occasionType: occasionType,
                celebrantName: celebrantName.trimmed,
                occasionDate: occasionDate,
                hostName: hostName.trimmed,
                hostAvatarId: hostAvatarId
            )
        } catch {
            logger.error("Create occasion failed: \(error.localizedDescription)")
            errorMessage = "Couldn't create the occasion. Check your connection and try again."
            return nil
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
```

- [ ] **Step 4: Implement the view**

`Views/Occasions/CreateOccasionView.swift`:

```swift
import SwiftUI

struct CreateOccasionView: View {

    @StateObject private var viewModel = CreateOccasionViewModel()
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("The occasion") {
                    TextField("Name it", text: $viewModel.name)
                    Picker("Type", selection: $viewModel.occasionType) {
                        ForEach(OccasionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    DatePicker(
                        "Date", selection: $viewModel.occasionDate, displayedComponents: .date
                    )
                }

                Section(viewModel.occasionType.celebrantLabel) {
                    TextField("Who is this for?", text: $viewModel.celebrantName)
                }

                Section("You") {
                    TextField("Your name", text: $viewModel.hostName)
                    AvatarPicker(selection: $viewModel.hostAvatarId)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(BQDesign.Colors.error)
                    }
                }
            }
            .navigationTitle("New occasion")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if await viewModel.create() != nil {
                                await session.refreshOccasions()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .overlay {
                if viewModel.isSubmitting { ProgressView() }
            }
        }
    }
}

/// Horizontal avatar strip. Shared by create and join.
struct AvatarPicker: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BQDesign.Spacing.sm) {
                ForEach(AvatarCatalog.all, id: \.self) { id in
                    Button {
                        BQDesign.Haptics.light()
                        selection = id
                    } label: {
                        AvatarView(avatarId: id, size: 56)
                            .overlay(
                                Circle().strokeBorder(
                                    selection == id
                                        ? BQDesign.Colors.accent : .clear,
                                    lineWidth: 3
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Avatar \(id)")
                    .accessibilityAddTraits(selection == id ? [.isSelected] : [])
                }
            }
            .padding(.vertical, BQDesign.Spacing.xs)
        }
    }
}
```

If `BQDesign.Colors.error` or `.accent` do not exist, use the nearest existing token in
`DesignSystem.swift` rather than introducing a hardcoded color.

- [ ] **Step 5: Run and confirm the tests pass**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/CreateOccasionTests test 2>&1 | /usr/bin/tail -20
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add BirthdayQuest/BirthdayQuest/ViewModels/CreateOccasionViewModel.swift BirthdayQuest/BirthdayQuest/Views/Occasions BirthdayQuest/BirthdayQuestTests/CreateOccasionTests.swift
git commit -m "Add occasion creation

A host names the occasion, picks a type and date, names the celebrant, and
registers themselves. Occasion type drives the celebrant label, replacing
hardcoded gendered copy."
```

---

### Task 12: Join an occasion

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/ViewModels/JoinOccasionViewModel.swift`
- Create: `BirthdayQuest/BirthdayQuest/Views/Occasions/JoinOccasionView.swift`
- Test: `BirthdayQuest/BirthdayQuestTests/JoinOccasionTests.swift`

**Interfaces:**
- Consumes: `GameBackend.joinOccasion(eventId:code:name:avatarId:mode:)` (Task 7); `AvatarPicker` (Task 11)
- Produces: `JoinOccasionViewModel` with `parse(link:) -> Bool`, `@Published eventId/code/name/avatarId/mode`, `canSubmit`, `join() async -> Bool`. Deep link scheme `birthdayquest://join?e=<eventId>&c=<CODE>`.

- [ ] **Step 1: Write the failing test**

`BirthdayQuest/BirthdayQuestTests/JoinOccasionTests.swift`:

```swift
import Testing
import Foundation
@testable import BirthdayQuest

@Suite("Join occasion")
@MainActor
struct JoinOccasionTests {

    @Test("a valid deep link populates the event id and code")
    func parsesLink() {
        let vm = JoinOccasionViewModel(service: MockGameBackend())
        #expect(vm.parse(link: URL(string: "birthdayquest://join?e=evt_1&c=ABCD2345")!))
        #expect(vm.eventId == "evt_1")
        #expect(vm.code == "ABCD2345")
    }

    @Test("a link missing either parameter is rejected")
    func rejectsIncompleteLink() {
        let vm = JoinOccasionViewModel(service: MockGameBackend())
        #expect(vm.parse(link: URL(string: "birthdayquest://join?e=evt_1")!) == false)
        #expect(vm.parse(link: URL(string: "birthdayquest://join?c=ABCD2345")!) == false)
        #expect(vm.parse(link: URL(string: "https://example.com/join?e=a&c=b")!) == false)
    }

    @Test("codes are normalised to uppercase before submission")
    func normalisesCode() async {
        let mock = MockGameBackend()
        let vm = JoinOccasionViewModel(service: mock)
        vm.eventId = "evt_1"
        vm.code = "abcd2345"
        vm.name = "Jordan"

        _ = await vm.join()

        #expect(mock.joinedOccasions.first?.code == "ABCD2345")
    }

    @Test("a rejected code surfaces a specific message, not a generic failure")
    func invalidCodeMessage() async {
        let mock = MockGameBackend()
        mock.errorToThrow = BackendError.invalidCode
        let vm = JoinOccasionViewModel(service: mock)
        vm.eventId = "evt_1"; vm.code = "WRONG123"; vm.name = "Jordan"

        #expect(await vm.join() == false)
        #expect(vm.errorMessage?.contains("invite") == true)
    }
}
```

- [ ] **Step 2: Run and confirm it fails**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/JoinOccasionTests test 2>&1 | /usr/bin/grep -E 'error:'
```

Expected: `cannot find 'JoinOccasionViewModel' in scope`.

- [ ] **Step 3: Implement the view model**

`ViewModels/JoinOccasionViewModel.swift`:

```swift
import Foundation
import OSLog

@MainActor
final class JoinOccasionViewModel: ObservableObject {

    @Published var eventId = ""
    @Published var code = ""
    @Published var name = ""
    @Published var avatarId = AvatarCatalog.fallback
    @Published var mode: ParticipantMode = .contributor

    @Published var isSubmitting = false
    @Published var errorMessage: String?

    private let service: GameBackend
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "JoinOccasion")

    init(service: GameBackend = FirestoreService.shared) {
        self.service = service
    }

    var canSubmit: Bool {
        !isSubmitting && !eventId.isEmpty && !code.isEmpty
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `birthdayquest://join?e=<eventId>&c=<CODE>`
    ///
    /// Both parameters are required: the invite-code collection is deny-all so a client
    /// cannot resolve an event id from a code, which is what stops codes being enumerated.
    func parse(link: URL) -> Bool {
        guard link.scheme == "birthdayquest", link.host == "join",
              let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
              let event = items.first(where: { $0.name == "e" })?.value, !event.isEmpty,
              let inviteCode = items.first(where: { $0.name == "c" })?.value, !inviteCode.isEmpty
        else { return false }

        eventId = event
        code = inviteCode.uppercased()
        return true
    }

    func join() async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await service.joinOccasion(
                eventId: eventId,
                code: code.uppercased(),
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarId: avatarId,
                mode: mode
            )
            return true
        } catch BackendError.invalidCode {
            errorMessage = "That invite link doesn't work. Ask for a fresh one."
            return false
        } catch {
            logger.error("Join failed: \(error.localizedDescription)")
            errorMessage = "Couldn't join. Check your connection and try again."
            return false
        }
    }
}
```

- [ ] **Step 4: Implement the view**

`Views/Occasions/JoinOccasionView.swift`:

```swift
import SwiftUI

struct JoinOccasionView: View {

    @StateObject private var viewModel = JoinOccasionViewModel()
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    /// Set when arriving from a deep link; nil when the user opened this manually.
    var incomingLink: URL?

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.eventId.isEmpty {
                    Section("Invite") {
                        Text("Open the invite link your host sent you to join.")
                            .foregroundStyle(BQDesign.Colors.textSecondary)
                    }
                } else {
                    Section("You") {
                        TextField("Your name", text: $viewModel.name)
                        AvatarPicker(selection: $viewModel.avatarId)
                    }
                    Section("Your role") {
                        Picker("I'm joining as", selection: $viewModel.mode) {
                            Text("A friend").tag(ParticipantMode.contributor)
                            Text("The guest of honour").tag(ParticipantMode.celebrant)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(BQDesign.Colors.error)
                    }
                }
            }
            .navigationTitle("Join an occasion")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        Task {
                            if await viewModel.join() {
                                await session.refreshOccasions()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .task {
                if let incomingLink { _ = viewModel.parse(link: incomingLink) }
            }
        }
    }
}
```

- [ ] **Step 5: Register the URL scheme**

In the target's Info settings, add a URL type with scheme `birthdayquest`. In
`BirthdayQuestApp.swift`, add `.onOpenURL { … }` to route an incoming link into
`JoinOccasionView(incomingLink:)`. Wire the actual presentation in Task 13, where the root
view is rebuilt.

- [ ] **Step 6: Run and confirm the tests pass**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/JoinOccasionTests test 2>&1 | /usr/bin/tail -20
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add BirthdayQuest/BirthdayQuest/ViewModels/JoinOccasionViewModel.swift BirthdayQuest/BirthdayQuest/Views/Occasions/JoinOccasionView.swift BirthdayQuest/BirthdayQuestTests/JoinOccasionTests.swift
git commit -m "Add occasion joining via invite link

The link carries both event id and code because the invite-code collection
is deny-all, so a client cannot resolve one from the other — which is what
prevents codes being enumerated. A rejected code reports as an invite
problem rather than a generic failure."
```

---

### Task 13: EventSession and the navigation rewrite

Restores a compiling, launchable app. Replaces `SessionManager`, the four-case `AppState`
router, and the character-select root.

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/Services/EventSession.swift`
- Create: `BirthdayQuest/BirthdayQuest/Views/Occasions/OccasionListView.swift`
- Create: `BirthdayQuest/BirthdayQuest/Views/Occasions/EventContainerView.swift`
- Modify: `BirthdayQuest/BirthdayQuest/ContentView.swift` (full replacement)
- Modify: `BirthdayQuest/BirthdayQuest/BirthdayQuestApp.swift`
- Rename: `Views/BirthdayBoy/BirthdayBoyTabView.swift` → `Views/Celebrant/CelebrantTabView.swift`
- Rename: `Views/Friend/FriendTabView.swift` → `Views/Contributor/ContributorTabView.swift`
- Modify: `Views/Profile/ProfileView.swift`, `Views/Friend/SecretChallengeHomeView.swift`, `ViewModels/AdminViewModel.swift`, and every view model that took no `eventId`
- Delete: `BirthdayQuest/BirthdayQuest/Services/SessionManager.swift`
- Delete: `BirthdayQuest/BirthdayQuest/ViewModels/CharacterSelectViewModel.swift`
- Delete: `BirthdayQuest/BirthdayQuest/Views/CharacterSelect/CharacterSelectView.swift`

**Interfaces:**
- Consumes: everything from Tasks 4–12
- Produces: `EventSession` with `@Published participant: Participant?`, `@Published gameState: GameState`, `@Published occasion: Occasion?`, `start() async`, `stop()`; and a root that routes `AppSession.RootState` → occasion list → `EventContainerView`.

- [ ] **Step 1: Implement EventSession**

`Services/EventSession.swift`:

```swift
import Foundation
import SwiftUI
import OSLog

/// One occasion's scope. Created when the user opens an occasion, destroyed when they leave.
///
/// Because listeners are owned by an instance whose lifetime *is* the occasion's, they are
/// scoped by construction and torn down together. The named-listener-key scheme that
/// previously prevented collisions is no longer load-bearing.
@MainActor
final class EventSession: ObservableObject {

    let eventId: String

    @Published var occasion: Occasion?
    @Published var participant: Participant?
    @Published var gameState: GameState = .empty
    @Published var errorMessage: String?
    @Published var isLoading = true

    var isHost: Bool { participant?.isHost ?? false }
    var isCelebrant: Bool { participant?.isCelebrant ?? false }
    var currentPoints: Int { gameState.currentPoints }

    private let service: GameBackend
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "EventSession")

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
    }

    func start() async {
        do {
            occasion = try await service.fetchOccasion(eventId: eventId)
            participant = try await service.fetchMyParticipant(eventId: eventId)
            isLoading = false
        } catch {
            logger.error("Opening occasion failed: \(error.localizedDescription)")
            errorMessage = "Couldn't open this occasion."
            isLoading = false
            return
        }

        service.listenToGameState(eventId: eventId) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let state):
                    self.gameState = state
                case .failure(let error):
                    self.logger.error("Game state listener: \(error.localizedDescription)")
                    self.errorMessage = "Lost the connection to this occasion."
                }
            }
        }
    }

    func stop() {
        service.removeAllListeners()
    }
}
```

- [ ] **Step 2: Implement the occasion list**

`Views/Occasions/OccasionListView.swift`:

```swift
import SwiftUI

struct OccasionListView: View {

    @EnvironmentObject private var session: AppSession
    @State private var creating = false
    @State private var joining = false
    @State private var openEventId: String?

    private var active: [Occasion] { session.occasions.filter(\.isOpen) }
    private var past: [Occasion] { session.occasions.filter { !$0.isOpen } }

    var body: some View {
        NavigationStack {
            List {
                if !active.isEmpty {
                    Section("Active") {
                        ForEach(active) { row($0) }
                    }
                }
                if !past.isEmpty {
                    Section("Past") {
                        ForEach(past) { row($0) }
                    }
                }
            }
            .navigationTitle("My Occasions")
            .refreshable { await session.refreshOccasions() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Create an occasion") { creating = true }
                        Button("Join with a link") { joining = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add an occasion")
                }
            }
            .sheet(isPresented: $creating) { CreateOccasionView() }
            .sheet(isPresented: $joining) { JoinOccasionView() }
            .navigationDestination(item: $openEventId) { eventId in
                EventContainerView(eventId: eventId)
            }
        }
    }

    private func row(_ occasion: Occasion) -> some View {
        Button {
            openEventId = occasion.id
        } label: {
            VStack(alignment: .leading, spacing: BQDesign.Spacing.xxs) {
                Text(occasion.name)
                    .font(BQDesign.Typography.cardTitle)
                Text("\(occasion.occasionType.displayName) · \(occasion.celebrantName)")
                    .font(BQDesign.Typography.caption)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
            }
        }
    }
}
```

- [ ] **Step 3: Implement the container and the root**

`Views/Occasions/EventContainerView.swift`:

```swift
import SwiftUI

struct EventContainerView: View {

    let eventId: String
    @StateObject private var event: EventSession

    init(eventId: String) {
        self.eventId = eventId
        _event = StateObject(wrappedValue: EventSession(eventId: eventId))
    }

    var body: some View {
        Group {
            if event.isLoading {
                ProgressView()
            } else if let message = event.errorMessage, event.participant == nil {
                ContentUnavailableView("Can't open this", systemImage: "lock", description: Text(message))
            } else if event.isCelebrant {
                CelebrantTabView()
            } else {
                ContributorTabView()
            }
        }
        .environmentObject(event)
        .task { await event.start() }
        .onDisappear { event.stop() }
    }
}
```

`ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var session: AppSession
    @State private var pendingJoinLink: URL?

    var body: some View {
        Group {
            switch session.rootState {
            case .launching:
                LoadingView()
            case .empty:
                EmptyOccasionsView()
            case .occasions:
                OccasionListView()
            }
        }
        .task { await session.bootstrap() }
        .onOpenURL { pendingJoinLink = $0 }
        .sheet(item: $pendingJoinLink) { link in
            JoinOccasionView(incomingLink: link)
        }
    }
}

struct EmptyOccasionsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var creating = false
    @State private var joining = false

    var body: some View {
        ZStack {
            BQDesign.Colors.background.ignoresSafeArea()
            VStack(spacing: BQDesign.Spacing.lg) {
                Text("👑").font(.system(size: 56))
                Text("No occasions yet")
                    .font(BQDesign.Typography.heroTitle)
                    .foregroundStyle(BQDesign.Colors.primaryGradient)
                Text("Create one for someone you love, or join with an invite link.")
                    .font(BQDesign.Typography.body)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BQDesign.Spacing.xl)

                VStack(spacing: BQDesign.Spacing.sm) {
                    Button("Create an occasion") { creating = true }
                        .buttonStyle(.borderedProminent)
                    Button("Join with a link") { joining = true }
                }

                if let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .font(BQDesign.Typography.caption)
                        .foregroundStyle(BQDesign.Colors.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BQDesign.Spacing.xl)
                }
            }
        }
        .sheet(isPresented: $creating) { CreateOccasionView() }
        .sheet(isPresented: $joining) { JoinOccasionView() }
    }
}
```

Keep `LoadingView` from the existing `ContentView.swift` unchanged. `URL` needs
`Identifiable` conformance for `.sheet(item:)`; add it in an extension in
`Extensions/View+Extensions.swift`:

```swift
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
```

In `BirthdayQuestApp.swift`, replace the `SessionManager` state object:

```swift
    @StateObject private var session = AppSession()
```

and inject it: `ContentView().environmentObject(session)`.

- [ ] **Step 4: Sweep the remaining views and view models**

Every view model that reached a global now takes `eventId`. Mechanically, for each of
`RewardsViewModel`, `ChallengesViewModel`, `TimelineViewModel`, `SecretChallengeViewModel`,
`ProfileViewModel`, `ChallengeSubmissionViewModel` and `AdminViewModel`:

1. Add `private let eventId: String` and accept it in `init`.
2. Pass `eventId:` to every `service.` call.
3. Where the view previously read `SessionManager.shared`, read `@EnvironmentObject var event: EventSession` instead.

In views, replace:

| Old | New |
|---|---|
| `session.isOrganizer` | `event.isHost` |
| `session.isBirthdayBoy` | `event.isCelebrant` |
| `session.currentUser?.name` | `event.participant?.name` |
| `session.gameState` | `event.gameState` |
| `AvatarView(name: user.name, …)` | `AvatarView(avatarId: participant.avatarId, …)` |
| `CharacterID.birthdayBoyName` | `event.occasion?.celebrantName ?? ""` |
| `"Deliver to Birthday Boy"` | `"Deliver to \(event.occasion?.celebrantName ?? "them")"` |
| `"waiting on him..."` | `"waiting on them..."` |

Delete the `ProfileView` per-character emoji map keyed by the old document IDs, and the
`AdminViewModel` reference to `CharacterID.organizer`.

- [ ] **Step 5: Build and run the full suite**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | /usr/bin/tail -30
cd firebase-tests && npm test
```

Expected: clean build, all Swift tests pass, all rules tests pass. **This is the gate that
closes the migration window** — do not proceed until the build is green.

- [ ] **Step 6: Manual two-device check**

This is the acceptance test for the whole plan, and it cannot be automated:

1. Simulator A: create an occasion. Note the invite link.
2. Simulator B (erase first, so it gets a fresh anonymous uid): open the link, join as a friend.
3. Confirm B sees the occasion in *their* list and A sees B in the roster.
4. Simulator C: create a *different* occasion. Confirm A and C see only their own, and that
   neither list leaks the other's name, points, or timeline.

- [ ] **Step 7: Commit**

```bash
git add -A BirthdayQuest
git commit -m "Replace the single-session root with per-occasion sessions

AppSession owns auth and the occasion list; EventSession owns one
occasion's data and listeners, so listeners are scoped by object lifetime
rather than by naming convention. Character select, the override PIN and
SessionManager are deleted.

Two isolated occasions can now run concurrently on separate devices."
```

---

### Task 14: Retire the timeline title prefixes

The last audit bug. Timeline titles are written as `"Completed: …"` and `"Unlocked: …"` in
four places, then parsed back off those literal prefixes at `TimelineNodeView.swift:254`.
`TimelineEvent` already carries a `type` field, so the parsing is pure redundancy — and it
cannot survive an app with five occasion types and non-English copy.

**Files:**
- Modify: `BirthdayQuest/BirthdayQuest/Views/Timeline/TimelineNodeView.swift:254`
- Modify: `BirthdayQuest/BirthdayQuest/ViewModels/ChallengeSubmissionViewModel.swift:96`
- Modify: `BirthdayQuest/BirthdayQuest/ViewModels/RewardsViewModel.swift:88`
- Modify: `BirthdayQuest/BirthdayQuest/ViewModels/AdminViewModel.swift:99,143`
- Test: `BirthdayQuest/BirthdayQuestTests/TimelineNodeTests.swift`

**Interfaces:**
- Consumes: `TimelineEvent.type` (already present, `Models/TimelineEvent.swift:29`)
- Produces: no new API. Titles become plain names; presentation derives from `type`.

- [ ] **Step 1: Write the failing test**

`BirthdayQuest/BirthdayQuestTests/TimelineNodeTests.swift`:

```swift
import Testing
import Foundation
@testable import BirthdayQuest

@Suite("Timeline node presentation")
struct TimelineNodeTests {

    private func event(type: TimelineEventType, title: String) -> TimelineEvent {
        TimelineEvent(
            id: "t1", type: type, referenceId: "r1", title: title, subtitle: "+50 ✦",
            badgeType: type == .rewardUnlocked ? .reward : .challenge,
            badgeAsset: "b", fromFriendName: nil, fromFriendAvatar: nil, timestamp: Date()
        )
    }

    @Test("the displayed title is the raw title, with no prefix stripping")
    func titleIsNotParsed() {
        let e = event(type: .challengeCompleted, title: "Convince a stranger")
        #expect(TimelineNodeView.displayTitle(for: e) == "Convince a stranger")
    }

    @Test("a title that happens to contain a colon is left intact")
    func colonInTitleSurvives() {
        let e = event(type: .rewardUnlocked, title: "Chapter 2: the toast")
        #expect(TimelineNodeView.displayTitle(for: e) == "Chapter 2: the toast")
    }

    @Test("the kind label comes from the event type, not the title text")
    func kindFromType() {
        #expect(TimelineNodeView.kindLabel(for: event(type: .challengeCompleted, title: "x")) == "Challenge")
        #expect(TimelineNodeView.kindLabel(for: event(type: .rewardUnlocked, title: "x")) == "Gift")
    }
}
```

- [ ] **Step 2: Run and confirm it fails**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/TimelineNodeTests test 2>&1 | /usr/bin/grep -E 'error:'
```

Expected: `displayTitle` and `kindLabel` do not exist.

- [ ] **Step 3: Replace the parsing with type dispatch**

In `Views/Timeline/TimelineNodeView.swift`, delete the prefix-stripping at line 254 and add:

```swift
extension TimelineNodeView {

    /// The title as written. Previously this stripped a `"Completed: "` / `"Unlocked: "`
    /// prefix, which broke on any title containing a colon and could not survive
    /// non-English copy.
    static func displayTitle(for event: TimelineEvent) -> String {
        event.title
    }

    static func kindLabel(for event: TimelineEvent) -> String {
        switch event.type {
        case .challengeCompleted: return "Challenge"
        case .rewardUnlocked:     return "Gift"
        }
    }
}
```

Update the view body to call `Self.displayTitle(for: event)` and `Self.kindLabel(for: event)`.

- [ ] **Step 4: Write plain titles at the four sources**

| File:line | Old | New |
|---|---|---|
| `ChallengeSubmissionViewModel.swift:96` | `"Completed: \(challenge.title)"` | `challenge.title` |
| `RewardsViewModel.swift:88` | `"Unlocked: \(reward.title)"` | `reward.title` |
| `AdminViewModel.swift:99` | `"Completed: \(challenge.title)"` | `challenge.title` |
| `AdminViewModel.swift:143` | `"Unlocked: \(reward.title)"` | `reward.title` |

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | /usr/bin/tail -20
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add BirthdayQuest
git commit -m "Derive timeline presentation from event type, not title text

Titles were written with a 'Completed: ' prefix and parsed back off it,
which broke on any title containing a colon and could not survive
non-English copy. TimelineEvent already carries a type field, so the
parsing was redundant."
```

---

---

### Task 15: Host controls — sharing the invite and closing the occasion

Without this the plan is unusable: a host can create an occasion but has no way to invite
anyone, and `isOpen` has no UI despite being the reveal gate you chose over a state machine.

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/Views/Occasions/HostControlsView.swift`
- Modify: `BirthdayQuest/BirthdayQuest/Views/Occasions/CreateOccasionView.swift`
- Modify: `BirthdayQuest/BirthdayQuest/Views/Profile/ProfileView.swift`
- Test: `BirthdayQuest/BirthdayQuestTests/HostControlsTests.swift`

**Interfaces:**
- Consumes: `Occasion.contributorLink`, `Occasion.celebrantLink` (Task 4); `GameBackend.setOccasionOpen(eventId:isOpen:)`, `.fetchParticipants(eventId:)` (Task 7); `EventSession` (Task 13)
- Produces: `HostControlsView`, shown from `ProfileView` when `event.isHost`.

- [ ] **Step 1: Write the failing test**

`BirthdayQuest/BirthdayQuestTests/HostControlsTests.swift`:

```swift
import Testing
import Foundation
@testable import BirthdayQuest

@Suite("Host controls")
struct HostControlsTests {

    private func occasion(id: String?) -> Occasion {
        Occasion(
            id: id, name: "Alex's 30th", occasionType: .birthday, celebrantName: "Alex",
            hostUid: "uid_host", occasionDate: Date(), isOpen: true, createdAt: Date(),
            contributorCode: "ABCD2345", celebrantCode: "EFGH6789"
        )
    }

    @Test("the contributor link carries both the event id and the contributor code")
    func contributorLink() {
        let url = occasion(id: "evt_1").contributorLink
        #expect(url?.absoluteString == "birthdayquest://join?e=evt_1&c=ABCD2345")
    }

    @Test("the celebrant link uses the celebrant code, not the contributor one")
    func celebrantLinkIsDistinct() {
        let o = occasion(id: "evt_1")
        #expect(o.celebrantLink?.absoluteString.contains("EFGH6789") == true)
        #expect(o.celebrantLink != o.contributorLink)
    }

    @Test("closing an occasion is reported to the backend")
    func closeOccasion() async throws {
        let mock = MockGameBackend()
        try await mock.setOccasionOpen(eventId: "evt_1", isOpen: false)
        #expect(mock.openStateChanges.first?.isOpen == false)
    }
}
```

Add to `MockGameBackend`:

```swift
    var openStateChanges: [(eventId: String, isOpen: Bool)] = []

    func setOccasionOpen(eventId: String, isOpen: Bool) async throws {
        if let errorToThrow { throw errorToThrow }
        openStateChanges.append((eventId, isOpen))
    }
```

- [ ] **Step 2: Run and confirm it fails**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/HostControlsTests test 2>&1 | /usr/bin/grep -E 'error:'
```

Expected: `openStateChanges` does not exist.

- [ ] **Step 3: Implement the view**

`Views/Occasions/HostControlsView.swift`:

```swift
import SwiftUI

struct HostControlsView: View {

    @EnvironmentObject private var event: EventSession
    @State private var participants: [Participant] = []
    @State private var isWorking = false

    private var celebrantHasJoined: Bool {
        participants.contains { $0.isCelebrant }
    }

    var body: some View {
        List {
            Section("Invite friends") {
                if let link = event.occasion?.contributorLink {
                    ShareLink(item: link) {
                        Label("Share the friend link", systemImage: "square.and.arrow.up")
                    }
                    Text(event.occasion?.contributorCode ?? "")
                        .font(BQDesign.Typography.caption.monospaced())
                        .foregroundStyle(BQDesign.Colors.textSecondary)
                }
            }

            Section {
                if let link = event.occasion?.celebrantLink {
                    ShareLink(item: link) {
                        Label(
                            "Share the \(event.occasion?.occasionType.celebrantLabel ?? "guest") link",
                            systemImage: "gift"
                        )
                    }
                }
            } header: {
                Text("Invite the guest of honour")
            } footer: {
                // There is no handover mode by design, so the celebrant must install the
                // app. Surfacing that here, early, is the mitigation for an occasion that
                // would otherwise stall silently on the day.
                if celebrantHasJoined {
                    Label(
                        "\(event.occasion?.celebrantName ?? "They") have joined.",
                        systemImage: "checkmark.circle"
                    )
                } else {
                    Label(
                        "\(event.occasion?.celebrantName ?? "They") haven't joined yet. "
                        + "They need the app installed to open their gifts.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(BQDesign.Colors.error)
                }
            }

            Section("Roster") {
                ForEach(participants) { participant in
                    HStack(spacing: BQDesign.Spacing.sm) {
                        AvatarView(avatarId: participant.avatarId, size: 36)
                        VStack(alignment: .leading) {
                            Text(participant.name)
                            Text(participant.isCelebrant ? "Guest of honour" : "Friend")
                                .font(BQDesign.Typography.caption)
                                .foregroundStyle(BQDesign.Colors.textSecondary)
                        }
                    }
                }
                if participants.isEmpty {
                    Text("No one has joined yet.")
                        .foregroundStyle(BQDesign.Colors.textSecondary)
                }
            }

            Section {
                Toggle("Open for play", isOn: Binding(
                    get: { event.occasion?.isOpen ?? false },
                    set: { newValue in
                        Task { await setOpen(newValue) }
                    }
                ))
                .disabled(isWorking)
            } footer: {
                Text("Closed occasions move to Past and become read-only.")
            }
        }
        .navigationTitle("Host tools")
        .task { await loadRoster() }
        .refreshable { await loadRoster() }
    }

    private func loadRoster() async {
        participants = (try? await FirestoreService.shared
            .fetchParticipants(eventId: event.eventId)) ?? []
    }

    private func setOpen(_ isOpen: Bool) async {
        isWorking = true
        defer { isWorking = false }
        try? await FirestoreService.shared
            .setOccasionOpen(eventId: event.eventId, isOpen: isOpen)
        await event.start()
    }
}
```

`HostControlsView` reaching `FirestoreService.shared` directly violates the project's DI
rule. Extract both calls into a small `HostControlsViewModel` taking
`service: GameBackend = FirestoreService.shared`, matching every other view model in the
codebase, and have the view hold it as `@StateObject`.

- [ ] **Step 4: Show the host the invite immediately after creating**

In `CreateOccasionView`, after `viewModel.create()` succeeds, present `HostControlsView`
rather than simply dismissing. A host who creates an occasion and is dropped back to a list
with no visible next step will not know that sharing a link is required.

- [ ] **Step 5: Link it from Profile**

In `ProfileView`, replace the old organizer gate with:

```swift
                if event.isHost {
                    NavigationLink {
                        HostControlsView()
                    } label: {
                        Label("Host tools", systemImage: "wrench.and.screwdriver")
                    }
                }
```

- [ ] **Step 6: Run the full suite**

```bash
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | /usr/bin/tail -20
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add BirthdayQuest
git commit -m "Add host tools for inviting and closing an occasion

Separate share links for friends and the guest of honour, a roster, and
the open/closed toggle that serves as the reveal gate. Whether the
celebrant has joined is surfaced prominently, because there is no handover
mode and an occasion whose celebrant never installs the app cannot be
rescued on the day."
```

---

### Task 16: Archive the original occasion

The spec's migration decision is "do not migrate" — but the original occasion's media is the
only irreplaceable content involved, and the new rules will make the old bucket paths
unreachable. This is an operational task, run once, before deploying the new rules.

**Files:**
- Create: `tools/export_media.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing
- Produces: a local archive of the original project's Storage objects.

- [ ] **Step 1: Write the export script**

`tools/export_media.sh`:

```bash
#!/usr/bin/env bash
# Archives every Storage object from a BirthdayQuest project to a local directory.
#
# Run this BEFORE deploying the event-scoped rules. The new storage.rules deny all access
# to the old rewards/** and proofs/** prefixes, so anything not copied out becomes
# unreachable through the app — recoverable only via the GCS console.
set -euo pipefail

BUCKET="${1:-}"
DEST="${2:-./bq-media-archive}"

if [[ -z "$BUCKET" ]]; then
  echo "usage: $0 <bucket-name> [destination-dir]" >&2
  echo "  bucket-name is the STORAGE_BUCKET value from GoogleService-Info.plist" >&2
  exit 1
fi

mkdir -p "$DEST"
echo "Archiving gs://$BUCKET -> $DEST"
gcloud storage cp -r "gs://$BUCKET/rewards" "$DEST/" 2>/dev/null || echo "  no rewards/ prefix"
gcloud storage cp -r "gs://$BUCKET/proofs"  "$DEST/" 2>/dev/null || echo "  no proofs/ prefix"

echo "Done. Verify before deploying new rules:"
/usr/bin/find "$DEST" -type f | /usr/bin/wc -l | /usr/bin/xargs echo "  files archived:"
```

```bash
chmod +x tools/export_media.sh
```

- [ ] **Step 2: Run it against the original project**

```bash
./tools/export_media.sh <your-storage-bucket> ~/Documents/birthdayquest-archive
```

Verify the file count matches what the Firebase console reports under Storage. Do not
proceed to deploying rules until it does.

- [ ] **Step 3: Update the README**

The README's setup instructions are stale in two ways the audit confirmed: they describe a
`DataSeeder` that no longer exists, and they claim a missing `GoogleService-Info.plist`
"crashes at launch with a message pointing you here" when it actually dies on a raw Firebase
assertion. Rewrite the setup section to describe creating an occasion in-app, and state
plainly that Cloud Storage for Firebase requires the Blaze plan for projects created after
2024-10-30.

- [ ] **Step 4: Commit**

```bash
git add tools/export_media.sh README.md
git commit -m "Add media archive script and correct stale setup docs

The new Storage rules make the old rewards/** and proofs/** prefixes
unreachable, so media must be copied out first. Also removes README
references to the deleted DataSeeder and the friendly missing-plist
message that never existed."
```

---

## What this plan does not cover

Deliberately deferred, each depending on this plan landing first:

- **`MediaStore` and media transit** — the courier-and-archive design. Contributors uploading
  video and audio, the celebrant's device persisting to Documents, `fetchedBy` tracking,
  client-side purge, GCS lifecycle backstop, expiry notifications, and switching the four
  content renderers to local file URLs. Also the two latent `RewardContentSheet` defects
  (a text reward with no content rendering its placeholder as the real gift; a
  single-element `contentUrls` array falling through to the wrong field). **Plan 2.**
- **Host authoring** — the 39-item gap list. Creating and editing challenges and rewards,
  setting costs, editing participants. **Subsystem #2.**
- **Occasion-type templates** — default challenge and reward sets for all five types.
  **Subsystem #4.**
- **Store compliance** — `PrivacyInfo.xcprivacy`, real bundle ID and team, moderation with
  report and block, the rename away from "BirthdayQuest", icon and listing. **Subsystem #4.**
- **Accessibility** — the audit found zero `accessibilityLabel`, no Dynamic Type, no
  reduce-motion handling, against roughly ten `repeatForever` animations. Not in scope here,
  but it is a store risk and should not stay unowned.
