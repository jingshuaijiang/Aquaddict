import SwiftUI
import DiveKit

struct LogbookView: View {
    @Environment(DiveStore.self) private var store
    @State private var showDownload = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    brand
                    if let latest = store.latest {
                        heroCard(latest)
                        if !store.trainingDives.isEmpty {
                            NavigationLink(destination: TrainingView()) {
                                trainingCard
                            }
                            .buttonStyle(.plain)
                        }
                        listHeader
                        ForEach(store.dives.reversed()) { dive in
                            NavigationLink(destination: DiveDetailView(dive: dive)) {
                                DiveRow(dive: dive)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ContentUnavailableView("连接你的潜水电脑",
                                               systemImage: "antenna.radiowaves.left.and.right",
                                               description: Text("下载潜水日志后会显示在这里"))
                            .padding(.top, 80)
                    }
                }
                .padding(.horizontal, 16)
            }
            .background(Theme.abyss)
            .sheet(isPresented: $showDownload) { DownloadSheet() }
        }
    }

    private var brand: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("潜迹").font(.system(size: 24, weight: .bold))
            Text("DIVETRACE").font(.system(size: 10, weight: .semibold))
                .kerning(3).foregroundStyle(Theme.accent)
            Spacer()
        }
        .padding(.top, 6)
    }

    private func heroCard(_ dive: Dive) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("上一潜 · #\(dive.n) · \(dive.dayText)")
                        .font(.system(size: 10, weight: .semibold)).kerning(1.5)
                        .foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", dive.maxDepth))
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                        Text("米 · 最大深度").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("时长").font(.system(size: 10, weight: .semibold)).kerning(1.5)
                        .foregroundStyle(Theme.muted)
                    Text(fmtDur(dive.durationS))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                }
            }
            DiveProfileChart(dive: dive, height: 240)
            Button {
                showDownload = true
            } label: {
                Label("从潜水电脑下载", systemImage: "arrow.down.circle.fill")
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
                Text("GUE 训练分析").font(.system(size: 14, weight: .semibold))
                let last = store.trainingDives.last?.metrics?.stabilityM
                Text("\(store.trainingDives.count) 潜已标记" +
                     (last.map { String(format: " · 最近平稳度 ±%.2f m", $0) } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
        }
        .cardStyle()
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("日志本").font(.system(size: 16, weight: .bold))
            Spacer()
            Text("\(store.dives.count) 潜 · Peregrine + Perdix 3")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
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
                        Text("训练").font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .foregroundStyle(Theme.accent)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.accent.opacity(0.4), lineWidth: 1))
                    }
                }
                Text(dive.dateText + String(format: " · %.0f–%.0f°C", dive.tempMin, dive.tempMax))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            SparklineView(depths: dive.samples.map(\.depthM))
                .frame(width: 72, height: 30)
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f m", dive.maxDepth))
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
