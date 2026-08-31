import SwiftUI
import DiveKit

struct LogbookView: View {
    @Environment(DiveStore.self) private var store
    @State private var showDownload = false
    @State private var prefs = Prefs.shared
    @State private var siteStore = SiteStore.shared
    @State private var selecting = false
    @State private var selected: Set<UInt32> = []
    @State private var showBatchAssign = false
    @State private var reviewYear: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    brand
                    if store.isDemoData {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                            Text(loc("示例数据 — 下载你的第一潜后自动替换",
                                     "Sample dives — replaced after your first download"))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.accent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let latest = store.latest {
                        heroCard(latest)
                        if !store.trainingDives.isEmpty {
                            NavigationLink(destination: TrainingView()) {
                                trainingCard
                            }
                            .buttonStyle(.plain)
                        }
                        yearReviewCard
                        listHeader
                        ForEach(store.dives.reversed()) { dive in
                            if selecting {
                                Button {
                                    if selected.contains(dive.id) { selected.remove(dive.id) }
                                    else { selected.insert(dive.id) }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: selected.contains(dive.id)
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(dive.id)
                                                             ? Theme.accent : Theme.faint)
                                        DiveRow(dive: dive)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(destination: DiveDetailView(dive: dive)) {
                                    DiveRow(dive: dive)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if selecting { Spacer(minLength: 70) }
                    } else if store.isLoading {
                        VStack(spacing: 14) {
                            ProgressView().tint(Theme.accent).scaleEffect(1.3)
                            Text(loc("解析潜水日志…", "Parsing dive logs…"))
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 140)
                    } else {
                        ContentUnavailableView(
                            loc("连接你的潜水电脑", "Connect your dive computer"),
                            systemImage: "antenna.radiowaves.left.and.right",
                            description: Text(loc("下载潜水日志后会显示在这里",
                                                  "Downloaded dives will appear here")))
                            .padding(.top, 80)
                    }
                }
                .padding(.horizontal, 16)
            }
            .background(Theme.abyss)
            .sheet(isPresented: $showDownload) { DownloadSheet() }
            .sheet(isPresented: $showBatchAssign) {
                SitePickerSheet(dives: store.dives.filter { selected.contains($0.id) }) {
                    selecting = false
                    selected = []
                }
            }
            .fullScreenCover(item: $reviewYear) { year in
                YearReviewView(year: year)
            }
            .overlay(alignment: .bottom) {
                if selecting {
                    HStack(spacing: 12) {
                        Text("\(selected.count)" + loc(" 潜已选", " selected"))
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        Spacer()
                        Button(loc("合并", "Merge")) {
                            MergeStore.shared.merge(Array(selected))
                            selecting = false
                            selected = []
                        }
                        .disabled(selected.count < 2)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(selected.count < 2 ? Theme.faint : Theme.ndl,
                                    in: Capsule())
                        .foregroundStyle(Theme.abyss)
                        Button(loc("关联到潜点", "Assign to site")) {
                            showBatchAssign = true
                        }
                        .disabled(selected.isEmpty)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(selected.isEmpty ? Theme.faint : Theme.accent, in: Capsule())
                        .foregroundStyle(Theme.abyss)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                }
            }
        }
    }

    private var brand: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                withAnimation(.spring(duration: 0.3)) { AppNav.shared.drawerOpen = true }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Aquaddict").font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            unitSwitch
        }
        .padding(.top, 6)
    }

    // Explicit two-segment metric/imperial switch — the active side lights up.
    private var unitSwitch: some View {
        HStack(spacing: 0) {
            unitSegment(loc("公制", "Metric"), sub: "m·bar", active: !prefs.imperial) {
                prefs.imperial = false
            }
            unitSegment(loc("英制", "Imperial"), sub: "ft·psi", active: prefs.imperial) {
                prefs.imperial = true
            }
        }
        .background(Theme.panel2, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }

    private func unitSegment(_ label: String, sub: String, active: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(label).font(.system(size: 10, weight: .bold))
                Text(sub).font(.system(size: 8, design: .monospaced))
                    .opacity(0.75)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(active ? Theme.accent : .clear, in: Capsule())
            .foregroundStyle(active ? Theme.abyss : Theme.muted)
        }
        .buttonStyle(.plain)
    }

    private func heroCard(_ dive: Dive) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc("上一潜", "LAST DIVE") + " · #\(dive.n) · \(dive.dayText)")
                        .font(.system(size: 10, weight: .semibold)).kerning(1.5)
                        .foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.\(prefs.imperial ? 0 : 1)f",
                                    U.depthValue(dive.maxDepth)))
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                        Text(U.depthUnit + " · " + loc("最大深度", "max depth"))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(loc("时长", "TIME"))
                        .font(.system(size: 10, weight: .semibold)).kerning(1.5)
                        .foregroundStyle(Theme.muted)
                    Text(fmtDur(dive.durationS))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                }
            }
            DiveProfileChart(dive: dive, height: 240)
            Button {
                showDownload = true
            } label: {
                Label(loc("从潜水电脑下载", "Download from dive computer"),
                      systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .background(.linearGradient(colors: [Theme.accent, Theme.depth],
                                        startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(Theme.abyss)
        }
        .cardStyle()
    }

    private var trainingCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(loc("GUE 训练分析", "GUE Training")).font(.system(size: 14, weight: .semibold))
                let last = store.trainingDives.last?.metrics?.stabilityM
                Text("\(store.trainingDives.count)" + loc(" 潜已标记", " dives tagged") +
                     (last.map { " · " + loc("最近平稳度", "stability") + " ±" + U.depth($0, digits: 2) } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var yearReviewCard: some View {
        let years = YearStats.availableYears(dives: store.dives)
        if let latest = years.first {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(loc("\(latest) 年度潜水回顾", "\(String(latest)) Year in Review"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(loc("你的一年，做成了故事", "Your year, told as a story"))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if years.count > 1 {
                    Menu {
                        ForEach(years, id: \.self) { y in
                            Button(String(y)) { reviewYear = y }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.faint)
                    }
                }
                Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
            }
            .cardStyle()
            .contentShape(Rectangle())
            .onTapGesture { reviewYear = latest }
        }
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(loc("日志本", "Logbook")).font(.system(size: 16, weight: .bold))
            Text("\(store.dives.count)" + loc(" 潜", " dives")
                 + (prefs.hideShortDives && store.hiddenShortCount > 0
                    ? loc("（已隐藏 \(store.hiddenShortCount) 短潜）",
                          " (\(store.hiddenShortCount) short hidden)")
                    : ""))
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
            Spacer()
            Menu {
                Button {
                    prefs.hideShortDives.toggle()
                } label: {
                    Label(loc("隐藏短于 5 分钟的潜水", "Hide dives under 5 min"),
                          systemImage: prefs.hideShortDives ? "checkmark" : "")
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle"
                      + (prefs.hideShortDives ? ".fill" : ""))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            Button(selecting ? loc("完成", "Done") : loc("选择", "Select")) {
                selecting.toggle()
                if !selecting { selected = [] }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
}

struct DiveRow: View {
    let dive: Dive

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("#\(dive.n)").font(.system(size: 13, weight: .semibold))
                    if dive.training {
                        Text(loc("训练", "TRAIN")).font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .foregroundStyle(Theme.accent)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.accent.opacity(0.4), lineWidth: 1))
                    }
                    if let group = MergeStore.shared.group(containing: dive.id) {
                        Text("×\(group.count)").font(.system(size: 9, weight: .bold,
                                                             design: .monospaced))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .foregroundStyle(Theme.ndl)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.ndl.opacity(0.4), lineWidth: 1))
                    }
                }
                Text(dive.dateText + " · " + U.tempRange(dive.tempMin, dive.tempMax))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            SparklineView(depths: dive.samples.map(\.depthM))
                .frame(width: 72, height: 30)
            VStack(alignment: .trailing, spacing: 2) {
                Text(U.depth(dive.maxDepth))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                Text(fmtDur(dive.durationS))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }
}

struct SparklineView: View {
    let depths: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard depths.count > 1, let maxD = depths.max(), maxD > 0 else { return }
            var path = Path()
            for (i, d) in depths.enumerated() {
                let x = 2 + (size.width - 4) * CGFloat(i) / CGFloat(depths.count - 1)
                let y = 2 + (size.height - 6) * CGFloat(d / maxD)
                i == 0 ? path.move(to: CGPoint(x: x, y: y))
                       : path.addLine(to: CGPoint(x: x, y: y))
            }
            var fill = path
            fill.addLine(to: CGPoint(x: size.width - 2, y: 2))
            fill.addLine(to: CGPoint(x: 2, y: 2))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(Theme.accent.opacity(0.18)))
            ctx.stroke(path, with: .color(Theme.depth), lineWidth: 1.5)
        }
    }
}
