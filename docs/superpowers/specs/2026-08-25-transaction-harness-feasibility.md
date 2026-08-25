# Transaction Test Harness — Feasibility Finding (DEFERRED, with recipe)

**Date:** 2026-08-25  **Status:** assessed, deferred to an attended session (evidence below).

## The gap
`FirestoreService.unlockRewardAtomically`, `completeChallengeAtomically`, and
`adminForceUnlockReward` run Firestore **transactions** with a server-side balance re-check and an
idempotency guard. They are the one critical path with no test: `MockGameBackend` cannot simulate a
real transaction, so proving "spend is refused when the balance re-check fails" and "a double-unlock
deducts once" needs the **real** `FirestoreService` against a **real** Firestore — i.e. the Firebase
emulator.

## Feasibility: YES in principle (verified)
- `firebase` CLI is installed (`/opt/homebrew/bin/firebase`); `firebase.json` runs the Firestore
  emulator on :8080.
- The JS rules suite already orchestrates it: `firebase emulators:exec --only firestore,storage
  --project birthdayquest-test '<cmd>'`. A Swift integration run would wrap xcodebuild the same way.
- Programmatic Firebase config against the emulator needs **no** GoogleService-Info.plist (the
  emulator ignores credentials): `FirebaseApp.configure(options:)` with dummy `FirebaseOptions`
  (projectID `birthdayquest-test`), then `Firestore.firestore().useEmulator(withHost:"localhost",
  port:8080)` + settings with SSL disabled and persistence off.

## Why it is DEFERRED (the real blocker — not a hand-wave)
1. **`FirebaseApp.configure()` is called unconditionally at app launch** (`BirthdayQuestApp.swift:12`)
   and the test target **hosts in the full app** (`TEST_HOST = …/BirthdayQuest.app/…/BirthdayQuest`).
   So the host app's `@main` runs a bare `configure()` at test launch. How the existing plist-less CI
   unit run survives that is not explained by static inspection (see
   [[project_ci_needs_no_firebase_secret]]) — the FirebaseApp singleton × test-host-launch ×
   no-plist interaction has to be understood and worked with before a second (emulator) configuration
   can be introduced. This is exactly the fragility that makes the app "die at launch on a bare
   `FirebaseApp.configure()`" without a plist.
2. **New test category + CI orchestration.** These integration tests must NOT run in the standard
   `-only-testing:BirthdayQuestTests` pass (CI has no emulator → they would hang/fail). Options: a
   new test target (pbxproj surgery the folder-synced project avoids), or keep them in the existing
   target but gate each with `@Test(.enabled(if: EmulatorProbe.isReachable))` (a fast socket probe to
   :8080) so they self-skip without the emulator, and run them via `firebase emulators:exec 'xcodebuild
   … test'`. The gating approach avoids a new target but still adds a CI step.

Both points are iterative, SDK-lifecycle-sensitive work best done **attended** (watch it actually
connect, debug the configure()/singleton interaction, decide the CI wiring) — a blind AFK spike risks
a long, possibly-failing effort that leaves a flaky half-harness, which is worse than this deferral.

## Recipe when picked up (attended)
1. Add `EmulatorProbe.isReachable` (a 100ms socket connect to localhost:8080).
2. Add `IntegrationTests`-style cases in the existing test dir, each `@Test(.enabled(if:
   EmulatorProbe.isReachable))`, that: ensure Firebase is configured for the emulator exactly once
   (guard against the host app's configure()), seed `events/e/state/main` + a reward via the SDK, run
   the real `FirestoreService` method, and assert balance re-check + idempotency (run the unlock
   twice; assert one deduction).
3. Run locally with `firebase emulators:exec --only firestore --project birthdayquest-test
   'xcodebuild -project BirthdayQuest/BirthdayQuest.xcodeproj -scheme BirthdayQuest -destination
   "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing:BirthdayQuestTests test'`.
4. Add the same wrapped invocation as a separate CI job (not the default unit pass).
