import Foundation

// Which tank set was worn on which dive — rigs change dive to dive (singles
// one trip, doubles the next), so RMV/calories must resolve per dive.
struct TankChoice: Codable, Equatable {
    var name: String
    var volumeL: Double
}

@MainActor @Observable
final class TankAssignStore {
    static let shared = TankAssignStore()

    private(set) var byDive: [UInt32: TankChoice] = [:]
    private let url: URL

    private init() {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dive_tanks.json")
        if let d = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: TankChoice].self, from: d) {
            byDive = Dictionary(uniqueKeysWithValues:
                decoded.compactMap { k, v in UInt32(k).map { ($0, v) } })
        }
    }

    private func save() {
        let stringKeyed = Dictionary(uniqueKeysWithValues:
            byDive.map { (String($0.key), $0.value) })
        try? JSONEncoder().encode(stringKeyed).write(to: url)
    }

    func assign(_ choice: TankChoice, to diveID: UInt32) {
        byDive[diveID] = choice
        save()
    }

    func clear(_ diveID: UInt32) {
        byDive[diveID] = nil
        save()
    }

    /// The tank for a dive: explicit assignment, else the gear default.
    func resolve(_ diveID: UInt32) -> TankChoice {
        byDive[diveID] ?? TankChoice(name: GearStore.shared.defaultTankName,
                                     volumeL: GearStore.shared.defaultTankL)
    }

    var isExplicit: (UInt32) -> Bool {
        { [byDive] id in byDive[id] != nil }
    }
}
