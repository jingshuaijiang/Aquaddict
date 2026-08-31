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
    static let shortDiveSeconds = 300

    /// Every parsed dive, numbering stable regardless of filters.
    private(set) var allDives: [Dive] = []
    private(set) var isLoading = false
    /// True while the logbook shows the bundled sample dives (fresh installs
    /// only — they disappear as soon as a real log lands in Documents).
    private(set) var isDemoData = false

    /// What the UI shows: merge groups collapsed into virtual dives, then
    /// short entries hidden when the pref says so.
    var dives: [Dive] {
        let merged = Self.applyMerges(allDives, groups: MergeStore.shared.groups)
        return Prefs.shared.hideShortDives
            ? merged.filter { $0.durationS >= Self.shortDiveSeconds }
            : merged
    }

    var hiddenShortCount: Int {
        allDives.filter { $0.durationS < Self.shortDiveSeconds }.count
    }

    var latest: Dive? { dives.last }
    var trainingDives: [Dive] { dives.filter { $0.training && $0.metrics != nil } }

    func load() {
        guard allDives.isEmpty, !isLoading else { return }
        isLoading = true
        Task {
            await reload()
            isLoading = false
        }
    }

    /// Parse all logs off the main actor, then publish on it.
    func reload() async {
        let (parsed, demo) = await Task.detached(priority: .userInitiated) {
            Self.parseAll()
        }.value
        allDives = parsed
        isDemoData = demo
    }

    private nonisolated static func parseAll() -> (dives: [Dive], demo: Bool) {
        struct Meta: Decodable { let n: Int; let date: String; let training: Bool }
        var loaded: [UInt32: (Data, Bool)] = [:]  // startTs -> (raw, training)

        // Training flags for downloaded/migrated history. Written to Documents
        // when the old real-dive bundle (whose meta.json carried the flags)
        // was migrated off the bundle in Aug 2026.
        var trainingTS = Set<UInt32>()
        let flagsURL = FileManager.default.urls(for: .documentDirectory,
                                                in: .userDomainMask)[0]
            .appendingPathComponent("training_flags.json")
        if let d = try? Data(contentsOf: flagsURL),
           let ts = try? JSONDecoder().decode([UInt32].self, from: d) {
            trainingTS = Set(ts)
        }

        // 1. BLE downloads / migrated history in Documents
        let files = (try? FileManager.default.contentsOfDirectory(
            at: divesDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "pnf" {
            guard let raw = try? Data(contentsOf: url),
                  let ts = Self.quickTimestamp(raw) else { continue }
            loaded[ts] = (raw, trainingTS.contains(ts))
        }

        // 2. no logs yet (fresh install): show the bundled sample dives so
        //    the whole app is browsable before the first download. They are
        //    never copied to Documents and vanish once a real log lands.
        var demo = false
        if loaded.isEmpty,
           let metaURL = Bundle.main.url(forResource: "meta", withExtension: "json"),
           let metaData = try? Data(contentsOf: metaURL),
           let meta = try? JSONDecoder().decode([Meta].self, from: metaData) {
            for m in meta {
                let name = String(format: "dive_%03d", m.n)
                guard let url = Bundle.main.url(forResource: name, withExtension: "pnf"),
                      let raw = try? Data(contentsOf: url),
                      let ts = Self.quickTimestamp(raw) else { continue }
                loaded[ts] = (raw, m.training)
            }
            demo = !loaded.isEmpty
        }

        // parse everything, order by time, number sequentially
        var parsed: [(UInt32, DiveHeader, [DiveSample], Bool)] = []
        for (ts, entry) in loaded {
            guard let (header, samples) = try? PNFParser.parse(entry.0), !samples.isEmpty
            else { continue }
            parsed.append((ts, header, samples, entry.1))
        }
        parsed.sort { $0.0 < $1.0 }
        let dives = parsed.enumerated().map { i, p in
            Dive(n: i, header: p.1, samples: p.2, training: p.3,
                 metrics: TrainingMetrics.compute(samples: p.2,
                                                  intervalS: p.1.intervalMs / 1000))
        }
        return (dives, demo)
    }

    /// Collapse each merge group into one virtual dive: samples concatenated
    /// on the true wall-clock timeline with surface bridges (0 m) across the
    /// gaps, metrics recomputed over the whole session.
    static func applyMerges(_ all: [Dive], groups: [[UInt32]]) -> [Dive] {
        guard !groups.isEmpty else { return all }
        var byID: [UInt32: Dive] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        var out = all

        for group in groups {
            let members = group.compactMap { byID[$0] }
                .sorted { $0.header.startTimestamp < $1.header.startTimestamp }
            guard members.count >= 2, let base = members.first else { continue }

            var combined: [DiveSample] = []
            for m in members {
                let offset = Int(m.header.startTimestamp) - Int(base.header.startTimestamp)
                if let lastT = combined.last?.timeS, let firstNew = m.samples.first {
                    // surface bridge across the gap
                    let iv = base.intervalS
                    let bridgeStart = lastT + iv
                    let bridgeEnd = offset + firstNew.timeS - iv
                    for t in [bridgeStart, max(bridgeStart, bridgeEnd)] {
                        combined.append(DiveSample(
                            timeS: t, depthM: 0, tempC: firstNew.tempC,
                            ndlMin: 99, ttsMin: 0, decoStopM: 0,
                            avgPPO2: 0.21, o2: firstNew.o2, he: firstNew.he, cns: 0))
                    }
                }
                for smp in m.samples {
                    combined.append(DiveSample(
                        timeS: offset + smp.timeS, depthM: smp.depthM, tempC: smp.tempC,
                        ndlMin: smp.ndlMin, ttsMin: smp.ttsMin, decoStopM: smp.decoStopM,
                        avgPPO2: smp.avgPPO2, o2: smp.o2, he: smp.he, cns: smp.cns,
                        tank1Bar: smp.tank1Bar, tank2Bar: smp.tank2Bar,
                        setpoint: smp.setpoint))
                }
            }

            let virtual = Dive(
                n: base.n, header: base.header, samples: combined,
                training: members.contains { $0.training },
                metrics: TrainingMetrics.compute(samples: combined,
                                                 intervalS: base.intervalS))
            let memberIDs = Set(members.map(\.id))
            out.removeAll { memberIDs.contains($0.id) }
            out.append(virtual)
            byID[base.id] = virtual
        }
        return out.sorted { $0.header.startTimestamp < $1.header.startTimestamp }
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
