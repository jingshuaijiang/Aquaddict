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
    @AppStorage("acceptedSafetyNotice") private var acceptedSafetyNotice = false
    @State private var autoReviewYear: Int?

    var body: some View {
        ZStack {
            mainTabs
            SideDrawer()
        }
        .fullScreenCover(isPresented: .constant(!acceptedSafetyNotice)) {
            SafetyNoticeView { acceptedSafetyNotice = true }
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

// One-time safety notice: the planner/blender/deco tools are decision aids,
// not a replacement for training or a dive computer (App Review guideline 1.4).
struct SafetyNoticeView: View {
    let accept: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.temp)
                .padding(.bottom, 18)
            Text(loc("下潜之前", "Before you dive"))
                .font(.system(size: 24, weight: .black))
                .padding(.bottom, 14)
            VStack(alignment: .leading, spacing: 12) {
                point(loc("本应用的减压计划、气体计算等工具仅供参考,不能替代正规潜水训练和认证。",
                          "The deco planner, gas tools and other calculators are aids only — they are no substitute for formal dive training and certification."))
                point(loc("请始终在你的认证范围内潜水,并以潜水电脑的实时数据为准。",
                          "Always dive within your certification and follow your dive computer in the water."))
                point(loc("水肺潜水有固有风险,使用本应用产生的任何决定由你自己负责。",
                          "Scuba diving carries inherent risk — decisions you make with this app are your own responsibility."))
            }
            .padding(.horizontal, 28)
            Spacer()
            Button(action: accept) {
                Text(loc("我已了解", "I understand"))
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.abyss)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.abyss)
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Theme.accent).frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .lineSpacing(4)
        }
    }
}
