import Foundation
import DiveKit

// MARK: - test-side LRE compressor (literal-only + zero-runs + terminator)

/// Encodes bytes as 9-bit values per the Shearwater scheme: 0x100|byte for
/// literals, 1..255 for zero-runs, 0 to terminate; pads the tail to whole bytes.
func lreEncode(_ data: Data) -> Data {
    var values: [Int] = []
    var i = 0
    let bytes = [UInt8](data)
    while i < bytes.count {
        if bytes[i] == 0 {
            var run = 0
            while i < bytes.count, bytes[i] == 0, run < 255 { run += 1; i += 1 }
            values.append(run)
        } else {
            values.append(0x100 | Int(bytes[i]))
            i += 1
        }
    }
    values.append(0)   // terminator

    var out = Data()
    var acc = 0
    var accBits = 0
    for v in values {
        acc = (acc << 9) | v
        accBits += 9
        while accBits >= 8 {
            out.append(UInt8((acc >> (accBits - 8)) & 0xFF))
            accBits -= 8
        }
    }
    if accBits > 0 {
        out.append(UInt8((acc << (8 - accBits)) & 0xFF))
    }
    // stream must be a whole number of 9-bit values: pad to a multiple of 9 bytes
    while (out.count * 8) % 9 != 0 { out.append(0) }
    return out
}

/// Forward XOR-encode (inverse of decompressXOR): later blocks XORed with the
/// already-encoded previous block, computed back-to-front.
func xorEncode(_ data: Data) -> Data {
    var d = data
    if d.count > 32 {
        for i in stride(from: d.count - 1, through: 32, by: -1) {
            d[i] ^= data[i - 32]   // note: XOR with the *decoded* previous block
        }
    }
    return d
}

// MARK: - fake transport speaking the device side of the protocol

