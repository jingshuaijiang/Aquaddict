import Foundation

// Gear management: tank sets (feeding real RMV numbers), serviceable gear
// with maintenance countdowns, and weighting notes per suit/water.
struct TankSet: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var volumeL: Double
    var fillBar: Double
    var isDefault: Bool
}

struct GearItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var category: String
    var lastService: Date?
    var serviceIntervalMonths: Int?

    var nextService: Date? {
        guard let last = lastService, let months = serviceIntervalMonths else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: last)
    }

    var daysToService: Int? {
        nextService.map {
            Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0
        }
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
