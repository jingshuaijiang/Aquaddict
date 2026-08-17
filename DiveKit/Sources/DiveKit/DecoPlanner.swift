import Foundation

// Full decompression planner: ZHL-16C + gradient factors, multi-gas.
//
// Conventions (GUE-flavored): bottom time includes the descent; descend at
// 18 m/min, ascend at 9 m/min; stops on 3 m multiples, 1-minute resolution;
// deco gases switch at their configured depth on the way up. The GF slope
// runs from GF-low at the first stop to GF-high at the surface.

public enum DecoPlanner {
    public struct PlanGas: Sendable, Equatable {
        public let o2: Int
        public let he: Int
        public let switchDepthM: Double   // 0 for the bottom gas

        public init(o2: Int, he: Int, switchDepthM: Double = 0) {
            self.o2 = o2
            self.he = he
            self.switchDepthM = switchDepthM
        }

        public var name: String {
            if o2 == 100 { return "O₂" }
            if he > 0 { return "\(o2)/\(he)" }
            if o2 == 21 { return "Air" }
            return "EAN\(o2)"
        }
    }

    public enum SegmentKind: String, Sendable {
        case descent, bottom, ascent, stop
    }

    public struct Segment: Sendable, Equatable {
        public let kind: SegmentKind
        public let depthM: Double        // segment end depth (stops: the stop depth)
        public let minutes: Double
        public let gas: PlanGas
        public let runtimeMin: Double    // runtime at segment end
    }

    public struct Plan: Sendable, Equatable {
        public let segments: [Segment]
        public let runtimeMin: Double
        public let decoMin: Double                    // time above bottom phase
        public let firstStopM: Double                 // 0 when no-deco
        public let gasUsedL: [(gas: PlanGas, liters: Double)]
        public let surfaceGF: Double

        public static func == (l: Plan, r: Plan) -> Bool {
            l.segments == r.segments && l.runtimeMin == r.runtimeMin
        }
    }

    static let descentRate = 18.0   // m/min
    static let ascentRate = 9.0     // m/min

    /// No-deco limit at a depth on a gas (direct ascent stays within GF-high).
    public static func ndlMin(depthM: Double, gas: PlanGas,
                              gfHigh: Double, surfaceBar: Double = 1.013) -> Int {
        var tissues = ZHL16C.Tissues(surfaceBar: surfaceBar)
        let ambient = surfaceBar + depthM / 10.0
        // include the descent
        descend(&tissues, from: 0, to: depthM, gas: gas, surfaceBar: surfaceBar)
        for minute in 0 ..< 200 {
            tissues.expose(ambientBar: ambient, fO2: Double(gas.o2) / 100.0,
                           fHe: Double(gas.he) / 100.0, minutes: 1)
            if tissues.ceilingM(gf: gfHigh, surfaceBar: surfaceBar) > 0 {
                return minute
            }
        }
        return 199
    }

