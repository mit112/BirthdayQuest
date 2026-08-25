# Media Lifecycle — Implementation Plan

Design: `docs/superpowers/specs/2026-08-24-media-lifecycle-design.md`. No rules change.

New `.swift` files need **no** pbxproj edit — the source & test dirs are folder-synced groups.

## Task A — `MediaLifecycle` policy (pure) + tests   [no deps]
- New `Services/MediaLifecycle.swift`: `gracePeriod` (30d), `reminderWindow` (7d),
  `expiry(occasionDate:)`, `isExpired(occasionDate:now:)`, `isWithinReminderWindow(occasionDate:now:)`.
  Pure, `enum` namespace, no I/O. `now` always injected (no `Date()` inside).
- New test file: boundary tests (exactly at expiry, ±1s, reminder-window edges). Each assertion must
  fail if the predicate is inverted (no vacuous green).
- Touches: only the two new files. Compiles alone.

## Task B — `.expired` presentation state end-to-end   [no deps; parallel with A]
Compile-coupled, so ONE task (enum case + every exhaustive switch + the failure translation):
- `MediaStore.swift`: add `MediaStoreError.objectMissing`; in `localURLs`, translate a thrown Storage
  `objectNotFound` (code `StorageErrorCode.objectNotFound.rawValue`) into `.objectMissing`; all other
  errors pass through. (Files already on disk still short-circuit before any download.)
- `RewardContentSheet.swift`: add `RewardContentPresentation.expired`; in `resolve`, map a caught
  `MediaStore.MediaStoreError.objectMissing` → `.expired`, any other throw → `.unavailable`
  (unchanged). Render `.expired` in `body`'s switch with honest copy ("This gift from {fromName}
  isn't available anymore. Ask them to send it again.") and in the `.task` switch suppress confetti +
  success haptic (same as `.unavailable`) and log at warning. Text never reaches `.expired`.
- Tests: `resolve` with a `MediaStoring` fake throwing `objectMissing` → `.expired`; throwing a
  generic error → `.unavailable`; returning URLs → renders. Removing the mapping must turn a test red.
- Touches: `MediaStore.swift`, `RewardContentSheet.swift`, + presentation test file.

## Task C — celebrant purge sweep + reminder banner   [after A and B]
Combined because both halves touch `RewardsViewModel` + are celebrant-rewards-view concerns, and the
purge half touches `MediaStore.swift` (serialize after B's MediaStore edit).
- `MediaStore.swift`: `purgeExpiredArchived(rewards:eventId:occasionDate:now:) async -> Int` per the
  spec's eligibility (has paths; `MediaLifecycle.isExpired`; every local file exists on disk *now*).
  Reuse the existing `storagePaths`/`localFileURL` helpers.
- `RewardsViewModel`: (1) celebrant-gated one-shot trigger firing the sweep in a best-effort Task
  after the first rewards snapshot; needs `isCelebrant`, `occasionDate`, a `MediaStoring` (injected,
  default `MediaStore()`). (2) A pure `showExpiryReminder(now:)`/computed reminder state + the banner
  copy inputs (count of unopened media gifts, formatted expiry date).
- `RewardsCarouselView.swift`: render the dismissible reminder banner from the VM state; pass
  `isCelebrant`/`occasionDate` from `EventSession` into the VM.
- Tests: `purgeExpiredArchived` matrix (not-expired→0; expired+files-absent→0; expired+files-present→
  deletes those paths; text→skip; idempotent). Reminder predicate matrix (isCelebrant × window ×
  unopened-media).
- Touches: `MediaStore.swift`, `RewardsViewModel.swift`, `RewardsCarouselView.swift`, + tests.

## Verify (controller)
- `xcodebuild ... -only-testing:BirthdayQuestTests test` green after each task.
- `swiftlint --strict` from repo root: 0 violations.
- Rules suite: NOT run (no rules change).
- Domain-sliced whole-branch review (Swift correctness on Opus; a11y/UI on Sonnet), fix wave, then
  FF-merge to main.
