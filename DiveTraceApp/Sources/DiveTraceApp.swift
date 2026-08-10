import SwiftUI

@main
struct DiveTraceApp: App {
    @State private var store = DiveStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(DiveStore.self) private var store

    var body: some View {
        TabView {
            LogbookView()
                .tabItem { Label(loc("日志", "Log"), systemImage: "water.waves") }
            MapTabView()
                .tabItem { Label(loc("地图", "Map"), systemImage: "mappin.and.ellipse") }
        }
        .task { store.load() }
    }
}

func fmtDur(_ s: Int) -> String {
    "\(s / 60):" + String(format: "%02d", s % 60)
}
