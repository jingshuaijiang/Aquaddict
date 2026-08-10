import Foundation

// Gas density and equivalent narcotic depth, as shown in the dive detail view.
// GUE guidance: gas density ideally <= 5.2 g/L (hard ceiling 6.2), END <= 30 m.

public enum GasPhysics {
    /// Gas density in g/L at depth. Molar mass of the mix over molar volume,
    /// times ambient pressure in ata (surface pressure and water density corrected).
    public static func densityGPerL(o2: Int, he: Int, depthM: Double,
                                    waterDensity: Int, surfaceMbar: Int) -> Double {
        let n2 = 100 - o2 - he
        let molarMass = (Double(o2) * 32.0 + Double(n2) * 28.0 + Double(he) * 4.0) / 100.0
        let ata = 1.0 + depthM / 10.0
            * (Double(waterDensity) / 1000.0)
            * (Double(surfaceMbar) / 1013.0)
        return molarMass / 22.4 * ata
    }

    /// Equivalent narcotic depth in meters (O2 counted as narcotic, GUE convention).
    public static func endM(depthM: Double, he: Int) -> Double {
        max(0, (depthM + 10.0) * (1.0 - Double(he) / 100.0) - 10.0)
    }
}
