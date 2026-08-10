import Foundation

// Shearwater application-layer protocol, per libdivecomputer shearwater_common.c:
// request  FF 01 [len+1] 00 <payload>            (V1, all models except Perdix 3)
//          FF 01 00 [len_hi] [len_lo] <payload>  (V2, Perdix 3)
// response 01 FF mirrored headers.

public enum ShearwaterModel: UInt8, Sendable {
    case predator = 2, petrel = 3, nerd = 4, perdix = 5, perdixAI = 6
    case nerd2 = 7, teric = 8, peregrine = 9, petrel3 = 10, perdix2 = 11
    case tern = 12, peregrineTX = 13, perdix3 = 14

    public var usesV2: Bool { self == .perdix3 }

    public var displayName: String {
        switch self {
        case .predator: "Predator"; case .petrel: "Petrel"; case .nerd: "NERD"
        case .perdix: "Perdix"; case .perdixAI: "Perdix AI"; case .nerd2: "NERD 2"
        case .teric: "Teric"; case .peregrine: "Peregrine"; case .petrel3: "Petrel 3"
        case .perdix2: "Perdix 2"; case .tern: "Tern"; case .peregrineTX: "Peregrine TX"
        case .perdix3: "Perdix 3"
        }
    }
}

public enum ShearwaterID {
    public static let serial: UInt16 = 0x8010
    public static let firmware: UInt16 = 0x8011
    public static let logUpload: UInt16 = 0x8021
    public static let hardware: UInt16 = 0x8050
    public static let model: UInt16 = 0x8060
}

public enum ShearwaterFrame {
    /// Wrap an application payload in the FF 01 request header.
    public static func buildRequest(_ payload: Data, v2: Bool) -> Data {
        var out = Data([0xFF, 0x01])
        if v2 {
            out.append(0x00)
            out.append(UInt8(payload.count >> 8))
            out.append(UInt8(payload.count & 0xFF))
        } else {
            out.append(UInt8(payload.count + 1))
            out.append(0x00)
        }
        out.append(payload)
        return out
    }

    /// Unwrap a 01 FF response header, returning the application payload.
    public static func parseResponse(_ packet: Data, v2: Bool) throws -> Data {
        let p = [UInt8](packet)
        let headerLen = v2 ? 5 : 4
        let zeroIdx = v2 ? 2 : 3
        guard p.count >= headerLen, p[0] == 0x01, p[1] == 0xFF, p[zeroIdx] == 0x00 else {
            throw ShearwaterError.badPacketHeader
        }
        let length: Int
        if v2 {
            length = Int(p[3]) << 8 | Int(p[4])
        } else {
            guard p[2] >= 1 else { throw ShearwaterError.badPacketHeader }
            length = Int(p[2]) - 1
        }
        guard length + headerLen == p.count else { throw ShearwaterError.badPacketHeader }
        return packet.suffix(length)
    }
}

public enum ShearwaterCompression {
    /// 9-bit run-length decoding: bit 8 set = literal byte, else a run of
    /// `value` zero bytes; a zero-length run terminates the stream.
    public static func decompressLRE(_ data: Data, into buffer: inout Data) throws -> Bool {
        let bytes = [UInt8](data)
        let nbits = bytes.count * 8
        guard nbits % 9 == 0 else { throw ShearwaterError.decompressionFailed }
        var isFinal = false
        var offset = 0
        while offset + 9 <= nbits {
            let byte = offset / 8
            let bit = offset % 8
            let hi = Int(bytes[byte]) << 8 | Int(byte + 1 < bytes.count ? bytes[byte + 1] : 0)
            let value = (hi >> (16 - (bit + 9))) & 0x1FF
            if value & 0x100 != 0 {
                buffer.append(UInt8(value & 0xFF))
            } else if value == 0 {
                isFinal = true
                break
            } else {
                buffer.append(Data(count: value))
            }
            offset += 9
        }
        return isFinal
    }

    /// Undo the per-32-byte-block XOR chaining (in place, forward).
    public static func decompressXOR(_ data: inout Data) {
        guard data.count > 32 else { return }
        for i in 32 ..< data.count {
            data[i] ^= data[i - 32]
        }
    }
}

/// One 32-byte manifest record. 0xA5C4 marks a dive, 0x5A23 a deleted dive.
public struct ManifestRecord: Sendable, Equatable {
    public static let diveHeader: UInt16 = 0xA5C4
    public static let deletedHeader: UInt16 = 0x5A23

    public let raw: Data          // full 32 bytes — also serves as the fingerprint
    public let address: UInt32    // dive data address (relative to the base address)

    public var code: UInt16 {
        let b = [UInt8](raw)
        return UInt16(b[0]) << 8 | UInt16(b[1])
    }

    /// Parse a downloaded manifest blob into dive records (deleted ones skipped).
    public static func parseManifest(_ data: Data) -> [ManifestRecord] {
        var out: [ManifestRecord] = []
        let bytes = [UInt8](data)
        var offset = 0
        while offset + 32 <= bytes.count {
            let header = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            if header == diveHeader {
                let addr = UInt32(bytes[offset + 20]) << 24
                    | UInt32(bytes[offset + 21]) << 16
                    | UInt32(bytes[offset + 22]) << 8
                    | UInt32(bytes[offset + 23])
                out.append(ManifestRecord(raw: Data(bytes[offset ..< offset + 32]),
                                          address: addr))
            } else if header != deletedHeader {
                break   // end of manifest
            }
            offset += 32
        }
        return out
    }
}
