import Foundation
import SolixBarCore
import UserNotifications

@MainActor
final class WarningMonitor {
    private var conditionStartedAt: [WarningKind: Date] = [:]
    private var deliveredWarnings = Set<WarningKind>()
    private var solarSamples: [(date: Date, watts: Double)] = []

    func activateIfNeeded(rules: [WarningKind: WarningRule]) {
        guard rules.values.contains(where: \.isEnabled) else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLogger.error("Notification permission failed: \(error.localizedDescription)")
            } else {
                AppLogger.info("Notification permission: \(granted ? "granted" : "not granted").")
            }
        }
    }

    func process(snapshot: SolixSnapshot, rules: [WarningKind: WarningRule]) {
        let now = Date()
        updateSolarHistory(snapshot.solarWatts, at: now)
        for kind in WarningKind.allCases {
            let rule = rules[kind] ?? .defaultRule(for: kind)
            guard rule.isEnabled else {
                reset(kind)
                continue
            }
            guard let state = warningState(kind, snapshot: snapshot, threshold: rule.threshold) else {
                reset(kind)
                continue
            }
            guard state.isTriggered else {
                reset(kind)
                continue
            }

            let started = conditionStartedAt[kind] ?? now
            conditionStartedAt[kind] = started
            let requiredSeconds = max(0, rule.durationMinutes * 60)
            guard now.timeIntervalSince(started) >= requiredSeconds,
                  !deliveredWarnings.contains(kind) else { continue }
            deliveredWarnings.insert(kind)
            deliver(kind: kind, detail: state.detail, durationMinutes: rule.durationMinutes)
        }
    }

    private func warningState(
        _ kind: WarningKind,
        snapshot: SolixSnapshot,
        threshold: Double
    ) -> (isTriggered: Bool, detail: String)? {
        switch kind {
        case .batteryLow:
            guard let value = snapshot.batteryPercent else { return nil }
            return (WarningConditionEvaluator.isLow(Double(value), threshold: threshold) == true, "\(value)%")
        case .solarDrop:
            guard let current = snapshot.solarWatts.map(Double.init),
                  let baseline = solarSamples.map(\.watts).max(),
                  let evaluation = WarningConditionEvaluator.solarDrop(
                    currentWatts: current,
                    baselineWatts: baseline,
                    thresholdPercent: threshold
                  ) else { return nil }
            return (evaluation.isTriggered, "\(Int(round(baseline)))W → \(Int(round(current)))W (\(Int(round(evaluation.dropPercent)))%)")
        case .homeHigh:
            guard let value = snapshot.homeWatts else { return nil }
            return (WarningConditionEvaluator.isHigh(Double(value), threshold: threshold) == true, "\(value)W")
        case .gridImportHigh:
            guard let value = snapshot.gridWatts else { return nil }
            return (WarningConditionEvaluator.isHigh(Double(max(0, value)), threshold: threshold) == true, "\(max(0, value))W")
        case .gridExportHigh:
            guard let value = snapshot.gridWatts else { return nil }
            return (WarningConditionEvaluator.isHigh(Double(max(0, -value)), threshold: threshold) == true, "\(max(0, -value))W")
        case .batteryChargeHigh:
            guard let value = snapshot.batteryWatts else { return nil }
            return (WarningConditionEvaluator.isHigh(Double(max(0, value)), threshold: threshold) == true, "\(max(0, value))W")
        case .batteryDischargeHigh:
            guard let value = snapshot.batteryWatts else { return nil }
            return (WarningConditionEvaluator.isHigh(Double(max(0, -value)), threshold: threshold) == true, "\(max(0, -value))W")
        }
    }

    private func updateSolarHistory(_ watts: Int?, at date: Date) {
        let cutoff = date.addingTimeInterval(-30 * 60)
        solarSamples.removeAll { $0.date < cutoff }
        if let watts {
            solarSamples.append((date, Double(max(0, watts))))
        }
    }

    private func reset(_ kind: WarningKind) {
        conditionStartedAt.removeValue(forKey: kind)
        deliveredWarnings.remove(kind)
    }

    private func deliver(kind: WarningKind, detail: String, durationMinutes: Double) {
        let content = UNMutableNotificationContent()
        content.title = "SolixBar – \(kind.title)"
        let duration = durationMinutes.rounded() == durationMinutes
            ? String(Int(durationMinutes))
            : String(format: "%.1f", durationMinutes)
        content.body = LocalizedText.text(
            "Grenzwert seit mindestens \(duration) Minuten erreicht: \(detail)",
            "Threshold reached for at least \(duration) minutes: \(detail)"
        )
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "solixbar.warning.\(kind.rawValue).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.error("Warning notification failed: \(error.localizedDescription)")
            } else {
                AppLogger.info("Warning delivered: \(kind.rawValue).")
            }
        }
    }
}
