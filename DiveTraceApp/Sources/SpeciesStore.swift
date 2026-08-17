import Foundation

// Critter log: species spotted per dive, with a personal life list.
@MainActor @Observable
final class SpeciesStore {
    static let shared = SpeciesStore()

    private(set) var byDive: [UInt32: [String]] = [:]
    private let url: URL

    private init() {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("species.json")
        if let d = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: d) {
            byDive = Dictionary(uniqueKeysWithValues:
                decoded.compactMap { k, v in UInt32(k).map { ($0, v) } })
        }
    }

    private func save() {
        let stringKeyed = Dictionary(uniqueKeysWithValues:
            byDive.map { (String($0.key), $0.value) })
        try? JSONEncoder().encode(stringKeyed).write(to: url)
    }

    func species(for diveID: UInt32) -> [String] {
        byDive[diveID] ?? []
    }

    /// Personal life list, most-seen first.
    var lifeList: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for names in byDive.values {
            for n in names { counts[n, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    func toggle(_ name: String, for diveID: UInt32) {
        var list = byDive[diveID] ?? []
        if let i = list.firstIndex(of: name) {
            list.remove(at: i)
        } else {
            list.append(name)
        }
        byDive[diveID] = list.isEmpty ? nil : list
        save()
    }

    func add(_ name: String, for diveID: UInt32) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var list = byDive[diveID] ?? []
        guard !list.contains(trimmed) else { return }
        list.append(trimmed)
        byDive[diveID] = list
        save()
    }

    /// Common sightings for the quick-pick grid.
    static let presets: [(zh: String, en: String, emoji: String)] = [
        ("海龟", "Turtle", "🐢"), ("蝠鲼", "Manta", "🦇"),
        ("鲸鲨", "Whale shark", "🦈"), ("礁鲨", "Reef shark", "🦈"),
        ("海鳗", "Moray eel", "🐍"), ("章鱼", "Octopus", "🐙"),
        ("乌贼/鱿鱼", "Cuttle/squid", "🦑"), ("海蛞蝓", "Nudibranch", "🐌"),
        ("海马", "Seahorse", "🐴"), ("狮子鱼", "Lionfish", "🦁"),
        ("小丑鱼", "Clownfish", "🐠"), ("石斑", "Grouper", "🐟"),
        ("杰克风暴", "Jack tornado", "🌪"), ("梭鱼群", "Barracuda", "⚡"),
        ("龙虾", "Lobster", "🦞"), ("螃蟹", "Crab", "🦀"),
        ("水母", "Jellyfish", "🎐"), ("海豚", "Dolphin", "🐬"),
    ]
}
