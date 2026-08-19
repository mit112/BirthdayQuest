# Security Policy

## Supported versions

`main` only. This is a personal project shared as a template; there are no released versions.

## Reporting a vulnerability

Please open a [private security advisory](https://github.com/mit112/BirthdayQuest/security/advisories/new)
rather than a public issue. I'll aim to respond within a week.

## Known limitations — read this before you deploy

These are design characteristics of this app, not bugs. If you fork it and point it at your own
Firebase project, you are accepting all of them.

### There is no user authentication

The app does not authenticate anyone. Identity is a *device-locked character claim*: the app writes
a random `deviceId` into `UserDefaults` and into the user's Firestore document. There is no
`request.auth`, which means:

* Security rules cannot distinguish your five players from anyone else holding your Firebase
  config (which ships inside every copy of the app binary).
* Clearing app data, or reinstalling, releases a claim.
* `firestore.rules` in this repo restricts *shape* — no deletes, no new collections, append-only
  timeline — but it cannot restrict *who* writes. Treat the database as writable by anyone who
  obtains your config.

If you need real isolation, add Firebase Anonymous Auth and gate every rule on
`request.auth != null`, keyed to the claiming uid.

### Reward media URLs are public links

Reward content is served from long-lived, unauthenticated Firebase Storage download URLs stored in
Firestore. Anyone who obtains a URL can view that media without any credential, indefinitely.

**Do not put anything genuinely private behind a reward.** Assume every video, audio note, and
photo you upload is publicly reachable by link.

### There is a hardcoded override PIN

`CharacterSelectViewModel.overridePin` is `"1234"`. It lets anyone take over an
already-claimed character. It exists so a party organizer can fix a mis-tap on the day. Change it,
or gate it behind `#if DEBUG`, before deploying anywhere you care about.

### The points economy is client-visible

Point values and reward costs are seeded into Firestore and readable by clients. Balance mutations
use transactions with server-side re-checks and idempotency guards, so the balance cannot be
double-spent — but a client that writes `game_state` directly can set it to anything.
