import Foundation
import SolixBarCore

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
        exit(1)
    }
}

let oneMinute = SolixEnergyCalculator.measuredKWh(from: 400, to: 600, seconds: 60)
require(abs(oneMinute - (500.0 / 60_000.0)) < 0.000_000_1, "trapezoid integration")
require(SolixEnergyCalculator.measuredKWh(from: 500, to: 500, seconds: 1_801) == 0, "large gap rejection")
require(SolixEnergyCalculator.measuredKWh(from: 500, to: 500, seconds: -1) == 0, "negative gap rejection")
require(WarningConditionEvaluator.isLow(19, threshold: 20) == true, "low battery warning")
require(WarningConditionEvaluator.isLow(nil, threshold: 20) == nil, "missing battery value")
require(WarningConditionEvaluator.isHigh(1_200, threshold: 1_000) == true, "high input warning")
require(WarningConditionEvaluator.solarDrop(currentWatts: 350, baselineWatts: 1_000, thresholdPercent: 60)?.isTriggered == true, "solar drop warning")
require(WarningConditionEvaluator.solarDrop(currentWatts: 0, baselineWatts: 99, thresholdPercent: 60) == nil, "nighttime solar suppression")
print("SolixBar core checks passed.")
