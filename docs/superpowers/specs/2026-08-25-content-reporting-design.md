# Content Reporting (App Store Guideline 1.2) — Design

**Date:** 2026-08-25  **Branch:** feat/content-reporting

Adds a way for any member to flag an objectionable gift; the host sees flagged items and acts via the
existing content-delete lever. Combined with **host participant removal** (already shipped — the "eject
an abusive user" half), this is the Guideline-1.2 UGC mechanism. The EULA/terms text is human-gated and
NOT fabricated here (a stub note is the deliverable for that piece).

## Scope (tight, extensible)
- Report **gifts (rewards)** this cut — the primary media UGC (the celebrant sees contributor photos/
  video/audio/text). The report doc is GENERIC (`contentType` field) so challenge reporting is a later
  add with no rules change.
- **No reason-input UI** this cut (Apple doesn't require it): report files with `reason: nil` behind a
  confirmation. The `reason` field exists in the model/rules for later.
- **No persistent local hide/block** this cut (it would pull in UserDefaults → a new privacy-manifest
  required-reason API; out of scope). The host acting (delete) is the enforcement; blocking an abuser =
  the already-shipped participant removal.

## New collection + rules (this slice CHANGES firestore.rules → run the emulator suite + mutation-test)
`events/{eventId}/reports/{reportId}`:
```
match /reports/{reportId} {
  allow read: if isHost(eventId);                       // host-only moderation view (get + list)
  allow create: if isMember(eventId)
                && request.resource.data.reportedByUserId == request.auth.uid
                && request.resource.data.contentType in ['reward', 'challenge']
                && request.resource.data.contentId is string
                && request.resource.data.contentId.size() > 0;
  allow update, delete: if false;                       // append-only audit record
}
```
Insert after the `state/{stateId}` block (firestore.rules ~line 317), inside `match /events/{eventId}`.

## Model / backend
- `Report` (`@DocumentID id`, `contentType: String`, `contentId: String`, `reportedByUserId: String`,
  `reason: String?`, `createdAt: Date`). No hand-written `init(from:)` (the `@DocumentID` rule).
- `Collections.reports = "reports"`; a `StoragePaths`-style path isn't needed (Firestore only).
- `GameBackend.reportContent(eventId:contentType:contentId:reason:) async throws` — create a report doc
  with `reportedByUserId` = the calling uid (`FirestoreService` reads `Auth.auth().currentUser?.uid`).
- `GameBackend.fetchReports(eventId:) async throws -> [Report]` — host-only by rule.

## UI
- `RewardContentSheet`: a low-key "Report this gift" affordance (secondary style, subordinate to the
  celebration — not competing with Done/confetti) → a `.confirmationDialog` ("Report this gift to the
  host?") → `reportContent(contentType: "reward", contentId: reward.id, reason: nil)` → a brief
  "Reported — the host will review" confirmation. BQDesign tokens; AA-safe; ≥44pt hit area.
- `AdminControlsView`: a "Reports" section (host) listing flagged items — resolve each report's
  `contentId` against the already-loaded `rewards`/`challenges` to show a title where possible, plus the
  reason (if any) and date. Read-only; the host removes the content via the existing curation/delete
  flow. Empty state consistent with the other admin cards.

## Testing
- Rules (`firestore.rules.test.js`, new `describe`): member can create a valid report; a non-member
  cannot; a member cannot file as another user (`reportedByUserId != auth.uid`); a create with a bad
  `contentType` is denied; the host can read/list; a non-host member cannot read; update/delete denied.
  MUTATION-VERIFY: `read: if isHost` → `isMember` turns the non-host-read test red; `create: if isMember`
  → `signedIn()` turns the non-member-create test red.
- Swift (`MockGameBackend` + VM tests): `reportContent` creates a doc with the right ids/reporter;
  `fetchReports` returns them; the report VM action + admin Reports display resolve titles. Discriminating.
