import SwiftUI

// App-level navigation state: the left drawer opened by tapping the brand.
@MainActor @Observable
final class AppNav {
    static let shared = AppNav()
    var drawerOpen = false
    var destination: DrawerDestination?
}

enum DrawerDestination: String, Identifiable {
    case planner, gear, records
    var id: String { rawValue }
}

// Left drawer with the tool pages that don't belong on the tab bar.
struct SideDrawer: View {
    @State private var nav = AppNav.shared

    var body: some View {
        ZStack(alignment: .leading) {
            if nav.drawerOpen {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.3)) { nav.drawerOpen = false }
                    }
                panel
                    .transition(.move(edge: .leading))
            }
        }
        .sheet(item: Binding(get: { nav.destination },
                             set: { nav.destination = $0 })) { dest in
            NavigationStack {
                switch dest {
                case .planner: PlannerContent()
                case .gear: GearView()
                case .records: RecordsView()
                }
            }
            .presentationDetents([.large])
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Aquaddict").font(.system(size: 22, weight: .black))
                Text(loc("工具箱", "TOOLS")).font(.system(size: 9, weight: .semibold))
                    .kerning(2).foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 18)

            item(loc("气体计划器", "Gas Planner"), icon: "function", dest: .planner)
            item(loc("装备管理", "Gear"), icon: "wrench.and.screwdriver.fill", dest: .gear)
            item(loc("个人纪录", "Records"), icon: "trophy.fill", dest: .records)

            Spacer()

            Text("DiveKit · Shearwater BLE\n\(loc("为自己潜，为自己记", "Dive it. Log it. Own it."))")
                .font(.system(size: 10)).foregroundStyle(Theme.faint)
                .lineSpacing(3)
        }
        .padding(EdgeInsets(top: 70, leading: 22, bottom: 40, trailing: 22))
        .frame(width: 270, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(Theme.panel2)
        .ignoresSafeArea()
    }

    private func item(_ title: String, icon: String, dest: DrawerDestination) -> some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { nav.drawerOpen = false }
            nav.destination = dest
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
                Text(title).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// PlannerView without its own NavigationStack (the sheet provides one).
struct PlannerContent: View {
    var body: some View {
        PlannerBody()
            .navigationTitle(loc("气体计划", "Gas Planner"))
    }
}
