import Foundation

public enum RefreshReliabilityPolicy {
    public static func timerIsOverdue(
        now: Date,
        scheduledFor: Date?,
        grace: TimeInterval = 15
    ) -> Bool {
        guard let scheduledFor else { return false }
        return now.timeIntervalSince(scheduledFor) >= max(0, grace)
    }

    public static func refreshIsStuck(
        now: Date,
        startedAt: Date?,
        timeout: TimeInterval = 60
    ) -> Bool {
        guard let startedAt else { return false }
        return now.timeIntervalSince(startedAt) >= max(1, timeout)
    }
}
