import Foundation

// Gear management: tank sets (feeding real RMV numbers), serviceable gear
// with maintenance countdowns, and weighting notes per suit/water.
// Common tank presets. US tanks are named by gas capacity (ft³) at working
// pressure; internal water volumes below are the standard spec values.
struct TankPreset {
    let name: String
    let volumeL: Double
    let fillBar: Double

    static let all: [TankPreset] = [
        TankPreset(name: "AL80", volumeL: 11.1, fillBar: 207),      // 77.4 ft³ @3000psi
        TankPreset(name: "AL63", volumeL: 9.0, fillBar: 207),
        TankPreset(name: "HP80", volumeL: 10.2, fillBar: 237),      // @3442psi
        TankPreset(name: "HP100", volumeL: 12.9, fillBar: 237),
        TankPreset(name: "HP117", volumeL: 14.8, fillBar: 237),
        TankPreset(name: "HP120", volumeL: 15.3, fillBar: 237),
        TankPreset(name: "LP85", volumeL: 13.2, fillBar: 182),      // @2640psi
        TankPreset(name: "LP95", volumeL: 14.8, fillBar: 182),
        TankPreset(name: "LP104", volumeL: 16.0, fillBar: 182),
        TankPreset(name: loc("双瓶 LP85", "Double LP85"), volumeL: 26.4, fillBar: 182),
        TankPreset(name: loc("双瓶 HP100", "Double HP100"), volumeL: 25.8, fillBar: 237),
        TankPreset(name: loc("10L 欧标", "10L (Euro)"), volumeL: 10.0, fillBar: 232),
        TankPreset(name: loc("12L 欧标", "12L (Euro)"), volumeL: 12.0, fillBar: 232),
        TankPreset(name: loc("15L 欧标", "15L (Euro)"), volumeL: 15.0, fillBar: 232),
        TankPreset(name: loc("双瓶 12L (D12)", "D12 (doubles)"), volumeL: 24.0, fillBar: 232),
    ]
}

struct TankSet: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var volumeL: Double
    var fillBar: Double
    var isDefault: Bool
}

struct GearPart: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var lastService: Date
    var intervalMonths: Int

    var nextService: Date? {
        Calendar.current.date(byAdding: .month, value: intervalMonths, to: lastService)
    }

    var daysToService: Int? {
        nextService.map {
            Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0
        }
    }
}

struct GearItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var category: String
    var lastService: Date?
    var serviceIntervalMonths: Int?
    var parts: [GearPart]?   // optional for backward-compatible decoding

    var nextService: Date? {
        guard let last = lastService, let months = serviceIntervalMonths else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: last)
    }

    var daysToService: Int? {
        nextService.map {
            Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0
        }
    }

    /// Most urgent countdown across the item and all its parts.
    var worstDays: Int? {
        let all = [daysToService] + (parts ?? []).map(\.daysToService)
        return all.compactMap { $0 }.min()
    }
}

struct WeightEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var suit: String
    var saltWater: Bool
    var weightKg: Double
    var note: String
}

@MainActor @Observable
final class GearStore {
    static let shared = GearStore()

    private(set) var tanks: [TankSet] = []
    private(set) var items: [GearItem] = []
    private(set) var weights: [WeightEntry] = []

    private let url: URL

    private struct Blob: Codable {
        var tanks: [TankSet]
        var items: [GearItem]
        var weights: [WeightEntry]
    }

    private init() {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gear.json")
        if let d = try? Data(contentsOf: url),
           let blob = try? JSONDecoder().decode(Blob.self, from: d) {
            tanks = blob.tanks
            items = blob.items
            weights = blob.weights
        }
    }

    private func save() {
        try? JSONEncoder().encode(Blob(tanks: tanks, items: items, weights: weights))
            .write(to: url)
    }

    /// Tank volume used for RMV — the default tank set, AL80 fallback.
    var defaultTankL: Double { tanks.first(where: \.isDefault)?.volumeL ?? 11.1 }
    var defaultTankName: String {
        tanks.first(where: \.isDefault)?.name ?? "AL80"
    }

    // MARK: tanks

    func addTank(name: String, volumeL: Double, fillBar: Double) {
        let makeDefault = tanks.isEmpty
        tanks.append(TankSet(id: UUID(), name: name, volumeL: volumeL,
                             fillBar: fillBar, isDefault: makeDefault))
        save()
    }

    func setDefaultTank(_ id: UUID) {
        for i in tanks.indices { tanks[i].isDefault = tanks[i].id == id }
        save()
    }

    func deleteTank(_ id: UUID) {
        tanks.removeAll { $0.id == id }
        if !tanks.contains(where: \.isDefault), !tanks.isEmpty {
            tanks[0].isDefault = true
        }
        save()
    }

    // MARK: serviceable gear

    func addItem(name: String, category: String,
                 lastService: Date?, intervalMonths: Int?) {
        items.append(GearItem(id: UUID(), name: name, category: category,
                              lastService: lastService,
                              serviceIntervalMonths: intervalMonths))
        save()
    }

    func markServiced(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].lastService = Date()
        save()
    }

    // MARK: parts

    func item(_ id: UUID) -> GearItem? {
        items.first { $0.id == id }
    }

    func addPart(to itemID: UUID, name: String, intervalMonths: Int,
                 lastService: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == itemID }) else { return }
        var parts = items[i].parts ?? []
        parts.append(GearPart(id: UUID(), name: name,
                              lastService: lastService, intervalMonths: intervalMonths))
        items[i].parts = parts
        save()
    }

    func markPartServiced(itemID: UUID, partID: UUID) {
        guard let i = items.firstIndex(where: { $0.id == itemID }),
              let j = items[i].parts?.firstIndex(where: { $0.id == partID }) else { return }
        items[i].parts?[j].lastService = Date()
        save()
    }

    func deletePart(itemID: UUID, partID: UUID) {
        guard let i = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[i].parts?.removeAll { $0.id == partID }
        save()
    }

    /// Standard drysuit wear parts with typical service intervals.
    func addDrysuitTemplate(to itemID: UUID) {
        addPart(to: itemID, name: loc("颈封", "Neck seal"), intervalMonths: 12)
        addPart(to: itemID, name: loc("手封", "Wrist seals"), intervalMonths: 12)
        addPart(to: itemID, name: loc("拉链", "Zipper"), intervalMonths: 24)
        addPart(to: itemID, name: loc("充气/排气阀", "Valves"), intervalMonths: 24)
    }

    func deleteItem(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    // MARK: weights

    func addWeight(suit: String, saltWater: Bool, weightKg: Double, note: String) {
        weights.append(WeightEntry(id: UUID(), suit: suit, saltWater: saltWater,
                                   weightKg: weightKg, note: note))
        save()
    }

    func deleteWeight(_ id: UUID) {
        weights.removeAll { $0.id == id }
        save()
    }
}
