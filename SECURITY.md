# Security Policy

## Supported versions

`main` only. This is a personal project shared as a template; there are no released versions.

## Reporting a vulnerability

Please open a [private security advisory](https://github.com/mit112/BirthdayQuest/security/advisories/new)
rather than a public issue. I'll aim to respond within a week.

## Known limitations — read this before you deploy

These are design characteristics of this app, not bugs. If you fork it and point it at your own
Firebase project, you are accepting all of them.

### Identity is an anonymous account by default, and losing it is unrecoverable

Every user is a Firebase **anonymous** uid, created on first launch. `request.auth.uid` gates every
security rule, and participants and memberships are keyed by that uid
(`events/{eventId}/participants/{uid}`, `memberships/{uid}/events/{eventId}`).

An anonymous account lives and dies with the app install. Deleting the app or replacing the device
loses the uid, and with it every occasion the user belongs to and any host role they held. Because
`hostUid` is immutable in the rules, **there is no host-transfer path** — an occasion whose host
loses their account cannot be administered by anyone again.

Sign in with Apple upgrades the anonymous account **in place** via `linkWithCredential`, preserving
the uid and all existing data, which is the only recovery path. It requires two setup steps that
are not in this repository: the **Sign in with Apple** capability on the Xcode target, and the
**Apple** provider enabled in the Firebase console. Until both are done the upgrade UI is present
but will fail at runtime, and every account stays disposable.

### Security rules carry the entire enforcement burden

There are no Cloud Functions. `firestore.rules` and `storage.rules` are the only thing standing
between a client and the data, so a rules mistake is a data breach rather than a bug.

The only mitigation is the emulator test suite in `firebase-tests/`. **That suite is not optional** —
run `npm test` there after any rules change, and treat a red run as a release blocker.

Isolation between occasions is by **path**, not by query discipline: all content lives under
`events/{eventId}` subcollections, so a client cannot express a query that reaches another
occasion, because the path does not exist for them.

### Any member can rewrite their own occasion's point balance and unlock flags

**The risk.** A member of an occasion can cheat the game: grant themselves points they didn't earn,
or unlock a gift without earning it. `firestore.rules` has, on `events/{eventId}/state/main`:

```
allow update: if isMember(eventId);
```

with no field scoping — so any member can write `currentPoints` (or any other field on that
document) to whatever they like. On `events/{eventId}/rewards/{id}`, the gameplay tier of `update`
is:

```
affects(['isUnlocked', 'unlockedAt', 'fetchedBy'])
```

open to any member regardless of who authored the reward, and `create` does not constrain those two
fields either — so a member authoring their own gift can create it already `isUnlocked: true`. The
normal unlock path (`unlockRewardAtomically`) goes through a transaction with a server-side balance
re-check, so points cannot be *double-spent* through the app's own UI — but nothing stops a member
from bypassing the app and writing these documents directly with the Firestore SDK or console.

**What this is not.** It is not a cross-tenant hole. Isolation between occasions is by **path**: all
occasion content lives under `events/{eventId}` subcollections, and no rule or query can reach a
different `eventId`'s data. It also doesn't expose the invite codes that authorize joining an
occasion in the first place — those live at `events/{id}/private/codes`, readable only by
`isHost(eventId)`, entirely separate from the gameplay-write gap above. A member who cheats their own
occasion's score gains nothing against any other occasion.

**Why it's this way.** This project deliberately ships with **no Cloud Functions** — zero server
ops, and it stays on Firebase's free Spark tier for Firestore. Security rules can restrict *who* may
write a document, but they cannot validate that a point balance transitions legitimately (e.g. "only
decrement by exactly `pointCost`, only if it was that high a moment ago") without a trusted
intermediary re-deriving the correct value — which is exactly what a Cloud Function would be for.
Rules alone cannot close this gap; the fix is server-side transaction validation, not a stricter
rule.

**The trade-off.** This is a documented design choice for a small, invite-only app among people who
already trust each other with the surprise — not an unpatched vulnerability. **You should only
invite people you would trust with the outcome of the game.**
Relatedly, a participant can rewrite their own `usedCode` field after joining, so never build a
"revoke this code and remove whoever used it" feature on top of that value.

### Reward media and proof photos are authenticated, not public links

`storage.rules` restricts object reads and writes to members of the owning occasion
(`allow read: if isMember(eventId)`), denies overwrites outright, and permits deletion only by the
celebrant (or the host, for reward media during curation). Firestore stores the Storage **object
path**, never a tokened download URL — `uploadRewardMedia` and `uploadProofData` both return the
path from `putDataAsync`, and the client (`MediaStore` for gifts, `ProofImageView` for proof photos)
fetches the bytes through an authenticated `Storage.storage().reference(withPath:)` call, which is
subject to the rule above. A revoked member's Storage read is denied along with their Firestore read.

This closes what was previously true of this project — the app used to persist Firebase's
`?alt=media&token=…` download URLs, which bypass Storage rules by design. That has been replaced
end-to-end; there is no remaining path in the app that stores or serves one of those tokened URLs
for reward or proof media.

### Invite codes are bearer tokens

Joining an occasion means presenting a code that matches `contributorCode` or `celebrantCode` on the
event document. Only the host can write those fields, so only the host can issue a code — but the
code itself is the entire credential, and invite links carry the eventId in plaintext. Anyone who
obtains a contributor link can join as a contributor.

The `inviteCodes` collection permits `get` but denies `list`, so a code you already hold resolves
while the collection cannot be enumerated. The celebrant code is single-use: the celebrant clears it
on claim. That clear is necessarily a second write after the join commits, so a crash in between
leaves the code briefly claimable — a second holder of a privately shared celebrant link could take
the role. It shows up in the host's roster.
