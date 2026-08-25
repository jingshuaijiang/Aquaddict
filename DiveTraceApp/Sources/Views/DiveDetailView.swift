import SwiftUI
import DiveKit

struct DiveDetailView: View {
    let dive: Dive
    @State private var prefs = Prefs.shared
    @State private var siteStore = SiteStore.shared
    @State private var showSitePicker = false
    @State private var buddyStore = BuddyStore.shared
    @State private var showBuddyPicker = false
    @State private var speciesStore = SpeciesStore.shared
    @State private var showSpeciesPicker = false
    @State private var tankStore = TankAssignStore.shared

    private var diveTank: TankChoice { tankStore.resolve(dive.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                DiveProfileChart(dive: dive)
                    .cardStyle()
                sectionTitle(loc("概要", "Summary"))
                summaryGrid
                sectionTitle(loc("减压 · 气体", "Deco · Gas"))
                decoCard
                tissueRow
                if dive.training, let m = dive.metrics {
                    sectionTitle(loc("训练评分", "Training Scores"))
                    trainingScores(m)
                }
                sectionTitle(loc("潜点 · 笔记", "Site · Notes"))
                siteRow
                buddyRow
                speciesRow
                locationSection
                sectionTitle(loc("照片", "Photos"))
                DivePhotosSection(diveID: dive.id)
                placeholder
            }
            .padding(.horizontal, 16)
        }
        .background(Theme.abyss)
        .navigationTitle(loc("潜水", "Dive") + " #\(dive.n)")
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        Text(dive.dateText + " · \(dive.header.mode.rawValue) · GF \(dive.header.gfLow)/\(dive.header.gfHigh)")
            .font(.system(size: 12)).foregroundStyle(Theme.muted)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 14, weight: .bold)).padding(.top, 6)
    }

    private var calorieEstimate: CalorieEstimator.Estimate? {
        CalorieEstimator.estimate(
            samples: dive.samples, intervalS: dive.intervalS,
            tankL: diveTank.volumeL,
            bodyKg: UserDefaults.standard.double(forKey: "wcBody").nonZero ?? 75)
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
            stat(loc("最大深度", "MAX DEPTH"),
                 String(format: "%.\(prefs.imperial ? 0 : 1)f", U.depthValue(dive.maxDepth)),
                 U.depthUnit)
            stat(loc("平均深度 x̄", "AVG DEPTH x̄"),
                 String(format: "%.\(prefs.imperial ? 0 : 1)f", U.depthValue(dive.avgDepth)),
                 U.depthUnit)
            stat(loc("时长", "DURATION"), fmtDur(dive.durationS), "")
            stat(loc("水温", "WATER TEMP"), U.tempRange(dive.tempMin, dive.tempMax), "")
            stat(loc("最大上升速率", "MAX ASCENT"),
                 String(format: "%.1f", prefs.imperial ? maxAscent * U.ftPerM : maxAscent),
                 U.rateUnit)
            stat(loc("CNS 峰值", "CNS PEAK"), "\(dive.cnsMax)", "%")
            if let cal = calorieEstimate {
                stat(loc("估算消耗", "EST. BURN") +
                     (cal.source == .ventilation ? " ·🫁\(diveTank.name)" : ""),
                     "\(Int(cal.totalKcal.rounded()))", "kcal")
                stat(loc("燃烧速率", "BURN RATE"),
                     "\(Int(cal.avgKcalPerHour.rounded()))", "kcal/h")
            }
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
                    : dive.o2 == 21 ? loc("空气", "Air") : "EAN\(dive.o2)"
        return VStack(spacing: 0) {
            kv(loc("减压模型", "Deco model"), "\(h.decoModel.rawValue) \(h.gfLow)/\(h.gfHigh)")
            kv(loc("最低 NDL / 最大 TTS", "Min NDL / Max TTS"),
               "\(dive.samples.map(\.ndlMin).min() ?? 0) / \(dive.samples.map(\.ttsMin).max() ?? 0) min")
            kv(loc("气体", "Gas"), "\(gasName) · O₂ \(dive.o2)% He \(dive.he)%")
            kv(loc("气体密度", "Gas density") + " @ " + U.depth(dive.maxDepth, digits: 0),
               String(format: "%.1f g/L", density),
               color: density <= 5.2 ? Theme.good : density <= 6.2 ? Theme.ink : Theme.danger)
            kv("END @ " + U.depth(dive.maxDepth, digits: 0), U.depth(end, digits: 0),
               color: end <= 30 ? Theme.good : Theme.danger)
            kv(loc("水型 · 表面气压", "Water · Surface pressure"),
               loc(h.waterDensity == 1000 ? "淡水" : "海水",
                   h.waterDensity == 1000 ? "Fresh" : "Salt")
               + " \(h.waterDensity) · \(h.surfaceMbar) mbar")
            sacRows
            ccrRows
            kv(loc("采样间隔", "Sample rate"), "\(dive.intervalS) s")
            tankPickerRow
        }
        .cardStyle()
    }

    // Which rig was worn on THIS dive — drives RMV and calorie numbers.
    private var tankPickerRow: some View {
        HStack {
            Text(loc("本潜瓶组", "Tank this dive"))
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer()
            Menu {
                ForEach(GearStore.shared.tanks) { tank in
                    Button("\(tank.name) · \(String(format: "%.1f", tank.volumeL))L") {
                        tankStore.assign(TankChoice(name: tank.name,
                                                    volumeL: tank.volumeL),
                                         to: dive.id)
                    }
                }
                ForEach(TankPreset.all, id: \.name) { preset in
                    Button("\(preset.name) · \(String(format: "%.1f", preset.volumeL))L") {
                        tankStore.assign(TankChoice(name: preset.name,
                                                    volumeL: preset.volumeL),
                                         to: dive.id)
                    }
                }
                Button(loc("跟随默认 ⭐", "Follow default ⭐")) {
                    tankStore.clear(dive.id)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(diveTank.name
                         + (tankStore.isExplicit(dive.id) ? "" : " ⭐"))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 11)
    }

    private var tissueRow: some View {
        NavigationLink(destination: TissueReplayView(dive: dive)) {
            HStack {
                Image(systemName: "chart.bar.fill").foregroundStyle(Theme.ndl)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("组织负荷回放", "Tissue loading replay"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(loc("ZHL-16C · 16 舱加载/排放动画", "ZHL-16C · watch 16 compartments load & clear"))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
    }

    private var speciesRow: some View {
        Button {
            showSpeciesPicker = true
        } label: {
            HStack {
                Image(systemName: "fish.fill").foregroundStyle(Theme.accent)
                let seen = speciesStore.species(for: dive.id)
                if seen.isEmpty {
                    Text(loc("记录看到的生物…", "Log sightings…"))
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                } else {
                    Text(seen.joined(separator: " · "))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
        .sheet(isPresented: $showSpeciesPicker) {
            SpeciesPickerSheet(diveID: dive.id)
        }
    }

    // Gas consumption from AI transmitter data, surface-normalized; tank size
    // defaults to an AL80 (11.1 L) until gear settings arrive.
    @ViewBuilder
    private var sacRows: some View {
        let pressures = dive.samples.compactMap { s in s.tank1Bar.map { (s.timeS, $0) } }
        if let first = pressures.first, let last = pressures.last,
           last.0 > first.0, first.1 > last.1 {
            let minutes = Double(last.0 - first.0) / 60.0
            let avgAta = 1.0 + dive.avgDepth / 10.0
            let sacBar = (first.1 - last.1) / minutes / avgAta
            let tankL = diveTank.volumeL
            let tankName = diveTank.name
            let rmvL = sacBar * tankL
            kv(loc("气瓶压力", "Tank pressure"),
               "\(U.pressure(first.1)) → \(U.pressure(last.1))", color: Theme.pressure)
            kv("SAC", U.sacPressure(sacBar), color: Theme.pressure)
            kv("RMV", U.rmv(rmvL) + " @\(tankName)",
               color: rmvL <= 18 ? Theme.good : Theme.ink)
        }
    }

    // CCR extras: average loop ppO2 and the setpoint range actually used.
    @ViewBuilder
    private var ccrRows: some View {
        if [DiveMode.cc, .cc2, .sc].contains(dive.header.mode) {
            let ppo2s = dive.samples.map(\.avgPPO2).filter { $0 > 0 }
            let setpoints = dive.samples.map(\.setpoint).filter { $0 > 0 }
            if !ppo2s.isEmpty {
                kv(loc("平均 ppO₂", "Avg ppO₂"),
                   String(format: "%.2f bar", ppo2s.reduce(0, +) / Double(ppo2s.count)),
                   color: Theme.ndl)
            }
            if let lo = setpoints.min(), let hi = setpoints.max() {
                kv(loc("设定点", "Setpoint"),
                   lo == hi ? String(format: "%.2f bar", lo)
                            : String(format: "%.2f – %.2f bar", lo, hi),
                   color: Theme.ndl)
            }
        }
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
            scoreCell(loc("平稳度", "STABILITY"),
                      m.stabilityM.map { "±" + U.depth($0, digits: 2) } ?? "—",
                      loc("目标", "target") + " ≤ ±" + U.depth(0.5, digits: 1),
                      good: (m.stabilityM ?? 9) <= 0.5)
            scoreCell(loc("上升违规", "ASCENT VIOL."), "\(m.ascentViolationSec)s",
                      loc("峰值 ", "peak ") + U.rate(m.maxAscentRateMPerMin),
                      good: m.ascentViolationSec == 0)
            scoreCell(loc("停留", "STOPS"), "\(m.stopSec)s",
                      "3/6 m ± 0.6 m", good: m.stopSec >= 120)
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

    private var siteRow: some View {
        Button {
            showSitePicker = true
        } label: {
            HStack {
                Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.accent)
                if let site = siteStore.site(for: dive.id) {
                    Text(site.name).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                } else {
                    Text(loc("设置潜点…", "Set dive site…"))
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
        .sheet(isPresented: $showSitePicker) {
            SitePickerSheet(dives: [dive])
        }
    }

    private var buddyRow: some View {
        Button {
            showBuddyPicker = true
        } label: {
            HStack {
                Image(systemName: "person.2.fill").foregroundStyle(Theme.accent)
                let buddies = buddyStore.buddies(for: dive.id)
                if buddies.isEmpty {
                    Text(loc("添加潜伴…", "Add buddies…"))
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                } else {
                    Text(buddies.joined(separator: " · "))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
        .sheet(isPresented: $showBuddyPicker) {
            BuddyPickerSheet(diveID: dive.id)
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        if let entry = dive.header.entryLocation {
            VStack(spacing: 0) {
                kv(loc("入水坐标", "Entry"), String(format: "%.5f, %.5f",
                                                    entry.latitude, entry.longitude))
                if let exit = dive.header.exitLocation {
                    kv(loc("出水坐标", "Exit"), String(format: "%.5f, %.5f",
                                                       exit.latitude, exit.longitude),
                       last: true)
                }
            }
            .cardStyle()
        }
    }

    private var placeholder: some View {
        Text(loc("笔记：点击添加（潜伴、装备、能见度…）",
                 "Notes: tap to add (buddy, gear, visibility…)"))
            .font(.system(size: 12)).foregroundStyle(Theme.faint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .padding(.bottom, 20)
    }
}
