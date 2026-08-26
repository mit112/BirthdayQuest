# Transaction integration tests

Emulator-backed tests that prove the **server-side transaction logic** in `FirestoreService`
against a real Firestore — the one critical path `MockGameBackend` cannot simulate:

- `unlockRewardAtomically` — the **balance re-check** refuses a spend when the in-transaction
  balance is below `pointCost`, and writes nothing.
- `completeChallengeAtomically` — the **idempotency guard** awards points at most once even when
  the completion runs twice.

The Swift tests live in `BirthdayQuest/BirthdayQuestTests/TransactionIntegrationTests.swift`. Each
is gated on `EmulatorProbe.isReachable` (a socket probe to `localhost:8080`), so the normal unit
pass (`-only-testing:BirthdayQuestTests`, no emulator) **skips** them — they only execute when an
emulator is up.

This directory holds a dedicated emulator config with **open rules** (`firestore.rules`). That is
deliberate: the invariants under test are rules-independent, and authorization is covered by the
strict production ruleset and the 183-test suite in `../firebase-tests`. These rules are never
deployed.

## Run locally

From the repo root, with a booted iPhone simulator:

```bash
firebase --config integration-tests/firebase.json emulators:exec \
  --only firestore --project birthdayquest-test \
  'xcodebuild -project BirthdayQuest/BirthdayQuest.xcodeproj -scheme BirthdayQuest \
     -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
     -only-testing:BirthdayQuestTests/TransactionIntegrationTests test'
```

`emulators:exec` boots the Firestore emulator, runs the command, and shuts down cleanly.
