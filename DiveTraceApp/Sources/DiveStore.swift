import Foundation
import DiveKit

// A dive as the UI consumes it: parsed PNF + app-side metadata.
struct Dive: Identifiable, Sendable, Hashable {
    static func == (lhs: Dive, rhs: Dive) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let n: Int
    let header: DiveHeader
    let samples: [DiveSample]
    let training: Bool
    let metrics: TrainingMetrics?

    var id: UInt32 { header.startTimestamp }
    var maxDepth: Double { samples.map(\.depthM).max() ?? 0 }
    var avgDepth: Double {
        samples.isEmpty ? 0 : samples.map(\.depthM).reduce(0, +) / Double(samples.count)
    }
    var durationS: Int { samples.last?.timeS ?? 0 }
    var tempMin: Double { samples.map(\.tempC).min() ?? 0 }
    var tempMax: Double { samples.map(\.tempC).max() ?? 0 }
    var cnsMax: Int { samples.map(\.cns).max() ?? 0 }
    var intervalS: Int { header.intervalMs / 1000 }
    var o2: Int { samples[samples.count / 2].o2 }
    var he: Int { samples[samples.count / 2].he }

    // startTimestamp holds the device's wall clock encoded as epoch seconds,
    // so all date rendering goes through UTC to read the fields back.
    var date: Date { Date(timeIntervalSince1970: Double(header.startTimestamp)) }

    private static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    var dateText: String { Self.short.string(from: date) }
    var dayText: String { Self.dayOnly.string(from: date) }

    /// Best surface fix: entry when the GPS locked before the splash,
    /// otherwise the exit fix (quick entries often miss the first one).
    var anyLocation: GeoPoint? { header.entryLocation ?? header.exitLocation }
}

// Loads dives from two places, deduped by start timestamp:
// 1. the app bundle (the user's imported history), 2. Documents/Dives
// (everything downloaded over BLE). Both are raw PNF parsed by DiveKit.
@MainActor @Observable
final class DiveStore {
    private(set) var dives: [Dive] = []
    private(set) var isLoading = false

    var latest: Dive? { dives.last }
    var trainingDives: [Dive] { dives.filter { $0.training && $0.metrics != nil } }

    func load() {
        guard dives.isEmpty, !isLoading else { return }
        isLoading = true
        Task {
            await reload()
            isLoading = false
        }
    }

    /// Parse all logs off the main actor, then publish on it.
    func reload() async {
        let parsed = await Task.detached(priority: .userInitiated) {
            Self.parseAll()
        }.value
        dives = parsed
    }

    private nonisolated static func parseAll() -> [Dive] {
        struct Meta: Decodable { let n: Int; let date: String; let training: Bool }
        var loaded: [UInt32: (Data, Bool)] = [:]  // startTs -> (raw, training)

        // 1. bundled history
        if let metaURL = Bundle.main.url(forResource: "meta", withExtension: "json"),
           let metaData = try? Data(contentsOf: metaURL),
           let meta = try? JSONDecoder().decode([Meta].self, from: metaData) {
            for m in meta {
                let name = String(format: "dive_%03d", m.n)
                guard let url = Bundle.main.url(forResource: name, withExtension: "pnf"),
                      let raw = try? Data(contentsOf: url) else { continue }
                if let ts = Self.quickTimestamp(raw) {
                    loaded[ts] = (raw, m.training)
                }
            }
        }

        // 2. BLE downloads (win over bundled duplicates)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: divesDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "pnf" {
            guard let raw = try? Data(contentsOf: url),
                  let ts = Self.quickTimestamp(raw) else { continue }
            let training = loaded[ts]?.1 ?? false
            loaded[ts] = (raw, training)
        }

        // parse everything, order by time, number sequentially
        var parsed: [(UInt32, DiveHeader, [DiveSample], Bool)] = []
        for (ts, entry) in loaded {
            guard let (header, samples) = try? PNFParser.parse(entry.0), !samples.isEmpty
            else { continue }
            parsed.append((ts, header, samples, entry.1))
        }
        parsed.sort { $0.0 < $1.0 }
        return parsed.enumerated().map { i, p in
            Dive(n: i, header: p.1, samples: p.2, training: p.3,
                 metrics: TrainingMetrics.compute(samples: p.2,
                                                  intervalS: p.1.intervalMs / 1000))
        }
    }

    /// Start timestamp without a full parse: opening record 0, bytes 12-15 BE.
    private nonisolated static func quickTimestamp(_ raw: Data) -> UInt32? {
        let b = [UInt8](raw)
        var i = 0
        while i + 32 <= b.count {
            if b[i] == 0x10 {
                return UInt32(b[i + 12]) << 24 | UInt32(b[i + 13]) << 16
                    | UInt32(b[i + 14]) << 8 | UInt32(b[i + 15])
            }
            i += 32
        }
        return nil
    }
}
