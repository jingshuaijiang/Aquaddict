import SwiftUI
import DiveKit

struct DiveDetailView: View {
    let dive: Dive

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                DiveProfileChart(dive: dive)
                    .cardStyle()
                sectionTitle("概要")
                summaryGrid
                sectionTitle("减压 · 气体")
                decoCard
                if dive.training, let m = dive.metrics {
                    sectionTitle("训练评分")
                    trainingScores(m)
                }
                sectionTitle("潜点 · 笔记")
                placeholder
            }
            .padding(.horizontal, 16)
        }
        .background(Theme.abyss)
        .navigationTitle("潜水 #\(dive.n)")
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        Text(dive.dateText + " · \(dive.header.mode.rawValue) · GF \(dive.header.gfLow)/\(dive.header.gfHigh)")
            .font(.system(size: 12)).foregroundStyle(Theme.muted)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 14, weight: .bold)).padding(.top, 6)
    }

    private var maxAscent: Double {
        let iv = Double(max(dive.intervalS, 1))
        var m = 0.0
        for i in 1 ..< dive.samples.count {
            m = max(m, (dive.samples[i - 1].depthM - dive.samples[i].depthM) * 60 / iv)
        }
        return m
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [.init(.flexible(), spacing: 8), .init(.flexible())], spacing: 8) {
            stat("最大深度", String(format: "%.1f", dive.maxDepth), "m")
            stat("平均深度 x̄", String(format: "%.1f", dive.avgDepth), "m")
            stat("时长", fmtDur(dive.durationS), "")
            stat("水温", String(format: "%.0f–%.0f", dive.tempMin, dive.tempMax), "°C")
            stat("最大上升速率", String(format: "%.1f", maxAscent), "m/min")
            stat("CNS 峰值", "\(dive.cnsMax)", "%")
        }
    }

    private func stat(_ k: String, _ v: String, _ u: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(k).font(.system(size: 10, weight: .semibold)).kerning(1)
                .foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(v).font(.system(size: 19, weight: .bold, design: .monospaced))
                Text(u).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
    }

    private var decoCard: some View {
        let h = dive.header
        let density = GasPhysics.densityGPerL(o2: dive.o2, he: dive.he, depthM: dive.maxDepth,
                                              waterDensity: h.waterDensity,
                                              surfaceMbar: h.surfaceMbar)
        let end = GasPhysics.endM(depthM: dive.maxDepth, he: dive.he)
        let gasName = dive.he > 0 ? "Tx \(dive.o2)/\(dive.he)"
                    : dive.o2 == 21 ? "空气" : "EAN\(dive.o2)"
        return VStack(spacing: 0) {
            kv("减压模型", "\(h.decoModel.rawValue) \(h.gfLow)/\(h.gfHigh)")
            kv("最低 NDL / 最大 TTS",
               "\(dive.samples.map(\.ndlMin).min() ?? 0) / \(dive.samples.map(\.ttsMin).max() ?? 0) min")
            kv("气体", "\(gasName) · O₂ \(dive.o2)% He \(dive.he)%")
            kv("气体密度 @ \(Int(dive.maxDepth))m",
               String(format: "%.1f g/L", density),
               color: density <= 5.2 ? Theme.good : density <= 6.2 ? Theme.ink : Theme.danger)
            kv("END @ \(Int(dive.maxDepth))m", String(format: "%.0f m", end),
               color: end <= 30 ? Theme.good : Theme.danger)
            kv("水型 · 表面气压",
               "\(h.waterDensity == 1000 ? "淡水" : "海水") \(h.waterDensity) · \(h.surfaceMbar) mbar")
            kv("采样间隔", "\(dive.intervalS) s", last: true)
        }
        .cardStyle()
    }

    private func kv(_ k: String, _ v: String, color: Color = Theme.ink, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(k).font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
                Text(v).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            .padding(.vertical, 11)
            if !last { Divider().overlay(Theme.line) }
        }
    }

    private func trainingScores(_ m: TrainingMetrics) -> some View {
        HStack(spacing: 8) {
            scoreCell("平稳度", m.stabilityM.map { String(format: "±%.2f", $0) } ?? "—",
                      "目标 ≤ ±0.5 m", good: (m.stabilityM ?? 9) <= 0.5)
            scoreCell("上升违规", "\(m.ascentViolationSec)s",
                      String(format: "峰值 %.1f m/min", m.maxAscentRateMPerMin),
                      good: m.ascentViolationSec == 0)
            scoreCell("停留", "\(m.stopSec)s", "3/6 m ± 0.6 m", good: m.stopSec >= 120)
        }
    }

    private func scoreCell(_ k: String, _ v: String, _ sub: String, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k).font(.system(size: 10, weight: .semibold)).kerning(1)
                .foregroundStyle(Theme.muted)
            Text(v).font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(good ? Theme.good : Theme.danger)
            Text(sub).font(.system(size: 9)).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
    }

    private var placeholder: some View {
        Text("未设置潜点 — 在地图上选择或新建潜点，可多潜批量关联\n笔记：点击添加（潜伴、装备、能见度…）")
            .font(.system(size: 12)).foregroundStyle(Theme.faint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .padding(.bottom, 20)
    }
}
