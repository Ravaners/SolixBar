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
require(abs(SolixEnergyCalculator.cumulativeKWh(from: 500, to: 500, seconds: 7_200) - 1) < 0.000_000_1, "daytime sleep gap integration")
require(SolixEnergyCalculator.cumulativeKWh(from: 0, to: 500, seconds: 7_200) == 0, "uncertain sunrise gap rejection")
require(abs(SolixEnergyCalculator.cumulativeKWh(from: 1_460, to: 1_180, seconds: 18_900, maximumGap: 28_800) - 6.93) < 0.000_000_1, "same-day long gap recovery")

let mergedLegacy = SolixCumulativeEnergyCalculator.mergingLegacyStates([
    ("command", SolixCumulativeEnergyState(totalKWh: 34.37, lastDate: Date(timeIntervalSince1970: 100), lastSolarWatts: 800)),
    ("solix", SolixCumulativeEnergyState(totalKWh: 9.64, lastDate: Date(timeIntervalSince1970: 200), lastSolarWatts: 600)),
])
require(abs(mergedLegacy.totalKWh - 44.01) < 0.000_000_1, "legacy live counters are combined")
require(mergedLegacy.lastSourceKey == "solix", "latest legacy source continues the measurement")

let start = Date(timeIntervalSince1970: 1_700_000_000)
let legacy = SolixCumulativeEnergyState(
    totalKWh: 34.37,
    lastDate: start,
    lastSolarWatts: 500,
    lastSourceKey: "command"
)
let switchedSource = SolixCumulativeEnergyCalculator.recording(
    state: legacy,
    solarWatts: 600,
    providerTotalKWh: nil,
    providerTotalIsAuthoritative: false,
    configuredManualBaseKWh: nil,
    tracksManualBase: true,
    sourceKey: "solix",
    date: start.addingTimeInterval(120)
)
require(switchedSource.totalKWh == 34.37, "source switch keeps cumulative total without double counting")

let correctedProvider = SolixCumulativeEnergyCalculator.recording(
    state: switchedSource,
    solarWatts: 600,
    providerTotalKWh: 31.45,
    providerTotalIsAuthoritative: true,
    configuredManualBaseKWh: nil,
    tracksManualBase: true,
    sourceKey: "solix",
    date: start.addingTimeInterval(240)
)
require(correctedProvider.totalKWh == 31.45, "first authoritative total corrects a high local estimate")

let manuallyReset = SolixCumulativeEnergyCalculator.recording(
    state: correctedProvider,
    solarWatts: 600,
    providerTotalKWh: nil,
    providerTotalIsAuthoritative: false,
    configuredManualBaseKWh: 20,
    tracksManualBase: true,
    sourceKey: "solix",
    date: start.addingTimeInterval(360)
)
require(manuallyReset.totalKWh == 20, "manual total base resets exactly")
require(WarningConditionEvaluator.isLow(19, threshold: 20) == true, "low battery warning")
require(WarningConditionEvaluator.isLow(nil, threshold: 20) == nil, "missing battery value")
require(WarningConditionEvaluator.isHigh(1_200, threshold: 1_000) == true, "high input warning")
require(WarningConditionEvaluator.solarDrop(currentWatts: 350, baselineWatts: 1_000, thresholdPercent: 60)?.isTriggered == true, "solar drop warning")
require(WarningConditionEvaluator.solarDrop(currentWatts: 0, baselineWatts: 99, thresholdPercent: 60) == nil, "nighttime solar suppression")
print("SolixBar core checks passed.")
