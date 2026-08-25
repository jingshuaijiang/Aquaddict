import Foundation

// Rough dive energy expenditure.
//
// Preferred path (AI transmitter data): ventilation → oxygen uptake →
// energy. RMV (surface-referenced L/min) over a rolling window, divided by
// the ventilatory equivalent (VE/VO2 ≈ 26 at light-moderate work) gives
// VO2, and each liter of O2 ≈ 4.86 kcal. Fallback path: MET method
// (scuba ≈ 6 METs × body mass). Both add a cold-water thermal term —
// staying warm is a large share of dive energy cost.
//
// This is an estimate (±30% easily); it's for trends and fun, not medicine.

public enum CalorieEstimator {
    public enum Source: String, Sendable {
        case ventilation   // from tank pressure data
        case met           // fallback
    }

    public struct Estimate: Sendable, Equatable {
        public let totalKcal: Double
        public let workKcal: Double
        public let thermalKcal: Double
        public let avgKcalPerHour: Double
        public let source: Source
    }

    static let kcalPerLiterO2 = 4.86
    static let ventilatoryEquivalent = 26.0
    static let fallbackMET = 6.0
    static let neutralWaterC = 27.0
    static let thermalKcalPerMinPerDeg = 0.10
    static let thermalCapKcalPerMin = 2.5

    public static func estimate(samples: [DiveSample], intervalS: Int,
                                tankL: Double?, bodyKg: Double) -> Estimate? {
        guard samples.count > 5, intervalS > 0 else { return nil }
        let minutes = Double(samples.last!.timeS) / 60.0
        guard minutes > 1 else { return nil }

        // thermal term from the recorded water temperature, minute by minute
        var thermal = 0.0
        for s in samples {
            let deficit = max(0, neutralWaterC - s.tempC)
            thermal += min(deficit * thermalKcalPerMinPerDeg, thermalCapKcalPerMin)
                * Double(intervalS) / 60.0
        }

        // work term
        var work = 0.0
        var source = Source.met
        let pressures = samples.compactMap { s in s.tank1Bar.map { (s.timeS, $0, s.depthM) } }
        let restingKcalPerMin = bodyKg * 0.0175   // ~1 MET

        if let tankL, pressures.count > samples.count / 2,
           let first = pressures.first, let last = pressures.last,
           first.1 > last.1 {
            // rolling RMV → VO2 → kcal, window ~90 s
            source = .ventilation
            let w = max(3, 90 / intervalS)
            for j in 0 ..< pressures.count {
                let a = pressures[max(0, j - w)]
                let b = pressures[j]
                let dtMin = Double(b.0 - a.0) / 60.0
                var kcalPerMin = restingKcalPerMin
                if dtMin > 0, a.1 > b.1 {
                    let ata = 1.0 + (a.2 + b.2) / 2.0 / 10.0
                    let rmv = (a.1 - b.1) / dtMin / ata * tankL
                    let vo2 = rmv / ventilatoryEquivalent
                    kcalPerMin = max(restingKcalPerMin,
                                     min(vo2 * kcalPerLiterO2, 15))
                }
                work += kcalPerMin * Double(intervalS) / 60.0
            }
        } else {
            work = fallbackMET * bodyKg / 60.0 * minutes
        }

        let total = work + thermal
        return Estimate(totalKcal: total,
                        workKcal: work,
                        thermalKcal: thermal,
                        avgKcalPerHour: total / minutes * 60.0,
                        source: source)
    }
}
