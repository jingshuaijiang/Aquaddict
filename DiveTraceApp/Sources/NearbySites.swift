import Foundation
import MapKit
import DiveKit

// Discover named dive sites around the user's GNSS dives via Apple Maps POI
// search: cluster unassigned dives (500 m), search each cluster's vicinity,
// and propose create+assign in one tap.

struct SiteCandidate: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distanceM: Double
    let source: String   // "Apple" | "OSM"
}

struct DiveCluster: Identifiable {
    let id = UUID()
    let center: CLLocationCoordinate2D
    let diveIDs: [UInt32]
    let diveNumbers: [Int]
    var candidates: [SiteCandidate] = []
}

enum NearbySites {
    static func cluster(_ dives: [Dive]) -> [DiveCluster] {
        var clusters: [(center: CLLocationCoordinate2D, dives: [Dive])] = []
        for dive in dives {
            guard let p = dive.anyLocation else { continue }
            let c = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
            if let i = clusters.firstIndex(where: {
                MKMapPoint($0.center).distance(to: MKMapPoint(c)) < 500
            }) {
                clusters[i].dives.append(dive)
            } else {
                clusters.append((c, [dive]))
            }
        }
        return clusters.map {
            DiveCluster(center: $0.center,
                        diveIDs: $0.dives.map(\.id),
                        diveNumbers: $0.dives.map(\.n))
        }
    }

    /// Search Apple Maps for dive-related POIs near a coordinate.
    static func searchCandidates(near center: CLLocationCoordinate2D,
                                 radiusM: Double = 5000) async -> [SiteCandidate] {
        var results: [SiteCandidate] = []
        for query in ["dive site", "scuba diving", loc("潜水", "diving")] {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(center: center,
                                                latitudinalMeters: radiusM * 2,
                                                longitudinalMeters: radiusM * 2)
            guard let response = try? await MKLocalSearch(request: request).start()
            else { continue }
            for item in response.mapItems {
                guard let name = item.name else { continue }
                let coord = item.placemark.coordinate
                let dist = MKMapPoint(center).distance(to: MKMapPoint(coord))
                guard dist <= radiusM else { continue }
                // dedupe by name
                if !results.contains(where: { $0.name == name }) {
                    results.append(SiteCandidate(name: name, coordinate: coord,
                                                 distanceM: dist, source: "Apple"))
                }
            }
        }

        // OpenStreetMap: dedicated scuba tags (great coverage of actual dive
        // sites, incl. spots Apple Maps doesn't know)
        for osm in await searchOSM(near: center, radiusM: radiusM) {
            if !results.contains(where: {
                $0.name == osm.name ||
                MKMapPoint($0.coordinate).distance(to: MKMapPoint(osm.coordinate)) < 100
            }) {
                results.append(osm)
            }
        }

        return results.sorted { $0.distanceM < $1.distanceM }.prefix(6).map { $0 }
    }

    /// Overpass API: nodes/ways tagged sport=scuba_diving or amenity=dive_centre.
    static func searchOSM(near center: CLLocationCoordinate2D,
                          radiusM: Double) async -> [SiteCandidate] {
        let around = "around:\(Int(radiusM)),\(center.latitude),\(center.longitude)"
        let query = """
        [out:json][timeout:10];
        (node["sport"="scuba_diving"](\(around));
         way["sport"="scuba_diving"](\(around));
         node["amenity"="dive_centre"](\(around)););
        out center 20;
        """
        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        request.httpBody = Data("data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")".utf8)
        request.timeoutInterval = 12

        struct Response: Decodable {
            struct Element: Decodable {
                struct Center: Decodable { let lat: Double; let lon: Double }
                let lat: Double?
                let lon: Double?
                let center: Center?
                let tags: [String: String]?
            }
            let elements: [Element]
        }

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(Response.self, from: data)
        else { return [] }

        var out: [SiteCandidate] = []
        for e in response.elements {
            let lat = e.lat ?? e.center?.lat
            let lon = e.lon ?? e.center?.lon
            guard let lat, let lon,
                  let name = e.tags?["name"] ?? e.tags?["name:en"] ?? e.tags?["name:zh"]
            else { continue }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let dist = MKMapPoint(center).distance(to: MKMapPoint(coord))
            guard dist <= radiusM else { continue }
            if !out.contains(where: { $0.name == name }) {
                out.append(SiteCandidate(name: name, coordinate: coord,
                                         distanceM: dist, source: "OSM"))
            }
        }
        return out
    }

    /// Full pipeline: cluster unassigned GNSS dives, search around each.
    static func discover(dives: [Dive]) async -> [DiveCluster] {
        var clusters = cluster(dives)
        for i in clusters.indices {
            clusters[i].candidates = await searchCandidates(near: clusters[i].center)
        }
        return clusters
    }
}
