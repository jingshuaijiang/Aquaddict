import Foundation
import DiveKit

func calorieTests() {
    runTest("metFallbackOnRealDive") {
        // dive 46: 50 min at 12-14 °C, no AI data → MET path + thermal
        let raw = try loadFixture("dive_046.pnf.bin")
        let (header, samples) = try PNFParser.parse(raw)
        guard let e = CalorieEstimator.estimate(samples: samples,
                                                intervalS: header.intervalMs / 1000,
                                                tankL: nil, bodyKg: 75) else {
            expect(false, "estimate available")
            return
        }
        expectEqual(e.source.rawValue, "met", "no AI → MET path")
        expect(e.totalKcal > 250 && e.totalKcal < 700,
               "50 min cold dive in a plausible band: \(e.totalKcal)")
        expect(e.thermalKcal > 40, "cold water adds real thermal cost: \(e.thermalKcal)")
        expect(e.avgKcalPerHour > 300 && e.avgKcalPerHour < 800,
               "hourly rate sane: \(e.avgKcalPerHour)")
    }

    runTest("coldBurnsMoreThanWarm") {
        let raw = try loadFixture("dive_046.pnf.bin")
        let (header, samples) = try PNFParser.parse(raw)
        let cold = CalorieEstimator.estimate(samples: samples,
                                             intervalS: header.intervalMs / 1000,
                                             tankL: nil, bodyKg: 75)!
        // same dive with tropical water
        let warm = samples.map {
            DiveSample(timeS: $0.timeS, depthM: $0.depthM, tempC: 29,
                       ndlMin: $0.ndlMin, ttsMin: $0.ttsMin, decoStopM: $0.decoStopM,
                       avgPPO2: $0.avgPPO2, o2: $0.o2, he: $0.he, cns: $0.cns)
        }
        let tropical = CalorieEstimator.estimate(samples: warm,
                                                 intervalS: header.intervalMs / 1000,
                                                 tankL: nil, bodyKg: 75)!
        expect(cold.totalKcal > tropical.totalKcal + 40,
               "cold \(cold.totalKcal) vs warm \(tropical.totalKcal)")
        expectClose(tropical.thermalKcal, 0, tol: 0.01, "no thermal cost at 29 °C")
    }

    runTest("ventilationPathTracksBreathing") {
        // synthetic 30-min dive at 10 m with AI data: 200 → 100 bar on 12 L
        func mk(rate: Double) -> [DiveSample] {
            (0 ... 180).map { i in
                DiveSample(timeS: i * 10, depthM: 10, tempC: 29, ndlMin: 90,
                           ttsMin: 1, decoStopM: 0, avgPPO2: 0.3, o2: 21, he: 0,
                           cns: 0, tank1Bar: 200 - rate * Double(i))
            }
        }
        let calm = CalorieEstimator.estimate(samples: mk(rate: 0.3), intervalS: 10,
                                             tankL: 12, bodyKg: 75)!
        let heavy = CalorieEstimator.estimate(samples: mk(rate: 0.6), intervalS: 10,
                                              tankL: 12, bodyKg: 75)!
        expectEqual(calm.source.rawValue, "ventilation", "AI data → ventilation path")
        expect(heavy.totalKcal > calm.totalKcal * 1.5,
               "double the gas, much more work: \(calm.totalKcal) vs \(heavy.totalKcal)")
        // sanity on magnitude: 1.8 bar/min · 12L / 2 ata = 10.8 L/min RMV →
        // VO2 ≈ 0.47 (VE 22.5 @2 ata) → ~2.3 kcal/min ≈ 70 kcal over 30 min
        expect(calm.totalKcal > 40 && calm.totalKcal < 220,
               "calm magnitude sane: \(calm.totalKcal)")
    }

    runTest("transmitterDropoutsDontDeleteWork") {
        func mk(dropout: Bool) -> [DiveSample] {
            (0 ... 180).map { i in
                DiveSample(timeS: i * 10, depthM: 10, tempC: 29, ndlMin: 90,
                           ttsMin: 1, decoStopM: 0, avgPPO2: 0.3, o2: 21, he: 0,
                           cns: 0,
                           tank1Bar: (dropout && i % 3 == 0)
                               ? nil : 200 - 0.5 * Double(i))
            }
        }
        let full = CalorieEstimator.estimate(samples: mk(dropout: false),
                                             intervalS: 10, tankL: 12, bodyKg: 75)!
        let holey = CalorieEstimator.estimate(samples: mk(dropout: true),
                                              intervalS: 10, tankL: 12, bodyKg: 75)!
        expect(abs(full.totalKcal - holey.totalKcal) < full.totalKcal * 0.15,
               "1/3 dropout ≈ same total: \(full.totalKcal) vs \(holey.totalKcal)")
    }

    runTest("doublesTankDoublesWork") {
        let samples: [DiveSample] = (0 ... 180).map { i in
            DiveSample(timeS: i * 10, depthM: 10, tempC: 29, ndlMin: 90,
                       ttsMin: 1, decoStopM: 0, avgPPO2: 0.3, o2: 21, he: 0,
                       cns: 0, tank1Bar: 200 - 0.3 * Double(i))
        }
        let single = CalorieEstimator.estimate(samples: samples, intervalS: 10,
                                               tankL: 11.1, bodyKg: 75)!
        let doubles = CalorieEstimator.estimate(samples: samples, intervalS: 10,
                                                tankL: 25.8, bodyKg: 75)!
        expect(doubles.totalKcal > single.totalKcal * 1.6,
               "same bar-drop on doubles = far more gas & work: "
               + "\(single.totalKcal) vs \(doubles.totalKcal)")
    }
}
