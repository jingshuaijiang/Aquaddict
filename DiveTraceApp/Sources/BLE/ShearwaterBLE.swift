import CoreBluetooth
import DiveKit
import Foundation

// Shearwater vendor GATT services: the classic one (Perdix/Teric/Peregrine/
// Tern/…) and the Perdix 3's new one (per Subsurface's device table).
enum ShearwaterGATT {
    nonisolated(unsafe) static let service =
        CBUUID(string: "FE25C237-0ECE-443C-B0AA-E02033E7029D")
    nonisolated(unsafe) static let servicePerdix3 =
        CBUUID(string: "1AA44039-1667-4B29-87CC-DFECAAF31D97")
    nonisolated(unsafe) static var knownServices: [CBUUID] { [service, servicePerdix3] }
}

struct DiscoveredDevice: Identifiable {
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    var id: UUID { peripheral.identifier }

    var model: ShearwaterModel? {
        // Advertised names look like "Perdix 3", "Peregrine", "Petrel 3"…
        let n = name.lowercased()
        if n.contains("perdix 3") { return .perdix3 }
        if n.contains("perdix 2") { return .perdix2 }
        if n.contains("perdix ai") { return .perdixAI }
        if n.contains("perdix") { return .perdix }
        if n.contains("peregrine tx") { return .peregrineTX }
        if n.contains("peregrine") { return .peregrine }
        if n.contains("petrel 3") { return .petrel3 }
        if n.contains("petrel") { return .petrel }
        if n.contains("teric") { return .teric }
        if n.contains("tern") { return .tern }
        if n.contains("nerd") { return .nerd2 }
        return nil
    }
}

/// On-screen debug trace so BLE issues are visible without a console.
@Observable
final class BLELog: @unchecked Sendable {
    static let shared = BLELog()
    private(set) var lines: [String] = []   // mutated on the main actor only
    @MainActor func add(_ line: String) {
        lines.append(line)
        if lines.count > 12 { lines.removeFirst() }
        print("BLE: \(line)")
    }
    nonisolated func post(_ line: String) {
        Task { @MainActor in self.add(line) }
    }
}

/// Scans for Shearwater computers and hands out connected transports.
@MainActor @Observable
final class BLEManager: NSObject {
    private(set) var devices: [DiscoveredDevice] = []
    private(set) var isScanning = false
    private(set) var bluetoothOff = false

    private var central: CBCentralManager!
    private var connectContinuation: CheckedContinuation<BLEPeripheralTransport, Error>?
    private var activeTransport: BLEPeripheralTransport?
    // Strong reference during discovery — CBPeripheral.delegate is weak, so the
    // transport must be kept alive until onReady fires.
    private var pendingTransport: BLEPeripheralTransport?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        devices = []
        isScanning = true
        guard central.state == .poweredOn else { return }
        // Scan unfiltered: Shearwater computers don't reliably include the
        // vendor service UUID in their advertisement packets.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        isScanning = false
        central.stopScan()
    }

    func connect(_ device: DiscoveredDevice) async throws -> BLEPeripheralTransport {
        BLELog.shared.add("connect → \(device.name) state=\(device.peripheral.state.rawValue)")
        stopScan()
        return try await withCheckedThrowingContinuation { cont in
            connectContinuation = cont
            central.connect(device.peripheral)
        }
    }

    func disconnect() {
        if let p = activeTransport?.peripheral {
            central.cancelPeripheralConnection(p)
        }
        activeTransport = nil
    }
}

