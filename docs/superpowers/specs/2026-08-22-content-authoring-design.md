# Content authoring — design

**Date:** 2026-08-22
**Scope:** Subsystem #2 of 4, slice 1
**Status:** draft, pending review
**Prerequisite:** subsystem #1 (event scoping and identity), merged to `main`

## Why this exists

`createOccasion` writes `totalChallenges: 0, totalRewards: 0` and seeds nothing. `DataSeeder` is
deleted. So **a newly created occasion is completely empty**, and the only in-app authoring path is
a contributor writing one secret dare. Everything else — every challenge, every gift, every point
cost — has to be hand-written into Firestore. The README's Customization section is a list of
Firestore field names, presented to the user as setup instructions.

Two consequences that are worse than "the app is inconvenient":

1. **The final celebration can never fire.** `checkFinalBadge` requires
   `rewardsUnlocked >= totalRewards && totalRewards > 0`. `totalRewards` is written as `0` and
   incremented nowhere in the codebase. Following the documented setup path, the occasion is
   unfinishable.
2. **The point economy has no author.** The design intent — challenges cannot quite cover the
   rewards, and secret dares close the gap — is unexpressible when nobody can set a point value.

## A naming correction

The prior documents call this subsystem "host authoring". That is now the wrong name. The host
authors challenges; **contributors author their own gifts**; the host curates the economy. This
document calls it **content authoring**.

## In scope

1. **Host authors challenges** — create, edit, delete. Reached from the existing host panel.
2. **Contributors author one text gift each** — title, teaser, letter body.
3. **Host curates gifts** — sets `pointCost` and `sortOrder`, and may delete a gift.
4. **The counters are maintained** — `totalChallenges` / `totalRewards` move with the content.
5. **Field-scoped rules hardening** on `challenges` and `rewards`, with emulator coverage.

## Out of scope, deliberately

- **Media gifts** (video / audio / image). Requires a `storage.rules` change — a host cannot
  currently delete media they uploaded (`storage.rules:53-61` gates upload on `isMember` but delete
  on `isCelebrant`, and overwrite is denied to everyone) — and knowingly inherits the download-URL
  leak that subsystem #3 exists to close. **Text gifts need no Storage object at all**, which is
  exactly why they are the right first slice.
- **Occasion-type templates.** Assigned to subsystem #4 and staying there. A template is bulk-create
  on top of the authoring model; designing it first means designing it twice.
- **Challenge reordering.** `Challenge` has no `sortOrder` field — challenges are ordered by
  `pointValue` (`FirestoreService.swift:513`), which is a meaningful easy-to-hard order. Drag-reorder
  would mean a new wire field, a new rules clause and a new parse path, to replace an ordering that
  already reads correctly. Rewards keep reordering; they already have `sortOrder`.
- **Participant removal UI** and **occasion settings editing** beyond the existing `isOpen` toggle.
- **Host-authored secret challenges.** No existing ruling covers secret-challenge authoring
  semantics, and the mechanic is a contributor's.

## Decisions, and what they cost if wrong

D1, the slice boundary, the rules-hardening approach and the templates deferral were **confirmed by
Mit**. **D2, D3 and D5 were not** — they were asked and the question timed out, so they are taken on
my judgment and are the three most likely things in this document to want flipping. Each records its
reasoning so the reversal is cheap.

### D1 — Contributors author their own gifts; the host prices them

