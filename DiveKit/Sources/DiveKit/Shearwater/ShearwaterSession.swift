import Foundation

/// Anything that can move raw bytes to/from a Shearwater computer.
/// The iOS app provides a CoreBluetooth implementation; tests use a fake.
public protocol ShearwaterTransport: Sendable {
    /// Write one chunk (one BLE characteristic write).
    func send(_ chunk: Data) async throws
    /// Receive the next chunk (one BLE notification). Throws when closed.
    func receive() async throws -> Data
}

public struct ShearwaterDeviceInfo: Sendable, Equatable {
    public let serial: String
    public let firmware: String
    public let model: ShearwaterModel?
}

/// Application-level session: request/response transfer, device identification,
/// manifest enumeration and dive download — transport-agnostic and fully
/// exercisable in tests via a fake transport.
public actor ShearwaterSession {
    public static let manifestAddress: UInt32 = 0xE000_0000
    public static let manifestSize = 0x600
    public static let diveSize = 0xFF_FFFF

    private let transport: any ShearwaterTransport
    private let v2: Bool
    private let mtu: Int

    public init(transport: any ShearwaterTransport, model: ShearwaterModel?, mtu: Int = 20) {
        self.transport = transport
        self.v2 = model?.usesV2 ?? false
        self.mtu = mtu
    }

    // MARK: transfer

    public func transfer(_ payload: Data, expectResponse: Bool = true) async throws -> Data {
        let request = ShearwaterFrame.buildRequest(payload, v2: v2)
        for chunk in SLIP.encode(request, v1Header: !v2, mtu: mtu) {
            try await transport.send(chunk)
        }
        guard expectResponse else { return Data() }

        var decoder = SLIP.Decoder(v1Header: !v2)
        while true {
            let chunk = try await transport.receive()
            if let packet = try decoder.feed(chunk).first {
                return try ShearwaterFrame.parseResponse(packet, v2: v2)
            }
        }
    }

    // MARK: identifiers

    public func readIdentifier(_ id: UInt16) async throws -> Data {
        let payload = Data([0x22, UInt8(id >> 8), UInt8(id & 0xFF)])
        let response = try await transfer(payload)
        let b = [UInt8](response)
        guard b.count >= 3, b[0] == 0x62, b[1] == UInt8(id >> 8), b[2] == UInt8(id & 0xFF) else {
            throw ShearwaterError.badResponse(expected: 0x62, got: b.first ?? 0)
        }
        return response.suffix(response.count - 3)
    }

    public func deviceInfo() async throws -> ShearwaterDeviceInfo {
        let serialRaw = try await readIdentifier(ShearwaterID.serial)
        let firmwareRaw = try await readIdentifier(ShearwaterID.firmware)
        let modelRaw = try await readIdentifier(ShearwaterID.model)
        return ShearwaterDeviceInfo(
            serial: String(data: serialRaw, encoding: .ascii) ?? serialRaw.map {
                String(format: "%02X", $0)
            }.joined(),
            firmware: String(data: firmwareRaw, encoding: .ascii) ?? "?",
            model: modelRaw.first.flatMap(ShearwaterModel.init(rawValue:))
        )
    }

    /// PNF base address advertised by the computer (0x80000000 for current firmware).
    public func logBaseAddress() async throws -> UInt32 {
        let info = try await readIdentifier(ShearwaterID.logUpload)
        let b = [UInt8](info)
        guard b.count >= 5 else { throw ShearwaterError.badPacketHeader }
        let addr = UInt32(b[1]) << 24 | UInt32(b[2]) << 16 | UInt32(b[3]) << 8 | UInt32(b[4])
        switch addr {
        case 0xDD00_0000, 0xC000_0000, 0x9000_0000: return 0xC000_0000
        case 0x8000_0000: return 0x8000_0000
        default: throw ShearwaterError.unknownLogFormat(addr)
        }
    }

    // MARK: bulk download (0x35 init / 0x36 blocks / 0x37 exit)

    public func download(address: UInt32, size: Int, compressed: Bool,
                         progress: (@Sendable (Int) -> Void)? = nil) async throws -> Data {
        var initReq = Data([0x35, compressed ? 0x10 : 0x00, 0x34])
        initReq.append(contentsOf: [
            UInt8(address >> 24 & 0xFF), UInt8(address >> 16 & 0xFF),
            UInt8(address >> 8 & 0xFF), UInt8(address & 0xFF),
            UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF),
        ])
        let initRsp = [UInt8](try await transfer(initReq))
        guard initRsp.count >= 2, initRsp[0] == 0x75 else {
            throw ShearwaterError.badResponse(expected: 0x75, got: initRsp.first ?? 0)
        }

        var out = Data()
        var block: UInt8 = 1
        var received = 0
        var done = false
        while received < size, !done {
            let blockReq = v2 ? Data([0x36, block, 0x00]) : Data([0x36, block])
            let rsp = try await transfer(blockReq)
            let b = [UInt8](rsp)
            guard b.count >= 2, b[0] == 0x76, b[1] == block else {
                throw ShearwaterError.badResponse(expected: 0x76, got: b.first ?? 0)
            }
            let payload = rsp.suffix(rsp.count - 2)
            if payload.isEmpty { break }
            if compressed {
                done = try ShearwaterCompression.decompressLRE(payload, into: &out)
            } else {
                out.append(payload)
            }
            received += payload.count
            block &+= 1
            progress?(received)
        }
        if compressed {
            ShearwaterCompression.decompressXOR(&out)
        }

        let exitRsp = [UInt8](try await transfer(Data([0x37])))
        guard exitRsp.first == 0x77 else {
            throw ShearwaterError.badResponse(expected: 0x77, got: exitRsp.first ?? 0)
        }
        return out
    }

    // MARK: high-level flow

    public func readManifest() async throws -> [ManifestRecord] {
        let raw = try await download(address: Self.manifestAddress,
                                     size: Self.manifestSize, compressed: false)
        return ManifestRecord.parseManifest(raw)
    }

    public func downloadDive(_ record: ManifestRecord, baseAddress: UInt32,
                             progress: (@Sendable (Int) -> Void)? = nil) async throws -> Data {
        try await download(address: baseAddress &+ record.address,
                           size: Self.diveSize, compressed: true, progress: progress)
    }

    /// Politely leave upload mode (WDBI 0x9020 = 0).
    public func close() async throws {
        _ = try await transfer(Data([0x2E, 0x90, 0x20, 0x00]), expectResponse: false)
    }
}
