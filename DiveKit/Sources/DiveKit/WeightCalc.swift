import Foundation

// Ballast transfer calculator.
//
// Starting from ONE measured configuration (the only trustworthy anchor —
// bodies vary too much to compute from scratch), predict the lead needed in a
// different configuration by summing the buoyancy differences:
//
//   lead L balances the rig: L = bodyResidual + suitLift + tankBuoy + plateBuoy
//   so between configs every term contributes (target − reference):
//   floatier target items need MORE lead, sinkier items need LESS,
//   plus a water-density correction (±2.5% of displaced system mass).
//
// Values are catalog estimates (±0.5 kg per item) — always verify with a
// weight check at 3 m with a near-empty tank.

public enum WeightCalc {
    /// Tanks: buoyancy when NEAR-EMPTY (that's what ballast must counter at
    /// the end of the dive) and full mass incl. gas for the density term.
    /// Salt-water catalog values.
    public struct Tank: Sendable, Equatable {
        public let key: String
        public let emptyBuoyancyKg: Double   // + floats (needs lead), − sinks
        public let fullMassKg: Double

        public init(key: String, emptyBuoyancyKg: Double, fullMassKg: Double) {
            self.key = key
            self.emptyBuoyancyKg = emptyBuoyancyKg
            self.fullMassKg = fullMassKg
        }
    }

    public static let tanks: [Tank] = [
        Tank(key: "AL80", emptyBuoyancyKg: 1.7, fullMassKg: 14.2),
        Tank(key: "AL63", emptyBuoyancyKg: 1.0, fullMassKg: 12.0),
        Tank(key: "HP80", emptyBuoyancyKg: -1.5, fullMassKg: 13.4),
        Tank(key: "HP100", emptyBuoyancyKg: -1.0, fullMassKg: 17.4),
        Tank(key: "HP117", emptyBuoyancyKg: -0.9, fullMassKg: 19.6),
        Tank(key: "HP120", emptyBuoyancyKg: -0.7, fullMassKg: 20.4),
        Tank(key: "LP85", emptyBuoyancyKg: -0.4, fullMassKg: 17.0),
        Tank(key: "LP95", emptyBuoyancyKg: -0.9, fullMassKg: 19.0),
        Tank(key: "LP104", emptyBuoyancyKg: -1.4, fullMassKg: 21.0),
        // doubles: 2× cylinders + manifold/bands ≈ −2.5 kg of hardware
        Tank(key: "2xLP85", emptyBuoyancyKg: -0.4 * 2 - 2.5, fullMassKg: 17.0 * 2 + 4),
        Tank(key: "2xHP100", emptyBuoyancyKg: -1.0 * 2 - 2.5, fullMassKg: 17.4 * 2 + 4),
        Tank(key: "12L", emptyBuoyancyKg: -1.5, fullMassKg: 16.0),
        Tank(key: "15L", emptyBuoyancyKg: -2.0, fullMassKg: 20.0),
        Tank(key: "2x12L", emptyBuoyancyKg: -1.5 * 2 - 2.5, fullMassKg: 16.0 * 2 + 4),
    ]

    public static func tank(_ key: String) -> Tank {
        tanks.first { $0.key == key } ?? tanks[0]
    }

    public enum Plate: String, CaseIterable, Sendable {
        case steel, aluminum, soft

        public var buoyancyKg: Double {
            switch self {
            case .steel: -2.7
            case .aluminum: -0.8
            case .soft: 0
            }
        }

        public var massKg: Double {
            switch self {
            case .steel: 3.0
            case .aluminum: 1.0
            case .soft: 0.5
            }
        }
    }

    /// Exposure protection lift (suit + undergarment), kg of buoyancy.
    public enum Suit: Equatable, Sendable {
        case drysuit(undergarmentGrams: Int)   // 150/200/300/400 g/m² fleece
        case wetsuit(mm: Int)
        case none

        public var liftKg: Double {
            switch self {
            case .drysuit(let g):
                // shell ≈ +2, undergarment loft dominates
                return 2.0 + 2.0 + Double(g - 150) * 0.012
            case .wetsuit(let mm):
                return Double(mm) * 0.7
            case .none:
                return 0
            }
        }

        public var massKg: Double {
            switch self {
            case .drysuit: 6
            case .wetsuit(let mm): Double(mm)
            case .none: 0
            }
        }
    }

    public struct Config: Equatable, Sendable {
        public var tankKey: String
        public var plate: Plate
        public var suit: Suit
        public var saltWater: Bool

        public init(tankKey: String, plate: Plate, suit: Suit, saltWater: Bool) {
            self.tankKey = tankKey
            self.plate = plate
            self.suit = suit
            self.saltWater = saltWater
        }
    }

    public struct Breakdown: Equatable, Sendable {
        public let tankDeltaKg: Double
        public let plateDeltaKg: Double
        public let suitDeltaKg: Double
        public let waterDeltaKg: Double
        public let targetKg: Double
    }

    /// Predict ballast for `target` given a measured `referenceWeightKg` in
    /// the `ref` configuration. `bodyKg` feeds the water-density term.
    public static func transfer(referenceWeightKg: Double, bodyKg: Double,
                                ref: Config, target: Config) -> Breakdown {
        let refTank = tank(ref.tankKey)
        let tgtTank = tank(target.tankKey)

        // every term: target − reference (sinkier target ⇒ negative ⇒ less lead)
        let tankDelta = tgtTank.emptyBuoyancyKg - refTank.emptyBuoyancyKg
        let plateDelta = target.plate.buoyancyKg - ref.plate.buoyancyKg
        let suitDelta = target.suit.liftKg - ref.suit.liftKg

        // water density: ballast scales with displaced volume ≈ system mass.
        var waterDelta = 0.0
        if ref.saltWater != target.saltWater {
            let systemMass = bodyKg + tgtTank.fullMassKg + target.plate.massKg
                + target.suit.massKg + max(referenceWeightKg, 0) + 3   // regs etc.
            let correction = systemMass * 0.025
            waterDelta = target.saltWater ? correction : -correction
        }

        let targetKg = max(0, referenceWeightKg + tankDelta + plateDelta
                            + suitDelta + waterDelta)
        return Breakdown(tankDeltaKg: tankDelta, plateDeltaKg: plateDelta,
                         suitDeltaKg: suitDelta, waterDeltaKg: waterDelta,
                         targetKg: targetKg)
    }
}
