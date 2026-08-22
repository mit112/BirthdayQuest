# Content Authoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an occasion fillable in-app — the host authors challenges, contributors author a text gift each, the host prices and orders the gifts — on rules that actually enforce who may change what.

**Architecture:** Firestore rules gain a field-scoped `update` split (gameplay fields stay member-writable, content fields go to host-or-author, `pointCost`/`sortOrder` go to host-only). `GameBackend` grows five methods, each batching the `state/main` counter increment with the content write so no caller can forget it. Three new screens follow the existing `ObservableObject` + `ContentState` + scoped-`ListenerKey` idiom: challenge authoring and gift curation hang off `AdminControlsView` via `NavigationLink`, gift authoring is a fourth contributor tab.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26.0), Firebase Firestore, Swift Testing (`@Suite`/`@Test`/`#expect`), Vitest + `@firebase/rules-unit-testing` for the emulator suite, SwiftLint.

**Spec:** `docs/superpowers/specs/2026-08-22-content-authoring-design.md`

## Global Constraints

- **No Cloud Functions.** Rules are the entire enforcement layer. Every rules change needs a matching case in `firebase-tests/firestore.rules.test.js`.
- **Never run a bare `xcodebuild test`.** Always `cd BirthdayQuest && xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BirthdayQuestTests test`. A bare `test` runs `BirthdayQuestUITests`, which boots a simulator, thrashes memory and hangs in teardown (R48).
- **Run the Swift suite backgrounded, not merely redirected.** A cold run exceeded a 10-minute tool ceiling at 576s. Write `exit=$?` into the log and grep for `** TEST SUCCEEDED **`; do not read the verdict from a task status.
- **One build at a time.** Concurrent runs fight over DerivedData and look exactly like the teardown hang. Never `pkill -f xcodebuild` — match `xcodebuild -scheme BirthdayQuest`, because a bare match also kills Mit's XcodeBuildMCP server.
- **`swiftlint` runs from the repo root**, never the nested source dir (it misses `.swiftlint.yml` there and reports ~678 phantom violations). CI runs `--strict`.
- **Every typography token is a semantic text style.** Never `Font.system(size:)`. For a glyph, use `@ScaledMetric`, which scales a dimension (R69).
- **Perpetual animation is gated in exactly one place:** `MotionLevel`, read via `@Environment(\.bqMotionLevel)`, asked via `allowsPerpetual`. Never read `accessibilityReduceMotion` directly. For an imperative `withAnimation`, *guard* it — passing a nil animation still applies the mutation and freezes the view in its animated end pose (R71).
- **Colour: `textTertiary` is not a text colour** (1.88:1). `gold` and `success` are dark-surface colours; `goldText` (#9C6407, 4.65:1) is the gold-on-light text colour (R72, R73). Reference colours by semantic name, never raw hex.
- **`updateData`, never `setData`, on an existing document.** `hostUid` is immutable, so a full replace that omits it is denied (R42).
- **Every Firestore path goes through `FirestoreService.eventRef`,** which validates the id. A malformed path raises an ObjC `NSException` Swift `do/catch` cannot intercept — the process aborts. Never try to catch it (R63).
- **Never hand-write `init(from:)` on a model carrying `@DocumentID`.** It suppresses the memberwise init and silently nulls every loaded id. Model tests decode through Firestore's decoder, never `JSONDecoder` (R7, R49, R51).
- **View models are `@MainActor final class`, `ObservableObject`.** Use the existing pattern, not `@Observable` — see the spec's "Two conflicts with the knowledge base".
- **Views never touch the backend.** Inject `service: GameBackend = FirestoreService.shared` into the view model (R20).
- **Any new listener gets its own scoped `ListenerKey`** and must handle the `.failure` branch explicitly — never `guard case .success … else { return }` (R52, R56).
- **Commit granularity is by whole file.** `git add -p` is unavailable (no interactive flags).
- **No AI attribution in commits** — no `Co-Authored-By`, no "Generated with".

---

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `BirthdayQuest/BirthdayQuest/Models/ChallengeSymbolCatalog.swift` | The curated SF Symbol set a host may pick from, plus a validated fallback. Mirrors `AvatarCatalog`. |
| `BirthdayQuest/BirthdayQuest/ViewModels/ChallengeAuthoringViewModel.swift` | Host's challenge list + create/edit/delete. Owns its own challenges listener. |
| `BirthdayQuest/BirthdayQuest/ViewModels/GiftAuthoringViewModel.swift` | One contributor's own gift: load-existing, save, update. |
| `BirthdayQuest/BirthdayQuest/ViewModels/GiftCurationViewModel.swift` | Host's view of all gifts: point cost, sort order, delete. |
| `BirthdayQuest/BirthdayQuest/Views/Authoring/ChallengeAuthoringView.swift` | The host's challenge list screen. |
| `BirthdayQuest/BirthdayQuest/Views/Authoring/ChallengeEditorView.swift` | The create/edit form for one challenge. |
| `BirthdayQuest/BirthdayQuest/Views/Authoring/GiftCurationView.swift` | The host's gift list with price and reorder. |
| `BirthdayQuest/BirthdayQuest/Views/Contributor/GiftAuthoringView.swift` | The contributor's gift-letter editor. |
| `BirthdayQuest/BirthdayQuest/Views/Components/SymbolPickerView.swift` | Reusable grid picker over `ChallengeSymbolCatalog`. |
| `BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift` | Tests for the three new view models and the symbol catalog. |

**Modified:**

| File | Change |
|---|---|
| `firestore.rules` | Field-scoped `update` split and validated `create` on `challenges` and `rewards`. |
| `firebase-tests/firestore.rules.test.js` | New `describe` block for the split; one existing test corrected. |
| `BirthdayQuest/BirthdayQuest/Services/GameBackend.swift` | Rename two methods, add five. |
| `BirthdayQuest/BirthdayQuest/Services/FirestoreService.swift` | Implement the seven; batch counter increments. |
| `BirthdayQuest/BirthdayQuestTests/MockGameBackend.swift` | Mirror all seven. |
| `BirthdayQuest/BirthdayQuest/ViewModels/SecretChallengeViewModel.swift` | Call-site rename only. |
| `BirthdayQuest/BirthdayQuest/Services/EventSession.swift` | Add `ContributorTab.gift`. |
| `BirthdayQuest/BirthdayQuest/AppConstants.swift` | Add three `ListenerKey` helpers. |
| `BirthdayQuest/BirthdayQuest/Views/Contributor/ContributorTabView.swift` | Add the Gift tab. |
| `BirthdayQuest/BirthdayQuest/Views/Profile/AdminControlsView.swift` | Add an authoring card with two `NavigationLink`s. |
| `CLAUDE.md`, `README.md` | Reconcile. |

**Why authoring lives in its own `Views/Authoring/` folder:** the source dir uses folder-synced groups, so a new folder needs no Xcode configuration. `AdminControlsView.swift` is already 769 lines and the largest view in the app; R60 forbids a *second host panel*, not a second file.

---

## Task 1: Pin the wire shape of an encoded Challenge

The spec flags one thing that must be measured, not reasoned about: whether Firestore's encoder **omits** nil optionals or writes them as null. `Challenge` has six nil optionals at create time. If they arrive as explicit nulls, a `hasOnly` create rule that does not list them rejects every create — and the failure would surface only against a live project, where no test runs.

**Files:**
- Test: `firebase-tests/firestore.rules.test.js` (temporary probe, deleted in Step 4)
- Create: `.superpowers/sdd/2026-08-22-content-authoring/wire-shape.md` (git-ignored record)

**Interfaces:**
- Produces: the definitive list of keys present in a newly created challenge document, consumed by Task 2's `create` rule.

- [ ] **Step 1: Write a probe that dumps the real encoded document**

This runs through the app's own encoder, not a hand-written literal, which is the whole point. Add to `BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift` (create the file):

```swift
import Testing
import FirebaseFirestore
@testable import BirthdayQuest

@Suite("Challenge wire shape")
struct ChallengeWireShapeTests {

    /// Pins which keys Firestore's encoder actually writes for a Challenge with six nil
    /// optionals. The create rule in firestore.rules lists fields explicitly, so a change
    /// here silently breaks every create against a live project — where no test runs.
    @Test func encodesOnlyNonNilFields() throws {
        let challenge = Challenge(
            title: "Sing", description: "In public", illustrationAsset: "music.mic",
            pointValue: 50, difficulty: .medium, category: .social,
            isSecret: false, createdByUserId: "uid_host",
            isDelivered: true, isCompleted: false,
            completedAt: nil, proofUrl: nil, proofType: nil, proofText: nil,
            createdAt: Date()
        )

        let encoded = try Firestore.Encoder().encode(challenge)
        let keys = Set(encoded.keys)

        // The six nil optionals must be ABSENT, not present-as-null.
        #expect(!keys.contains("completedAt"))
        #expect(!keys.contains("proofUrl"))
        #expect(!keys.contains("proofType"))
        #expect(!keys.contains("proofText"))
        #expect(!keys.contains("optionBTitle"))
        #expect(!keys.contains("optionBDescription"))

        // @DocumentID is never encoded into the body.
        #expect(!keys.contains("id"))

        // And these eleven must be present.
        #expect(keys == [
            "title", "description", "illustrationAsset", "pointValue", "difficulty",
            "category", "isSecret", "createdByUserId", "isDelivered", "isCompleted",
            "createdAt",
        ])
    }
}
```

- [ ] **Step 2: Run it**

```bash
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/ChallengeWireShapeTests test 2>&1 | /usr/bin/tail -40
```

Expected: PASS. **If it fails**, the assertion message tells you the real key set. That is the answer — do not "fix" the test to match a guess. Record the actual set and carry it into Task 2's `create` rule instead.

- [ ] **Step 3: Record the result**

```bash
mkdir -p .superpowers/sdd/2026-08-22-content-authoring
cat > .superpowers/sdd/2026-08-22-content-authoring/wire-shape.md <<'EOF'
# Encoded Challenge wire shape (measured 2026-08-22)

Firestore's encoder OMITS nil optionals (it routes through `encodeIfPresent`, whose stdlib
default is a no-op on nil; `@ExplicitNull` exists precisely to opt into the other behaviour,
and no Challenge property uses it).

Keys written on create: title, description, illustrationAsset, pointValue, difficulty,
category, isSecret, createdByUserId, isDelivered, isCompleted, createdAt.

Absent: completedAt, proofUrl, proofType, proofText, optionBTitle, optionBDescription, id.

This is what the `create` rule's field list in firestore.rules is built against.
EOF
```

If Step 2 disagreed with this text, write what actually happened instead. The record is the measurement, not the expectation.

- [ ] **Step 4: Commit**

The test stays — it is now the regression guard for the create rule.

```bash
git add BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift
git commit -m "Pin the encoded wire shape of a challenge document

The create rule about to be written lists fields explicitly, so whether the
encoder omits nil optionals or writes them as null decides whether every
create is rejected. Measured rather than assumed, because the failure would
only appear against a live project."
```

---
## Task 2: Field-scoped rules for `challenges`

`challenges` today is `read/create/update: if isMember(eventId)` with **zero** field validation — no `hasOnly`, no types, no length caps, no immutable fields. Any member can rewrite any challenge's `pointValue` or title. This task splits `update` into a gameplay half (member-writable, unchanged behaviour) and a content half (host-or-author), and validates `create`.

**Files:**
- Modify: `firestore.rules:29-52` (add two helpers), `firestore.rules:177-182` (the challenges block)
- Test: `firebase-tests/firestore.rules.test.js`

**Interfaces:**
- Produces: `affects(allowed)` and `isAuthorOf(field)` rules helpers, consumed by Task 3.
- Produces: the guarantee that `createdByUserId` equals the creator's uid on every new challenge — which `ChallengeAuthoringViewModel` (Task 9) and `GiftAuthoringViewModel` (Task 11) must satisfy or every write is denied.

**The mechanism, so you don't add a redundant clause:** immutability is achieved by *omission*. `affects()` uses `hasOnly`, so any key absent from **both** allow-lists cannot be written at all. `isSecret`, `createdByUserId` and `createdAt` appear in neither list, which is exactly what makes them immutable. Do not add a separate immutability clause — it would be dead.

- [ ] **Step 1: Add the two rules helpers**

In `firestore.rules`, immediately after the existing `codesData(eventId)` function (currently ending at line 52), add:

```
    // Content vs gameplay, used by both challenges and rewards below.
    //
    // `hasOnly` is what makes a field immutable: any key absent from every allow-list
    // cannot be written at all, so isSecret / createdByUserId / fromUserId / createdAt are
    // pinned without a clause of their own.
    function affects(allowed) {
      return request.resource.data.diff(resource.data).affectedKeys().hasOnly(allowed);
    }

    // Author identity is the hinge the whole content/gameplay split turns on. `.get(k, '')`
    // rather than direct access, because documents written before this rule existed carry
    // no author field and direct access on a missing key errors out rather than returning
    // false — which would deny the host too.
    function isAuthorOf(field) {
      return resource.data.get(field, '') == request.auth.uid;
    }
```

- [ ] **Step 2: Write the failing tests**

Append a new `describe` block to `firebase-tests/firestore.rules.test.js`, after the existing `content collections are reachable` block:

```javascript
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
});
```

- [ ] **Step 3: Correct the one existing test whose premise the new rule changes**

`lets a member create a secret challenge` creates a challenge with **no `createdByUserId`**, which the new create rule rejects. The app has always written that field; the test never did. Change it in place — this is a correction, not a regression:

```javascript
  it('lets a member create a secret challenge', async () => {
    await joinAsContributor(GUEST);
    const db = testEnv.authenticatedContext(GUEST).firestore();
    await assertSucceeds(setDoc(doc(db, `events/${EVENT}/challenges/c2`), {
      title: 'Secret dare', description: 'x', pointValue: 50, isSecret: true,
      isCompleted: false, createdByUserId: GUEST,
    }));
  });
```

- [ ] **Step 4: Run the suite and watch it fail**

```bash
cd firebase-tests && npm test 2>&1 | /usr/bin/tail -40
```

Expected: the new `describe` block fails throughout — the current rule allows every member every write, so the six `assertFails` cases all succeed when they should not.

- [ ] **Step 5: Replace the challenges block**

Replace `firestore.rules:177-182` in its entirety:

```
    // Split into a gameplay half and a content half. The gameplay list is verbatim the
    // field set `completeChallengeAtomically` writes, and stays open to any member: the two
    // tests that exercise it do so as an ordinary contributor, and narrowing it to the
    // celebrant would break the dare flow. The content half is the host or the challenge's
    // own author, which is what lets a contributor edit their dare and nobody else's.
    match /challenges/{challengeId} {
      allow read: if isMember(eventId);

      // A member may author a secret dare, in their own name only. The host may author
      // either kind. Both stamp themselves as the author, because the update rule above
      // trusts that field.
      allow create: if isMember(eventId)
                    && request.resource.data.createdByUserId == request.auth.uid
                    && (isHost(eventId) || request.resource.data.isSecret == true)
                    && request.resource.data.title is string
                    && request.resource.data.title.size() > 0
                    && request.resource.data.title.size() <= 120
                    && request.resource.data.description is string
                    && request.resource.data.description.size() <= 2000
                    && request.resource.data.pointValue is int
                    && request.resource.data.pointValue >= 0
                    && request.resource.data.pointValue <= 1000;

      allow update: if isMember(eventId) && (
                      affects(['isCompleted', 'completedAt', 'proofUrl', 'proofType', 'proofText'])
                      || (
                        (isHost(eventId) || isAuthorOf('createdByUserId'))
                        && affects([
                          'title', 'description', 'pointValue', 'difficulty', 'category',
                          'illustrationAsset', 'isDelivered',
                          'optionBTitle', 'optionBDescription'
                        ])
                      )
                    );

      allow delete: if isHost(eventId);
    }
```

- [ ] **Step 6: Run the suite and watch it pass**

```bash
cd firebase-tests && npm test 2>&1 | /usr/bin/tail -40
```

Expected: all green. If `lets a member complete a challenge` or `lets a member unlock a reward` fails, the gameplay allow-list is wrong — those two are performed by a plain contributor and are the contract you must not break.

- [ ] **Step 7: Mutation-test the split (R74)**

A green suite proves nothing until you have seen it go red for the right reason. Do all three, one at a time, reverting between:

1. Delete `&& (isHost(eventId) || request.resource.data.isSecret == true)` from `create`. Run. Expected: `denies a member creating a NON-secret challenge` fails. Revert.
2. Add `'createdByUserId'` to the content allow-list. Run. Expected: `denies reassigning a challenge's author` fails. Revert.
3. Change `isAuthorOf('createdByUserId')` to `true`. Run. Expected: `denies a member editing a challenge they did not author` fails. Revert.

If any mutation leaves the suite green, that clause has no test and you must write one before continuing. Record the outcome in the commit message.

- [ ] **Step 8: Commit**

```bash
git add firestore.rules firebase-tests/firestore.rules.test.js
git commit -m "Stop any member rewriting any challenge

challenges was one of two collections in the rules file with no field
validation at all, so a contributor could rewrite the host's point values or
another contributor's dare. Splits update into a gameplay half (unchanged,
still any member - the celebrant completing a dare is a plain member write)
and a content half gated on host-or-author, and validates create.

Immutability falls out of hasOnly: isSecret, createdByUserId and createdAt
are in neither allow-list, so nothing can write them after creation. That
matters because the author field is what the content branch trusts.

Corrects 'lets a member create a secret challenge', which never wrote the
createdByUserId the app has always written.

Mutation-tested: removing the secret-only clause, the author immutability or
the author check each fails a named test."
```

---

## Task 3: Field-scoped rules for `rewards`

Same split, plus a third tier: `pointCost` and `sortOrder` are the economy, and belong to the host alone. This is also where contributor-authored gifts become possible at all — today reward `create` is host-only, which contradicts both the model (`fromUserId`, `fromName`, "Sam's gift") and `storage.rules:46`'s own comment that reward media is "written by contributors".

**Files:**
- Modify: `firestore.rules:184-189`
- Test: `firebase-tests/firestore.rules.test.js`

**Interfaces:**
- Consumes: `affects(allowed)` and `isAuthorOf(field)` from Task 2.
- Produces: the guarantee that `fromUserId` equals the creator's uid on every new reward, which `GiftAuthoringViewModel` (Task 11) must satisfy.

- [ ] **Step 1: Write the failing tests**

Append to the `content is author-scoped, gameplay is member-scoped` describe block from Task 2:

```javascript
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
```

- [ ] **Step 2: Rework the existing test whose premise this reverses**

`denies a non-host creating a reward` asserts that a contributor cannot create a gift. That is precisely what this task makes legal, so the test is now **wrong**, not failing. Its real intent — you cannot create a gift attributed to someone else — is already covered by `denies a member creating a gift in someone else's name` above. Delete the old test:

```bash
# Remove the `denies a non-host creating a reward` it(...) block at
# firebase-tests/firestore.rules.test.js:192-200
```

Do not "fix" it by adding a `fromUserId` mismatch — that duplicates a test you just wrote. Deleting a test whose premise a deliberate design change reversed is correct; note it in the commit message so it reads as a decision rather than a disappearance.

- [ ] **Step 3: Run and watch it fail**

```bash
cd firebase-tests && npm test 2>&1 | /usr/bin/tail -40
```

Expected: `lets a member create the gift that is from them` fails (create is still host-only), and the price/author `assertFails` cases pass spuriously because *everything* currently fails for non-hosts.

- [ ] **Step 4: Replace the rewards block**

Replace `firestore.rules:184-189` in its entirety:

```
    // Three tiers, not two. Gameplay stays any-member (R39's parked trust model, inherited
    // not relitigated). Content belongs to whoever wrote the gift. But pointCost and
    // sortOrder are the economy, and the host curates that alone — a contributor pricing
    // their own gift can trivially make the whole board free.
    //
    // `fetchedBy` is in the gameplay list although nothing writes it yet, so the media
    // pipeline does not need a second rules change to record a download.
    match /rewards/{rewardId} {
      allow read: if isMember(eventId);

      // The host may create a gift for anyone; a member may create only the gift that is
      // from them. This is what the model always said - fromUserId, fromName, "Sam's gift" -
      // and what storage.rules already assumed when it let contributors upload gift media.
      allow create: if isMember(eventId)
                    && (isHost(eventId)
                        || request.resource.data.get('fromUserId', '') == request.auth.uid)
                    && request.resource.data.title is string
                    && request.resource.data.title.size() > 0
                    && request.resource.data.title.size() <= 120
                    && request.resource.data.fromName is string
                    && request.resource.data.fromName.size() > 0
                    && request.resource.data.pointCost is int
                    && request.resource.data.pointCost >= 0
                    && request.resource.data.pointCost <= 10000
                    && request.resource.data.sortOrder is int
                    && request.resource.data.contentType in ['video', 'audio', 'text', 'image'];

      allow update: if isMember(eventId) && (
                      affects(['isUnlocked', 'unlockedAt', 'fetchedBy'])
                      || (isHost(eventId) && affects(['pointCost', 'sortOrder']))
                      || (
                        (isHost(eventId) || isAuthorOf('fromUserId'))
                        && affects([
                          'title', 'teaser', 'contentText', 'contentType',
                          'contentUrl', 'contentUrls', 'badgeIllustration'
                        ])
                      )
                    );

      allow delete: if isHost(eventId);
    }
```

Note `.get('fromUserId', '')` on create: the existing `lets the host create a reward` test writes no `fromUserId`, and direct access would error rather than fall through to the host branch.

- [ ] **Step 5: Run and watch it pass**

```bash
cd firebase-tests && npm test 2>&1 | /usr/bin/tail -40
```

- [ ] **Step 6: Mutation-test (R74)**

One at a time, reverting between:

1. Move `'pointCost'` from the host-only tier into the content tier. Run. Expected: `denies the author repricing their own gift` fails. Revert.
2. Add `'fromUserId'` to the content allow-list. Run. Expected: `denies reassigning a gift's author` fails. Revert.
3. Delete `&& request.resource.data.contentType in [...]`. Run. Expected: `denies a gift with an unknown content type` fails. Revert.

- [ ] **Step 7: Commit**

```bash
git add firestore.rules firebase-tests/firestore.rules.test.js
git commit -m "Let contributors write their own gift, and only the host price it

Reward create was host-only, which contradicted the model (fromUserId,
fromName, 'Sam's gift') and storage.rules' own comment that reward media is
written by contributors: a contributor could upload the media and not create
the document pointing at it.

Three tiers now. Gameplay (isUnlocked, unlockedAt, fetchedBy) stays open to
any member, unchanged. Content belongs to the gift's author. pointCost and
sortOrder are host-only, because a contributor who can price their own gift
can make the whole board free.

Deletes 'denies a non-host creating a reward': that is the behaviour this
change deliberately reverses. Its real intent - you cannot attribute a gift
to someone else - is covered by a new test.

Mutation-tested: moving pointCost out of the host tier, making the author
field writable, or dropping the content-type check each fails a named test."
```

---
## Task 4: Rename the two challenge methods

`createSecretChallenge` / `updateSecretChallenge` never enforced secrecy — the first is one line of `addDocument(from: challenge)`, and `isSecret: true` comes from the caller's struct. Host authoring needs exactly these two operations for non-secret challenges. Adding a second pair beside them would be two methods doing one job, so they are renamed instead. Pure refactor: no behaviour changes, and the suite must be green at both ends.

**Files:**
- Modify: `BirthdayQuest/BirthdayQuest/Services/GameBackend.swift:134-139` and the doc comment at `:12-15`
- Modify: `BirthdayQuest/BirthdayQuest/Services/FirestoreService.swift:598-609`
- Modify: `BirthdayQuest/BirthdayQuestTests/MockGameBackend.swift` (the two implementations)
- Modify: `BirthdayQuest/BirthdayQuest/ViewModels/SecretChallengeViewModel.swift:127, 150, 179`

**Interfaces:**
- Produces: `createChallenge(eventId:challenge:) async throws -> String` and `updateChallenge(eventId:challengeId:data:) async throws`, consumed by Tasks 5, 8 and 9.

- [ ] **Step 1: Rename in the protocol**

In `GameBackend.swift`, replace the two declarations under `// MARK: Challenges`:

```swift
    /// Creates a challenge. The caller supplies the whole `Challenge`, including `isSecret`
    /// and `createdByUserId` — this method has never enforced either, and the rules do.
    ///
    /// `createdByUserId` must be the calling uid or the write is denied: it is the field the
    /// content-edit rule reads to decide who may edit this challenge later.
    func createChallenge(eventId: String, challenge: Challenge) async throws -> String

    /// Partial edit. `data` must contain only content fields (`title`, `description`,
    /// `pointValue`, `difficulty`, `category`, `illustrationAsset`, `isDelivered`,
    /// `optionBTitle`, `optionBDescription`) or only gameplay fields — the rules reject a
    /// mixture, because a gameplay write that also carries a point value is how a member
    /// would smuggle an edit past the author check.
    func updateChallenge(
        eventId: String,
        challengeId: String,
        data: [String: Any]
    ) async throws
```

Also correct the file's own doc comment at `GameBackend.swift:12-15`, which names the old method: change `updateSecretChallenge(eventId:challengeId:data:)` to `updateChallenge(eventId:challengeId:data:)`.

- [ ] **Step 2: Rename in `FirestoreService`**

Replace `FirestoreService.swift:598-609` (keep the bodies byte-for-byte; only the two names change — Task 5 changes the bodies):

```swift
    func createChallenge(eventId: String, challenge: Challenge) async throws -> String {
        let ref = try challengesRef(eventId).addDocument(from: challenge)
        return ref.documentID
    }

    func updateChallenge(
        eventId: String,
        challengeId: String,
        data: [String: Any]
    ) async throws {
        try await challengesRef(eventId).document(challengeId).updateData(data)
    }
```

- [ ] **Step 3: Rename in the mock**

In `MockGameBackend.swift`, replace the two implementations. Note the recorded call *names* change too, because three existing tests assert on them via `called(_:)`:

```swift
    func createChallenge(eventId: String, challenge: Challenge) async throws -> String {
        record("createChallenge", eventId: eventId)
        createdChallenges.append(challenge)
        try throwIfNeeded()
        return stubbedSecretChallengeId
    }

    /// Every challenge the caller asked to create, so a test can assert what was stamped on
    /// it — `createdByUserId` in particular, which the rules require to be the caller's uid.
    private(set) var createdChallenges: [Challenge] = []

    func updateChallenge(
        eventId: String,
        challengeId: String,
        data: [String: Any]
    ) async throws {
        record("updateChallenge", eventId: eventId)
        updatedChallenges.append((challengeId, data))
        try throwIfNeeded()
    }

    /// Recorded so a test can prove an edit sent only content fields — the rules reject a
    /// write that mixes content and gameplay keys.
    private(set) var updatedChallenges: [(id: String, data: [String: Any])] = []
```

- [ ] **Step 4: Update the three call sites in `SecretChallengeViewModel`**

`SecretChallengeViewModel.swift:127` (`service.updateSecretChallenge` in the edit branch of `save()`), `:150` (`service.createSecretChallenge` in the create branch), and `:179` (`service.updateSecretChallenge` in `deliver()`). Change the method name only — every argument label is unchanged.

- [ ] **Step 5: Fix any test that asserted on the old call names**

```bash
/usr/bin/grep -rn 'createSecretChallenge\|updateSecretChallenge' BirthdayQuest/
```

Expected after Steps 1-4: only hits inside `BirthdayQuestTests/`. Change each `called("createSecretChallenge")` to `called("createChallenge")` and likewise for update. **Leave `stubbedSecretChallengeId` alone** — it is a stub value name, not a call name, and renaming it is churn with no reader benefit.

- [ ] **Step 6: Build and run the suite**

```bash
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests test > /tmp/t4.log 2>&1; echo "exit=$?" >> /tmp/t4.log
/usr/bin/grep -c 'TEST SUCCEEDED' /tmp/t4.log
```

Expected: `1`, and the same test count as before this task. A rename that changes a count means it changed behaviour.

- [ ] **Step 7: Commit**

```bash
git add BirthdayQuest/BirthdayQuest/Services BirthdayQuest/BirthdayQuest/ViewModels/SecretChallengeViewModel.swift BirthdayQuest/BirthdayQuestTests
git commit -m "Drop 'Secret' from the two challenge write methods

Neither ever enforced secrecy - createSecretChallenge is one line of
addDocument(from:), and isSecret comes from the caller's struct. Host
authoring needs the same two operations for non-secret challenges, and a
second pair beside them would be two methods doing one job.

Pure rename: bodies unchanged, same test count either side."
```

---

## Task 5: Make the challenge counter move

`createOccasion` writes `totalChallenges: 0` and nothing ever increments it. `GameState.challengeProgress` divides by it, and `checkFinalBadge` refuses to fire while `totalRewards == 0` — so an occasion filled in by hand, exactly as `README.md` instructs, can never be finished. This task makes the counter move with the content, in the same batch, inside `FirestoreService`, so no caller can forget it.

**Files:**
- Modify: `BirthdayQuest/BirthdayQuest/Services/GameBackend.swift` (add `deleteChallenge`)
- Modify: `BirthdayQuest/BirthdayQuest/Services/FirestoreService.swift` (batch both writes)
- Modify: `BirthdayQuest/BirthdayQuestTests/MockGameBackend.swift`
- Test: `BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift`

**Interfaces:**
- Consumes: `createChallenge` / `updateChallenge` from Task 4.
- Produces: `deleteChallenge(eventId:challengeId:) async throws`, consumed by Task 8.

**Why increment and not recompute:** contributors add gifts concurrently, so a recompute-from-count races. `FieldValue.increment` is the only concurrency-correct option. The trade is that a write lost while offline leaves the counter permanently off by one rather than self-healing; that is recorded as an accepted risk in the spec, and it is visible in the host panel's game-state card.

**What these tests can and cannot prove.** They assert the view model asked the backend to create
or delete. They **cannot** assert the counter moved: the increment is batched inside
`FirestoreService`, and `MockGameBackend` replaces exactly that type. Do not "fix" this by teaching
the mock to keep a running count — that tests the mock. It is the same structural gap that leaves
the three atomic transactions uncovered (R30), and closing it needs a Swift-to-emulator harness that
does not exist. Say so rather than implying coverage.

**Note on id validation:** `eventRef` validates the event id because it arrives from a deep link and from the client-writable `inviteCodes.eventId`. Challenge and reward ids do **not** get the same treatment, and should not: they only ever come from `@DocumentID` on a document Firestore itself returned. Follow the existing `updateChallenge` precedent — `challengesRef(eventId).document(challengeId)` with no extra guard.

- [ ] **Step 1: Write the failing tests**

Append to `BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift`:

```swift
@MainActor
@Suite("Authoring keeps the occasion's counters honest")
struct AuthoringCounterTests {

    @Test("creating a challenge is recorded with its author stamp")
    func createStampsAuthor() async throws {
        let mock = MockGameBackend()
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.beginCreating()
        vm.draft.title = "Sing in public"
        vm.draft.description = "Somewhere busy"
        vm.draft.pointValue = 50

        await vm.save(authorUid: "uid_host")

        #expect(mock.called("createChallenge"))
        #expect(mock.createdChallenges.first?.createdByUserId == "uid_host")
        #expect(mock.createdChallenges.first?.isSecret == false)
    }

    @Test("deleting a challenge asks the backend to delete it")
    func deleteCallsBackend() async {
        let mock = MockGameBackend()
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)

        await vm.delete(.fixture(id: "c9"))

        #expect(mock.deletedChallengeIds == ["c9"])
    }

    @Test("an edit sends only content fields, never a gameplay field")
    func editSendsOnlyContent() async {
        let mock = MockGameBackend()
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.beginEditing(.fixture(id: "c1", title: "Old"))
        vm.draft.title = "New"

        await vm.save(authorUid: "uid_host")

        let sent = Set(mock.updatedChallenges.first?.data.keys ?? [:].keys)
        let gameplay: Set<String> = [
            "isCompleted", "completedAt", "proofUrl", "proofType", "proofText",
        ]
        #expect(sent.isDisjoint(with: gameplay), "the rules reject a mixed write")
        #expect(sent.contains("title"))
    }

    @Test("a failed write is reported, not swallowed")
    func failureIsReported() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.beginCreating()
        vm.draft.title = "X"
        vm.draft.description = "Y"

        await vm.save(authorUid: "uid_host")

        #expect(vm.actionResult?.isError == true)
        #expect(vm.isPerformingAction == false)
    }
}
```

These will not compile yet — `ChallengeAuthoringViewModel` arrives in Task 8. That is deliberate: this task delivers the backend they need, and Task 8 makes them run. If you prefer a compiling tree at every commit, move this Step to Task 8 and verify this task with Steps 2-4 only.

- [ ] **Step 2: Add `deleteChallenge` to the protocol**

In `GameBackend.swift`, after `updateChallenge`:

```swift
    /// Deletes a challenge and decrements the occasion's challenge counter in one batch.
    /// Host-only at the rules layer.
    func deleteChallenge(eventId: String, challengeId: String) async throws
```

- [ ] **Step 3: Batch the counter into create and delete**

Replace `createChallenge` in `FirestoreService.swift` and add `deleteChallenge` beside it:

```swift
    /// Creates a challenge and moves the occasion's counter in the same batch.
    ///
    /// The counter is not decoration. `GameState.challengeProgress` divides by
    /// `totalChallenges`, and `checkFinalBadge` refuses to fire while `totalRewards == 0` —
    /// both were seeded to 0 and incremented nowhere, so an occasion filled in by hand (which
    /// is what the README told hosts to do) could never be finished. Batching the increment
    /// with the write is what stops that coming back: a caller cannot forget what it is never
    /// asked to remember.
    ///
    /// `increment` rather than a recomputed count because contributors add gifts
    /// concurrently, and a recompute races. Neither rule reads the other document, so the
    /// committed-state trap that forced two-phase occasion creation does not apply here.
    func createChallenge(eventId: String, challenge: Challenge) async throws -> String {
        let ref = try challengesRef(eventId).document()
        let state = try stateRef(eventId)
        let batch = db.batch()
        try batch.setData(from: challenge, forDocument: ref)
        batch.updateData([
            "totalChallenges": FieldValue.increment(Int64(1)),
            "updatedAt": Timestamp(date: Date())
        ], forDocument: state)
        try await batch.commit()
        logger.info("Created challenge \(ref.documentID)")
        return ref.documentID
    }

    func deleteChallenge(eventId: String, challengeId: String) async throws {
        let ref = try challengesRef(eventId).document(challengeId)
        let state = try stateRef(eventId)
        let batch = db.batch()
        batch.deleteDocument(ref)
        batch.updateData([
            "totalChallenges": FieldValue.increment(Int64(-1)),
            "updatedAt": Timestamp(date: Date())
        ], forDocument: state)
        try await batch.commit()
    }
```

`createChallenge` now allocates the id locally with `.document()` instead of `addDocument(from:)`, because a batch needs the reference before the commit. Same result, same id semantics.

- [ ] **Step 4: Mirror in the mock**

```swift
    func deleteChallenge(eventId: String, challengeId: String) async throws {
        record("deleteChallenge", eventId: eventId)
        deletedChallengeIds.append(challengeId)
        try throwIfNeeded()
    }

    private(set) var deletedChallengeIds: [String] = []
```

- [ ] **Step 5: Build**

```bash
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build > /tmp/t5.log 2>&1; echo "exit=$?" >> /tmp/t5.log
/usr/bin/grep -c 'BUILD SUCCEEDED' /tmp/t5.log
```

- [ ] **Step 6: Commit**

```bash
git add BirthdayQuest/BirthdayQuest/Services BirthdayQuest/BirthdayQuestTests/MockGameBackend.swift
git commit -m "Move the challenge counter when a challenge moves

totalChallenges was written as 0 at occasion creation and incremented
nowhere. challengeProgress divides by it and checkFinalBadge refuses to fire
while totalRewards is 0, so an occasion filled in by hand - which is exactly
what the README instructed - could never be finished.

The increment is batched with the content write inside FirestoreService, so a
caller cannot forget it. increment rather than a recomputed count because
gifts arrive concurrently."
```

---

## Task 6: Reward create, update, delete and reorder

Rewards have **no** create/update/delete on `GameBackend` at all — only the two atomic unlock transactions, which flip `isUnlocked` on a document that must already exist. Nothing in the Swift app has ever written `pointCost`, `sortOrder`, `fromUserId` or `fromName`.

**Files:**
- Modify: `BirthdayQuest/BirthdayQuest/Services/GameBackend.swift`
- Modify: `BirthdayQuest/BirthdayQuest/Services/FirestoreService.swift`
- Modify: `BirthdayQuest/BirthdayQuestTests/MockGameBackend.swift`

**Interfaces:**
- Produces, consumed by Tasks 10 and 12:
  - `createReward(eventId:reward:) async throws -> String`
  - `updateReward(eventId:rewardId:fields:) async throws`
  - `deleteReward(eventId:rewardId:) async throws`
  - `setRewardOrder(eventId:orderedRewardIds:) async throws`

- [ ] **Step 1: Add the four declarations**

In `GameBackend.swift`, under `// MARK: Rewards`, after `unlockRewardAtomically`:

```swift
    /// Creates a gift and increments the occasion's gift counter in one batch.
    ///
    /// `reward.fromUserId` must be the calling uid unless the caller is the host: it is the
    /// field the content-edit rule reads to decide who may edit this gift later.
    func createReward(eventId: String, reward: Reward) async throws -> String

    /// Partial edit. `fields` must contain only content keys, only `pointCost`/`sortOrder`,
    /// or only gameplay keys — the rules reject a mixture, and the three tiers have
    /// different audiences.
    func updateReward(eventId: String, rewardId: String, fields: [String: Any]) async throws

    /// Deletes a gift and decrements the counter in one batch. Host-only at the rules layer.
    func deleteReward(eventId: String, rewardId: String) async throws

    /// Rewrites `sortOrder` across the whole list to match the given order, in one batch.
    /// Host-only at the rules layer, because `sortOrder` is host-only.
    func setRewardOrder(eventId: String, orderedRewardIds: [String]) async throws
```

- [ ] **Step 2: Implement in `FirestoreService`**

Add after `unlockRewardAtomically`:

```swift
    func createReward(eventId: String, reward: Reward) async throws -> String {
        let ref = try rewardsRef(eventId).document()
        let state = try stateRef(eventId)
        let batch = db.batch()
        try batch.setData(from: reward, forDocument: ref)
        batch.updateData([
            "totalRewards": FieldValue.increment(Int64(1)),
            "updatedAt": Timestamp(date: Date())
        ], forDocument: state)
        try await batch.commit()
        logger.info("Created reward \(ref.documentID)")
        return ref.documentID
    }

    func updateReward(eventId: String, rewardId: String, fields: [String: Any]) async throws {
        try await rewardsRef(eventId).document(rewardId).updateData(fields)
    }

    func deleteReward(eventId: String, rewardId: String) async throws {
        let ref = try rewardsRef(eventId).document(rewardId)
        let state = try stateRef(eventId)
        let batch = db.batch()
        batch.deleteDocument(ref)
        batch.updateData([
            "totalRewards": FieldValue.increment(Int64(-1)),
            "updatedAt": Timestamp(date: Date())
        ], forDocument: state)
        try await batch.commit()
    }

    /// One batch, one write per gift. A Firestore batch caps at 500 writes; an occasion has
    /// one gift per contributor, so the cap is not reachable in practice and is not guarded
    /// against — a guard here would be error handling for an impossible case.
    func setRewardOrder(eventId: String, orderedRewardIds: [String]) async throws {
        let rewards = try rewardsRef(eventId)
        let batch = db.batch()
        for (index, rewardId) in orderedRewardIds.enumerated() {
            batch.updateData(["sortOrder": index], forDocument: rewards.document(rewardId))
        }
        try await batch.commit()
    }
```

- [ ] **Step 3: Mirror all four in the mock**

```swift
    func createReward(eventId: String, reward: Reward) async throws -> String {
        record("createReward", eventId: eventId)
        createdRewards.append(reward)
        try throwIfNeeded()
        return stubbedCreatedRewardId
    }

    var stubbedCreatedRewardId = "gift-1"
    private(set) var createdRewards: [Reward] = []

    func updateReward(eventId: String, rewardId: String, fields: [String: Any]) async throws {
        record("updateReward", eventId: eventId)
        updatedRewards.append((rewardId, fields))
        try throwIfNeeded()
    }

    private(set) var updatedRewards: [(id: String, fields: [String: Any])] = []

    func deleteReward(eventId: String, rewardId: String) async throws {
        record("deleteReward", eventId: eventId)
        deletedRewardIds.append(rewardId)
        try throwIfNeeded()
    }

    private(set) var deletedRewardIds: [String] = []

    func setRewardOrder(eventId: String, orderedRewardIds: [String]) async throws {
        record("setRewardOrder", eventId: eventId)
        rewardOrders.append(orderedRewardIds)
        try throwIfNeeded()
    }

    /// Every reorder the caller asked for, so a test can assert the resulting sequence
    /// rather than merely that a reorder happened.
    private(set) var rewardOrders: [[String]] = []
```

- [ ] **Step 4: Build and run the suite**

```bash
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests test > /tmp/t6.log 2>&1; echo "exit=$?" >> /tmp/t6.log
/usr/bin/grep -c 'TEST SUCCEEDED' /tmp/t6.log
```

Expected: `1`. The mock must still conform — if it does not, the build error names the missing method, which is this codebase's most repeated defect class (R9, R33, R59).

- [ ] **Step 5: Commit**

```bash
git add BirthdayQuest/BirthdayQuest/Services BirthdayQuest/BirthdayQuestTests/MockGameBackend.swift
git commit -m "Give rewards a write surface

GameBackend had no create, update or delete for rewards at all - only the two
atomic unlock transactions, which flip isUnlocked on a document that has to
already exist. Nothing in the Swift app had ever written pointCost, sortOrder,
fromUserId or fromName; they only existed in seed data.

Create and delete batch the totalRewards counter, matching challenges.
setRewardOrder rewrites the whole list in one batch rather than per-row, so a
reorder cannot land half-applied."
```

---
## Task 7: The symbol catalog and its picker

`illustrationAsset` is rendered as an SF Symbol name with a `bolt.fill` fallback (`TimelineNodeView.swift:256`). The literal the dare flow writes — `"secret_mission"` — is not a symbol, so **every secret dare already renders the fallback**. A free-text field in an authoring form lets a host reproduce that bug deliberately, so the field becomes a picker over a validated set.

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/Models/ChallengeSymbolCatalog.swift`
- Create: `BirthdayQuest/BirthdayQuest/Views/Components/SymbolPickerView.swift`
- Test: `BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift`

**Interfaces:**
- Produces: `ChallengeSymbolCatalog.all: [String]`, `.fallback: String`, `.resolved(_:) -> String`; and `SymbolPickerView(selection: Binding<String>)`. Consumed by Tasks 8 and 9.

- [ ] **Step 1: Write the failing test**

Append to `AuthoringTests.swift`. The second assertion is the one that earns its keep — a typo'd symbol name is invisible at runtime because it silently falls back, which is exactly how `"secret_mission"` survived:

```swift
@Suite("Challenge symbols")
struct ChallengeSymbolCatalogTests {

    @Test("every catalogued symbol is a real SF Symbol")
    func allSymbolsResolve() {
        for name in ChallengeSymbolCatalog.all {
            #expect(UIImage(systemName: name) != nil, "\(name) is not an SF Symbol")
        }
    }

    @Test("the fallback is itself catalogued and real")
    func fallbackIsValid() {
        #expect(ChallengeSymbolCatalog.all.contains(ChallengeSymbolCatalog.fallback))
        #expect(UIImage(systemName: ChallengeSymbolCatalog.fallback) != nil)
    }

    @Test("an uncatalogued name resolves to the fallback rather than rendering nothing")
    func unknownResolvesToFallback() {
        #expect(ChallengeSymbolCatalog.resolved("secret_mission") == ChallengeSymbolCatalog.fallback)
        #expect(ChallengeSymbolCatalog.resolved("music.mic") == "music.mic")
    }

    @Test("the catalogue has no duplicates")
    func noDuplicates() {
        #expect(Set(ChallengeSymbolCatalog.all).count == ChallengeSymbolCatalog.all.count)
    }
}
```

Add `import UIKit` to the top of `AuthoringTests.swift`.

- [ ] **Step 2: Run it and watch it fail**

```bash
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/ChallengeSymbolCatalogTests test 2>&1 | /usr/bin/tail -20
```

Expected: compile failure, "cannot find 'ChallengeSymbolCatalog' in scope".

- [ ] **Step 3: Write the catalogue**

Create `BirthdayQuest/BirthdayQuest/Models/ChallengeSymbolCatalog.swift`:

```swift
import Foundation

/// The symbols a host may attach to a challenge.
///
/// `Challenge.illustrationAsset` is interpreted as an SF Symbol name and falls back to
/// `bolt.fill` when it is not one (`TimelineNodeView.badgeIcon`). The dare flow writes the
/// literal `"secret_mission"`, which is not a symbol, so every secret dare has always
/// rendered the fallback and nobody noticed — a silent fallback is invisible by
/// construction. A curated list is what stops an authoring form reproducing that on purpose.
///
/// Mirrors `AvatarCatalog`: a fixed set, a fallback, and a test asserting every entry
/// actually resolves.
enum ChallengeSymbolCatalog {

    static let all: [String] = [
        "music.mic", "figure.run", "camera.fill", "paintbrush.fill",
        "heart.fill", "star.fill", "gift.fill", "book.fill",
        "fork.knife", "map.fill", "phone.fill", "hand.wave.fill",
        "theatermasks.fill", "bicycle", "leaf.fill", "sparkles",
        "flame.fill", "bolt.fill",
    ]

    static let fallback = "sparkles"

    static func resolved(_ name: String) -> String {
        all.contains(name) ? name : fallback
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests/ChallengeSymbolCatalogTests test 2>&1 | /usr/bin/grep -c 'TEST SUCCEEDED'
```

Expected: `1`. **If a symbol fails**, remove it from the list rather than weakening the test — the whole point is that the list is verified.

- [ ] **Step 5: Write the picker**

Create `BirthdayQuest/BirthdayQuest/Views/Components/SymbolPickerView.swift`. Every tile is ≥44×44pt regardless of glyph size, and selection carries a border as well as a colour so it does not depend on colour alone:

```swift
import SwiftUI

/// A grid picker over `ChallengeSymbolCatalog`.
///
/// Tiles are a fixed 44pt minimum because that is the tap-target floor, while the glyph
/// inside scales with Dynamic Type via `@ScaledMetric` — the target and the artwork are
/// different measurements and only one of them is a hit area.
///
/// Selection is shown by a border *and* a fill, not by colour alone: a colour-only
/// selection state is unreadable to anyone who cannot distinguish the two tints.
struct SymbolPickerView: View {

    @Binding var selection: String

    @ScaledMetric private var glyphSize: CGFloat = 20
    private let columns = [GridItem(.adaptive(minimum: 52), spacing: BQDesign.Spacing.sm)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: BQDesign.Spacing.sm) {
            ForEach(ChallengeSymbolCatalog.all, id: \.self) { name in
                let isSelected = selection == name
                Button {
                    selection = name
                    BQDesign.Haptics.selection()
                } label: {
                    Image(systemName: name)
                        .font(.system(size: glyphSize))
                        .foregroundStyle(
                            isSelected
                            ? BQDesign.Colors.primaryPurple
                            : BQDesign.Colors.textSecondary
                        )
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: BQDesign.Radius.sm, style: .continuous)
                                .fill(
                                    isSelected
                                    ? BQDesign.Colors.primaryPurple.opacity(0.12)
                                    : BQDesign.Colors.background
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BQDesign.Radius.sm, style: .continuous)
                                .stroke(
                                    isSelected
                                    ? BQDesign.Colors.primaryPurple
                                    : Color.clear,
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.spokenName(for: name))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// SF Symbol names are dot-separated identifiers, which VoiceOver reads literally
    /// ("music dot mic"). Spoken form instead.
    static func spokenName(for symbol: String) -> String {
        symbol
            .replacingOccurrences(of: ".fill", with: "")
            .split(separator: ".")
            .joined(separator: " ")
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add BirthdayQuest/BirthdayQuest/Models/ChallengeSymbolCatalog.swift \
        BirthdayQuest/BirthdayQuest/Views/Components/SymbolPickerView.swift \
        BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift
git commit -m "Add a verified symbol set for challenges

illustrationAsset is read as an SF Symbol name with a bolt.fill fallback, and
the dare flow writes 'secret_mission', which is not one - so every secret dare
has always rendered the fallback and nothing said so. A silent fallback is
invisible by construction, which is why the catalogue is tested for real
resolution rather than trusted.

A free-text field in the authoring form would let a host reproduce that bug on
purpose, so the field is a picker over this list."
```

---

## Task 8: `ChallengeAuthoringViewModel`

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/ViewModels/ChallengeAuthoringViewModel.swift`
- Modify: `BirthdayQuest/BirthdayQuest/AppConstants.swift` (one `ListenerKey` helper)
- Test: `BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift` (the suite written in Task 5 now runs)

**Interfaces:**
- Consumes: `createChallenge`, `updateChallenge`, `deleteChallenge` (Tasks 4-5); `ChallengeSymbolCatalog` (Task 7); `ContentState`, `AdminActionResult` (existing).
- Produces: `ChallengeAuthoringViewModel(eventId:service:)` with `challenges`, `contentState`, `draft`, `beginCreating()`, `beginEditing(_:)`, `save(authorUid:)`, `delete(_:)`, `startListening()`, `stopListening()`. Consumed by Task 9.
- Produces: `ChallengeDraft`, consumed by Task 9's editor.

- [ ] **Step 1: Add the listener key**

In `AppConstants.swift`, inside `enum ListenerKey`, after `gameState`:

```swift
    static func authoringChallenges(_ eventId: String) -> String {
        scoped("authoring_challenges", eventId: eventId)
    }
    static func authoringRewards(_ eventId: String) -> String {
        scoped("authoring_rewards", eventId: eventId)
    }
    static func myGift(_ eventId: String) -> String {
        scoped("my_gift", eventId: eventId)
    }
```

Its own key, not `admin_challenges`: the authoring screen is a `NavigationLink` push inside the Profile tab, so the host panel behind it stays alive and both are subscribed at once. Sharing a key means the pushed screen's `onDisappear` tears down the panel's listener — exactly R52's bug.

- [ ] **Step 2: Write the view model**

Create `BirthdayQuest/BirthdayQuest/ViewModels/ChallengeAuthoringViewModel.swift`:

```swift
import Foundation
import SwiftUI
import Combine
import OSLog

// MARK: - Challenge Draft

/// The editable shape of a challenge, separate from `Challenge` itself.
///
/// `Challenge` is almost entirely `let` and carries gameplay state (`isCompleted`, proof
/// fields) an author has no business setting. A draft holds only what the form edits, which
/// is also what makes `contentFields` provably free of gameplay keys — the rules reject a
/// write that mixes the two, so this is not a stylistic preference.
struct ChallengeDraft: Equatable {
    var title = ""
    var description = ""
    var pointValue = 50
    var difficulty: ChallengeDifficulty = .medium
    var category: ChallengeCategory = .social
    var symbol = ChallengeSymbolCatalog.fallback
    var hasOptionB = false
    var optionBTitle = ""
    var optionBDescription = ""

    init() {}

    init(from challenge: Challenge) {
        title = challenge.title
        description = challenge.description
        pointValue = challenge.pointValue
        difficulty = challenge.difficulty
        category = challenge.category
        symbol = ChallengeSymbolCatalog.resolved(challenge.illustrationAsset)
        hasOptionB = challenge.optionBTitle != nil
        optionBTitle = challenge.optionBTitle ?? ""
        optionBDescription = challenge.optionBDescription ?? ""
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool { !trimmedTitle.isEmpty && !trimmedDescription.isEmpty }

    /// Content keys only. Never a gameplay key — the rules deny a mixed write, which is what
    /// stops a member smuggling a point-value change inside a completion.
    var contentFields: [String: Any] {
        [
            "title": trimmedTitle,
            "description": trimmedDescription,
            "pointValue": pointValue,
            "difficulty": difficulty.rawValue,
            "category": category.rawValue,
            "illustrationAsset": symbol,
            "optionBTitle": hasOptionB ? optionBTitle : "",
            "optionBDescription": hasOptionB ? optionBDescription : "",
        ]
    }

    /// `isDelivered: true` because a host-authored challenge is live the moment it is saved.
    /// Only a contributor's dare is held back for a separate "deliver" step.
    func newChallenge(authorUid: String) -> Challenge {
        Challenge(
            title: trimmedTitle,
            description: trimmedDescription,
            illustrationAsset: symbol,
            pointValue: pointValue,
            difficulty: difficulty,
            category: category,
            isSecret: false,
            createdByUserId: authorUid,
            isDelivered: true,
            isCompleted: false,
            completedAt: nil,
            proofUrl: nil,
            proofType: nil,
            proofText: nil,
            createdAt: Date(),
            optionBTitle: hasOptionB ? optionBTitle : nil,
            optionBDescription: hasOptionB ? optionBDescription : nil
        )
    }
}

// MARK: - Challenge Authoring View Model

@MainActor
final class ChallengeAuthoringViewModel: ObservableObject {

    @Published private(set) var challenges: [Challenge] = []
    @Published private(set) var contentState: ContentState = .loading
    @Published var draft = ChallengeDraft()
    @Published var isEditorPresented = false
    @Published var challengeToDelete: Challenge?
    @Published var actionResult: AdminActionResult?
    @Published var isPerformingAction = false
    /// Set the first time Save is pressed on an invalid draft, which is what reveals the
    /// inline field errors. Save is never disabled: a greyed-out button with no explanation
    /// is indistinguishable from a broken one.
    @Published var showValidation = false

    /// nil while creating, the document id while editing. The editor renders from `draft`
    /// either way, so this is the only thing distinguishing the two modes.
    private(set) var editingId: String?

    private let service: GameBackend
    private let eventId: String
    private let listenerKey: String
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Authoring")

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
        self.listenerKey = ListenerKey.authoringChallenges(eventId)
    }

    /// Host-authored challenges only. A contributor's secret dare belongs to them — the host
    /// can still force-complete or delete it from the existing host panel, but editing
    /// someone else's dare is not what this screen is for, and the rules would refuse.
    private var authorable: [Challenge] { challenges.filter { !$0.isSecret } }

    var visibleChallenges: [Challenge] {
        authorable.sorted { $0.pointValue < $1.pointValue }
    }

    var isEditing: Bool { editingId != nil }

    // MARK: Listener

    func startListening() {
        service.listenToChallenges(eventId: eventId, listenerKey: listenerKey) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let challenges):
                    self.challenges = challenges
                    self.contentState = self.authorable.isEmpty ? .empty : .ready
                case .failure(let error):
                    self.logger.error("Authoring listener: \(error.localizedDescription)")
                    self.challenges = []
                    self.contentState = .failed("Couldn't load this occasion's challenges.")
                }
            }
        }
    }

    func stopListening() {
        service.removeListener(forKey: listenerKey)
    }

    // MARK: Editor lifecycle

    func beginCreating() {
        editingId = nil
        draft = ChallengeDraft()
        showValidation = false
        isEditorPresented = true
    }

    func beginEditing(_ challenge: Challenge) {
        editingId = challenge.id
        draft = ChallengeDraft(from: challenge)
        showValidation = false
        isEditorPresented = true
    }

    // MARK: Writes

    /// Never gated behind a disabled button. An invalid draft reveals its field errors and
    /// returns; a valid one writes.
    func save(authorUid: String) async {
        guard !isPerformingAction else { return }
        guard draft.isValid else {
            showValidation = true
            BQDesign.Haptics.error()
            return
        }
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            if let editingId {
                try await service.updateChallenge(
                    eventId: eventId, challengeId: editingId, data: draft.contentFields
                )
            } else {
                _ = try await service.createChallenge(
                    eventId: eventId, challenge: draft.newChallenge(authorUid: authorUid)
                )
            }
            isEditorPresented = false
            actionResult = AdminActionResult(
                message: isEditing ? "Saved your changes." : "Added \"\(draft.title)\".",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            logger.error("Saving a challenge failed: \(error.localizedDescription)")
            actionResult = AdminActionResult(
                message: "Couldn't save that challenge. \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
    }

    func delete(_ challenge: Challenge) async {
        guard let challengeId = challenge.id else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await service.deleteChallenge(eventId: eventId, challengeId: challengeId)
            actionResult = AdminActionResult(
                message: "Deleted \"\(challenge.title)\".", isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            logger.error("Deleting a challenge failed: \(error.localizedDescription)")
            actionResult = AdminActionResult(
                message: "Couldn't delete that challenge. \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
    }
}
```

- [ ] **Step 3: Run the suite from Task 5, which now compiles**

```bash
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests test > /tmp/t8.log 2>&1; echo "exit=$?" >> /tmp/t8.log
/usr/bin/grep -c 'TEST SUCCEEDED' /tmp/t8.log
```

Expected: `1`, with `AuthoringCounterTests` now running.

- [ ] **Step 4: Add the two `ContentState` tests this screen needs**

The empty state on this screen is the host's first instruction, so a refused read rendering as "no challenges yet" would tell them to start authoring into an occasion that has stopped answering. Append to `AuthoringTests.swift`:

```swift
@MainActor
@Suite("Challenge authoring renders a refused read as a failure")
struct ChallengeAuthoringStateTests {

    private func permissionDenied() -> NSError {
        NSError(
            domain: "FIRFirestoreErrorDomain", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )
    }

    @Test("a refused read is .failed, never an invitation to start authoring")
    func refusedReadIsFailed() async {
        let mock = MockGameBackend()
        mock.listenerFailure = permissionDenied()
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        for _ in 0..<8 { await Task.yield() }

        guard case .failed(let message) = vm.contentState else {
            Issue.record("expected .failed, got \(String(describing: vm.contentState))")
            return
        }
        #expect(message.isEmpty == false)
    }

    @Test("a genuinely empty occasion still reads as empty")
    func emptyIsEmpty() async {
        let mock = MockGameBackend()
        mock.challenges = []
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        for _ in 0..<8 { await Task.yield() }

        #expect(vm.contentState == .empty)
    }

    @Test("an occasion holding only secret dares still reads as empty to the host")
    func onlySecretDaresIsEmpty() async {
        let mock = MockGameBackend()
        mock.challenges = [.fixture(id: "s1", isSecret: true)]
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        for _ in 0..<8 { await Task.yield() }

        #expect(vm.contentState == .empty)
        #expect(vm.visibleChallenges.isEmpty, "a contributor's dare is not the host's to edit")
    }
}
```

- [ ] **Step 5: Run and commit**

```bash
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests test > /tmp/t8b.log 2>&1; echo "exit=$?" >> /tmp/t8b.log
/usr/bin/grep -c 'TEST SUCCEEDED' /tmp/t8b.log
cd .. && swiftlint --strict
git add BirthdayQuest/BirthdayQuest/ViewModels/ChallengeAuthoringViewModel.swift \
        BirthdayQuest/BirthdayQuest/AppConstants.swift \
        BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift
git commit -m "Add the host's challenge authoring view model

ChallengeDraft holds only the fields the form edits, which is what makes
contentFields provably free of gameplay keys - the rules reject a write mixing
the two, so keeping them apart is enforcement, not tidiness.

Host-authored challenges are stamped isDelivered: true, because they are live
on save; only a contributor's dare is held back for a separate deliver step.

Its own listener key, not the host panel's: the authoring screen is pushed
inside the Profile tab, so both are subscribed at once and a shared key would
let this screen's teardown kill the panel's listener."
```

---
## Task 9: The challenge authoring screens, and the host-panel entry point

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/Views/Authoring/ChallengeAuthoringView.swift`
- Create: `BirthdayQuest/BirthdayQuest/Views/Authoring/ChallengeEditorView.swift`
- Modify: `BirthdayQuest/BirthdayQuest/Views/Profile/AdminControlsView.swift` (one new card, one line in `body`)

**Interfaces:**
- Consumes: `ChallengeAuthoringViewModel`, `ChallengeDraft` (Task 8); `SymbolPickerView` (Task 7); `ContentFailureView`, `ContentState` (existing).

**Two constraints that shape these files:**
1. `AdminControlsView` owns a `NavigationStack` (`:31`). `ChallengeAuthoringView` is pushed into it and **must not** introduce another. `ChallengeEditorView` is presented as a sheet and **does** need its own, because a sheet is a new presentation context.
2. `.adminCard()` is `private extension View` inside `AdminControlsView.swift` (`:758-769`). A new file cannot call it. The authoring screens are `List`/`Form`-based and do not need it — do not copy the modifier into a second file.

- [ ] **Step 1: Write the list screen**

Create `BirthdayQuest/BirthdayQuest/Views/Authoring/ChallengeAuthoringView.swift`:

```swift
import SwiftUI

/// The host's challenge list.
///
/// Pushed from `AdminControlsView`, which owns the `NavigationStack` — this view must not
/// add another, or the pushed screen gets a second nav bar.
struct ChallengeAuthoringView: View {

    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: ChallengeAuthoringViewModel

    @ScaledMetric private var rowGlyphSize: CGFloat = 18

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: ChallengeAuthoringViewModel(eventId: eventId))
    }

    var body: some View {
        Group {
            switch viewModel.contentState {
            case .loading:
                ProgressView()
                    .tint(BQDesign.Colors.primaryPurple)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentFailureView(message: message)
            case .empty:
                emptyState
            case .ready:
                list
            }
        }
        .background(BQDesign.Colors.background.ignoresSafeArea())
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.beginCreating()
                } label: {
                    Label("New challenge", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.isEditorPresented) {
            ChallengeEditorView(
                viewModel: viewModel,
                authorUid: event.participant?.id ?? ""
            )
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { viewModel.challengeToDelete != nil },
                set: { if !$0 { viewModel.challengeToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let challenge = viewModel.challengeToDelete {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete(challenge) }
                }
                Button("Keep it", role: .cancel) { viewModel.challengeToDelete = nil }
            }
        } message: {
            Text("This can't be undone.")
        }
        .alert(
            viewModel.actionResult?.isError == true ? "Couldn't do that" : "Done",
            isPresented: Binding(
                get: { viewModel.actionResult != nil },
                set: { if !$0 { viewModel.actionResult = nil } }
            )
        ) {
            Button("OK") { viewModel.actionResult = nil }
        } message: {
            Text(viewModel.actionResult?.message ?? "")
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
    }

    /// Names the specific challenge rather than asking "Are you sure?", so the host can act
    /// without rereading the row behind the dialog.
    private var deleteTitle: String {
        if let title = viewModel.challengeToDelete?.title {
            return "Delete \"\(title)\"?"
        }
        return "Delete this challenge?"
    }

    /// The first thing a host sees in a brand-new occasion, so it carries the instruction
    /// rather than decorating the absence of one.
    private var emptyState: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            Text("No challenges yet")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundStyle(BQDesign.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("""
                Challenges are how \(event.celebrantName) earns points. Add a few, and keep \
                the total just short of what the gifts cost — the secret dares close the gap.
                """)
                .font(BQDesign.Typography.body)
                .foregroundStyle(BQDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button("Create your first challenge") {
                viewModel.beginCreating()
            }
            .font(BQDesign.Typography.bodyBold)
            .buttonStyle(.borderedProminent)
            .tint(BQDesign.Colors.primaryPurple)
        }
        .padding(BQDesign.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(viewModel.visibleChallenges) { challenge in
                Button {
                    viewModel.beginEditing(challenge)
                } label: {
                    row(challenge)
                }
                .buttonStyle(.plain)
                .listRowBackground(BQDesign.Colors.cardBackground)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewModel.challengeToDelete = challenge
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// The title deliberately has no `lineLimit`: truncating it with no way to see the rest
    /// would hide the one thing that distinguishes one row from another, and this list has
    /// no detail view that would recover it — tapping opens the editor, not a reader.
    private func row(_ challenge: Challenge) -> some View {
        HStack(spacing: BQDesign.Spacing.md) {
            Image(systemName: ChallengeSymbolCatalog.resolved(challenge.illustrationAsset))
                .font(.system(size: rowGlyphSize))
                .foregroundStyle(BQDesign.Colors.primaryPurple)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                Text(challenge.title)
                    .font(BQDesign.Typography.cardTitle)
                    .foregroundStyle(BQDesign.Colors.textPrimary)

                Text("\(challenge.pointValue) points · \(challenge.difficulty.rawValue)")
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, BQDesign.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the challenge editor")
    }
}
```

- [ ] **Step 2: Write the editor sheet**

Create `BirthdayQuest/BirthdayQuest/Views/Authoring/ChallengeEditorView.swift`:

```swift
import SwiftUI

/// Create or edit one challenge.
///
/// Save is never disabled. An invalid draft reveals its field errors on the first press and
/// writes nothing; a greyed-out button with no explanation is indistinguishable from a
/// broken one, and assistive technology routinely skips disabled controls entirely.
struct ChallengeEditorView: View {

    @ObservedObject var viewModel: ChallengeAuthoringViewModel
    let authorUid: String

    @Environment(\.dismiss) private var dismiss

    private var titleIsMissing: Bool {
        viewModel.showValidation
            && viewModel.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var descriptionIsMissing: Bool {
        viewModel.showValidation
            && viewModel.draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                scoringSection
                symbolSection
                optionBSection
            }
            .navigationTitle(viewModel.isEditing ? "Edit challenge" : "New challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await viewModel.save(authorUid: authorUid) }
                    }
                    .font(BQDesign.Typography.bodyBold)
                }
            }
            .overlay {
                if viewModel.isPerformingAction {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .overlay(ProgressView().tint(BQDesign.Colors.primaryPurple))
                }
            }
        }
    }

    private var basicsSection: some View {
        Section("Basics") {
            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                Text("Title")
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
                TextField("", text: $viewModel.draft.title, prompt: Text("Sing in public"))
                    .font(BQDesign.Typography.body)
                    .accessibilityLabel("Title")
                if titleIsMissing {
                    fieldError("Give the challenge a title.")
                }
            }

            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                Text("What they have to do")
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
                TextField(
                    "", text: $viewModel.draft.description,
                    prompt: Text("Somewhere busy, and get it on camera"),
                    axis: .vertical
                )
                .font(BQDesign.Typography.body)
                .lineLimit(3...8)
                .accessibilityLabel("What they have to do")
                if descriptionIsMissing {
                    fieldError("Say what they have to do.")
                }
            }
        }
    }

    private var scoringSection: some View {
        Section("Scoring") {
            Stepper(value: $viewModel.draft.pointValue, in: 5...500, step: 5) {
                HStack {
                    Text("Points").font(BQDesign.Typography.body)
                    Spacer()
                    Text("\(viewModel.draft.pointValue)")
                        .font(BQDesign.Typography.bodyBold)
                        .foregroundStyle(BQDesign.Colors.goldText)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("Points")
            .accessibilityValue("\(viewModel.draft.pointValue)")

            Picker("Difficulty", selection: $viewModel.draft.difficulty) {
                ForEach(ChallengeDifficulty.allCases, id: \.self) { level in
                    Text(level.rawValue.capitalized).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Picker("Category", selection: $viewModel.draft.category) {
                ForEach(ChallengeCategory.allCases, id: \.self) { category in
                    Text(category.rawValue.capitalized).tag(category)
                }
            }
        }
    }

    private var symbolSection: some View {
        Section("Symbol") {
            SymbolPickerView(selection: $viewModel.draft.symbol)
                .padding(.vertical, BQDesign.Spacing.xs)
        }
    }

    private var optionBSection: some View {
        Section {
            Toggle("Offer a second option", isOn: $viewModel.draft.hasOptionB)

            if viewModel.draft.hasOptionB {
                TextField(
                    "", text: $viewModel.draft.optionBTitle,
                    prompt: Text("Second option title")
                )
                .accessibilityLabel("Second option title")

                TextField(
                    "", text: $viewModel.draft.optionBDescription,
                    prompt: Text("What the second option involves"), axis: .vertical
                )
                .lineLimit(2...5)
                .accessibilityLabel("Second option description")
            }
        } footer: {
            Text("A 2-in-1 challenge lets them pick either option. Off unless you turn it on.")
                .font(BQDesign.Typography.captionSmall)
        }
    }

    /// The colour sits on the icon; the sentence stays at `textPrimary`. `Colors.error` is
    /// 3.59:1 — large-text-and-UI only, never a body sentence.
    private func fieldError(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BQDesign.Spacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(BQDesign.Colors.error)
                .accessibilityHidden(true)
            Text(message)
                .font(BQDesign.Typography.captionSmall)
                .foregroundStyle(BQDesign.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 3: Add the entry point to the host panel**

In `AdminControlsView.swift`, add one line to `body`'s `VStack`, immediately after `inviteCard` (authoring is what a host does first in a new occasion, so it belongs above the runtime controls):

```swift
                    // 0b. Authoring. A row that pushes, not a card that expands: this file
                    // is already the largest view in the app, and R60 forbids a second host
                    // panel, not a second file.
                    authoringCard
```

And add the card in a `private extension AdminControlsView` block, following the file's existing pattern:

```swift
// MARK: - Section 0b: Authoring

private extension AdminControlsView {

    var authoringCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            adminSectionHeader("Content", icon: "square.and.pencil")

            NavigationLink {
                ChallengeAuthoringView(eventId: event.eventId)
                    .environmentObject(event)
            } label: {
                authoringRow(
                    "Challenges",
                    subtitle: "\(viewModel.challenges.filter { !$0.isSecret }.count) added",
                    icon: "flag.checkered"
                )
            }

            NavigationLink {
                GiftCurationView(eventId: event.eventId)
                    .environmentObject(event)
            } label: {
                authoringRow(
                    "Gifts",
                    subtitle: "\(viewModel.rewards.count) from your guests",
                    icon: "gift.fill"
                )
            }
        }
        .adminCard()
    }

    func authoringRow(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: BQDesign.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: sectionHeaderIconSize))
                .foregroundStyle(BQDesign.Colors.primaryPurple)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BQDesign.Typography.caption)
                    .foregroundStyle(BQDesign.Colors.textPrimary)
                Text(subtitle)
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
                    .monospacedDigit()
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: chevronIconSize))
                .foregroundStyle(BQDesign.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(BQDesign.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.sm, style: .continuous)
                .fill(BQDesign.Colors.background)
        )
        .accessibilityElement(children: .combine)
    }
}
```

`GiftCurationView` does not exist until Task 12. Either implement Tasks 9 and 12 as one unit, or temporarily comment out the second `NavigationLink` and restore it in Task 12 — say which in the commit message rather than leaving a silently dead link.

- [ ] **Step 4: Build, lint and verify by hand**

```bash
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests test > /tmp/t9.log 2>&1; echo "exit=$?" >> /tmp/t9.log
/usr/bin/grep -c 'TEST SUCCEEDED' /tmp/t9.log
cd .. && swiftlint --strict
```

There are no snapshot tests, so the unit suite cannot see clipping or overlap. This screen is a dense form and belongs in the first attended large-text pass (R75) — do not claim it is verified.

- [ ] **Step 5: Commit**

```bash
git add BirthdayQuest/BirthdayQuest/Views/Authoring BirthdayQuest/BirthdayQuest/Views/Profile/AdminControlsView.swift
git commit -m "Let the host write challenges

A row in the host panel that pushes a list, rather than a ninth card inside
it: AdminControlsView is already the largest view in the app at 769 lines, and
R60 forbids a second host panel, not a second file.

Save is never disabled - an invalid draft reveals its field errors and writes
nothing. A disabled button with no explanation reads as broken, and assistive
technology often skips disabled controls outright.

The empty state carries the instruction, because an empty occasion is the
problem this subsystem exists to solve."
```

---
## Task 10: `GiftAuthoringViewModel`

One gift per contributor, recovered the same way the secret dare is: scan the shared listener for the row whose author is you. `SecretChallengeViewModel` is the pattern — copy its shape rather than inventing a second one.

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/ViewModels/GiftAuthoringViewModel.swift`
- Test: `BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift`

**Interfaces:**
- Consumes: `createReward`, `updateReward` (Task 6); `ListenerKey.myGift` (Task 8).
- Produces: `GiftAuthoringViewModel(eventId:service:)` with `title`, `teaser`, `body`, `contentState`, `hasExisting`, `loadExisting(userId:name:)`, `save()`, `stopListening()`. Consumed by Task 11.

**Two decisions encoded here:**
- **A new gift is created at 100 points, not 0.** The host owns pricing, but a gift created at 0 is instantly unlockable — it would appear on the board already free. A non-zero default means the host is retuning a price rather than repairing a hole.
- **`sortOrder` is the current gift count**, so a new gift lands at the end. The contributor's listener already sees every gift (read is member-wide), so the count is available without an extra read.

- [ ] **Step 1: Write the failing tests**

```swift
@MainActor
@Suite("Gift authoring")
struct GiftAuthoringTests {

    @Test("saving a new gift stamps the author and a non-zero price")
    func createStampsAuthorAndPrice() async {
        let mock = MockGameBackend()
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "uid_jo", name: "Jordan")
        for _ in 0..<8 { await Task.yield() }
        vm.title = "A letter"
        vm.teaser = "Open me last"
        vm.letter = "Dear Alex..."

        await vm.save()

        let created = mock.createdRewards.first
        #expect(created?.fromUserId == "uid_jo")
        #expect(created?.fromName == "Jordan")
        #expect(created?.contentType == .text)
        #expect(created?.contentText == "Dear Alex...")
        #expect((created?.pointCost ?? 0) > 0, "a gift created free is instantly unlockable")
    }

    @Test("a new gift sorts to the end of the existing list")
    func newGiftSortsLast() async {
        let mock = MockGameBackend()
        mock.rewards = [.fixture(id: "r1"), .fixture(id: "r2")]
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "uid_jo", name: "Jordan")
        for _ in 0..<8 { await Task.yield() }
        vm.title = "A letter"; vm.letter = "x"

        await vm.save()

        #expect(mock.createdRewards.first?.sortOrder == 2)
    }

    @Test("editing an existing gift sends only content fields, never the price")
    func editSendsOnlyContent() async {
        let mock = MockGameBackend()
        // fixture defaults to isUnlocked: false, which is what makes it still editable.
        let mine = Reward.fixture(id: "r_mine", contentType: .text)
        mock.rewards = [mine]
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "u1", name: "Jordan")   // fixture's fromUserId is "u1"
        for _ in 0..<8 { await Task.yield() }
        #expect(vm.hasExisting)
        vm.letter = "Rewritten"

        await vm.save()

        let sent = Set(mock.updatedRewards.first?.fields.keys ?? [:].keys)
        #expect(!sent.contains("pointCost"), "pricing is the host's, and a mixed write is denied")
        #expect(!sent.contains("sortOrder"))
        #expect(!sent.contains("isUnlocked"))
        #expect(sent.contains("contentText"))
    }

    @Test("a refused read renders as a failure, not as an invitation to write a gift")
    func refusedReadIsFailed() async {
        let mock = MockGameBackend()
        mock.listenerFailure = NSError(
            domain: "FIRFirestoreErrorDomain", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "uid_jo", name: "Jordan")
        for _ in 0..<8 { await Task.yield() }

        guard case .failed = vm.contentState else {
            Issue.record("expected .failed, got \(String(describing: vm.contentState))")
            return
        }
    }
}
```

- [ ] **Step 2: Run and watch it fail** — "cannot find 'GiftAuthoringViewModel' in scope".

- [ ] **Step 3: Write the view model**

Create `BirthdayQuest/BirthdayQuest/ViewModels/GiftAuthoringViewModel.swift`:

```swift
import Foundation
import SwiftUI
import Combine
import OSLog

/// One contributor's gift to the celebrant.
///
/// Shaped exactly like `SecretChallengeViewModel`: one per person, recovered by scanning the
/// shared listener for the row whose author is you rather than by remembering a document id
/// across launches.
///
/// The contributor writes the gift; the **host** sets its price and position. That split is
/// enforced in `firestore.rules` — a write from here carrying `pointCost` is denied — so
/// `contentFields` must never include one.
@MainActor
final class GiftAuthoringViewModel: ObservableObject {

    @Published var title = ""
    @Published var teaser = ""
    @Published var letter = ""
    @Published private(set) var existingGift: Reward?
    @Published private(set) var isLoading = true
    @Published var isSaving = false
    @Published var saveSuccess = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showValidation = false
    /// Set when the gift listener is refused. Separate from `errorMessage`, which drives the
    /// save alert: a refused read is a persistent state, and an alert is dismissed straight
    /// back onto a blank form that invites writing a gift into an occasion that has stopped
    /// answering.
    @Published private(set) var loadFailure: String?

    /// Every gift in the occasion, held only to place a new one at the end of the order.
    private var allGifts: [Reward] = []
    private var userId: String?
    private var authorName: String = ""

    private let service: GameBackend
    private let eventId: String
    private let listenerKey: String
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "GiftAuthoring")

    /// A gift created at zero is unlockable the instant it appears. The host retunes this;
    /// the default only has to be a price rather than a hole.
    private static let defaultPointCost = 100

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
        self.listenerKey = ListenerKey.myGift(eventId)
    }

    var hasExisting: Bool { existingGift != nil }

    /// Locked once the celebrant has opened it. Rewriting a gift someone has already read
    /// would silently change what they were given.
    var isEditable: Bool { !(existingGift?.isUnlocked ?? false) }

    var contentState: ContentState {
        if let loadFailure { return .failed(loadFailure) }
        return isLoading ? .loading : .ready
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !letter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var statusText: String {
        if loadFailure != nil { return "Couldn't load your gift" }
        if existingGift?.isUnlocked == true { return "Opened — they've read it" }
        if hasExisting { return "Saved — edit any time" }
        return "Write your gift"
    }

    // MARK: Load

    func loadExisting(userId: String?, name: String) {
        self.userId = userId
        self.authorName = name
        guard let userId else {
            isLoading = false
            return
        }

        service.listenToRewards(eventId: eventId, listenerKey: listenerKey) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let gifts):
                    self.allGifts = gifts
                    if let mine = gifts.first(where: { $0.fromUserId == userId }) {
                        self.existingGift = mine
                        self.title = mine.title
                        self.teaser = mine.teaser ?? ""
                        self.letter = mine.contentText ?? ""
                    }
                    self.loadFailure = nil
                case .failure(let error):
                    self.logger.error("Gift listener: \(error.localizedDescription)")
                    self.loadFailure = """
                        Your gift didn't load. You may no longer have access to this \
                        occasion, or the connection dropped.
                        """
                }
            }
        }
    }

    func stopListening() {
        service.removeListener(forKey: listenerKey)
    }

    // MARK: Save

    func save() async {
        guard !isSaving, let userId else { return }
        guard isValid else {
            showValidation = true
            BQDesign.Haptics.error()
            return
        }

        isSaving = true
        defer { isSaving = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTeaser = teaser.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLetter = letter.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if let existing = existingGift, let id = existing.id {
                // Content keys only. pointCost and sortOrder are the host's tier, and the
                // rules reject a write that reaches across tiers.
                try await service.updateReward(eventId: eventId, rewardId: id, fields: [
                    "title": trimmedTitle,
                    "teaser": trimmedTeaser,
                    "contentText": trimmedLetter,
                ])
            } else {
                let gift = Reward(
                    fromUserId: userId,
                    fromName: authorName,
                    title: trimmedTitle,
                    teaser: trimmedTeaser,
                    pointCost: Self.defaultPointCost,
                    contentType: .text,
                    contentUrl: nil,
                    contentUrls: nil,
                    contentText: trimmedLetter,
                    isUnlocked: false,
                    unlockedAt: nil,
                    sortOrder: allGifts.count,
                    badgeIllustration: "envelope.fill",
                    createdAt: Date()
                )
                _ = try await service.createReward(eventId: eventId, reward: gift)
            }

            saveSuccess = true
            BQDesign.Haptics.success()
            try? await Task.sleep(for: .milliseconds(1500))
            saveSuccess = false
        } catch {
            logger.error("Saving the gift failed: \(error.localizedDescription)")
            errorMessage = "Couldn't save your gift. Try again."
            showError = true
            BQDesign.Haptics.error()
        }
    }
}
```

- [ ] **Step 4: Run the suite, lint, commit**

```bash
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests test > /tmp/t10.log 2>&1; echo "exit=$?" >> /tmp/t10.log
/usr/bin/grep -c 'TEST SUCCEEDED' /tmp/t10.log
cd .. && swiftlint --strict
git add BirthdayQuest/BirthdayQuest/ViewModels/GiftAuthoringViewModel.swift BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift
git commit -m "Add the contributor's gift view model

One gift per person, recovered by scanning the shared listener for the row
whose fromUserId is yours - the same shape as the secret dare, deliberately,
rather than a second pattern for the same problem.

Writes content fields only. pointCost and sortOrder belong to the host's tier
and the rules reject a write that reaches across tiers, so a stray key here is
a permission-denied, not a cosmetic slip.

A new gift is created at 100 points rather than 0: a gift priced at zero is
unlockable the moment it appears, so the host would be repairing a hole rather
than tuning a price."
```

---

## Task 11: The gift tab

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/Views/Contributor/GiftAuthoringView.swift`
- Modify: `BirthdayQuest/BirthdayQuest/Services/EventSession.swift:35-55` (`ContributorTab`)
- Modify: `BirthdayQuest/BirthdayQuest/Views/Contributor/ContributorTabView.swift`

**Interfaces:**
- Consumes: `GiftAuthoringViewModel` (Task 10).

**Why a fourth tab and not a merged screen:** `SecretChallengeHomeView` is a deliberate full-bleed dark surface (`secretGradient.ignoresSafeArea()`, `secretAccent` throughout, documented as "Secret agent themed"). A warm gift letter inside it forces one theme to lose. Worse, R72 records that `textSecondary` darkened to `#6B6880` measures **3.18:1 on the dark secret surfaces** — harmless today *only because no dark-themed view uses the token*. Putting prose content on that screen is precisely what would make that latent failure real.

- [ ] **Step 1: Add the enum case**

In `EventSession.swift`, `ContributorTab` is `Int`-backed with `case secretChallenge = 0`. **Append** `gift` rather than inserting it, so no existing raw value shifts. Nothing persists this value (there is no `UserDefaults`, `@AppStorage` or `@SceneStorage` anywhere in the app — verified), so a shift would in fact be harmless; appending is free insurance and costs a reader nothing.

```swift
enum ContributorTab: Int, CaseIterable {
    case secretChallenge = 0
    case timeline
    case profile
    /// Appended, not inserted: raw values are positional and nothing gains from renumbering
    /// the three that already exist. Tab *order* is set by the TabView body, not by this.
    case gift

    var title: String {
        switch self {
        case .secretChallenge: return "Secret Dare"
        case .gift:            return "Gift"
        case .timeline:        return "Timeline"
        case .profile:         return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .secretChallenge: return "eye.slash.fill"
        case .gift:            return "gift.fill"
        case .timeline:        return "safari.fill"
        case .profile:         return "person.crop.circle.fill"
        }
    }
}
```

Keep whatever the existing `.profile` icon literal is — the value above is illustrative; read it from the file and preserve it.

- [ ] **Step 2: Write the gift editor**

Create `BirthdayQuest/BirthdayQuest/Views/Contributor/GiftAuthoringView.swift`:

```swift
import SwiftUI

/// The contributor's gift to the celebrant: a letter they unlock with points.
///
/// Light-surfaced on purpose. Its sibling tab, the secret dare, is a deliberately dark
/// "dossier"; a warm letter does not belong on that surface, and `textSecondary` measures
/// 3.18:1 there.
struct GiftAuthoringView: View {

    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: GiftAuthoringViewModel

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: GiftAuthoringViewModel(eventId: eventId))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.contentState {
                case .loading:
                    ProgressView().tint(BQDesign.Colors.primaryPurple)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentFailureView(message: message)
                case .empty, .ready:
                    form
                }
            }
            .background(BQDesign.Colors.background.ignoresSafeArea())
            .navigationTitle("Your gift")
            .alert("Couldn't save", isPresented: $viewModel.showError) {
                Button("OK") { viewModel.showError = false }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .onAppear {
            viewModel.loadExisting(
                userId: event.participant?.id,
                name: event.participant?.name ?? "A friend"
            )
        }
        .onDisappear { viewModel.stopListening() }
    }

    private var form: some View {
        Form {
            Section {
                Text(viewModel.statusText)
                    .font(BQDesign.Typography.caption)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
            }

            Section("Your letter") {
                labelled("Title", hint: "What \(event.celebrantName) sees before unlocking") {
                    TextField("", text: $viewModel.title, prompt: Text("A letter from me"))
                        .accessibilityLabel("Title")
                }
                if viewModel.showValidation
                    && viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fieldError("Give your gift a title.")
                }

                labelled("Teaser", hint: "One line, shown while it's still locked") {
                    TextField("", text: $viewModel.teaser, prompt: Text("Open this one last"))
                        .accessibilityLabel("Teaser")
                }

                labelled("The letter itself", hint: nil) {
                    TextField(
                        "", text: $viewModel.letter,
                        prompt: Text("Say the thing you'd say in person"), axis: .vertical
                    )
                    .lineLimit(6...20)
                    .accessibilityLabel("The letter itself")
                }
                if viewModel.showValidation
                    && viewModel.letter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fieldError("Write something for them to read.")
                }
            }
            .disabled(!viewModel.isEditable)

            Section {
                Button {
                    Task { await viewModel.save() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text(saveLabel).font(BQDesign.Typography.bodyBold)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(BQDesign.Colors.primaryPurple)
                .disabled(!viewModel.isEditable)
            } footer: {
                Text(
                    viewModel.isEditable
                    ? "Your host sets what it costs to unlock."
                    : "\(event.celebrantName) has opened this, so it can't be changed now."
                )
                .font(BQDesign.Typography.captionSmall)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var saveLabel: String {
        if viewModel.saveSuccess { return "Saved" }
        return viewModel.hasExisting ? "Update gift" : "Save gift"
    }

    private func labelled<Content: View>(
        _ label: String, hint: String?, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
            Text(label)
                .font(BQDesign.Typography.captionSmall)
                .foregroundStyle(BQDesign.Colors.textSecondary)
            content()
                .font(BQDesign.Typography.body)
            if let hint {
                Text(hint)
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
            }
        }
    }

    private func fieldError(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BQDesign.Spacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(BQDesign.Colors.error)
                .accessibilityHidden(true)
            Text(message)
                .font(BQDesign.Typography.captionSmall)
                .foregroundStyle(BQDesign.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
```

Note the Save button *is* `.disabled` when the gift is locked. That is not the anti-pattern: the footer states the reason in the same view, and the state is genuinely immutable rather than merely incomplete.

- [ ] **Step 3: Add the tab, second in order**

In `ContributorTabView.swift`, insert between the secret-dare tab and the timeline tab:

```swift
            GiftAuthoringView(eventId: event.eventId)
                .tabItem {
                    Label(ContributorTab.gift.title, systemImage: ContributorTab.gift.icon)
                }
                .tag(ContributorTab.gift)
```

- [ ] **Step 4: Build, lint, commit**

```bash
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests test > /tmp/t11.log 2>&1; echo "exit=$?" >> /tmp/t11.log
/usr/bin/grep -c 'TEST SUCCEEDED' /tmp/t11.log
cd .. && swiftlint --strict
git add BirthdayQuest/BirthdayQuest/Views/Contributor BirthdayQuest/BirthdayQuest/Services/EventSession.swift
git commit -m "Give contributors somewhere to write their gift

A fourth tab rather than a section inside the secret-dare screen. That screen
is a deliberate full-bleed dark dossier, and a warm letter inside it forces one
of the two themes to lose - and would put prose on a surface where
textSecondary measures 3.18:1, a latent failure that is currently harmless
only because no dark-themed view uses the token.

The enum case is appended rather than inserted so no raw value shifts; tab
order comes from the TabView body."
```

---
## Task 12: Gift curation — the host prices and orders

**Files:**
- Create: `BirthdayQuest/BirthdayQuest/ViewModels/GiftCurationViewModel.swift`
- Create: `BirthdayQuest/BirthdayQuest/Views/Authoring/GiftCurationView.swift`
- Modify: `BirthdayQuest/BirthdayQuest/Views/Profile/AdminControlsView.swift` (restore the second `NavigationLink` if it was commented out in Task 9)
- Test: `BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift`

**Interfaces:**
- Consumes: `updateReward`, `deleteReward`, `setRewardOrder` (Task 6); `ListenerKey.authoringRewards` (Task 8).

**Reorder must be `List` + `.onMove`.** `.onMove` ships VoiceOver's Reorder custom action and Switch Control support for free. WCAG 2.5.7 requires every drag interaction to have a non-drag path, and a hand-rolled `DragGesture` means hand-reimplementing that — which is the version that ships without it. Do not hand-roll this.

- [ ] **Step 1: Write the failing tests**

```swift
@MainActor
@Suite("Gift curation")
struct GiftCurationTests {

    @Test("repricing sends only pointCost")
    func repriceSendsOnlyPrice() async {
        let mock = MockGameBackend()
        let vm = GiftCurationViewModel(eventId: "evt_1", service: mock)

        await vm.setPrice(150, for: .fixture(id: "r1"))

        #expect(mock.updatedRewards.first?.id == "r1")
        let sent = Set(mock.updatedRewards.first?.fields.keys ?? [:].keys)
        #expect(sent == ["pointCost"], "the rules deny a write that crosses tiers")
    }

    @Test("moving a gift rewrites the whole order, in the new sequence")
    func moveRewritesOrder() async {
        let mock = MockGameBackend()
        mock.rewards = [.fixture(id: "a", sortOrder: 0), .fixture(id: "b", sortOrder: 1),
                        .fixture(id: "c", sortOrder: 2)]
        let vm = GiftCurationViewModel(eventId: "evt_1", service: mock)
        vm.startListening()
        for _ in 0..<8 { await Task.yield() }

        await vm.move(from: IndexSet(integer: 2), to: 0)

        #expect(mock.rewardOrders.first == ["c", "a", "b"])
    }

    @Test("deleting a gift asks the backend to delete it")
    func deleteCallsBackend() async {
        let mock = MockGameBackend()
        let vm = GiftCurationViewModel(eventId: "evt_1", service: mock)

        await vm.delete(.fixture(id: "r7"))

        #expect(mock.deletedRewardIds == ["r7"])
    }

    @Test("an occasion with no gifts reads as empty, a refused read as failed")
    func statesAreDistinct() async {
        let empty = MockGameBackend()
        empty.rewards = []
        let emptyVM = GiftCurationViewModel(eventId: "evt_1", service: empty)
        emptyVM.startListening()
        for _ in 0..<8 { await Task.yield() }
        #expect(emptyVM.contentState == .empty)

        let refused = MockGameBackend()
        refused.listenerFailure = NSError(
            domain: "FIRFirestoreErrorDomain", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )
        let refusedVM = GiftCurationViewModel(eventId: "evt_1", service: refused)
        refusedVM.startListening()
        for _ in 0..<8 { await Task.yield() }
        guard case .failed = refusedVM.contentState else {
            Issue.record("expected .failed")
            return
        }
    }
}
```

- [ ] **Step 2: Write the view model**

Create `BirthdayQuest/BirthdayQuest/ViewModels/GiftCurationViewModel.swift`:

```swift
import Foundation
import SwiftUI
import Combine
import OSLog

/// The host's view of every gift: what it costs, where it sits, and whether it stays.
///
/// Deliberately cannot edit a gift's text. A gift is a personal message and curating the
/// economy is a different job from rewriting what somebody wrote — `firestore.rules` enforces
/// that, so a stray content key here is a permission-denied rather than a style nit. The
/// host's moderation lever is `delete`.
@MainActor
final class GiftCurationViewModel: ObservableObject {

    @Published private(set) var gifts: [Reward] = []
    @Published private(set) var contentState: ContentState = .loading
    @Published var giftToDelete: Reward?
    @Published var actionResult: AdminActionResult?
    @Published var isPerformingAction = false

    private let service: GameBackend
    private let eventId: String
    private let listenerKey: String
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "GiftCuration")

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
        self.listenerKey = ListenerKey.authoringRewards(eventId)
    }

    /// The total a celebrant would have to earn to unlock everything. The design intent is
    /// that challenges cannot quite cover it, so the host needs to see it while pricing.
    var totalCost: Int { gifts.reduce(0) { $0 + $1.pointCost } }

    func startListening() {
        service.listenToRewards(eventId: eventId, listenerKey: listenerKey) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let gifts):
                    self.gifts = gifts.sorted { $0.sortOrder < $1.sortOrder }
                    self.contentState = gifts.isEmpty ? .empty : .ready
                case .failure(let error):
                    self.logger.error("Curation listener: \(error.localizedDescription)")
                    self.gifts = []
                    self.contentState = .failed("Couldn't load this occasion's gifts.")
                }
            }
        }
    }

    func stopListening() {
        service.removeListener(forKey: listenerKey)
    }

    func setPrice(_ pointCost: Int, for gift: Reward) async {
        guard let giftId = gift.id else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            // pointCost alone. sortOrder is the same tier but a different action, and the
            // content keys are a different tier entirely — the rules reject a mixed write.
            try await service.updateReward(
                eventId: eventId, rewardId: giftId, fields: ["pointCost": pointCost]
            )
            BQDesign.Haptics.selection()
        } catch {
            logger.error("Repricing a gift failed: \(error.localizedDescription)")
            actionResult = AdminActionResult(
                message: "Couldn't change that price. \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
    }

    /// Applies the move locally first so the row lands where the finger left it, then writes
    /// the whole sequence. The listener will re-sort to the same order a moment later.
    func move(from source: IndexSet, to destination: Int) async {
        var reordered = gifts
        reordered.move(fromOffsets: source, toOffset: destination)
        gifts = reordered

        let ids = reordered.compactMap(\.id)
        do {
            try await service.setRewardOrder(eventId: eventId, orderedRewardIds: ids)
        } catch {
            logger.error("Reordering gifts failed: \(error.localizedDescription)")
            actionResult = AdminActionResult(
                message: "Couldn't save the new order. \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
    }

    func delete(_ gift: Reward) async {
        guard let giftId = gift.id else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await service.deleteReward(eventId: eventId, rewardId: giftId)
            actionResult = AdminActionResult(
                message: "Deleted \(gift.fromName)'s gift.", isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            logger.error("Deleting a gift failed: \(error.localizedDescription)")
            actionResult = AdminActionResult(
                message: "Couldn't delete that gift. \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
    }
}
```

- [ ] **Step 3: Write the view**

Create `BirthdayQuest/BirthdayQuest/Views/Authoring/GiftCurationView.swift`:

```swift
import SwiftUI

/// The host's gift list: price, order, remove. Not edit — the words belong to whoever wrote
/// them.
///
/// Pushed from `AdminControlsView`, which owns the `NavigationStack`.
struct GiftCurationView: View {

    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: GiftCurationViewModel

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: GiftCurationViewModel(eventId: eventId))
    }

    var body: some View {
        Group {
            switch viewModel.contentState {
            case .loading:
                ProgressView().tint(BQDesign.Colors.primaryPurple)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentFailureView(message: message)
            case .empty:
                emptyState
            case .ready:
                list
            }
        }
        .background(BQDesign.Colors.background.ignoresSafeArea())
        .navigationTitle("Gifts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // EditButton is what turns .onMove's drag handles on. It also carries the
            // keyboard and Switch Control path into reordering, which a bespoke drag
            // gesture would not.
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { viewModel.giftToDelete != nil },
                set: { if !$0 { viewModel.giftToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let gift = viewModel.giftToDelete {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete(gift) }
                }
                Button("Keep it", role: .cancel) { viewModel.giftToDelete = nil }
            }
        } message: {
            Text("This can't be undone, and they'd have to write it again.")
        }
        .alert(
            viewModel.actionResult?.isError == true ? "Couldn't do that" : "Done",
            isPresented: Binding(
                get: { viewModel.actionResult != nil },
                set: { if !$0 { viewModel.actionResult = nil } }
            )
        ) {
            Button("OK") { viewModel.actionResult = nil }
        } message: {
            Text(viewModel.actionResult?.message ?? "")
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
    }

    private var deleteTitle: String {
        if let gift = viewModel.giftToDelete {
            return "Delete \(gift.fromName)'s gift?"
        }
        return "Delete this gift?"
    }

    private var emptyState: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            Text("No gifts yet")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundStyle(BQDesign.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("""
                Gifts come from your guests — each of them can write one. Share the \
                contributor link and they'll appear here for you to price.
                """)
                .font(BQDesign.Typography.body)
                .foregroundStyle(BQDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(BQDesign.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            Section {
                ForEach(viewModel.gifts) { gift in
                    row(gift)
                        .listRowBackground(BQDesign.Colors.cardBackground)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.giftToDelete = gift
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onMove { source, destination in
                    Task { await viewModel.move(from: source, to: destination) }
                }
            } footer: {
                Text("Everything costs \(viewModel.totalCost) points in total.")
                    .font(BQDesign.Typography.captionSmall)
                    .monospacedDigit()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ gift: Reward) -> some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
            Text(gift.title)
                .font(BQDesign.Typography.cardTitle)
                .foregroundStyle(BQDesign.Colors.textPrimary)

            Text("from \(gift.fromName)")
                .font(BQDesign.Typography.captionSmall)
                .foregroundStyle(BQDesign.Colors.textSecondary)

            Stepper(
                value: Binding(
                    get: { gift.pointCost },
                    set: { newValue in Task { await viewModel.setPrice(newValue, for: gift) } }
                ),
                in: 0...2000,
                step: 10
            ) {
                HStack {
                    Text("Costs").font(BQDesign.Typography.caption)
                    Spacer()
                    Text("\(gift.pointCost)")
                        .font(BQDesign.Typography.bodyBold)
                        .foregroundStyle(BQDesign.Colors.goldText)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("Cost of \(gift.fromName)'s gift")
            .accessibilityValue("\(gift.pointCost) points")
        }
        .padding(.vertical, BQDesign.Spacing.xs)
    }
}
```

- [ ] **Step 4: Restore the host-panel link if Task 9 stubbed it**

- [ ] **Step 5: Run, lint, commit**

```bash
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests test > /tmp/t12.log 2>&1; echo "exit=$?" >> /tmp/t12.log
/usr/bin/grep -c 'TEST SUCCEEDED' /tmp/t12.log
cd .. && swiftlint --strict
git add BirthdayQuest/BirthdayQuest/ViewModels/GiftCurationViewModel.swift \
        BirthdayQuest/BirthdayQuest/Views/Authoring/GiftCurationView.swift \
        BirthdayQuest/BirthdayQuest/Views/Profile/AdminControlsView.swift \
        BirthdayQuest/BirthdayQuestTests/AuthoringTests.swift
git commit -m "Let the host price and order the gifts

Price, order and remove - not edit. A gift is a personal message and curating
the economy is a different job from rewriting what somebody wrote; the rules
enforce that split, so a stray content key here is a permission-denied.

Reorder is List + .onMove, which carries VoiceOver's Reorder action and Switch
Control for free. WCAG 2.5.7 wants a non-drag path for every drag, and a
hand-rolled gesture is the version that ships without one.

The footer shows the running total, because the design intent is that
challenges cannot quite cover it and the host cannot aim at a number they
can't see."
```

---

## Task 13: Verify both tiers and reconcile the docs

**Files:**
- Modify: `CLAUDE.md`, `README.md`

- [ ] **Step 1: Run both tiers clean, from a clean tree**

```bash
cd /Users/mitsheth/dev/BirthdayQuest
/usr/bin/git status --porcelain     # must be empty

cd firebase-tests && npm test > /tmp/final-rules.log 2>&1; echo "exit=$?" >> /tmp/final-rules.log
/usr/bin/tail -20 /tmp/final-rules.log
```

Then the Swift tier, **backgrounded** — a cold run has exceeded a 10-minute tool ceiling at 576s:

```bash
cd /Users/mitsheth/dev/BirthdayQuest/BirthdayQuest && \
  (xcodebuild -scheme BirthdayQuest \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -only-testing:BirthdayQuestTests test > /tmp/final-swift.log 2>&1; \
   echo "exit=$?" >> /tmp/final-swift.log) &
```

Read the verdict from the log, never from the task status:

```bash
/usr/bin/grep -c 'TEST SUCCEEDED' /tmp/final-swift.log
/usr/bin/tail -3 /tmp/final-swift.log
```

- [ ] **Step 2: Lint, from the repo root**

```bash
swiftlint --strict
```

- [ ] **Step 3: Clean up after the run**

Mit raised stale simulators unprompted; check all three:

```bash
/usr/bin/xcrun simctl list devices booted
/usr/bin/xcrun simctl list devices | /usr/bin/grep -i 'Clone .* of iPhone' || echo "no test clones"
/bin/ps aux | /usr/bin/grep '[x]codebuild -scheme BirthdayQuest' || echo "no stray builds"
```

Delete any leftover clones. Never `pkill -f xcodebuild` — it also matches Mit's XcodeBuildMCP server.

- [ ] **Step 4: Derive the counts, do not invent them**

```bash
/usr/bin/grep -c '^\s*it(' firebase-tests/firestore.rules.test.js
/usr/bin/grep -c '^\s*it(' firebase-tests/storage.rules.test.js
/usr/bin/grep -o 'Executed [0-9]* test' /tmp/final-swift.log | /usr/bin/tail -1
```

Note the Swift "passed on" line runs higher than the number of distinct tests, because parameterized cases report once per argument. Count unique test names if you need to compare against a previous figure.

- [ ] **Step 5: Update `CLAUDE.md`**

Four edits, each replacing something this subsystem made false:

1. **Known Gaps** — `**A new occasion is empty.**` is no longer true. Replace with a note that the host authors challenges and contributors author text gifts, that media gifts still need subsystem #3, and that `totalChallenges`/`totalRewards` now move with the content.
2. **Collections table** — add the field-scoped rules to the `challenges` and `rewards` rows: gameplay fields member-writable, content fields host-or-author, `pointCost`/`sortOrder` host-only, and the author fields immutable.
3. **Key Firestore Patterns** — add one bullet: *content and gameplay writes must not be mixed in one `updateData`; the rules reject a write whose changed keys span two tiers.* This is the single easiest thing to break by accident and it fails only at runtime.
4. **Direction** — subsystem #2 slice 1 done; name what is still out (media gifts, templates, participant removal, occasion settings).

Do **not** write a commit count or a test count into `CLAUDE.md`. State the command (R76).

- [ ] **Step 6: Fix `README.md`, including two staleness bugs this task inherited**

- The **Customization** section currently instructs hosts to hand-write challenge and reward documents into Firestore, field by field. Replace with the in-app path; keep the Firestore route only as a note for bulk setup, and warn that a hand-written document does **not** move the counters.
- `**No host authoring yet.**` in Known Limitations — delete.
- Two pre-existing staleness bugs, unrelated to this work but wrong in the same file: `**`birthdayquest://` isn't registered.**` (fixed as Critical 3) and `**Near-zero accessibility.**` (fixed by `ba0cd1a`). Correct both.

- [ ] **Step 7: Final commit**

```bash
git add CLAUDE.md README.md
git commit -m "Reconcile the guides with content authoring

CLAUDE.md's 'a new occasion is empty' and README's 'no host authoring yet' are
both now false. The collections table gains the field-scoped rules, and a new
pattern note: a single updateData must not mix content and gameplay keys,
because the rules reject a write whose changed keys span two tiers and it
fails only at runtime.

Also corrects two README claims that were already stale before this branch -
birthdayquest:// is registered, and accessibility is no longer near-zero."
```

---

## Verification Summary

| Tier | Command | When |
|---|---|---|
| Emulator rules | `cd firebase-tests && npm test` | Tasks 2, 3, 13 — mandatory, rules changed |
| Swift unit | `cd BirthdayQuest && xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BirthdayQuestTests test` | Every Swift task |
| Lint | `swiftlint --strict` from the repo root | Tasks 8-13 |
| Mutation | Delete a clause, confirm a named test fails, revert | Tasks 2, 3 |
| **Attended, not automatable** | `xcrun simctl ui booted content_size accessibility-extra-extra-extra-large` | Offer to Mit before merge |

That last row is not optional theatre. These are the densest forms in the app, there are no snapshot tests, and the unit suite structurally cannot see clipping or overlap. It needs a live Firebase project because the app cannot get past `.launching` without the Anonymous provider, so it is Mit's to run. **Do not report the accessibility of these screens as verified.**

## What this plan does not cover

- **Media gifts** (video / audio / image). Needs a `storage.rules` change — a host cannot currently delete media they uploaded — and inherits the download-URL leak. Subsystem #3.
- **Occasion-type templates.** Subsystem #4.
- **Challenge reordering.** `Challenge` has no `sortOrder`; ordering by `pointValue` already reads correctly.
- **Participant removal UI** and **occasion settings** beyond `isOpen`.
- **The counter increment itself is untested, and cannot be tested by either tier.** It is batched
  inside `FirestoreService`, which every Swift test replaces with `MockGameBackend`; the emulator
  suite tests rules, not the Swift client. So Task 5 and Task 6 prove the view model asked for a
  create, not that the batch carried an increment. Same structural gap as R30, same missing fix: a
  Swift-to-emulator harness. **Do not add a mock that fakes a counter** � it would test the mock.
- **The three atomic transactions** remain untested (R30). Unchanged by this work.
- **`fetchMyOccasions`' skip-on-failure** still has no test and still cannot get one (R9).
