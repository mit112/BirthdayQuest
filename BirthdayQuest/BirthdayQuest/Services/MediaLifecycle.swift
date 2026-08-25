import Foundation

/// Pure policy for reward-media lifetime — the single source of truth for "when". Kept free of I/O
/// so it is directly unit-testable, mirroring the WireKey / GameState.init(wire:) split that keeps
/// load-bearing logic out of the I/O types. `now` is always injected; this type never reads the
/// clock itself.
enum MediaLifecycle {
    /// Time after the occasion date that a reward's server media becomes eligible for cleanup.
    static let gracePeriod: TimeInterval = 30 * 24 * 60 * 60
    /// How long before expiry the celebrant is reminded to open unopened gifts.
    static let reminderWindow: TimeInterval = 7 * 24 * 60 * 60

    /// The instant a reward's server media becomes eligible for cleanup.
    static func expiry(occasionDate: Date) -> Date {
        occasionDate.addingTimeInterval(gracePeriod)
    }

    /// Whether server media is past its lifetime as of `now`.
    static func isExpired(occasionDate: Date, now: Date) -> Bool {
        now >= expiry(occasionDate: occasionDate)
    }

    /// Whether `now` is within the reminder window before expiry — and stays true past expiry, since
    /// a past-expiry occasion is still relevant to remind about. Intended, not a bug.
    static func isWithinReminderWindow(occasionDate: Date, now: Date) -> Bool {
        now >= expiry(occasionDate: occasionDate).addingTimeInterval(-reminderWindow)
    }
}
