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
    let startTs: UInt32
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
            expectEqual(h.startTimestamp, row.startTs, "dive \(row.n) startTimestamp")
        }
    }
}

func gnssTests() {
    runTest("gnssParsedFromSyntheticRecord9") {
        // take a real dive, splice in opening/closing record 9 with a fix,
        // and bump the log version to 17
        var raw = [UInt8](try loadFixture("dive_046.pnf.bin"))
        var idxO4 = -1
        for i in stride(from: 0, to: raw.count, by: 32) where raw[i] == 0x14 { idxO4 = i }
        expect(idxO4 >= 0, "found opening 4")
        raw[idxO4 + 16] = 17   // log version

        func record9(_ type: UInt8, lat: Int32, lon: Int32) -> [UInt8] {
            var r = [UInt8](repeating: 0, count: 32)
            r[0] = type; r[16] = 3
            for (o, v) in [(21, lat), (25, lon)] {
                let u = UInt32(bitPattern: v)
                r[o] = UInt8(u >> 24 & 0xFF); r[o+1] = UInt8(u >> 16 & 0xFF)
                r[o+2] = UInt8(u >> 8 & 0xFF); r[o+3] = UInt8(u & 0xFF)
            }
            return r
        }
        // 29.53512°N 121.03427°E entry / slightly different exit
        raw.insert(contentsOf: record9(0x19, lat: 2953512, lon: 12103427), at: idxO4 + 32)
        raw.append(contentsOf: record9(0x29, lat: 2953600, lon: 12103500))

        let (h, _) = try PNFParser.parse(Data(raw))
        expectClose(h.entryLocation?.latitude ?? 0, 29.53512, tol: 1e-6, "entry lat")
        expectClose(h.entryLocation?.longitude ?? 0, 121.03427, tol: 1e-6, "entry lon")
        expectClose(h.exitLocation?.latitude ?? 0, 29.536, tol: 1e-6, "exit lat")
    }

    runTest("gnssNilForPeregrineDives") {
        let (h, _) = try PNFParser.parse(try loadFixture("dive_046.pnf.bin"))
        expect(h.entryLocation == nil && h.exitLocation == nil, "no GNSS on Peregrine")
    }
}
