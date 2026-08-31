import SwiftUI

// Destination inspiration: browse the world's great dive sites by month or
// by big animal, with season windows and a wishlist.
struct DestinationsView: View {
    @AppStorage("destMode") private var mode = 0
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var speciesFilter: String? = nil
    @AppStorage("destWishlist") private var wishlistJSON = "[]"
    @State private var selected: Destination?

    private var wishlist: Set<String> {
        Set((try? JSONDecoder().decode([String].self,
                                       from: Data(wishlistJSON.utf8))) ?? [])
    }

    private func toggleWish(_ id: String) {
        var w = wishlist
        if w.contains(id) { w.remove(id) } else { w.insert(id) }
        if let d = try? JSONEncoder().encode(Array(w)) {
            wishlistJSON = String(data: d, encoding: .utf8) ?? "[]"
        }
    }

    private var filtered: [Destination] {
        switch mode {
        case 0:   // by month
            return DestinationGuide.all.filter { $0.months.contains(month) }
                .sorted { $0.en < $1.en }
        case 1:   // by big thing
            guard let f = speciesFilter else {
                return DestinationGuide.all.sorted { $0.en < $1.en }
            }
            return DestinationGuide.all.filter { $0.species.contains(f) }
                .sorted { $0.en < $1.en }
        default:  // wishlist
            return DestinationGuide.all.filter { wishlist.contains($0.id) }
                .sorted { $0.en < $1.en }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $mode) {
                    Text(loc("按月份", "By month")).tag(0)
                    Text(loc("按大物", "By animal")).tag(1)
                    Text(loc("心愿单", "Wishlist")).tag(2)
                }
                .pickerStyle(.segmented)

                if mode == 0 { monthPicker }
                if mode == 1 { speciesPicker }

                if filtered.isEmpty {
                    Text(mode == 2
                         ? loc("还没有心愿 — 点星号收藏目的地", "No wishes yet — star a destination")
                         : loc("这个筛选下没有条目", "Nothing matches"))
                        .font(.system(size: 12)).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
                ForEach(filtered) { dest in
                    row(dest)
                }
                Text(loc("季节为常见最佳窗口，出行前与当地潜店确认（厄尔尼诺年份会漂移）",
                         "Season windows are typical bests — confirm with operators before booking"))
                    .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
        }
        .background(Theme.abyss)
        .navigationTitle(loc("潜旅灵感", "Destinations"))
        .sheet(item: $selected) { dest in
            DestinationDetail(dest: dest,
                              wished: wishlist.contains(dest.id)) {
                toggleWish(dest.id)
            }
        }
    }

    private var monthPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(1 ... 12, id: \.self) { mo in
                    Button {
                        month = mo
                    } label: {
                        Text(loc("\(mo)月", Calendar.current.shortMonthSymbols[mo - 1]))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(month == mo ? Theme.accent : Theme.panel2,
                                        in: Capsule())
                            .foregroundStyle(month == mo ? Theme.abyss : Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var speciesPicker: some View {
        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 5), spacing: 6) {
            ForEach(DestinationGuide.things) { thing in
                Button {
                    speciesFilter = speciesFilter == thing.id ? nil : thing.id
                } label: {
                    VStack(spacing: 2) {
                        Text(thing.emoji).font(.system(size: 18))
                        Text(thing.name).font(.system(size: 8, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(speciesFilter == thing.id ? Theme.accent : Theme.line,
                                lineWidth: 1))
                    .foregroundStyle(speciesFilter == thing.id ? Theme.accent : Theme.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ dest: Destination) -> some View {
        Button {
            selected = dest
        } label: {
            HStack(spacing: 12) {
                Text(dest.species.compactMap { DestinationGuide.thing($0)?.emoji }
                    .prefix(3).joined())
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(dest.name).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        if dest.coldWater {
                            Text("❄️").font(.system(size: 10))
                        }
                        if wishlist.contains(dest.id) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9)).foregroundStyle(Theme.temp)
                        }
                    }
                    Text(dest.region + " · " + monthsText(dest))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func monthsText(_ dest: Destination) -> String {
        dest.months.count >= 11
            ? loc("全年", "year-round")
            : (1 ... 12).filter { dest.months.contains($0) }
                .map(String.init).joined(separator: "·") + loc("月", "")
    }
}

struct DestinationDetail: View {
    let dest: Destination
    let wished: Bool
    let toggleWish: () -> Void

    @State private var prefs = Prefs.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(dest.name).font(.system(size: 24, weight: .black))
                    Spacer()
                    Button {
                        toggleWish()
                    } label: {
                        Image(systemName: wished ? "star.fill" : "star")
                            .font(.system(size: 20))
                            .foregroundStyle(wished ? Theme.temp : Theme.faint)
                    }
                    .buttonStyle(.plain)
                }
                Text(dest.region
                     + String(format: " · %.2f, %.2f", dest.lat, dest.lon)
                     + (dest.coldWater ? loc(" · ❄️ 干衣", " · ❄️ drysuit") : ""))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)

                // 12-month season strip
                HStack(spacing: 3) {
                    ForEach(1 ... 12, id: \.self) { mo in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(dest.months.contains(mo)
                                      ? Theme.accent : Theme.panel2)
                                .frame(height: 22)
                            Text("\(mo)").font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                }
                .cardStyle()

                HStack {
                    Text(loc("水温", "Water"))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text("\(U.temp(Double(dest.tempC.lowerBound))) – \(U.temp(Double(dest.tempC.upperBound)))")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Spacer()
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 8) {
                    Text(loc("能看到什么", "WHAT YOU'LL SEE"))
                        .font(.system(size: 10, weight: .semibold)).kerning(1.5)
                        .foregroundStyle(Theme.muted)
                    ForEach(dest.species, id: \.self) { id in
                        if let thing = DestinationGuide.thing(id) {
                            HStack(spacing: 8) {
                                Text(thing.emoji)
                                Text(thing.name).font(.system(size: 13, weight: .semibold))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                Text(dest.note)
                    .font(.system(size: 13)).foregroundStyle(Theme.ink)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                Spacer(minLength: 20)
            }
            .padding(16)
        }
        .background(Theme.abyss)
        .presentationDetents([.large])
    }
}
