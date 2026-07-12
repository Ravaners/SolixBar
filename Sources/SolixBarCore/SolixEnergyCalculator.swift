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
}
