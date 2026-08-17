import Foundation

// Bühlmann ZHL-16C with gradient factors.
//
// 16 tissue compartments, each tracking inert-gas partial pressures (N2 + He)
// via exponential uptake/offgassing. A compartment tolerates an ambient
// pressure down to (P − a·gf) / (gf/b + 1 − gf); the ceiling is the deepest
// such limit across compartments. Constants are the published ZHL-16C set
// (as used by Subsurface/libdivecomputer).

public enum ZHL16C {
    public static let compartments = 16

    // N2 half-times (min) and coefficients
    static let n2Halftime: [Double] = [
        5.0, 8.0, 12.5, 18.5, 27.0, 38.3, 54.3, 77.0,
        109.0, 146.0, 187.0, 239.0, 305.0, 390.0, 498.0, 635.0,
    ]
    static let n2A: [Double] = [
        1.1696, 1.0000, 0.8618, 0.7562, 0.6200, 0.5043, 0.4410, 0.4000,
        0.3750, 0.3500, 0.3295, 0.3065, 0.2835, 0.2610, 0.2480, 0.2327,
    ]
    static let n2B: [Double] = [
        0.5578, 0.6514, 0.7222, 0.7825, 0.8126, 0.8434, 0.8693, 0.8910,
        0.9092, 0.9222, 0.9319, 0.9403, 0.9477, 0.9544, 0.9602, 0.9653,
    ]

    // He half-times and coefficients
    static let heHalftime: [Double] = [
        1.88, 3.02, 4.72, 6.99, 10.21, 14.48, 20.53, 29.11,
        41.20, 55.19, 70.69, 90.34, 115.29, 147.42, 188.24, 240.03,
    ]
    static let heA: [Double] = [
        1.6189, 1.3830, 1.1919, 1.0458, 0.9220, 0.8205, 0.7305, 0.6502,
        0.5950, 0.5545, 0.5333, 0.5189, 0.5181, 0.5176, 0.5172, 0.5119,
    ]
    static let heB: [Double] = [
        0.4770, 0.5747, 0.6527, 0.7223, 0.7582, 0.7957, 0.8279, 0.8553,
        0.8757, 0.8903, 0.8997, 0.9073, 0.9122, 0.9171, 0.9217, 0.9267,
    ]

    public static let waterVaporBar = 0.0627
    public static let airN2Fraction = 0.79

    /// Inert gas loadings, bar.
    public struct Tissues: Sendable, Equatable {
        public var pN2: [Double]
        public var pHe: [Double]

        /// Saturated at the surface breathing air.
        public init(surfaceBar: Double) {
            let p = (surfaceBar - ZHL16C.waterVaporBar) * ZHL16C.airN2Fraction
            pN2 = Array(repeating: p, count: ZHL16C.compartments)
            pHe = Array(repeating: 0, count: ZHL16C.compartments)
        }

        /// Exposure at constant ambient pressure for a duration.
        public mutating func expose(ambientBar: Double, fO2: Double, fHe: Double,
                                    minutes: Double) {
            let fN2 = 1.0 - fO2 - fHe
            let alvN2 = max(0, (ambientBar - ZHL16C.waterVaporBar) * fN2)
            let alvHe = max(0, (ambientBar - ZHL16C.waterVaporBar) * fHe)
            for i in 0 ..< ZHL16C.compartments {
                pN2[i] += (alvN2 - pN2[i]) * (1 - pow(2, -minutes / ZHL16C.n2Halftime[i]))
                pHe[i] += (alvHe - pHe[i]) * (1 - pow(2, -minutes / ZHL16C.heHalftime[i]))
            }
        }

        /// Lowest tolerated ambient pressure (bar) at a gradient factor.
        public func toleratedAmbient(gf: Double) -> Double {
            var worst = 0.0
            for i in 0 ..< ZHL16C.compartments {
                let p = pN2[i] + pHe[i]
                guard p > 0 else { continue }
                let a = (ZHL16C.n2A[i] * pN2[i] + ZHL16C.heA[i] * pHe[i]) / p
                let b = (ZHL16C.n2B[i] * pN2[i] + ZHL16C.heB[i] * pHe[i]) / p
                let tolerated = (p - a * gf) / (gf / b + 1.0 - gf)
                worst = max(worst, tolerated)
            }
            return worst
        }

        /// Ceiling in meters at a gradient factor (0 = surface is fine).
        public func ceilingM(gf: Double, surfaceBar: Double) -> Double {
            let tolerated = toleratedAmbient(gf: gf)
            return max(0, (tolerated - surfaceBar) * 10.0)
        }

        /// Current supersaturation as a percent of the raw M-value gradient at
        /// an ambient pressure — the "GF99" a Shearwater shows.
        public func gradientPercent(ambientBar: Double) -> Double {
            var worst = 0.0
            for i in 0 ..< ZHL16C.compartments {
                let p = pN2[i] + pHe[i]
                guard p > 0 else { continue }
                let a = (ZHL16C.n2A[i] * pN2[i] + ZHL16C.heA[i] * pHe[i]) / p
                let b = (ZHL16C.n2B[i] * pN2[i] + ZHL16C.heB[i] * pHe[i]) / p
                let mValue = ambientBar / b + a
                let gradient = (p - ambientBar) / max(mValue - ambientBar, 1e-9)
                worst = max(worst, gradient)
            }
            return max(0, worst * 100)
        }

        /// Per-compartment supersaturation percent at an ambient pressure
        /// (for the 16-bar loading display; can exceed 100 beyond the M-value).
        public func compartmentPercents(ambientBar: Double) -> [Double] {
            (0 ..< ZHL16C.compartments).map { i in
                let p = pN2[i] + pHe[i]
                guard p > 0 else { return 0 }
                let a = (ZHL16C.n2A[i] * pN2[i] + ZHL16C.heA[i] * pHe[i]) / p
                let b = (ZHL16C.n2B[i] * pN2[i] + ZHL16C.heB[i] * pHe[i]) / p
                let mValue = ambientBar / b + a
                // fraction of the way from ambient equilibrium to the M-value
                let gradient = (p - ambientBar) / max(mValue - ambientBar, 1e-9)
                return gradient * 100
            }
        }
    }
}
