import Foundation
import UIKit

// Per-dive photos, stored as JPEGs under Documents/Photos/<diveID>/.
// Keyed by the dive's PNF start timestamp, same as site assignments.
@MainActor @Observable
final class PhotoStore {
    static let shared = PhotoStore()

    private let root: URL
    private(set) var version = 0   // bump to refresh views after add/delete

    private init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func dir(_ diveID: UInt32) -> URL {
        let d = root.appendingPathComponent(String(diveID), isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func photos(for diveID: UInt32) -> [URL] {
        _ = version
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir(diveID), includingPropertiesForKeys: [.creationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "jpg" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
    }

    func add(_ image: UIImage, to diveID: UInt32) {
        // cap the long edge at 2500px to keep storage sane
        let maxEdge: CGFloat = 2500
        var img = image
        let long = max(image.size.width, image.size.height)
        if long > maxEdge {
            let scale = maxEdge / long
            let size = CGSize(width: image.size.width * scale,
                              height: image.size.height * scale)
            img = UIGraphicsImageRenderer(size: size).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let data = img.jpegData(compressionQuality: 0.85) else { return }
        let url = dir(diveID).appendingPathComponent(UUID().uuidString + ".jpg")
        try? data.write(to: url)
        version += 1
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        version += 1
    }

    func count(for diveID: UInt32) -> Int { photos(for: diveID).count }
}
