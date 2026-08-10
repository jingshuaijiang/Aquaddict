import Foundation
import DiveKit

struct DiveSite: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var latitude: Double?
    var longitude: Double?
}

// Site library + dive→site assignments, persisted as JSON in Documents.
// Dives are keyed by their PNF start timestamp (stable across reinstalls).
@MainActor @Observable
final class SiteStore {
    static let shared = SiteStore()

    private(set) var sites: [DiveSite] = []
    private(set) var assignments: [UInt32: UUID] = [:]

    private let sitesURL: URL
    private let assignURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        sitesURL = docs.appendingPathComponent("sites.json")
        assignURL = docs.appendingPathComponent("site_assignments.json")
        load()
    }

    private func load() {
        if let d = try? Data(contentsOf: sitesURL),
           let s = try? JSONDecoder().decode([DiveSite].self, from: d) {
            sites = s
        }
        if let d = try? Data(contentsOf: assignURL),
           let a = try? JSONDecoder().decode([String: UUID].self, from: d) {
            assignments = Dictionary(uniqueKeysWithValues:
                a.compactMap { k, v in UInt32(k).map { ($0, v) } })
        }
    }

    private func save() {
        try? JSONEncoder().encode(sites).write(to: sitesURL)
        let stringKeyed = Dictionary(uniqueKeysWithValues:
            assignments.map { (String($0.key), $0.value) })
        try? JSONEncoder().encode(stringKeyed).write(to: assignURL)
    }

    // MARK: sites

    @discardableResult
    func createSite(name: String, latitude: Double? = nil, longitude: Double? = nil) -> DiveSite {
        let site = DiveSite(id: UUID(), name: name, latitude: latitude, longitude: longitude)
        sites.append(site)
        save()
        return site
    }

    func renameSite(_ id: UUID, to name: String) {
        guard let i = sites.firstIndex(where: { $0.id == id }) else { return }
        sites[i].name = name
        save()
    }

    func deleteSite(_ id: UUID) {
        sites.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
        save()
    }

    // MARK: assignments

    func assign(_ diveIDs: [UInt32], to siteID: UUID) {
        for id in diveIDs { assignments[id] = siteID }
        save()
    }

    func unassign(_ diveID: UInt32) {
        assignments[diveID] = nil
        save()
    }

    func site(for diveID: UInt32) -> DiveSite? {
        assignments[diveID].flatMap { id in sites.first { $0.id == id } }
    }

    func diveCount(at siteID: UUID) -> Int {
        assignments.values.filter { $0 == siteID }.count
    }
}
