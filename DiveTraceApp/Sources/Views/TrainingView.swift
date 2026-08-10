import SwiftUI
import Charts
import DiveKit

struct TrainingView: View {
    @Environment(DiveStore.self) private var store

    private var recent: [Dive] { Array(store.trainingDives.suffix(8)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(store.trainingDives.count)" + loc(" 潜已标记", " dives tagged"))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                summaryCards
                sectionTitle(loc("平稳度趋势", "Stability Trend"), sub: loc("目标 ≤ ±0.5 m（GUE-F）", "target ≤ ±0.5 m (GUE-F)"))
                trendChart(values: store.trainingDives.map { $0.metrics?.stabilityM ?? 0 },
                           color: Theme.accent, target: 0.5)
                sectionTitle(loc("上升速率违规", "Ascent Violations"), sub: loc(">9 m/min 秒数", "seconds >9 m/min"))
                trendChart(values: store.trainingDives.map { Double($0.metrics?.ascentViolationSec ?? 0) },
                           color: Theme.temp, target: nil)
                sectionTitle(loc("近 5 潜曲线叠加", "Last 5 Overlaid"), sub: loc("时间归一化 · 最新最亮", "time-normalized · latest brightest"))
                overlayChart
                Text(loc("SAC 气耗趋势 — AI 数据或手动录入压力后自动计算", "SAC trend — computed from AI data or manual pressures"))
                    .font(.system(size: 12)).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity).padding(14)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 16)
        }
        .background(Theme.abyss)
        .navigationTitle(loc("GUE 训练", "GUE Training"))
    }

    private func sectionTitle(_ t: String, sub: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(t).font(.system(size: 14, weight: .bold))
            Text(sub).font(.system(size: 11)).foregroundStyle(Theme.faint)
        }
        .padding(.top, 6)
    }

    private var summaryCards: some View {
        let stab = recent.compactMap { $0.metrics?.stabilityM }
        let viol = recent.compactMap { $0.metrics?.ascentViolationSec }
        let stop = recent.compactMap { $0.metrics?.stopSec }
        func avg(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
        return HStack(spacing: 8) {
            card(loc("平稳度", "STABILITY"), String(format: "±%.2f", avg(stab)), loc("m · 近8潜均值", "m · last 8 avg"),
                 good: avg(stab) <= 0.5)
            card(loc("上升违规", "ASC. VIOL."), String(format: "%.0f", avg(viol.map(Double.init))), loc("s/潜 · 近8潜均值", "s/dive · last 8 avg"),
                 good: avg(viol.map(Double.init)) < 30)
            card(loc("停留", "STOPS"), String(format: "%.0f", avg(stop.map(Double.init))), loc("s/潜 · 3/6m 带内", "s/dive in 3/6m band"),
                 good: true)
        }
    }

    private func card(_ k: String, _ v: String, _ sub: String, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k).font(.system(size: 10, weight: .semibold)).kerning(1)
                .foregroundStyle(Theme.muted)
            Text(v).font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(good ? Theme.good : Theme.danger)
            Text(sub).font(.system(size: 9)).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
    }

    private func trendChart(values: [Double], color: Color, target: Double?) -> some View {
        Chart {
            if let target {
                RuleMark(y: .value("target", target))
                    .foregroundStyle(Theme.good)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("i", i), y: .value("v", v))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                PointMark(x: .value("i", i), y: .value("v", v))
                    .foregroundStyle(color)
                    .symbolSize(i == values.count - 1 ? 60 : 20)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Theme.line.opacity(0.6))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(String(format: "%.1f", d))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
        }
        .frame(height: 120)
        .cardStyle()
    }

    private var overlayChart: some View {
        let five = Array(store.trainingDives.suffix(5))
        return Chart {
            ForEach(Array(five.enumerated()), id: \.offset) { k, dive in
                ForEach(Array(dive.samples.enumerated()), id: \.offset) { i, s in
                    LineMark(x: .value("p", Double(i) / Double(max(dive.samples.count - 1, 1))),
                             y: .value("d", s.depthM),
                             series: .value("dive", "#\(dive.n)"))
                        .foregroundStyle(Theme.accent.opacity(0.25 + 0.75 * Double(k) / 4))
                        .lineStyle(StrokeStyle(lineWidth: k == four ? 2.2 : 1.4))
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: true, reversed: true))
        .chartXAxis(.hidden)
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
        .frame(height: 150)
        .cardStyle()
    }

    private var four: Int { 4 }
}
