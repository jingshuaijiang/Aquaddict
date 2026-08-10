import Foundation

// Pre-dive gas planning math, GUE-flavored. Pure closed-form formulas —
// every function is covered by unit tests against hand-checked values.
//
// Conventions: depths in meters of sea water (10 m ≈ 1 atm approximation,
// consistent with common dive-planning practice), pressures in bar,
// volumes in liters.

public enum GasPlanner {
    /// Ambient pressure in ata at depth (planning convention: 10 m = 1 atm).
    public static func ata(_ depthM: Double) -> Double {
        1.0 + depthM / 10.0
    }

    /// Maximum operating depth for a mix at a ppO2 limit (bar).
    public static func modM(o2Percent: Int, ppO2Limit: Double) -> Double {
        max(0, (ppO2Limit / (Double(o2Percent) / 100.0) - 1.0) * 10.0)
    }

    /// Best (highest) O2 percentage for a target depth at a ppO2 limit.
    public static func bestO2Percent(depthM: Double, ppO2Limit: Double) -> Int {
        Int(ppO2Limit / ata(depthM) * 100.0)
    }

    /// Minimum helium fraction so END stays at or below a limit.
    /// END convention matches GasPhysics.endM (O2 counted narcotic).
    public static func minHePercent(depthM: Double, endLimitM: Double) -> Int {
        guard depthM > endLimitM else { return 0 }
        let fraction = 1.0 - (endLimitM + 10.0) / (depthM + 10.0)
        return Int((fraction * 100.0).rounded(.up))
    }

    /// GUE standard gases with their intended depth ranges (m).
    public struct StandardGas: Sendable, Equatable {
        public let name: String
        public let o2: Int
        public let he: Int
        public let maxDepthM: Double
    }

    public static let standardGases: [StandardGas] = [
        StandardGas(name: "EAN32", o2: 32, he: 0, maxDepthM: 30),
        StandardGas(name: "25/25", o2: 25, he: 25, maxDepthM: 39),
        StandardGas(name: "21/35", o2: 21, he: 35, maxDepthM: 51),
        StandardGas(name: "18/45", o2: 18, he: 45, maxDepthM: 60),
        StandardGas(name: "15/55", o2: 15, he: 55, maxDepthM: 75),
    ]

    /// The standard gas for a planned depth (nil beyond the standard range).
    public static func standardGas(forDepthM depth: Double) -> StandardGas? {
        standardGases.first { depth <= $0.maxDepthM }
    }

    /// Min-deco ascent schedule: first stop at half the max depth (rounded
    /// down to a 3 m multiple), then every 3 m up to 3 m, one minute each.
    public struct Stop: Sendable, Equatable {
        public let depthM: Int
        public let minutes: Int
    }

    public static func minDecoStops(maxDepthM: Double) -> [Stop] {
        guard maxDepthM > 9 else { return [] }
        let first = Int(maxDepthM / 2.0 / 3.0) * 3
        guard first >= 3 else { return [] }
        return stride(from: first, through: 3, by: -3).map { Stop(depthM: $0, minutes: 1) }
    }

    /// Minimum gas (rock bottom), GUE style: gas for two stressed divers to
    /// ascend from depth with min deco.
    /// - consumption: team SAC under stress, default 30 L/min (2 × 15).
    /// - time: 1 min problem-solving at depth + ascent at 3 m/min average.
    /// Returns liters at the surface; divide by tank volume for bar.
    public static func minGasL(depthM: Double, teamSACLPerMin: Double = 30) -> Double {
        let minutes = 1.0 + depthM / 3.0
        let averageAta = ata(depthM / 2.0)
        return minutes * averageAta * teamSACLPerMin
    }

    public static func minGasBar(depthM: Double, tankL: Double,
                                 teamSACLPerMin: Double = 30) -> Double {
        minGasL(depthM: depthM, teamSACLPerMin: teamSACLPerMin) / tankL
    }

    /// Rule of thirds on the usable gas above minimum gas.
    public struct ThirdsPlan: Sendable, Equatable {
        public let usableBar: Double     // fill − min gas
        public let thirdBar: Double
        public let turnPressureBar: Double
    }

    public static func thirds(fillBar: Double, minGasBar: Double) -> ThirdsPlan {
        let usable = max(0, fillBar - minGasBar)
        let third = usable / 3.0
        return ThirdsPlan(usableBar: usable, thirdBar: third,
                          turnPressureBar: fillBar - third)
    }

    /// Total gas needed for a planned bottom segment (liters at surface).
    public static func bottomGasL(depthM: Double, minutes: Double,
                                  sacLPerMin: Double) -> Double {
        minutes * ata(depthM) * sacLPerMin
    }
}