extension BLEManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothOff = central.state != .poweredOn
        if central.state == .poweredOn, isScanning {
            central.scanForPeripherals(withServices: nil,
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    private static let knownNames = ["perdix", "peregrine", "petrel", "teric",
                                     "tern", "nerd", "predator", "shearwater"]

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? ""
        let advertised = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let lower = name.lowercased()
        // Keep only Shearwater computers: match by name, or by advertised service.
        guard Self.knownNames.contains(where: lower.contains)
            || advertised.contains(where: ShearwaterGATT.knownServices.contains) else { return }
        let device = DiscoveredDevice(peripheral: peripheral, name: name, rssi: RSSI.intValue)
        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            devices[idx] = device
        } else {
            devices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        BLELog.shared.add("didConnect \(peripheral.name ?? "?")")
        let transport = BLEPeripheralTransport(peripheral: peripheral) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let t): self?.activeTransport = t
                                      self?.connectContinuation?.resume(returning: t)
                case .failure(let e): self?.connectContinuation?.resume(throwing: e)
                }
                self?.connectContinuation = nil
                self?.pendingTransport = nil
            }
        }
        pendingTransport = transport
        transport.discover()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        BLELog.shared.add("didFailToConnect \(String(describing: error))")
        connectContinuation?.resume(throwing: error ?? ShearwaterError.transportClosed)
        connectContinuation = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        BLELog.shared.add("didDisconnect err=\(String(describing: error))")
        activeTransport?.didDisconnect()
        activeTransport = nil
    }
}

/// ShearwaterTransport over one connected CBPeripheral: writes go to the
/// vendor characteristic, notifications feed an async chunk queue.
final class BLEPeripheralTransport: NSObject, ShearwaterTransport, @unchecked Sendable {
    let peripheral: CBPeripheral
    private let onReady: (Result<BLEPeripheralTransport, Error>) -> Void
    private var characteristic: CBCharacteristic?

    private let lock = NSLock()
    private var chunkQueue: [Data] = []
    private var waiter: CheckedContinuation<Data, Error>?
    private var closed = false

    init(peripheral: CBPeripheral,
         onReady: @escaping (Result<BLEPeripheralTransport, Error>) -> Void) {
        self.peripheral = peripheral
        self.onReady = onReady
        super.init()
        peripheral.delegate = self
    }

    func discover() {
        BLELog.shared.post("discovering services…")
        peripheral.discoverServices(nil)
    }

    var writeChunkSize: Int {
        max(20, peripheral.maximumWriteValueLength(for: .withoutResponse))
    }

    func send(_ chunk: Data) async throws {
        guard let characteristic else { throw ShearwaterError.transportClosed }
        BLELog.shared.post("tx \(chunk.prefix(12).map { String(format: "%02x", $0) }.joined())")
        peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
    }

    func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if closed {
                lock.unlock()
                cont.resume(throwing: ShearwaterError.transportClosed)
            } else if chunkQueue.isEmpty {
                waiter = cont
                lock.unlock()
            } else {
                let chunk = chunkQueue.removeFirst()
                lock.unlock()
                cont.resume(returning: chunk)
            }
        }
    }

    func didDisconnect() {
        lock.lock()
        closed = true
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume(throwing: ShearwaterError.transportClosed)
    }
}

extension BLEPeripheralTransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        BLELog.shared.post("services err=\(error != nil) found=\(peripheral.services?.map { $0.uuid.uuidString.prefix(8) } ?? [])")
        guard let service = peripheral.services?.first(where: {
            ShearwaterGATT.knownServices.contains($0.uuid)
        }) else { onReady(.failure(ShearwaterError.transportClosed)); return }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let props = service.characteristics?.map {
            "\($0.uuid.uuidString.prefix(8)):\($0.properties.rawValue)"
        } ?? []
        BLELog.shared.post("chars err=\(error != nil) \(props)")
        // Pick by capability: some models use one characteristic for both
        // directions, the Perdix 3 may split write and notify.
        let chars = service.characteristics ?? []
        let writable = chars.first { $0.properties.contains(.writeWithoutResponse)
                                  || $0.properties.contains(.write) }
        let notifying = chars.first { $0.properties.contains(.notify)
                                   || $0.properties.contains(.indicate) }
        guard let writable, let notifying else {
            onReady(.failure(ShearwaterError.transportClosed)); return
        }
        characteristic = writable
        peripheral.setNotifyValue(true, for: notifying)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        BLELog.shared.post("notify err=\(String(describing: error)) on=\(characteristic.isNotifying)")
        if let error {
            onReady(.failure(error))
        } else {
            onReady(.success(self))
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value, !value.isEmpty else { return }
        BLELog.shared.post("rx \(value.prefix(12).map { String(format: "%02x", $0) }.joined())")
        lock.lock()
        if let w = waiter {
            waiter = nil
            lock.unlock()
            w.resume(returning: value)
        } else {
            chunkQueue.append(value)
            lock.unlock()
        }
    }
}
