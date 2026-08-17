import Foundation

// 2D static trim model of a prone diver.
//
// Body frame: x toward the head (m), y toward the surface (m), origin at the
// torso center. Weight acts down at the center of gravity (CG), buoyancy acts
// up at the center of buoyancy (CB). A free body rotates until CB sits
// directly above CG, giving the equilibrium pitch:
//
//     tan(theta) = (xb - xg) / (yb - yg),  theta > 0 = head-up
//
// The key non-rigid effect: gas (drysuit, wing bladder) migrates toward the
// high end of the body as pitch changes, which feeds back into CB — that's
// why a small head-up attitude with a gassy drysuit runs away. The model
// solves the feedback by damped fixed-point iteration.

public struct TrimComponent: Sendable, Equatable {
    public let name: String
    public let massKg: Double       // downward force (kgf)
    public let buoyancyKg: Double   // upward force (kgf)
    public let x: Double
    public let y: Double
}

public struct TrimResult: Sendable, Equatable {
    public let angleDeg: Double        // equilibrium pitch, + = head-up
    public let netBuoyancyKg: Double   // + floats, − sinks
    public let cgX: Double
    public let cgY: Double
    public let cbX: Double
    public let cbY: Double
    public let suitBubbleX: Double     // where the drysuit gas ended up
}

public enum TrimModel {
    /// The adjustable rig. Distances in meters along the body, weights in kg,
    /// gas in liters (1 L ≈ 1 kgf of lift).
    public struct Rig: Sendable, Equatable {
        /// Tank shift along the back; 0 = band at the shoulder blades,
        /// + toward the head (a slipped band after a valve drill is +).
        public var tankShiftM: Double
        /// Net in-water weight of the tank (full HP100 ≈ 5, near-empty ≈ 1).
        public var tankHeavyKg: Double
        public var weightKg: Double
        public var weightX: Double
        public var wingLiftL: Double
        public var suitGasL: Double
        /// Lung inflation offset from mid-breath (−2…+2).
        public var lungL: Double

        public init(tankShiftM: Double = 0, tankHeavyKg: Double = 5,
                    weightKg: Double = 4, weightX: Double = -0.05,
                    wingLiftL: Double = 3, suitGasL: Double = 4, lungL: Double = 0) {
            self.tankShiftM = tankShiftM
            self.tankHeavyKg = tankHeavyKg
            self.weightKg = weightKg
            self.weightX = weightX
            self.wingLiftL = wingLiftL
            self.suitGasL = suitGasL
            self.lungL = lungL
        }
    }

    static let bodyMass = 80.0
    static let bodyBuoyancy = 82.5      // suited body incl. exposure suit lift
    static let suitBaseX = 0.10         // drysuit gas rests over the chest
    static let suitMigration = 0.38     // how far the bubble travels per sin(θ)·2
    static let wingMigration = 0.15     // bladder gas is contained, moves less

    /// Component list at a given pitch (gas positions depend on the pitch).
    public static func components(rig: Rig, pitchDeg: Double) -> [TrimComponent] {
        let s = sin(pitchDeg * .pi / 180)
        let suitX = min(max(suitBaseX + suitMigration * s * 2.0, -0.5), 0.6)
        let wingX = min(max(-0.02 + wingMigration * s * 2.0, -0.25), 0.25)
        return [
            // calibrated so the baseline rig solves level and neutral;
            // both centers sit near the hips, CB ~5 cm above CG (righting arm)
            TrimComponent(name: "bodyMass", massKg: bodyMass, buoyancyKg: 0,
                          x: -0.05, y: -0.01),
            TrimComponent(name: "bodyBuoyancy", massKg: 0, buoyancyKg: bodyBuoyancy,
                          x: -0.06, y: 0.04),
            TrimComponent(name: "lungs", massKg: 0, buoyancyKg: max(rig.lungL, 0),
                          x: 0.22, y: 0.05),
            TrimComponent(name: "tank", massKg: rig.tankHeavyKg, buoyancyKg: 0,
                          x: 0.02 + rig.tankShiftM, y: 0.13),
            TrimComponent(name: "weights", massKg: rig.weightKg, buoyancyKg: 0,
                          x: rig.weightX, y: -0.10),
            TrimComponent(name: "wing", massKg: 0, buoyancyKg: rig.wingLiftL,
                          x: wingX, y: 0.10),
            TrimComponent(name: "suitGas", massKg: 0, buoyancyKg: rig.suitGasL,
                          x: suitX, y: 0.06),
            TrimComponent(name: "fins", massKg: 0.6, buoyancyKg: 0,
                          x: -0.85, y: -0.02),
        ]
    }

    /// Solve the equilibrium pitch. `postureDeg` is a held body attitude —
    /// lifting the head/arching the back biases the pitch, and migrating gas
    /// then amplifies it (the more gas, the bigger the amplification).
    public static func solve(rig: Rig, postureDeg: Double = 0) -> TrimResult {
        var theta = postureDeg
        for _ in 0 ..< 60 {
            let comps = components(rig: rig, pitchDeg: theta)
            let c = centers(comps)
            let dx = c.cb.0 - c.cg.0
            let dy = max(c.cb.1 - c.cg.1, 0.02)   // CB stays above CG when prone
            let target = atan2(dx, dy) * 180 / .pi + postureDeg
            theta = theta * 0.5 + target * 0.5
        }
        let comps = components(rig: rig, pitchDeg: theta)
        let c = centers(comps)
        return TrimResult(angleDeg: theta,
                          netBuoyancyKg: c.b - c.w,
                          cgX: c.cg.0, cgY: c.cg.1,
                          cbX: c.cb.0, cbY: c.cb.1,
                          suitBubbleX: comps.first { $0.name == "suitGas" }?.x ?? 0)
    }

    static func centers(_ comps: [TrimComponent])
        -> (cg: (Double, Double), cb: (Double, Double), w: Double, b: Double) {
        var w = 0.0, b = 0.0
        var gx = 0.0, gy = 0.0, bx = 0.0, by = 0.0
        for c in comps {
            w += c.massKg
            gx += c.massKg * c.x
            gy += c.massKg * c.y
            b += c.buoyancyKg
            bx += c.buoyancyKg * c.x
            by += c.buoyancyKg * c.y
        }
        return ((gx / max(w, 0.001), gy / max(w, 0.001)),
                (bx / max(b, 0.001), by / max(b, 0.001)), w, b)
    }
}
