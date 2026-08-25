# Participant Removal — Design

**Date:** 2026-08-25  **Branch:** feat/participant-removal

Host can remove a contributor from an occasion. Closes the "participant removal" gap.

## Security boundary (ALREADY in the rules — no rule change)
`events/{id}/participants/{uid}` has `allow delete: if isHost(eventId)` (firestore.rules:218), and
`isMember(eventId)` is `exists(participantPath(eventId))` (rules:37). So deleting a participant doc
**revokes that uid's membership** — every content read/write gated on `isMember` immediately fails.
That is the whole mechanism. **This rule was previously UNTESTED as an assertion** (the only
participant delete in the suite is inside `withSecurityRulesDisabled`), so this slice ADDS rules tests
(and mutation-verifies them) but changes NO rule.

## Semantics (the product call — conservative + reversible)
- Removing a contributor deletes ONLY their participant doc. Their **authored gifts stay** (a reward
  is *to* the celebrant; `fromUserId` is immutable and retracting it would surprise the celebrant),
  as do any challenge completions/timeline entries. Removal revokes *access*, not their contributions.
- The membership mirror `memberships/{uid}/events/{id}` is **left in place** — the host cannot delete
  another user's mirror (rules:128 gate mirror-delete on `request.auth.uid == uid`, and widening that
  would let a host delete arbitrary users' membership docs — an unwanted privilege). A stale mirror is
  harmless: `fetchMyOccasions` fans out and its **skip-on-failure** drops the now-unreadable occasion
  from the removed user's list (the event read denies on `isMember == false`). Re-join needs the code.
- **UI policy:** offer Remove only for a `mode == .contributor && !isHost` participant — never the host
  (self) and never the celebrant (removing the recipient would orphan the occasion). The rule enforces
  host-only *delete*; the UI enforces the finer "contributors only" policy (rules = security boundary,
  UI = product policy — the standard split).

## Components
- `GameBackend.removeParticipant(eventId:uid:) async throws` + `FirestoreService` impl:
  `participantsRef(eventId).document(uid).delete()` (after `eventRef(eventId)` validation). Deletes
  only the participant doc. Doc-comment the stale-mirror consequence.
- `AdminViewModel.removeParticipant(_ participant:) async`: `guard !isPerformingAction`; defensively
  guard the target is a removable contributor; call the service; on success reload the roster + set a
  success `actionResult`; on failure set an error `actionResult`. Add `participantToRemove: Participant?`
  for the confirmation.
- `AdminControlsView`: a participants section listing removable contributors, each with a Remove button
  → sets `participantToRemove` → a **destructive confirmation dialog** → `removeParticipant`. BQDesign
  tokens only; matches the existing admin-section patterns.

## Testing
- Rules (`firestore.rules.test.js`): host CAN delete a contributor's participant doc (assertSucceeds);
  a non-host member CANNOT delete another participant, nor their own, via this rule (assertFails).
  MUTATION-VERIFY: flipping `allow delete: if isHost(eventId)` → `if isMember(eventId)` must turn the
  non-host-denied test red.
- Swift (`AdminViewModel` via `MockGameBackend`): removeParticipant calls the backend with the right
  eventId/uid and reloads the roster; a backend failure surfaces an error `actionResult`; the
  `!isPerformingAction` guard holds. `MockGameBackend` gains a recording `removeParticipant` stub.