final class FakeShearwater: ShearwaterTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var inbox: [Data] = []      // chunks queued for the app to receive
    private var rxDecoder = SLIP.Decoder(v1Header: false)
    let v2: Bool
    let dives: [Data]                   // raw PNF blobs served by "the computer"
    private var uploadSource = Data()   // bytes being served by the active upload
    private var uploadOffset = 0
    private var uploadCompressed = false

    init(v2: Bool, dives: [Data]) {
        self.v2 = v2
        self.dives = dives
        rxDecoder = SLIP.Decoder(v1Header: !v2)
    }

    func send(_ chunk: Data) async throws {
        let packets = try rxDecoder.feed(chunk)
        for packet in packets {
            let payload = try ShearwaterFrame.parseResponse(swapHeader(packet), v2: v2)
            if let response = handle([UInt8](payload)) {
                let framed = ShearwaterFrame.buildRequest(response, v2: v2)
                // device responses use the mirrored 01 FF header
                let chunks = SLIP.encode(swapHeader(framed), v1Header: !v2, mtu: 200)
                pushInbox(chunks)
            }
        }
    }

    private func pushInbox(_ chunks: [Data]) {
        lock.lock()
        defer { lock.unlock() }
        inbox.append(contentsOf: chunks)
    }

    private func popInbox() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return inbox.isEmpty ? nil : inbox.removeFirst()
    }

    func receive() async throws -> Data {
        while true {
            if let next = popInbox() { return next }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    /// Requests are FF 01 …, responses 01 FF … — same layout otherwise.
    private func swapHeader(_ packet: Data) -> Data {
        var p = packet
        let a = p[p.startIndex]
        p[p.startIndex] = p[p.startIndex + 1]
        p[p.startIndex + 1] = a
        return p
    }

    private func manifestData() -> Data {
        var m = Data()
        for (i, dive) in dives.enumerated() {
            var rec = Data(count: 32)
            rec[0] = 0xA5; rec[1] = 0xC4
            rec[2] = UInt8(i + 1)                       // pseudo dive number
            let addr = UInt32(0x1000 * (i + 1))
            rec[20] = UInt8(addr >> 24 & 0xFF); rec[21] = UInt8(addr >> 16 & 0xFF)
            rec[22] = UInt8(addr >> 8 & 0xFF); rec[23] = UInt8(addr & 0xFF)
            m.append(rec)
            _ = dive
        }
        return m
    }

    private func handle(_ req: [UInt8]) -> Data? {
        switch req.first {
        case 0x22:   // RDBI
            let id = UInt16(req[1]) << 8 | UInt16(req[2])
            var v: Data
            switch id {
            case ShearwaterID.serial: v = Data("9D8ACD80".utf8)
            case ShearwaterID.firmware: v = Data("V81".utf8)
            case ShearwaterID.model: v = Data([ShearwaterModel.peregrine.rawValue])
            case ShearwaterID.logUpload: v = Data([0x00, 0x80, 0x00, 0x00, 0x00, 0, 0, 0, 0])
            default: v = Data()
            }
            return Data([0x62, req[1], req[2]]) + v
        case 0x2E:   // WDBI (close) — no response expected
            return nil
        case 0x35:   // upload init
            let addr = UInt32(req[3]) << 24 | UInt32(req[4]) << 16
                     | UInt32(req[5]) << 8 | UInt32(req[6])
            uploadCompressed = req[1] == 0x10
            if addr == ShearwaterSession.manifestAddress {
                uploadSource = manifestData()
            } else {
                let index = Int((addr & 0x00FF_FFFF) / 0x1000) - 1
                let dive = dives[index]
                uploadSource = uploadCompressed ? lreEncode(xorEncode(dive)) : dive
            }
            uploadOffset = 0
            return Data([0x75, 0x10, 0x90])   // max block length 0x90
        case 0x36:   // upload block
            let block = req[1]
            let chunkLen = min(0x90, uploadSource.count - uploadOffset)
            let chunk = uploadSource.subdata(in: uploadOffset ..< uploadOffset + chunkLen)
            uploadOffset += chunkLen
            return Data([0x76, block]) + chunk
        case 0x37:   // upload exit
            return Data([0x77])
        default:
            return Data([0x7F])   // NAK
        }
    }
}

// MARK: - tests

func shearwaterProtocolTests() {
    runTest("slipRoundtripWithEscapes") {
        let payload = Data([0x01, 0xC0, 0xDB, 0xFF, 0xC0, 0x00])
        for v1 in [true, false] {
            let frames = SLIP.encode(payload, v1Header: v1, mtu: 5)
            var decoder = SLIP.Decoder(v1Header: v1)
            var packets: [Data] = []
            for f in frames { packets += try decoder.feed(f) }
            expectEqual(packets.count, 1, "one packet (v1Header=\(v1))")
            expectEqual(Array(packets[0]), Array(payload), "roundtrip (v1Header=\(v1))")
        }
    }

    runTest("frameBuildParseRoundtrip") {
        for v2 in [false, true] {
            let payload = Data([0x22, 0x80, 0x10])
            var framed = ShearwaterFrame.buildRequest(payload, v2: v2)
            // convert request header to response header for parsing
            framed[framed.startIndex] = 0x01
            framed[framed.startIndex + 1] = 0xFF
            let parsed = try ShearwaterFrame.parseResponse(framed, v2: v2)
            expectEqual(Array(parsed), Array(payload), "frame roundtrip v2=\(v2)")
        }
    }

    runTest("lreRoundtripAndXor") {
        let raw = try loadFixture("dive_046.pnf.bin")
        var decoded = Data()
        let isFinal = try ShearwaterCompression.decompressLRE(lreEncode(raw), into: &decoded)
        expect(isFinal, "stream terminated")
        expectEqual(decoded.count, raw.count, "LRE roundtrip length")
        expect(decoded == raw, "LRE roundtrip bytes")

        var x = xorEncode(raw)
        ShearwaterCompression.decompressXOR(&x)
        expect(x == raw, "XOR roundtrip")
    }

    runTest("manifestParsing") {
        var m = Data(count: 32); m[0] = 0xA5; m[1] = 0xC4; m[23] = 0x10
        var deleted = Data(count: 32); deleted[0] = 0x5A; deleted[1] = 0x23
        let records = ManifestRecord.parseManifest(m + deleted + m + Data(count: 32))
        expectEqual(records.count, 2, "two live dives")
        expectEqual(records[0].address, 0x10, "address parsed")
    }

    // Full flow against the simulated computer, V1 (Peregrine) and V2 (Perdix 3)
    for v2 in [false, true] {
        runTest("fullSessionDownload(v2=\(v2))") {
            let dive = try loadFixture("dive_046.pnf.bin")
            let fake = FakeShearwater(v2: v2, dives: [dive])
            let session = ShearwaterSession(
                transport: fake,
                model: v2 ? .perdix3 : .peregrine)

            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: Result<Data, Error>?
            Task {
                do {
                    let info = try await session.deviceInfo()
                    expectEqual(info.serial, "9D8ACD80", "serial")
                    expectEqual(info.model, .peregrine, "model id")
                    let base = try await session.logBaseAddress()
                    expectEqual(base, 0x8000_0000, "base address")
                    let manifest = try await session.readManifest()
                    expectEqual(manifest.count, 1, "manifest entries")
                    let data = try await session.downloadDive(manifest[0], baseAddress: base)
                    try await session.close()
                    result = .success(data)
                } catch {
                    result = .failure(error)
                }
                sem.signal()
            }
            sem.wait()

            let downloaded = try result!.get()
            expect(downloaded == dive, "downloaded bytes identical to source")
            let (header, samples) = try PNFParser.parse(downloaded)
            expectEqual(header.gfLow, 40, "parsed GF low")
            expectEqual(samples.count, 303, "parsed sample count")
        }
    }
}
