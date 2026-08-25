import Foundation

// Groups of dive IDs merged into one logical dive (training days get
// fragmented by brief surfacings). Raw logs are never touched — merging is
// a view-layer grouping and always reversible.
@MainActor @Observable
final class MergeStore {
    static let shared = MergeStore()

    private(set) var groups: [[UInt32]] = []
    private let url: URL

    private init() {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("merges.json")
        if let d = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([[UInt32]].self, from: d) {
            groups = decoded
        }
    }

    private func save() {
        try? JSONEncoder().encode(groups).write(to: url)
    }

    func merge(_ ids: [UInt32]) {
        guard ids.count >= 2 else { return }
        // absorb any existing groups that overlap the new selection
        var members = Set(ids)
        groups.removeAll { group in
            if group.contains(where: members.contains) {
                members.formUnion(group)
                return true
            }
            return false
        }
        groups.append(members.sorted())
        save()
    }

    func unmerge(containing id: UInt32) {
        groups.removeAll { $0.contains(id) }
        save()
    }

    func group(containing id: UInt32) -> [UInt32]? {
        groups.first { $0.contains(id) }
    }
}
