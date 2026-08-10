import SwiftUI
import Charts
import DiveKit

// The dive profile: depth as an inverted area+line, running-average depth,
// ascent-rate violations in red, plus normalized overlay bands for water
// temperature (top) and tank pressure (bottom) — true values live in the
// scrubber readout and the endpoint labels. One real value axis (depth).
struct DiveProfileChart: View {
    let dive: Dive
    var height: CGFloat = 300

    @State private var scrubIndex: Int? = nil
    @State private var showTemp = true
    @State private var showAvg = true
    @State private var showNDL = false
    @State private var showPressure = true

    private var maxDepth: Double { max(dive.maxDepth * 1.05, 1) }
    private var dur: Int { dive.samples.last?.timeS ?? 1 }
    private var hasPressure: Bool { dive.samples.contains { $0.tank1Bar != nil } }

    private var runningAvg: [Double] {
        var out: [Double] = []
        var sum = 0.0
        for (i, s) in dive.samples.enumerated() {
            sum += s.depthM
            out.append(sum / Double(i + 1))
        }
        return out
    }

    private var pressures: [(t: Int, bar: Double)] {
        dive.samples.compactMap { s in s.tank1Bar.map { (s.timeS, $0) } }
    }

    // normalize a value into a horizontal band of the depth axis
    private func bandY(_ v: Double, lo: Double, hi: Double, top: Double, bottom: Double) -> Double {
        let span = max(hi - lo, 1e-6)
        return maxDepth * top + (1 - (v - lo) / span) * maxDepth * (bottom - top)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            legendChips
            chart
            readout
        }
    }

    private var legendChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("深度", Theme.depth, .constant(true))
                chip("平均", Theme.ink, $showAvg)
                chip("水温", Theme.temp, $showTemp)
                if hasPressure { chip("气压", Theme.pressure, $showPressure) }
                chip("NDL", Theme.ndl, $showNDL)
            }
        }
    }

    private func chip(_ label: String, _ color: Color, _ on: Binding<Bool>) -> some View {
        Button {
            on.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.system(size: 11))
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Theme.panel2, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            .opacity(on.wrappedValue ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
    }

    private var chart: some View {
        Chart {
            ForEach(dive.samples, id: \.timeS) { s in
                AreaMark(x: .value("t", s.timeS), y: .value("d", s.depthM))
                    .foregroundStyle(.linearGradient(
                        colors: [Theme.accent.opacity(0.28), Theme.depth.opacity(0.03)],
                        startPoint: .bottom, endPoint: .top))
                LineMark(x: .value("t", s.timeS), y: .value("d", s.depthM),
                         series: .value("series", "depth"))
                    .foregroundStyle(Theme.depth)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            ForEach(violationSegments, id: \.self) { i in
                LineMark(x: .value("t", dive.samples[i].timeS),
                         y: .value("d", dive.samples[i].depthM),
                         series: .value("series", "viol\(violationSeries[i] ?? 0)"))
                    .foregroundStyle(Theme.danger)
                    .lineStyle(StrokeStyle(lineWidth: 2.6, lineJoin: .round))
            }
            if showAvg {
                ForEach(Array(runningAvg.enumerated()), id: \.offset) { i, avg in
                    LineMark(x: .value("t", dive.samples[i].timeS), y: .value("d", avg),
                             series: .value("series", "avg"))
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                }
            }
            if showTemp {
                let lo = dive.tempMin, hi = dive.tempMax
                ForEach(dive.samples, id: \.timeS) { s in
                    LineMark(x: .value("t", s.timeS),
                             y: .value("d", bandY(s.tempC, lo: lo, hi: hi, top: 0.02, bottom: 0.22)),
                             series: .value("series", "temp"))
                        .foregroundStyle(Theme.temp)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                }
            }
            if showPressure, hasPressure {
                let bars = pressures.map(\.bar)
                let lo = bars.min()!, hi = bars.max()!
                ForEach(pressures, id: \.t) { p in
                    LineMark(x: .value("t", p.t),
                             y: .value("d", bandY(p.bar, lo: lo, hi: hi, top: 0.72, bottom: 0.98)),
                             series: .value("series", "pressure"))
                        .foregroundStyle(Theme.pressure)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                }
            }
            if showNDL {
                let ndls = dive.samples.map { Double($0.ndlMin) }
                let lo = ndls.min() ?? 0, hi = ndls.max() ?? 1
                ForEach(dive.samples, id: \.timeS) { s in
                    LineMark(x: .value("t", s.timeS),
                             y: .value("d", bandY(Double(s.ndlMin), lo: lo, hi: hi,
                                                  top: 0.45, bottom: 0.65)),
                             series: .value("series", "ndl"))
                        .foregroundStyle(Theme.ndl)
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
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
        .chartXScale(domain: 0 ... dur)
        .chartYScale(domain: .automatic(includesZero: true, reversed: true))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(Theme.line.opacity(0.6))
                AxisValueLabel(anchor: .trailing) {
                    if let d = v.as(Double.self) {
                        Text("\(Int(d))").font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: dur > 3600 ? 1200 : 600)) { v in
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
        .frame(height: height)
        .padding(.leading, -6)   // tuck the narrow axis in tight
    }

    @ViewBuilder
    private var readout: some View {
        if let i = scrubIndex, dive.samples.indices.contains(i) {
            let s = dive.samples[i]
            HStack(spacing: 10) {
                Text(fmtDur(s.timeS)).bold()
                pair("深度", String(format: "%.1fm", s.depthM), Theme.depth)
                pair("x̄", String(format: "%.1fm", runningAvg[i]), Theme.ink)
                pair("温", String(format: "%.0f°", s.tempC), Theme.temp)
                if let bar = s.tank1Bar { pair("压", String(format: "%.0fbar", bar), Theme.pressure) }
                pair("NDL", "\(s.ndlMin)'", Theme.ndl)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.ink)
        } else {
            HStack(spacing: 10) {
                Text("触摸曲线查看逐点数据").font(.system(size: 10)).foregroundStyle(Theme.faint)
                Spacer()
                if let first = pressures.first, let last = pressures.last {
                    Text(String(format: "气压 %.0f → %.0f bar", first.bar, last.bar))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.pressure)
                }
            }
        }
    }

    private func pair(_ k: String, _ v: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(k).foregroundStyle(Theme.muted)
            Text(v)
        }
    }

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
}
