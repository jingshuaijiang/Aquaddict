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
    // year for which the annual recap was already offered (0 = never)
    @AppStorage("reviewOfferedForYear") private var reviewOfferedForYear = 0
    @State private var autoReviewYear: Int?

    var body: some View {
        ZStack {
            mainTabs
            SideDrawer()
        }
    }

    private var mainTabs: some View {
        TabView {
            LogbookView()
                .tabItem { Label(loc("日志", "Log"), systemImage: "water.waves") }
            MapTabView()
                .tabItem { Label(loc("地图", "Map"), systemImage: "mappin.and.ellipse") }
        }
        .task {
            store.load()
            // first launch of a new year: replay last year's diving before the app
            let year = Calendar.current.component(.year, from: Date())
            let lastYear = year - 1
            if reviewOfferedForYear < year,
               YearStats.availableYears(dives: store.dives).contains(lastYear) {
                reviewOfferedForYear = year
                autoReviewYear = lastYear
            }
        }
        .fullScreenCover(item: $autoReviewYear) { y in
            YearReviewView(year: y, autoPresented: true)
        }
    }
}

func fmtDur(_ s: Int) -> String {
    "\(s / 60):" + String(format: "%02d", s % 60)
}
