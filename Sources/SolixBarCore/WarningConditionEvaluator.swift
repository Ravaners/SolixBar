import Foundation

public struct SolarDropEvaluation: Equatable, Sendable {
    public var dropPercent: Double
    public var isTriggered: Bool

    public init(dropPercent: Double, isTriggered: Bool) {
        self.dropPercent = dropPercent
        self.isTriggered = isTriggered
    }
}

public enum WarningConditionEvaluator {
    public static func isLow(_ value: Double?, threshold: Double) -> Bool? {
        value.map { $0 <= max(0, threshold) }
    }

    public static func isHigh(_ value: Double?, threshold: Double) -> Bool? {
        value.map { $0 >= max(0, threshold) }
    }

    public static func solarDrop(
        currentWatts: Double?,
        baselineWatts: Double?,
        thresholdPercent: Double,
        minimumBaselineWatts: Double = 100
    ) -> SolarDropEvaluation? {
        guard let currentWatts, let baselineWatts,
              baselineWatts >= minimumBaselineWatts, baselineWatts > 0 else { return nil }
        let drop = max(0, (baselineWatts - max(0, currentWatts)) / baselineWatts * 100)
        return SolarDropEvaluation(
            dropPercent: drop,
            isTriggered: drop >= max(0, thresholdPercent)
        )
    }
}
