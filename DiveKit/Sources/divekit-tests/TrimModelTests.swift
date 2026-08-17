import Foundation
import DiveKit

func trimModelTests() {
    runTest("balancedRigIsFlat") {
        // baseline rig should trim out close to level and near neutral
        let r = TrimModel.solve(rig: TrimModel.Rig())
        expect(abs(r.angleDeg) < 6, "near-level, got \(r.angleDeg)°")
        expect(abs(r.netBuoyancyKg) < 3, "near-neutral, got \(r.netBuoyancyKg) kg")
    }

    runTest("valveDrillTankForwardGoesHeadDown") {
        let base = TrimModel.solve(rig: TrimModel.Rig())
        var rig = TrimModel.Rig()
        rig.tankShiftM = 0.08   // band slipped toward the head
        let shifted = TrimModel.solve(rig: rig)
        expect(shifted.angleDeg < base.angleDeg - 2,
               "tank forward pitches head-down: \(base.angleDeg)° → \(shifted.angleDeg)°")
    }

    runTest("gassySuitAmplifiesHeadUpPosture") {
        var lean = TrimModel.Rig()
        lean.suitGasL = 1
        var gassy = TrimModel.Rig()
        gassy.suitGasL = 8
        let leanUp = TrimModel.solve(rig: lean, postureDeg: 10)
        let gassyUp = TrimModel.solve(rig: gassy, postureDeg: 10)
        expect(gassyUp.angleDeg > leanUp.angleDeg + 6,
               "same posture, more gas, bigger tilt: \(leanUp.angleDeg)° vs \(gassyUp.angleDeg)°")
        expect(gassyUp.suitBubbleX > 0.3,
               "bubble migrated toward the head, x=\(gassyUp.suitBubbleX)")
    }

    runTest("weightsAtFeetGoFeetDown") {
        var rig = TrimModel.Rig()
        rig.weightX = -0.45
        let r = TrimModel.solve(rig: rig)
        expect(r.angleDeg > 3, "CG feetward → head rises: \(r.angleDeg)°")
    }

    runTest("inhaleAddsLift") {
        var rig = TrimModel.Rig()
        rig.lungL = 2
        let inhaled = TrimModel.solve(rig: rig)
        let base = TrimModel.solve(rig: TrimModel.Rig())
        expectClose(inhaled.netBuoyancyKg - base.netBuoyancyKg, 2, tol: 0.01,
                    "2L inhale ≈ +2 kg lift")
    }
}
