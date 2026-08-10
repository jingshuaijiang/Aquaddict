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
                .tabItem { Label("日志", systemImage: "water.waves") }
            MapTabView()
                .tabItem { Label("地图", systemImage: "mappin.and.ellipse") }
        }
        .task { store.load() }
    }
}

func fmtDur(_ s: Int) -> String {
    "\(s / 60):" + String(format: "%02d", s % 60)
}
