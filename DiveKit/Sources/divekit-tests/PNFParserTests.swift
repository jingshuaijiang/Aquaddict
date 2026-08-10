import Foundation
import DiveKit

struct Golden: Decodable {
    struct H: Decodable {
        let imperial: Bool
        let logversion: Int
        let interval_ms: Int
        let gf_low: Int
        let gf_high: Int
        let decomodel: String
        let surface_mbar: Int
        let density: Int
        let mode: String
        let n_samples: Int
    }
    struct S: Decodable {
        let time_s: Int
        let depth_m: Double
        let temp_c: Double
        let ndl_min: Int
        let tts_min: Int
        let deco_stop: Int
        let avg_ppo2: Double
        let o2: Int
        let he: Int
        let cns: Int
    }
    let header: H
    let samples: [S]
}

func testGoldenDive(_ name: String) {
    runTest("parsesGoldenDive(\(name))") {
        let raw = try loadFixture("\(name).pnf.bin")
        let golden = try JSONDecoder().decode(Golden.self, from: loadFixture("\(name).golden.json"))
        let (header, samples) = try PNFParser.parse(raw)

        expectEqual(header.gfLow, golden.header.gf_low, "gfLow")
        expectEqual(header.gfHigh, golden.header.gf_high, "gfHigh")
        expectEqual(header.surfaceMbar, golden.header.surface_mbar, "surfaceMbar")
        expectEqual(header.waterDensity, golden.header.density, "waterDensity")
        expectEqual(header.intervalMs, golden.header.interval_ms, "intervalMs")
        expectEqual(header.logVersion, golden.header.logversion, "logVersion")
        expectEqual(header.imperial, golden.header.imperial, "imperial")
        expectEqual(header.mode.rawValue, golden.header.mode, "mode")
        expectEqual(header.decoModel.rawValue, golden.header.decomodel, "decoModel")
        expectEqual(samples.count, golden.header.n_samples, "sample count")

        for (s, g) in zip(samples, golden.samples) {
            expectEqual(s.timeS, g.time_s, "timeS@\(g.time_s)")
            expectClose(s.depthM, g.depth_m, tol: 0.005, "depthM@\(g.time_s)")
            expectClose(s.tempC, g.temp_c, tol: 0.05, "tempC@\(g.time_s)")
            expectEqual(s.ndlMin, g.ndl_min, "ndl@\(g.time_s)")
            expectEqual(s.ttsMin, g.tts_min, "tts@\(g.time_s)")
            expectEqual(s.decoStopM, g.deco_stop, "decoStop@\(g.time_s)")
            expectClose(s.avgPPO2, g.avg_ppo2, tol: 0.005, "avgPPO2@\(g.time_s)")
            expectEqual(s.o2, g.o2, "o2@\(g.time_s)")
            expectEqual(s.he, g.he, "he@\(g.time_s)")
            expectEqual(s.cns, g.cns, "cns@\(g.time_s)")
        }
    }
}

func pnfParserTests() {
    testGoldenDive("dive_000")
    testGoldenDive("dive_031")
    testGoldenDive("dive_046")

    runTest("throwsOnTruncatedData") {
        do {
            _ = try PNFParser.parse(Data([0x10, 0xFF]))
            expect(false, "should have thrown")
        } catch PNFError.truncated {
            // expected
        }
    }
}