    public static func plan(depthM: Double, bottomMin: Double, bottomGas: PlanGas,
                            decoGases: [PlanGas], gfLow: Double, gfHigh: Double,
                            sacLPerMin: Double = 20, surfaceBar: Double = 1.013) -> Plan {
        var tissues = ZHL16C.Tissues(surfaceBar: surfaceBar)
        var segments: [Segment] = []
        var runtime = 0.0
        var gasUsed: [String: Double] = [:]
        var gas = bottomGas

        func consume(_ gas: PlanGas, depth: Double, minutes: Double) {
            let ata = surfaceBar + depth / 10.0
            gasUsed[gas.name, default: 0] += ata * minutes * sacLPerMin
        }

        // descent (counts into bottom time)
        let descentMin = depthM / descentRate
        descend(&tissues, from: 0, to: depthM, gas: gas, surfaceBar: surfaceBar)
        runtime += descentMin
        consume(gas, depth: depthM / 2, minutes: descentMin)
        segments.append(Segment(kind: .descent, depthM: depthM, minutes: descentMin,
                                gas: gas, runtimeMin: runtime))

        // bottom
        let bottomPhase = max(0, bottomMin - descentMin)
        tissues.expose(ambientBar: surfaceBar + depthM / 10.0,
                       fO2: Double(gas.o2) / 100.0, fHe: Double(gas.he) / 100.0,
                       minutes: bottomPhase)
        runtime += bottomPhase
        consume(gas, depth: depthM, minutes: bottomPhase)
        segments.append(Segment(kind: .bottom, depthM: depthM, minutes: bottomPhase,
                                gas: gas, runtimeMin: runtime))

        // first stop from GF-low ceiling
        var depth = depthM
        let rawCeiling = tissues.ceilingM(gf: gfLow, surfaceBar: surfaceBar)
        var firstStop = ceil(rawCeiling / 3.0) * 3.0
        let gfSlopeStart = firstStop   // GF interpolation anchor

        func gfAt(_ d: Double) -> Double {
            guard gfSlopeStart > 0.5 else { return gfHigh }
            let t = max(0, min(1, d / gfSlopeStart))
            return gfHigh + (gfLow - gfHigh) * t
        }

        func maybeSwitchGas(at d: Double) {
            if let better = decoGases
                .filter({ $0.switchDepthM >= d - 0.01 })
                .min(by: { $0.switchDepthM < $1.switchDepthM }),
                better != gas {
                gas = better
            }
        }

        var decoStart = runtime
        var stops: [Segment] = []
        var totalDeco = 0.0

        // ascend through stops
        var guardCount = 0
        while depth > 0.01, guardCount < 500 {
            guardCount += 1
            let nextStop = firstStop > 0
                ? max(0, min(depth - 3.0, firstStop))
                : 0
            // target of this ascent leg: the deeper of nextStop or ceiling stop
            let ceilNow = tissues.ceilingM(gf: gfAt(max(nextStop, 0)),
                                           surfaceBar: surfaceBar)
            var target = max(nextStop, ceil(ceilNow / 3.0) * 3.0)
            if target >= depth { target = max(0, depth - 3.0) }

            // ascend
            let ascMin = (depth - target) / ascentRate
            ascendExpose(&tissues, from: depth, to: target, gas: gas,
                         surfaceBar: surfaceBar)
            runtime += ascMin
            consume(gas, depth: (depth + target) / 2, minutes: ascMin)
            depth = target
            maybeSwitchGas(at: depth)
            if depth <= 0.01 { break }

            // hold until the next 3 m is allowed
            let next = max(0, depth - 3.0)
            var held = 0.0
            while tissues.ceilingM(gf: gfAt(next), surfaceBar: surfaceBar) > next,
                  held < 200 {
                tissues.expose(ambientBar: surfaceBar + depth / 10.0,
                               fO2: Double(gas.o2) / 100.0,
                               fHe: Double(gas.he) / 100.0, minutes: 1)
                held += 1
                runtime += 1
                consume(gas, depth: depth, minutes: 1)
            }
            if held > 0 {
                stops.append(Segment(kind: .stop, depthM: depth, minutes: held,
                                     gas: gas, runtimeMin: runtime))
                totalDeco += held
            }
            firstStop = min(firstStop, depth)   // slope anchors at the real first hold
        }

        segments.append(contentsOf: stops.isEmpty ? [] : stops)
        segments.sort { $0.runtimeMin < $1.runtimeMin }
        let surfGF = tissues.gradientPercent(ambientBar: surfaceBar)

        let used = gasUsed
            .map { key, liters in
                (gas: ([bottomGas] + decoGases).first { $0.name == key } ?? bottomGas,
                 liters: liters)
            }
            .sorted { $0.liters > $1.liters }

        return Plan(segments: segments,
                    runtimeMin: runtime,
                    decoMin: runtime - decoStart - (depthM / ascentRate),
                    firstStopM: stops.first?.depthM ?? 0,
                    gasUsedL: used,
                    surfaceGF: surfGF)
    }

    // MARK: exposure helpers (0.1-min stepped ramps)

    static func descend(_ tissues: inout ZHL16C.Tissues, from: Double, to: Double,
                        gas: PlanGas, surfaceBar: Double) {
        ramp(&tissues, from: from, to: to, rate: descentRate, gas: gas,
             surfaceBar: surfaceBar)
    }

    static func ascendExpose(_ tissues: inout ZHL16C.Tissues, from: Double,
                             to: Double, gas: PlanGas, surfaceBar: Double) {
        ramp(&tissues, from: from, to: to, rate: ascentRate, gas: gas,
             surfaceBar: surfaceBar)
    }

    private static func ramp(_ tissues: inout ZHL16C.Tissues, from: Double,
                             to: Double, rate: Double, gas: PlanGas,
                             surfaceBar: Double) {
        let minutes = abs(to - from) / rate
        let steps = max(1, Int(minutes / 0.1))
        for i in 0 ..< steps {
            let f = (Double(i) + 0.5) / Double(steps)
            let d = from + (to - from) * f
            tissues.expose(ambientBar: surfaceBar + d / 10.0,
                           fO2: Double(gas.o2) / 100.0,
                           fHe: Double(gas.he) / 100.0,
                           minutes: minutes / Double(steps))
        }
    }
}
