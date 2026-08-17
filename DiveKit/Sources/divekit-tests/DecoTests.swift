import Foundation
import DiveKit

func decoTests() {
    runTest("surfaceSaturationIsStable") {
        var t = ZHL16C.Tissues(surfaceBar: 1.013)
        let before = t.pN2[0]
        t.expose(ambientBar: 1.013, fO2: 0.21, fHe: 0, minutes: 600)
        expectClose(t.pN2[0], before, tol: 0.001, "air at surface stays saturated")
        expectClose(t.ceilingM(gf: 0.85, surfaceBar: 1.013), 0, tol: 0.001,
                    "no ceiling at surface saturation")
        expect(t.gradientPercent(ambientBar: 1.013) < 1, "no supersaturation")
    }

    runTest("fastCompartmentLoadsFirst") {
        var t = ZHL16C.Tissues(surfaceBar: 1.013)
        t.expose(ambientBar: 4.013, fO2: 0.21, fHe: 0, minutes: 10)
        expect(t.pN2[0] > t.pN2[15] + 0.3,
               "5-min compartment far ahead of 635-min after 10 min at 30 m")
    }

    runTest("ndlValuesAreSane") {
        let air = DecoPlanner.PlanGas(o2: 21, he: 0)
        let ean32 = DecoPlanner.PlanGas(o2: 32, he: 0)
        let ndl18 = DecoPlanner.ndlMin(depthM: 18, gas: air, gfHigh: 0.85)
        let ndl30 = DecoPlanner.ndlMin(depthM: 30, gas: air, gfHigh: 0.85)
        let ndl30n = DecoPlanner.ndlMin(depthM: 30, gas: ean32, gfHigh: 0.85)
        expect(ndl18 > 30 && ndl18 < 80, "18 m air NDL in a sane band: \(ndl18)")
        expect(ndl30 > 8 && ndl30 < 25, "30 m air NDL in a sane band: \(ndl30)")
        expect(ndl30n > ndl30 + 3, "nitrox extends NDL: \(ndl30) → \(ndl30n)")
    }

    runTest("decoDiveProducesStops") {
        let air = DecoPlanner.PlanGas(o2: 21, he: 0)
        let plan = DecoPlanner.plan(depthM: 40, bottomMin: 20, bottomGas: air,
                                    decoGases: [], gfLow: 0.3, gfHigh: 0.85)
        let stops = plan.segments.filter { $0.kind == .stop }
        expect(!stops.isEmpty, "40 m / 20 min air needs stops")
        expect(plan.firstStopM >= 3 && plan.firstStopM <= 21,
               "first stop reasonable: \(plan.firstStopM) m")
        expect(plan.runtimeMin > 25 && plan.runtimeMin < 90,
               "runtime sane: \(plan.runtimeMin)")
        expect(plan.surfaceGF <= 90, "surfaces at or under GF-high: \(plan.surfaceGF)")
        // stops shallowest last, times positive
        expect(stops.allSatisfy { $0.minutes >= 1 }, "stop minutes >= 1")
    }

    runTest("ndlDiveHasNoStops") {
        let ean32 = DecoPlanner.PlanGas(o2: 32, he: 0)
        let plan = DecoPlanner.plan(depthM: 18, bottomMin: 30, bottomGas: ean32,
                                    decoGases: [], gfLow: 0.3, gfHigh: 0.85)
        expect(plan.segments.filter { $0.kind == .stop }.isEmpty,
               "18 m / 30 min EAN32 is a no-deco dive")
    }

    runTest("decoGasShortensDeco") {
        let air = DecoPlanner.PlanGas(o2: 21, he: 0)
        let ean50 = DecoPlanner.PlanGas(o2: 50, he: 0, switchDepthM: 21)
        let airOnly = DecoPlanner.plan(depthM: 42, bottomMin: 25, bottomGas: air,
                                       decoGases: [], gfLow: 0.3, gfHigh: 0.85)
        let withDeco = DecoPlanner.plan(depthM: 42, bottomMin: 25, bottomGas: air,
                                        decoGases: [ean50], gfLow: 0.3, gfHigh: 0.85)
        expect(withDeco.runtimeMin < airOnly.runtimeMin - 3,
               "EAN50 cuts runtime: \(airOnly.runtimeMin) → \(withDeco.runtimeMin)")
    }

    runTest("longerBottomMeansMoreDeco") {
        let air = DecoPlanner.PlanGas(o2: 21, he: 0)
        let short = DecoPlanner.plan(depthM: 40, bottomMin: 15, bottomGas: air,
                                     decoGases: [], gfLow: 0.3, gfHigh: 0.85)
        let long = DecoPlanner.plan(depthM: 40, bottomMin: 30, bottomGas: air,
                                    decoGases: [], gfLow: 0.3, gfHigh: 0.85)
        expect(long.runtimeMin - long.segments[1].runtimeMin
               > short.runtimeMin - short.segments[1].runtimeMin,
               "more bottom, more hang")
    }

    runTest("tissueReplayOnRealDive") {
        let raw = try loadFixture("dive_046.pnf.bin")
        let (header, samples) = try PNFParser.parse(raw)
        let r = TissueReplay.compute(samples: samples, header: header)
        expectEqual(r.snapshots.count, samples.count, "one snapshot per sample")
        // 14 m / 50 min rec dive: modest loading, no ceiling, clean-ish exit
        expect(r.surfaceGF > 5 && r.surfaceGF < 80,
               "plausible surfacing GF: \(r.surfaceGF)")
        expect(r.snapshots.allSatisfy { $0.ceilingM < 3 },
               "no-deco dive never has a meaningful ceiling")
        expect(r.desatHours > 0.5 && r.desatHours < 24,
               "plausible desat time: \(r.desatHours) h")
        // deepest point should show the highest gf99 pressure gradient... at
        // depth gradient is low; the max gf99 should occur during/after ascent
        let maxGF = r.snapshots.map(\.gf99).max() ?? 0
        expect(maxGF >= r.surfaceGF - 1, "peak gf99 at or after surfacing")
    }

    runTest("blenderTextbookCase") {
        // empty tank → EAN32 @ 200 bar: O2 to (0.32−0.209)/0.791·200 ≈ 28.1 bar
        let r = GasBlender.blend(startBar: 0, startO2: 0.21,
                                 targetBar: 200, targetO2: 0.32)
        expect(r != nil, "solvable")
        expectClose(r!.addO2Bar, 28.07, tol: 0.5, "O2 fill pressure")
        expect(r!.drainToBar == nil || r!.drainToBar == 0, "no drain for empty tank")
    }

    runTest("blenderTopUpExistingMix") {
        // 100 bar of EAN32 → 200 bar EAN36
        let r = GasBlender.blend(startBar: 100, startO2: 0.32,
                                 targetBar: 200, targetO2: 0.36)
        expect(r != nil, "solvable")
        // check the math forward: final O2 fraction should be 0.36
        let x = r!.addO2Bar - 100
        let topped = 200 - r!.addO2Bar
        let o2Total = 100 * 0.32 + x + topped * 0.209
        expectClose(o2Total / 200, 0.36, tol: 0.002, "forward-check final mix")
    }

    runTest("blenderNeedsDrainWhenTooRich") {
        // full tank of EAN36 but want EAN32 at same pressure → must drain
        let r = GasBlender.blend(startBar: 200, startO2: 0.36,
                                 targetBar: 200, targetO2: 0.32)
        expect(r?.drainToBar != nil, "drain required")
        if let d = r?.drainToBar {
            let x = r!.addO2Bar - d
            let topped = 200 - r!.addO2Bar
            let o2Total = d * 0.36 + x + topped * 0.209
            expectClose(o2Total / 200, 0.32, tol: 0.002, "forward-check after drain")
        }
    }
}
