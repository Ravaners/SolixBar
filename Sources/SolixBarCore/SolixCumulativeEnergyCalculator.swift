import Foundation

public struct SolixCumulativeEnergyState: Codable, Sendable, Equatable {
    public var totalKWh: Double
    public var lastDate: Date?
    public var lastSolarWatts: Int?
    public var lastSourceKey: String?
    public var manualBaseKWh: Double?
    public var lastAuthoritativeTotalKWh: Double?

    public init(
        totalKWh: Double = 0,
        lastDate: Date? = nil,
        lastSolarWatts: Int? = nil,
        lastSourceKey: String? = nil,
        manualBaseKWh: Double? = nil,
        lastAuthoritativeTotalKWh: Double? = nil
    ) {
        self.totalKWh = totalKWh
        self.lastDate = lastDate
        self.lastSolarWatts = lastSolarWatts
        self.lastSourceKey = lastSourceKey
        self.manualBaseKWh = manualBaseKWh
        self.lastAuthoritativeTotalKWh = lastAuthoritativeTotalKWh
    }
}

public enum SolixCumulativeEnergyCalculator {
    public static func mergingLegacyStates(
        _ states: [(sourceKey: String, state: SolixCumulativeEnergyState)]
    ) -> SolixCumulativeEnergyState {
        guard let newest = states.max(by: {
            ($0.state.lastDate ?? .distantPast) < ($1.state.lastDate ?? .distantPast)
        }) else {
            return SolixCumulativeEnergyState()
        }

        var merged = newest.state
        merged.totalKWh = states.reduce(0) { $0 + max(0, $1.state.totalKWh) }
        merged.lastSourceKey = newest.state.lastSourceKey ?? newest.sourceKey
        merged.lastAuthoritativeTotalKWh = nil
        return merged
    }

    public static func recording(
        state originalState: SolixCumulativeEnergyState,
        solarWatts: Int?,
        providerTotalKWh: Double?,
        providerTotalIsAuthoritative: Bool,
        configuredManualBaseKWh: Double?,
        tracksManualBase: Bool,
        sourceKey: String,
        date: Date
    ) -> SolixCumulativeEnergyState {
        var state = originalState

        if tracksManualBase, configuredManualBaseKWh != state.manualBaseKWh {
            state.manualBaseKWh = configuredManualBaseKWh
            if let configuredManualBaseKWh {
                state.totalKWh = max(0, configuredManualBaseKWh)
                state.lastAuthoritativeTotalKWh = nil
                updateLastSample(&state, solarWatts: solarWatts, sourceKey: sourceKey, date: date)
                return state
            }
        }

        let measuredKWh: Double
        if state.lastSourceKey == nil || state.lastSourceKey == sourceKey,
           let lastDate = state.lastDate,
           let lastSolarWatts = state.lastSolarWatts,
           let solarWatts {
            let isSameDay = Calendar.current.isDate(lastDate, inSameDayAs: date)
            measuredKWh = SolixEnergyCalculator.cumulativeKWh(
                from: lastSolarWatts,
                to: solarWatts,
                seconds: date.timeIntervalSince(lastDate),
                maximumGap: isSameDay ? 8 * 60 * 60 : 30 * 60
            )
        } else {
            measuredKWh = 0
        }

        if providerTotalIsAuthoritative,
           let providerTotalKWh,
           providerTotalKWh >= 0 {
            if state.lastAuthoritativeTotalKWh == nil {
                // The first real provider value corrects older local estimates in either direction.
                state.totalKWh = providerTotalKWh
            } else if providerTotalKWh > (state.lastAuthoritativeTotalKWh ?? 0) {
                // Keep the smoother local estimate only while the provider is still catching up.
                state.totalKWh = max(state.totalKWh + measuredKWh, providerTotalKWh)
            } else {
                state.totalKWh += measuredKWh
            }
            state.lastAuthoritativeTotalKWh = max(
                state.lastAuthoritativeTotalKWh ?? providerTotalKWh,
                providerTotalKWh
            )
        } else {
            state.totalKWh += measuredKWh
            if let providerTotalKWh, providerTotalKWh > state.totalKWh {
                state.totalKWh = providerTotalKWh
            }
        }

        updateLastSample(&state, solarWatts: solarWatts, sourceKey: sourceKey, date: date)
        return state
    }

    private static func updateLastSample(
        _ state: inout SolixCumulativeEnergyState,
        solarWatts: Int?,
        sourceKey: String,
        date: Date
    ) {
        state.lastDate = date
        state.lastSolarWatts = solarWatts
        state.lastSourceKey = sourceKey
    }
}
