import Foundation
import SwiftUI

// App preferences + localization + unit formatting.
//
// Language follows the system setting (Chinese UI on zh-* systems, English
// otherwise). Units are a one-tap metric/imperial toggle, persisted.

@Observable
final class Prefs: @unchecked Sendable {
    static let shared = Prefs()

    var imperial: Bool {
        didSet { UserDefaults.standard.set(imperial, forKey: "imperialUnits") }
    }

    private init() {
        imperial = UserDefaults.standard.bool(forKey: "imperialUnits")
    }

    static let isChinese: Bool =
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
}

/// Pick the string for the system language.
func loc(_ zh: String, _ en: String) -> String {
    Prefs.isChinese ? zh : en
}

// MARK: unit conversion & formatting

enum U {
    static var imperial: Bool { Prefs.shared.imperial }

    static let ftPerM = 3.280839895
    static let psiPerBar = 14.5037738
    static let cuftPerL = 0.0353147

    // numbers only (for big displays)
    static func depthValue(_ m: Double) -> Double { imperial ? m * ftPerM : m }
    static func tempValue(_ c: Double) -> Double { imperial ? c * 9 / 5 + 32 : c }

    // unit labels
    static var depthUnit: String { imperial ? "ft" : "m" }
    static var tempUnit: String { imperial ? "°F" : "°C" }
    static var pressureUnit: String { imperial ? "psi" : "bar" }
    static var rateUnit: String { imperial ? "ft/min" : "m/min" }

    // formatted strings
    static func depth(_ m: Double, digits: Int = 1) -> String {
        String(format: "%.\(imperial ? 0 : digits)f %@", depthValue(m), depthUnit)
    }
    static func temp(_ c: Double) -> String {
        String(format: "%.0f%@", tempValue(c), tempUnit)
    }
    static func tempRange(_ lo: Double, _ hi: Double) -> String {
        String(format: "%.0f–%.0f%@", tempValue(lo), tempValue(hi), tempUnit)
    }
    static func pressure(_ bar: Double) -> String {
        imperial ? String(format: "%.0f psi", bar * psiPerBar)
                 : String(format: "%.0f bar", bar)
    }
    static func rate(_ mPerMin: Double) -> String {
        String(format: "%.1f %@", imperial ? mPerMin * ftPerM : mPerMin, rateUnit)
    }
    /// Volume rate (RMV in Shearwater terms) — needs a tank size.
    static func rmv(_ lPerMin: Double) -> String {
        imperial ? String(format: "%.2f ft³/min", lPerMin * cuftPerL)
                 : String(format: "%.1f L/min", lPerMin)
    }
    /// Pressure rate (SAC in Shearwater terms) — straight from the transmitter.
    static func sacPressure(_ barPerMin: Double) -> String {
        imperial ? String(format: "%.0f psi/min", barPerMin * psiPerBar)
                 : String(format: "%.2f bar/min", barPerMin)
    }
}
