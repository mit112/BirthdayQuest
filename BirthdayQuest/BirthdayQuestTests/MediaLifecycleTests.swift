import Testing
@testable import BirthdayQuest
import Foundation

@Suite("MediaLifecycle")
struct MediaLifecycleTests {
    private let occasionDate = Date(timeIntervalSince1970: 1_000_000_000)

    @Test("expiry is exactly occasionDate plus the grace period")
    func expiryIsOccasionDatePlusGracePeriod() {
        let expected = occasionDate.addingTimeInterval(MediaLifecycle.gracePeriod)
        #expect(MediaLifecycle.expiry(occasionDate: occasionDate) == expected)
    }

    @Test("isExpired is false one second before expiry")
    func isExpiredFalseJustBeforeExpiry() {
        let expiry = MediaLifecycle.expiry(occasionDate: occasionDate)
        let now = expiry.addingTimeInterval(-1)
        #expect(MediaLifecycle.isExpired(occasionDate: occasionDate, now: now) == false)
    }

    @Test("isExpired is true exactly at expiry")
    func isExpiredTrueAtExpiry() {
        let expiry = MediaLifecycle.expiry(occasionDate: occasionDate)
        #expect(MediaLifecycle.isExpired(occasionDate: occasionDate, now: expiry) == true)
    }

    @Test("isExpired is true one second after expiry")
    func isExpiredTrueJustAfterExpiry() {
        let expiry = MediaLifecycle.expiry(occasionDate: occasionDate)
        let now = expiry.addingTimeInterval(1)
        #expect(MediaLifecycle.isExpired(occasionDate: occasionDate, now: now) == true)
    }

    @Test("isWithinReminderWindow is false one second before the window opens")
    func isWithinReminderWindowFalseJustBeforeWindow() {
        let expiry = MediaLifecycle.expiry(occasionDate: occasionDate)
        let windowStart = expiry.addingTimeInterval(-MediaLifecycle.reminderWindow)
        let now = windowStart.addingTimeInterval(-1)
        #expect(MediaLifecycle.isWithinReminderWindow(occasionDate: occasionDate, now: now) == false)
    }

    @Test("isWithinReminderWindow is true exactly when the window opens")
    func isWithinReminderWindowTrueAtWindowStart() {
        let expiry = MediaLifecycle.expiry(occasionDate: occasionDate)
        let windowStart = expiry.addingTimeInterval(-MediaLifecycle.reminderWindow)
        #expect(MediaLifecycle.isWithinReminderWindow(occasionDate: occasionDate, now: windowStart) == true)
    }

    @Test("isWithinReminderWindow is true exactly at expiry")
    func isWithinReminderWindowTrueAtExpiry() {
        let expiry = MediaLifecycle.expiry(occasionDate: occasionDate)
        #expect(MediaLifecycle.isWithinReminderWindow(occasionDate: occasionDate, now: expiry) == true)
    }

    @Test("isWithinReminderWindow is true well past expiry")
    func isWithinReminderWindowTrueWellPastExpiry() {
        let expiry = MediaLifecycle.expiry(occasionDate: occasionDate)
        let now = expiry.addingTimeInterval(MediaLifecycle.reminderWindow * 10)
        #expect(MediaLifecycle.isWithinReminderWindow(occasionDate: occasionDate, now: now) == true)
    }
}
