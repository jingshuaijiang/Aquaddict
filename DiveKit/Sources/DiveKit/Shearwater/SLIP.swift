import Foundation

// SLIP framing as used by Shearwater's serial-over-GATT link
// (RFC 1055 with Shearwater's BLE chunk header on the V1 protocol).

public enum SLIP {
    public static let end: UInt8 = 0xC0
    public static let esc: UInt8 = 0xDB
    public static let escEnd: UInt8 = 0xDC
    public static let escEsc: UInt8 = 0xDD

    /// Escape + terminate a packet, splitting into BLE writes.
    /// V1 BLE prefixes every chunk with [totalFrames, frameIndex]; V2 does not.
    public static func encode(_ payload: Data, v1Header: Bool, mtu: Int = 20) -> [Data] {
        var stuffed = Data()
        for b in payload {
            switch b {
            case end: stuffed.append(contentsOf: [esc, escEnd])
            case esc: stuffed.append(contentsOf: [esc, escEsc])
            default: stuffed.append(b)
            }
        }
        stuffed.append(end)

        guard v1Header else { return [stuffed] }

        let body = mtu - 2
        let frames = (stuffed.count + body - 1) / body
        var out: [Data] = []
        var index = 0
        var offset = 0
        while offset < stuffed.count {
            let chunk = stuffed.subdata(in: offset ..< min(offset + body, stuffed.count))
            var frame = Data([UInt8(frames), UInt8(index)])
            frame.append(chunk)
            out.append(frame)
            index += 1
            offset += body
        }
        return out
    }

    /// Incremental decoder: feed transport chunks, complete packets pop out.
    public struct Decoder {
        private var escaped = false
        private var packet = Data()
        public var v1Header: Bool

        public init(v1Header: Bool) { self.v1Header = v1Header }

        public mutating func feed(_ chunk: Data) throws -> [Data] {
            var out: [Data] = []
            let body = v1Header ? chunk.dropFirst(2) : chunk[...]
            for b in body {
                if b == SLIP.end || b == SLIP.esc {
                    if escaped { throw ShearwaterError.slipViolation }
                    if b == SLIP.end {
                        if !packet.isEmpty { out.append(packet); packet = Data() }
                    } else {
                        escaped = true
                    }
                    continue
                }
                var c = b
                if escaped {
                    if b == SLIP.escEnd { c = SLIP.end }
                    else if b == SLIP.escEsc { c = SLIP.esc }
                    escaped = false
                }
                packet.append(c)
            }
            return out
        }
    }
}

public enum ShearwaterError: Error, Equatable {
    case slipViolation
    case badPacketHeader
    case badResponse(expected: UInt8, got: UInt8)
    case decompressionFailed
    case unknownLogFormat(UInt32)
    case transportClosed
}
