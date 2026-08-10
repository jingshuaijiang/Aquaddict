import Foundation
import DiveKit

// A dive as the UI consumes it: parsed PNF + metadata not carried by PNF yet.
struct Dive: Identifiable, Sendable {
    let n: Int
    let date: Date
    let header: DiveHeader
    let samples: [DiveSample]
    let training: Bool
    let metrics: TrainingMetrics?

    var id: Int { n }
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
}

// Loads the bundled real dives (raw PNF + meta.json). This is the same code
// path future BLE downloads will use: raw bytes in, DiveKit.PNFParser out.
@MainActor @Observable
final class DiveStore {
    private(set) var dives: [Dive] = []
    private(set) var loadErrors = 0

    var latest: Dive? { dives.last }
    var trainingDives: [Dive] { dives.filter { $0.training && $0.metrics != nil } }

    func load() {
        guard dives.isEmpty else { return }
        struct Meta: Decodable { let n: Int; let date: String; let training: Bool }

        guard let metaURL = Bundle.main.url(forResource: "meta", withExtension: "json"),
              let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode([Meta].self, from: metaData)
        else { return }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = .current

        var loaded: [Dive] = []
        for m in meta {
            let name = String(format: "dive_%03d", m.n)
            guard let url = Bundle.main.url(forResource: name, withExtension: "pnf"),
                  let raw = try? Data(contentsOf: url),
                  let (header, samples) = try? PNFParser.parse(raw),
                  !samples.isEmpty
            else { loadErrors += 1; continue }
            loaded.append(Dive(
                n: m.n,
                date: df.date(from: m.date) ?? .distantPast,
                header: header,
                samples: samples,
                training: m.training,
                metrics: TrainingMetrics.compute(samples: samples,
                                                 intervalS: header.intervalMs / 1000)
            ))
        }
        dives = loaded.sorted { $0.date < $1.date }
    }
}
