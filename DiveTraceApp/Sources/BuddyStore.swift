import Foundation

// Dive buddies: free-form names per dive, with a memory of everyone you've
// dived with for quick re-picking. Persisted as JSON in Documents.
@MainActor @Observable
final class BuddyStore {
    static let shared = BuddyStore()

    private(set) var byDive: [UInt32: [String]] = [:]
    private let url: URL

    private init() {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("buddies.json")
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

    func buddies(for diveID: UInt32) -> [String] {
        byDive[diveID] ?? []
    }

    /// Everyone ever logged, most-frequent first.
    var knownBuddies: [String] {
        var counts: [String: Int] = [:]
        for names in byDive.values {
            for n in names { counts[n, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
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
}
