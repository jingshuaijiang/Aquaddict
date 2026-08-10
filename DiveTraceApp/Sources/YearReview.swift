import Foundation
import DiveKit

// Stats behind the year-in-review story cards.
struct YearStats {
    let year: Int
    let diveCount: Int
    let totalSeconds: Int
    let deepest: (depthM: Double, diveN: Int, date: String)?
    let totalDescendedM: Double
    let coldest: (tempC: Double, diveN: Int, date: String)?
    let busiestDay: (count: Int, date: String)?
    let favoriteSite: (name: String, count: Int)?
    let siteCount: Int
    let sacFirstHalf: Double?    // bar/min, AI dives only
    let sacSecondHalf: Double?
    let stabilityEarly: Double?  // training dives, first vs last third
    let stabilityLate: Double?
    let photoCount: Int

    var totalHours: Int { totalSeconds / 3600 }
    var totalMinutesRemainder: Int { totalSeconds % 3600 / 60 }
    var movieCount: Int { max(1, totalSeconds / 7200) }
    var eiffelCount: Double { totalDescendedM / 330.0 }

    var sacImprovementPercent: Double? {
        guard let a = sacFirstHalf, let b = sacSecondHalf, a > 0 else { return nil }
        return (a - b) / a * 100
    }

    @MainActor
    static func compute(year: Int, dives: [Dive],
                        sites: SiteStore, photos: PhotoStore) -> YearStats {
        let cal = Calendar(identifier: .gregorian)
        var utcCal = cal
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let yearDives = dives.filter { utcCal.component(.year, from: $0.date) == year }

        let deepestDive = yearDives.max { $0.maxDepth < $1.maxDepth }
        let coldestDive = yearDives.min { $0.tempMin < $1.tempMin }

        var byDay: [String: Int] = [:]
        for d in yearDives { byDay[d.dayText, default: 0] += 1 }
        let busiest = byDay.max { $0.value < $1.value }

        var siteCounts: [String: Int] = [:]
        for d in yearDives {
            if let s = sites.site(for: d.id) { siteCounts[s.name, default: 0] += 1 }
        }
        let favorite = siteCounts.max { $0.value < $1.value }

        // SAC (pressure rate) halves, AI dives only
        func avgSAC(_ ds: [Dive]) -> Double? {
            let vals: [Double] = ds.compactMap { d in
                let ps = d.samples.compactMap { s in s.tank1Bar.map { (s.timeS, $0) } }
                guard let f = ps.first, let l = ps.last, l.0 > f.0, f.1 > l.1
                else { return nil }
                let ata = 1.0 + d.avgDepth / 10.0
                return (f.1 - l.1) / (Double(l.0 - f.0) / 60.0) / ata
            }
            guard vals.count >= 2 else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }
        let aiDives = yearDives.filter { $0.samples.contains { $0.tank1Bar != nil } }
        let mid = aiDives.count / 2
        let sacA = aiDives.count >= 4 ? avgSAC(Array(aiDives.prefix(mid))) : nil
        let sacB = aiDives.count >= 4 ? avgSAC(Array(aiDives.suffix(aiDives.count - mid))) : nil

        // stability: first vs last third of training dives
        let train = yearDives.filter { $0.training }.compactMap { $0.metrics?.stabilityM }
        let third = max(1, train.count / 3)
        func avg(_ a: [Double]) -> Double? {
            a.isEmpty ? nil : a.reduce(0, +) / Double(a.count)
        }
        let stabA = train.count >= 4 ? avg(Array(train.prefix(third))) : nil
        let stabB = train.count >= 4 ? avg(Array(train.suffix(third))) : nil

        return YearStats(
            year: year,
            diveCount: yearDives.count,
            totalSeconds: yearDives.map(\.durationS).reduce(0, +),
            deepest: deepestDive.map { ($0.maxDepth, $0.n, $0.dayText) },
            totalDescendedM: yearDives.map(\.maxDepth).reduce(0, +),
            coldest: coldestDive.map { ($0.tempMin, $0.n, $0.dayText) },
            busiestDay: busiest.map { ($0.value, $0.key) },
            favoriteSite: favorite.map { ($0.key, $0.value) },
            siteCount: siteCounts.count,
            sacFirstHalf: sacA,
            sacSecondHalf: sacB,
            stabilityEarly: stabA,
            stabilityLate: stabB,
            photoCount: yearDives.map { photos.count(for: $0.id) }.reduce(0, +)
        )
    }

    @MainActor
    static func availableYears(dives: [Dive]) -> [Int] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return Array(Set(dives.map { cal.component(.year, from: $0.date) })).sorted(by: >)
    }
}
