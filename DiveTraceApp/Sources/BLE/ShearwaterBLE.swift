import CoreBluetooth
import DiveKit
import Foundation

// Shearwater's vendor GATT service (same on every BLE model).
enum ShearwaterGATT {
    nonisolated(unsafe) static let service =
        CBUUID(string: "FE25C237-0ECE-443C-B0AA-E02033E7029D")
    nonisolated(unsafe) static let characteristic =
        CBUUID(string: "27B7570B-359E-45A3-91BB-CF7E70049BD2")
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

/// Scans for Shearwater computers and hands out connected transports.
@MainActor @Observable
final class BLEManager: NSObject {
    private(set) var devices: [DiscoveredDevice] = []
    private(set) var isScanning = false
    private(set) var bluetoothOff = false

    private var central: CBCentralManager!
    private var connectContinuation: CheckedContinuation<BLEPeripheralTransport, Error>?
    private var activeTransport: BLEPeripheralTransport?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        devices = []
        guard central.state == .poweredOn else { return }
        isScanning = true
        central.scanForPeripherals(withServices: [ShearwaterGATT.service])
    }

    func stopScan() {
        isScanning = false
        central.stopScan()
    }

    func connect(_ device: DiscoveredDevice) async throws -> BLEPeripheralTransport {
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
            central.scanForPeripherals(withServices: [ShearwaterGATT.service])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? "Shearwater"
        let device = DiscoveredDevice(peripheral: peripheral, name: name, rssi: RSSI.intValue)
        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            devices[idx] = device
        } else {
            devices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let transport = BLEPeripheralTransport(peripheral: peripheral) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let t): self?.activeTransport = t
                                      self?.connectContinuation?.resume(returning: t)
                case .failure(let e): self?.connectContinuation?.resume(throwing: e)
                }
                self?.connectContinuation = nil
            }
        }
        transport.discover()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        connectContinuation?.resume(throwing: error ?? ShearwaterError.transportClosed)
        connectContinuation = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
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
        peripheral.discoverServices([ShearwaterGATT.service])
    }

    var writeChunkSize: Int {
        max(20, peripheral.maximumWriteValueLength(for: .withoutResponse))
    }

    func send(_ chunk: Data) async throws {
        guard let characteristic else { throw ShearwaterError.transportClosed }
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
        guard let service = peripheral.services?.first(where: { $0.uuid == ShearwaterGATT.service })
        else { onReady(.failure(ShearwaterError.transportClosed)); return }
        peripheral.discoverCharacteristics([ShearwaterGATT.characteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let ch = service.characteristics?.first(where: {
            $0.uuid == ShearwaterGATT.characteristic
        }) else { onReady(.failure(ShearwaterError.transportClosed)); return }
        characteristic = ch
        peripheral.setNotifyValue(true, for: ch)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            onReady(.failure(error))
        } else {
            onReady(.success(self))
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value, !value.isEmpty else { return }
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
