import Foundation
import DiveKit

struct SummaryRow: Decodable {
    let n: Int
    let maxDepth: Double
    let nSamples: Int
    let gfLow: Int
    let gfHigh: Int
    let mode: String
    let surfaceMbar: Int
}

func metricsAndPhysicsTests() {
    // Golden values computed by build_data.py for dive 46
    runTest("metricsMatchPythonForDive46") {
        let raw = try loadFixture("dive_046.pnf.bin")
        let (header, samples) = try PNFParser.parse(raw)
        guard let m = TrainingMetrics.compute(samples: samples,
                                              intervalS: header.intervalMs / 1000) else {
            expect(false, "metrics should not be nil")
            return
        }
        expectClose(m.stabilityM ?? -1, 0.34, tol: 0.005, "stability")
        expectEqual(m.ascentViolationSec, 10, "ascentViolationSec")
        expectClose(m.maxAscentRateMPerMin, 11.9, tol: 0.05, "maxAscentRate")
        expectEqual(m.stopSec, 80, "stopSec")
    }

    runTest("metricsNilForTinyDives") {
        expect(TrainingMetrics.compute(samples: [], intervalS: 10) == nil, "empty -> nil")
    }

    runTest("airDensityAt14mSalt") {
        let d = GasPhysics.densityGPerL(o2: 21, he: 0, depthM: 14.0,
                                        waterDensity: 1020, surfaceMbar: 1015)
        expectClose(d, 3.13, tol: 0.05, "air density @14m salt")
    }

    runTest("endIsDepthForAirAndReducedForTrimix") {
        expectClose(GasPhysics.endM(depthM: 30, he: 0), 30, tol: 0.001, "air END")
        expect(GasPhysics.endM(depthM: 30, he: 35) < 20, "trimix END reduced")
    }

    // Full-logbook regression: every one of the 47 real dives
    runTest("allFortySevenDivesMatchSummary") {
        let summary = try JSONDecoder().decode([SummaryRow].self,
            from: loadFixture("all_dives_summary.golden.json"))
        expectEqual(summary.count, 47, "summary rows")
        for row in summary {
            let name = String(format: "AllDives/dive_%03d.pnf.bin", row.n)
            let (h, s) = try PNFParser.parse(loadFixture(name))
            expectEqual(s.count, row.nSamples, "dive \(row.n) nSamples")
            expectClose(s.map(\.depthM).max() ?? -1, row.maxDepth, tol: 0.005, "dive \(row.n) maxDepth")
            expectEqual(h.gfLow, row.gfLow, "dive \(row.n) gfLow")
            expectEqual(h.gfHigh, row.gfHigh, "dive \(row.n) gfHigh")
            expectEqual(h.mode.rawValue, row.mode, "dive \(row.n) mode")
            expectEqual(h.surfaceMbar, row.surfaceMbar, "dive \(row.n) surfaceMbar")
        }
    }
}
