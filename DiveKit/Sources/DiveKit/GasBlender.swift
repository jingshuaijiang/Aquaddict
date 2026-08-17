import Foundation

// Partial-pressure nitrox blending: starting from what's in the tank, how
// much pure O2 to add before topping off with air (or a nitrox bank).
public enum GasBlender {
    public struct Recipe: Sendable, Equatable {
        /// Drain the tank down to this pressure first (nil = no drain needed).
        public let drainToBar: Double?
        /// Then add pure O2 until this absolute pressure…
        public let addO2Bar: Double
        /// …then top with the fill gas to the target pressure.
        public let topWithBar: Double
    }

    /// Solve start(startBar, startO2) → target(targetBar, targetO2), topping
    /// with `topO2` fraction (0.209 for air, or a nitrox bank).
    public static func blend(startBar: Double, startO2: Double,
                             targetBar: Double, targetO2: Double,
                             topO2: Double = 0.209) -> Recipe? {
        guard targetBar > 0, targetO2 > topO2 - 1e-9, targetO2 <= 1.0 else { return nil }

        func o2ToAdd(from bar: Double, o2 frac: Double) -> Double {
            // x = O2 bar to add so that after topping with topO2 to targetBar
            // the mix hits targetO2:
            // targetO2·targetBar = frac·bar + x + topO2·(targetBar − bar − x)
            (targetBar * (targetO2 - topO2) - bar * (frac - topO2)) / (1.0 - topO2)
        }

        var drain: Double? = nil
        var base = startBar
        var baseO2 = startO2
        var x = o2ToAdd(from: base, o2: baseO2)

        if x < 0 {
            // current mix is too rich/full — find the drain pressure where
            // x becomes 0
            let d = targetBar * (targetO2 - topO2) / max(baseO2 - topO2, 1e-9)
            if d >= 0, d < startBar {
                drain = d
                base = d
                x = 0
            } else {
                // even a full drain can't get there (target leaner than top gas)
                drain = 0
                base = 0
                baseO2 = 0
                x = o2ToAdd(from: 0, o2: 0)
                guard x >= 0 else { return nil }
            }
        }

        return Recipe(drainToBar: drain,
                      addO2Bar: base + x,
                      topWithBar: targetBar)
    }

    /// Best mix for a depth at a ppO2 limit, plus its MOD — planning helpers.
    public static func bestMixO2Percent(depthM: Double, ppO2: Double = 1.4) -> Int {
        GasPlanner.bestO2Percent(depthM: depthM, ppO2Limit: ppO2)
    }
}
