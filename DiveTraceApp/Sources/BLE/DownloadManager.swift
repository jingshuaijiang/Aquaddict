import Foundation
import DiveKit

/// Orchestrates a download session: connect → identify → manifest → fetch only
/// new dives (fingerprint = manifest record bytes, remembered per serial) →
/// persist raw PNF into Documents so DiveStore picks them up.
@MainActor @Observable
final class DownloadManager {
    enum Phase: Equatable {
        case idle
        case connecting(String)
        case readingManifest
        case downloading(current: Int, total: Int)
        case done(new: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    static let divesDirectory: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dives", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func knownFingerprints(serial: String) -> Set<Data> {
        let key = "fingerprints.\(serial)"
        let arr = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        return Set(arr)
    }

    private func rememberFingerprints(_ fps: Set<Data>, serial: String) {
        UserDefaults.standard.set(Array(fps), forKey: "fingerprints.\(serial)")
    }

    func download(from device: DiscoveredDevice, ble: BLEManager,
                  store: DiveStore) async {
        phase = .connecting(device.name)
        do {
            let transport = try await ble.connect(device)
            let session = ShearwaterSession(transport: transport,
                                            model: device.model,
                                            mtu: transport.writeChunkSize)
            let info = try await session.deviceInfo()
            let base = try await session.logBaseAddress()

            phase = .readingManifest
            let manifest = try await session.readManifest()
            var known = knownFingerprints(serial: info.serial)
            let fresh = manifest.filter { !known.contains($0.raw) }

            var newCount = 0
            for (i, record) in fresh.enumerated() {
                phase = .downloading(current: i + 1, total: fresh.count)
                let pnf = try await session.downloadDive(record, baseAddress: base)
                guard let (header, samples) = try? PNFParser.parse(pnf), !samples.isEmpty
                else { continue }
                let url = Self.divesDirectory
                    .appendingPathComponent("\(header.startTimestamp)_\(info.serial).pnf")
                try pnf.write(to: url)
                known.insert(record.raw)
                newCount += 1
            }
            rememberFingerprints(known, serial: info.serial)
            try? await session.close()
            ble.disconnect()

            store.reloadFromDisk()
            phase = .done(new: newCount)
        } catch {
            ble.disconnect()
            phase = .failed(String(describing: error))
        }
    }
}
