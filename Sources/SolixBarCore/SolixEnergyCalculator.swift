import Foundation

public enum SolixEnergyCalculator {
    public static func measuredKWh(
        from firstWatts: Int,
        to secondWatts: Int,
        seconds: TimeInterval
    ) -> Double {
        guard seconds > 0, seconds <= 30 * 60 else { return 0 }
        return max(0, Double(firstWatts + secondWatts) / 2 * seconds / 3_600_000)
    }

    public static func cumulativeKWh(
        from firstWatts: Int,
        to secondWatts: Int,
        seconds: TimeInterval,
        maximumGap: TimeInterval = 4 * 60 * 60
    ) -> Double {
        guard seconds > 0 else { return 0 }
        if seconds <= 30 * 60 {
            return measuredKWh(from: firstWatts, to: secondWatts, seconds: seconds)
        }
        guard seconds <= maximumGap, min(firstWatts, secondWatts) >= 50 else { return 0 }
        return max(0, Double(firstWatts + secondWatts) / 2 * seconds / 3_600_000)
    }
}
