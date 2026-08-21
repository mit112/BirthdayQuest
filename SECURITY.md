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

`events/{eventId}/state/main` updates and `rewards.isUnlocked` are gated on occasion membership
only. Balance mutations go through transactions with server-side re-checks and idempotency guards,
so points cannot be *double-spent* — but a member who writes `state/main` directly can set the
balance to anything and unlock every reward.

This is bounded to occasions the user already belongs to; there is no cross-occasion exposure. It is
the cost of a no-Functions design, and it means **you should only invite people you would trust with
the surprise.** Relatedly, a participant can rewrite their own `usedCode` field after joining, so
never build a "revoke this code and remove whoever used it" feature on top of that value.

### Reward media URLs are public links, even though Storage rules gate the objects

`storage.rules` restricts object reads and writes to members of the owning occasion, denies
overwrites outright, and permits deletion only by the celebrant. That protects the *objects*.

It does not protect the *links*. The app stores long-lived Firebase **download URLs** (the
`?alt=media&token=…` form, from `StorageReference.downloadURL()`) in Firestore, and those URLs are
designed to bypass Storage rules — anyone holding one can fetch the media with no credential,
indefinitely, whether or not they belong to the occasion.

**Do not put anything genuinely private behind a reward.** Assume every video, audio note, and photo
is publicly reachable by anyone who ever sees its URL.

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
