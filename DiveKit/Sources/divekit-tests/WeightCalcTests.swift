import Foundation
import DiveKit

func weightCalcTests() {
    let drysuit200 = WeightCalc.Suit.drysuit(undergarmentGrams: 200)

    runTest("identityTransferChangesNothing") {
        let cfg = WeightCalc.Config(tankKey: "AL80", plate: .steel,
                                    suit: drysuit200, saltWater: true)
        let r = WeightCalc.transfer(referenceWeightKg: 12.7, bodyKg: 75,
                                    ref: cfg, target: cfg)
        expectClose(r.targetKg, 12.7, tol: 0.001, "same config, same lead")
    }

    runTest("al80ToHp100NeedsLessLead") {
        // AL80 empty +1.7, HP100 empty −1.0 → 2.7 kg less lead
        var cfg = WeightCalc.Config(tankKey: "AL80", plate: .steel,
                                    suit: drysuit200, saltWater: true)
        var tgt = cfg
        tgt.tankKey = "HP100"
        let r = WeightCalc.transfer(referenceWeightKg: 12.7, bodyKg: 75,
                                    ref: cfg, target: tgt)
        expectClose(r.tankDeltaKg, -2.7, tol: 0.001, "steel sinks → less lead")
        expectClose(r.targetKg, 10.0, tol: 0.001, "12.7 − 2.7")
        _ = cfg
    }

    runTest("singleToDoublesDropsBig") {
        // user's scenario: single HP100 → double HP100
        let cfg = WeightCalc.Config(tankKey: "HP100", plate: .steel,
                                    suit: drysuit200, saltWater: true)
        var tgt = cfg
        tgt.tankKey = "2xHP100"
        let r = WeightCalc.transfer(referenceWeightKg: 10, bodyKg: 75,
                                    ref: cfg, target: tgt)
        // −1.0 → −7.0: 6 kg less lead
        expectClose(r.tankDeltaKg, -6.0, tol: 0.001, "doubles sink 6 kg more")
        expectClose(r.targetKg, 4.0, tol: 0.001, "target")
    }

    runTest("saltToFreshRemovesAboutTwoPointFivePercent") {
        let cfg = WeightCalc.Config(tankKey: "HP100", plate: .steel,
                                    suit: drysuit200, saltWater: true)
        var tgt = cfg
        tgt.saltWater = false
        let r = WeightCalc.transfer(referenceWeightKg: 12, bodyKg: 75,
                                    ref: cfg, target: tgt)
        expect(r.waterDeltaKg < -2.0 && r.waterDeltaKg > -3.5,
               "fresh water sheds ~2-3 kg, got \(r.waterDeltaKg)")
        expectClose(r.targetKg, 12 + r.waterDeltaKg, tol: 0.001, "sum")
    }

    runTest("warmerUndergarmentAddsLead") {
        let cfg = WeightCalc.Config(tankKey: "HP100", plate: .steel,
                                    suit: .drysuit(undergarmentGrams: 200), saltWater: true)
        var tgt = cfg
        tgt.suit = .drysuit(undergarmentGrams: 400)
        let r = WeightCalc.transfer(referenceWeightKg: 10, bodyKg: 75,
                                    ref: cfg, target: tgt)
        expectClose(r.suitDeltaKg, 2.4, tol: 0.001, "200→400 g adds 2.4 kg")
    }

    runTest("userMeasuredScenario28lbSingleSaltTo6lbDoublesFresh") {
        // real-world anchor: drysuit 200 g + single HP100 + salt = 28 lb;
        // the same diver measured 6 lb (2.7 kg) on double HP100 in fresh.
        let ref = WeightCalc.Config(tankKey: "HP100", plate: .steel,
                                    suit: drysuit200, saltWater: true)
        let tgt = WeightCalc.Config(tankKey: "2xHP100", plate: .steel,
                                    suit: drysuit200, saltWater: false)
        let r = WeightCalc.transfer(referenceWeightKg: 12.7, bodyKg: 75,
                                    ref: ref, target: tgt)
        expect(abs(r.targetKg - 2.7) < 1.5,
               "predicts close to the measured 6 lb: \(r.targetKg) kg")
    }
}
