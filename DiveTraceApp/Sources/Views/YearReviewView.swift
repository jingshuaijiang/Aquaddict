import SwiftUI
import DiveKit

// "Dive Wrapped" — fullscreen swipeable story cards for a year of diving.
struct YearReviewView: View {
    let year: Int
    var autoPresented = false
    @Environment(\.dismiss) private var dismiss
    @Environment(DiveStore.self) private var store
    @State private var stats: YearStats?
    @State private var page = 0

    var body: some View {
        ZStack {
            Theme.abyss.ignoresSafeArea()
            if let s = stats {
                TabView(selection: $page) {
                    ForEach(Array(cards(s).enumerated()), id: \.offset) { i, card in
                        card.tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(9)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(16)
        }
        .overlay(alignment: .bottom) {
            if autoPresented {
                Button {
                    dismiss()
                } label: {
                    Text(loc("跳过，直接进入 →", "Skip to the app →"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 44)
            }
        }
        .task {
            stats = YearStats.compute(year: year, dives: store.dives,
                                      sites: SiteStore.shared, photos: PhotoStore.shared)
        }
    }

    // MARK: cards

    private func cards(_ s: YearStats) -> [AnyView] {
        var out: [AnyView] = []

        out.append(AnyView(StoryCard(hue: 0) {
            Text("\(s.year)").font(.system(size: 72, weight: .black, design: .monospaced))
                .foregroundStyle(Theme.accent)
            Text(loc("你的潜水年", "Your Year in Diving"))
                .font(.system(size: 22, weight: .bold))
            Text(loc("← 滑动开始", "swipe to begin →"))
                .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 30)
        }))

        out.append(AnyView(StoryCard(hue: 1) {
            big("\(s.diveCount)", loc("次潜水", "dives"))
            Text(loc("水下待了 \(s.totalHours) 小时 \(s.totalMinutesRemainder) 分",
                     "\(s.totalHours)h \(s.totalMinutesRemainder)m underwater"))
                .font(.system(size: 17, weight: .semibold))
            quip(loc("相当于连看 \(s.movieCount) 场电影 — 但风景好多了",
                     "That's \(s.movieCount) movies back-to-back — better scenery though"))
        }))

        if let d = s.deepest {
            out.append(AnyView(StoryCard(hue: 2) {
                eyebrow(loc("最深的一刻", "DEEPEST MOMENT"))
                big(U.depth(d.depthM, digits: 1), "")
                Text(loc("潜水 #\(d.diveN) · \(d.date)", "Dive #\(d.diveN) · \(d.date)"))
                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
                quip(loc("全年累计下潜 \(Int(s.totalDescendedM)) 米 — \(String(format: "%.1f", s.eiffelCount)) 座埃菲尔铁塔",
                         "\(Int(s.totalDescendedM)) m descended this year — \(String(format: "%.1f", s.eiffelCount)) Eiffel Towers"))
            }))
        }

        if let b = s.busiestDay, b.count >= 3 {
            out.append(AnyView(StoryCard(hue: 3) {
                eyebrow(loc("最疯的一天", "WILDEST DAY"))
                big("\(b.count)", loc("潜 / 一天", "dives in one day"))
                Text(b.date).font(.system(size: 15)).foregroundStyle(Theme.muted)
                quip(loc("那天你基本长在水里", "You basically lived underwater that day"))
            }))
        }

        if let c = s.coldest {
            out.append(AnyView(StoryCard(hue: 4) {
                eyebrow(loc("最冷的坚持", "COLDEST GRIND"))
                big(U.temp(c.tempC), "")
                Text(loc("潜水 #\(c.diveN) · \(c.date)", "Dive #\(c.diveN) · \(c.date)"))
                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
                quip(c.tempC < 15 ? loc("这个水温还下去，是真爱", "Getting in at that temp? True love.")
                                  : loc("温暖的水，幸福的年", "Warm water, happy year"))
            }))
        }

        if let f = s.favoriteSite {
            out.append(AnyView(StoryCard(hue: 5) {
                eyebrow(loc("最爱的潜点", "FAVORITE SITE"))
                Text(f.name).font(.system(size: 34, weight: .black))
                    .multilineTextAlignment(.center)
                Text(loc("去了 \(f.count) 次 · 全年共 \(s.siteCount) 个潜点",
                         "\(f.count) visits · \(s.siteCount) sites this year"))
                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
                quip(loc("那里一定有什么在等你", "Something down there keeps calling you back"))
            }))
        }

        if let buddy = s.favoriteBuddy {
            out.append(AnyView(StoryCard(hue: 6) {
                eyebrow(loc("最常一起潜", "FAVORITE BUDDY"))
                Text(buddy.name).font(.system(size: 40, weight: .black))
                    .multilineTextAlignment(.center)
                Text(loc("一起潜了 \(buddy.count) 次 · 全年共 \(s.buddyCount) 位潜伴",
                         "\(buddy.count) dives together · \(s.buddyCount) buddies this year"))
                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
                quip(loc("水下最信任的人", "The one you trust down there"))
            }))
        }

        if s.speciesCount > 0, let top = s.topSpecies {
            out.append(AnyView(StoryCard(hue: 5) {
                eyebrow(loc("年度图鉴", "LIFE LIST"))
                big("\(s.speciesCount)", loc("种生物", "species"))
                Text(loc("见得最多：\(top.name) · \(top.count) 次",
                         "Most seen: \(top.name) · \(top.count)×"))
                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
                quip(loc("海里的老朋友都认识你了", "The locals know you by now"))
            }))
        }

        if let imp = s.sacImprovementPercent, let b = s.sacSecondHalf {
            out.append(AnyView(StoryCard(hue: 6) {
                eyebrow(loc("气耗进步", "BREATHING BETTER"))
                big(String(format: "%+.0f%%", -imp), "")
                Text(loc("SAC 从 \(U.sacPressure(s.sacFirstHalf!)) 到 \(U.sacPressure(b))",
                         "SAC \(U.sacPressure(s.sacFirstHalf!)) → \(U.sacPressure(b))"))
                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
                quip(imp > 0 ? loc("越潜越松弛，这就是经验", "Calmer every dive — that's experience")
                             : loc("深度上去了，气耗波动很正常", "Deeper dives, different numbers — normal"))
            }))
        }

        if let a = s.stabilityEarly, let b = s.stabilityLate {
            out.append(AnyView(StoryCard(hue: 7) {
                eyebrow(loc("训练成长", "TRAINING ARC"))
                big("±" + U.depth(b, digits: 2), "")
                Text(loc("平稳度 ±\(String(format: "%.2f", a)) → ±\(String(format: "%.2f", b)) m",
                         "Stability ±\(String(format: "%.2f", a)) → ±\(String(format: "%.2f", b)) m"))
                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
                quip(b < a ? loc("GUE 教练看了会点头", "Your GUE instructor would nod approvingly")
                           : loc("练的科目变难了，波动正常", "Harder drills, noisier numbers — keep going"))
            }))
        }

        out.append(AnyView(summaryCard(s)))
        return out
    }

    private func summaryCard(_ s: YearStats) -> some View {
        StoryCard(hue: 8) {
            SummaryPoster(stats: s)
            ShareLink(
                item: Image(uiImage: renderPoster(s)),
                preview: SharePreview("Aquaddict \(s.year)",
                                      image: Image(uiImage: renderPoster(s)))
            ) {
                Label(loc("分享给潜伴", "Share with your buddies"),
                      systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(Theme.abyss)
            }
            .padding(.top, 18)
        }
    }

    @MainActor
    private func renderPoster(_ s: YearStats) -> UIImage {
        let renderer = ImageRenderer(content:
            SummaryPoster(stats: s)
                .padding(40)
                .background(Theme.abyss)
                .frame(width: 420))
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }

    // MARK: pieces

    private func eyebrow(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .bold)).kerning(3)
            .foregroundStyle(Theme.accent)
    }

    private func big(_ v: String, _ unit: String) -> some View {
        VStack(spacing: 4) {
            Text(v).font(.system(size: 64, weight: .black, design: .monospaced))
                .minimumScaleFactor(0.5).lineLimit(1)
            if !unit.isEmpty {
                Text(unit).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func quip(_ t: String) -> some View {
        Text(t).font(.system(size: 13)).foregroundStyle(Theme.faint)
            .multilineTextAlignment(.center)
            .padding(.top, 22).padding(.horizontal, 30)
    }
}

// One story card with a slightly shifting deep-sea gradient per page.
struct StoryCard<Content: View>: View {
    let hue: Int
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hue: 0.55 + Double(hue % 4) * 0.03,
                               saturation: 0.75, brightness: 0.24),
                         Theme.abyss],
                center: .init(x: 0.5, y: 0.25), startRadius: 40, endRadius: 500)
                .ignoresSafeArea()
            VStack(spacing: 12) { content }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 24)
        }
    }
}

// The shareable poster: number wall + branding.
struct SummaryPoster: View {
    let stats: YearStats

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Aquaddict").font(.system(size: 18, weight: .black))
                    .foregroundStyle(Theme.accent)
                Text("\(stats.year)").font(.system(size: 18, weight: .black,
                                                   design: .monospaced))
                    .foregroundStyle(Theme.ink)
            }
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                cell("\(stats.diveCount)", loc("潜水", "dives"))
                cell("\(stats.totalHours)h", loc("水下时长", "underwater"))
                if let d = stats.deepest { cell(U.depth(d.depthM), loc("最深", "deepest")) }
                if let c = stats.coldest { cell(U.temp(c.tempC), loc("最冷", "coldest")) }
                if let f = stats.favoriteSite {
                    cell("\(f.count)×", f.name)
                }
                if stats.photoCount > 0 {
                    cell("\(stats.photoCount)", loc("张照片", "photos"))
                }
                if let b = stats.favoriteBuddy {
                    cell("\(b.count)×", b.name)
                }
            }
        }
        .padding(20)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.line, lineWidth: 1))
    }

    private func cell(_ v: String, _ k: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.system(size: 24, weight: .black, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(k).font(.system(size: 11)).foregroundStyle(Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 14))
    }
}


extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
