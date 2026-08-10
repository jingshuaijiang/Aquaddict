import SwiftUI

// Deep-ocean palette from the approved visual prototype.
enum Theme {
    static let abyss = Color(red: 0.016, green: 0.063, blue: 0.110)      // #04101C
    static let panel = Color(red: 0.039, green: 0.106, blue: 0.169)      // #0A1B2B
    static let panel2 = Color(red: 0.055, green: 0.133, blue: 0.208)     // #0E2235
    static let line = Color(red: 0.086, green: 0.196, blue: 0.290)       // #16324A
    static let ink = Color(red: 0.863, green: 0.918, blue: 0.949)        // #DCEAF2
    static let muted = Color(red: 0.431, green: 0.549, blue: 0.651)      // #6E8CA0
    static let faint = Color(red: 0.243, green: 0.353, blue: 0.439)      // #3E5A70
    static let accent = Color(red: 0.224, green: 0.824, blue: 0.910)     // #39D2E8
    static let depth = Color(red: 0.114, green: 0.616, blue: 0.710)      // #1D9DB5
    static let temp = Color(red: 0.784, green: 0.435, blue: 0.133)       // #C86F22
    static let ndl = Color(red: 0.494, green: 0.431, blue: 0.878)        // #7E6EE0
    static let pressure = Color(red: 0.455, green: 0.702, blue: 0.353)   // #74B35A
    static let danger = Color(red: 0.910, green: 0.365, blue: 0.290)     // #E85D4A
    static let good = Color(red: 0.247, green: 0.682, blue: 0.478)       // #3FAE7A
}

extension View {
    func cardStyle() -> some View {
        padding(16)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))
    }
}
