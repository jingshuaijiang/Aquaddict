import Foundation

public enum DiveMode: String, Codable, Sendable {
    case cc = "CC"
    case ocTec = "OC Tec"
    case gauge = "Gauge"
    case ppo2 = "PPO2"
    case sc = "SC"
    case cc2 = "CC2"
    case ocRec = "OC Rec"
    case freedive = "Freedive"
    case avelo = "Avelo"
    case unknown = "?"

    init(rawByte: UInt8) {
        switch rawByte {
        case 0: self = .cc
        case 1: self = .ocTec
        case 2: self = .gauge
        case 3: self = .ppo2
        case 4: self = .sc
        case 5: self = .cc2
        case 6: self = .ocRec
        case 7: self = .freedive
        case 12: self = .avelo
        default: self = .unknown
        }
    }
}

public enum DecoModel: String, Codable, Sendable {
    case gf = "GF"
    case vpmb = "VPM-B"
    case vpmbGFS = "VPM-B/GFS"
    case dciem = "DCIEM"
    case unknown = "?"

    init(rawByte: UInt8) {
        switch rawByte {
        case 0: self = .gf
        case 1: self = .vpmb
        case 2: self = .vpmbGFS
        case 3: self = .dciem
        default: self = .unknown
        }
    }
}

public struct DiveHeader: Codable, Sendable, Equatable {
    public let imperial: Bool
    public let logVersion: Int
    public let intervalMs: Int
    public let gfLow: Int
    public let gfHigh: Int
    public let decoModel: DecoModel
    public let vpmbConservatism: Int?
    public let surfaceMbar: Int
    public let waterDensity: Int   // 1000 = fresh water
    public let mode: DiveMode
}

public struct DiveSample: Codable, Sendable, Equatable {
    public let timeS: Int
    public let depthM: Double
    public let tempC: Double
    public let ndlMin: Int
    public let ttsMin: Int
    public let decoStopM: Int
    public let avgPPO2: Double
    public let o2: Int
    public let he: Int
    public let cns: Int
}
