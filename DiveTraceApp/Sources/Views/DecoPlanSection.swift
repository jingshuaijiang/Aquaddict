import SwiftUI
import DiveKit

// Full deco planning mode inside the planner page: ZHL-16C + GF schedule
// with optional standard deco gases.
struct DecoPlanSection: View {
    @AppStorage("plannerDepth") private var depth = 30.0
    @AppStorage("plannerO2") private var o2 = 32
    @AppStorage("plannerHe") private var he = 0
    @AppStorage("plannerSAC") private var sacL = 15.0
    @AppStorage("plannerTankL") private var tankL = 11.1
    @AppStorage("decoBottomMin") private var bottomMin = 25.0
    @AppStorage("decoGFLow") private var gfLow = 30.0
    @AppStorage("decoGFHigh") private var gfHigh = 85.0
    @AppStorage("decoUseEAN50") private var useEAN50 = false
    @AppStorage("decoUseO2") private var useO2 = false

    private var bottomGas: DecoPlanner.PlanGas {
        DecoPlanner.PlanGas(o2: o2, he: he)
    }

    private var decoGases: [DecoPlanner.PlanGas] {
        var g: [DecoPlanner.PlanGas] = []
        if useEAN50 { g.append(DecoPlanner.PlanGas(o2: 50, he: 0, switchDepthM: 21)) }
        if useO2 { g.append(DecoPlanner.PlanGas(o2: 100, he: 0, switchDepthM: 6)) }
        return g
    }

    private var plan: DecoPlanner.Plan {
        DecoPlanner.plan(depthM: depth, bottomMin: bottomMin, bottomGas: bottomGas,
                         decoGases: decoGases, gfLow: gfLow / 100,
                         gfHigh: gfHigh / 100, sacLPerMin: sacL)
    }

    private var ndl: Int {
        DecoPlanner.ndlMin(depthM: depth, gas: bottomGas, gfHigh: gfHigh / 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            inputCard
            resultCard
            Text(loc("规划参考 — 实潜以你的电脑和受训程序为准",
                     "Planning aid — dive your computer and your training"))
                .font(.system(size: 10)).foregroundStyle(Theme.faint)
                .frame(maxWidth: .infinity)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc("底部时间（含下潜）", "Bottom time (incl. descent)"))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Int(bottomMin)) min")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            Slider(value: $bottomMin, in: 5 ... 90, step: 1).tint(Theme.accent)
            HStack {
                Text("GF").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text("\(Int(gfLow))/\(Int(gfHigh))")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                Spacer()
            }
            HStack(spacing: 12) {
                Slider(value: $gfLow, in: 10 ... 100, step: 5).tint(Theme.ndl)
                Slider(value: $gfHigh, in: 40 ... 100, step: 5).tint(Theme.accent)
            }
            HStack(spacing: 10) {
                gasToggle("EAN50 @ 21m", isOn: $useEAN50)
                gasToggle("O₂ @ 6m", isOn: $useO2)
            }
        }
        .cardStyle()
    }

    private func gasToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn.wrappedValue
                      ? "checkmark.circle.fill" : "circle")
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.panel2, in: Capsule())
            .overlay(Capsule().stroke(
                isOn.wrappedValue ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1))
            .foregroundStyle(isOn.wrappedValue ? Theme.accent : Theme.muted)
        }
        .buttonStyle(.plain)
    }

    private var resultCard: some View {
        let p = plan
        let stops = p.segments.filter { $0.kind == .stop }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                stat(loc("总时间", "RUNTIME"), "\(Int(p.runtimeMin.rounded()))'",
                     color: Theme.ink)
                stat("NDL", ndl >= 199 ? "∞" : "\(ndl)'",
                     color: bottomMin <= Double(ndl) ? Theme.good : Theme.temp)
                stat("SurfGF", String(format: "%.0f%%", p.surfaceGF),
                     color: p.surfaceGF < 90 ? Theme.good : Theme.danger)
            }
            if stops.isEmpty {
                Label(loc("免减压范围内 — 按 min deco 阶梯上升即可",
                          "Within NDL — ascend on the min-deco ladder"),
                      systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.good)
            } else {
                Text(loc("减压停留", "DECO STOPS"))
                    .font(.system(size: 10, weight: .semibold)).kerning(1.5)
                    .foregroundStyle(Theme.muted)
                ForEach(Array(stops.enumerated()), id: \.offset) { _, seg in
                    HStack {
                        Text(U.depth(seg.depthM, digits: 0))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .frame(width: 60, alignment: .leading)
                        Text("\(Int(seg.minutes)) min")
                            .font(.system(size: 13, design: .monospaced))
                        Spacer()
                        Text(seg.gas.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(seg.gas.o2 > 40 ? Theme.good : Theme.muted)
                        Text(loc("累计 ", "rt ") + "\(Int(seg.runtimeMin.rounded()))'")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.faint)
                    }
                    .padding(.vertical, 3)
                }
            }
            Divider().overlay(Theme.line)
            Text(loc("耗气估算", "GAS ESTIMATE"))
                .font(.system(size: 10, weight: .semibold)).kerning(1.5)
                .foregroundStyle(Theme.muted)
            ForEach(Array(p.gasUsedL.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.gas.name).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(String(format: "%.0f L · %.0f bar @%.1fL",
                                item.liters, item.liters / tankL, tankL))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .cardStyle()
    }

    private func stat(_ k: String, _ v: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(k).font(.system(size: 9, weight: .semibold)).kerning(1)
                .foregroundStyle(Theme.muted)
            Text(v).font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 12))
    }
}