The data model already says a reward is a gift from a person (`fromUserId`, `fromName`, "Unlocked
Sam's gift"), and `storage.rules:46` comments *"Reward media. Written by contributors."* But
`firestore.rules:186` makes reward `create` host-only. Today a contributor can upload gift media and
cannot create the document that points at it. That contradiction is resolved in the model's
favour.

The split: a contributor writes the gift's **content**; the host sets its **price and position**.
Contributors do not price their own gifts, so the economy stays in one pair of hands and the
"challenges cannot quite cover the rewards" intent remains achievable.

**Cost if wrong:** if gifts should have been host-authored, the rules change is reverted and the
contributor editor is deleted. The host curation UI survives either way.

### D2 — One gift per contributor

Mirrors the secret dare exactly: same one-per-person shape, same `first { … $0.fromUserId == uid }`
recovery on a shared listener, same mental model. It also makes the economy predictable — N
contributors means at most N gifts, which is what lets a host price them sensibly.

**Cost if wrong:** generous contributors are capped at one gift. Relaxing "one" to "many" later is
additive; tightening "many" to "one" is not.

### D3 — The host sets price and order, and does not rewrite the letter

A gift is a personal message. Curating the economy is a different job from editing what somebody
wrote. This is enforceable exactly: content fields gated to the author, `pointCost` / `sortOrder`
gated to the host.

**This is curation, not privacy.** Firestore rules are document-granular — the host can still *read*
the gift, as can every member. Nothing here hides a letter from anyone; it only decides who may
change it. The host's moderation lever is `delete`, which is already host-only.

**Cost if wrong:** a host who needs to fix a typo in someone's gift has to ask them, or delete it.

### D4 — Authoring screens hang off the host panel, not inside it

R60 rules that there is one host panel — `AdminControlsView`, reached from Profile — and forbids a
second. It does not require one enormous file. `AdminControlsView` is already the largest view in the
app at 769 lines, with eight cards. Authoring adds a ninth row that **pushes a dedicated screen**.
One entry point, focused files beneath it.

**Cost if wrong:** authoring is one tap deeper than a card would be.

### D5 — The gift editor is a fourth contributor tab, not a merged "contribution" hub

The conceptually tidier option is one screen holding both of a contributor's contributions. Rejected
on evidence: `SecretChallengeHomeView` is a deliberate full-bleed dark surface
(`secretGradient.ignoresSafeArea()`, `secretAccent` throughout, documented as "Secret agent themed").
A warm gift letter inside it forces one of the two themes to lose. Worse, R72 records that
`textSecondary` darkened to `#6B6880` drops to **3.18:1 on the dark secret surfaces**, harmless today
*only because no dark-themed view uses the token* — adding prose content to that screen is precisely
what would make that latent failure real.

So: `Secret Dare / Gift / Timeline / Profile`. The dark screen is not touched.

**Cost if wrong:** four tabs in a small app, and a contributor's two contributions sit side by side
without their relationship being drawn.

### D6 — Counters are incremented inside the same batch as the content write

Every create and delete batches a `FieldValue.increment(±1)` on `state/main`. Not a
recompute-from-count: contributors add gifts concurrently, and increment is the only
concurrency-correct option. The increment lives inside `FirestoreService`, not in a view model, so no
caller can forget it.

`state/main` update is already `isMember`-writable (R39, parked), so this needs no rules change.

**Cost if wrong:** a failed batch leaves the counter behind by one and the final badge fires early or
late. Bounded, and visible in the host panel's game-state card.

### D7 — `createSecretChallenge` / `updateSecretChallenge` are renamed, not duplicated

Neither method ever enforced secrecy — `createSecretChallenge` is one line of
`addDocument(from: challenge)`, and the `isSecret: true` comes from the caller's struct. Adding
`createChallenge` alongside them would be two methods doing one thing. They become
`createChallenge` / `updateChallenge`, and the secret flow keeps passing `isSecret: true`.

**Cost if wrong:** nothing; it is a rename with a compiler-enforced call-site update.

## Data model

**No new fields, and no new models.** Every field authoring needs already exists on `Challenge` and
`Reward`. This is the main reason the slice is small.

Two facts constrain how the code is written, both already paid for in blood:

- **Never hand-write `init(from:)` on either model.** Both carry `@DocumentID`; a custom decoder
  suppresses the memberwise init *and* silently nulls every loaded id (R7, R49).
- **Model tests decode through Firestore's decoder, never `JSONDecoder`**, which throws `keyNotFound`
  on `"id"` regardless of the JSON (R49, R51).

One behaviour needs an empirical check before the rules are written: whether Firestore's encoder
**omits** nil optionals or writes them as null. `Challenge` has six nil optionals at create time
(`completedAt`, `proofUrl`, `proofType`, `proofText`, `optionBTitle`, `optionBDescription`). If they
arrive as explicit nulls, a `hasOnly` create rule that does not list them will reject every create.
The check is one emulator round-trip; do it first, do not reason about it.

## Security rules

This is the substantial half of the work, and it is new ground: **no existing ruling covers the
`challenges` collection's rule shape at all.**

### The problem being fixed

`challenges` and `rewards` have **zero** field validation today (`firestore.rules:177-189`) — no
`hasOnly`, no type checks, no length limits, no immutable fields. Every other collection in the file
has validation. Concretely: any member can rewrite any challenge's `pointValue`, any reward's
`pointCost`, or any gift's text. Building an authoring UI on that is building a UI for a door with
no lock.

### The split

Each collection's `update` divides into a **gameplay** half and a **content** half, using the
`diff().affectedKeys().hasOnly()` idiom the celebrant-code rule already uses
(`firestore.rules:117-124`).

**challenges**

| Half | Fields | Who |
|---|---|---|
| gameplay | `isCompleted`, `completedAt`, `proofUrl`, `proofType`, `proofText` | any member |
| content | `title`, `description`, `pointValue`, `difficulty`, `category`, `illustrationAsset`, `isDelivered`, `optionBTitle`, `optionBDescription` | host, or the challenge's own author |
| immutable | `isSecret`, `createdByUserId`, `createdAt` | nobody |

**rewards**

| Half | Fields | Who |
|---|---|---|
| gameplay | `isUnlocked`, `unlockedAt`, `fetchedBy` | any member |
| curation | `pointCost`, `sortOrder` | host only |
| content | `title`, `teaser`, `contentText`, `contentType`, `contentUrl`, `contentUrls`, `badgeIllustration` | host, or the gift's own author |
| immutable | `fromUserId`, `fromName`, `createdAt` | nobody |

The gameplay halves are **verbatim** the field sets the three existing transactions write, and both
halves stay open to **any member**, not the celebrant. That is not laziness: the two emulator tests
that exercise `update` on these collections (`lets a member complete a challenge`,
`lets a member unlock a reward`) are both performed by a plain contributor. Narrowing to celebrant
flips both. R39's parked trust model is inherited unchanged, not relitigated.

`fetchedBy` is placed in the gameplay half although nothing writes it yet, so subsystem #3's media
purge does not need a second rules change.

### Create

Create is where the split is actually secured. Author-scoping is worthless if a member can claim
authorship, so:

- **challenges**: `create` requires `createdByUserId == request.auth.uid`. A member may create only
  with `isSecret == true` (the dare flow); the host may create either.
- **rewards**: `create` requires `fromUserId == request.auth.uid` for a member; the host may create
  a reward for anyone.
- Both: required-field presence, type checks, and length caps on the free-text fields.

**This flips one existing test.** `lets a member create a secret challenge`
(`firestore.rules.test.js:227-234`) creates `{title, description, pointValue, isSecret, isCompleted}`
with **no `createdByUserId`** — the app always writes one, the test does not. The test is updated,
and that is a correction, not a regression.

### The immutability clauses are load-bearing

`createdByUserId` and `fromUserId` are the keys every author-scoped rule reads. If either is
mutable, a member sets it to themselves and the entire content half collapses to "any member". They
are pinned exactly as `hostUid` is pinned (R37).

## Backend surface

`GameBackend` gains five methods net, all `eventId`-scoped, all routed through the validated
`eventRef` so no path is built from an unvalidated string (R63):

```
createChallenge(eventId:challenge:) -> String        // renamed from createSecretChallenge
updateChallenge(eventId:challengeId:fields:)         // renamed from updateSecretChallenge
deleteChallenge(eventId:challengeId:)                // new
createReward(eventId:reward:) -> String              // new
updateReward(eventId:rewardId:fields:)               // new
deleteReward(eventId:rewardId:)                      // new
setRewardOrder(eventId:orderedRewardIds:)            // new, one batch
```

Every one gets a `MockGameBackend` stub in the same task — `record(_:eventId:)`, then
`try throwIfNeeded()`, then a recording array. This codebase has been bitten three times by protocol
methods added without a mock (R9, R33, R59); it is not going to be a fourth.

`create*` and `delete*` internally batch the `state/main` counter increment (D6). Edits use
`updateData`, never `setData` (R42).

## UI

Three surfaces, consulted against the design knowledge base (`~/dev/design`, 305 cards) rather
than composed freehand.

**1. Challenge authoring** — a row in `AdminControlsView` pushing a list of the occasion's
non-secret challenges. Create, edit, delete.

**2. Gift authoring** — a fourth contributor tab (D5). Title, teaser, letter body.

**3. Gift curation** — inside the host panel's authoring screen: per-gift point cost, order, delete.

### Rules that change what gets built

- **Gift reorder is `List` + `.onMove`, never a hand-rolled `DragGesture`.** (Gifts only — challenge
  reordering is out of scope, see above.) `.onMove` ships VoiceOver's
  Reorder custom action and Switch Control support for free. WCAG 2.5.7 requires every drag
  interaction to have a non-drag path; rolling our own means reimplementing that by hand, and the
  version that gets shipped is the one without it.
- **Point value is a `Stepper`, not a numeric text field.** A bounded discrete range belongs in a
  control that cannot express an invalid value. The text-field version needs a numeric keyboard, a
  min/max check, and an error state — all of which the `Stepper` makes structurally unreachable.
- **Difficulty is a segmented `Picker` (3 options); category is a menu `Picker` (5).** Segmented
  starts to cramp past about four.
- **The option B pair sits behind a collapsed disclosure, default off.** It is the 2-in-1 escape
  hatch, not a field everyone should confront. Never a pre-checked toggle.
- **`illustrationAsset` is a curated SF Symbol grid, not a text field.** The field renders as an SF
  Symbol name with a `bolt.fill` fallback (`TimelineNodeView.swift:256`), and the literal the dare
  flow writes — `"secret_mission"` — is not a symbol, so **every secret dare already renders the
  fallback**. A free-text field lets a host reproduce that bug on purpose. Symbol tiles are ≥44×44pt
  regardless of glyph size, and the selected tile carries a checkmark, not just a colour fill.
- **Labels are persistent and above the field.** Placeholders are not labels. Any restyled
  `TextField` still needs an explicit `.accessibilityLabel()`.
- **The description and letter-body editors grow with content.** A fixed height clips at large
  Dynamic Type sizes, which is exactly the unverified risk (R75) these screens sit inside.
- **Point values shown in a list use `.monospacedDigit()`** so a changing total does not jitter.
- **Delete confirms and names the item** — "Delete 'Scavenger hunt'? This can't be undone" — because
  the delete is a real Firestore delete with no restore path. Confirmation *or* undo, never both;
  `AdminControlsView` already uses confirmation dialogs, so this is consistent.

### Empty states are the feature, not decoration

The empty occasion is the problem being solved, so the empty state is the host's first instruction.
Each list gets its own: a heading saying why it is empty, one sentence of context, and exactly one
action that resolves it. The challenge list and the gift list get **different copy** — they are
different content types, and one reused "Nothing here yet" is the failure mode.

It must route through `ContentState` so a failed read cannot render as a confident "no challenges
yet" (R65) — the exact defect that shipped as Critical 4.

### Two conflicts with the knowledge base, resolved explicitly

- **`ios-swiftui-observable` calls `ObservableObject` / `@StateObject` / `@EnvironmentObject` the
  legacy pattern and says not to use it in new code.** This entire app is built on it —
  `EventSession` is an `@EnvironmentObject`, every view model is an `ObservableObject`. New view
  models **follow the existing pattern.** Introducing `@Observable` for two new screens would leave
  the app with two DI models and no migration, which is worse than being consistently one version
  behind. Migrating is its own piece of work, and not this one.
- **The entire dark-mode card family is overridden.** Dark mode is deliberately pinned off
  (`.preferredColorScheme(.light)`); every colour is a fixed hex with no dark variant. Those cards
  are not gaps to close here. The adjacent, non-conflicting half still applies: colours are
  referenced by semantic name, never raw hex, so the recorded contrast audit stays valid as the UI
  grows.

### The invariants that carry over unchanged

Every type token is a semantic text style, never a fixed point size (R69). No perpetual animation
that is not gated behind `MotionLevel.allowsPerpetual` (R71) — including the reorder spring and any
empty-state entrance. `textTertiary` is not a text colour; `gold` is not a text colour on light,
`goldText` is (R72, R73). All spacing on the existing 8pt scale.

One deliberate divergence to note, so nobody "fixes" it in the wrong direction: the KB's
`anti-disabled-submit-no-feedback` says never disable a submit button, and the **new** editors follow
that — Save stays enabled, and tapping it validates and focuses the first bad field. This does **not**
apply to `JoinOccasionViewModel.canSubmit`, which requires `isResolved` because joining an unresolved
code is impossible rather than merely invalid. That gate stays. The existing dare editor's `canSave`
is not retrofitted in this slice.

### The AI-generic-look tells this UI is most at risk of

A gamified authoring screen full of points, difficulty and categories is the exact surface where
generated UI reaches for 🎯🏆⭐ as difficulty and category glyphs. **Every glyph comes from the SF
Symbol family**, one weight, no emoji. The second risk is empty-state copy — "Start your journey!"
is averaged filler; name the actual object ("No challenges yet for this occasion"). The third is a
rainbow palette: five categories is five chances to invent a hue per option. Category and difficulty
take their colour from existing functional roles, and the label carries the meaning, not the colour
(`a11y-color-not-sole`).

## Testing

**Rules — the tier that carries the enforcement burden, since there are no Cloud Functions.**
Positive `assertSucceeds` coverage is mandatory, not optional: a wrong path yields permission-denied
via the catch-all, so an all-`assertFails` block passes just as happily when the rule is broken
(R45, R47). For every field-scope clause, both directions:

- the author edits their own content field — succeeds
- a non-author, non-host member edits the same field — fails
- the host edits `pointCost` — succeeds; a contributor edits `pointCost` — fails
- a member writes a gameplay field — succeeds (pins the two existing tests' contract)
- a create with someone else's `createdByUserId` / `fromUserId` — fails
- an update touching an immutable field — fails

**Then mutation-test it.** Delete one clause, confirm a named test fails, revert (R74). A truth-table
test passes just as happily against an implementation that never reads one of its inputs — that is
why the original `GameState` wire-parser bug was invisible, and why R74 exists. A rules suite nobody
has mutated is a suite nobody has tested.

**Swift.** View-model tests through `MockGameBackend` for each new method, and — the assertion that
actually matters — that create and delete move the counter. Model round-trips decode through
Firestore's decoder (R49, R51).

Both tiers must be green, and the rules suite must be re-run because rules change:

```
cd BirthdayQuest && xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests test      # never a bare `test` (R48)
cd firebase-tests && npm test
swiftlint --strict                            # from the repo root
```

## Risks

- **The counter can still drift.** A batch that fails after a partial commit is not possible
  (batches are atomic), but a create that succeeds while the client is offline and never syncs will.
  The drift is visible in the host panel's game-state card and self-corrects on the next authoring
  action only if a reconciliation is added — which this slice does not add. Accepted.
- **Field-scoped rules are long and easy to get subtly wrong.** The mitigation is the mutation test,
  not review.
- **Reflow at large accessibility sizes is unverified across the whole app** (R75), and these are
  new form screens with the densest text in the app. They should be part of the first attended
  AX-size pass, not after it.
- **No test can prove any of this works against a live project.** The three manual steps
  (Sign in with Apple capability, Anonymous + Apple providers, `tools/export_media.sh` before
  deploy) still gate everything, and a fully green suite proves nothing about them.

## What this unblocks

An occasion that a host can fill, a contributor can contribute to, and a celebrant can finish.
After this: subsystem #3 (media pipeline — which turns the text-only gift into any gift), then #4
(templates, moderation, compliance, the rename).
