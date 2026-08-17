import SwiftUI
import DiveKit

// Nitrox blending calculator (partial-pressure method).
struct BlenderView: View {
    @State private var prefs = Prefs.shared
    @AppStorage("blStartBar") private var startBar = 50.0
    @AppStorage("blStartO2") private var startO2 = 21.0
    @AppStorage("blTargetBar") private var targetBar = 200.0
    @AppStorage("blTargetO2") private var targetO2 = 32.0
    @AppStorage("blTopO2") private var topO2 = 20.9

    private var recipe: GasBlender.Recipe? {
        GasBlender.blend(startBar: startBar, startO2: startO2 / 100,
                         targetBar: targetBar, targetO2: targetO2 / 100,
                         topO2: topO2 / 100)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                card(loc("现在瓶里", "IN THE TANK")) {
                    slider(loc("剩余压力", "Pressure"), value: $startBar,
                           range: 0 ... 300, step: 5, fmt: { U.pressure($0) })
                    slider("O₂ %", value: $startO2, range: 15 ... 100, step: 1,
                           fmt: { String(format: "%.0f%%", $0) })
                }
                card(loc("想要的混气", "TARGET MIX")) {
                    slider(loc("目标压力", "Pressure"), value: $targetBar,
                           range: 50 ... 300, step: 5, fmt: { U.pressure($0) })
                    slider("O₂ %", value: $targetO2, range: 21 ... 100, step: 1,
                           fmt: { String(format: "%.0f%%", $0) })
                    HStack {
                        Text("MOD @1.4")
                            .font(.system(size: 11)).foregroundStyle(Theme.muted)
                        Text(U.depth(GasPlanner.modM(o2Percent: Int(targetO2),
                                                     ppO2Limit: 1.4), digits: 0))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                        Spacer()
                    }
                }
                card(loc("顶充气体", "TOP-UP GAS")) {
                    HStack(spacing: 8) {
                        topPreset(loc("空气", "Air"), 20.9)
                        topPreset("EAN32", 32)
                        topPreset("EAN36", 36)
                    }
                    slider("O₂ %", value: $topO2, range: 20.9 ... 40, step: 0.1,
                           fmt: { String(format: "%.1f%%", $0) })
                }
                recipeCard
                Text(loc("分压混气涉及高压纯氧 — 仅限受过混气训练者按规程操作",
                         "Partial-pressure blending involves high-pressure O₂ — trained blenders only"))
                    .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
        .background(Theme.abyss)
        .navigationTitle(loc("混气计算", "Blender"))
    }

    private func topPreset(_ label: String, _ v: Double) -> some View {
        Button {
            topO2 = v
        } label: {
            Text(label).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(abs(topO2 - v) < 0.05 ? Theme.accent : Theme.panel2,
                            in: Capsule())
                .foregroundStyle(abs(topO2 - v) < 0.05 ? Theme.abyss : Theme.accent)
        }
        .buttonStyle(.plain)
    }

    private var recipeCard: some View {
        Group {
            if let r = recipe {
                VStack(alignment: .leading, spacing: 12) {
                    Text(loc("配方", "RECIPE"))
                        .font(.system(size: 10, weight: .semibold)).kerning(1.5)
                        .foregroundStyle(Theme.muted)
                    if let drain = r.drainToBar {
                        step("1",
                             loc("先放气到 ", "Drain to ") + U.pressure(drain),
                             icon: "arrow.down.circle", color: Theme.temp)
                    }
                    step(r.drainToBar == nil ? "1" : "2",
                         loc("充纯氧到 ", "Add O₂ to ") + U.pressure(r.addO2Bar),
                         icon: "o.circle.fill", color: Theme.good)
                    step(r.drainToBar == nil ? "2" : "3",
                         loc("顶充到 ", "Top up to ") + U.pressure(r.topWithBar)
                         + String(format: " (O₂ %.1f%%)", topO2),
                         icon: "wind", color: Theme.accent)
                    Text(loc("充完静置后务必用氧分仪实测", "Always analyze the final mix"))
                        .font(.system(size: 11)).foregroundStyle(Theme.temp)
                }
                .cardStyle()
            } else {
                Text(loc("这个目标无法用当前顶充气体调出（目标比顶充气体还稀）",
                         "Unreachable with this top-up gas"))
                    .font(.system(size: 12)).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity)
                    .cardStyle()
            }
        }
    }

    private func step(_ n: String, _ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(n).font(.system(size: 12, weight: .black, design: .monospaced))
                .frame(width: 22, height: 22)
                .background(Theme.panel2, in: Circle())
                .foregroundStyle(Theme.accent)
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 14, weight: .semibold, design: .monospaced))
        }
    }

    private func card(_ title: String,
                      @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .semibold)).kerning(1.5)
                .foregroundStyle(Theme.muted)
            content()
        }
        .cardStyle()
    }

    private func slider(_ label: String, value: Binding<Double>,
                        range: ClosedRange<Double>, step: Double,
                        fmt: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                Text(fmt(value.wrappedValue))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            Slider(value: value, in: range, step: step).tint(Theme.accent)
        }
    }
}
