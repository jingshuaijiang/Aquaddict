import Foundation

// Runs the ZHL-16C model over a recorded dive: per-sample tissue snapshots
// for the loading replay, plus surfacing numbers.
public struct TissueSnapshot: Sendable, Equatable {
    public let timeS: Int
    public let depthM: Double
    public let compartmentPercents: [Double]   // 16 values, % toward M-value
    public let ceilingM: Double                // at GF-high
    public let gf99: Double                    // raw supersaturation %
}

public enum TissueReplay {
    public struct Result: Sendable, Equatable {
        public let snapshots: [TissueSnapshot]
        public let surfaceGF: Double           // GF99 immediately after surfacing
        public let leadingCompartment: Int     // most-loaded at surfacing (0-based)
        public let desatHours: Double          // rough time to ~near-clean tissues
    }

    /// Replay a dive's samples. Gas fractions come from each sample (handles
    /// recorded gas switches); ceilings use the dive's own GF-high.
    public static func compute(samples: [DiveSample], header: DiveHeader) -> Result {
        let surface = Double(header.surfaceMbar) / 1000.0
        let densityFactor = Double(header.waterDensity) / 1000.0
        var tissues = ZHL16C.Tissues(surfaceBar: surface)
        let gfHigh = Double(header.gfHigh) / 100.0

        var snapshots: [TissueSnapshot] = []
        snapshots.reserveCapacity(samples.count)
        var lastT = 0
        for s in samples {
            let dt = Double(s.timeS - lastT) / 60.0
            lastT = s.timeS
            let ambient = surface + s.depthM / 10.0 * densityFactor
            tissues.expose(ambientBar: ambient,
                           fO2: Double(s.o2) / 100.0,
                           fHe: Double(s.he) / 100.0,
                           minutes: max(dt, 0))
            snapshots.append(TissueSnapshot(
                timeS: s.timeS,
                depthM: s.depthM,
                compartmentPercents: tissues.compartmentPercents(ambientBar: ambient),
                ceilingM: tissues.ceilingM(gf: gfHigh, surfaceBar: surface),
                gf99: tissues.gradientPercent(ambientBar: ambient)))
        }

        let surfaceGF = tissues.gradientPercent(ambientBar: surface)
        let surfacePercents = tissues.compartmentPercents(ambientBar: surface)
        let leading = surfacePercents.enumerated().max { $0.element < $1.element }?.offset ?? 0

        // rough desaturation: time for the leading compartment's excess to
        // decay to 5% (n half-times of that compartment)
        let equilibrium = (surface - ZHL16C.waterVaporBar) * ZHL16C.airN2Fraction
        let excess = tissues.pN2[leading] + tissues.pHe[leading] - equilibrium
        var desat = 0.0
        if excess > 0.01 {
            let halftime = ZHL16C.n2Halftime[leading]
            let halvings = log2(excess / 0.01)
            desat = max(0, halvings * halftime / 60.0)
        }

        return Result(snapshots: snapshots, surfaceGF: surfaceGF,
                      leadingCompartment: leading, desatHours: desat)
    }
}
