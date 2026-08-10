import Foundation

// Parser for Shearwater's Petrel Native Format (PNF): a stream of 32-byte
// records. Record type is byte 0: 0x01 dive sample, 0x10-0x19 opening blocks,
// 0x20-0x29 closing blocks, 0xFF final. Field offsets follow libdivecomputer's
// shearwater_predator_parser.c (PNF branch) and are verified against golden
// fixtures produced by the Python reference parser from real dive data.

public enum PNFError: Error, Equatable {
    case truncated
    case missingOpeningRecord(Int)
}

public enum PNFParser {
    static let recordSize = 32
    static let feet = 0.3048

    public static func parse(_ data: Data) throws -> (header: DiveHeader, samples: [DiveSample]) {
        let bytes = [UInt8](data)
        guard bytes.count >= recordSize else { throw PNFError.truncated }

        var opening: [Int: [UInt8]] = [:]
        var records: [[UInt8]] = []
        var i = 0
        while i + recordSize <= bytes.count {
            let rec = Array(bytes[i ..< i + recordSize])
            records.append(rec)
            if (0x10 ... 0x19).contains(rec[0]) {
                opening[Int(rec[0]) - 0x10] = rec
            }
            i += recordSize
        }
        for required in 0 ... 4 where opening[required] == nil {
            throw PNFError.missingOpeningRecord(required)
        }

        func be16(_ buf: [UInt8], _ off: Int) -> Int {
            Int(buf[off]) << 8 | Int(buf[off + 1])
        }

        let o0 = opening[0]!, o2 = opening[2]!, o4 = opening[4]!
        let imperial = o0[8] == 1
        let logVersion = Int(o4[16])

        let intervalMs: Int
        if logVersion >= 9, let o5 = opening[5] {
            intervalMs = be16(o5, 23)
        } else {
            intervalMs = 10000
        }

        let decoRaw = o2[18]
        let header = DiveHeader(
            imperial: imperial,
            logVersion: logVersion,
            intervalMs: intervalMs,
            gfLow: Int(o0[4]),
            gfHigh: Int(o0[5]),
            decoModel: DecoModel(rawByte: decoRaw),
            vpmbConservatism: (decoRaw == 1 || decoRaw == 2) ? Int(o2[19]) : nil,
            surfaceMbar: be16(opening[1]!, 16),
            waterDensity: be16(opening[3]!, 3),
            mode: logVersion >= 8 ? DiveMode(rawByte: o4[1]) : .unknown,
            startTimestamp: UInt32(o0[12]) << 24 | UInt32(o0[13]) << 16
                | UInt32(o0[14]) << 8 | UInt32(o0[15])
        )

        var samples: [DiveSample] = []
        var tMs = 0
        for r in records {
            guard r[0] == 0x01, r.contains(where: { $0 != 0 }) else { continue }
            tMs += intervalMs

            let depthRaw = Double(be16(r, 1))
            let depthM = imperial ? depthRaw * Self.feet / 10.0 : depthRaw / 10.0

            var temp = Int(Int8(bitPattern: r[14]))
            if temp < 0 { temp = min(temp + 102, 0) }   // libdivecomputer negative-temp fix
            let tempC = imperial ? (Double(temp) - 32.0) * 5.0 / 9.0 : Double(temp)

            samples.append(DiveSample(
                timeS: tMs / 1000,
                depthM: (depthM * 100).rounded() / 100,
                tempC: (tempC * 10).rounded() / 10,
                ndlMin: Int(r[10]),
                ttsMin: be16(r, 5),
                decoStopM: be16(r, 3),
                avgPPO2: Double(r[7]) / 100.0,
                o2: Int(r[8]),
                he: Int(r[9]),
                cns: Int(r[23])
            ))
        }
        return (header, samples)
    }
}
