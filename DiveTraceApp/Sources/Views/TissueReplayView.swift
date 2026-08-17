import SwiftUI
import DiveKit

// Tissue loading replay: scrub through the dive and watch the 16 ZHL-16C
// compartments load and offgas, with ceiling / GF99 readouts.
struct TissueReplayView: View {
    let dive: Dive

    @State private var result: TissueReplay.Result?
    @State private var index = 0
    @State private var playing = false

    private let timer = Timer.publish(every: 0.06, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let r = result, !r.snapshots.isEmpty {
                    let snap = r.snapshots[min(index, r.snapshots.count - 1)]
                    readouts(snap, r)
                    bars(snap)
                    scrubber(r)
                    surfacingCard(r)
                    explainer
                } else {
                    ProgressView().tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Theme.abyss)
        .navigationTitle(loc("组织负荷回放", "Tissue Replay"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let samples = dive.samples
            let header = dive.header
            result = await Task.detached(priority: .userInitiated) {
                TissueReplay.compute(samples: samples, header: header)
            }.value
        }
        .onReceive(timer) { _ in
            guard playing, let r = result else { return }
            if index < r.snapshots.count - 1 {
                index += 1
            } else {
                playing = false
            }
        }
    }

    private func readouts(_ snap: TissueSnapshot, _ r: TissueReplay.Result) -> some View {
        HStack(spacing: 10) {
            readout(loc("时间", "TIME"), fmtDur(snap.timeS))
            readout(loc("深度", "DEPTH"), U.depth(snap.depthM))
            readout("GF99", String(format: "%.0f%%", snap.gf99),
                    color: snap.gf99 < 60 ? Theme.good
                           : snap.gf99 < 90 ? Theme.temp : Theme.danger)
            readout(loc("天花板", "CEILING"),
                    snap.ceilingM < 0.5 ? "—" : U.depth(snap.ceilingM, digits: 0),
                    color: snap.ceilingM < 0.5 ? Theme.good : Theme.danger)
        }
    }

    private func readout(_ k: String, _ v: String, color: Color = Theme.ink) -> some View {
        VStack(spacing: 3) {
            Text(k).font(.system(size: 9, weight: .semibold)).kerning(1)
                .foregroundStyle(Theme.muted)
            Text(v).font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
    }

    // 16 compartment bars: half-times fast → slow, height = % toward M-value
    private func bars(_ snap: TissueSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0 ..< 16, id: \.self) { i in
                    let pct = snap.compartmentPercents[i]
                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(pct < 50 ? Theme.depth
                                          : pct < 80 ? Theme.temp : Theme.danger)
                                    .frame(height: max(3, geo.size.height
                                                        * min(abs(pct), 120) / 120))
                                    .opacity(pct < 0 ? 0.35 : 1)   // offgassing below ambient
                            }
                        }
                        Text("\(i + 1)").font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
            .frame(height: 170)
            HStack {
                Text(loc("快组织 ←", "fast ←")).font(.system(size: 9))
                Spacer()
                Text(loc("→ 慢组织（半时 5→635 分钟）", "→ slow (half-times 5→635 min)"))
                    .font(.system(size: 9))
            }
            .foregroundStyle(Theme.faint)
        }
        .cardStyle()
        .animation(.linear(duration: 0.06), value: index)
    }

    private func scrubber(_ r: TissueReplay.Result) -> some View {
        HStack(spacing: 12) {
            Button {
                if index >= r.snapshots.count - 1 { index = 0 }
                playing.toggle()
            } label: {
                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            Slider(value: Binding(get: { Double(index) },
                                  set: { index = Int($0); playing = false }),
                   in: 0 ... Double(max(r.snapshots.count - 1, 1)))
                .tint(Theme.accent)
        }
    }

    private func surfacingCard(_ r: TissueReplay.Result) -> some View {
        VStack(spacing: 0) {
            row(loc("出水 SurfGF", "Surfacing GF"),
                String(format: "%.0f%%", r.surfaceGF),
                color: r.surfaceGF < 70 ? Theme.good
                       : r.surfaceGF < 90 ? Theme.temp : Theme.danger)
            row(loc("主导组织", "Leading compartment"),
                "#\(r.leadingCompartment + 1) · "
                + String(format: "%.0f min", ZHL16CInfo.halftime(r.leadingCompartment)))
            row(loc("组织基本排净约需", "Approx. desaturation"),
                String(format: loc("%.1f 小时", "%.1f h"), r.desatHours), last: true)
        }
        .cardStyle()
    }

    private func row(_ k: String, _ v: String, color: Color = Theme.ink,
                     last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(k).font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
                Text(v).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            .padding(.vertical, 10)
            if !last { Divider().overlay(Theme.line) }
        }
    }

    private var explainer: some View {
        Text(loc("每根柱 = 一个理论组织舱的惰性气体负荷，以其 M 值（ZHL-16C + 本潜 GF 上限）为 100%。快组织潜中先满、出水先排；慢组织决定重复潜水的余氮。仅供理解减压，不构成潜水依据。",
                 "Each bar is one theoretical compartment's inert gas load as a % of its M-value (ZHL-16C, this dive's GF-high). Fast tissues fill and clear first; slow ones drive repetitive-dive planning. For understanding deco, not for diving."))
            .font(.system(size: 10)).foregroundStyle(Theme.faint)
            .padding(.bottom, 16)
    }
}

// small helper to surface half-times without exposing the arrays
enum ZHL16CInfo {
    static func halftime(_ i: Int) -> Double {
        let times = [5.0, 8.0, 12.5, 18.5, 27.0, 38.3, 54.3, 77.0,
                     109.0, 146.0, 187.0, 239.0, 305.0, 390.0, 498.0, 635.0]
        return times[min(max(i, 0), 15)]
    }
}
