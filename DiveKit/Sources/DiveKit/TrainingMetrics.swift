import Foundation

// GUE-oriented skill metrics computed from a dive's sample series.
// Algorithm mirrors the validated Python reference (build_data.py::metrics):
// - flat segments: runs of >= 6 samples with |Δdepth| < 1.5 m/min at depth > 2 m
// - stability: worst (max) population stddev across flat segments
// - violations: seconds spent ascending faster than 9 m/min
// - stopSec: seconds in the last 40% of the dive within ±0.6 m of the 3 m / 6 m stops

public struct TrainingMetrics: Sendable, Equatable {
    public let stabilityM: Double?
    public let ascentViolationSec: Int
    public let maxAscentRateMPerMin: Double
    public let stopSec: Int

    public static func compute(samples: [DiveSample], intervalS: Int) -> TrainingMetrics? {
        let d = samples.map(\.depthM)
        guard d.count >= 12, intervalS > 0 else { return nil }
        let iv = Double(intervalS)

        var segments: [Range<Int>] = []
        var start: Int? = nil
        for i in 1 ..< d.count {
            let rate = abs(d[i] - d[i - 1]) * 60 / iv
            let ok = rate < 1.5 && d[i] > 2.0
            if ok, start == nil {
                start = i - 1
            } else if !ok, let s = start {
                if i - s >= 6 { segments.append(s ..< i) }
                start = nil
            }
        }
        if let s = start, d.count - s >= 6 { segments.append(s ..< d.count) }

        let stability = segments.map { seg -> Double in
            let v = Array(d[seg])
            let mean = v.reduce(0, +) / Double(v.count)
            return (v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(v.count)).squareRoot()
        }.max()

        var violSec = 0
        var maxAsc = 0.0
        for i in 1 ..< d.count {
            let asc = (d[i - 1] - d[i]) * 60 / iv
            maxAsc = max(maxAsc, asc)
            if asc > 9.0 { violSec += intervalS }
        }

        let tail = d[Int(Double(d.count) * 0.6)...]
        let stopSec = tail.filter { abs($0 - 3) <= 0.6 || abs($0 - 6) <= 0.6 }.count * intervalS

        return TrainingMetrics(
            stabilityM: stability.map { ($0 * 100).rounded() / 100 },
            ascentViolationSec: violSec,
            maxAscentRateMPerMin: (maxAsc * 10).rounded() / 10,
            stopSec: stopSec
        )
    }
}
