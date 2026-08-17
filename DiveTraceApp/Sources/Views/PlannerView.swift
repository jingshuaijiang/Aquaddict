import SwiftUI
import DiveKit

// Pre-dive gas planner: dial in depth and tanks, read MOD / mix / density /
// END / min deco / min gas / turn pressure at a glance. GUE conventions.
struct PlannerView: View {
    var body: some View {
        NavigationStack {
            PlannerBody()
                .navigationTitle(loc("气体计划", "Gas Planner"))
        }
    }
}

struct PlannerBody: View {
    @State private var prefs = Prefs.shared
    @State private var gear = GearStore.shared
    @AppStorage("plannerMode") private var mode = 0
    @AppStorage("plannerDepth") private var depth = 30.0
    @AppStorage("plannerO2") private var o2 = 32
    @AppStorage("plannerHe") private var he = 0
    @AppStorage("plannerTankL") private var tankL = 11.1
    @AppStorage("plannerFillBar") private var fillBar = 200.0
    @AppStorage("plannerSAC") private var sacL = 15.0

    private var density: Double {
        GasPhysics.densityGPerL(o2: o2, he: he, depthM: depth,
                                waterDensity: 1020, surfaceMbar: 1013)
    }
    private var end: Double { GasPhysics.endM(depthM: depth, he: he) }
    private var mod14: Double { GasPlanner.modM(o2Percent: o2, ppO2Limit: 1.4) }
    private var minGasBar: Double { GasPlanner.minGasBar(depthM: depth, tankL: tankL) }
    private var thirds: GasPlanner.ThirdsPlan {
        GasPlanner.thirds(fillBar: fillBar, minGasBar: minGasBar)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $mode) {
                    Text(loc("气体 · MinDeco", "Gas · Min Deco")).tag(0)
                    Text(loc("减压计划", "Deco Plan")).tag(1)
                }
                .pickerStyle(.segmented)
                inputCard
                if mode == 0 {
                    suggestionCard
                    limitsCard
                    gasCard
                    minDecoCard
                    Text(loc("计划工具仅供参考 — 执行你受训过的程序",
                             "Planning aid only — execute the procedures you trained"))
                        .font(.system(size: 10)).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 16)
                } else {
                    DecoPlanSection()
                        .padding(.bottom, 16)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Theme.abyss)
    }

    // MARK: inputs

    private var inputCard: some View {
        VStack(spacing: 14) {
            row(loc("目标深度", "Target depth"),
                value: U.depth(depth, digits: 0)) {
                Slider(value: $depth, in: 6 ... 75, step: 1).tint(Theme.accent)
            }
            HStack(spacing: 14) {
                stepper("O₂ %", value: $o2, range: 15 ... 100)
                stepper("He %", value: $he, range: 0 ... 60)
            }
            HStack(spacing: 14) {
                picker(loc("瓶组", "Tanks"), selection: $tankL,
                       options: gear.tanks.map { ($0.volumeL, $0.name) }
                           + TankPreset.all.map { ($0.volumeL, $0.name) })
                row2(loc("充气", "Fill"), U.pressure(fillBar)) {
                    Slider(value: $fillBar, in: 100 ... 300, step: 5).tint(Theme.accent)
                }
            }
            row(loc("个人 SAC（水面）", "Personal SAC (surface)"),
                value: U.rmv(sacL)) {
                Slider(value: $sacL, in: 8 ... 30, step: 0.5).tint(Theme.accent)
            }
        }
        .cardStyle()
    }

    private func row(_ label: String, value: String,
                     @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                Text(value).font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            control()
        }
    }

    private func row2(_ label: String, _ value: String,
                      @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                Text(value).font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            control()
        }
    }

    private func stepper(_ label: String, value: Binding<Int>,
                         range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            HStack {
                Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) }
                    label: { Image(systemName: "minus.circle.fill") }
                Text("\(value.wrappedValue)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .frame(minWidth: 36)
                Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) }
                    label: { Image(systemName: "plus.circle.fill") }
            }
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func picker(_ label: String, selection: Binding<Double>,
                        options: [(Double, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Menu {
                ForEach(options, id: \.0) { opt in
                    Button("\(opt.1) · \(String(format: "%.1f", opt.0)) L") {
                        selection.wrappedValue = opt.0
                    }
                }
            } label: {
                HStack {
                    Text(options.first { $0.0 == selection.wrappedValue }?.1
                         ?? String(format: "%.1f L", selection.wrappedValue))
                        .font(.system(size: 15, weight: .bold))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                }
                .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: outputs

    @ViewBuilder
    private var suggestionCard: some View {
        if let std = GasPlanner.standardGas(forDepthM: depth),
           std.o2 != o2 || std.he != he {
            Button {
                o2 = std.o2
                he = std.he
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars").foregroundStyle(Theme.accent)
                    Text(loc("这个深度的 GUE 标准气体：", "GUE standard gas for this depth: ")
                         + std.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(loc("采用", "Use")).font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cardStyle()
        }
    }

    private var limitsCard: some View {
        VStack(spacing: 0) {
            kv("MOD @ ppO₂ 1.4", U.depth(mod14, digits: 0),
               color: depth <= mod14 ? Theme.good : Theme.danger)
            kv(loc("气体密度", "Gas density") + " @ " + U.depth(depth, digits: 0),
               String(format: "%.1f g/L", density),
               color: density <= 5.2 ? Theme.good : density <= 6.2 ? Theme.ink : Theme.danger)
            kv("END @ " + U.depth(depth, digits: 0), U.depth(end, digits: 0),
               color: end <= 30 ? Theme.good : Theme.danger)
            kv(loc("此深度最佳 O₂ / 最低 He", "Best O₂ / min He here"),
               "\(GasPlanner.bestO2Percent(depthM: depth, ppO2Limit: 1.4))% / " +
               "\(GasPlanner.minHePercent(depthM: depth, endLimitM: 30))%", last: true)
        }
        .cardStyle()
    }

    private var gasCard: some View {
        let bottom20 = GasPlanner.bottomGasL(depthM: depth, minutes: 20, sacLPerMin: sacL)
        return VStack(spacing: 0) {
            kv(loc("最小气体 MinGas", "Min gas"),
               String(format: "%.0f bar · %.0f L", minGasBar,
                      GasPlanner.minGasL(depthM: depth)),
               color: Theme.pressure)
            kv(loc("三分法则可用气", "Thirds usable"),
               String(format: "%.0f bar", thirds.usableBar))
            kv(loc("折返压力", "Turn pressure"),
               U.pressure(thirds.turnPressureBar), color: Theme.accent)
            kv(loc("20 min 底部耗气", "20 min bottom gas"),
               String(format: "%.0f L · %.0f bar", bottom20, bottom20 / tankL),
               last: true)
        }
        .cardStyle()
    }

    private var minDecoCard: some View {
        let stops = GasPlanner.minDecoStops(maxDepthM: depth)
        return VStack(alignment: .leading, spacing: 10) {
            Text(loc("Min Deco 上升阶梯", "Min deco ladder"))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            if stops.isEmpty {
                Text(loc("浅于 9 米 — 直接慢升", "Shallower than 9 m — just ascend slowly"))
                    .font(.system(size: 13)).foregroundStyle(Theme.faint)
            } else {
                HStack(spacing: 8) {
                    ForEach(stops, id: \.depthM) { stop in
                        VStack(spacing: 3) {
                            Text(U.depth(Double(stop.depthM), digits: 0))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                            Text("\(stop.minutes)'").font(.system(size: 10))
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                Text(loc("上升 9 m/min 到首停，之后每站 1 分钟",
                         "9 m/min to first stop, then 1 min per stop"))
                    .font(.system(size: 10)).foregroundStyle(Theme.faint)
            }
        }
        .cardStyle()
    }

    private func kv(_ k: String, _ v: String, color: Color = Theme.ink,
                    last: Bool = false) -> some View {
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
}
