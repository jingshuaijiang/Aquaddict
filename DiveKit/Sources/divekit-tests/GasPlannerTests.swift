import Foundation
import DiveKit

// Hand-checked values from standard dive-planning references.
func gasPlannerTests() {
    runTest("modForStandardMixes") {
        // EAN32 @ ppO2 1.4: (1.4/0.32 − 1) × 10 = 33.75 m
        expectClose(GasPlanner.modM(o2Percent: 32, ppO2Limit: 1.4), 33.75, tol: 0.01, "EAN32 MOD")
        // Air @ 1.4: (1.4/0.21 − 1) × 10 = 56.67 m
        expectClose(GasPlanner.modM(o2Percent: 21, ppO2Limit: 1.4), 56.67, tol: 0.01, "Air MOD")
        // O2 @ 1.6: 6 m
        expectClose(GasPlanner.modM(o2Percent: 100, ppO2Limit: 1.6), 6.0, tol: 0.01, "O2 MOD")
    }

    runTest("bestMix") {
        // 30 m @ 1.4: 1.4/4.0 = 35%
        expectEqual(GasPlanner.bestO2Percent(depthM: 30, ppO2Limit: 1.4), 35, "best O2 @30m")
        // END 30 m at 45 m: 1 − 40/55 = 27.27% → 28% He
        expectEqual(GasPlanner.minHePercent(depthM: 45, endLimitM: 30), 28, "min He @45m")
        expectEqual(GasPlanner.minHePercent(depthM: 20, endLimitM: 30), 0, "no He needed @20m")
    }

    runTest("standardGasSelection") {
        expectEqual(GasPlanner.standardGas(forDepthM: 25)?.name, "EAN32", "25m → EAN32")
        expectEqual(GasPlanner.standardGas(forDepthM: 35)?.name, "25/25", "35m → 25/25")
        expectEqual(GasPlanner.standardGas(forDepthM: 50)?.name, "21/35", "50m → 21/35")
        expect(GasPlanner.standardGas(forDepthM: 80) == nil, "80m beyond standard range")
    }

    runTest("minDecoLadder") {
        // 30 m: first stop 15 m, then 12/9/6/3 — five 1-minute stops
        let stops = GasPlanner.minDecoStops(maxDepthM: 30)
        expectEqual(stops.map(\.depthM), [15, 12, 9, 6, 3], "30m ladder")
        expect(stops.allSatisfy { $0.minutes == 1 }, "1 min each")
        expectEqual(GasPlanner.minDecoStops(maxDepthM: 8).count, 0, "shallow → no ladder")
    }

    runTest("minGas") {
        // 30 m: (1 + 10) min × 2.5 avg ata × 30 L/min = 825 L; /24 L twinset ≈ 34.4 bar
        expectClose(GasPlanner.minGasL(depthM: 30), 825, tol: 0.5, "min gas L @30m")
        expectClose(GasPlanner.minGasBar(depthM: 30, tankL: 24), 34.4, tol: 0.1, "min gas bar D12")
        // 18 m on an AL80 (11.1 L): (1+6) × 1.9 × 30 = 399 L → 35.9 bar
        expectClose(GasPlanner.minGasBar(depthM: 18, tankL: 11.1), 35.9, tol: 0.1, "min gas bar AL80")
    }

    runTest("ruleOfThirds") {
        let plan = GasPlanner.thirds(fillBar: 200, minGasBar: 35)
        expectClose(plan.usableBar, 165, tol: 0.01, "usable")
        expectClose(plan.thirdBar, 55, tol: 0.01, "third")
        expectClose(plan.turnPressureBar, 145, tol: 0.01, "turn pressure")
    }

    runTest("bottomGas") {
        // 20 min @ 30 m @ 15 L/min: 20 × 4 × 15 = 1200 L
        expectClose(GasPlanner.bottomGasL(depthM: 30, minutes: 20, sacLPerMin: 15),
                    1200, tol: 0.5, "bottom gas")
    }
}
