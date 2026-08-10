import SwiftUI
import Charts
import DiveKit

// The dive profile: depth as an inverted area+line, running-average depth,
// ascent-rate violations drawn red on the depth line, water temperature as a
// normalized overlay band (true values shown by the scrubber), per the
// approved prototype. One value axis (depth); overlays are direct-labeled.
struct DiveProfileChart: View {
    let dive: Dive
    var showAverage = true
    var showTemp = true

    @State private var scrubIndex: Int? = nil

    private var maxDepth: Double { max(dive.maxDepth * 1.12, 1) }

    private var runningAvg: [Double] {
        var out: [Double] = []
        var sum = 0.0
        for (i, s) in dive.samples.enumerated() {
            sum += s.depthM
            out.append(sum / Double(i + 1))
        }
        return out
    }

    // temp normalized into the top 30% band of the chart
    private func tempY(_ t: Double) -> Double {
        let lo = dive.tempMin, hi = dive.tempMax
        let span = max(hi - lo, 0.5)
        return maxDepth * 0.02 + (1 - (t - lo) / span) * maxDepth * 0.26
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            chart
            if let i = scrubIndex, dive.samples.indices.contains(i) {
                scrubReadout(dive.samples[i], avg: runningAvg[i])
            } else {
                Text("触摸曲线查看逐点数据")
                    .font(.caption2).foregroundStyle(Theme.faint)
            }
        }
    }

    private var chart: some View {
        Chart {
            // water column fill
            ForEach(dive.samples, id: \.timeS) { s in
                AreaMark(x: .value("t", s.timeS), y: .value("d", s.depthM))
                    .foregroundStyle(.linearGradient(
                        colors: [Theme.accent.opacity(0.28), Theme.depth.opacity(0.03)],
                        startPoint: .bottom, endPoint: .top))
            }
            // depth line
            ForEach(dive.samples, id: \.timeS) { s in
                LineMark(x: .value("t", s.timeS), y: .value("d", s.depthM),
                         series: .value("series", "depth"))
                    .foregroundStyle(Theme.depth)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            // ascent violations (>9 m/min) on top, red
            ForEach(violationSegments, id: \.self) { i in
                LineMark(x: .value("t", dive.samples[i].timeS),
                         y: .value("d", dive.samples[i].depthM),
                         series: .value("series", "viol\(violationSeries[i] ?? 0)"))
                    .foregroundStyle(Theme.danger)
                    .lineStyle(StrokeStyle(lineWidth: 2.6, lineJoin: .round))
            }
            // running average depth
            if showAverage {
                ForEach(Array(runningAvg.enumerated()), id: \.offset) { i, avg in
                    LineMark(x: .value("t", dive.samples[i].timeS), y: .value("d", avg),
                             series: .value("series", "avg"))
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                }
            }
            // temperature, normalized band
            if showTemp {
                ForEach(dive.samples, id: \.timeS) { s in
                    LineMark(x: .value("t", s.timeS), y: .value("d", tempY(s.tempC)),
                             series: .value("series", "temp"))
                        .foregroundStyle(Theme.temp)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                }
            }
            if let i = scrubIndex, dive.samples.indices.contains(i) {
                RuleMark(x: .value("t", dive.samples[i].timeS))
                    .foregroundStyle(Theme.ink.opacity(0.35))
                PointMark(x: .value("t", dive.samples[i].timeS),
                          y: .value("d", dive.samples[i].depthM))
                    .foregroundStyle(Theme.ink)
                    .symbolSize(40)
            }
        }
        .chartYScale(domain: .automatic(includesZero: true, reversed: true))
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Theme.line.opacity(0.6))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text("\(Int(d))m").font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 600)) { v in
                AxisValueLabel {
                    if let t = v.as(Int.self) {
                        Text("\(t / 60)'").font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { _ in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            if let t: Int = proxy.value(atX: g.location.x) {
                                let iv = max(dive.intervalS, 1)
                                scrubIndex = min(max(t / iv - 1, 0), dive.samples.count - 1)
                            }
                        }
                        .onEnded { _ in scrubIndex = nil })
            }
        }
        .frame(height: 220)
    }

    // indices belonging to ascent-rate violation segments, grouped so line
    // segments don't connect across separate violations
    private var violationSeries: [Int: Int] {
        var out: [Int: Int] = [:]
        var group = 0
        var inViol = false
        let iv = Double(max(dive.intervalS, 1))
        for i in 1 ..< dive.samples.count {
            let asc = (dive.samples[i - 1].depthM - dive.samples[i].depthM) * 60 / iv
            if asc > 9 {
                if !inViol { group += 1; inViol = true; out[i - 1] = group }
                out[i] = group
            } else {
                inViol = false
            }
        }
        return out
    }

    private var violationSegments: [Int] { violationSeries.keys.sorted() }

    private func scrubReadout(_ s: DiveSample, avg: Double) -> some View {
        HStack(spacing: 10) {
            Text(fmtDur(s.timeS)).bold()
            Label2("深度", "\(s.depthM, sig: 1)m", Theme.depth)
            Label2("x̄", "\(avg, sig: 1)m", Theme.ink)
            Label2("水温", "\(s.tempC, sig: 0)°", Theme.temp)
            Label2("NDL", "\(s.ndlMin)'", Theme.ndl)
            if s.cns > 0 { Label2("CNS", "\(s.cns)%", Theme.muted) }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Theme.ink)
    }
}

private struct Label2: View {
    let k: String, v: String, color: Color
    init(_ k: String, _ v: String, _ color: Color) { self.k = k; self.v = v; self.color = color }
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(k).foregroundStyle(Theme.muted)
            Text(v)
        }
    }
}

extension String.StringInterpolation {
    mutating func appendInterpolation(_ value: Double, sig: Int) {
        appendLiteral(String(format: "%.\(sig)f", value))
    }
}
