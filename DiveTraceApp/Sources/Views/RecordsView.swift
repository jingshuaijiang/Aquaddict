import SwiftUI
import DiveKit

// Personal records + achievement badges, computed live from the logbook.
struct RecordsView: View {
    @Environment(DiveStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                recordsCard
                Text(loc("成就", "Achievements"))
                    .font(.system(size: 14, weight: .bold)).padding(.top, 6)
                badgeGrid
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
        }
        .background(Theme.abyss)
        .navigationTitle(loc("个人纪录", "Records"))
    }

    // MARK: records

    private var recordsCard: some View {
        let dives = store.dives
        let deepest = dives.max { $0.maxDepth < $1.maxDepth }
        let longest = dives.max { $0.durationS < $1.durationS }
        let coldest = dives.min { $0.tempMin < $1.tempMin }
        let totalS = dives.map(\.durationS).reduce(0, +)
        return VStack(spacing: 0) {
            recordRow(loc("总潜数", "Total dives"), "\(dives.count)", nil)
            recordRow(loc("水下总时长", "Total time"),
                      "\(totalS / 3600)h \(totalS % 3600 / 60)m", nil)
            recordRow(loc("最深", "Deepest"),
                      deepest.map { U.depth($0.maxDepth) } ?? "—", deepest)
            recordRow(loc("最长", "Longest"),
                      longest.map { fmtDur($0.durationS) } ?? "—", longest)
            recordRow(loc("最冷", "Coldest"),
                      coldest.map { U.temp($0.tempMin) } ?? "—", coldest, last: true)
        }
        .cardStyle()
    }

    @ViewBuilder
    private func recordRow(_ k: String, _ v: String, _ dive: Dive?,
                           last: Bool = false) -> some View {
        VStack(spacing: 0) {
            if let dive {
                NavigationLink(destination: DiveDetailView(dive: dive)) {
                    recordRowContent(k, v, sub: "#\(dive.n) · \(dive.dayText)")
                }
                .buttonStyle(.plain)
            } else {
                recordRowContent(k, v, sub: nil)
            }
            if !last { Divider().overlay(Theme.line) }
        }
    }

    private func recordRowContent(_ k: String, _ v: String, sub: String?) -> some View {
        HStack {
            Text(k).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(v).font(.system(size: 15, weight: .bold, design: .monospaced))
                if let sub {
                    Text(sub).font(.system(size: 10)).foregroundStyle(Theme.faint)
                }
            }
            if sub != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: badges

    private struct Badge: Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String
        let achieved: Bool
    }

    private var badges: [Badge] {
        let dives = store.dives
        let n = dives.count
        let maxDepth = dives.map(\.maxDepth).max() ?? 0
        let maxDur = dives.map(\.durationS).max() ?? 0
        let minTemp = dives.map(\.tempMin).min() ?? 99
        var byDay: [String: Int] = [:]
        for d in dives { byDay[d.dayText, default: 0] += 1 }
        let maxPerDay = byDay.values.max() ?? 0
        let trainCount = dives.filter(\.training).count
        let siteCount = Set(dives.compactMap { SiteStore.shared.site(for: $0.id)?.id }).count
        let photoCount = dives.map { PhotoStore.shared.count(for: $0.id) }.reduce(0, +)
        let buddyDives = dives.filter { !BuddyStore.shared.buddies(for: $0.id).isEmpty }.count

        return [
            Badge(id: "d10", icon: "10.circle.fill",
                  title: loc("入门十潜", "First 10"), subtitle: "10 dives", achieved: n >= 10),
            Badge(id: "d50", icon: "50.circle.fill",
                  title: loc("半百俱乐部", "Half Century"), subtitle: "50 dives", achieved: n >= 50),
            Badge(id: "d100", icon: "crown.fill",
                  title: loc("百潜达成", "Century Diver"), subtitle: "100 dives", achieved: n >= 100),
            Badge(id: "deep18", icon: "arrow.down.circle.fill",
                  title: loc("进阶深度", "Going Deeper"), subtitle: "18 m", achieved: maxDepth >= 18),
            Badge(id: "deep30", icon: "water.waves.and.arrow.down",
                  title: loc("三十米", "Thirty Club"), subtitle: "30 m", achieved: maxDepth >= 30),
            Badge(id: "deep40", icon: "flame.fill",
                  title: loc("四十米", "The Forty"), subtitle: "40 m", achieved: maxDepth >= 40),
            Badge(id: "hour", icon: "clock.fill",
                  title: loc("一小时潜", "Hour Underwater"), subtitle: "60 min",
                  achieved: maxDur >= 3600),
            Badge(id: "cold", icon: "snowflake",
                  title: loc("冷水勇士", "Cold Warrior"), subtitle: "< 10 °C",
                  achieved: minTemp < 10),
            Badge(id: "iron", icon: "bolt.fill",
                  title: loc("单日铁人", "Iron Day"), subtitle: loc("单日 5 潜", "5 in a day"),
                  achieved: maxPerDay >= 5),
            Badge(id: "train25", icon: "figure.pool.swim",
                  title: loc("训练狂", "Drill Sergeant"), subtitle: loc("25 训练潜", "25 training"),
                  achieved: trainCount >= 25),
            Badge(id: "sites10", icon: "map.fill",
                  title: loc("探索者", "Explorer"), subtitle: loc("10 潜点", "10 sites"),
                  achieved: siteCount >= 10),
            Badge(id: "photo", icon: "camera.fill",
                  title: loc("水下记录者", "Documentarian"), subtitle: loc("20 张照片", "20 photos"),
                  achieved: photoCount >= 20),
            Badge(id: "buddy", icon: "person.2.fill",
                  title: loc("从不独潜", "Never Alone"), subtitle: loc("10 潜有潜伴", "10 buddied"),
                  achieved: buddyDives >= 10),
        ]
    }

    private var badgeGrid: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())],
                  spacing: 10) {
            ForEach(badges) { badge in
                VStack(spacing: 6) {
                    Image(systemName: badge.icon)
                        .font(.system(size: 26))
                        .foregroundStyle(badge.achieved ? Theme.accent : Theme.faint)
                    Text(badge.title).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(badge.achieved ? Theme.ink : Theme.faint)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(badge.subtitle).font(.system(size: 9))
                        .foregroundStyle(Theme.faint)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(badge.achieved ? Theme.accent.opacity(0.4) : Theme.line,
                            lineWidth: 1))
                .opacity(badge.achieved ? 1 : 0.55)
            }
        }
    }
}
